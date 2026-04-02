// Logic/ClubManager.as - High-level Club management coroutines

void RefreshClubs() {
    if (State::refreshingClubs) return;
    State::refreshingClubs = true;
    State::lastClubRefresh = Time::Now;

    // trace("Refreshing clubs...");
    Club@[] items;

    Json::Value@ resp = API::GetMyClubs(100, 0);
    if (resp !is null && resp.HasKey("clubList")) {
        Json::Value@ list = resp["clubList"];
        // trace("Raw API Result: " + list.Length + " clubs found.");
        for (uint i = 0; i < list.Length; i++) {
            Club@ c = Club(list[i]);
            if (c.Id != 0) items.InsertLast(c);
        }
    } else {
        warn("API Response invalid or null for RefreshClubs.");
    }

    State::MyClubs = items;
    // print("Loaded " + State::MyClubs.Length + " clubs.");
    State::refreshingClubs = false;
}

void RefreshActivities() {
    if (State::SelectedClub is null || State::refreshingActivities) return;
    State::refreshingActivities = true;
    uint clubId = State::SelectedClub.Id;
    
    // trace("Refreshing activities for club " + clubId);
    Activity@[] items;
    FetchActivitiesForStatus(clubId, true, items);
    
    string role = State::SelectedClub.Role.ToUpper();
    bool isManager = (role == "ADMIN" || role == "CREATOR" || role == "CONTENT_CREATOR");
    if (isManager) FetchActivitiesForStatus(clubId, false, items);

    if (State::SelectedClub !is null && State::SelectedClub.Id == clubId) {
        State::ClubActivities = items;
        startnew(RefreshActiveActivities);
    }
    State::refreshingActivities = false;
}

/* 
 * Eager Metadata Loading:
 * Prevents "Zero-State" UI flicker by background-loading map counts for all Active
 * items immediately upon club selection. This also ensures mirrored rooms correctly
 * inherit their parent campaign's metadata from the start.
 */
void RefreshActiveActivities() {
    if (State::SelectedClub is null) return;
    State::isInitialised = true;
    
    uint[] toFetch;
    Activity@[]@ items = State::ClubActivities;
    for (uint i = 0; i < items.Length; i++) {
        Activity@ a = items[i];
        if (a.Type == "folder" || a.Type == "news") continue;
        
        // Eager load if active
        if (a.Active) {
            if (toFetch.Find(a.Id) < 0) toFetch.InsertLast(a.Id);
        }
        
        // Eager load parent campaign for mirrored rooms (even if parent is inactive)
        if (a.Type == "room" && a.MirrorCampaignId > 0) {
            for (uint j = 0; j < items.Length; j++) {
                if (items[j].Type == "campaign" && items[j].CampaignId == a.MirrorCampaignId) {
                    if (toFetch.Find(items[j].Id) < 0) toFetch.InsertLast(items[j].Id);
                    break;
                }
            }
        }
    }
    
    if (toFetch.Length > 0) {
        startnew(RunEagerMetadataFetch, toFetch);
    }
}

void RunEagerMetadataFetch(ref@ r) {
    uint[]@ ids = cast<uint[]>(r);
    if (ids is null || State::SelectedClub is null) return;
    
    for (uint i = 0; i < ids.Length; i++) {
        // Find activity in current state (selection may have changed since start)
        Activity@ a = null;
        for (uint j = 0; j < State::ClubActivities.Length; j++) {
            if (State::ClubActivities[j].Id == ids[i]) {
                @a = State::ClubActivities[j];
                break;
            }
        }
        
        if (a !is null && !a.MapsLoaded && !a.LoadingMaps) {
            startnew(LoadActivityMaps, a);
            sleep(100); // Throttle API burst
        }
    }
}

