// Tabs/ClubsTab.as - Club Management & Branding View

class ClubsTab : Tab {
    ClubsTab() {
        super("Clubs", Icons::BuildingO);
    }

    void DrawInner() override {
        if (State::MyClubs.Length == 0 && !State::refreshingClubs && Time::Now > State::lastClubRefresh + State::REFRESH_COOLDOWN) {
            startnew(RefreshClubs);
        }

        UI::Separator();

        // Club Selection
        if (bool(UI::BeginCombo("Select Club", State::SelectedClub is null ? "None" : State::SelectedClub.Name))) {
            if (UI::Selectable("None", State::SelectedClub is null)) {
                @State::SelectedClub = null;
            }
            for (uint i = 0; i < State::MyClubs.Length; i++) {
                string role = State::MyClubs[i].Role.ToUpper();
                bool isManager = (role == "ADMIN" || role == "CREATOR" || role == "CONTENT_CREATOR");
                if (!isManager) continue;

                if (UI::Selectable(State::MyClubs[i].Name, State::SelectedClub !is null && State::SelectedClub.Id == State::MyClubs[i].Id)) {
                    @State::SelectedClub = State::MyClubs[i];
                    State::iconUrl = State::SelectedClub.IconUrl;
                    State::verticalUrl = State::SelectedClub.VerticalUrl;
                    State::backgroundUrl = State::SelectedClub.BackgroundUrl;
                    State::grassUrl = State::SelectedClub.StadiumGrassUrl;
                    State::terrainUrl = State::SelectedClub.StadiumTerrainUrl;
                    State::logoUrl = State::SelectedClub.StadiumLogoUrl;
                    State::clubTag = State::SelectedClub.Tag;
                    State::clubDescription = State::SelectedClub.Description;
                    State::clubPublic = State::SelectedClub.Public;
                    startnew(RefreshActivities);
                }
            }
            UI::EndCombo();
        }

        UI::SameLine();
        if (UI::Button(Icons::Refresh + "##RefreshClubs")) {
            startnew(RefreshClubs);
        }

        if (State::SelectedClub !is null) {
            UI::Separator();
            UI::Text("Club ID: " + State::SelectedClub.Id);
            UI::Text("Tag: " + State::SelectedClub.Tag);
            
            // Using pure call for void-return version
            UI::BeginTabBar("ClubChildTabs");
            if (UI::BeginTabItem("Activities")) {
                RenderActivityTab();
                UI::EndTabItem();
            }
            if (UI::BeginTabItem("Branding & Images")) {
                RenderBrandingTab();
                UI::EndTabItem();
            }
            UI::EndTabBar();
        }
    }

    // --- Activity Tab Implementation ---

    bool showCreateFolderModal = false;
    bool showCreateCampaignModal = false;
    bool showCreateRoomModal = false;
    uint[] renderedIds;

    void RenderActivityTab() {
        if (UI::Button("Refresh Activities")) {
            startnew(RefreshActivities);
        }
        UI::SameLine();
        if (UI::Button("Create Folder")) { State::nextActivityName = "New Folder"; showCreateFolderModal = true; }
        UI::SameLine();
        if (UI::Button("Create Campaign")) { State::nextActivityName = "New Campaign"; showCreateCampaignModal = true; }
        UI::SameLine();
        if (UI::Button("Create Room")) { State::nextActivityName = "New Room"; showCreateRoomModal = true; }

        UI::Separator();

        if (State::bulkAuditInProgress) {
            UI::Text("\\$f80" + Icons::Spinner + " " + State::bulkAuditStatus);
            UI::ProgressBar(State::bulkAuditProgress, vec2(-1, 0), "");
        } else {
            if (UI::Button("\\$f80" + Icons::Refresh + "\\$z Sync All Subscriptions")) startnew(DoBulkAudit);
            UI::SameLine();
            if (UI::Button(Icons::Trash + " Clean Up Orphaned Subscriptions")) Subscriptions::CleanupOrphans();
        }


        HandleModals();

        UI::Separator();

        auto items = State::ClubActivities;
        if (items.Length == 0 && !State::refreshingActivities) {
            UI::TextDisabled("No activities found for this club.");
        } else {
            renderedIds.RemoveRange(0, renderedIds.Length);
            
            // BeginChild unconditionally needs an EndChild
            UI::BeginChild("ActivityExplorer");
            
            RenderActivities(0, items);
            
            // Render orphans
            bool hasOrphans = false;
            for (uint i = 0; i < items.Length; i++) {
                if (items[i].FolderId != 0) {
                    bool foundParent = false;
                    for (uint j = 0; j < items.Length; j++) {
                        if (items[j].Id == items[i].FolderId) { foundParent = true; break; }
                    }
                    if (!foundParent) {
                        if (!hasOrphans) { UI::Separator(); UI::TextDisabled("Misc / Unsorted"); hasOrphans = true; }
                        RenderActivityNode(items[i], items);
                    }
                }
            }
            UI::EndChild();
        }
    }

