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

    void SetDifficulty(const string &in uid, int difficulty) {
        Load();
        if (!data.HasKey(uid)) data[uid] = Json::Object();
        data[uid]["Difficulty"] = difficulty;
        // Also sync DifficultyName for consistency
        if (difficulty > 0 && difficulty <= int(TMX::SORT_NAMES.Length)) {
            data[uid]["DifficultyName"] = TMX::DIFFICULTY_NAMES[difficulty - 1];
        }
        Save();
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

    void Intercept(TmxMap@ map) {
        if (map is null || map.Uid == "") return;
        Load();
        if (!data.HasKey(map.Uid)) return;

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
    }

    void RenderOverrideMenu(TmxMap@ map) {
        if (UI::BeginPopupContextItem("OverrideMenu" + map.Uid)) {
            UI::TextDisabled("Global Override");
            UI::Separator();

            if (UI::BeginMenu(Icons::ClockO + " Set Difficulty")) {
                for (uint d = 0; d < TMX::DIFFICULTY_NAMES.Length; d++) {
                    bool selected = map.Difficulty == int(d + 1);
                    if (UI::MenuItem(TMX::DIFFICULTY_NAMES[d], "", selected)) {
                        SetDifficulty(map.Uid, d + 1);
                        SetName(map.Uid, map.Name); // Ensure name is stored when editing Difficulty
                        map.Difficulty = d + 1;
                        map.DifficultyName = TMX::DIFFICULTY_NAMES[d];
                    }
                }
                UI::EndMenu();
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
                            // Keep all other tags (including other surfaces — they are demoted, not removed)
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
