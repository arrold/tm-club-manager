// Logic/ConfigImporter.as - Idempotent Club Configuration Importer

namespace ConfigImporter {
    bool isImporting = false;
    bool dryRun = false;
    
    enum LogType { Info, Warning, Error }
    
    class LogEntry {
        string Msg;
        LogType Type;
        LogEntry(const string &in msg, LogType type) {
            Msg = msg;
            Type = type;
        }
    }

    LogEntry@[] log;

    string[] GetAvailableConfigs() {
        string[] files;
        string dir = IO::FromStorageFolder("");
        array<string> allFiles = IO::IndexFolder(dir, true);
        for (uint i = 0; i < allFiles.Length; i++) {
            string f = allFiles[i];
            if (f.EndsWith(".json") && !f.Contains("subscriptions.json") && !f.Contains("metadata_overrides.json") && !f.Contains("custom_lists.json")) {
                // Return only the filename for easier selection
                files.InsertLast(f.Replace(dir, ""));
            }
        }
        return files;
    }

    void Log(const string &in msg, LogType type = LogType::Info) {
        log.InsertLast(LogEntry(msg, type));
        if (type == LogType::Error) trace("[Importer] ERROR: " + msg);
        else if (type == LogType::Warning) trace("[Importer] WARNING: " + msg);
        else trace("[Importer] " + msg);
    }

    class DeltaSummary {
        uint FoldersCreated = 0;
        uint FoldersUpdated = 0;
        uint FoldersVerified = 0;
        uint ActivitiesCreated = 0;
        uint ActivitiesUpdated = 0;
        uint ActivitiesVerified = 0;
        uint SubscriptionsUpdated = 0;
        uint Warnings = 0;
        uint Errors = 0;

        string ToLogString() {
            return "Summary: Folders: " + FoldersCreated + " Created, " + FoldersUpdated + " Updated, " + FoldersVerified + " Verified | " +
                   "Activities: " + ActivitiesCreated + " Created, " + ActivitiesUpdated + " Updated, " + ActivitiesVerified + " Verified | " +
                   "Subscriptions: " + SubscriptionsUpdated + " Updated | " +
                   "Warnings: " + Warnings + " | Errors: " + Errors;
        }
    }

    DeltaSummary@ currentDelta;

    void Import(Json::Value@ config, bool isDryRun = false) {
        if (config is null || config.GetType() != Json::Type::Object) return;
        if (isImporting) return;
        if (State::SelectedClub is null) {
            UI::ShowNotification("Importer", "Select a club first.");
            return;
        }

        isImporting = true;
        dryRun = isDryRun;
        @currentDelta = DeltaSummary();
        log.RemoveRange(0, log.Length);
        Log("Starting " + (dryRun ? "DRY RUN " : "") + "import for Club: " + State::SelectedClub.Name);

        // 0. Pre-flight Validation
        ValidateJson(config);
        if (currentDelta.Warnings > 0) {
            Log("Validation Warning: Found " + currentDelta.Warnings + " potential issues with name lengths or metadata.");
        }

        // Club Name Validation
        string targetClubName = JsonGetString(config, "clubName");
        if (targetClubName == "") {
            Log("Warning: No 'clubName' field found in JSON. Proceeding with caution.");
            currentDelta.Warnings++;
        } else if (targetClubName != State::SelectedClub.Name) {
            Log("CRITICAL ERROR: Configuration is intended for club '" + targetClubName + "' but you have '" + State::SelectedClub.Name + "' selected.", LogType::Error);
            Log("Import aborted for safety.", LogType::Error);
            currentDelta.Errors++;
            isImporting = false;
            return;
        }

        // 1. Discovery
        Activity@[] existing;
        uint clubId = State::SelectedClub.Id;
        FetchAllExisting(clubId, existing);
        bool prune = JsonGetBool(config, "prune", false);
        
        // 2. Process Folders first
        if (config.HasKey("folders") && config["folders"].GetType() == Json::Type::Array) {
            Json::Value@ folders = config["folders"];
            for (uint i = 0; i < folders.Length; i++) {
                ProcessFolder(folders[i], 0, existing, clubId);
            }
        }

        // 3. Process Root Activities (Campaigns first for mirroring)
        if (config.HasKey("activities") && config["activities"].GetType() == Json::Type::Array) {
            Json::Value@ activities = config["activities"];
            // First pass: Campaigns
            for (uint i = 0; i < activities.Length; i++) {
                if (JsonGetString(activities[i], "type") == "campaign") ProcessActivity(activities[i], 0, existing, clubId);
            }
            // Second pass: Rooms & Others
            for (uint i = 0; i < activities.Length; i++) {
                if (JsonGetString(activities[i], "type") != "campaign") ProcessActivity(activities[i], 0, existing, clubId);
            }
        }

        // 4. Pruning (if enabled)
        if (prune) {
            Log("Pruning is enabled but not yet fully implemented for safety.");
        }

        Log("Import complete.");
        Log(currentDelta.ToLogString());
        
        if (currentDelta.FoldersCreated == 0 && currentDelta.ActivitiesCreated == 0 && currentDelta.ActivitiesUpdated == 0 && currentDelta.SubscriptionsUpdated == 0) {
            Log("Result: 0 Changes Pending. Local state perfectly matches remote.");
        }

        isImporting = false;
        UI::ShowNotification("Importer", "Import complete. See log for details.");
    }

