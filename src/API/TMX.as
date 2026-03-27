// API/TMX.as - TMX API Service (Modularized, Stable Logic from REF)

namespace TMX {
    const string TMX_FIELDS = "MapId%2CMapUid%2CName%2CUploader.Name%2CLength%2CDifficulty%2CAwardCount%2CDownloadCount%2CTags%2CUploadedAt%2CHasThumbnail%2CMedals.Author%2CReplayWR.RecordTime%2CAuthorBeaten%2CServerSizeExceeded%2CEmbeddedItemsSize%2CDisplayCost";

    void Notify(const string &in msg) {
        UI::ShowNotification("Trackmania Club Manager", msg);
    }

    // Cache and Throttling
    uint64 lastRequestTime = 0;
    dictionary searchCache;

    void Throttle() {
        uint64 now = Time::Now;
        if (now < lastRequestTime + 500) {
            uint64 sleepTime = (lastRequestTime + 500) - now;
            // trace("[TMX] Throttling for " + sleepTime + "ms...");
            yield(int(sleepTime));
        }
        lastRequestTime = Time::Now;
    }

    Json::Value@ TmxRequest(const string &in url, bool useCache = true) {
        if (useCache && searchCache.Exists(url)) {
            // trace("[TMX] Serving from cache: " + url);
            return cast<Json::Value>(searchCache[url]);
        }

        Throttle();

        Net::HttpRequest@ req = Net::HttpRequest();
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

        Json::Value@ json = req.Json();
        if (useCache && json !is null) {
            @searchCache[url] = json;
        }
        return json;
    }

    Json::Value@ TmxSearch(const string &in params, bool useCache = true) {
        return TmxRequest("https://trackmania.exchange/api/maps?" + params, useCache);
    }

    uint GetTagIdFromName(const string &in name) {
        for (uint i = 0; i < TMX::TAG_NAMES.Length; i++) {
            if (TMX::TAG_NAMES[i] == name) return TMX::TAG_IDS[i];
        }
        return 0;
    }

    int GetSortEnumValue(int index) {
        switch (index) {
            case 0:  return 12; // Awards Most
            case 1:  return 11; // Awards Least
            case 2:  return 20; // Downloads Most
            case 3:  return 19; // Downloads Least
            case 4:  return 15; // Difficulty Easiest
            case 5:  return 16; // Difficulty Hardest
            case 6:  return 1;  // Name A-Z
            case 7:  return 2;  // Name Z-A
            case 8:  return 6;  // Uploaded Newest
            case 9:  return 5;  // Uploaded Oldest
        }
        return -1;
    }

    string FormatDate(const string &in d) {
        if (d == "") return "";
        string[] parts = d.Split("/");
        if (parts.Length != 3) return d;
        return parts[2] + "-" + parts[1] + "-" + parts[0];
    }

/*
 * Advanced TMX Search:
 * Maps the complex TmxSearchFilters into a string of URL parameters for the TMX API.
 * Handles the "Multi-State Tag Grid" logic:
 * - IncludeTags: maps that MUST have these tags.
 * - ExcludeTags: maps that MUST NOT have these tags.
 * Also implements guardrails for "Awards Most" sorting to prevent 500 errors on the TMX side.
 */
    Json::Value@ SearchMaps(TmxSearchFilters@ f, uint limit = 25, uint offset = 0, uint afterId = 0, bool useCache = true, const string &in authorOverride = "") {
        string params = "fields=" + TMX_FIELDS + "&count=" + tostring(limit);
        
        // Priority filters first for TMX V1 stability
        if (f.InTOTD == 1) params += "&intotd=1";
        else if (f.InTOTD == 0) params += "&intotd=0";

        string author = authorOverride != "" ? authorOverride : (f.AuthorNames.Length > 0 ? f.AuthorNames[0] : "");
        if (author != "") params += "&author=" + Net::UrlEncode(author);
        if (f.MapName != "") params += "&name=" + Net::UrlEncode(f.MapName);
        
        if (afterId > 0) params += "&after=" + tostring(afterId);
        if (offset > 0) params += "&skip=" + tostring(offset);
        
        // Optimize complex queries that 500 on TMX side (Pagination + Awards + Not TOTD)
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
        if (f.SortSecondary >= 0 && f.InTOTD != 0 && f.SortPrimary != 0) {
            int enumVal = GetSortEnumValue(f.SortSecondary);
            if (enumVal >= 0) params += "&order2=" + tostring(enumVal);
        }

        if (f.InCollection >= 0 && f.InCollection != 0) {
            params += "&collection=" + tostring(f.InCollection);
        }
        
        // trace("[TMX] Search Params: " + params);
        Json::Value@ json = TmxSearch(params, useCache);
        if (json is null) {
            warn("[TMX] Search returned null.");
        } else if (json.GetType() != Json::Type::Array) {
            if (!(json.GetType() == Json::Type::Object && json.HasKey("Results"))) {
                warn("[TMX] Search returned unexpected object type: " + json.GetType());
            } else {
                // trace("[TMX] Found " + json["Results"].Length + " maps.");
            }
        } else {
            // trace("[TMX] Found " + json.Length + " maps.");
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

    /* User List Endpoints */

    Json::Value@ GetFavorites(uint limit = 100, uint offset = 0) {
        return TmxRequest("https://trackmania.exchange/api/favorites/get_maps?count=" + limit + "&skip=" + offset, true);
    }

    Json::Value@ GetPlayLater(uint limit = 100, uint offset = 0) {
        return TmxRequest("https://trackmania.exchange/api/playlater/get_maps?count=" + limit + "&skip=" + offset, true);
    }

    Json::Value@ GetSetMaps(int setId, uint limit = 100, uint offset = 0) {
        return TmxRequest("https://trackmania.exchange/api/set/get_maps?id=" + setId + "&count=" + limit + "&skip=" + offset, true);
    }

    bool AddFavorite(int trackId) {
        // TMX Auth disabled. Use Local Lists.
        return false;
    }

    bool RemoveFavorite(int trackId) {
        // Functionality moved to TMX website or official plugin
        return false;
    }

    void DoAddFavorite(int64 trackId) {
        // Redirected to Local Lists
        Notify("TMX Auth disabled. Use Local Lists instead.");
    }
}