    void HandleModals() {
        if (showCreateFolderModal) { UI::OpenPopup("Create Folder"); showCreateFolderModal = false; }
        if (bool(UI::BeginPopupModal("Create Folder", UI::WindowFlags::AlwaysAutoResize))) {
            State::nextActivityName = UI::InputText("Folder Name", State::nextActivityName);
            State::nextActivityActive = UI::Checkbox("Create as Active", State::nextActivityActive);
            if (UI::Button("Create")) { startnew(DoCreateFolder); UI::CloseCurrentPopup(); }
            UI::SameLine(); if (UI::Button("Cancel")) UI::CloseCurrentPopup();
            UI::EndPopup();
        }
        if (showCreateCampaignModal) { UI::OpenPopup("Create Campaign"); showCreateCampaignModal = false; }
        if (bool(UI::BeginPopupModal("Create Campaign", UI::WindowFlags::AlwaysAutoResize))) {
            State::nextActivityName = UI::InputText("Campaign Name", State::nextActivityName);
            State::nextActivityActive = UI::Checkbox("Create as Active", State::nextActivityActive);
            if (UI::Button("Create")) { startnew(DoCreateCampaign); UI::CloseCurrentPopup(); }
            UI::SameLine(); if (UI::Button("Cancel")) UI::CloseCurrentPopup();
            UI::EndPopup();
        }
        if (showCreateRoomModal) { UI::OpenPopup("Create Room"); showCreateRoomModal = false; }
        if (bool(UI::BeginPopupModal("Create Room", UI::WindowFlags::AlwaysAutoResize))) {
            State::nextActivityName = UI::InputText("Room Name", State::nextActivityName);
            State::nextActivityActive = UI::Checkbox("Create as Active", State::nextActivityActive);
            if (UI::Button("Create")) { startnew(DoCreateRoom); UI::CloseCurrentPopup(); }
            UI::SameLine(); if (UI::Button("Cancel")) UI::CloseCurrentPopup();
            UI::EndPopup();
        }
    }

    void RenderActivities(uint folderId, Activity[]@ items) {
        auto siblings = GetSortedSiblings(folderId, items);
        for (uint i = 0; i < siblings.Length; i++) {
            RenderActivityNode(siblings[i], items);
        }
    }