    void FetchAllExisting(uint clubId, Activity@[]& items) {
        FetchActivitiesForStatus(clubId, true, items);
        FetchActivitiesForStatus(clubId, false, items);
    }

    void ProcessFolder(Json::Value@ json, uint parentFolderId, Activity@[]& existing, uint clubId) {
        string name = JsonGetString(json, "name");
        if (name == "") return;

        Activity@ folder = FindExisting(name, "folder", parentFolderId, existing);
        uint folderId = 0;

        if (folder is null) {
            Log("Creating folder: " + name);
            currentDelta.FoldersCreated++;
            if (!dryRun) {
                Json::Value@ resp = API::CreateClubActivity(clubId, name, "folder", parentFolderId, true);
                if (resp !is null) {
                    folderId = JsonGetUint(resp, "id");
                    if (folderId == 0) folderId = JsonGetUint(resp, "activityId");
                }
            } else {
                folderId = 999999 + currentDelta.FoldersCreated; // Mock ID
            }
        } else {
            folderId = folder.Id;
            
            bool changed = false;
            bool active = JsonGetBool(json, "active", true);
            if (folder.Active != active) {
                Log("Updating active status for folder: " + name);
                if (!dryRun) API::SetActivityStatus(clubId, folderId, active);
                changed = true;
            }
            
            // Use shared logic for featured/public/description to prevent persistent deltas
            if (SyncActivityMetadata(folder, json, clubId)) {
                changed = true;
            }

            if (changed) {
                currentDelta.FoldersUpdated++;
            } else {
                currentDelta.FoldersVerified++;
            }
        }

        if (folderId == 0) {
            Log("Error: Failed to resolve ID for folder: " + name, LogType::Error);
            currentDelta.Errors++;
            return;
        }

        if (json.HasKey("activities") && json["activities"].GetType() == Json::Type::Array) {
            Json::Value@ items = json["activities"];
            // Pass 1: Campaigns first
            for (uint i = 0; i < items.Length; i++) {
                if (JsonGetString(items[i], "type") == "campaign") ProcessActivity(items[i], folderId, existing, clubId);
            }
            // Pass 2: Folders (Recursive)
            for (uint i = 0; i < items.Length; i++) {
                if (JsonGetString(items[i], "type") == "folder") ProcessFolder(items[i], folderId, existing, clubId);
            }
            // Pass 3: Rooms & Others
            for (uint i = 0; i < items.Length; i++) {
                string type = JsonGetString(items[i], "type");
                if (type != "campaign" && type != "folder") ProcessActivity(items[i], folderId, existing, clubId);
            }
        }
    }

