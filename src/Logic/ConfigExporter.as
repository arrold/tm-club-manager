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
                    rootActivities.Add(ExportActivity(items[i], items));
                }
            }
        }

        if (rootActivities.Length > 0) config["activities"] = rootActivities;
        if (folders.Length > 0) config["folders"] = folders;

        // Standardise filename: lowercase_with_underscores.json
        string rawName = State::SelectedClub.Name;
        string filename = "";
        for (int i = 0; i < rawName.Length; i++) {
            string c = rawName.SubStr(i, 1);
            if (c == " " || c == "/" || c == "\\" || c == ":" || c == "-") filename += "_";
            else filename += c.ToLower();
        }
        filename += ".json";
        
        Json::ToFile(IO::FromStorageFolder(filename), config);
        UI::ShowNotification("Exporter", "Club structure exported to " + filename, vec4(0, 0.8, 0, 1), 7000);
    }

    Json::Value@ ExportFolder(Activity@ f, Activity@[]@ all) {
        Json::Value@ json = Json::Object();
        json["name"] = f.Name;
        json["active"] = f.Active;
        json["featured"] = f.Featured;
        json["public"] = f.Public;
        if (f.Description != "") json["description"] = f.Description;
        Json::Value@ activities = Json::Array();
        for (uint i = 0; i < all.Length; i++) {
            if (all[i].FolderId == f.Id) {
                if (all[i].Type == "folder") {
                    activities.Add(ExportFolder(all[i], all)); // Recursive crawl
                } else {
                    activities.Add(ExportActivity(all[i], all));
                }
            }
        }
        json["activities"] = activities;
        return json;
    }

    Json::Value@ ExportActivity(Activity@ a, Activity@[]@ all) {
        Json::Value@ json = Json::Object();
        json["name"] = a.Name;
        json["type"] = a.Type;
        json["active"] = a.Active;
        json["featured"] = a.Featured;
        json["public"] = a.Public;
        if (a.Description != "") json["description"] = a.Description;
        
        if (a.Type == "news") {
            json["headline"] = a.Headline;
            json["body"] = a.Body;
        }

        if (a.Type == "room" && a.MirrorCampaignId > 0) {
            // Find the campaign name by ID in the list of all activities
            string mirrorName = "";
            for (uint i = 0; i < all.Length; i++) {
                if (all[i].Type == "campaign" && all[i].CampaignId == a.MirrorCampaignId) {
                    mirrorName = all[i].Name;
                    break;
                }
            }
            if (mirrorName != "") {
                json["mirrorCampaignName"] = mirrorName;
            } else {
                // Fallback to ID if not found in current list (unlikely within club)
                json["mirrorCampaignId"] = a.MirrorCampaignId;
            }
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
