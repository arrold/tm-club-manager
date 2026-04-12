// CustomTags.as - User-defined local tags for map categorization
// Tags are stored in custom_tags.json and applied per-map in metadata_overrides.json.
// They are purely local and invisible to TMX; filtering is client-side only.

namespace CustomTags {
    string[] tagNames;
    bool loaded = false;

    string GetStoragePath() {
        return IO::FromStorageFolder("custom_tags.json");
    }

    void Load() {
        if (loaded) return;
        string path = GetStoragePath();
        if (IO::FileExists(path)) {
            Json::Value@ json = Json::FromFile(path);
            if (json !is null && json.GetType() == Json::Type::Array) {
                for (uint i = 0; i < json.Length; i++) {
                    tagNames.InsertLast(string(json[i]));
                }
            }
        }
        loaded = true;
    }

    void Save() {
        Json::Value@ json = Json::Array();
        for (uint i = 0; i < tagNames.Length; i++) {
            json.Add(tagNames[i]);
        }
        Json::ToFile(GetStoragePath(), json);
    }

    bool Exists(const string &in name) {
        Load();
        return tagNames.Find(name) >= 0;
    }

    void Create(const string &in name) {
        Load();
        if (name.Trim() == "" || Exists(name)) return;
        tagNames.InsertLast(name.Trim());
        Save();
    }

    // Removes the tag definition and strips it from every map that had it applied.
    void Delete(const string &in name) {
        Load();
        int idx = tagNames.Find(name);
        if (idx < 0) return;
        tagNames.RemoveAt(idx);
        Save();
        MetadataOverrides::RemoveCustomTagFromAll(name);
    }

    string[] GetAll() {
        Load();
        return tagNames;
    }
}