    void ProcessActivity(Json::Value@ json, uint folderId, Activity@[]& existing, uint clubId) {
        string name = JsonGetString(json, "name");
        string type = JsonGetString(json, "type");
        if (name == "" || type == "") return;

        Activity@ act = FindExisting(name, type, folderId, existing);
        uint actId = 0;

        if (act is null) {
            Log("Creating " + type + ": " + name);
            currentDelta.ActivitiesCreated++;
            if (!dryRun) {
                bool active = JsonGetBool(json, "active", true);
                uint mirrorId = JsonGetUint(json, "mirrorCampaignId", 0);
                string mirrorName = JsonGetString(json, "mirrorCampaignName");
                if (mirrorName != "") {
                    mirrorId = FindCampaignIdByName(mirrorName, existing);
                    if (mirrorId == 0) Log("Warning: Could not find mirrored campaign '" + mirrorName + "' locally. Linking may fail.", LogType::Warning);
                    else Log("Resolved mirror '" + mirrorName + "' to ID: " + mirrorId);
                }
                Json::Value@ resp = API::CreateClubActivity(clubId, name, type, folderId, active, mirrorId);
                Json::Value@ activityJson = JsonDeepExtract(resp);
                if (activityJson !is null && activityJson.GetType() == Json::Type::Object) {
                    actId = JsonGetUint(activityJson, "id");
                    if (actId == 0) actId = JsonGetUint(activityJson, "activityId");
                    
                    Log("Successfully created " + type + " '" + name + "' with ID: " + actId);

                    // Add newly created activity to existing list so siblings can mirror it!
                    Activity@ newAct = Activity(activityJson);
                    newAct.FolderId = folderId;
                    existing.InsertLast(newAct);
                    
                    // Sync metadata for new activities too (News body/headline)
                    SyncActivityMetadata(newAct, json, clubId);
                } else {
                    Log("CRITICAL ERROR: Failed to create " + type + " '" + name + "'. Response was null or invalid.", LogType::Error);
                    currentDelta.Errors++;
                }
            } else {
                actId = 888888 + currentDelta.ActivitiesCreated;
            }
        } else {
            actId = act.Id;
            bool changed = false;

            // 1. Metadata Sync First (Lazy loading detailed data like Mirror IDs and Descriptions)
            if (SyncActivityMetadata(act, json, clubId)) {
                changed = true;
            }
            
            // 2. State checks (Active, Folder/Location)
            bool active = JsonGetBool(json, "active", true);
            if (act.Active != active) {
                Log("Updating active status for " + name);
                if (!dryRun) API::SetActivityStatus(clubId, actId, active);
                changed = true;
            }
            if (act.FolderId != folderId) {
                Log("Moving " + name + " to folder " + folderId + " (Previous: " + act.FolderId + ")");
                if (!dryRun) API::MoveActivity(clubId, actId, folderId);
                changed = true;
            }

            // 3. Mirror Link Audit (Rooms only - now uses fresh data from SyncActivityMetadata)
            if (type == "room") {
                string mirrorName = JsonGetString(json, "mirrorCampaignName");
                if (mirrorName != "") {
                    uint targetMirrorId = FindCampaignIdByName(mirrorName, existing);
                    if (targetMirrorId > 0) {
                        if (act.MirrorCampaignId == targetMirrorId) {
                            // Perfect match, no change needed
                        } else if (act.MirrorCampaignId == 0) {
                            Log("[Unsupported] Room '" + name + "' already exists and is not linked to a campaign. Linking existing rooms is not supported by the TM API.", LogType::Warning);
                            currentDelta.Warnings++;
                        } else {
                            Log("[Unsupported] Room '" + name + "' is already linked to campaign ID " + act.MirrorCampaignId + ". Changing room links is not supported by the TM API.", LogType::Warning);
                            currentDelta.Warnings++;
                        }
                    }
                }
            }

            if (changed) currentDelta.ActivitiesUpdated++;
            else currentDelta.ActivitiesVerified++;
        }

        if (actId > 0 && json.HasKey("subscription")) {
            ApplySubscription(actId, name, json["subscription"], act, clubId);
        }
    }

