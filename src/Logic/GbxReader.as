// Logic/GbxReader.as - Manual Gbx header parsing
// This version uses minimal IO features to maximize compatibility.

namespace Gbx {
    class MapHeader {
        string Uid;
        string Name;
        uint DisplayCost = 0;
        uint AuthorTime = 0;
        bool IsValidated = false;
    }

    // Treat possibly signed string bytes as uint8 (0..255).
    uint u8At(const string &in s, uint i) {
        if (int(i) >= s.Length) return 0;
        int v = s[i];
        return (v < 0) ? uint(v + 256) : uint(v);
    }

    uint u32At(const string &in s, uint i) {
        if (int(i + 3) >= s.Length) return 0;
        return u8At(s, i) | (u8At(s, i + 1) << 8) | (u8At(s, i + 2) << 16) | (u8At(s, i + 3) << 24);
    }

    int stringFind(const string &in s, const string &in sub, uint start = 0) {
        if (sub.Length == 0) return int(start);
        int sLen = int(s.Length);
        int subLen = int(sub.Length);
        for (int i = int(start); i <= sLen - subLen; i++) {
            if (s.SubStr(i, subLen) == sub) return i;
        }
        return -1;
    }

    string ExtractXmlAttr(const string &in scan, const string &in attr, const string &in parentTag = "") {
        int searchStart = 0;
        if (parentTag != "") {
            searchStart = stringFind(scan, "<" + parentTag);
            if (searchStart == -1) return "";
        }
        
        // Try double quotes first
        int start = stringFind(scan, attr + "=\"", searchStart);
        string quote = "\"";
        if (start == -1) {
            // Try single quotes
            start = stringFind(scan, attr + "='", searchStart);
            quote = "'";
        }
        
        if (start == -1) return "";
        
        // Ensure we don't bleed into next tag if parentTag was specified
        if (parentTag != "") {
            int tagClose = stringFind(scan, ">", searchStart);
            if (tagClose != -1 && start > tagClose) return "";
        }
        
        start += attr.Length + 2;
        int end = stringFind(scan, quote, start);
        if (end == -1) return "";
        return scan.SubStr(start, end - start);
    }

    MapHeader@ ReadHeader(const string &in path) {
        if (path.Length == 0) return null;
        if (!IO::FileExists(path)) return null;

        IO::File f;
        f.Open(path, IO::FileMode::Read);
        
        // Read 4KB to ensure we get the chunk table and early metadata
        auto buf = f.Read(4096);
        f.Close();

        if (buf is null || buf.GetSize() < 100) return null;
        buf.Seek(0);
        string scan = buf.ReadString(buf.GetSize());
        uint scanLen = uint(scan.Length);

        // Verify GBX signature (offset 0)
        if (scanLen < 3 || scan.SubStr(0, 3) != "GBX") return null;

        MapHeader@ h = MapHeader();
        
        // --- Strategy 1: XML Parsing (Preferred) ---
        // Specific tags to avoid ambiguity (e.g. ident.author vs times.author)
        h.Uid = ExtractXmlAttr(scan, "uid", "ident");
        if (h.Uid != "") {
            h.Name = Text::StripFormatCodes(ExtractXmlAttr(scan, "name", "ident"));
            h.DisplayCost = Text::ParseUInt(ExtractXmlAttr(scan, "displaycost", "desc"));
            
            string validatedStr = ExtractXmlAttr(scan, "validated", "desc");
            string authorTimeStr = ExtractXmlAttr(scan, "author", "times");
            if (authorTimeStr == "") authorTimeStr = ExtractXmlAttr(scan, "Author", "times");
            
            if (authorTimeStr != "") h.AuthorTime = Text::ParseUInt(authorTimeStr);
            
            h.IsValidated = (validatedStr == "1" || h.AuthorTime > 0);
            
            // Return early if we have a UID and some validation info
            if (h.Uid != "") return h;
        }

        // --- Strategy 2: Binary Chunk Parsing (Accurate Fallback) ---
        uint numChunks = u32At(scan, 17);
        uint tablePos = 21;
        uint dataPos = 21 + (numChunks * 8);

        for (uint i = 0; i < numChunks; i++) {
            uint chunkId = u32At(scan, tablePos + (i * 8));
            uint chunkSizeHeavy = u32At(scan, tablePos + (i * 8) + 4);
            uint chunkSize = chunkSizeHeavy & 0x7FFFFFFF;

            if (chunkId == 0x03043003) { // CGameCtnChallenge info
                uint pos = dataPos;
                if (pos + 128 < scanLen) {
                    uint version = u8At(scan, pos);
                    pos++;
                    
                    if (version >= 1) {
                        uint uLen = u32At(scan, pos); pos += 4 + uLen;
                        pos += 4; // ID
                        uint aLen = u32At(scan, pos); pos += 4 + aLen;
                        uint nLen = u32At(scan, pos);
                        if (h.Name == "" && pos + 4 + nLen <= scanLen) {
                            h.Name = Text::StripFormatCodes(scan.SubStr(pos + 4, nLen));
                        }
                        pos += 4 + nLen;
                    }

                    if (version >= 2 && pos < scanLen) pos++; 
                    if (version >= 3 && pos < scanLen) pos++; 
                    if (version >= 4 && pos + 3 < scanLen) pos += 4; 
                    if (version >= 5 && pos + 7 < scanLen) pos += 8; 
                    if (version >= 6 && pos + 7 < scanLen) pos += 8;
                    if (version >= 8 && pos + 3 < scanLen) pos += 4;
                    if (version >= 9 && pos + 3 < scanLen) {
                        uint cost = u32At(scan, pos);
                        if (h.DisplayCost == 0) h.DisplayCost = cost;
                    }
                }
                break;
            }
            dataPos += chunkSize;
        }

        if (h.Uid != "") return h;
        return null;
    }

    bool IsProbablyUid(const string &in s) {
        if (s.Length != 27) return false;
        for (uint i = 0; i < 27; i++) {
            int c = s[i];
            if (!((c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 45)) return false;
        }
        return true;
    }
}
