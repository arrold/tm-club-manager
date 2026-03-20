// Club Manager - API.as

namespace API {
    /* Nadeo API Helpers */

    /* Nadeo Service Task Helpers */
    
    CWebServicesTaskResult@[] tasksToClear;

    void WaitAndClearTaskLater(CWebServicesTaskResult@ task, CMwNod@ owner) {
        while (task.IsProcessing) yield();
        tasksToClear.InsertLast(task);
    }

    void ClearTasks() {
        auto app = cast<CGameManiaPlanet>(GetApp());
        auto userMgr = app.MenuManager.MenuCustom_CurrentManiaApp.UserMgr;
        for (uint i = 0; i < tasksToClear.Length; i++) {
            userMgr.TaskResult_Release(tasksToClear[i].Id);
        }
        tasksToClear.RemoveRange(0, tasksToClear.Length);
    }

    string[]@ GetDisplayNames(const string[] &in wsids) {
        if (wsids.Length == 0) return array<string>();
        
        MwFastBuffer<wstring> list = MwFastBuffer<wstring>();
        for (uint i = 0; i < wsids.Length; i++) {
            list.Add(wstring(wsids[i]));
        }
        
        auto app = cast<CGameManiaPlanet>(GetApp());
        auto userMgr = app.MenuManager.MenuCustom_CurrentManiaApp.UserMgr;
        auto userId = userMgr.Users[0].Id;
        
        auto task = userMgr.GetDisplayName(userId, list);
        while (task.IsProcessing) yield();
        
        string[] names;
        if (task.HasSucceeded) {
            for (uint i = 0; i < wsids.Length; i++) {
                names.InsertLast(task.GetDisplayName(wsids[i]));
            }
        } else {
            warn("GetDisplayName task failed: " + task.ErrorDescription);
            for (uint i = 0; i < wsids.Length; i++) names.InsertLast("Unknown");
        }
        
        userMgr.TaskResult_Release(task.Id);
        return names;
    }

    Json::Value@ FetchLiveEndpoint(const string &in route) {
        trace("Fetching: " + route);
        auto req = NadeoServices::Get("NadeoLiveServices", route);
        req.Start();
        while(!req.Finished()) yield();
        auto json = req.Json();
        if (json is null || (json.GetType() == Json::Type::Object && json.HasKey("error"))) {
            warn("API Fetch Error: " + route + (json !is null ? " Response: " + Json::Write(json) : ""));
            return null;
        }
        return json;
    }

    Json::Value@ PostLiveEndpoint(const string &in route, Json::Value@ data) {
        trace("Posting to: " + route);
        while (!NadeoServices::IsAuthenticated("NadeoLiveServices")) yield();
        auto req = NadeoServices::Post("NadeoLiveServices", route, Json::Write(data));
        req.Start();
        while(!req.Finished()) yield();
        auto json = req.Json();
        if (json !is null && json.GetType() == Json::Type::Object && json.HasKey("error")) {
            warn("API POST Error: " + route + " Response: " + Json::Write(json));
            return null;
        }
        if (json !is null && json.GetType() == Json::Type::Array && json.Length > 0) {
            string first = string(json[0]);
            if (first.Contains(":error-")) {
                warn("API POST Error: " + route + " Response: " + Json::Write(json));
                return null;
            }
        }
        if (json is null) {
            warn("API POST Error: " + route + " (null response)");
            return null;
        }
        trace("API POST Success: " + route + " Response: " + Json::Write(json));
        return json;
    }

    /* Club & Activity Endpoints */

    Json::Value@ GetMyClubs(uint length = 100, uint offset = 0) {
        return FetchLiveEndpoint(NadeoServices::BaseURLLive() + "/api/token/club/mine?length=" + length + "&offset=" + offset);
    }