    Activity@ FindExisting(const string &in name, const string &in type, uint folderId, Activity@[]& existing) {
        string lowerName = name.ToLower();
        // Pass 1: Exact match (Name, Type, Folder)
        for (uint i = 0; i < existing.Length; i++) {
            if (existing[i].Name.ToLower() == lowerName && existing[i].Type == type && existing[i].FolderId == folderId) {
                return existing[i];
            }
        }
        // Pass 2: Fuzzy match (Name, Type only - allows for detecting "Moved" activities)
        for (uint i = 0; i < existing.Length; i++) {
            if (existing[i].Name.ToLower() == lowerName && existing[i].Type == type) {
                // trace("Identity RESOLVED for '" + name + "' (Type: " + type + ") but folder differs: " + existing[i].FolderId + " vs expected " + folderId);
                return existing[i];
            }
        }
        return null;
    }

    uint FindCampaignIdByName(const string &in name, Activity@[]& existing) {
        string lowerName = name.ToLower();
        // trace("Searching for '" + lowerName + "' in " + existing.Length + " indexed activities..."); 
        for (uint i = 0; i < existing.Length; i++) {
            if (existing[i].Name.ToLower() == lowerName && existing[i].Type == "campaign") {
                uint cid = existing[i].CampaignId > 0 ? existing[i].CampaignId : existing[i].Id;
                // trace("Found match: " + existing[i].Name + " (CID/ID: " + cid + ")");
                return cid;
            }
        }
        return 0;
    }

    void ValidateJson(Json::Value@ config) {
        currentDelta.Errors = 0;
        currentDelta.Warnings = 0;
        log.RemoveRange(0, log.Length);
        
        uint featuredCount = CountFeatured(config);
        if (featuredCount > 1) {
            Log("Validation Error: Multiple featured items found (" + featuredCount + "). Only one activity can be featured at a time in a club, or they will flip-flop every sync.", LogType::Error);
            currentDelta.Errors++;
        }

        string clubName = JsonGetString(config, "clubName");
        if (clubName != "" && (clubName.Length < 3 || clubName.Length > 20)) {
            Log("Validation Error: Club Name '" + clubName + "' must be between 3 and 20 characters (Current: " + clubName.Length + ").", LogType::Error);
            currentDelta.Errors++;
        }

        if (config.HasKey("description")) {
            string desc = JsonGetString(config, "description");
            if (desc.Length > 200) {
                Log("Validation Error: Club Description is too long (" + desc.Length + " > 200).", LogType::Error);
                currentDelta.Errors++;
            }
        }

        if (config.HasKey("activities") && config["activities"].GetType() == Json::Type::Array) {
            Json::Value@ activities = config["activities"];
            for (uint i = 0; i < activities.Length; i++) ValidateActivity(activities[i]);
        }
        if (config.HasKey("folders") && config["folders"].GetType() == Json::Type::Array) {
            Json::Value@ folders = config["folders"];
            for (uint i = 0; i < folders.Length; i++) ValidateFolder(folders[i]);
        }
    }

    uint CountFeatured(Json::Value@ json) {
        uint count = 0;
        if (JsonGetBool(json, "featured")) count++;
        if (json.HasKey("activities") && json["activities"].GetType() == Json::Type::Array) {
            Json::Value@ items = json["activities"];
            for (uint i = 0; i < items.Length; i++) count += CountFeatured(items[i]);
        }
        if (json.HasKey("folders") && json["folders"].GetType() == Json::Type::Array) {
            Json::Value@ items = json["folders"];
            for (uint i = 0; i < items.Length; i++) count += CountFeatured(items[i]);
        }
        return count;
    }

