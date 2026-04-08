// Logic/MetadataOverride.as - Global Map reclassification storage

namespace MetadataOverrides {
    Json::Value@ data = Json::Object();
    bool loaded = false;

    string GetStoragePath() {
        return IO::FromStorageFolder("metadata_overrides.json");
    }

    void Load() {
        if (loaded) return;
        string path = GetStoragePath();
        if (IO::FileExists(path)) {
            @data = Json::FromFile(path);
        }
        loaded = true;
    }

    void Save() {
        Json::ToFile(GetStoragePath(), data);
    }

    void Reset(const string &in uid, TmxMap@ map = null) {
        Load();
        if (data.HasKey(uid)) {
            data.Remove(uid);
            Save();
        }
        if (map !is null && map.Uid == uid) {
            RevertMapToDefault(map);
        } else {
            // Try to find the map in current results and favorites to live-update
            for (uint i = 0; i < State::tmxSearchResults.Length; i++) {
                if (State::tmxSearchResults[i].Uid == uid) RevertMapToDefault(State::tmxSearchResults[i]);
            }
            for (uint i = 0; i < State::Favorites.Length; i++) {
                if (State::Favorites[i].Uid == uid) RevertMapToDefault(State::Favorites[i]);
            }
        }
    }

    // Since we don't store original TMX metadata, we "re-intercept" 
    // but without the override record it will just stay as is.
    // Wait! A better way is to actually re-parse the TMX data if we had it.
    // Since we don't, we recommend a refresh for "Reset".
    void RevertMapToDefault(TmxMap@ map) {
        if (map is null) return;
        // This is a bit of a hack: we can't easily get the original TMX data 
        // without a re-fetch, so we notify the user.
        UI::ShowNotification("Metadata Reset", "Map " + map.Name + " reset. Performance search refresh to see TMX defaults.");
    }

    void SetDifficulty(const string &in uid, int difficulty, TmxMap@ map = null) {
        Load();
        if (!data.HasKey(uid)) data[uid] = Json::Object();
        data[uid]["Difficulty"] = difficulty;
        if (difficulty > 0 && difficulty <= int(TMX::DIFFICULTY_NAMES.Length)) {
            data[uid]["DifficultyName"] = TMX::DIFFICULTY_NAMES[difficulty - 1];
        }
        if (map !is null) {
            data[uid]["IsTOTD"] = map.IsTOTD;
            data[uid]["MapData"] = map.ToJson();
        }
        Save();
        // Fire a background lookup to correct IsTOTD from the API
        State::pendingTotdSyncUid = uid;
        startnew(UpdateTotdForNewOverride);
    }

    void UpdateTotdForNewOverride() {
        string uid = State::pendingTotdSyncUid;
        if (uid == "") return;
        string[] uids = { uid };
        TmxMap@[] maps = TMX::GetMapsByUids(uids);
        SupplementLengths(maps);
        if (maps.Length > 0) {
            Load();
            if (data.HasKey(uid)) {
                data[uid]["IsTOTD"] = maps[0].IsTOTD;
                if (data[uid].HasKey("MapData")) data[uid]["MapData"] = maps[0].ToJson();
                Save();
            }
        }
    }

    // Fills in LengthSecs for any maps where TMX returned 0, using the Nadeo authorScore field.
    void SupplementLengths(TmxMap@[]@ maps) {
        string[] missing;
        for (uint i = 0; i < maps.Length; i++) {
            if (maps[i].LengthSecs == 0) missing.InsertLast(maps[i].Uid);
        }
        if (missing.Length == 0) return;

        while (!NadeoServices::IsAuthenticated("NadeoLiveServices")) yield();
        Json::Value@ resp = API::GetMapsInfo(missing);
        if (resp is null) return;
        Json::Value@ list = null;
        if (resp.GetType() == Json::Type::Array) @list = resp;
        else if (resp.HasKey("mapList")) @list = resp["mapList"];
        if (list is null) return;

        for (uint i = 0; i < list.Length; i++) {
            string nadeoUid = JsonGetString(list[i], "uid");
            uint score = JsonGetUint(list[i], "authorTime");
            if (nadeoUid == "" || score == 0) continue;
            for (uint j = 0; j < maps.Length; j++) {
                if (maps[j].Uid == nadeoUid && maps[j].LengthSecs == 0) {
                    maps[j].LengthSecs = score / 1000;
                    break;
                }
            }
        }
    }

