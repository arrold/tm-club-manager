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
                            // Keep other tags that ARE NOT surfaces
                            if (!TMX::ArrayContains(TMX::SURFACE_TAGS, map.Tags[j])) {
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

            UI::Separator();
            if (UI::MenuItem(Icons::Refresh + " Reset to Default")) {
                Reset(map.Uid, map);
            }

            UI::EndPopup();
        }
    }
}
