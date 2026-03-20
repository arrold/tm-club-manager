// Club Manager - Subscriptions.as
// Handles persistence of TMX search configurations for activities

namespace Subscriptions {
    Subscription@[] All;
    bool Loaded = false;

    string GetStoragePath() {
        return IO::FromStorageFolder("subscriptions.json");
    }

    void Load() {
        if (Loaded) return;
        string path = GetStoragePath();
        if (!IO::FileExists(path)) {
            Loaded = true;
            trace("Subscriptions file not found at " + path);
            return;
        }

        auto json = Json::FromFile(path);
        if (json.GetType() == Json::Type::Array) {
            for (uint i = 0; i < json.Length; i++) {
                Subscription@ sub = Subscription(json[i]);
                if (sub.ActivityId != 0) {
                    All.InsertLast(sub);
                }
            }
        }
        Loaded = true;
        trace("Loaded " + All.Length + " subscriptions from " + path);
    }

    void Save() {
        Json::Value@ json = Json::Array();
        for (uint i = 0; i < All.Length; i++) {
            json.Add(All[i].ToJson());
        }
        Json::ToFile(GetStoragePath(), json);
        trace("Saved " + All.Length + " subscriptions.");
    }

    Subscription@ GetByActivity(uint activityId) {
        for (uint i = 0; i < All.Length; i++) {
            if (All[i].ActivityId == activityId) return All[i];
        }
        return null;
    }

    void Add(Subscription@ sub) {
        if (sub.ActivityId == 0) return;
        auto existing = GetByActivity(sub.ActivityId);
        if (existing !is null) {
            // Update existing
            @existing.Filters = sub.Filters;
            existing.MapLimit = sub.MapLimit;
            existing.ActivityName = sub.ActivityName;
        } else {
            All.InsertLast(sub);
        }
        trace("Subscription added/updated for " + sub.ActivityName + " (ID: " + sub.ActivityId + ", Page: " + sub.Filters.CurrentPage + ")");
        Save();
    }

    void Remove(uint activityId) {
        for (uint i = 0; i < All.Length; i++) {
            if (All[i].ActivityId == activityId) {
                All.RemoveAt(i);
                Save();
                return;
            }
        }
    }
}