    void StoreMapData(const string &in uid, TmxMap@ map) {
        Load();
        if (!data.HasKey(uid)) return; // Only store if override already exists
        data[uid]["MapData"] = map.ToJson();
        Save();
    }

    TmxMap@ GetCachedMap(const string &in uid) {
        Load();
        if (!data.HasKey(uid) || !data[uid].HasKey("MapData")) return null;
        TmxMap@ map = TmxMap(data[uid]["MapData"]);
        // Prefer top-level IsTOTD (set at override time) over whatever is in MapData
        map.IsTOTD = JsonGetBool(data[uid], "IsTOTD", map.IsTOTD);
        return map;
    }

    void SetName(const string &in uid, const string &in name) {
        Load();
        if (!data.HasKey(uid)) data[uid] = Json::Object();
        data[uid]["Name"] = name;
        Save();
    }

    void AddExtraTag(const string &in uid, const string &in tag) {
        Load();
        if (!data.HasKey(uid)) data[uid] = Json::Object();
        // Build the updated ExtraTags array, avoiding duplicates
        Json::Value@ existing = data[uid].HasKey("ExtraTags") ? data[uid]["ExtraTags"] : Json::Array();
        for (uint i = 0; i < existing.Length; i++) {
            if (string(existing[i]) == tag) return; // already present
        }
        existing.Add(tag);
        data[uid]["ExtraTags"] = existing;
        Save();
    }

    void RemoveExtraTag(const string &in uid, const string &in tag) {
        Load();
        if (!data.HasKey(uid) || !data[uid].HasKey("ExtraTags")) return;
        Json::Value@ updated = Json::Array();
        Json::Value@ existing = data[uid]["ExtraTags"];
        for (uint i = 0; i < existing.Length; i++) {
            if (string(existing[i]) != tag) updated.Add(string(existing[i]));
        }
        data[uid]["ExtraTags"] = updated;
        // Clean up the override entry entirely if nothing remains
        if (updated.Length == 0 && !data[uid].HasKey("Name") && !data[uid].HasKey("Difficulty") && !data[uid].HasKey("Tags")) {
            data.Remove(uid);
        }
        Save();
    }

    void SetTags(const string &in uid, string[]@ tags) {
        Load();
        if (!data.HasKey(uid)) data[uid] = Json::Object();
        Json::Value@ tagsArr = Json::Array();
        for (uint i = 0; i < tags.Length; i++) tagsArr.Add(tags[i]);
        data[uid]["Tags"] = tagsArr;
        Save();
    }

    // Returns all UIDs that have a difficulty override AND cached map data
    string[] GetUidsWithCachedMap() {
        Load();
        string[] result;
        string[] uids = data.GetKeys();
        for (uint i = 0; i < uids.Length; i++) {
            if (data[uids[i]].HasKey("Difficulty") && data[uids[i]].HasKey("MapData")) {
                result.InsertLast(uids[i]);
            }
        }
        return result;
    }

    void SyncMapData() {
        Load();
        string[] uids = data.GetKeys();
        string[] toSync;
        for (uint i = 0; i < uids.Length; i++) {
            if (data[uids[i]].HasKey("Difficulty")) toSync.InsertLast(uids[i]);
        }
        if (toSync.Length == 0) { Notify("No global overrides to sync."); return; }
        Notify("Syncing metadata for " + toSync.Length + " global override(s)...");
        uint synced = 0;
        for (uint i = 0; i < toSync.Length; i += 10) {
            string[] batch;
            for (uint j = i; j < i + 10 && j < toSync.Length; j++) batch.InsertLast(toSync[j]);
            TmxMap@[] maps = TMX::GetMapsByUids(batch);
            SupplementLengths(maps);
            for (uint j = 0; j < maps.Length; j++) {
                if (data.HasKey(maps[j].Uid)) {
                    data[maps[j].Uid]["MapData"] = maps[j].ToJson();
                    synced++;
                }
            }
            yield();
        }
        Save();
        Notify("Global override metadata synced: " + synced + "/" + toSync.Length + " maps updated.");
    }