    void RenderActivityNode(Activity@ a, Activity[]@ items) {
        renderedIds.InsertLast(a.Id);
        UI::PushID("act_" + a.Id);

        string icon = Icons::ExternalLink;
        if (a.Type == "folder") icon = Icons::FolderOpen;
        else if (a.Type == "campaign") icon = Icons::Flag;
        else if (a.Type == "room") icon = Icons::Gamepad;
        else if (a.Type == "news") icon = Icons::NewspaperO;

        bool nodeOpen = false;
        if (a.IsRenaming) {
            UI::SetNextItemWidth(200);
            a.RenameBuffer = UI::InputText("##rename", a.RenameBuffer);
            UI::SameLine();
            if (UI::Button(Icons::Check + "##confirm")) { 
                if (a.RenameBuffer != "") { startnew(DoRenameActivity, a); a.IsRenaming = false; }
            }
            UI::SameLine();
            if (UI::Button(Icons::Times + "##cancel")) a.IsRenaming = false;
        } else {
            string label = icon + " " + a.Name;
            if (a.Type == "campaign" || a.Type == "room") label += " (" + a.Maps.Length + " maps)";
            if (!a.Active) label = "\\$f44" + Icons::ExclamationCircle + " " + label;
            if (!a.Public) label += " \\$888" + Icons::Lock;
            if (a.Featured) label += " \\$fd0" + Icons::Star;
            if (Subscriptions::GetByActivity(a.Id) !is null) label += " \\$f80" + Icons::Rss;
            
            if (a.AuditDone && (a.AuditAdded.Length > 0 || a.AuditRemoved.Length > 0 || a.AuditOrderMismatch)) {
                label += " \\$0f0\\$s" + Icons::ExclamationTriangle + " Update Available";
            }

            nodeOpen = bool(UI::TreeNode(label + "###node_" + a.Id));
            if (a.HasMapChanges) {
                UI::SameLine();
                UI::Text("\\$f44" + Icons::FloppyO);
                if (UI::IsItemHovered()) UI::SetTooltip("Unsaved Changes (Click Save below)");
            }
            UI::SameLine();
            if (UI::Button(Icons::Pencil + "##rename_btn")) { a.IsRenaming = true; a.RenameBuffer = a.Name; }

            // Reorder
            auto siblings = GetSortedSiblings(a.FolderId, items);
            int idx = -1;
            for (uint i = 0; i < siblings.Length; i++) if (siblings[i].Id == a.Id) { idx = i; break; }
            UI::SameLine(); UI::BeginDisabled(idx <= 0);
            if (UI::Button(Icons::ArrowUp + "##up")) {
                State::reorderIds.RemoveRange(0, State::reorderIds.Length);
                State::reorderIds.InsertLast(a.Id);
                State::reorderIds.InsertLast(siblings[idx-1].Id);
                startnew(DoReorderActivity);
            }
            UI::EndDisabled();
            UI::SameLine(); UI::BeginDisabled(idx < 0 || uint(idx) >= siblings.Length - 1);
            if (UI::Button(Icons::ArrowDown + "##down")) {
                State::reorderIds.RemoveRange(0, State::reorderIds.Length);
                State::reorderIds.InsertLast(a.Id);
                State::reorderIds.InsertLast(siblings[idx+1].Id);
                startnew(DoReorderActivity);
            }
            UI::EndDisabled();

            // Move
            UI::SameLine();
            if (a.IsMoving) {
                if (UI::Button(Icons::Times + "##cancel_move")) a.IsMoving = false;
                UI::SameLine();
                UI::SetNextItemWidth(200);
                if (UI::BeginCombo("##move_to", "Select Destination...")) {
                    if (a.FolderId != 0) {
                        if (UI::Selectable("Root Folder (None)", false)) {
                            startnew(DoMoveActivity, MoveAction(a, 0));
                        }
                    }
                    for (uint j = 0; j < items.Length; j++) {
                        if (items[j].Type == "folder" && items[j].Id != a.Id && items[j].Id != a.FolderId) {
                            if (UI::Selectable(Icons::FolderOpen + " " + items[j].Name, false)) {
                                startnew(DoMoveActivity, MoveAction(a, items[j].Id));
                            }
                        }
                    }
                    UI::EndCombo();
                }
            } else {
                if (UI::Button(Icons::FolderOpen + "##move_btn")) a.IsMoving = true;
                
                // Delete
                UI::SameLine();
                if (a.PendingDelete) {
                    if (UI::Button("Confirm Del?")) { startnew(DoDeleteActivity, a); a.PendingDelete = false; }
                    UI::SameLine(); if (UI::Button(Icons::Times + "##cancel_del")) a.PendingDelete = false;
                } else {
                    if (UI::Button(Icons::Trash + "##del_btn")) a.PendingDelete = true;
                }
            }
        }

        if (nodeOpen) {
            RenderActivityStatusToggles(a);
            UI::Separator();
            if (a.Type == "folder") RenderActivities(a.Id, items);
            else DisplayActivityContent(a);
            UI::TreePop();
        }
        UI::PopID();
    }

    void RenderActivityStatusToggles(Activity@ a) {
        if (UI::Button((a.Active ? Icons::CheckCircle : Icons::CircleO) + " Active")) startnew(DoToggleActivityActive, a);
        UI::SameLine();
        if (UI::Button((a.Public ? Icons::Globe : Icons::Lock) + (a.Public ? " Public" : " Private"))) startnew(DoToggleActivityPublic, a);
        UI::SameLine();
        if (UI::Button((a.Featured ? Icons::Star : Icons::StarO) + " Featured")) startnew(DoToggleActivityFeatured, a);
    }

