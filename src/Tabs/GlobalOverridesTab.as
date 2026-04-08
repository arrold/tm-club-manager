// Tabs/GlobalOverridesTab.as - Centralized management for 'The Void' overrides

class GlobalOverridesTab : Tab {
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
    }
}
