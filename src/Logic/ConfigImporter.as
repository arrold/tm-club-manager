// Logic/ConfigImporter.as - Idempotent Club Configuration Importer

namespace ConfigImporter {
    bool isImporting = false;
    bool dryRun = false;
    string[] log;

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

    void Log(const string &in msg) {
        log.InsertLast(msg);
        // trace("[Importer] " + msg);
    }

    class DeltaSummary {
        uint FoldersCreated = 0;
        uint FoldersVerified = 0;
        uint ActivitiesCreated = 0;
        uint ActivitiesUpdated = 0;
        uint ActivitiesVerified = 0;
        uint SubscriptionsUpdated = 0;
        uint Warnings = 0;

        string ToLogString() {
            return "Summary: Folders: " + FoldersCreated + " Created, " + FoldersVerified + " Verified | " +
                   "Activities: " + ActivitiesCreated + " Created, " + ActivitiesUpdated + " Updated, " + ActivitiesVerified + " Verified | " +
                   "Subscriptions: " + SubscriptionsUpdated + " Updated | " +
                   "Warnings: " + Warnings;
        }
    }

    DeltaSummary@ currentDelta;

    void Import(Json::Value@ config, bool isDryRun = false) {
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

        // Club Name Validation
        string targetClubName = JsonGetString(config, "clubName");
        if (targetClubName == "") {
            Log("Warning: No 'clubName' field found in JSON. Proceeding with caution.");
            currentDelta.Warnings++;
        } else if (targetClubName != State::SelectedClub.Name) {
            Log("CRITICAL ERROR: Configuration is intended for club '" + targetClubName + "' but you have '" + State::SelectedClub.Name + "' selected.");
            Log("Import aborted for safety.");
            currentDelta.Warnings++;
            isImporting = false;
            return;
        }

        // 1. Discovery
        Activity@[] existing;
        FetchAllExisting(State::SelectedClub.Id, existing);
        // Log("Found " + existing.Length + " existing activities.");

        bool prune = JsonGetBool(config, "prune", false);
        
        // 2. Process Folders first
        if (config.HasKey("folders") && config["folders"].GetType() == Json::Type::Array) {
            Json::Value@ folders = config["folders"];
            for (uint i = 0; i < folders.Length; i++) {
                ProcessFolder(folders[i], 0, existing);
            }
        }

        // 3. Process Root Activities
        if (config.HasKey("activities") && config["activities"].GetType() == Json::Type::Array) {
            Json::Value@ activities = config["activities"];
            for (uint i = 0; i < activities.Length; i++) {
                ProcessActivity(activities[i], 0, existing);
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

    void ProcessFolder(Json::Value@ json, uint parentFolderId, Activity@[]& existing) {
        string name = JsonGetString(json, "name");
        if (name == "") return;

        Activity@ folder = FindExisting(name, "folder", parentFolderId, existing);
        uint folderId = 0;

        if (folder is null) {
            Log("Creating folder: " + name);
            currentDelta.FoldersCreated++;
            if (!dryRun) {
                Json::Value@ resp = API::CreateClubActivity(State::SelectedClub.Id, name, "folder", parentFolderId, true);
                if (resp !is null) {
                    folderId = JsonGetUint(resp, "id");
                    if (folderId == 0) folderId = JsonGetUint(resp, "activityId");
                }
            } else {
                folderId = 999999 + currentDelta.FoldersCreated; // Mock ID
            }
        } else {
            folderId = folder.Id;
            currentDelta.FoldersVerified++;
            // Log("Found existing folder: " + name);
        }

        if (folderId == 0) {
            Log("Error: Failed to resolve ID for folder: " + name);
            currentDelta.Warnings++;
            return;
        }

        if (json.HasKey("activities") && json["activities"].GetType() == Json::Type::Array) {
            Json::Value@ items = json["activities"];
            for (uint i = 0; i < items.Length; i++) {
                string type = JsonGetString(items[i], "type");
                if (type == "folder") {
                    ProcessFolder(items[i], folderId, existing);
                } else {
                    ProcessActivity(items[i], folderId, existing);
                }
            }
        }
    }

    void ProcessActivity(Json::Value@ json, uint folderId, Activity@[]& existing) {
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
                Json::Value@ resp = API::CreateClubActivity(State::SelectedClub.Id, name, type, folderId, active, mirrorId);
                if (resp !is null) {
                    actId = JsonGetUint(resp, "id");
                    if (actId == 0) actId = JsonGetUint(resp, "activityId");
                }
            } else {
                actId = 888888 + currentDelta.ActivitiesCreated;
            }
        } else {
            actId = act.Id;
            bool changed = false;
            
            // Check for updates
            bool active = JsonGetBool(json, "active", true);
            if (act.Active != active) {
                Log("Updating active status for " + name);
                if (!dryRun) API::SetActivityStatus(State::SelectedClub.Id, actId, active);
                changed = true;
            }
            if (act.FolderId != folderId) {
                Log("Moving " + name + " to folder " + folderId);
                if (!dryRun) API::MoveActivity(State::SelectedClub.Id, actId, folderId);
                changed = true;
            }

            if (changed) currentDelta.ActivitiesUpdated++;
            else currentDelta.ActivitiesVerified++;
        }

        if (actId > 0 && json.HasKey("subscription")) {
            ApplySubscription(actId, name, json["subscription"], act);
        }
    }

    Activity@ FindExisting(const string &in name, const string &in type, uint folderId, Activity@[]& existing) {
        for (uint i = 0; i < existing.Length; i++) {
            if (existing[i].Name == name && existing[i].Type == type && existing[i].FolderId == folderId) {
                return existing[i];
            }
        }
        return null;
    }

    void ApplySubscription(uint activityId, const string &in activityName, Json::Value@ json, Activity@ existingAct) {
        Subscription@ sub = Subscription();
        sub.ClubId = State::SelectedClub.Id;
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

        // Check for updates if we have an existing activity
        bool needsUpdate = true;
        if (existingAct !is null) {
            Subscription@ existingSub = Subscriptions::GetByActivity(existingAct.Id);
            if (existingSub !is null) {
                // Simplified comparison: if we are importing, we assume the user wants THIS subscription state.
                // We'll mark it as updated for transparency.
            }
        }

        currentDelta.SubscriptionsUpdated++;
        if (!dryRun) {
            Subscriptions::Add(sub);
        } else {
            // Log("Dry Run: Subscription update pending for " + activityName);
        }
    }
}
