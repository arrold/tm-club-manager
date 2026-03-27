// Logic/AuditCache.as - Global Map metadata cache for UI resolution

namespace AuditCache {
    dictionary cache;
    string[] pendingLoads;
    bool isEagerLoading = false;

    void Init() {
        if (MetadataOverrides::data is null) return;
        string[]@ keys = MetadataOverrides::data.GetKeys();
        for (uint i = 0; i < keys.Length; i++) {
            TriggerEagerLoad(keys[i]);
        }
    }

    void Register(TmxMap@ map) {
        if (map is null || map.Uid == "") return;
        cache[map.Uid] = map.Name;
    }

    void Register(MapInfo@ map) {
        if (map is null || map.Uid == "") return;
        cache[map.Uid] = map.Name;
    }

    string GetName(const string &in uid) {
        if (cache.Exists(uid)) {
            return string(cache[uid]);
        }
        if (pendingLoads.Find(uid) >= 0) {
            return "Resolving: " + uid.SubStr(0, 8) + "...";
        }
        return "Map: " + uid.SubStr(0, 8) + "...";
    }

    bool IsKnown(const string &in uid) {
        return cache.Exists(uid);
    }

    void TriggerEagerLoad(const string &in uid) {
        if (IsKnown(uid)) return;
        if (pendingLoads.Find(uid) >= 0) return;

        pendingLoads.InsertLast(uid);
        if (!isEagerLoading) {
            startnew(RunEagerLoad);
        }
    }

    void RunEagerLoad() {
        isEagerLoading = true;
        while (pendingLoads.Length > 0) {
            string[] batch;
            for (uint i = 0; i < 50 && pendingLoads.Length > 0; i++) {
                batch.InsertLast(pendingLoads[0]);
                pendingLoads.RemoveAt(0);
            }

            // trace("[AuditCache] Eager loading metadata for " + batch.Length + " maps...");
            Json::Value@ resp = API::GetMapsInfo(batch);
            if (resp !is null) {
                Json::Value@ list = null;
                if (resp.GetType() == Json::Type::Array) @list = resp;
                else if (resp.HasKey("mapList")) @list = resp["mapList"];

                if (list !is null) {
                    for (uint i = 0; i < list.Length; i++) {
                        TmxMap m(list[i]);
                        if (m.Uid != "") {
                            cache[m.Uid] = m.Name;
                        }
                    }
                }
            }
            yield();
        }
        isEagerLoading = false;
    }
}
