// Logic/GbxReader.as - Manual Gbx header parsing (Zertrov Style)
// This version uses minimal IO features to maximize compatibility.

namespace Gbx {
    class MapHeader {
        string Uid;
        string Name;
    }

    // Treat possibly signed string bytes as uint8 (0..255).
    uint u8At(const string &in s, uint i) {
        int v = s[i];
        return (v < 0) ? uint(v + 256) : uint(v);
    }

    MapHeader@ ReadHeader(const string &in path) {
        if (path.Length == 0) return null;
        if (!IO::FileExists(path)) return null;

        // OpenPlanet's IO::File.Open returns `void`, and IO::File.Read returns MemoryBuffer.
        // To avoid missing ReadUint8()/buffer APIs across versions, we parse using bytes from a string.
        IO::File f;
        f.Open(path, IO::FileMode::Read);

        uint64 size64 = f.Size();
        uint readSize = 16384;
        if (size64 < readSize) readSize = uint(size64);

        // ReadToEnd reads the remaining file; we then slice to readSize to keep work bounded.
        string data = f.ReadToEnd();
        f.Close();

        if (data.Length < 100) return null;

        // Limit parsing to the first readSize bytes (header area).
        uint scanLenU = readSize;
        if (uint(data.Length) < scanLenU) scanLenU = uint(data.Length);
        string scan = data.SubStr(0, int(scanLenU));

        // #region agent log
        DebugLog("post-fix-1", "H1", "GbxReader.as:ReadHeader", "Read GBX bytes", "{\"dataLen\":" + tostring(data.Length) + ",\"scanLen\":" + tostring(scan.Length) + "}");
        // #endregion

        // Verify GBX signature.
        if (scan.Length < 3) return null;
        if (scan.SubStr(0, 3) != "GBX") return null;

        uint targetChunk = 0x03043002;
        bool found = false;

        // The chunk ID is usually in the first bytes (chunk table).
        for (uint i = 0; i < 500; i++) {
            if (scan.Length < i + 4) break;

            uint c1 = u8At(scan, i);
            uint c2 = u8At(scan, i + 1);
            uint c3 = u8At(scan, i + 2);
            uint c4 = u8At(scan, i + 3);
            uint chunkId = c1 | (c2 << 8) | (c3 << 16) | (c4 << 24);

            if (chunkId == targetChunk) {
                found = true;
                break;
            }
        }

        if (!found) return null;

        // Scan for the UID length prefix 27 (0x1B 00 00 00) and then a 27-byte UID string.
        for (uint i = 20; i + 32 <= scan.Length; i++) {
            if (u8At(scan, i) == 0x1B && u8At(scan, i + 1) == 0x00 && u8At(scan, i + 2) == 0x00 && u8At(scan, i + 3) == 0x00) {
                string uid = scan.SubStr(i + 4, 27);
                if (!IsProbablyUid(uid)) continue;

                MapHeader h;
                h.Uid = uid;

                // Name format:
                // - Try 1-byte length immediately after UID.
                uint nameLen = u8At(scan, i + 4 + 27);
                if (nameLen > 0 && nameLen < 200 && (i + 4 + 27 + 1 + nameLen) <= scan.Length) {
                    string nameRaw = scan.SubStr(i + 4 + 27 + 1, int(nameLen));
                    h.Name = Text::StripFormatCodes(nameRaw);
                } else {
                    // - Try 4-byte length (we currently only need the first 2 bytes like the old parser).
                    if ((i + 4 + 27 + 4) <= scan.Length) {
                        uint nameLen4 = u8At(scan, i + 4 + 27) | (u8At(scan, i + 4 + 27 + 1) << 8);
                        if (nameLen4 > 0 && nameLen4 < 500 && (i + 4 + 27 + 4 + nameLen4) <= scan.Length) {
                            string nameRaw = scan.SubStr(i + 4 + 27 + 4, int(nameLen4));
                            h.Name = Text::StripFormatCodes(nameRaw);
                        }
                    }
                }

                if (h.Name == "") h.Name = "Unknown Map";

                // #region agent log
                DebugLog("post-fix-1", "H2", "GbxReader.as:ReadHeader", "Extracted UID/name", "{\"uidLen\":27,\"uidFound\":1,\"nameLen\":" + tostring(h.Name.Length) + "}");
                // #endregion

                return h;
            }
        }

        // #region agent log
        DebugLog("post-fix-1", "H3", "GbxReader.as:ReadHeader", "Did not find UID", "{\"scanLen\":" + tostring(scan.Length) + "}");
        // #endregion

        return null;
    }

    // Writes NDJSON into `debug-d1d6a7.log` so we can correlate runtime evidence with hypotheses.
    void DebugLog(const string &in runId, const string &in hypothesisId, const string &in location, const string &in message, const string &in dataJson) {
        // #region agent log
        IO::File logFile;
        logFile.Open("c:/Users/simon/repos/tm/plugins/tm-club-manager/debug-d1d6a7.log", IO::FileMode::Append);

        uint64 ts = Time::Now;
        string line = "{\"sessionId\":\"d1d6a7\",\"runId\":\"" + runId +
            "\",\"hypothesisId\":\"" + hypothesisId +
            "\",\"location\":\"" + location +
            "\",\"message\":\"" + message +
            "\",\"data\":" + dataJson +
            ",\"timestamp\":" + tostring(ts) + "}";

        logFile.WriteLine(line);
        logFile.Close();
        // #endregion
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
