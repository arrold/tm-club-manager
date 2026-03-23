// Logic/ClubManager.as - High-level Club management coroutines (Zertrov Style)

void RefreshClubs() {
    if (State::refreshingClubs) return;
    State::refreshingClubs = true;
    State::lastClubRefresh = Time::Now;

    trace("Refreshing clubs...");
    Club[] items;

    auto resp = API::GetMyClubs(100, 0);
    if (resp !is null && resp.HasKey("clubList")) {
        auto list = resp["clubList"];
        trace("Raw API Result: " + list.Length + " clubs found.");
        for (uint i = 0; i < list.Length; i++) {
            Club c(list[i]);
            if (c.Id != 0) items.InsertLast(c);
            else trace("Club ignored due to empty ID: " + (list[i].HasKey("name") ? string(list[i]["name"]) : "unknown"));
        }
    } else {
        warn("API Response invalid or null for RefreshClubs.");
    }

    State::MyClubs = items;
    print("Loaded " + State::MyClubs.Length + " clubs.");
    State::refreshingClubs = false;
}

void RefreshActivities() {
    if (State::SelectedClub is null || State::refreshingActivities) return;
    State::refreshingActivities = true;
    uint clubId = State::SelectedClub.Id;
    
    trace("Refreshing activities for club " + clubId);
    Activity[] items;
    FetchActivitiesForStatus(clubId, true, items);
    
    string role = State::SelectedClub.Role.ToUpper();
    bool isManager = (role == "ADMIN" || role == "CREATOR" || role == "CONTENT_CREATOR");
    if (isManager) FetchActivitiesForStatus(clubId, false, items);

    if (State::SelectedClub !is null && State::SelectedClub.Id == clubId) {
        State::ClubActivities = items;
    }
    State::refreshingActivities = false;
}

void FetchActivitiesForStatus(uint clubId, bool active, Activity[]@ items) {
    auto resp = API::GetClubActivities(clubId, active, 100, 0);
    if (resp !is null && resp.HasKey("activityList")) {
        auto list = resp["activityList"];
        for (uint i = 0; i < list.Length; i++) {
            Activity a(list[i]);
            bool duplicate = false;
            for (uint j = 0; j < items.Length; j++) if (items[j].Id == a.Id) { duplicate = true; break; }
            if (!duplicate) items.InsertLast(a);
        }
    }
}

void DoCreateCampaign() {
    if (State::SelectedClub is null) return;
    API::CreateClubActivity(State::SelectedClub.Id, State::nextActivityName, "campaign");
    Notify("Campaign created.");
    startnew(RefreshActivities);
}

void DoCreateRoom() {
    if (State::SelectedClub is null) return;
    API::CreateClubActivity(State::SelectedClub.Id, State::nextActivityName, "room");
    Notify("Room created.");
    startnew(RefreshActivities);
}

void DoCreateFolder() {
    if (State::SelectedClub is null) return;
    API::CreateClubActivity(State::SelectedClub.Id, State::nextActivityName, "folder");
    Notify("Folder created.");
    startnew(RefreshActivities);
}

void DoRenameActivity(ref@ r) {
    Activity@ a = cast<Activity>(r);
    if (a is null || State::SelectedClub is null) return;
    Json::Value@ settings = Json::Object();
    settings["name"] = a.RenameBuffer;
    API::EditClubActivity(State::SelectedClub.Id, a.Id, settings);
    a.Name = a.RenameBuffer;
    a.IsRenaming = false;
    Notify("Activity renamed.");
}

void DoDeleteActivity(ref@ r) {
    Activity@ a = cast<Activity>(r);
    if (a is null || State::SelectedClub is null) return;
    Json::Value@ settings = Json::Object();
    settings["active"] = false;
    API::EditClubActivity(State::SelectedClub.Id, a.Id, settings);
    Notify("Activity deactivated/deleted.");
    startnew(RefreshActivities);
}

void DoToggleActivityActive(ref@ r) {
    Activity@ a = cast<Activity>(r);
    if (a is null || State::SelectedClub is null) return;
    Json::Value@ settings = Json::Object();
    settings["active"] = !a.Active;
    API::EditClubActivity(State::SelectedClub.Id, a.Id, settings);
    a.Active = !a.Active;
    Notify("Status updated.");
}