void FetchActivitiesForStatus(uint clubId, bool active, Activity@[]& items) {
    Json::Value@ resp = API::GetClubActivities(clubId, active, 100, 0);
    if (resp !is null && resp.HasKey("activityList")) {
        Json::Value@ list = resp["activityList"];
        for (uint i = 0; i < list.Length; i++) {
            if (list[i].GetType() != Json::Type::Object) {
                continue;
            }
            Activity@ a = Activity(list[i]);
            
            // Re-use existing activity handle if it has unsaved changes
            Activity@ toAdd = a;
            for (uint j = 0; j < State::ClubActivities.Length; j++) {
                if (State::ClubActivities[j].Id == a.Id && State::ClubActivities[j].HasMapChanges) {
                    @toAdd = State::ClubActivities[j];
                    break;
                }
            }

            bool duplicate = false;
            for (uint j = 0; j < items.Length; j++) if (items[j].Id == toAdd.Id) { duplicate = true; break; }
            if (!duplicate) items.InsertLast(toAdd);
        }
    }
}

void DoCreateCampaign() {
    if (State::SelectedClub is null) return;
    Json::Value@ json = API::CreateClubActivity(State::SelectedClub.Id, State::nextActivityName, "campaign", 0, State::nextActivityActive);
    
    // Nadeo API bug: campaigns are always created inactive despite the creation flag.
    if (json !is null && State::nextActivityActive) {
        uint activityId = 0;
        if (json.HasKey("activityId")) activityId = uint(json["activityId"]);
        else if (json.HasKey("id")) activityId = uint(json["id"]);
        
        if (activityId > 0) {
            API::SetActivityStatus(State::SelectedClub.Id, activityId, true);
        }
    }
    
    Notify("Campaign created.");
    startnew(RefreshActivities);
}

void DoCreateRoom() {
    if (State::SelectedClub is null) return;
    Json::Value@ resp = API::CreateClubActivity(State::SelectedClub.Id, State::nextActivityName, "room", 0, State::nextActivityActive, State::nextRoomMirrorCampaignId);
    
    // Response Validation: Ensure the API returned a valid ID
    uint activityId = 0;
    if (resp !is null && resp.GetType() == Json::Type::Object) {
        if (resp.HasKey("activityId")) activityId = uint(resp["activityId"]);
        else if (resp.HasKey("id")) activityId = uint(resp["id"]);
    }

    if (activityId > 0) {
        Notify("Room created successfully (ID: " + activityId + ")");
        State::nextRoomMirrorCampaignId = 0; // Reset
        startnew(RefreshActivities);
    } else {
        string errorMsg = "Room creation failed on server.";
        if (resp !is null && resp.GetType() == Json::Type::Array && resp.Length > 0) {
            errorMsg = string(resp[0]);
        }
        Notify("\\$f00Error: " + errorMsg);
        warn("Room creation failed. Response: " + (resp !is null ? Json::Write(resp) : "null"));
    }
}