    void DisplayActivityContent(Activity@ a) {
        if (a.Type == "news") {
            if (!a.NewsLoaded && !a.LoadingMaps) { a.LoadingMaps = true; startnew(LoadActivityDetails, a); }
        } else if (!a.MapsLoaded && !a.LoadingMaps && a.Type != "folder") {
            a.LoadingMaps = true; startnew(LoadActivityMaps, a);
        }

        if (a.LoadingMaps) {
            UI::TextDisabled("Loading content...");
        } else {
            if (a.Type == "campaign" || a.Type == "room") {
                if (UI::Button((a.IsManagingMaps ? Icons::Check : Icons::List) + " Manage Maps##" + a.Id)) a.IsManagingMaps = !a.IsManagingMaps;
                
                if (a.IsManagingMaps) {
                    if (UI::Button("Select Max (Leave 1)##" + a.Id)) {
                        for (uint i = 1; i < a.Maps.Length; i++) a.Maps[i].PendingDelete = true;
                        a.HasMapChanges = true;
                    }
                    UI::SameLine();
                    if (UI::Button("Deselect All##" + a.Id)) {
                        for (uint i = 0; i < a.Maps.Length; i++) a.Maps[i].PendingDelete = false;
                        a.HasMapChanges = true;
                    }
                    
                    if (UI::BeginTable("ManageMapsTable_" + a.Id, 5, UI::TableFlags::Resizable | UI::TableFlags::Borders | UI::TableFlags::RowBg)) {
                        UI::TableSetupColumn("Pos", UI::TableColumnFlags::WidthFixed, 40);
                        UI::TableSetupColumn("Map Name", UI::TableColumnFlags::WidthStretch);
                        UI::TableSetupColumn("Author", UI::TableColumnFlags::WidthFixed, 150);
                        UI::TableSetupColumn("Del?", UI::TableColumnFlags::WidthFixed, 40);
                        UI::TableSetupColumn("Order", UI::TableColumnFlags::WidthFixed, 100);
                        UI::TableHeadersRow();

                        for (uint i = 0; i < a.Maps.Length; i++) {
                            auto m = a.Maps[i];
                            UI::TableNextRow();
                            
                            if (m.PendingDelete) UI::TableSetBgColor(UI::TableBgTarget::RowBg0, vec4(0.4f, 0.1f, 0.1f, 0.5f));

                            UI::TableNextColumn(); UI::Text("" + (i + 1));
                            UI::TableNextColumn(); UI::Text(m.Name);
                            UI::TableNextColumn(); UI::Text(m.Author);
                            UI::TableNextColumn();
                            
                            // Checkbox for deletion
                            UI::PushID("del_chk_" + i);
                            bool wasPending = m.PendingDelete;
                            m.PendingDelete = UI::Checkbox("##del", m.PendingDelete);
                            if (m.PendingDelete != wasPending) a.HasMapChanges = true;
                            UI::PopID();
                            
                            UI::TableNextColumn();
                            UI::PushID("map_order_" + i);
                            bool canClick = Time::Now > State::lastActionTime + 300;
                            UI::BeginDisabled(!canClick || i == 0);
                            if (UI::Button(Icons::ArrowUp + "##up")) { startnew(DoReorderMap, MapAction(a, i, -1)); State::lastActionTime = Time::Now; }
                            UI::EndDisabled();
                            UI::SameLine();
                            UI::BeginDisabled(!canClick || i == a.Maps.Length - 1);
                            if (UI::Button(Icons::ArrowDown + "##down")) { startnew(DoReorderMap, MapAction(a, i, 1)); State::lastActionTime = Time::Now; }
                            UI::EndDisabled();
                            UI::PopID();
                        }
                            UI::EndTable();
                        }
                        if (a.HasMapChanges) {
                            UI::PushStyleColor(UI::Col::Button, vec4(0.1f, 0.6f, 0.1f, 0.8f));
                            if (UI::Button(Icons::FloppyO + " Save Changes##" + a.Id)) startnew(DoSaveMapChanges, a);
                            UI::PopStyleColor();
                            UI::SameLine();
                            if (UI::Button(Icons::Times + " Discard##" + a.Id)) startnew(DoDiscardMapChanges, a);
                            UI::SameLine();
                            UI::TextDisabled("(Unsaved Changes)");
                        }
                    } else {
                    for (uint i = 0; i < a.Maps.Length; i++) {
                        UI::Text(" " + (i + 1) + ". " + a.Maps[i].Name + " by " + a.Maps[i].Author);
                    }
                }
            }
 else if (a.Type == "news") {
                a.Headline = UI::InputText("Headline", a.Headline);
                a.Body = UI::InputTextMultiline("Body", a.Body, vec2(0, 150));
                if (UI::Button(Icons::FloppyO + " Save News")) startnew(DoSaveNews, a);
            }
            RenderAuditSubscription(a);
        }
    }