    void ValidateActivity(Json::Value@ json) {
        string name = JsonGetString(json, "name");
        string type = JsonGetString(json, "type");
        // Log("DEBUG: Scanning activity '" + name + "' (" + type + ")");
        if (name.Length > 20) {
            Log("Validation Error: Activity name '" + name + "' is too long (" + name.Length + " > 20).", LogType::Error);
            currentDelta.Errors++;
        }
        
        // Field Validation for Campaigns/Rooms (No descriptions allowed)
        if (type == "room" || type == "campaign") {
            if (json.HasKey("description")) {
                Log("Validation Error: Type '" + type + "' does not support descriptions (Master Campaign / Mirror Room 1). Remove this field from JSON.", LogType::Error);
                currentDelta.Errors++;
            }
            if (json.HasKey("headline") || json.HasKey("body")) {
                Log("Validation Error: Type '" + type + "' does not support news content (Headline/Body).", LogType::Error);
                currentDelta.Errors++;
            }
        }

        if (type == "news") {
            string headline = JsonGetString(json, "headline");
            if (headline.Length > 40) {
                Log("Validation Error: News headline for '" + name + "' is too long (" + headline.Length + " > 40).", LogType::Error);
                currentDelta.Errors++;
            }
            string body = JsonGetString(json, "body");
            if (body.Length > 2000) {
                Log("Validation Error: News body for '" + name + "' is too long (" + body.Length + " > 2000).", LogType::Error);
                currentDelta.Errors++;
            }
        }
    }

    void ValidateFolder(Json::Value@ json) {
        string name = JsonGetString(json, "name");
        // Log("DEBUG: Scanning folder '" + name + "'");
        if (name.Length > 20) {
            Log("Validation Error: Folder name '" + name + "' is too long (" + name.Length + " > 20).", LogType::Error);
            currentDelta.Errors++;
        }
        if (json.HasKey("activities") && json["activities"].GetType() == Json::Type::Array) {
            Json::Value@ activities = json["activities"];
            for (uint i = 0; i < activities.Length; i++) {
                string type = JsonGetString(activities[i], "type");
                if (type == "folder") ValidateFolder(activities[i]);
                else ValidateActivity(activities[i]);
            }
        }
    }

    bool SyncActivityMetadata(Activity@ act, Json::Value@ json, uint clubId) {
        if (act is null) return false;

        if (!act.DetailsLoaded) {
            Json::Value@ detail = null;
            if (act.Type == "news") @detail = API::GetClubNews(clubId, act.Id);
            else if (act.Type == "room") @detail = API::GetClubRoom(clubId, act.RoomId);
            else if (act.Type == "campaign") @detail = API::GetCampaignMaps(clubId, act.CampaignId);
            
            if (detail !is null) {
                act.UpdateFromDetail(JsonDeepExtract(detail));
                trace("[Importer] Loaded details for " + act.Name + " (Mirror ID: " + act.MirrorCampaignId + ")");
            } else {
                warn("[Importer] Failed to load details for " + act.Name + " (Type: " + act.Type + " | ID: " + act.Id + " | Room ID: " + act.RoomId + ")");
            }
        }

        bool featured = JsonGetBool(json, "featured", false);
        bool isPublic = JsonGetBool(json, "public", true);
        string desc = JsonGetString(json, "description");
        
        bool metaChanged = false;
        string reason = "";

        if (act.Featured != featured) {
            metaChanged = true;
            reason += "Featured (" + act.Featured + " -> " + featured + "), ";
        }
        if (act.Public != isPublic) {
            metaChanged = true;
            reason += "Public (" + act.Public + " -> " + isPublic + "), ";
        }
        if (act.Description != desc && desc != "") {
            metaChanged = true;
            reason += "Description changed, ";
        }

        if (act.Type == "news") {
            string headline = JsonGetString(json, "headline");
            string body = JsonGetString(json, "body");
            if ((act.Headline != headline && headline != "") || (act.Body != body && body != "")) {
                metaChanged = true;
                reason += "News content changed, ";
            }
            
            if (metaChanged) {
                if (reason.EndsWith(", ")) reason = reason.SubStr(0, reason.Length - 2);
                Log((dryRun ? "[Dry Run] " : "") + "News update for \"" + act.Name + "\": " + reason);
                if (!dryRun) {
                    Json::Value@ data = Json::Object();
                    data["name"] = act.Name;
                    data["headline"] = headline != "" ? headline : act.Name;
                    data["body"] = body != "" ? body : act.Description;
                    data["public"] = isPublic;
                    data["featured"] = featured;
                    API::EditClubNews(clubId, act.Id, data); // News has its own edit endpoint
                }
                if (act.Type != "folder") currentDelta.ActivitiesUpdated++;
                return true;
            }
        } else if (metaChanged) {
            if (reason.EndsWith(", ")) reason = reason.SubStr(0, reason.Length - 2);
            Log((dryRun ? "[Dry Run] " : "") + "Metadata update for \"" + act.Name + "\": " + reason);
            if (!dryRun) {
                Json::Value@ data = Json::Object();
                data["public"] = isPublic;
                data["featured"] = featured;
                if (desc != "") data["description"] = desc;
                // For regular activities, use EditClubActivity
                API::EditClubActivity(clubId, act.Id, data);
            }
            if (act.Type != "folder") currentDelta.ActivitiesUpdated++;
            return true;
        }
        return false;
    }