    void Intercept(TmxMap@ map) {
        if (map is null || map.Uid == "") return;
        Load();

        if (data.HasKey(map.Uid)) {
        Json::Value@ override = data[map.Uid];
        if (override.HasKey("Name")) {
            map.Name = string(override["Name"]);
        }
        if (override.HasKey("Difficulty")) {
            map.Difficulty = int(override["Difficulty"]);
        }
        if (override.HasKey("DifficultyName")) {
            map.DifficultyName = string(override["DifficultyName"]);
        }
        if (override.HasKey("Tags") && override["Tags"].GetType() == Json::Type::Array) {
            map.Tags.RemoveRange(0, map.Tags.Length);
            for (uint i = 0; i < override["Tags"].Length; i++) {
                map.Tags.InsertLast(string(override["Tags"][i]));
            }
        }
        if (override.HasKey("ExtraTags") && override["ExtraTags"].GetType() == Json::Type::Array) {
            for (uint i = 0; i < override["ExtraTags"].Length; i++) {
                string extraTag = string(override["ExtraTags"][i]);
                if (map.Tags.Find(extraTag) < 0) {
                    map.Tags.InsertLast(extraTag);
                }
            }
        }
        } // end global override block

        // Layer club-specific override on top of global (club always wins)
        if (State::SelectedClub !is null) {
            Json::Value@ clubOvr = ClubOverrides::GetOverride(State::SelectedClub.Id, map.Uid);
            if (clubOvr !is null) {
                if (clubOvr.HasKey("Difficulty")) map.Difficulty = int(clubOvr["Difficulty"]);
                if (clubOvr.HasKey("DifficultyName")) map.DifficultyName = string(clubOvr["DifficultyName"]);
            }
        }
    }

    void RenderOverrideMenu(TmxMap@ map) {
        if (UI::BeginPopupContextItem("OverrideMenu" + map.Uid)) {
            UI::TextDisabled("Global Override");
            UI::Separator();

            if (UI::BeginMenu(Icons::ClockO + " Set Difficulty")) {
                for (uint d = 0; d < TMX::DIFFICULTY_NAMES.Length; d++) {
                    bool selected = map.Difficulty == int(d + 1);
                    if (UI::MenuItem(TMX::DIFFICULTY_NAMES[d], "", selected)) {
                        SetDifficulty(map.Uid, d + 1, map);
                        SetName(map.Uid, map.Name);
                        map.Difficulty = d + 1;
                        map.DifficultyName = TMX::DIFFICULTY_NAMES[d];
                    }
                }
                UI::EndMenu();
            }

            if (State::SelectedClub !is null) {
                if (UI::BeginMenu(Icons::BuildingO + " Override for " + State::SelectedClub.Name)) {
                    UI::TextDisabled("Club-Specific Difficulty");
                    UI::Separator();
                    for (uint d = 0; d < TMX::DIFFICULTY_NAMES.Length; d++) {
                        Json::Value@ clubOvr = ClubOverrides::GetOverride(State::SelectedClub.Id, map.Uid);
                        bool selected = clubOvr !is null && clubOvr.HasKey("Difficulty") && int(clubOvr["Difficulty"]) == int(d + 1);
                        if (UI::MenuItem(TMX::DIFFICULTY_NAMES[d], "", selected)) {
                            ClubOverrides::SetDifficulty(State::SelectedClub.Id, map.Uid, d + 1, map);
                            map.Difficulty = d + 1;
                            map.DifficultyName = TMX::DIFFICULTY_NAMES[d];
                        }
                    }
                    UI::Separator();
                    if (UI::MenuItem(Icons::Refresh + " Reset Club Override")) {
                        ClubOverrides::Reset(State::SelectedClub.Id, map.Uid);
                    }
                    UI::EndMenu();
                }
            }

            if (UI::BeginMenu(Icons::Tag + " Set Primary Surface")) {
                string currentPrimary = map.PrimarySurface;
                for (uint s = 0; s < TMX::SURFACE_TAGS.Length; s++) {
                    string surface = TMX::SURFACE_TAGS[s];
                    bool isPrimary = (surface == currentPrimary);
                    if (UI::MenuItem(surface, "", isPrimary)) {
                        string[] newTags;
                        newTags.InsertLast(surface); // New primary surface goes first
                        for (uint j = 0; j < map.Tags.Length; j++) {
                            // Keep all other tags (including other surfaces - they are demoted, not removed)
                            if (map.Tags[j] != surface) {
                                newTags.InsertLast(map.Tags[j]);
                            }
                        }
                        SetTags(map.Uid, newTags);
                        SetName(map.Uid, map.Name); // Ensure name is stored when editing Tags
                        map.Tags = newTags;
                    }
                }
                UI::EndMenu();
            }

            if (UI::BeginMenu(Icons::PlusCircle + " Add Tag")) {
                for (uint t = 0; t < TMX::TAG_NAMES.Length; t++) {
                    string tag = TMX::TAG_NAMES[t];
                    if (map.Tags.Find(tag) >= 0) continue; // already on this map
                    if (UI::MenuItem(tag)) {
                        AddExtraTag(map.Uid, tag);
                        SetName(map.Uid, map.Name);
                        map.Tags.InsertLast(tag);
                    }
                }
                UI::EndMenu();
            }

            // Show removable extra tags (only tags added via override)
            Json::Value@ ovr = data.HasKey(map.Uid) ? data[map.Uid] : null;
            if (ovr !is null && ovr.HasKey("ExtraTags") && ovr["ExtraTags"].GetType() == Json::Type::Array && ovr["ExtraTags"].Length > 0) {
                if (UI::BeginMenu(Icons::MinusCircle + " Remove Added Tag")) {
                    for (uint t = 0; t < ovr["ExtraTags"].Length; t++) {
                        string tag = string(ovr["ExtraTags"][t]);
                        if (UI::MenuItem(tag)) {
                            RemoveExtraTag(map.Uid, tag);
                            int idx = map.Tags.Find(tag);
                            if (idx >= 0) map.Tags.RemoveAt(idx);
                        }
                    }
                    UI::EndMenu();
                }
            }

            UI::Separator();
            if (Denylist::IsExcluded(map.Uid)) {
                if (UI::MenuItem(Icons::Check + " Remove from Denylist")) {
                    Denylist::Remove(map.Uid);
                }
            } else {
                if (UI::MenuItem(Icons::Ban + " Add to Denylist")) {
                    Denylist::Add(map.Uid);
                }
            }

            UI::Separator();
            if (UI::MenuItem(Icons::Refresh + " Reset to Default")) {
                Reset(map.Uid, map);
            }

            UI::EndPopup();
        }
    }
    