void DoCreateFolder() {
    if (State::SelectedClub is null) return;
    API::CreateClubActivity(State::SelectedClub.Id, State::nextActivityName, "folder", 0, State::nextActivityActive);
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

class MoveAction {
    Activity@ Act;
    uint FolderId;
    MoveAction(Activity@ a, uint f) { @Act = a; FolderId = f; }
}

void DoMoveActivity(ref@ r) {
    MoveAction@ action = cast<MoveAction>(r);
    if (action is null || action.Act is null || State::SelectedClub is null) return;
    API::MoveActivity(State::SelectedClub.Id, action.Act.Id, action.FolderId);
    action.Act.IsMoving = false;
    Notify("Activity moved.");
    startnew(RefreshActivities);
}

void DoDeleteActivity(ref@ r) {
    Activity@ a = cast<Activity>(r);
    if (a is null || State::SelectedClub is null) return;
    API::DeleteActivity(State::SelectedClub.Id, a.Id);
    Subscriptions::Remove(a.Id); // Clean up subscription
    Notify("Activity permanently deleted.");
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
    a.Failed = false;
    Json::Value@ resp = (a.Type == "news") ? API::GetClubNews(State::SelectedClub.Id, a.Id) : API::GetClubActivity(State::SelectedClub.Id, a.Id);
    if (resp !is null && resp.GetType() == Json::Type::Object) {
        Json::Value@ details = resp.HasKey("news") ? resp["news"] : resp;
        if (a.Type == "news") {
            a.Headline = JsonGetString(details, "headline", a.Name).Replace("|ClubActivity|", "");
            a.Body = JsonGetString(details, "body", "").Replace("|ClubActivity|", "");
        } else {
            a.Body = JsonGetString(details, "description", "");
        }
        a.NewsLoaded = true;
    } else {
        a.Failed = true;
        warn("Failed to load activity details for " + a.Id + " (Type: " + a.Type + ")");
    }
    a.LoadingMaps = false;
}

void LoadActivityMaps(ref@ r) {
    Activity@ a = cast<Activity>(r);
    if (a is null || State::SelectedClub is null) return;
    
    a.Failed = false;
    a.LoadingMaps = true;
    if (a.HasMapChanges) {
        // trace("LoadActivityMaps: " + a.Name + " has unsaved changes, skipping reload.");
        a.LoadingMaps = false;
        a.MapsLoaded = true;
        return;
    }
    a.Maps.RemoveRange(0, a.Maps.Length);
    uint clubId = State::SelectedClub.Id;
    string[] uids;

    if (a.Type == "campaign") {
        Json::Value@ json = API::GetCampaignMaps(clubId, a.CampaignId);
        // trace("GetCampaignMaps(" + a.CampaignId + ") raw response: " + (json is null ? "null" : Json::Write(json)));
        if (json !is null && json.GetType() == Json::Type::Object) {
            a.CampaignId = JsonGetUint(json, "campaignId", a.CampaignId);
            a.Name = Text::StripFormatCodes(JsonGetString(json, "name", a.Name));
            // Check top level, then check inside "campaign" object
            Json::Value@ list = GetMapListFromJson(json);
            if (list is null && json.HasKey("campaign")) @list = GetMapListFromJson(json["campaign"]);

            if (list !is null && list.GetType() == Json::Type::Array) {
                for (uint i = 0; i < list.Length; i++) {
                    if (uids.Length >= 25) break; // Nadeo backend sometimes retains ghost maps >25, force clip to game limits
                    Json::Value@ item = list[i];
                    if (item.HasKey("mapUid")) {
                        uids.InsertLast(string(item["mapUid"]).Trim());
                    }
                }
            }
        } else {
            a.Failed = true;
        }
    } else if (a.Type == "room") {
        Json::Value@ json = API::GetClubRoom(clubId, a.RoomId);
        // trace("GetClubRoom(" + a.RoomId + ") raw response: " + (json is null ? "null" : Json::Write(json)));
        if (json !is null && json.GetType() == Json::Type::Object) {
            // Check if this room is mirroring a campaign
            uint campaignId = 0;
            if (json.HasKey("campaignId") && json["campaignId"].GetType() == Json::Type::Number) {
                campaignId = uint(json["campaignId"]);
            } else if (json.HasKey("room") && json["room"].HasKey("campaignId") && json["room"]["campaignId"].GetType() == Json::Type::Number) {
                campaignId = uint(json["room"]["campaignId"]);
            }
            a.CampaignId = campaignId; // Update so SEVER button shows up
            a.MirrorCampaignId = campaignId; // Unify with UI/Importer monitoring
            
            Json::Value@ list = null;
            if (campaignId > 0) {
                // trace("Room " + a.Id + " is mirroring Campaign ID " + campaignId + ". Fetching campaign maps.");
                uint campaignActivityId = 0;
                for (uint i = 0; i < State::ClubActivities.Length; i++) {
                    if (State::ClubActivities[i].Type == "campaign" && State::ClubActivities[i].CampaignId == campaignId) {
                        campaignActivityId = State::ClubActivities[i].Id;
                        a.MirroringCampaignName = State::ClubActivities[i].Name;
                        break;
                    }
                }
                if (campaignActivityId > 0) {
                    Json::Value@ campJson = API::GetCampaignMaps(clubId, campaignActivityId);
                    @list = GetMapListFromJson(campJson);
                    if (list is null && campJson.HasKey("campaign")) @list = GetMapListFromJson(campJson["campaign"]);
                } else {
                    // trace("Could not find campaign activity for mirroring campaignId " + campaignId);
                }
            }

            if (list is null) {
                @list = GetMapListFromJson(json);
                if (list is null && json.HasKey("room")) @list = GetMapListFromJson(json["room"]);
            }

            if (list !is null && list.GetType() == Json::Type::Array) {
                for (uint i = 0; i < list.Length; i++) {
                    Json::Value@ item = list[i];
                    string uid = "";
                    if (item.GetType() == Json::Type::Object && item.HasKey("mapUid")) uid = string(item["mapUid"]).Trim();
                    else if (item.GetType() == Json::Type::String) uid = string(item).Trim();
                    
                    if (uid != "" && !uid.Contains(":error-")) uids.InsertLast(uid);
                }
            }
        } else {
            a.Failed = true;
        }
    }

    // trace("Found " + uids.Length + " map UIDs for " + a.Name);
    if (uids.Length > 0) {
        // trace("Fetching metadata for " + uids.Length + " maps...");
        
        // Process in batches of 100 (API limit)
        for (uint i = 0; i < uids.Length; i += 100) {
            string[] batch;
            for (uint j = i; j < i + 100 && j < uids.Length; j++) {
                batch.InsertLast(uids[j]);
            }
            
            Json::Value@ mapsJson = API::GetMapsInfo(batch);
            if (mapsJson !is null) {
                Json::Value@ list = null;
                if (mapsJson.GetType() == Json::Type::Array) @list = mapsJson;
                else if (mapsJson.HasKey("mapList")) @list = mapsJson["mapList"];

                if (list !is null) {
                    for (uint k = 0; k < list.Length; k++) {
                        MapInfo@ mi = MapInfo(list[k]);
                        a.Maps.InsertLast(mi);
                        AuditCache::Register(mi);
                    }
                }
            }
        }

        // Important: API might return maps in different order. Reorder a.Maps to match 'uids' array.
        MapInfo@[] ordered;
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
            // trace("Resolving " + authorIds.Length + " author names...");
            string[]@ resolvedNames = API::GetDisplayNames(authorIds);
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
    // trace("Finished loading " + a.Maps.Length + " maps for " + a.Name);
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
            Json::Value@ res = GetMapListFromJson(json[nested[i]]);
            if (res !is null) return res;
        }
    }

    return null;
}

