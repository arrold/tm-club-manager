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

    void Import(Json::Value@ config, bool isDryRun = false) {
        if (isImporting) return;
        if (State::SelectedClub is null) {
            UI::ShowNotification("Importer", "Select a club first.");
            return;
        }

        isImporting = true;
        dryRun = isDryRun;
        log.RemoveRange(0, log.Length);
        Log("Starting " + (dryRun ? "DRY RUN " : "") + "import for Club: " + State::SelectedClub.Name);

        // Club Name Validation
        string targetClubName = JsonGetString(config, "clubName");
        if (targetClubName == "") {
            Log("Warning: No 'clubName' field found in JSON. Proceeding with caution.");
        } else if (targetClubName != State::SelectedClub.Name) {
            Log("CRITICAL ERROR: Configuration is intended for club '" + targetClubName + "' but you have '" + State::SelectedClub.Name + "' selected.");
            Log("Import aborted for safety.");
            isImporting = false;
            return;
        }

        // 1. Discovery
        Activity@[] existing;
        FetchAllExisting(State::SelectedClub.Id, existing);
        Log("Found " + existing.Length + " existing activities.");

        bool prune = JsonGetBool(config, "prune", false);
        
        // 2. Process Folders first (to establish parentage)
        if (config.HasKey("folders") && config["folders"].GetType() == Json::Type::Array) {
            Json::Value@ folders = config["folders"];
            for (uint i = 0; i < folders.Length; i++) {
                ProcessFolder(folders[i], existing);
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
            // TODO: Implement pruning logic if needed
            Log("Pruning is enabled but not yet fully implemented for safety.");
        }

        Log("Import complete.");
        isImporting = false;
        UI::ShowNotification("Importer", "Import complete. See log for details.");
    }

    void FetchAllExisting(uint clubId, Activity@[]& items) {
        FetchActivitiesForStatus(clubId, true, items);
        FetchActivitiesForStatus(clubId, false, items);
    }

    void ProcessFolder(Json::Value@ json, Activity@[]& existing) {
        string name = JsonGetString(json, "name");
        if (name == "") return;

        Activity@ folder = FindExisting(name, "folder", 0, existing);
        uint folderId = 0;

        if (folder is null) {
            Log("Creating folder: " + name);
            if (!dryRun) {
                Json::Value@ resp = API::CreateClubActivity(State::SelectedClub.Id, name, "folder", 0, true);
                if (resp !is null) {
                    folderId = JsonGetUint(resp, "id");
                    if (folderId == 0) folderId = JsonGetUint(resp, "activityId");
                }
            } else {
                folderId = 999999; // Mock ID for dry run
            }
        } else {
            folderId = folder.Id;
            Log("Found existing folder: " + name + " (ID: " + folderId + ")");
        }

        if (folderId == 0) {
            Log("Error: Failed to resolve ID for folder: " + name);
            return;
        }

        if (json.HasKey("activities") && json["activities"].GetType() == Json::Type::Array) {
            Json::Value@ activities = json["activities"];
            for (uint i = 0; i < activities.Length; i++) {
                ProcessActivity(activities[i], folderId, existing);
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
            if (!dryRun) {
                bool active = JsonGetBool(json, "active", true);
                uint mirrorId = JsonGetUint(json, "mirrorCampaignId", 0);
                Json::Value@ resp = API::CreateClubActivity(State::SelectedClub.Id, name, type, folderId, active, mirrorId);
                if (resp !is null) {
                    actId = JsonGetUint(resp, "id");
                    if (actId == 0) actId = JsonGetUint(resp, "activityId");
                }
            } else {
                actId = 999999;
            }
        } else {
            actId = act.Id;
            Log("Found existing " + type + ": " + name + " (ID: " + actId + ")");
            // Check for updates (active status, mirror ID etc.)
            bool active = JsonGetBool(json, "active", true);
            if (act.Active != active) {
                Log("Updating active status for " + name);
                if (!dryRun) API::SetActivityStatus(State::SelectedClub.Id, actId, active);
            }
            if (act.FolderId != folderId) {
                Log("Moving " + name + " to folder " + folderId);
                if (!dryRun) API::MoveActivity(State::SelectedClub.Id, actId, folderId);
            }
        }

        if (actId > 0 && json.HasKey("subscription")) {
            ApplySubscription(actId, name, json["subscription"]);
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

    void ApplySubscription(uint activityId, const string &in activityName, Json::Value@ json) {
        Log("Applying subscription for: " + activityName);
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
        if (!dryRun) Subscriptions::Add(sub);
        else Log("Dry Run: Skipping subscription persistence.");
    }
}
