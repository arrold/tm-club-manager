// Logic/Denylist.as - Global Map exclusion list
// Used to skip "TemplateNoStadium" and other junk maps during audits.

namespace Denylist {
    string[] ExcludedUids;
    bool loaded = false;

    string GetStoragePath() {
        return IO::FromStorageFolder("denylist.json");
    }

    void Load() {
        if (loaded) return;
        string path = GetStoragePath();
        if (IO::FileExists(path)) {
            Json::Value@ json = Json::FromFile(path);
            if (json !is null && json.GetType() == Json::Type::Array) {
                for (uint i = 0; i < json.Length; i++) {
                    ExcludedUids.InsertLast(string(json[i]));
                }
            }
        }
        loaded = true;
    }

    void Save() {
        Json::Value@ json = Json::Array();
        for (uint i = 0; i < ExcludedUids.Length; i++) {
            json.Add(ExcludedUids[i]);
        }
        Json::ToFile(GetStoragePath(), json);
    }

    bool IsExcluded(const string &in uid) {
        Load();
        return ExcludedUids.Find(uid) >= 0;
    }

    void Add(const string &in uid) {
        Load();
        if (!IsExcluded(uid)) {
            ExcludedUids.InsertLast(uid);
            Save();
            Notify("Map added to Denylist: " + uid);
        }
    }

    void Remove(const string &in uid) {
        Load();
        int idx = ExcludedUids.Find(uid);
        if (idx >= 0) {
            ExcludedUids.RemoveAt(idx);
            Save();
            Notify("Map removed from Denylist: " + uid);
        }
    }
}