void DoSaveNews(ref@ r) {
    Activity@ a = cast<Activity>(r);
    if (a is null || State::SelectedClub is null) return;
    Json::Value@ s = Json::Object();
    s["headline"] = "|ClubActivity|" + a.Headline;
    s["body"] = "|ClubActivity|" + a.Body;
    API::EditClubNews(State::SelectedClub.Id, a.Id, s);
    Notify("News content updated.");
}

void DoUpdateBranding(ref@ r) {
    if (State::SelectedClub is null) return;
    Json::Value@ s = Json::Object();
    s["tag"] = State::clubTag;
    s["description"] = State::clubDescription;
    s["public"] = State::clubPublic;
    
    API::SetClubDetails(State::SelectedClub.Id, s);
    Notify("Club settings updated.");
}

void DoAuditSubscription(ref@ r) {
    Activity@ a = cast<Activity>(r);
    if (a is null || State::SelectedClub is null) return;
    
    Subscription@ sub = Subscriptions::GetByActivity(a.Id);
    if (sub is null) return;
    
    if (!a.MapsLoaded && !a.LoadingMaps) {
        startnew(LoadActivityMaps, a);
    }
    while (a.LoadingMaps) yield();
    
    a.IsAuditing = true;
    a.AuditDone = false;
    a.AuditAdded.RemoveRange(0, a.AuditAdded.Length);
    a.AuditRemoved.RemoveRange(0, a.AuditRemoved.Length);
    a.AuditFullUidList.RemoveRange(0, a.AuditFullUidList.Length);
    a.AuditOrderMismatch = false;
    
    Notify("Auditing subscription for " + a.Name + "...");
    
    TmxMap@[] results;
    if (sub.SourceType == 1) { // Local List
        TmxMap@[] allMaps = CustomLists::GetMaps(sub.ListId);
        // Apply Denylist for local lists too
        TmxMap@[] filtered;
        for (uint i = 0; i < allMaps.Length; i++) {
            if (!Denylist::IsExcluded(allMaps[i].Uid)) filtered.InsertLast(allMaps[i]);
            if (filtered.Length >= sub.MapLimit) break;
        }
        results = filtered;
    } else { // TMX Search
        // Denylist is handled inside FetchMapsSequential -> FilterTmxResults
        // For page 2+, shift the TMX skip count back by the number of smart-includes that
        // were injected into earlier pages, so bumped maps aren't lost in the gap.
        int priorSmart = (sub.Filters.CurrentPage > 1) ? CountMatchingSmartIncludes(sub.Filters) : 0;
        results = FetchMapsSequential(sub.Filters, sub.MapLimit, true, true, priorSmart);
    }

    if (results.Length == 0 && sub.ForcedIncludes.Length == 0) {
        Notify("Audit failed: No maps found in source (" + (sub.SourceType == 1 ? "Local List: " + sub.ListId : "TMX Search") + ").");
        a.IsAuditing = false;
        return;
    }

    // --- Smart includes: override-cached maps that match subscription filters ---
    if (sub.SourceType == 0) {
        results = ApplySmartIncludes(results, sub.Filters, sub.MapLimit);
    }

    // Calculate Diff
    for (uint i = 0; i < results.Length; i++) {
        if (i % 20 == 0) yield();
        bool found = false;
        for (uint j = 0; j < a.Maps.Length; j++) {
            if (a.Maps[j].Uid == results[i].Uid) { found = true; break; }
        }
        if (!found) a.AuditAdded.InsertLast(results[i]);
    }

    for (uint i = 0; i < a.Maps.Length; i++) {
        if (i % 20 == 0) yield();
        bool found = false;
        for (uint j = 0; j < results.Length; j++) {
            if (results[j].Uid == a.Maps[i].Uid) { found = true; break; }
        }
        if (!found) a.AuditRemoved.InsertLast(a.Maps[i]);
    }

    // Check Order Mismatch (only if map sets are identical)
    if (results.Length == a.Maps.Length && a.AuditAdded.Length == 0 && a.AuditRemoved.Length == 0) {
        for (uint i = 0; i < results.Length; i++) {
            if (results[i].Uid != a.Maps[i].Uid) {
                a.AuditOrderMismatch = true;
                break;
            }
        }
    }

    // Store the full UID list for the Action step
    for (uint i = 0; i < results.Length; i++) a.AuditFullUidList.InsertLast(results[i].Uid);

    // --- Forced includes: pinned maps appended regardless of filters ---
    for (uint i = 0; i < sub.ForcedIncludes.Length; i++) {
        string uid = sub.ForcedIncludes[i];
        bool alreadyIn = false;
        for (uint j = 0; j < a.AuditFullUidList.Length; j++) {
            if (a.AuditFullUidList[j] == uid) { alreadyIn = true; break; }
        }
        if (!alreadyIn) {
            a.AuditFullUidList.InsertLast(uid);
            // Try to surface a TmxMap for the audit detail display
            TmxMap@ cached = null;
            if (State::SelectedClub !is null) cached = ClubOverrides::GetCachedMap(State::SelectedClub.Id, uid);
            if (cached is null) cached = MetadataOverrides::GetCachedMap(uid);
            if (cached !is null) {
                a.AuditAdded.InsertLast(cached);
            } else {
                // Create minimal placeholder so the audit display shows something
                TmxMap@ placeholder = TmxMap();
                placeholder.Uid = uid;
                placeholder.Name = AuditCache::IsKnown(uid) ? AuditCache::GetName(uid) : uid;
                a.AuditAdded.InsertLast(placeholder);
            }
        }
        // Remove from AuditRemoved if it was there
        MapInfo@[] kept;
        for (uint j = 0; j < a.AuditRemoved.Length; j++) {
            if (a.AuditRemoved[j].Uid != uid) kept.InsertLast(a.AuditRemoved[j]);
        }
        a.AuditRemoved = kept;
    }

    a.AuditDone = true;
    a.IsAuditing = false;
    Notify("Audit complete for " + a.Name + ". Review the proposed changes.");
}