    bool showAuditDetails = false;
    void RenderAuditSubscription(Activity@ a) {
        auto sub = Subscriptions::GetByActivity(a.Id);
        if (sub is null) return;
        UI::Separator();
        UI::Text("\\$f80" + Icons::MapMarker + "\\$z Subscription Curation Audit");
        
        if (a.IsAuditing) {
            UI::Text("\\$888" + Icons::Spinner + " Auditing TMX...");
        } else if (a.AuditDone) {
            // Display Filter Summary for context
            if (UI::TreeNode("Subscription Filter Summary##" + a.Id)) {
                if (sub.Filters.CurrentPage > 1) UI::TextDisabled("Page: " + sub.Filters.CurrentPage);
                if (sub.Filters.AuthorName != "") UI::TextDisabled("Author: " + sub.Filters.AuthorName);
                if (sub.Filters.Vehicle >= 0 && sub.Filters.Vehicle < int(TMX::VEHICLE_NAMES.Length)) 
                    UI::TextDisabled("Vehicle: " + TMX::VEHICLE_NAMES[sub.Filters.Vehicle]);
                
                if (sub.Filters.SortPrimary >= 0 && sub.Filters.SortPrimary < int(TMX::SORT_NAMES.Length))
                    UI::TextDisabled("Sort: " + TMX::SORT_NAMES[sub.Filters.SortPrimary] + (sub.Filters.SortSecondary >= 0 ? " -> " + TMX::SORT_NAMES[sub.Filters.SortSecondary] : ""));

                if (sub.Filters.IncludeTags.Length > 0) UI::TextDisabled("Include: " + string::Join(sub.Filters.IncludeTags, ", "));
                if (sub.Filters.ExcludeTags.Length > 0) UI::TextDisabled("Exclude: " + string::Join(sub.Filters.ExcludeTags, ", "));
                
                string diffList = "";
                for (uint i = 0; i < sub.Filters.Difficulties.Length; i++) if (sub.Filters.Difficulties[i]) diffList += TMX::DIFFICULTY_NAMES[i] + ", ";
                if (diffList != "") UI::TextDisabled("Difficulty: " + diffList.SubStr(0, diffList.Length - 2));

                if (sub.Filters.UploadedFrom != "" || sub.Filters.UploadedTo != "") 
                    UI::TextDisabled("Uploaded: " + (sub.Filters.UploadedFrom == "" ? "Start" : sub.Filters.UploadedFrom) + " to " + (sub.Filters.UploadedTo == "" ? "Now" : sub.Filters.UploadedTo));
                
                if (sub.Filters.TimeFromMs > 0 || sub.Filters.TimeToMs > 0)
                    UI::TextDisabled("Time: " + Time::Format(sub.Filters.TimeFromMs) + " to " + Time::Format(sub.Filters.TimeToMs));

                if (sub.Filters.InTOTD == 1) UI::TextDisabled("Flag: TOTD Only");
                if (sub.Filters.InCollection >= 0 && sub.Filters.InCollection < int(TMX::COLLECTION_NAMES.Length))
                    UI::TextDisabled("Collection: " + TMX::COLLECTION_NAMES[sub.Filters.InCollection]);
                if (sub.Filters.PrimaryTagOnly) UI::TextDisabled("Flag: Primary Tag Only");
                if (sub.Filters.PrimarySurfaceOnly) UI::TextDisabled("Flag: Primary Surface Only");
                UI::TextDisabled("Max Maps: " + sub.MapLimit);

                UI::TreePop();
            }

            bool hasChanges = a.AuditAdded.Length > 0 || a.AuditRemoved.Length > 0 || a.AuditOrderMismatch;
            
            if (!hasChanges) {
                UI::Text("\\$8f8" + Icons::Check + " Subscription is up to date.");
                if (UI::Button("Close##audit_" + a.Id)) a.AuditDone = false;
            } else {
                string summary = "";
                if (a.AuditAdded.Length > 0) summary += "\\$0f0+" + a.AuditAdded.Length + " ";
                if (a.AuditRemoved.Length > 0) summary += "\\$f00-" + a.AuditRemoved.Length + " ";
                if (a.AuditOrderMismatch) summary += "\\$ff0(Reorder)";
                
                UI::Text("Proposed changes: " + summary);
                
                if (UI::Button(Icons::List + " Review Details##" + a.Id)) showAuditDetails = !showAuditDetails;
                UI::SameLine();
                UI::PushStyleColor(UI::Col::Button, vec4(0.1f, 0.6f, 0.1f, 0.8f));
                if (UI::Button(Icons::Check + " Apply Audit##" + a.Id)) startnew(DoApplyAudit, a);
                UI::PopStyleColor();
                UI::SameLine();
                if (UI::Button(Icons::Times + " Discard##" + a.Id)) startnew(DoDiscardAudit, a);

                if (showAuditDetails) {
                    if (UI::BeginTable("AuditDetails_" + a.Id, 2, UI::TableFlags::Borders | UI::TableFlags::RowBg)) {
                        UI::TableSetupColumn("Action", UI::TableColumnFlags::WidthFixed, 60);
                        UI::TableSetupColumn("Map Name", UI::TableColumnFlags::WidthStretch);
                        UI::TableHeadersRow();

                        for (uint i = 0; i < a.AuditAdded.Length; i++) {
                            UI::TableNextRow();
                            UI::TableSetBgColor(UI::TableBgTarget::RowBg0, vec4(0, 0.4f, 0, 0.3f));
                            UI::TableNextColumn(); UI::Text("\\$0f0" + Icons::PlusCircle + " ADD");
                            UI::TableNextColumn(); UI::Text(a.AuditAdded[i].Name);
                        }
                        for (uint i = 0; i < a.AuditRemoved.Length; i++) {
                            UI::TableNextRow();
                            UI::TableSetBgColor(UI::TableBgTarget::RowBg0, vec4(0.4f, 0, 0, 0.3f));
                            UI::TableNextColumn(); UI::Text("\\$f00" + Icons::MinusCircle + " REM");
                            UI::TableNextColumn(); UI::Text(a.AuditRemoved[i].Name);
                        }
                        if (a.AuditOrderMismatch && a.AuditAdded.Length == 0 && a.AuditRemoved.Length == 0) {
                            UI::TableNextRow();
                            UI::TableNextColumn(); UI::Text("\\$ff0" + Icons::Refresh);
                            UI::TableNextColumn(); UI::Text("Maps will be reordered to match TMX subscription.");
                        }
                        UI::EndTable();
                    }
                }
            }
        } else {
            if (UI::Button(Icons::Search + " Audit Now")) startnew(DoAuditSubscription, a);
            UI::SameLine();
            if (UI::Button(Icons::Trash + " Remove Subscription")) {
                Subscriptions::Remove(a.Id);
                UI::ShowNotification("Club Manager", "Subscription removed for " + a.Name);
            }
        }
    }

