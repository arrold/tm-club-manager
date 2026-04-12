// Tabs/GlobalOverridesTab.as - Centralized management for 'The Void' overrides

class GlobalOverridesTab : Tab {
    string newCustomTagName = "";

    GlobalOverridesTab() {
        super("Overrides", Icons::Shield);
    }

    void DrawInner() override {
        UI::Text("\\$f80" + Icons::Shield + "\\$z Global Metadata Overrides");
        UI::TextDisabled("Maps listed here have manual reclassifications that differ from TMX defaults.");
        UI::TextDisabled("Select a club in the Clubs tab to populate and refresh map names.");
        UI::SameLine();
        if (UI::Button(Icons::Refresh + " Sync Metadata##globalsync")) {
            startnew(MetadataOverrides::SyncMapData);
        }
        if (UI::IsItemHovered()) UI::SetTooltip("Re-fetch TMX data for all global overrides (updates award/download counts for sorting)");
        UI::Separator();

        if (UI::BeginTable("OverridesTable", 6, UI::TableFlags::Resizable | UI::TableFlags::RowBg)) {
            UI::TableSetupColumn("Map Name", UI::TableColumnFlags::WidthStretch);
            UI::TableSetupColumn("UID", UI::TableColumnFlags::WidthFixed, 200);
            UI::TableSetupColumn("Difficulty", UI::TableColumnFlags::WidthFixed, 120);
            UI::TableSetupColumn("Surface", UI::TableColumnFlags::WidthFixed, 120);
            UI::TableSetupColumn("Cached", UI::TableColumnFlags::WidthFixed, 50);
            UI::TableSetupColumn("Actions", UI::TableColumnFlags::WidthFixed, 80);
            UI::TableHeadersRow();

            string[] uids = MetadataOverrides::data.GetKeys();
            for (uint i = 0; i < uids.Length; i++) {
                string uid = uids[i];
                Json::Value@ ovr = MetadataOverrides::data[uid];

                UI::TableNextRow();
                UI::TableNextColumn();
                if (AuditCache::IsKnown(uid)) {
                    UI::Text(AuditCache::GetName(uid));
                } else {
                    UI::TextDisabled(AuditCache::GetName(uid));
                    AuditCache::TriggerEagerLoad(uid);
                }
                UI::TableNextColumn();
                UI::Text(uid);
                UI::TableNextColumn();
                UI::Text(ovr.HasKey("DifficultyName") ? string(ovr["DifficultyName"]) : "-");
                UI::TableNextColumn();
                if (ovr.HasKey("Tags") && ovr["Tags"].GetType() == Json::Type::Array && ovr["Tags"].Length > 0) {
                    UI::Text(string(ovr["Tags"][0]));
                } else {
                    UI::Text("-");
                }
                UI::TableNextColumn();
                UI::Text(ovr.HasKey("MapData") ? "\\$8f8" + Icons::Check : "\\$f44" + Icons::Times);
                if (UI::IsItemHovered()) UI::SetTooltip(ovr.HasKey("MapData") ? "Map metadata cached, smart-include active" : "No metadata - set override again or Sync to enable smart-include");
                UI::TableNextColumn();
                if (UI::Button(Icons::Refresh + "##res" + i)) {
                    MetadataOverrides::Reset(uid);
                }
                if (UI::IsItemHovered()) UI::SetTooltip("Reset to Default");
            }
            UI::EndTable();
        }

        if (MetadataOverrides::data.GetKeys().Length == 0) {
            UI::TextDisabled("No active overrides found.");
        }

        UI::Separator();
        UI::Text("\\$f80" + Icons::Tag + "\\$z Custom Tags");
        UI::TextDisabled("User-defined tags applied locally to maps. Use them as include/exclude filters in the TMX search.");

        // Create new tag
        UI::PushItemWidth(220);
        newCustomTagName = UI::InputText("##newCustomTag", newCustomTagName);
        UI::PopItemWidth();
        UI::SameLine();
        if (UI::Button(Icons::Plus + " Create Tag")) {
            string trimmed = newCustomTagName.Trim();
            if (trimmed != "" && !CustomTags::Exists(trimmed)) {
                CustomTags::Create(trimmed);
                newCustomTagName = "";
            }
        }
        if (UI::IsItemHovered()) UI::SetTooltip("Create a new custom tag with this name");

        string[] customTagList = CustomTags::GetAll();
        if (customTagList.Length == 0) {
            UI::TextDisabled("No custom tags defined yet.");
        } else {
            if (UI::BeginTable("CustomTagsTable", 2, UI::TableFlags::RowBg)) {
                UI::TableSetupColumn("Tag Name", UI::TableColumnFlags::WidthStretch);
                UI::TableSetupColumn("Actions", UI::TableColumnFlags::WidthFixed, 80);
                UI::TableHeadersRow();
                for (uint i = 0; i < customTagList.Length; i++) {
                    UI::TableNextRow();
                    UI::TableNextColumn();
                    UI::Text(customTagList[i]);
                    UI::TableNextColumn();
                    if (UI::Button(Icons::Trash + "##delct" + i)) {
                        CustomTags::Delete(customTagList[i]);
                    }
                    if (UI::IsItemHovered()) UI::SetTooltip("Delete tag '" + customTagList[i] + "' and remove it from all maps");
                }
                UI::EndTable();
            }
        }
    }
}