void DoToggleActivityPublic(ref@ r) {
    Activity@ a = cast<Activity>(r);
    if (a is null || State::SelectedClub is null) return;
    Json::Value@ settings = Json::Object();
    settings["public"] = !a.Public;
    API::EditClubActivity(State::SelectedClub.Id, a.Id, settings);
    a.Public = !a.Public;
    Notify("Privacy updated.");
}

void DoToggleActivityFeatured(ref@ r) {
    Activity@ a = cast<Activity>(r);
    if (a is null || State::SelectedClub is null) return;
    Json::Value@ settings = Json::Object();
    settings["featured"] = !a.Featured;
    API::EditClubActivity(State::SelectedClub.Id, a.Id, settings);
    a.Featured = !a.Featured;
    Notify("Featured status updated.");
}

void LoadActivityDetails(ref@ r) {
    Activity@ a = cast<Activity>(r);
    if (a is null || State::SelectedClub is null) return;
    auto resp = API::GetClubActivity(State::SelectedClub.Id, a.Id);
    if (resp !is null) {
        a.Description = resp.HasKey("description") ? string(resp["description"]) : "";
        a.NewsLoaded = true;
    }
}

void LoadActivityMaps(ref@ r) {
    Activity@ a = cast<Activity>(r);
    if (a is null || State::SelectedClub is null) return;
    
    a.LoadingMaps = true;
    a.Maps.RemoveRange(0, a.Maps.Length);
    uint clubId = State::SelectedClub.Id;
    string[] uids;

    if (a.Type == "campaign") {
        auto json = API::GetCampaignMaps(clubId, a.CampaignId);
        trace("GetCampaignMaps(" + a.CampaignId + ") raw response: " + (json is null ? "null" : Json::Write(json)));
        if (json !is null) {
            a.CampaignId = JsonGetUint(json, "campaignId", a.CampaignId);
            a.Name = Text::StripFormatCodes(JsonGetString(json, "name", a.Name));
            // Check top level, then check inside "campaign" object
            Json::Value@ list = GetMapListFromJson(json);
            if (list is null && json.HasKey("campaign")) @list = GetMapListFromJson(json["campaign"]);

            if (list !is null && list.GetType() == Json::Type::Array) {
                for (uint i = 0; i < list.Length; i++) {
                    auto item = list[i];
                    if (item.HasKey("mapUid")) {
                        uids.InsertLast(string(item["mapUid"]).Trim());
                    }
                }
            }
        }
    } else if (a.Type == "room") {
        auto json = API::GetClubRoom(clubId, a.RoomId);
        trace("GetClubRoom(" + a.RoomId + ") raw response: " + (json is null ? "null" : Json::Write(json)));
        if (json !is null) {
            // Check if this room is mirroring a campaign
            uint campaignId = 0;
            if (json.HasKey("campaignId") && json["campaignId"].GetType() == Json::Type::Number) {
                campaignId = uint(json["campaignId"]);
            } else if (json.HasKey("room") && json["room"].HasKey("campaignId") && json["room"]["campaignId"].GetType() == Json::Type::Number) {
                campaignId = uint(json["room"]["campaignId"]);
            }
            a.CampaignId = campaignId; // Update so SEVER button shows up
            
            Json::Value@ list = null;
            if (campaignId > 0) {
                trace("Room " + a.Id + " is mirroring Campaign ID " + campaignId + ". Fetching campaign maps.");
                uint campaignActivityId = 0;
                for (uint i = 0; i < State::ClubActivities.Length; i++) {
                    if (State::ClubActivities[i].Type == "campaign" && State::ClubActivities[i].CampaignId == campaignId) {
                        campaignActivityId = State::ClubActivities[i].Id;
                        a.MirroringCampaignName = State::ClubActivities[i].Name;
                        break;
                    }
                }
                if (campaignActivityId > 0) {
                    auto campJson = API::GetCampaignMaps(clubId, campaignActivityId);
                    @list = GetMapListFromJson(campJson);
                    if (list is null && campJson.HasKey("campaign")) @list = GetMapListFromJson(campJson["campaign"]);
                } else {
                    trace("Could not find campaign activity for mirroring campaignId " + campaignId);
                }
            }

            if (list is null) {
                @list = GetMapListFromJson(json);
                if (list is null && json.HasKey("room")) @list = GetMapListFromJson(json["room"]);
            }

            if (list !is null && list.GetType() == Json::Type::Array) {
                for (uint i = 0; i < list.Length; i++) {
                    auto item = list[i];
                    string uid = "";
                    if (item.GetType() == Json::Type::Object && item.HasKey("mapUid")) uid = string(item["mapUid"]).Trim();
                    else if (item.GetType() == Json::Type::String) uid = string(item).Trim();
                    
                    if (uid != "" && !uid.Contains(":error-")) uids.InsertLast(uid);
                }
            }
        }
    }

    trace("Found " + uids.Length + " map UIDs for " + a.Name);
    if (uids.Length > 0) {
        trace("Fetching metadata for " + uids.Length + " maps...");
        
        // Process in batches of 100 (API limit)
        for (uint i = 0; i < uids.Length; i += 100) {
            string[] batch;
            for (uint j = i; j < i + 100 && j < uids.Length; j++) {
                batch.InsertLast(uids[j]);
            }
            
            auto mapsJson = API::GetMapsInfo(batch);
            if (mapsJson !is null) {
                Json::Value@ list = null;
                if (mapsJson.GetType() == Json::Type::Array) @list = mapsJson;
                else if (mapsJson.HasKey("mapList")) @list = mapsJson["mapList"];

                if (list !is null) {
                    for (uint k = 0; k < list.Length; k++) {
                        a.Maps.InsertLast(MapInfo(list[k]));
                    }
                }
            }
        }

        // Important: API might return maps in different order. Reorder a.Maps to match 'uids' array.
        MapInfo[] ordered;
        for (uint i = 0; i < uids.Length; i++) {
            for (uint j = 0; j < a.Maps.Length; j++) {
                if (a.Maps[j].Uid == uids[i]) {
                    ordered.InsertLast(a.Maps[j]);
                    break;
                }
            }
        }
        a.Maps = ordered;

        // Fallback for any UIDs that didn't get metadata
        if (a.Maps.Length < uids.Length) {
            for (uint i = 0; i < uids.Length; i++) {
                bool found = false;
                for (uint j = 0; j < a.Maps.Length; j++) {
                    if (a.Maps[j].Uid == uids[i]) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    MapInfo m;
                    m.Uid = uids[i];
                    m.Name = "Unknown Map (" + uids[i] + ")";
                    m.Author = "Unknown";
                    a.Maps.InsertLast(m);
                }
            }
        }

        // Resolve author names
        string[] authorIds;
        for (uint i = 0; i < a.Maps.Length; i++) {
            if (a.Maps[i].AuthorWebServicesId != "" && authorIds.Find(a.Maps[i].AuthorWebServicesId) < 0) {
                authorIds.InsertLast(a.Maps[i].AuthorWebServicesId);
            }
        }
        
        if (authorIds.Length > 0) {
            trace("Resolving " + authorIds.Length + " author names...");
            auto resolvedNames = API::GetDisplayNames(authorIds);
            for (uint i = 0; i < a.Maps.Length; i++) {
                int idx = authorIds.Find(a.Maps[i].AuthorWebServicesId);
                if (idx >= 0 && uint(idx) < resolvedNames.Length) {
                    a.Maps[i].Author = resolvedNames[idx];
                }
            }
        }
    }

    a.MapsLoaded = true;
    a.LoadingMaps = false;
    trace("Finished loading " + a.Maps.Length + " maps for " + a.Name);
}

