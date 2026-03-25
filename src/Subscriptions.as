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
        if (sub.ClubId == 0 && State::SelectedClub !is null) sub.ClubId = State::SelectedClub.Id;
        auto existing = GetByActivity(sub.ActivityId);
        if (existing !is null) {
            // Update existing
            @existing.Filters = sub.Filters;
            existing.MapLimit = sub.MapLimit;
            existing.ActivityName = sub.ActivityName;
            existing.ClubId = sub.ClubId;
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

    void CleanupOrphans() {
        if (State::SelectedClub is null) {
            UI::ShowNotification("Club Manager", "Select a club first to clean up its orphaned subscriptions.");
            return;
        }

        uint removed = 0;
        uint currentClubId = State::SelectedClub.Id;
        
        for (int i = int(All.Length) - 1; i >= 0; i--) {
            // Only clean up subscriptions belonging to the current club
            if (All[i].ClubId != currentClubId) continue;

            bool found = false;
            for (uint j = 0; j < State::ClubActivities.Length; j++) {
                if (State::ClubActivities[j].Id == All[i].ActivityId) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                trace("Removing orphaned subscription for activity " + All[i].ActivityId + " (" + All[i].ActivityName + ") in club " + currentClubId);
                All.RemoveAt(i);
                removed++;
            }
        }
        if (removed > 0) {
            Save();
            UI::ShowNotification("Club Manager", "Removed " + removed + " orphaned subscription(s) for this club.");
        } else {
            UI::ShowNotification("Club Manager", "No orphaned subscriptions found for the current club.");
        }
    }
}