    Json::Value@ GetClubActivities(uint clubId, bool active = true, uint length = 100, uint offset = 0) {
        return FetchLiveEndpoint(NadeoServices::BaseURLLive() + "/api/token/club/" + clubId + "/activity?active=" + (active ? "true" : "false") + "&length=" + length + "&offset=" + offset);
    }

    Json::Value@ SetClubDetails(uint clubId, Json::Value@ data) {
        return PostLiveEndpoint(NadeoServices::BaseURLLive() + "/api/token/club/" + clubId + "/edit", data);
    }

    Json::Value@ CreateClubActivity(uint clubId, const string &in name, const string &in type, uint folderId = 0) {
        Json::Value@ data = Json::Object();
        data["name"] = name;
        data["activityType"] = type;
        data["folderId"] = folderId;
        data["public"] = true;
        data["active"] = true;

        string endpoint = "/folder/create";
        if (type == "campaign") endpoint = "/campaign/create";
        else if (type == "news") endpoint = "/news/create";
        else if (type == "room") endpoint = "/room/create";

        return PostLiveEndpoint(NadeoServices::BaseURLLive() + "/api/token/club/" + clubId + endpoint, data);
    }

    Json::Value@ GetCampaignMaps(uint clubId, uint campaignId) {
        return FetchLiveEndpoint(NadeoServices::BaseURLLive() + "/api/token/club/" + clubId + "/campaign/" + campaignId);
    }

    Json::Value@ SetCampaignMaps(uint clubId, uint campaignId, const string &in campaignName, string[]@ mapUids) {
        Json::Value@ playlist = Json::Array();
        for (uint i = 0; i < mapUids.Length; i++) {
            Json::Value@ entry = Json::Object();
            entry["position"] = i;
            entry["mapUid"] = mapUids[i];
            playlist.Add(entry);
        }
        Json::Value@ data = Json::Object();
        data["name"] = campaignName;
        data["playlist"] = playlist;
        return PostLiveEndpoint(NadeoServices::BaseURLLive() + "/api/token/club/" + clubId + "/campaign/" + campaignId + "/edit", data);
    }

    Json::Value@ GetClubRoom(uint clubId, uint roomId) {
        return FetchLiveEndpoint(NadeoServices::BaseURLLive() + "/api/token/club/" + clubId + "/room/" + roomId);
    }

    Json::Value@ SetRoomDetails(uint clubId, uint roomId, Json::Value@ data) {
        return PostLiveEndpoint(NadeoServices::BaseURLLive() + "/api/token/club/" + clubId + "/room/" + roomId + "/edit", data);
    }

    Json::Value@ SetRoomMaps(uint clubId, uint roomId, string[]@ mapUids) {
        auto roomJson = GetClubRoom(clubId, roomId);
        if (roomJson is null) return null;
        Json::Value@ room = roomJson.HasKey("room") ? roomJson["room"] : roomJson;
        Json::Value@ data = Json::Object();
        data["name"] = room.HasKey("name") ? room["name"] : "";
        data["script"] = room.HasKey("script") ? room["script"] : "TrackMania/TM_TimeAttack_Online.Script.txt";
        data["scalable"] = room.HasKey("scalable") ? bool(room["scalable"]) : true;
        data["maxPlayers"] = room.HasKey("maxPlayers") ? int(room["maxPlayers"]) : 32;
        data["region"] = room.HasKey("region") ? room["region"] : "eu-west";
        Json::Value@ mapsArr = Json::Array();
        for (uint i = 0; i < mapUids.Length; i++) mapsArr.Add(mapUids[i]);
        data["maps"] = mapsArr;
        if (room.HasKey("scriptSettings")) data["scriptSettings"] = room["scriptSettings"];
        return PostLiveEndpoint(NadeoServices::BaseURLLive() + "/api/token/club/" + clubId + "/room/" + roomId + "/edit", data);
    }