void DoApplyAudit(ref@ r) {
    Activity@ a = cast<Activity>(r);
    if (a is null || State::SelectedClub is null) return;
    
    Subscription@ sub = Subscriptions::GetByActivity(a.Id);
    if (sub is null) return;
    
    // Logic Refactor: use the cached AuditFullUidList from the Perform Audit stage
    if (a.AuditFullUidList.Length == 0) {
        Notify("Failed to apply audit: No cached TMX data found. Please run the audit again.");
        return;
    }
    
    string[] newUids;
    for (uint i = 0; i < a.AuditFullUidList.Length; i++) {
        if (i % 10 == 0) yield();
        string uid = a.AuditFullUidList[i];
        if (!Nadeo::IsMapUploaded(uid)) {
            Nadeo::RegisterMap(uid);
            yield();
        }
        newUids.InsertLast(uid);
    }
    
    Notify("Applying audit changes to " + a.Name + "...");
    ApplyBatchToActivity(a, newUids);
    a.AuditDone = false;
    a.AuditFullUidList.RemoveRange(0, a.AuditFullUidList.Length);
    startnew(LoadActivityMaps, a);
}

void DoDiscardAudit(ref@ r) {
    Activity@ a = cast<Activity>(r);
    if (a is null) return;
    a.AuditDone = false;
    a.AuditAdded.RemoveRange(0, a.AuditAdded.Length);
    a.AuditRemoved.RemoveRange(0, a.AuditRemoved.Length);
    a.AuditFullUidList.RemoveRange(0, a.AuditFullUidList.Length);
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
    
    MapInfo@ m = action.Act.Maps[action.Index];
    action.Act.Maps.RemoveAt(action.Index);
    action.Act.Maps.InsertAt(toIdx, m);
    action.Act.HasMapChanges = true;
}

