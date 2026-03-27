// Logic/ConfigExporter.as - Export Club structure to JSON

namespace ConfigExporter {
    void Export() {
        if (State::SelectedClub is null) {
            UI::ShowNotification("Exporter", "Select a club first.");
            return;
        }

        Json::Value@ config = Json::Object();
        config["clubName"] = State::SelectedClub.Name;
        config["prune"] = false;

        Activity@[]@ items = State::ClubActivities;
        
        Json::Value@ rootActivities = Json::Array();
        Json::Value@ folders = Json::Array();

        for (uint i = 0; i < items.Length; i++) {
            if (items[i].FolderId == 0) {
                if (items[i].Type == "folder") {
                    folders.Add(ExportFolder(items[i], items));
                } else {
                    rootActivities.Add(ExportActivity(items[i]));
                }
            }
        }

        if (rootActivities.Length > 0) config["activities"] = rootActivities;
        if (folders.Length > 0) config["folders"] = folders;

        string filename = State::SelectedClub.Name + "_export.json";
        // Sanitise filename
        filename = filename.Replace("/", "_").Replace("\\", "_").Replace(":", "_");
        
        Json::ToFile(IO::FromStorageFolder(filename), config);
        UI::ShowNotification("Exporter", "Club structure exported to " + filename, vec4(0, 0.8, 0, 1), 7000);
    }

    Json::Value@ ExportFolder(Activity@ f, Activity@[]@ all) {
        Json::Value@ json = Json::Object();
        json["name"] = f.Name;
        Json::Value@ activities = Json::Array();
        for (uint i = 0; i < all.Length; i++) {
            if (all[i].FolderId == f.Id) {
                activities.Add(ExportActivity(all[i]));
            }
        }
        json["activities"] = activities;
        return json;
    }

    Json::Value@ ExportActivity(Activity@ a) {
        Json::Value@ json = Json::Object();
        json["name"] = a.Name;
        json["type"] = a.Type;
        json["active"] = a.Active;
        if (a.Type == "room" && a.MirrorCampaignId > 0) {
            json["mirrorCampaignId"] = a.MirrorCampaignId;
        }

        Subscription@ sub = Subscriptions::GetByActivity(a.Id);
        if (sub !is null) {
            Json::Value@ s = Json::Object();
            s["mapLimit"] = int(sub.MapLimit);
            if (sub.SourceType == 0) {
                s["filters"] = sub.Filters.ToExportJson();
            } else {
                s["listId"] = sub.ListId;
                s["listType"] = sub.ListType;
            }
            json["subscription"] = s;
        }
        return json;
    }
}
