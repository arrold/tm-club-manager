// API/TMX.as - TMX API Service (Modularized, Stable Logic from REF)

namespace TMX {
    const string TMX_FIELDS = "MapId%2CMapUid%2CName%2CUploader.Name%2CLength%2CDifficulty%2CAwardCount%2CTags%2CUploadedAt%2CHasThumbnail%2CMedals.Author%2CReplayWR.RecordTime%2CAuthorBeaten%2CServerSizeExceeded%2CEmbeddedItemsSize%2CDisplayCost";

    void Notify(const string &in msg) {
        UI::ShowNotification("Trackmania Club Manager", msg);
    }

    Json::Value@ TmxRequest(const string &in url) {
        auto req = Net::HttpRequest();
        req.Url = url;
        // User-Agent is strictly mandatory for TMX to avoid 403s
        req.Headers["User-Agent"] = "TM_Plugin:ClubManager / contact=Arrold / client_version=" + Meta::ExecutingPlugin().Version;
        req.Headers["Accept"] = "application/json";
        req.Method = Net::HttpMethod::Get;
        req.Start();
        while (!req.Finished()) yield();
        if (req.ResponseCode() >= 400) {
            warn("TMX API Error [" + req.ResponseCode() + "]:  (URL: " + url + ")");
            return null;
        }
        return req.Json();
    }

    Json::Value@ TmxSearch(const string &in params) {
        return TmxRequest("https://trackmania.exchange/api/maps?" + params);
    }

    uint GetTagIdFromName(const string &in name) {
        for (uint i = 0; i < TMX::TAG_NAMES.Length; i++) {
            if (TMX::TAG_NAMES[i] == name) return TMX::TAG_IDS[i];
        }
        return 0;
    }

    int GetSortEnumValue(int index) {
        // Stable mapping from REF API.as
        switch (index) {
            case 0:  return 12; // Awards Most
            case 1:  return 11; // Awards Least
            case 2:  return 20; // Downloads Most
            case 3:  return 10; // Activity Newest
            case 4:  return 14; // Comments Most
            case 5:  return 13; // Comments Least
            case 6:  return 15; // Difficulty Easiest
            case 7:  return 16; // Difficulty Hardest
            case 8:  return 17; // Length Shortest
            case 9:  return 18; // Length Longest
            case 10: return 1;  // Name A-Z
            case 11: return 2;  // Name Z-A
            case 12: return 30; // Online Rating Most
            case 13: return 29; // Online Rating Least
            case 14: return 6;  // Uploaded Newest
            case 15: return 5;  // Uploaded Oldest
            case 16: return 42; // Awards This Week
            case 17: return 44; // Awards This Month
        }
        return -1;
    }

    string FormatDate(const string &in d) {
        if (d == "") return "";
        auto parts = d.Split("/");
        if (parts.Length != 3) return d;
        return parts[2] + "-" + parts[1] + "-" + parts[0];
    }

    Json::Value@ SearchMaps(TmxSearchFilters@ f, uint limit = 25, uint offset = 0, uint afterId = 0) {
        string params = "fields=" + TMX_FIELDS + "&count=" + tostring(limit);
        
        // Priority filters first for TMX V1 stability
        if (f.InTOTD == 1) params += "&intotd=1";
        else if (f.InTOTD == 0) params += "&intotd=0";

        if (f.AuthorName != "") params += "&author=" + Net::UrlEncode(f.AuthorName);
        if (f.MapName != "") params += "&name=" + Net::UrlEncode(f.MapName);
        
        if (afterId > 0) params += "&after=" + tostring(afterId);
        if (offset > 0) params += "&skip=" + tostring(offset);
        
        // Optimize "Not TOTD" + "Awards Most" searches which often 500
        if (f.InTOTD == 0 && f.SortPrimary == 0) {
            params += "&awardsmin=1";
        }
        
        // Selective difficulty: TMX only supports one value. If multiple are selected, 
        // we omit it in the API and let FilterTmxResults handle it client-side.
        uint selectedDiffCount = 0;
        int singleDiffIdx = -1;
        for (uint i = 0; i < f.Difficulties.Length; i++) {
            if (f.Difficulties[i]) {
                selectedDiffCount++;
                singleDiffIdx = i;
            }
        }
        if (selectedDiffCount == 1) {
            params += "&difficulty=" + tostring(singleDiffIdx);
        }

        if (f.TimeFromMs > 0) params += "&authortimemin=" + tostring(f.TimeFromMs);
        if (f.TimeToMs > 0) params += "&authortimemax=" + tostring(f.TimeToMs);

        // Tags must be passed as individual &tag= parameters
        for (uint i = 0; i < f.IncludeTags.Length; i++) {
            uint tid = GetTagIdFromName(f.IncludeTags[i]);
            if (tid > 0) params += "&tag=" + tostring(tid);
        }
        for (uint i = 0; i < f.ExcludeTags.Length; i++) {
            uint tid = GetTagIdFromName(f.ExcludeTags[i]);
            if (tid > 0) params += "&etag=" + tostring(tid);
        }

        string dFrom = FormatDate(f.UploadedFrom);
        string dTo = FormatDate(f.UploadedTo);
        if (dFrom != "") params += "&uploadedafter=" + Net::UrlEncode(dFrom);
        if (dTo != "") params += "&uploadedbefore=" + Net::UrlEncode(dTo);

        if (f.SortPrimary >= 0) {
            int enumVal = GetSortEnumValue(f.SortPrimary);
            if (enumVal >= 0) params += "&order1=" + tostring(enumVal);
        }
        if (f.SortSecondary >= 0 && f.InTOTD != 0) {
            int enumVal = GetSortEnumValue(f.SortSecondary);
            if (enumVal >= 0) params += "&order2=" + tostring(enumVal);
        }

        if (f.InCollection >= 0 && f.InCollection != 0) {
            params += "&collection=" + tostring(f.InCollection);
        }
        
        trace("[TMX] Search Params: " + params);
        auto json = TmxSearch(params);
        if (json is null) {
            warn("[TMX] Search returned null.");
        } else if (json.GetType() != Json::Type::Array) {
            if (!(json.GetType() == Json::Type::Object && json.HasKey("Results"))) {
                warn("[TMX] Search returned unexpected object type: " + json.GetType());
            } else {
                trace("[TMX] Found " + json["Results"].Length + " maps.");
            }
        } else {
            trace("[TMX] Found " + json.Length + " maps.");
        }
        return json;
    }
    bool ArrayContains(const string[] &in arr, const string &in value) {
        for (uint i = 0; i < arr.Length; i++) {
            if (arr[i] == value) return true;
        }
        return false;
    }

    void ArrayRemove(string[]@ arr, const string &in value) {
        for (uint i = 0; i < arr.Length; i++) {
            if (arr[i] == value) {
                arr.RemoveAt(i);
                return;
            }
        }
    }
}