    Json::Value@ SetNewsDetails(uint clubId, uint activityId, const string &in name, const string &in headline, const string &in body) {
        Json::Value@ data = Json::Object();
        data["name"] = name;
        data["headline"] = headline;
        data["body"] = body;
        return PostLiveEndpoint(NadeoServices::BaseURLLive() + "/api/token/club/" + clubId + "/news/" + activityId + "/edit", data);
    }

    Json::Value@ GetMapsInfo(const string[] &in uids) {
        if (uids.Length == 0) return null;
        string uidList = string::Join(uids, ",");
        return FetchLiveEndpoint(NadeoServices::BaseURLLive() + "/api/token/map/get-multiple?mapUidList=" + uidList);
    }

    Json::Value@ RenameActivity(uint clubId, uint activityId, const string &in newName) {
        Json::Value@ data = Json::Object();
        data["name"] = newName;
        return PostLiveEndpoint(NadeoServices::BaseURLLive() + "/api/token/club/" + clubId + "/activity/" + activityId + "/edit", data);
    }

    Json::Value@ MoveActivity(uint clubId, uint activityId, uint newFolderId) {
        Json::Value@ data = Json::Object();
        data["folderId"] = newFolderId;
        return PostLiveEndpoint(NadeoServices::BaseURLLive() + "/api/token/club/" + clubId + "/activity/" + activityId + "/edit", data);
    }

    Json::Value@ ReorderActivity(uint clubId, uint activityId, uint newPosition) {
        Json::Value@ data = Json::Object();
        data["position"] = newPosition;
        return PostLiveEndpoint(NadeoServices::BaseURLLive() + "/api/token/club/" + clubId + "/activity/" + activityId + "/edit", data);
    }

    Json::Value@ GetActivity(uint clubId, uint activityId, const string &in type) {
        string subPath = type;
        if (type == "campaign") subPath = "campaign";
        else if (type == "news") subPath = "news";
        else if (type == "map-upload" || type == "skin-upload") subPath = "activity";

        string url = NadeoServices::BaseURLLive() + "/api/token/club/" + clubId + "/" + subPath + "/" + activityId;
        return FetchLiveEndpoint(url);
    }

    // Helper for Core API (different audience)
    Json::Value@ FetchCoreEndpoint(const string &in url) {
        auto req = NadeoServices::Get("NadeoServices", url);
        req.Start();
        while (!req.Finished()) yield();
        
        if (req.ResponseCode() == 200) {
            return Json::Parse(req.String());
        }
        trace("Core API Error (" + req.ResponseCode() + "): " + req.String());
        return null;
    }

    Json::Value@ SetActivityStatus(uint clubId, uint activityId, bool active) {
        Json::Value@ data = Json::Object();
        data["active"] = active;
        return PostLiveEndpoint(NadeoServices::BaseURLLive() + "/api/token/club/" + clubId + "/activity/" + activityId + "/edit", data);
    }

    Json::Value@ SetActivityPrivacy(uint clubId, uint activityId, bool isPublic) {
        Json::Value@ data = Json::Object();
        data["public"] = isPublic;
        return PostLiveEndpoint(NadeoServices::BaseURLLive() + "/api/token/club/" + clubId + "/activity/" + activityId + "/edit", data);
    }

    Json::Value@ SetActivityFeatured(uint clubId, uint activityId, bool featured) {
        Json::Value@ data = Json::Object();
        data["featured"] = featured;
        return PostLiveEndpoint(NadeoServices::BaseURLLive() + "/api/token/club/" + clubId + "/activity/" + activityId + "/edit", data);
    }

    Json::Value@ DeleteActivity(uint clubId, uint activityId) {
        return PostLiveEndpoint(NadeoServices::BaseURLLive() + "/api/token/club/" + clubId + "/activity/" + activityId + "/delete", Json::Object());
    }

    /* TMX API (Trackmania Exchange) */

    Net::HttpRequest@ TmxRequest(const string &in url) {
        auto r = Net::HttpRequest();
        r.Url = url;
        r.Headers['User-Agent'] = "TM_Plugin:ClubManager / contact=Arrold / client_version=" + Meta::ExecutingPlugin().Version;
        return r;
    }