    Activity@[] GetSortedSiblings(uint folderId, Activity[]@ items) {
        Activity@[] siblings;
        for (uint i = 0; i < items.Length; i++) if (items[i].FolderId == folderId) siblings.InsertLast(items[i]);
        // Simple sort
        for (uint i = 0; i < siblings.Length; i++) {
            for (uint j = i + 1; j < siblings.Length; j++) {
                if (siblings[i].Position > siblings[j].Position) {
                    auto temp = siblings[i]; @siblings[i] = siblings[j]; @siblings[j] = temp;
                }
            }
        }
        return siblings;
    }

    void RenderBrandingTab() {
        UI::TextDisabled("General Settings");
        State::clubTag = UI::InputText("Club Tag", State::clubTag);
        State::clubDescription = UI::InputText("Description", State::clubDescription);
        State::clubPublic = UI::Checkbox("Public Club", State::clubPublic);
        UI::Separator();
        UI::TextDisabled("Branding Image URLs");
        State::iconUrl = UI::InputText("Icon URL", State::iconUrl);
        State::verticalUrl = UI::InputText("Vertical URL", State::verticalUrl);
        State::backgroundUrl = UI::InputText("Background URL", State::backgroundUrl);
        if (UI::Button("Update Branding")) startnew(DoUpdateBranding, null);
    }
}
