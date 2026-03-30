// API/TMX.as - TMX API Service (Modularized, Stable Logic from REF)

namespace TMX {
    const string TMX_FIELDS = "MapId%2CMapUid%2CName%2CUploader.Name%2CAuthors%5B%5D%2CLength%2CDifficulty%2CAwardCount%2CTags%2CUploadedAt%2CHasThumbnail%2CMedals.Author";

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
            return cast<Json::Value>(searchCache[url]);
        }
        Throttle();
        Net::HttpRequest@ req = Net::HttpRequest();
        req.Url = url;
        req.Headers["User-Agent"] = "TM_Plugin:ClubManager / contact=Arrold";
        req.Headers["Accept"] = "application/json";
        trace("[TMX] Requesting: " + url);
        req.Method = Net::HttpMethod::Get;
        req.Start();
        uint64 start = Time::Now;
        while (!req.Finished()) {
            if (Time::Now > start + 30000) {
                req.Cancel();
                warn("[TMX] Request Timeout (30s): " + url);
                return null; 
            }
            yield();
        }
        if (req.ResponseCode() >= 400) {
            warn("TMX Error [" + req.ResponseCode() + "]. Body: " + req.String().SubStr(0, 100));
            return null;
        }

        string body = req.String();
        // trace("[TMX] Response length: " + body.Length);
        Json::Value@ json = req.Json();
        if (json is null) {
            warn("TMX API Error: Failed to parse JSON. Body Start: " + body.SubStr(0, 100));
            return null;
        }
        if (useCache) { @searchCache[url] = json; }
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
            case 2:  return 5;  // Uploaded Oldest
            case 3:  return 20; // Downloads Most
            case 4:  return 19; // Downloads Least
            case 5:  return 6;  // Uploaded Newest
            case 6:  return 15; // Difficulty Easiest
            case 7:  return 16; // Difficulty Hardest
            case 8:  return 1;  // Name A-Z
            case 9:  return 2;  // Name Z-A
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
    Json::Value@ SearchMaps(TmxSearchFilters@ f, uint limit = 25, uint offset = 0, uint afterId = 0, bool useCache = true, const string &in authorOverride = "", int authorId = -1) {
        string params = "fields=" + TMX_FIELDS + "&count=" + tostring(limit);
        
        // Priority filters first for TMX V1 stability
        if (f.InTOTD == 1) params += "&intotd=1";
        else if (f.InTOTD == 0) params += "&intotd=0";

        if (authorId > 0) {
            params += "&authoruserid=" + tostring(authorId);
            // Universal Search: anyauthor=1 ensures collaborators are included
            params += "&anyauthor=1";
        } else if (authorOverride != "" || f.AuthorNames.Length > 0) {
            string author = authorOverride != "" ? authorOverride : f.AuthorNames[0];
            params += "&author=" + Net::UrlEncode(author);
            params += "&anyauthor=1";
        }
        
        if (f.MapName != "") params += "&name=" + Net::UrlEncode(f.MapName);
        
        if (afterId > 0) params += "&after=" + tostring(afterId);
        if (offset > 0) params += "&skip=" + tostring(offset);
        
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
        
        trace("[TMX] Search Params: " + params);
        Json::Value@ json = TmxSearch(params, useCache);
        if (json is null) {
            warn("[TMX] Search returned null.");
        } else {
            uint count = 0;
            if (json.GetType() == Json::Type::Array) count = json.Length;
            else if (json.GetType() == Json::Type::Object && json.HasKey("Results")) count = json["Results"].Length;
            trace("[TMX] Search completed. Found " + count + " entries.");
            
            if (count > 0) {
                Json::Value@ first;
                if (json.GetType() == Json::Type::Array) @first = json[0];
                else if (json.GetType() == Json::Type::Object && json.HasKey("Results")) @first = json["Results"][0];
                
                if (first !is null && first.GetType() == Json::Type::Object) {
                    string name = first.HasKey("Name") ? string(first["Name"]) : "Unknown";
                    string uploader = (first.HasKey("Uploader") && first["Uploader"].HasKey("Name")) ? string(first["Uploader"]["Name"]) : "Unknown";
                    string authorList = "";
                    if (first.HasKey("Authors") && first["Authors"].GetType() == Json::Type::Array) {
                        for (uint j = 0; j < first["Authors"].Length && j < 5; j++) {
                            Json::Value@ a = first["Authors"][j];
                            if (a.GetType() == Json::Type::Object) {
                                if (a.HasKey("User") && a["User"].HasKey("Name")) {
                                    authorList += string(a["User"]["Name"]) + ", ";
                                } else if (a.HasKey("Name")) {
                                    authorList += string(a["Name"]) + ", ";
                                }
                            }
                        }
                    }
                    trace("[TMX] Sample: " + name + " | Uploader: " + uploader + " | Authors: " + authorList);
                }
            }
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

    /* User Resolution */
    int GetUserId(const string &in username) {
        if (username == "") return -1;
        string url = "https://trackmania.exchange/api/user/search?query=" + Net::UrlEncode(username);
        trace("[TMX] Resolving user via: " + url);
        Json::Value@ json = TmxRequest(url, true);
        if (json is null) return -1;

        Json::Value@ results = null;
        if (json.GetType() == Json::Type::Array) {
            @results = json;
        } else if (json.GetType() == Json::Type::Object && json.HasKey("results")) {
            @results = json["results"];
        }

        if (results is null || results.GetType() != Json::Type::Array || results.Length == 0) {
            warn("[TMX] Failed to resolve UserId for: " + username);
            return -1;
        }
        
        Json::Value@ first = results[0];
        int id = -1;
        if (first.HasKey("id")) id = int(first["id"]);
        else if (first.HasKey("UserID")) id = int(first["UserID"]);

        if (id <= 0) {
            warn("[TMX] Resolved user but missing UserId field.");
            return -1;
        }

        trace("[TMX] Resolved username '" + username + "' to UserId: " + id);
        return id;
    }
}
