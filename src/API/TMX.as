// API/TMX.as - Trackmania Exchange API (Zertrov Style)

namespace TMX {
    void ThrottleTMX() {
        sleep(250); 
    }

    Json::Value@ TmxRequest(const string &in url) {
        ThrottleTMX();
        Net::HttpRequest req;
        req.Method = Net::HttpMethod::Get;
        req.Url = url;
        req.Headers['User-Agent'] = "TM_Plugin:BetterClubManager / contact=Arrold / client_version=" + Meta::ExecutingPlugin().Version;
        req.Headers['Accept'] = "application/json";
        req.Start();
        while (!req.Finished()) yield();
        if (req.ResponseCode() >= 400) {
            warn("TMX API Error [" + req.ResponseCode() + "]: " + req.Error() + " (URL: " + url + ")");
            return null;
        }
        return req.Json();
    }

    Json::Value@ TmxSearch(const string &in params) {
        return TmxRequest("https://trackmania.exchange/api/maps?" + params);
    }

    uint GetTagIdFromName(const string &in name) {
        string cleaned = name.Trim().ToLower();
        for (uint i = 0; i < TMX::TAG_NAMES.Length; i++) {
            if (TMX::TAG_NAMES[i].ToLower() == cleaned) return TMX::TAG_IDS[i];
        }
        return 0;
    }

    int GetSortEnumValue(int index) {
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
        if (d == "" || d.Contains("-")) return d;
        auto parts = d.Split("/");
        if (parts.Length != 3) return d;
        return parts[2] + "-" + parts[1] + "-" + parts[0];
    }

    const string TMX_FIELDS = "MapId%2CMapUid%2CName%2CUploader.Name%2CLength%2CDifficulty%2CAwardCount%2CTags%2CUploadedAt%2CHasThumbnail%2CMedals.Author";

    Json::Value@ SearchMaps(TmxSearchFilters@ f, uint limit = 25) {
        string params = "fields=" + TMX_FIELDS + "&count=" + tostring(limit);
        
        int afterId = 0;
        if (f.CurrentPage > 1 && f.CurrentPage <= int(f.PageStartingTrackIds.Length)) {
            afterId = f.PageStartingTrackIds[f.CurrentPage - 1];
        }
        if (afterId > 0) params += "&after=" + afterId;

        if (f.AuthorName != "") params += "&author=" + Net::UrlEncode(f.AuthorName);

        if (f.Vehicle >= 0 && f.Vehicle < int(TMX::VEHICLE_NAMES.Length))
            params += "&vehicle=" + Net::UrlEncode(TMX::VEHICLE_NAMES[f.Vehicle]);

        // Difficulty: trying 1-6 range (Beginner=1)
        for (uint i = 0; i < f.Difficulties.Length; i++) {
            if (f.Difficulties[i]) {
                params += "&difficulty=" + (i + 1);
            }
        }

        if (f.TimeFromMs > 0) params += "&authortimemin=" + tostring(f.TimeFromMs);
        if (f.TimeToMs > 0) params += "&authortimemax=" + tostring(f.TimeToMs);

        // Tags
        for (uint i = 0; i < f.IncludeTags.Length; i++) {
            uint tid = GetTagIdFromName(f.IncludeTags[i]);
            if (tid > 0) params += "&tag=" + tid;
        }
        for (uint i = 0; i < f.ExcludeTags.Length; i++) {
            uint tid = GetTagIdFromName(f.ExcludeTags[i]);
            if (tid > 0) params += "&etag=" + tid;
        }

        if (f.PrimaryTagOnly) params += "&pri=1";
        if (f.PrimarySurfaceOnly) params += "&psu=1";

        string dFrom = FormatDate(f.UploadedFrom);
        string dTo = FormatDate(f.UploadedTo);
        if (dFrom != "") params += "&uploadedafter=" + Net::UrlEncode(dFrom);
        if (dTo != "") params += "&uploadedbefore=" + Net::UrlEncode(dTo);

        if (f.SortPrimary >= 0) {
            int enumVal = GetSortEnumValue(f.SortPrimary);
            if (enumVal >= 0) params += "&order1=" + tostring(enumVal);
        }
        if (f.SortSecondary >= 0) {
            int enumVal = GetSortEnumValue(f.SortSecondary);
            if (enumVal >= 0) params += "&order2=" + tostring(enumVal);
        }

        if (f.InTOTD >= 0) params += "&intotd=" + tostring(f.InTOTD);
        if (f.InOnlineRecords >= 0) params += "&inonlinerecords=" + tostring(f.InOnlineRecords);

        return TmxSearch(params);
    }
}