    void SyncAllNames() {
        Load();
        string[] uids = data.GetKeys();
        string[] toFetch;
        for (uint i = 0; i < uids.Length; i++) {
            if (!data[uids[i]].HasKey("Name") || JsonGetString(data[uids[i]], "Name").Trim() == "") {
                toFetch.InsertLast(uids[i]);
            }
        }

        if (toFetch.Length == 0) {
            // trace("[Metadata Sync] No names missing for " + uids.Length + " overrides.");
            return;
        }

        trace("[Metadata Sync] Waiting for authentication to resolve " + toFetch.Length + " map names...");
        while (!NadeoServices::IsAuthenticated("NadeoLiveServices")) yield();

        uint updatedCount = 0;
        // Fetch in batches of 25 (safer URL length for Nadeo API)
        for (uint i = 0; i < toFetch.Length; i += 25) {
            string[] batch;
            for (uint j = i; j < i + 25 && j < toFetch.Length; j++) batch.InsertLast(toFetch[j]);
            
            trace("[Metadata Sync] Requesting batch " + (i/25 + 1) + " (" + batch.Length + " maps)...");
            Json::Value@ results = API::GetMapsInfo(batch);
            if (results !is null) {
                Json::Value@ list = results.GetType() == Json::Type::Array ? results : (results.HasKey("mapList") ? results["mapList"] : null);
                if (list !is null && list.GetType() == Json::Type::Array) {
                    if (list.Length > 0) {
                        trace("[Metadata Sync] First item keys: " + string::Join(list[0].GetKeys(), ", "));
                    }
                    for (uint k = 0; k < list.Length; k++) {
                        string uid = JsonGetString(list[k], "mapUid");
                        if (uid == "") uid = JsonGetString(list[k], "uid"); // Fallback
                        string name = Text::StripFormatCodes(JsonGetString(list[k], "name"));
                        if (name == "") name = Text::StripFormatCodes(JsonGetString(list[k], "mapName")); // Fallback
                        if (uid != "" && name != "") {
                            if (data.HasKey(uid)) {
                                data[uid]["Name"] = name;
                                updatedCount++;
                            }
                        }
                    }
                } else {
                    warn("[Metadata Sync] Error: API returned unexpected structure: " + Json::Write(results));
                }
            } else {
                warn("[Metadata Sync] API::GetMapsInfo returned null for batch starting at " + i);
            }
            yield();
        }
        
        if (updatedCount > 0) {
            Save();
            Notify("Metadata Sync complete. " + updatedCount + " names updated.");
            trace("[Metadata Sync] Successfully updated " + updatedCount + " map names.");
        } else {
            trace("[Metadata Sync] Finished. No names were updated (API mismatch or all valid).");
        }
    }
}
