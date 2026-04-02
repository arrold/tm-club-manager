// Logic/ClubOverrides.as - Per-club map difficulty overrides

namespace ClubOverrides {
    Json::Value@ data = Json::Object();
    bool loaded = false;

    string GetStoragePath() {
        return IO::FromStorageFolder("club_overrides.json");
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

    void SetDifficulty(uint clubId, const string &in uid, int difficulty, TmxMap@ map = null) {
        Load();
        string key = tostring(clubId);
        if (!data.HasKey(key)) data[key] = Json::Object();
        if (!data[key].HasKey(uid)) data[key][uid] = Json::Object();
        data[key][uid]["Difficulty"] = difficulty;
        if (difficulty > 0 && difficulty <= int(TMX::DIFFICULTY_NAMES.Length)) {
            data[key][uid]["DifficultyName"] = TMX::DIFFICULTY_NAMES[difficulty - 1];
        }
        if (map !is null) {
            data[key][uid]["IsTOTD"] = map.IsTOTD;
            data[key][uid]["MapData"] = map.ToJson();
        }
        Save();
        // Fire a background lookup to correct IsTOTD from the API
        State::pendingTotdSyncUid = uid;
        State::pendingTotdSyncClubId = clubId;
        startnew(UpdateTotdForNewOverride);
    }

    void UpdateTotdForNewOverride() {
        string uid = State::pendingTotdSyncUid;
        uint clubId = State::pendingTotdSyncClubId;
        if (uid == "") return;
        string[] uids = { uid };
        TmxMap@[] maps = TMX::GetMapsByUids(uids);
        MetadataOverrides::SupplementLengths(maps);
        if (maps.Length > 0) {
            Load();
            string key = tostring(clubId);
            if (data.HasKey(key) && data[key].HasKey(uid)) {
                data[key][uid]["IsTOTD"] = maps[0].IsTOTD;
                if (data[key][uid].HasKey("MapData")) data[key][uid]["MapData"] = maps[0].ToJson();
                Save();
            }
        }
    }

    void StoreMapData(uint clubId, const string &in uid, TmxMap@ map) {
        Load();
        string key = tostring(clubId);
        if (!data.HasKey(key) || !data[key].HasKey(uid)) return;
        data[key][uid]["MapData"] = map.ToJson();
        Save();
    }

    TmxMap@ GetCachedMap(uint clubId, const string &in uid) {
        Load();
        string key = tostring(clubId);
        if (!data.HasKey(key) || !data[key].HasKey(uid) || !data[key][uid].HasKey("MapData")) return null;
        TmxMap@ map = TmxMap(data[key][uid]["MapData"]);
        // Prefer top-level IsTOTD (set at override time) over whatever is in MapData
        map.IsTOTD = JsonGetBool(data[key][uid], "IsTOTD", map.IsTOTD);
        return map;
    }

    // Returns all UIDs for the given club that have a difficulty override AND cached map data
    string[] GetUidsWithCachedMap(uint clubId) {
        Load();
        string key = tostring(clubId);
        string[] result;
        if (!data.HasKey(key)) return result;
        string[] uids = data[key].GetKeys();
        for (uint i = 0; i < uids.Length; i++) {
            if (data[key][uids[i]].HasKey("Difficulty") && data[key][uids[i]].HasKey("MapData")) {
                result.InsertLast(uids[i]);
            }
        }
        return result;
    }

    void SyncMapData(uint clubId) {
        Load();
        string key = tostring(clubId);
        if (!data.HasKey(key)) { Notify("No club overrides to sync."); return; }
        string[] uids = data[key].GetKeys();
        string[] toSync;
        for (uint i = 0; i < uids.Length; i++) {
            if (data[key][uids[i]].HasKey("Difficulty")) toSync.InsertLast(uids[i]);
        }
        if (toSync.Length == 0) { Notify("No club overrides to sync."); return; }
        Notify("Syncing metadata for " + toSync.Length + " club override(s)...");
        uint synced = 0;
        for (uint i = 0; i < toSync.Length; i += 10) {
            string[] batch;
            for (uint j = i; j < i + 10 && j < toSync.Length; j++) batch.InsertLast(toSync[j]);
            TmxMap@[] maps = TMX::GetMapsByUids(batch);
            MetadataOverrides::SupplementLengths(maps);
            for (uint j = 0; j < maps.Length; j++) {
                if (data[key].HasKey(maps[j].Uid)) {
                    data[key][maps[j].Uid]["MapData"] = maps[j].ToJson();
                    synced++;
                }
            }
            yield();
        }
        Save();
        Notify("Club override metadata synced: " + synced + "/" + toSync.Length + " maps updated.");
    }

    void Reset(uint clubId, const string &in uid) {
        Load();
        string key = tostring(clubId);
        if (!data.HasKey(key)) return;
        if (data[key].HasKey(uid)) {
            data[key].Remove(uid);
            if (data[key].GetKeys().Length == 0) data.Remove(key);
            Save();
        }
    }

    bool HasOverride(uint clubId, const string &in uid) {
        Load();
        string key = tostring(clubId);
        return data.HasKey(key) && data[key].HasKey(uid);
    }

    Json::Value@ GetOverride(uint clubId, const string &in uid) {
        if (!HasOverride(clubId, uid)) return null;
        return data[tostring(clubId)][uid];
    }
}