    void ApplySubscription(uint activityId, const string &in activityName, Json::Value@ json, Activity@ existingAct, uint clubId) {
        Subscription@ sub = Subscription();
        sub.ClubId = clubId;
        sub.ActivityId = activityId;
        sub.ActivityName = activityName;
        
        if (json.HasKey("filters")) {
            @sub.Filters = TmxSearchFilters(json["filters"]);
            sub.SourceType = 0;
        } else if (json.HasKey("listId")) {
            sub.ListId = JsonGetString(json, "listId");
            sub.ListType = JsonGetString(json, "listType", "custom");
            sub.SourceType = 1;
        }
        
        sub.MapLimit = JsonGetUint(json, "mapLimit", 25);

        bool needsUpdate = true;
        string reason = "New subscription";

        if (existingAct !is null) {
            Subscription@ existingSub = Subscriptions::GetByActivity(existingAct.Id);
            if (existingSub !is null) {
                needsUpdate = false;
                reason = "";

                if (sub.SourceType != existingSub.SourceType) {
                    needsUpdate = true;
                    reason += "SourceType changed (" + sub.SourceType + " != " + existingSub.SourceType + "), ";
                }
                if (sub.MapLimit != existingSub.MapLimit) {
                    needsUpdate = true;
                    reason += "MapLimit changed (" + sub.MapLimit + " != " + existingSub.MapLimit + "), ";
                }
                
                if (sub.SourceType == 0) { // Search Filters
                    string diff = sub.Filters.GetDifference(existingSub.Filters);
                    if (diff != "") {
                        needsUpdate = true;
                        reason += diff + ", ";
                    }
                } else if (sub.SourceType == 1) { // List
                    if (sub.ListId != existingSub.ListId) {
                        needsUpdate = true;
                        reason += "ListId changed, ";
                    }
                    if (sub.ListType != existingSub.ListType) {
                        needsUpdate = true;
                        reason += "ListType changed, ";
                    }
                }
            }
        }

        if (needsUpdate) {
            if (reason.EndsWith(", ")) reason = reason.SubStr(0, reason.Length - 2);
            Log((dryRun ? "[Dry Run] " : "") + "Subscription update needed for \"" + activityName + "\": " + reason);
            currentDelta.SubscriptionsUpdated++;
            if (!dryRun) {
                Subscriptions::Add(sub);
            }
        }
    }
}
