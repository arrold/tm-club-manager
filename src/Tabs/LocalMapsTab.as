// Tabs/LocalMapsTab.as - Local Maps Browser (Zertrov Style)

class LocalMapsTab : Tab {
    bool selectAll = false;

    LocalMapsTab() {
        super("Local Maps", Icons::FolderOpenO);
    }

    void DrawInner() override {
        if (State::SelectedClub is null) {
            UI::TextDisabled("Select a club in the 'Clubs' tab first.");
            return;
        }

        if (State::PersonalTracksProxy is null) {
            @State::PersonalTracksProxy = Activity();
            State::PersonalTracksProxy.Id = 0xFFFFFFFF;
            State::PersonalTracksProxy.Name = "Nadeo Personal Tracks (Upload Only)";
            State::PersonalTracksProxy.Type = "personal";
        }

        UI::BeginGroup();
        UI::Text("Target Activity:");
        UI::SameLine();
        if (UI::BeginCombo("##target_act_local", State::TargetActivity is null ? "None" : State::TargetActivity.Name)) {
            if (UI::Selectable(State::PersonalTracksProxy.Name, State::TargetActivity !is null && State::TargetActivity.Id == State::PersonalTracksProxy.Id)) {
                @State::TargetActivity = State::PersonalTracksProxy;
            }
            for (uint i = 0; i < State::ClubActivities.Length; i++) {
                if (State::ClubActivities[i].Type == "campaign" || State::ClubActivities[i].Type == "room") {
                    if (UI::Selectable(State::ClubActivities[i].Name, State::TargetActivity !is null && State::TargetActivity.Id == State::ClubActivities[i].Id)) {
                        @State::TargetActivity = State::ClubActivities[i];
                    }
                }
            }
            UI::EndCombo();
        }
        UI::EndGroup();

        UI::Separator();

        if (UI::Button(Icons::Refresh + " Refresh Local Maps")) {
            startnew(RefreshLocalMaps);
        }
        UI::SameLine();
        UI::BeginDisabled(State::TargetActivity is null);
        if (UI::Button(Icons::Plus + " Add Selected to " + (State::TargetActivity !is null ? State::TargetActivity.Name : "Activity"))) {
            startnew(DoAddSelectedLocalMaps);
        }
        UI::EndDisabled();

        UI::Separator();

        if (State::refreshingLocalMaps) {
            UI::TextDisabled("Indexing maps... " + State::localMapsCount + " found");
            return;
        }

        if (State::LocalMaps.Length == 0) {
            UI::TextDisabled("No maps found in Documents/Trackmania/Maps/");
            UI::TextDisabled("Try clicking 'Refresh' above.");
            return;
        }

        if (UI::BeginTable("LocalMapsList", 5, UI::TableFlags::RowBg | UI::TableFlags::ScrollY | UI::TableFlags::Resizable)) {
            UI::TableSetupColumn("##sel", UI::TableColumnFlags::WidthFixed, 25);
            UI::TableSetupColumn("S", UI::TableColumnFlags::WidthFixed, 25);
            UI::TableSetupColumn("Map Name");
            UI::TableSetupColumn("Filename");
            UI::TableSetupColumn("Actions", UI::TableColumnFlags::WidthFixed, 120);
            
            // Header row with "Select All"
            UI::TableNextRow(UI::TableRowFlags::Headers);
            UI::TableNextColumn();
            if (UI::Checkbox("##sel_all", selectAll)) {
                for (uint i = 0; i < State::LocalMaps.Length; i++) {
                    if (State::LocalMaps[i] !is null) State::LocalMaps[i].Selected = selectAll;
                }
            }
            UI::TableNextColumn(); UI::Text("S");
            UI::TableNextColumn(); UI::Text("Map Name");
            UI::TableNextColumn(); UI::Text("Filename");
            UI::TableNextColumn(); UI::Text("Actions");

            for (uint i = 0; i < State::LocalMaps.Length; i++) {
                auto@ m = State::LocalMaps[i];
                // Only show if validated in editor (playable).
                if (m.Uid == "" || !m.IsValidated) continue;

                UI::TableNextRow();
                UI::TableNextColumn();
                m.Selected = UI::Checkbox("##sel_" + i, m.Selected);

                UI::TableNextColumn(); 
                if (m.IsUploaded) {
                    UI::Text(Icons::CloudUpload);
                    if (UI::IsItemHovered()) UI::SetTooltip("Uploaded to Nadeo");
                } else if (m.IsValidated) {
                    UI::Text(Icons::Check);
                    if (UI::IsItemHovered()) UI::SetTooltip("Validated in Editor");
                } else {
                    UI::TextDisabled(Icons::ExclamationTriangle);
                    if (UI::IsItemHovered()) UI::SetTooltip("Not Validated (Editor)");
                }

                UI::TableNextColumn(); UI::Text(m.Name);
                UI::TableNextColumn(); UI::TextDisabled(m.Filename);
                UI::TableNextColumn();
                UI::BeginDisabled(State::TargetActivity is null);
                if (UI::Button("Add##" + i)) {
                    startnew(DoAddLocalMap, m);
                }
                UI::EndDisabled();
            }
            UI::EndTable();
        }
    }
}