Json::Value@ GetMapListFromJson(Json::Value@ json) {
    if (json is null) return null;
    if (json.GetType() == Json::Type::Array) return json;
    if (json.GetType() != Json::Type::Object) return null;

    string[] keys = {"playlist", "maps", "mapList", "mapUidList", "list"};
    for (uint i = 0; i < keys.Length; i++) {
        if (json.HasKey(keys[i]) && json[keys[i]].GetType() == Json::Type::Array) return json[keys[i]];
    }

    string[] nested = {"campaign", "room", "resource"};
    for (uint i = 0; i < nested.Length; i++) {
        if (json.HasKey(nested[i]) && json[nested[i]].GetType() == Json::Type::Object) {
            auto res = GetMapListFromJson(json[nested[i]]);
            if (res !is null) return res;
        }
    }

    return null;
}

void DoSaveNews(ref@ r) {
    Activity@ a = cast<Activity>(r);
    if (a is null || State::SelectedClub is null) return;
    Json::Value@ s = Json::Object();
    s["name"] = a.Headline;
    s["description"] = a.Body;
    API::EditClubActivity(State::SelectedClub.Id, a.Id, s);
    Notify("News updated.");
}

void DoUpdateBranding(ref@ r) {
    if (State::SelectedClub is null) return;
    Json::Value@ s = Json::Object();
    s["tag"] = State::clubTag;
    s["description"] = State::clubDescription;
    s["public"] = State::clubPublic;
    API::SetClubDetails(State::SelectedClub.Id, s);
    Notify("Club branding updated.");
}

