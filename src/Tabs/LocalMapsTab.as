// Tabs/LocalMapsTab.as - Local Maps Browser

class LocalMapsTab : Tab {
    bool selectAll = false;

    LocalMapsTab() {
        super("Local Maps", Icons::FolderOpenO);
    }

    bool showTreeView = true;

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

        if (UI::Button(Icons::Refresh + " Refresh")) {
            startnew(RefreshLocalMaps);
        }
        UI::SameLine();
        if (UI::Button((showTreeView ? Icons::List : Icons::FolderOpen) + " " + (showTreeView ? "Flat View" : "Tree View"))) {
            showTreeView = !showTreeView;
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

        if (showTreeView) {
            RenderTreeView();
        } else {
            RenderFlatView();
        }
    }

    void RenderTreeView() {
        FolderNode@ root = BuildFolderTree();
        UI::BeginChild("LocalMapsTreeScroll");
        RenderFolderNode(root);
        UI::EndChild();
    }

    FolderNode@ BuildFolderTree() {
        FolderNode@ root = FolderNode("Maps");
        for (uint i = 0; i < State::LocalMaps.Length; i++) {
            auto m = State::LocalMaps[i];
            if (m.Uid == "" || !m.IsValidated) continue;

            string path = m.Filename;
            if (path.StartsWith("Maps/")) path = path.SubStr(5);
            
            array<string> parts = path.Split("/");
            FolderNode@ current = root;
            for (uint j = 0; j < parts.Length - 1; j++) {
                @current = current.GetOrCreateSubfolder(parts[j]);
            }
            current.Maps.InsertLast(m);
        }
        root.Sort();
        return root;
    }

    void RenderFolderNode(FolderNode@ node) {
        if (node is null) return;
        
        bool isRoot = node.Name == "Maps";
        bool isOpen = isRoot;
        
        if (!isRoot) {
            isOpen = UI::TreeNode(Icons::Folder + " " + node.Name + " (" + (node.Maps.Length + node.Subfolders.Length) + ")###fn_" + node.Name);
        }

        if (isOpen) {
            for (uint i = 0; i < node.Subfolders.Length; i++) {
                RenderFolderNode(node.Subfolders[i]);
            }
            
            if (node.Maps.Length > 0) {
                if (UI::BeginTable("Table_" + node.Name, 5, UI::TableFlags::RowBg | UI::TableFlags::Resizable)) {
                    UI::TableSetupColumn("##sel", UI::TableColumnFlags::WidthFixed, 25);
                    UI::TableSetupColumn("S", UI::TableColumnFlags::WidthFixed, 25);
                    UI::TableSetupColumn("Map Name");
                    UI::TableSetupColumn("Filename");
                    UI::TableSetupColumn("Actions", UI::TableColumnFlags::WidthFixed, 60);

                    for (uint i = 0; i < node.Maps.Length; i++) {
                        RenderMapRow(node.Maps[i], i);
                    }
                    UI::EndTable();
                }
            }
            
            if (!isRoot) UI::TreePop();
        }
    }

    void RenderMapRow(LocalMap@ m, uint index) {
        UI::TableNextRow();
        UI::TableNextColumn();
        m.Selected = UI::Checkbox("##sel_" + m.Uid, m.Selected);

        UI::TableNextColumn(); 
        if (m.IsUploaded) {
            UI::Text(Icons::CloudUpload);
            if (UI::IsItemHovered()) UI::SetTooltip("Uploaded to Nadeo");
        } else {
            UI::Text(Icons::Check);
            if (UI::IsItemHovered()) UI::SetTooltip("Validated in Editor");
        }

        UI::TableNextColumn(); UI::Text(m.Name);
        UI::TableNextColumn(); UI::TextDisabled(m.Filename);
        UI::TableNextColumn();
        UI::BeginDisabled(State::TargetActivity is null);
        if (UI::Button("Add##" + m.Uid)) {
            startnew(DoAddLocalMap, m);
        }
        UI::EndDisabled();
    }

    void RenderFlatView() {
        if (UI::BeginTable("LocalMapsList", 5, UI::TableFlags::RowBg | UI::TableFlags::ScrollY | UI::TableFlags::Resizable)) {
            UI::TableSetupColumn("##sel", UI::TableColumnFlags::WidthFixed, 25);
            UI::TableSetupColumn("S", UI::TableColumnFlags::WidthFixed, 25);
            UI::TableSetupColumn("Map Name");
            UI::TableSetupColumn("Filename");
            UI::TableSetupColumn("Actions", UI::TableColumnFlags::WidthFixed, 60);
            
            UI::TableHeadersRow();

            for (uint i = 0; i < State::LocalMaps.Length; i++) {
                auto@ m = State::LocalMaps[i];
                if (m.Uid == "" || !m.IsValidated) continue;
                RenderMapRow(m, i);
            }
            UI::EndTable();
        }
    }
}