    Json::Value@ TmxSearch(const string &in params) {
        string url = "https://trackmania.exchange/api/maps?" + params;
        trace("TMX Search URL: " + url);
        auto req = TmxRequest(url);
        req.Headers['Accept'] = "application/json";
        req.Start();
        while (!req.Finished()) yield();
        if (req.ResponseCode() >= 400) {
            warn("TMX Search Error [" + req.ResponseCode() + "]: " + req.Error());
            return null;
        }
        return req.Json();
    }

    uint GetTagIdFromName(const string &in name) {
        for (uint i = 0; i < TMX::TAG_NAMES.Length; i++) {
            if (TMX::TAG_NAMES[i] == name) return TMX::TAG_IDS[i];
        }
        return 0;
    }

    int GetSortEnumValue(int index) {
        switch (index) {
            case 0:  return 12;
            case 1:  return 11;
            case 2:  return 20;
            case 3:  return 10;
            case 4:  return 14;
            case 5:  return 13;
            case 6:  return 15;
            case 7:  return 16;
            case 8:  return 17;
            case 9:  return 18;
            case 10: return 1;
            case 11: return 2;
            case 12: return 30;
            case 13: return 29;
            case 14: return 6;
            case 15: return 5;
            case 16: return 42;
            case 17: return 44;
        }
        return -1;
    }

    string FormatDate(const string &in d) {
        if (d == "") return "";
        auto parts = d.Split("/");
        if (parts.Length != 3) return d;
        return parts[2] + "-" + parts[1] + "-" + parts[0];
    }

    const string TMX_FIELDS = "MapId%2CMapUid%2CName%2CUploader.Name%2CLength%2CDifficulty%2CAwardCount%2CTags%2CUploadedAt%2CHasThumbnail%2CMedals.Author%2CAuthorBeaten";

    Json::Value@ SearchMaps(TmxSearchFilters@ f, uint limit = 25) {
        string params = "fields=" + TMX_FIELDS + "&count=" + tostring(limit);
        int afterId = 0;
        if (f.CurrentPage > 1 && f.CurrentPage <= int(f.PageStartingIds.Length)) {
            afterId = f.PageStartingIds[f.CurrentPage - 1];
        }
        if (afterId > 0) params += "&after=" + tostring(afterId);
        // else if (f.Offset > 0) params += "&offset=" + tostring(f.Offset);

        if (f.AuthorName != "") params += "&author=" + Net::UrlEncode(f.AuthorName);

        if (f.Vehicle >= 0 && f.Vehicle < int(TMX::VEHICLE_NAMES.Length))
            params += "&vehicle=" + Net::UrlEncode(TMX::VEHICLE_NAMES[f.Vehicle]);

        if (f.Difficulty >= 0) params += "&difficulty=" + tostring(f.Difficulty);
        if (f.TimeFromMs > 0) params += "&authortimemin=" + tostring(f.TimeFromMs);
        if (f.TimeToMs > 0) params += "&authortimemax=" + tostring(f.TimeToMs);

        for (uint i = 0; i < f.IncludeTags.Length; i++)
            params += "&tag=" + tostring(GetTagIdFromName(f.IncludeTags[i]));
        for (uint i = 0; i < f.ExcludeTags.Length; i++)
            params += "&etag=" + tostring(GetTagIdFromName(f.ExcludeTags[i]));

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

        // Workaround for TMX 500 error with intotd=0 (Not TOTD)
        // Adding an empty or dummy etag parameter often bypasses this bug.
        if (!params.Contains("&etag=")) params += "&etag=";

        trace("Final TMX Search Params: " + params);
        auto json = TmxSearch(params);
        if (json !is null) {
            trace("TMX Search response, result count: " + (json.HasKey("Results") ? tostring(json["Results"].Length) : "unknown"));
        }
        return json;
    }
}
