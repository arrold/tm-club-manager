// API/Nadeo.as - Nadeo Live Services endpoints

namespace API {
    /* User & Display Names */

    string[]@ GetDisplayNames(const string[] &in wsids) {
        if (wsids.Length == 0) return array<string>();
        
        MwFastBuffer<wstring> list = MwFastBuffer<wstring>();
        for (uint i = 0; i < wsids.Length; i++) {
            list.Add(wstring(wsids[i]));
        }
        
        CGameManiaPlanet@ app = cast<CGameManiaPlanet>(GetApp());
        if (app.MenuManager is null || app.MenuManager.MenuCustom_CurrentManiaApp is null) return array<string>();
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

    /* HTTP Helpers */

    Json::Value@ FetchLiveEndpoint(const string &in route) {
        // trace("Fetching: " + route);
        Net::HttpRequest@ req = NadeoServices::Get("NadeoLiveServices", route);
        req.Start();
        while (!req.Finished()) yield();
        Json::Value@ json = req.Json();
        if (json is null || (json.GetType() == Json::Type::Object && json.HasKey("error"))) {
            warn("API Fetch Error: " + route + (json !is null ? " Response: " + Json::Write(json) : ""));
            return null;
        }
        return json;
    }

    Json::Value@ PostLiveEndpoint(const string &in route, Json::Value@ data) {
        // trace("Posting to: " + route);
        while (!NadeoServices::IsAuthenticated("NadeoLiveServices")) yield();
        Net::HttpRequest@ req = NadeoServices::Post("NadeoLiveServices", route, Json::Write(data));
        req.Start();
        while (!req.Finished()) yield();
        Json::Value@ json = req.Json();
        if (json !is null && json.GetType() == Json::Type::Object && json.HasKey("error")) {
            warn("API POST Error: " + route + " Response: " + Json::Write(json));
            return null;
        }
        if (json is null) {
            warn("API POST Error: " + route + " (null response)");
            return null;
        }
        // trace("API POST Success: " + route + " Response: " + Json::Write(json));
        return json;
    }

    /* Club & Activity Endpoints */

    Json::Value@ GetMyClubs(uint length = 100, uint offset = 0) {
        return FetchLiveEndpoint(NadeoServices::BaseURLLive() + "/api/token/club/mine?length=" + length + "&offset=" + offset);
    }

    Json::Value@ GetClubActivities(uint clubId, bool active = true, uint length = 100, uint offset = 0) {
        return FetchLiveEndpoint(NadeoServices::BaseURLLive() + "/api/token/club/" + clubId + "/activity?active=" + (active ? "true" : "false") + "&length=" + length + "&offset=" + offset);
    }

    Json::Value@ GetClubActivity(uint clubId, uint activityId) {
        return FetchLiveEndpoint(NadeoServices::BaseURLLive() + "/api/token/club/" + clubId + "/activity/" + activityId);
    }

    Json::Value@ GetClubDetails(uint clubId) {
        return FetchLiveEndpoint(NadeoServices::BaseURLLive() + "/api/token/club/" + clubId);
    }

    Json::Value@ SetClubDetails(uint clubId, Json::Value@ data) {
        return PostLiveEndpoint(NadeoServices::BaseURLLive() + "/api/token/club/" + clubId + "/edit", data);
    }

    Json::Value@ CreateClubActivity(uint clubId, const string &in name, const string &in type, uint folderId = 0, bool active = true, uint campaignId = 0) {
        Json::Value@ data = Json::Object();
        data["name"] = name;
        data["activityType"] = type;
        data["folderId"] = folderId;
        data["public"] = true;
        data["active"] = active;

        string endpoint = "/folder/create";
        if (type == "campaign") endpoint = "/campaign/create";
        else if (type == "news") endpoint = "/news/create";
        else if (type == "room") {
            endpoint = "/room/create";
            data["region"] = "eu-west";
            data["maxPlayersPerServer"] = 32;
            data["script"] = "TrackMania/TM_TimeAttack_Online.Script.txt";
            data["settings"] = Json::Array();
            data["password"] = 0;
            data["scalable"] = 1;
            
            if (campaignId > 0) {
                data["campaignId"] = int(campaignId);
                // Payload Sanitisation: Omit 'maps' for mirrored rooms as per API requirements
            } else {
                data["maps"] = Json::Array();
            }
        }

        // trace("CreateClubActivity Payload: " + Json::Write(data));
        return PostLiveEndpoint(NadeoServices::BaseURLLive() + "/api/token/club/" + clubId + endpoint, data);
    }

    Json::Value@ EditClubActivity(uint clubId, uint activityId, Json::Value@ data) {
        return PostLiveEndpoint(NadeoServices::BaseURLLive() + "/api/token/club/" + clubId + "/activity/" + activityId + "/edit", data);
    }

    Json::Value@ MoveActivity(uint clubId, uint activityId, uint newFolderId) {
        Json::Value@ data = Json::Object();
        data["folderId"] = newFolderId;
        return PostLiveEndpoint(NadeoServices::BaseURLLive() + "/api/token/club/" + clubId + "/activity/" + activityId + "/edit", data);
    }

    Json::Value@ DeleteActivity(uint clubId, uint activityId) {
        return PostLiveEndpoint(NadeoServices::BaseURLLive() + "/api/token/club/" + clubId + "/activity/" + activityId + "/delete", Json::Object());
    }

    Json::Value@ SetActivityDetails(uint clubId, uint activityId, const string &in name, bool isPublic, uint itemsCount) {
        Json::Value@ data = Json::Object();
        data["name"] = name;
        data["public"] = isPublic;
        data["itemsCount"] = int(itemsCount);
        return PostLiveEndpoint(NadeoServices::BaseURLLive() + "/api/token/club/" + clubId + "/activity/" + activityId + "/edit", data);
    }

    Json::Value@ SetActivityStatus(uint clubId, uint activityId, bool active) {
        Json::Value@ data = Json::Object();
        data["active"] = active;
        return PostLiveEndpoint(NadeoServices::BaseURLLive() + "/api/token/club/" + clubId + "/activity/" + activityId + "/edit", data);
    }

    /* Campaign Endpoints */

    Json::Value@ GetCampaignMaps(uint clubId, uint campaignId) {
        return FetchLiveEndpoint(NadeoServices::BaseURLLive() + "/api/token/club/" + clubId + "/campaign/" + campaignId);
    }

    Json::Value@ SetCampaignMaps(uint clubId, uint campaignId, const string &in campaignName, string[]@ mapUids, Json::Value@ current = null) {
        Json::Value@ playlist = Json::Array();
        for (uint i = 0; i < mapUids.Length; i++) {
            Json::Value@ entry = Json::Object();
            entry["position"] = i;
            entry["mapUid"] = mapUids[i];
            playlist.Add(entry);
        }

        Json::Value@ cats = null;
        if (current !is null) {
            if (current.HasKey("categories") && current["categories"].GetType() == Json::Type::Array) {
                @cats = current["categories"];
            } else if (current.HasKey("campaign") && current["campaign"].HasKey("categories") && current["campaign"]["categories"].GetType() == Json::Type::Array) {
                @cats = current["campaign"]["categories"];
            }
        }

        Json::Value@ data = Json::Object();
        data["name"] = campaignName;
        data["playlist"] = playlist;
        data["published"] = true;

        if (cats !is null && cats.Length > 0) {
            Json::Value@ newCats = Json::Array();
            for (uint i = 0; i < cats.Length; i++) {
                Json::Value@ c = Json::Object();
                c["name"] = cats[i]["name"];
                c["position"] = cats[i]["position"];
                c["length"] = (cats.Length == 1) ? int(mapUids.Length) : int(cats[i]["length"]);
                newCats.Add(c);
            }
            data["categories"] = newCats;
        } else {
            // Fallback for new campaigns or missing category data
            Json::Value@ c = Json::Object();
            c["name"] = campaignName;
            c["position"] = 0;
            c["length"] = int(mapUids.Length);
            Json::Value@ newCats = Json::Array();
            newCats.Add(c);
            data["categories"] = newCats;
        }

        // trace("SetCampaignMaps: Updating campaign " + campaignId + " with " + mapUids.Length + " maps. UIDs: " + string::Join(mapUids, ", "));
        return PostLiveEndpoint(NadeoServices::BaseURLLive() + "/api/token/club/" + clubId + "/campaign/" + campaignId + "/edit", data);
    }

    /* Room Endpoints */

    Json::Value@ GetClubRoom(uint clubId, uint roomId) {
        return FetchLiveEndpoint(NadeoServices::BaseURLLive() + "/api/token/club/" + clubId + "/room/" + roomId);
    }

    Json::Value@ SetRoomMaps(uint clubId, uint activityId, string[]@ mapUids) {
        auto@ roomJson = GetClubRoom(clubId, activityId);
        if (roomJson is null) return null;
        Json::Value@ data = PrepareRoomPayload(roomJson);
        
        Json::Value@ mapsArr = Json::Array();
        for (uint i = 0; i < mapUids.Length; i++) mapsArr.Add(mapUids[i]);
        data["maps"] = mapsArr;

        return PostLiveEndpoint(NadeoServices::BaseURLLive() + "/api/token/club/" + clubId + "/room/" + activityId + "/edit", data);
    }

    Json::Value@ PrepareRoomPayload(Json::Value@ roomJson) {
        Json::Value@ room = roomJson.HasKey("room") ? roomJson["room"] : roomJson;
        Json::Value@ data = Json::Object();
        data["name"] = room.HasKey("name") ? string(room["name"]) : "";
        data["script"] = room.HasKey("script") ? string(room["script"]) : "TrackMania/TM_TimeAttack_Online.Script.txt";
        data["scalable"] = room.HasKey("scalable") ? (bool(room["scalable"]) ? 1 : 0) : 1;
        data["maxPlayersPerServer"] = room.HasKey("maxPlayers") ? int(room["maxPlayers"]) : 32;
        data["region"] = room.HasKey("region") ? string(room["region"]) : "eu-west";
        data["password"] = room.HasKey("password") ? (bool(room["password"]) ? 1 : 0) : 0;
        
        if (room.HasKey("campaignId")) data["campaignId"] = JsonGetUint(room, "campaignId");

        if (room.HasKey("maps") && room["maps"].GetType() == Json::Type::Array) {
            data["maps"] = room["maps"];
        } else {
            data["maps"] = Json::Array();
        }
        
        Json::Value@ settingsArr = Json::Array();
        if (room.HasKey("scriptSettings") && room["scriptSettings"].GetType() == Json::Type::Object) {
            Json::Value@ s = room["scriptSettings"];
            string[]@ keys = s.GetKeys();
            for (uint i = 0; i < keys.Length; i++) {
                settingsArr.Add(s[keys[i]]);
            }
        }
        data["settings"] = settingsArr;
        return data;
    }

    /* Map Info Endpoints */

    Json::Value@ GetMapsInfo(const string[] &in uids) {
        if (uids.Length == 0) return null;
        string uidList = string::Join(uids, ",");
        return FetchLiveEndpoint(NadeoServices::BaseURLLive() + "/api/token/map/get-multiple?mapUidList=" + uidList);
    }
}
