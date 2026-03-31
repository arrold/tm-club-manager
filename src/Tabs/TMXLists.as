// Tabs/TMXLists.as - Local List Management UI

class TMXListsTab : Tab {
    TMXListsTab() {
        super("Local Lists", Icons::ListUl);
    }

    void DrawInner() override {
        if (State::CustomListNames.Length == 0) {
            CustomLists::Load();
        }

        if (UI::BeginTable("MainLayout", 2, UI::TableFlags::Resizable)) {
            UI::TableSetupColumn("Sidebar", UI::TableColumnFlags::WidthFixed, 200);
            UI::TableSetupColumn("Content", UI::TableColumnFlags::WidthStretch);

            UI::TableNextRow();
            UI::TableNextColumn();
            RenderSidebar();

            UI::TableNextColumn();
            RenderListContents();

            UI::EndTable();
        }
    }

    string newListName = "";
    void RenderSidebar() {
        UI::TextDisabled("Curated Lists:");
        for (uint i = 0; i < State::CustomListNames.Length; i++) {
            string name = State::CustomListNames[i];
            bool selected = State::SelectedListId == name;
            if (UI::Selectable(Icons::FolderOpen + " " + name, selected)) {
                State::SelectedListId = name;
                State::SelectedListType = "local";
                State::CustomListMaps = CustomLists::GetMaps(name);
            }
        }
        
        UI::Separator();
        if (UI::Button(Icons::Plus + " Create New List")) {
            UI::OpenPopup("NewListPopup");
        }

        if (UI::BeginPopup("NewListPopup")) {
            newListName = UI::InputText("List Name", newListName);
            if (UI::Button("Create")) {
                CustomLists::Save(newListName, {});
                newListName = "";
                UI::CloseCurrentPopup();
            }
            UI::EndPopup();
        }
    }

    void RenderListContents() {
        if (State::SelectedListId == "") {
            UI::Text("Select a list from the sidebar.");
            return;
        }

        TmxMap@[] maps = State::CustomListMaps;
        UI::Text(State::SelectedListId + " (" + maps.Length + " maps)");
        
        UI::SameLine();
        if (UI::Button(Icons::Link + " Sync to Activity")) {
            UI::OpenPopup("SyncToActivityPopup");
        }

        if (UI::BeginPopup("SyncToActivityPopup")) {
            UI::TextDisabled("Select Destination Activity:");
            if (State::ClubActivities.Length == 0) {
                UI::Text("Select a club and refresh activities first.");
            } else {
                for (uint i = 0; i < State::ClubActivities.Length; i++) {
                    Activity@ a = State::ClubActivities[i];
                    if (a.Type == "campaign" || a.Type == "room") {
                        if (UI::Selectable(a.Name + " (" + a.Type + ")", false)) {
                            Subscription sub;
                            sub.ActivityId = a.Id;
                            sub.ActivityName = a.Name;
                            sub.SourceType = 1; // Local List
                            sub.ListId = State::SelectedListId;
                            sub.ListType = "local";
                            Subscriptions::Add(sub);
                            UI::ShowNotification("List Linked", "Link created: '" + State::SelectedListId + "' -> " + a.Name);
                            UI::CloseCurrentPopup();
                        }
                    }
                }
            }
            UI::EndPopup();
        }

        UI::SameLine();
        if (UI::Button(Icons::Trash + " Delete List")) {
            CustomLists::DeleteList(State::SelectedListId);
            State::SelectedListId = "";
        }

        if (UI::BeginTable("ListContentTable", 7, UI::TableFlags::Resizable | UI::TableFlags::RowBg)) {
            UI::TableSetupColumn("ID", UI::TableColumnFlags::WidthFixed, 60);
            UI::TableSetupColumn("Name", UI::TableColumnFlags::WidthStretch);
            UI::TableSetupColumn("Author", UI::TableColumnFlags::WidthStretch);
            UI::TableSetupColumn("Length", UI::TableColumnFlags::WidthFixed, 80);
            UI::TableSetupColumn("Difficulty", UI::TableColumnFlags::WidthFixed, 100);
            UI::TableSetupColumn("Tags", UI::TableColumnFlags::WidthStretch);
            UI::TableSetupColumn("Actions", UI::TableColumnFlags::WidthFixed, 60);
            UI::TableHeadersRow();

            for (uint i = 0; i < maps.Length; i++) {
                TmxMap@ m = maps[i];
                UI::TableNextRow();
                UI::TableNextColumn();
                UI::Text(tostring(m.TrackId));
                UI::TableNextColumn();
                UI::Text(m.Name);
                MetadataOverrides::RenderOverrideMenu(m);
                UI::TableNextColumn();
                UI::Text(m.Author);
                UI::TableNextColumn();
                UI::Text(Time::Format(m.LengthSecs * 1000));
                UI::TableNextColumn();
                UI::Text(m.DifficultyName);
                UI::TableNextColumn();
                UI::Text(string::Join(m.Tags, ", "));
                UI::TableNextColumn();
                if (UI::Button(Icons::Trash + "##rem" + i)) {
                    CustomLists::Remove(State::SelectedListId, m.TrackId);
                    State::CustomListMaps = CustomLists::GetMaps(State::SelectedListId);
                }
            }
            UI::EndTable();
        }
    }
}