void DoSaveMapChanges(ref@ r) {
    Activity@ a = cast<Activity>(r);
    if (a is null || State::SelectedClub is null) return;
    
    // trace("DoSaveMapChanges: committing changes for " + a.Name);
    string[] uids;
    for (uint i = 0; i < a.Maps.Length; i++) {
        if (!a.Maps[i].PendingDelete) {
            uids.InsertLast(a.Maps[i].Uid);
        }
    }
    
    if (uids.Length == 0) {
        Notify("Operation failed: Nadeo requires at least 1 map to remain in the activity!");
        return;
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

void DoBulkAudit() {
    if (State::bulkAuditInProgress) return;
    State::bulkAuditInProgress = true;
    State::bulkAuditComplete = false;
    State::bulkAuditUpdatesAvailable = 0;
    State::bulkAuditProgress = 0.0f;
    
    Activity@[]@ items = State::ClubActivities;
    uint total = 0;
    for (uint i = 0; i < items.Length; i++) {
        if (Subscriptions::GetByActivity(items[i].Id) !is null) total++;
    }
    
    if (total == 0) {
        Notify("No subscriptions found to audit.");
        State::bulkAuditInProgress = false;
        return;
    }
    
    uint current = 0;
    uint updatesFound = 0;
    for (uint i = 0; i < items.Length; i++) {
        if (State::SelectedClub is null) break;
        if (Subscriptions::GetByActivity(items[i].Id) !is null) {
            State::bulkAuditStatus = "Auditing " + items[i].Name + "... (" + (current + 1) + "/" + total + ")";
            State::bulkAuditProgress = float(current) / float(total);
            
            DoAuditSubscription(items[i]);
            if (items[i].AuditAdded.Length > 0 || items[i].AuditRemoved.Length > 0 || items[i].AuditOrderMismatch) {
                updatesFound++;
            }
            
            current++;
            yield();
        }
    }
    
    uint campaignUpdates = 0;
    uint roomUpdates = 0;
    for (uint i = 0; i < items.Length; i++) {
        if (items[i].AuditDone && (items[i].AuditAdded.Length > 0 || items[i].AuditRemoved.Length > 0 || items[i].AuditOrderMismatch)) {
            if (items[i].Type == "campaign") campaignUpdates++;
            else if (items[i].Type == "room") roomUpdates++;
        }
    }

    State::bulkAuditUpdatesAvailable = campaignUpdates + roomUpdates;
    if (State::bulkAuditUpdatesAvailable == 0) {
        State::bulkAuditStatus = "Audit Complete: All subscriptions are up to date.";
    } else if (State::bulkAuditUpdatesAvailable == 1) {
        // Single activity changed — name it and describe the change inline
        for (uint i = 0; i < items.Length; i++) {
            if (items[i].AuditDone && (items[i].AuditAdded.Length > 0 || items[i].AuditRemoved.Length > 0 || items[i].AuditOrderMismatch)) {
                string changeDesc = "";
                if (items[i].AuditAdded.Length > 0) changeDesc += "+" + items[i].AuditAdded.Length;
                if (items[i].AuditRemoved.Length > 0) { if (changeDesc != "") changeDesc += " "; changeDesc += "-" + items[i].AuditRemoved.Length; }
                if (items[i].AuditOrderMismatch) { if (changeDesc != "") changeDesc += " "; changeDesc += "reorder"; }
                State::bulkAuditStatus = "Audit Complete: " + items[i].Name + " (" + changeDesc + ")";
                break;
            }
        }
    } else {
        string summary = "";
        if (campaignUpdates > 0) summary += campaignUpdates + " Campaign" + (campaignUpdates > 1 ? "s" : "");
        if (roomUpdates > 0) {
            if (summary != "") summary += ", ";
            summary += roomUpdates + " Room" + (roomUpdates > 1 ? "s" : "");
        }
        State::bulkAuditStatus = "Audit Complete: " + summary + " out of sync. See details below.";
    }
    
    State::bulkAuditProgress = 1.0f;
    State::bulkAuditComplete = true;
    State::bulkAuditInProgress = false;
}

void DoBulkApply() {
    if (State::bulkAuditInProgress || !State::bulkAuditComplete) return;
    State::bulkAuditInProgress = true;
    State::bulkAuditProgress = 0.0f;
    
    Activity@[]@ items = State::ClubActivities;
    uint total = 0;
    for (uint i = 0; i < items.Length; i++) {
        if (items[i].AuditDone && (items[i].AuditAdded.Length > 0 || items[i].AuditRemoved.Length > 0 || items[i].AuditOrderMismatch)) {
            total++;
        }
    }
    
    if (total == 0) {
        Notify("No pending updates to apply.");
        State::bulkAuditInProgress = false;
        State::bulkAuditComplete = false;
        return;
    }
    
    uint current = 0;
    for (uint i = 0; i < items.Length; i++) {
        if (State::SelectedClub is null) break;
        if (items[i].AuditDone && (items[i].AuditAdded.Length > 0 || items[i].AuditRemoved.Length > 0 || items[i].AuditOrderMismatch)) {
            State::bulkAuditStatus = "Updating " + items[i].Name + "... (" + (current + 1) + "/" + total + ")";
            State::bulkAuditProgress = float(current) / float(total);
            
            DoApplyAudit(items[i]);
            
            current++;
            yield();
        }
    }
    
    State::bulkAuditStatus = "Bulk Update Complete!";
    State::bulkAuditProgress = 1.0f;
    sleep(2000);
    State::bulkAuditComplete = false;
    State::bulkAuditInProgress = false;
}