void DoAuditSubscription(ref@ r) {
    Activity@ a = cast<Activity>(r);
    if (a is null || State::SelectedClub is null) return;
    
    auto sub = Subscriptions::GetByActivity(a.Id);
    if (sub is null) return;
    
    a.IsAuditing = true;
    Notify("Auditing subscription for " + a.Name + "...");
    
    auto results = FetchMapsSequential(sub.Filters, sub.MapLimit, false);
    if (results.Length == 0) {
        Notify("Audit failed: No maps found on TMX.");
        a.IsAuditing = false;
        return;
    }
    
    string[] newUids;
    for (uint i = 0; i < results.Length; i++) newUids.InsertLast(results[i].Uid);
    
    // Check if change needed
    bool changed = (newUids.Length != a.Maps.Length);
    if (!changed) {
        for (uint i = 0; i < newUids.Length; i++) {
            if (newUids[i] != a.Maps[i].Uid) { changed = true; break; }
        }
    }
    
    if (changed) {
        Notify("Updating " + a.Name + " with " + newUids.Length + " maps...");
        ApplyBatchToActivity(a, newUids);
        startnew(LoadActivityMaps, a);
    } else {
        Notify("Subscription for " + a.Name + " is already up to date.");
    }
    
    a.IsAuditing = false;
}

class MapAction {
    Activity@ Act;
    uint Index;
    int Delta;
    MapAction(Activity@ a, uint i, int d = 0) { @Act = a; Index = i; Delta = d; }
}

void DoReorderMap(ref@ r) {
    MapAction@ action = cast<MapAction>(r);
    if (action is null || action.Act is null) return;
    
    int toIdx = int(action.Index) + action.Delta;
    if (toIdx < 0 || toIdx >= int(action.Act.Maps.Length)) return;
    
    auto m = action.Act.Maps[action.Index];
    action.Act.Maps.RemoveAt(action.Index);
    action.Act.Maps.InsertAt(toIdx, m);
    action.Act.HasMapChanges = true;
}

void DoSaveMapChanges(ref@ r) {
    Activity@ a = cast<Activity>(r);
    if (a is null || State::SelectedClub is null) return;
    
    trace("DoSaveMapChanges: committing changes for " + a.Name);
    string[] uids;
    for (uint i = 0; i < a.Maps.Length; i++) {
        if (!a.Maps[i].PendingDelete) {
            uids.InsertLast(a.Maps[i].Uid);
        }
    }
    
    ApplyBatchToActivity(a, uids);
    a.HasMapChanges = false;
    // Don't need to manually reset PendingDelete as LoadActivityMaps will refill from server
    Notify("Changes saved to " + a.Name);
    
    startnew(LoadActivityMaps, a);
}

void DoDiscardMapChanges(ref@ r) {
    Activity@ a = cast<Activity>(r);
    if (a is null) return;
    a.HasMapChanges = false;
    for (uint i = 0; i < a.Maps.Length; i++) a.Maps[i].PendingDelete = false;
    startnew(LoadActivityMaps, a); // Full sync just in case
}

void DoReorderActivity() {
    if (State::reorderIds.Length < 2 || State::SelectedClub is null) return;
    
    uint clubId = State::SelectedClub.Id;
    uint targetId = State::reorderIds[0];
    uint swapWithId = State::reorderIds[1];
    
    // Find target activity to get its folder/current position
    Activity@ target = null;
    Activity@ swapWith = null;
    for (uint i = 0; i < State::ClubActivities.Length; i++) {
        if (State::ClubActivities[i].Id == targetId) @target = State::ClubActivities[i];
        if (State::ClubActivities[i].Id == swapWithId) @swapWith = State::ClubActivities[i];
    }
    
    if (target is null || swapWith is null) return;
    
    uint targetPos = target.Position;
    uint swapPos = swapWith.Position;
    
    Json::Value@ s1 = Json::Object();
    s1["position"] = int(swapPos);
    API::EditClubActivity(clubId, targetId, s1);
    
    Json::Value@ s2 = Json::Object();
    s2["position"] = int(targetPos);
    API::EditClubActivity(clubId, swapWithId, s2);
    
    target.Position = swapPos;
    swapWith.Position = targetPos;
    
    Notify("Activity reordered.");
}
