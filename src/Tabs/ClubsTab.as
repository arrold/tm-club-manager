// Tabs/ClubsTab.as - Club Management & Branding View

string FormatJson(Json::Value@ val, const string &in indent = "") {
    if (val is null) return "null";
    string next = indent + "  ";
    Json::Type type = val.GetType();
    if (type == Json::Type::Object) {
        string[] keys = val.GetKeys();
        if (keys.Length == 0) return "{}";
        string r = "{\n";
        for (uint i = 0; i < keys.Length; i++) {
            r += next + "\"" + keys[i] + "\": " + FormatJson(val[keys[i]], next);
            if (i < keys.Length - 1) r += ",";
            r += "\n";
        }
        return r + indent + "}";
    } else if (type == Json::Type::Array) {
        if (val.Length == 0) return "[]";
        string r = "[\n";
        for (uint i = 0; i < val.Length; i++) {
            r += next + FormatJson(val[i], next);
            if (i < val.Length - 1) r += ",";
            r += "\n";
        }
        return r + indent + "]";
    }
    return Json::Write(val);
}

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
        if (UI::BeginCombo("Select Club", State::SelectedClub is null ? "None" : State::SelectedClub.Name)) {
            if (UI::Selectable("None", State::SelectedClub is null)) {
                @State::SelectedClub = null;
            }
            for (uint i = 0; i < State::MyClubs.Length; i++) {
                string role = State::MyClubs[i].Role.ToUpper();
                bool isManager = (role == "ADMIN" || role == "CREATOR" || role == "CONTENT_CREATOR");
                if (!isManager) continue;

                if (UI::Selectable(State::MyClubs[i].Name, State::SelectedClub !is null && State::SelectedClub.Id == State::MyClubs[i].Id)) {
                    @State::SelectedClub = State::MyClubs[i];
                    State::clubTag = State::SelectedClub.Tag;
                    State::clubDescription = State::SelectedClub.Description;
                    State::clubPublic = State::SelectedClub.Public;
                    State::isInitialised = false;
                    State::bulkAuditComplete = false;
                    @State::TargetActivity = null;
                    AuditCache::Init();
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
            if (UI::BeginTabItem("General Settings")) {
                RenderGeneralSettingsTab();
                UI::EndTabItem();
            }
            if (UI::BeginTabItem("Club Overrides")) {
                RenderClubOverridesTab();
                UI::EndTabItem();
            }
            UI::EndTabBar();
            
            UI::Separator();
            UI::TextDisabled(Icons::InfoCircle + " Note: Campaign and Room updates may require a manual UI refresh (Shift + Scroll Lock).");
        }

        if (showImportModal) {
            UI::OpenPopup("Select Configuration");
            showImportModal = false;
        }

        if (UI::BeginPopupModal("Select Configuration", UI::WindowFlags::AlwaysAutoResize)) {
            UI::Text("Select a configuration file to import:");
            if (UI::BeginCombo("##File", selectedConfig == "" ? "Select File..." : selectedConfig)) {
                for (uint i = 0; i < availableConfigs.Length; i++) {
                    if (UI::Selectable(availableConfigs[i], selectedConfig == availableConfigs[i])) {
                        selectedConfig = availableConfigs[i];
                    }
                }
                UI::EndCombo();
            }

            UI::Separator();
            if (UI::Button("Dry Run")) {
                startnew(RunImportFlowInternal, selectedConfig);
                UI::CloseCurrentPopup();
            }
            UI::SameLine();
            if (UI::Button("Cancel")) {
                UI::CloseCurrentPopup();
            }
            UI::EndPopup();
        }
    }

    // --- Activity Tab Implementation ---

    bool showCreateFolderModal = false;
    bool showCreateCampaignModal = false;
    bool showCreateRoomModal = false;
    bool showImportModal = false;
    bool isExportingMapData = false;
    string exportMapDataStatus = "";
    string[] availableConfigs;
    string selectedConfig;
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
        UI::SameLine();
        if (UI::Button(Icons::CloudDownload + " Import Config")) {
            startnew(RunImportFlow);
        }
        UI::SameLine();
        if (UI::Button(Icons::CloudUpload + " Export Config")) {
            ConfigExporter::Export();
        }
        UI::SameLine();
        if (isExportingMapData) UI::BeginDisabled();
        if (UI::Button(Icons::Database + " Export Map Data")) {
            startnew(ExportMapData);
        }
        if (UI::IsItemHovered()) {
            UI::BeginTooltip();
            UI::Text("Exports map UIDs only (no metadata such as author names or tags).");
            UI::TextDisabled("Further analysis (e.g. author aggregation) can be scripted against this file externally.");
            UI::EndTooltip();
        }
        if (isExportingMapData) UI::EndDisabled();
        if (exportMapDataStatus != "") {
            UI::SameLine();
            UI::TextDisabled(exportMapDataStatus);
        }

        UI::Separator();

        if (State::bulkAuditInProgress) {
            UI::Text("\\$f80" + Icons::Spinner + " " + State::bulkAuditStatus);
            UI::ProgressBar(State::bulkAuditProgress, vec2(-1, 0), "");
        } else if (State::bulkAuditComplete) {
            if (State::bulkAuditUpdatesAvailable > 0) {
                if (UI::Button("\\$0f0" + Icons::CloudUpload + "\\$z Apply " + State::bulkAuditUpdatesAvailable + " Updates")) startnew(DoBulkApply);
                UI::SameLine();
                if (UI::Button(Icons::Refresh + " Re-Audit All")) startnew(DoBulkAudit);
                UI::TextDisabled(State::bulkAuditStatus);
                RenderAuditSummary();
            } else {
                UI::Text("\\$8f8" + Icons::Check + " Audit Complete: All subscriptions are up to date.");
                if (UI::Button(Icons::Refresh + " Re-Audit All")) startnew(DoBulkAudit);
            }
        } else {
            // Initial state: No audit in progress or complete for this club session
            if (UI::Button(Icons::Search + " Audit All Subscriptions")) startnew(DoBulkAudit);
        }

        if (ConfigImporter::log.Length > 0) {
            UI::Separator();
            UI::Text("\\$f80" + Icons::Book + " Importer Log " + (ConfigImporter::isImporting ? Icons::Spinner : ""));
            if (UI::BeginChild("ImporterLog", vec2(0, 150), true)) {
                for (uint i = 0; i < ConfigImporter::log.Length; i++) {
                    auto entry = ConfigImporter::log[i];
                    string color = "";
                    if (entry.Type == ConfigImporter::LogType::Error) color = "\\$f44";
                    else if (entry.Type == ConfigImporter::LogType::Warning) color = "\\$f80";
                    
                    if (color != "") UI::Text(color + entry.Msg);
                    else UI::TextDisabled(entry.Msg);
                }
                if (ConfigImporter::isImporting) UI::SetScrollHereY(1.0f);
            }
            UI::EndChild();
            if (ConfigImporter::dryRun && !ConfigImporter::isImporting) {
                bool hasErrors = ConfigImporter::currentDelta !is null && ConfigImporter::currentDelta.Errors > 0;
                UI::BeginDisabled(hasErrors);
                if (UI::Button(Icons::Check + " Commit Import")) {
                     startnew(CommitImportFlow);
                }
                UI::EndDisabled();
                if (hasErrors) {
                    UI::SameLine();
                    UI::Text("\\$f44" + Icons::ExclamationTriangle + " Resolve Errors to Commit");
                }
            }
            if (UI::Button("Clear Log")) ConfigImporter::log.RemoveRange(0, ConfigImporter::log.Length);
        }


        HandleModals();

        UI::Separator();

        Activity@[]@ items = State::ClubActivities;
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

    void RenderAuditSummary() {
        UI::PushStyleColor(UI::Col::Header, vec4(0.15f, 0.15f, 0.15f, 0.5f));
        bool open = UI::CollapsingHeader(Icons::ListUl + " Changed Activities");
        UI::PopStyleColor();
        if (!open) return;

        bool anyShown = false;
        for (uint i = 0; i < State::ClubActivities.Length; i++) {
            Activity@ a = State::ClubActivities[i];
            if (!a.AuditDone) continue;
            if (a.AuditAdded.Length == 0 && a.AuditRemoved.Length == 0 && !a.AuditOrderMismatch) continue;

            anyShown = true;
            string icon = a.Type == "campaign" ? Icons::Flag : Icons::Gamepad;
            UI::Text(icon + " " + a.Name);
            UI::SameLine(0, 12);
            if (a.AuditAdded.Length > 0) {
                UI::Text("\\$0f0+" + a.AuditAdded.Length);
                UI::SameLine(0, 8);
            }
            if (a.AuditRemoved.Length > 0) {
                UI::Text("\\$f44-" + a.AuditRemoved.Length);
                UI::SameLine(0, 8);
            }
            if (a.AuditOrderMismatch) {
                UI::TextDisabled("(order changed)");
            }
        }

        if (!anyShown) {
            UI::TextDisabled("No details available.");
        }
    }

    void HandleModals() {
        if (showCreateFolderModal) { UI::OpenPopup("Create Folder"); showCreateFolderModal = false; }
        if (UI::BeginPopupModal("Create Folder", UI::WindowFlags::AlwaysAutoResize)) {
            State::nextActivityName = UI::InputText("Folder Name", State::nextActivityName);
            State::nextActivityActive = UI::Checkbox("Create as Active", State::nextActivityActive);
            if (UI::Button("Create")) { startnew(DoCreateFolder); UI::CloseCurrentPopup(); }
            UI::SameLine(); if (UI::Button("Cancel")) UI::CloseCurrentPopup();
            UI::EndPopup();
        }
        if (showCreateCampaignModal) { UI::OpenPopup("Create Campaign"); showCreateCampaignModal = false; }
        if (UI::BeginPopupModal("Create Campaign", UI::WindowFlags::AlwaysAutoResize)) {
            State::nextActivityName = UI::InputText("Campaign Name", State::nextActivityName);
            State::nextActivityActive = UI::Checkbox("Create as Active", State::nextActivityActive);
            if (UI::Button("Create")) { startnew(DoCreateCampaign); UI::CloseCurrentPopup(); }
            UI::SameLine(); if (UI::Button("Cancel")) UI::CloseCurrentPopup();
            UI::EndPopup();
        }
        if (showCreateRoomModal) { UI::OpenPopup("Create Room"); showCreateRoomModal = false; }
        if (UI::BeginPopupModal("Create Room", UI::WindowFlags::AlwaysAutoResize)) {
            State::nextActivityName = UI::InputText("Room Name", State::nextActivityName);
            State::nextActivityActive = UI::Checkbox("Create as Active", State::nextActivityActive);
            
            UI::Separator();
            UI::Text("Mirror a Campaign (Optional)");
            string campName = "None";
            if (State::nextRoomMirrorCampaignId > 0) {
                for (uint i = 0; i < State::ClubActivities.Length; i++) {
                    if (State::ClubActivities[i].Type == "campaign" && State::ClubActivities[i].CampaignId == State::nextRoomMirrorCampaignId) {
                        campName = State::ClubActivities[i].Name;
                        break;
                    }
                }
            }
            if (UI::BeginCombo("Campaign link", campName)) {
                if (UI::Selectable("None", State::nextRoomMirrorCampaignId == 0)) State::nextRoomMirrorCampaignId = 0;
                for (uint i = 0; i < State::ClubActivities.Length; i++) {
                    Activity@ c = State::ClubActivities[i];
                    if (c.Type == "campaign") {
                        if (UI::Selectable(Icons::Flag + " " + c.Name, State::nextRoomMirrorCampaignId == c.CampaignId)) {
                            State::nextRoomMirrorCampaignId = c.CampaignId;
                        }
                    }
                }
                UI::EndCombo();
            }
            UI::TextDisabled("If linked, maps will be automatically managed by the campaign.");

            if (UI::Button("Create")) { startnew(DoCreateRoom); UI::CloseCurrentPopup(); }
            UI::SameLine(); if (UI::Button("Cancel")) UI::CloseCurrentPopup();
            UI::EndPopup();
        }
    }

    void RenderActivities(uint parentId, Activity@[]@ items) {
        Activity@[] siblings = GetSortedSiblings(parentId, items);
        for (uint i = 0; i < siblings.Length; i++) {
            RenderActivityNode(siblings[i], items);
        }
    }

    void RenderActivityNode(Activity@ a, Activity@[]@ items) {
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
            if (a.Type == "news" && a.RenameBuffer.Length > 20) a.RenameBuffer = a.RenameBuffer.SubStr(0, 20);
            UI::SameLine();
            if (UI::Button(Icons::Check + "##confirm")) { 
                if (a.RenameBuffer != "") { startnew(DoRenameActivity, a); a.IsRenaming = false; }
            }
            UI::SameLine();
            if (UI::Button(Icons::Times + "##cancel")) a.IsRenaming = false;
        } else {
            string label = icon + " " + a.Name;
            if (a.Type == "campaign" || a.Type == "room") {
                uint mapCount = a.Maps.Length;
                bool isMirrored = a.Type == "room" && a.MirrorCampaignId > 0;
                
                if (isMirrored) {
                    bool loadingParent = false;
                    for (uint i = 0; i < State::ClubActivities.Length; i++) {
                        if (State::ClubActivities[i].Type == "campaign" && State::ClubActivities[i].CampaignId == a.MirrorCampaignId) {
                            if (State::ClubActivities[i].MapsLoaded) {
                                mapCount = State::ClubActivities[i].Maps.Length;
                            } else {
                                loadingParent = State::ClubActivities[i].LoadingMaps;
                                mapCount = 0;
                            }
                            break;
                        }
                    }
                    if (mapCount == 0 && loadingParent) label += " \\$8f8" + Icons::Link + " (" + Icons::Spinner + ")";
                    else label += " \\$8f8" + Icons::Link + " (" + mapCount + ")";
                } else {
                    label += " (" + mapCount + ")";
                }
            }
            if (!a.Active) label = "\\$f44" + Icons::ExclamationCircle + " " + label;
            if (!a.Public) label += " \\$888" + Icons::Lock;
            if (a.Featured) label += " \\$fd0" + Icons::Star;
            if (Subscriptions::GetByActivity(a.Id) !is null) label += " \\$f80" + Icons::Rss;
            
            if (a.AuditDone && (a.AuditAdded.Length > 0 || a.AuditRemoved.Length > 0 || a.AuditOrderMismatch)) {
                label += " \\$0f0\\$s" + Icons::ExclamationTriangle + " Update Available";
            }

            nodeOpen = UI::TreeNode(label + "###node_" + a.Id);
            if (a.HasMapChanges) {
                UI::SameLine();
                UI::Text("\\$f44" + Icons::FloppyO);
                if (UI::IsItemHovered()) UI::SetTooltip("Unsaved Changes (Click Save below)");
            }
            UI::SameLine();
            if (UI::Button(Icons::Pencil + "##rename_btn")) { a.IsRenaming = true; a.RenameBuffer = a.Name; }

            // Reorder
            Activity@[] siblings = GetSortedSiblings(a.FolderId, items);
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
            if (!a.NewsLoaded && !a.LoadingMaps && !a.Failed) { a.LoadingMaps = true; startnew(LoadActivityDetails, a); }
        } else if (!a.MapsLoaded && !a.LoadingMaps && a.Type != "folder" && !a.Failed) {
            a.LoadingMaps = true; startnew(LoadActivityMaps, a);
        }

        if (a.LoadingMaps) {
            UI::TextDisabled(Icons::Spinner + " Loading content...");
        } else if (a.Failed) {
            UI::Text("\\$f00" + Icons::ExclamationTriangle + " Failed to load metadata.");
            UI::SameLine();
            if (UI::Button(Icons::Refresh + " Retry##" + a.Id)) {
                a.Failed = false;
                if (a.Type == "news") startnew(LoadActivityDetails, a);
                else startnew(LoadActivityMaps, a);
            }
        } else {
            if (a.Type == "campaign" || a.Type == "room") {
                bool isMirrored = a.Type == "room" && a.MirrorCampaignId > 0;
                
                if (isMirrored) {
                    string campName = "Unknown Campaign";
                    uint mapCount = 0;
                    bool parentLoading = false;
                    for (uint i = 0; i < State::ClubActivities.Length; i++) {
                        if (State::ClubActivities[i].Type == "campaign" && State::ClubActivities[i].CampaignId == a.MirrorCampaignId) {
                            campName = State::ClubActivities[i].Name;
                            mapCount = State::ClubActivities[i].Maps.Length;
                            parentLoading = State::ClubActivities[i].LoadingMaps;
                            break;
                        }
                    }
                    if (parentLoading && mapCount == 0) {
                        UI::Text("\\$8f8" + Icons::Link + " Inherited State: Synchronizing maps from campaign...");
                    } else {
                        UI::Text("\\$8f8" + Icons::Link + " Inherited State: Managing " + mapCount + " maps via linked Campaign: " + campName + " (ID: " + a.MirrorCampaignId + ")");
                    }
                } else {
                    if (UI::Button((a.IsManagingMaps ? Icons::Check : Icons::List) + " Manage Maps##" + a.Id)) a.IsManagingMaps = !a.IsManagingMaps;
                }
                
                if (a.IsManagingMaps && !isMirrored) {
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
                            MapInfo@ m = a.Maps[i];
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
                a.Headline = UI::InputText("News Headline (max 26 chars)", a.Headline);
                if (a.Headline.Length > 26) a.Headline = a.Headline.SubStr(0, 26);
                a.Body = UI::InputTextMultiline("News Body (max 1986 chars)", a.Body, vec2(0, 100));
                if (a.Body.Length > 1986) a.Body = a.Body.SubStr(0, 1986);
                if (UI::Button(Icons::FloppyO + " Save News Content")) startnew(DoSaveNews, a);
            }
            if (a.Type == "room" && a.MirrorCampaignId > 0) {
                // Mirrored rooms do not support manual curation or subscriptions
            } else {
                RenderAuditSubscription(a);
            }
        }
    }

    void RenderFilterSummary(Subscription@ sub, Activity@ a) {
        if (sub.SourceType == 0) {
            if (UI::TreeNode("Subscription Filter Summary##" + a.Id)) {
                if (sub.Filters.CurrentPage > 1) UI::TextDisabled("Page: " + sub.Filters.CurrentPage);
                if (sub.Filters.AuthorNames.Length > 0) UI::TextDisabled("Author(s): " + string::Join(sub.Filters.AuthorNames, ", "));
                if (sub.Filters.Vehicle >= 0 && sub.Filters.Vehicle < int(TMX::VEHICLE_NAMES.Length))
                    UI::TextDisabled("Vehicle: " + TMX::VEHICLE_NAMES[sub.Filters.Vehicle]);

                if (sub.Filters.SortPrimary >= 0 && sub.Filters.SortPrimary < int(TMX::SORT_NAMES.Length))
                    UI::TextDisabled("Sort: " + TMX::SORT_NAMES[sub.Filters.SortPrimary]);
                if (sub.Filters.SortSecondary >= 0 && sub.Filters.SortSecondary < int(TMX::SORT_NAMES.Length))
                    UI::TextDisabled("Secondary Sort: " + TMX::SORT_NAMES[sub.Filters.SortSecondary]);

                if (sub.Filters.IncludeTags.Length > 0) UI::TextDisabled("Include: " + string::Join(sub.Filters.IncludeTags, ", "));
                if (sub.Filters.ExcludeTags.Length > 0) UI::TextDisabled("Exclude: " + string::Join(sub.Filters.ExcludeTags, ", "));

                string diffList = "";
                for (uint i = 0; i < sub.Filters.Difficulties.Length; i++) if (sub.Filters.Difficulties[i]) diffList += TMX::DIFFICULTY_NAMES[i] + ", ";
                if (diffList != "") UI::TextDisabled("Difficulty: " + diffList.SubStr(0, diffList.Length - 2));

                if (sub.Filters.RelativeDays > 0)
                    UI::TextDisabled("Uploaded: last " + sub.Filters.RelativeDays + " days (rolling)");
                else if (sub.Filters.UploadedFrom != "" || sub.Filters.UploadedTo != "")
                    UI::TextDisabled("Uploaded: " + (sub.Filters.UploadedFrom == "" ? "Start" : sub.Filters.UploadedFrom) + " to " + (sub.Filters.UploadedTo == "" ? "Now" : sub.Filters.UploadedTo));

                if (sub.Filters.TimeFromMs > 0 || sub.Filters.TimeToMs > 0)
                    UI::TextDisabled("Time: " + Time::Format(sub.Filters.TimeFromMs) + " to " + Time::Format(sub.Filters.TimeToMs));

                if (sub.Filters.InTOTD == 1) UI::TextDisabled("Flag: TOTD Only");
                else if (sub.Filters.InTOTD == 0) UI::TextDisabled("Flag: Not TOTD");
                if (sub.Filters.InCollection >= 0 && sub.Filters.InCollection < int(TMX::COLLECTION_NAMES.Length))
                    UI::TextDisabled("Collection: " + TMX::COLLECTION_NAMES[sub.Filters.InCollection]);
                if (sub.Filters.PrimaryTagOnly) UI::TextDisabled("Flag: Primary Tag Only");
                if (sub.Filters.PrimarySurfaceOnly) UI::TextDisabled("Flag: Primary Surface Only");
                UI::TextDisabled("Max Maps: " + sub.MapLimit);

                UI::TreePop();
            }
        } else {
            UI::TextDisabled("Using maps from Local List: " + sub.ListId);
            UI::TextDisabled("Max Maps: " + sub.MapLimit);
        }
    }

    void RenderJsonEditor(Activity@ a, Subscription@ sub) {
        if (sub.SourceType != 0) return;

        if (!a.IsEditingJson) {
            if (UI::Button(Icons::Pencil + " Edit Filters##jsonedit_" + a.Id)) {
                a.JsonEditBuffer = FormatJson(sub.Filters.ToExportJson());
                a.JsonEditError = "";
                a.IsEditingJson = true;
            }
            return;
        }

        UI::Separator();
        UI::TextDisabled("Edit subscription filters as JSON. Only include keys you want to change.");
        a.JsonEditBuffer = UI::InputTextMultiline("##jsonbuf_" + a.Id, a.JsonEditBuffer, vec2(0, 140));

        if (a.JsonEditError != "") {
            UI::Text("\\$f44" + a.JsonEditError);
        }

        UI::PushStyleColor(UI::Col::Button, vec4(0.1f, 0.6f, 0.1f, 0.8f));
        if (UI::Button(Icons::Check + " Save##jsonsave_" + a.Id)) {
            string tmpPath = IO::FromStorageFolder("tmp_filter_edit.json");
            IO::File f;
            f.Open(tmpPath, IO::FileMode::Write);
            f.Write(a.JsonEditBuffer);
            f.Close();
            Json::Value@ parsed = IO::FileExists(tmpPath) ? Json::FromFile(tmpPath) : null;
            if (parsed is null || parsed.GetType() != Json::Type::Object) {
                a.JsonEditError = "Invalid JSON: could not parse. Check syntax and try again.";
            } else {
                @sub.Filters = TmxSearchFilters(parsed);
                Subscriptions::Save();
                a.IsEditingJson = false;
                a.JsonEditBuffer = "";
                a.JsonEditError = "";
                a.AuditDone = false;
                UI::ShowNotification("Club Manager", "Filters updated for " + a.Name + ". Re-audit to see the new results.");
            }
        }
        UI::PopStyleColor();
        UI::SameLine();
        if (UI::Button(Icons::Times + " Cancel##jsoncancel_" + a.Id)) {
            a.IsEditingJson = false;
            a.JsonEditBuffer = "";
            a.JsonEditError = "";
        }

        if (UI::TreeNode("Filter Key Reference##jsonref_" + a.Id)) {
            UI::TextDisabled("PrimarySort / SecondarySort:");
            string sortList = "";
            for (uint i = 0; i < TMX::SORT_NAMES.Length; i++) sortList += (i > 0 ? ", " : "") + TMX::SORT_NAMES[i];
            UI::TextDisabled("  " + sortList);
            UI::TextDisabled("Difficulties (JSON array of strings):");
            string diffList = "";
            for (uint i = 0; i < TMX::DIFFICULTY_NAMES.Length; i++) diffList += (i > 0 ? ", " : "") + TMX::DIFFICULTY_NAMES[i];
            UI::TextDisabled("  " + diffList);
            UI::TextDisabled("InTOTD: -1 (any), 0 (Not TOTD), 1 (TOTD Only)");
            UI::TextDisabled("InCollection: -1 (any), 0 (TrackOfTheDay), 1 (ManiaClub)");
            UI::TextDisabled("IncludeTags / ExcludeTags: JSON array of tag name strings");
            UI::TextDisabled("Authors: comma-separated string  |  MapName: string");
            UI::TextDisabled("MapLimit: integer (default 25)");
            UI::TextDisabled("RelativeDays: integer (0=off, >0=rolling upload window)");
            UI::TextDisabled("AuthorTimeRange: { \"Min\": <ms>, \"Max\": <ms> }");
            UI::TextDisabled("UploadDateRange: { \"From\": \"YYYY-MM-DD\", \"To\": \"YYYY-MM-DD\" }");
            UI::TextDisabled("ForcedIncludes: JSON array of map UIDs, always included regardless of filters");
            UI::TreePop();
        }
        UI::Separator();
    }

    bool showAuditDetails = false;
    void RenderAuditSubscription(Activity@ a) {
        Subscription@ sub = Subscriptions::GetByActivity(a.Id);
        if (sub is null) return;
        UI::Separator();
        UI::Text("\\$f80" + Icons::MapMarker + "\\$z Subscription Curation Audit");

        if (a.IsAuditing) {
            UI::Text("\\$888" + Icons::Spinner + " Auditing TMX...");
        } else {
            RenderFilterSummary(sub, a);
            RenderJsonEditor(a, sub);

            if (a.AuditDone) {
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
                    if (UI::BeginTable("AuditDetails_" + a.Id, 5, UI::TableFlags::Borders | UI::TableFlags::RowBg)) {
                        UI::TableSetupColumn("Action", UI::TableColumnFlags::WidthFixed, 60);
                        UI::TableSetupColumn("Map Name", UI::TableColumnFlags::WidthStretch);
                        UI::TableSetupColumn("Author", UI::TableColumnFlags::WidthStretch);
                        UI::TableSetupColumn("Tags", UI::TableColumnFlags::WidthStretch);
                        UI::TableSetupColumn("Warn", UI::TableColumnFlags::WidthFixed, 40);
                        UI::TableHeadersRow();

                        for (uint i = 0; i < a.AuditAdded.Length; i++) {
                            TmxMap@ m = a.AuditAdded[i];
                            UI::TableNextRow();
                            UI::TableSetBgColor(UI::TableBgTarget::RowBg0, vec4(0, 0.4f, 0, 0.3f));
                            UI::TableNextColumn(); UI::Text("\\$0f0" + Icons::PlusCircle + " ADD");
                            UI::TableNextColumn(); UI::Text(m.Name);
                            MetadataOverrides::RenderOverrideMenu(m);
                            UI::TableNextColumn(); UI::Text(m.Author);
                            UI::TableNextColumn(); UI::Text(string::Join(m.Tags, ", "));
                            UI::TableNextColumn(); UI::Text(m.SizeWarning);
                        }
                        for (uint i = 0; i < a.AuditRemoved.Length; i++) {
                            UI::TableNextRow();
                            UI::TableSetBgColor(UI::TableBgTarget::RowBg0, vec4(0.4f, 0, 0, 0.3f));
                            UI::TableNextColumn(); UI::Text("\\$f00" + Icons::MinusCircle + " REM");
                            UI::TableNextColumn(); UI::Text(a.AuditRemoved[i].Name);
                            UI::TableNextColumn(); UI::Text(a.AuditRemoved[i].Author);
                            UI::TableNextColumn(); // No warning for removal
                        }
                        if (a.AuditOrderMismatch && a.AuditAdded.Length == 0 && a.AuditRemoved.Length == 0) {
                            UI::TableNextRow();
                            UI::TableNextColumn(); UI::Text("\\$ff0" + Icons::Refresh);
                            UI::TableNextColumn(); UI::Text("Maps will be reordered to match TMX subscription.");
                            UI::TableNextColumn();
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
    }

    Activity@[] GetSortedSiblings(uint folderId, Activity@[]@ items) {
        Activity@[] siblings;
        for (uint i = 0; i < items.Length; i++) if (items[i].FolderId == folderId) siblings.InsertLast(items[i]);
        // Simple sort
        for (uint i = 0; i < siblings.Length; i++) {
            for (uint j = i + 1; j < siblings.Length; j++) {
                if (siblings[i].Position > siblings[j].Position) {
                    Activity@ temp = siblings[i]; @siblings[i] = siblings[j]; @siblings[j] = temp;
                }
            }
        }
        return siblings;
    }

    void RenderGeneralSettingsTab() {
        UI::TextDisabled("Modify Club Metadata");
        
        UI::BeginGroup();
        UI::SetNextItemWidth(120);
        State::clubTag = UI::InputText("Club Tag", State::clubTag);
        if (State::clubTag.Length > 5) State::clubTag = State::clubTag.SubStr(0, 5);
        if (UI::IsItemHovered()) UI::SetTooltip("Max 5 characters");
        
        UI::SameLine();
        UI::SetNextItemWidth(UI::GetContentRegionAvail().x - 100);
        State::clubDescription = UI::InputText("Description", State::clubDescription);
        if (State::clubDescription.Length > 200) State::clubDescription = State::clubDescription.SubStr(0, 200);
        if (UI::IsItemHovered()) UI::SetTooltip("Max 200 characters");
        UI::EndGroup();

        State::clubPublic = UI::Checkbox("Public Club", State::clubPublic);
        
        UI::Separator();
        if (UI::Button(Icons::FloppyO + " Update Settings")) startnew(DoUpdateBranding, null);
    }

    void RenderClubOverridesTab() {
        if (State::SelectedClub is null) return;
        uint clubId = State::SelectedClub.Id;
        string key = tostring(clubId);

        UI::Text("\\$f80" + Icons::BuildingO + "\\$z Club-Specific Overrides");
        UI::TextDisabled("Difficulty overrides that apply only within this club.");
        UI::TextDisabled("Right-click a map in audit results to set an override for this club.");
        UI::SameLine();
        if (UI::Button(Icons::Refresh + " Sync Metadata##clubsync")) {
            startnew(SyncClubOverrides);
        }
        if (UI::IsItemHovered()) UI::SetTooltip("Re-fetch TMX data for all club overrides (updates award/download counts for sorting)");
        UI::Separator();

        ClubOverrides::Load();
        if (!ClubOverrides::data.HasKey(key) || ClubOverrides::data[key].GetKeys().Length == 0) {
            UI::TextDisabled("No per-club overrides set for " + State::SelectedClub.Name + ".");
            return;
        }

        if (UI::BeginTable("ClubOverridesTable", 5, UI::TableFlags::Resizable | UI::TableFlags::RowBg | UI::TableFlags::Borders)) {
            UI::TableSetupColumn("Map Name", UI::TableColumnFlags::WidthStretch);
            UI::TableSetupColumn("UID", UI::TableColumnFlags::WidthFixed, 200);
            UI::TableSetupColumn("Difficulty", UI::TableColumnFlags::WidthFixed, 120);
            UI::TableSetupColumn("Cached", UI::TableColumnFlags::WidthFixed, 50);
            UI::TableSetupColumn("Actions", UI::TableColumnFlags::WidthFixed, 110);
            UI::TableHeadersRow();

            string[] uids = ClubOverrides::data[key].GetKeys();
            for (uint i = 0; i < uids.Length; i++) {
                string uid = uids[i];
                Json::Value@ ovr = ClubOverrides::data[key][uid];
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
                UI::Text(ovr.HasKey("MapData") ? "\\$8f8" + Icons::Check : "\\$f44" + Icons::Times);
                if (UI::IsItemHovered()) UI::SetTooltip(ovr.HasKey("MapData") ? "Map metadata cached, smart-include active" : "No metadata - set override again or Sync to enable smart-include");
                UI::TableNextColumn();
                // Pin to campaign button
                if (UI::Button(Icons::MapMarker + "##clpin_" + i)) UI::OpenPopup("PinPopup_" + uid);
                if (UI::IsItemHovered()) UI::SetTooltip("Force-pin to a campaign");
                if (UI::BeginPopup("PinPopup_" + uid)) {
                    UI::TextDisabled("Pin to campaign:");
                    UI::Separator();
                    Subscription@[] subs = Subscriptions::GetByClub(clubId);
                    if (subs.Length == 0) {
                        UI::TextDisabled("No subscriptions in this club.");
                    }
                    for (uint s = 0; s < subs.Length; s++) {
                        bool alreadyPinned = subs[s].ForcedIncludes.Find(uid) >= 0;
                        if (alreadyPinned) {
                            if (UI::MenuItem(Icons::Check + " " + subs[s].ActivityName + "##unpin_" + s)) {
                                int idx = subs[s].ForcedIncludes.Find(uid);
                                if (idx >= 0) subs[s].ForcedIncludes.RemoveAt(idx);
                                Subscriptions::Save();
                            }
                            if (UI::IsItemHovered()) UI::SetTooltip("Click to unpin");
                        } else {
                            if (UI::MenuItem(subs[s].ActivityName + "##pin_" + s)) {
                                subs[s].ForcedIncludes.InsertLast(uid);
                                Subscriptions::Save();
                                UI::ShowNotification("Club Manager", uid.SubStr(0, 8) + "... pinned to " + subs[s].ActivityName);
                            }
                        }
                    }
                    UI::EndPopup();
                }
                UI::SameLine();
                if (UI::Button(Icons::Refresh + "##clres_" + i)) {
                    ClubOverrides::Reset(clubId, uid);
                }
                if (UI::IsItemHovered()) UI::SetTooltip("Reset Club Override");
            }
            UI::EndTable();
        }
    }
}

void SyncClubOverrides() {
    if (State::SelectedClub is null) return;
    ClubOverrides::SyncMapData(State::SelectedClub.Id);
}

void RunImportFlow() {
    ClubsTab@ tab = cast<ClubsTab>(CM_UI::GetTab("Clubs"));
    if (tab is null) return;

    tab.availableConfigs = ConfigImporter::GetAvailableConfigs();
    if (tab.availableConfigs.Length == 0) {
        UI::ShowNotification("Importer", "No .json configuration files found in storage.", vec4(0.8, 0.4, 0.1, 1), 7000);
        return;
    }
    
    tab.selectedConfig = "";
    tab.showImportModal = true;
}

void ExportMapData() {
    ClubsTab@ tab = cast<ClubsTab>(CM_UI::GetTab("Clubs"));
    if (tab is null || State::SelectedClub is null) return;
    tab.isExportingMapData = true;
    tab.exportMapDataStatus = Icons::Spinner + " Loading maps...";

    uint clubId = State::SelectedClub.Id;
    string clubName = State::SelectedClub.Name;

    // Ensure maps are loaded for all campaigns
    for (uint i = 0; i < State::ClubActivities.Length; i++) {
        Activity@ a = State::ClubActivities[i];
        if (a.Type != "campaign") continue;
        if (!a.MapsLoaded && !a.LoadingMaps) {
            a.LoadingMaps = true;
            startnew(LoadActivityMaps, a);
        }
    }
    // Wait for all campaign map loads to finish
    bool allLoaded = false;
    while (!allLoaded) {
        allLoaded = true;
        for (uint i = 0; i < State::ClubActivities.Length; i++) {
            Activity@ a = State::ClubActivities[i];
            if (a.Type != "campaign" || a.Failed) continue;
            if (!a.MapsLoaded) { allLoaded = false; break; }
        }
        if (!allLoaded) yield();
    }

    // Build JSON
    Json::Value@ root = Json::Object();
    root["clubId"] = clubId;
    root["clubName"] = clubName;

    Time::Info t = Time::ParseUTC(Time::Stamp);
    string mm = (t.Month < 10 ? "0" : "") + t.Month;
    string dd = (t.Day   < 10 ? "0" : "") + t.Day;
    root["exportedAt"] = t.Year + "-" + mm + "-" + dd;

    Json::Value@ campaigns = Json::Array();
    uint totalUids = 0;
    for (uint i = 0; i < State::ClubActivities.Length; i++) {
        Activity@ a = State::ClubActivities[i];
        if (a.Type != "campaign" || a.Failed || !a.MapsLoaded) continue;
        Json::Value@ entry = Json::Object();
        entry["name"] = a.Name;
        Json::Value@ uids = Json::Array();
        for (uint j = 0; j < a.Maps.Length; j++) {
            uids.Add(a.Maps[j].Uid);
            totalUids++;
        }
        entry["uids"] = uids;
        campaigns.Add(entry);
    }
    root["campaigns"] = campaigns;

    string path = IO::FromStorageFolder("map_dump_" + clubId + ".json");
    IO::File f;
    f.Open(path, IO::FileMode::Write);
    f.Write(Json::Write(root));
    f.Close();

    tab.exportMapDataStatus = Icons::Check + " Exported " + totalUids + " maps across " + campaigns.Length + " campaigns.";
    tab.isExportingMapData = false;
    trace("[ExportMapData] Written to: " + path);
}

void CommitImportFlow() {
    ClubsTab@ tab = cast<ClubsTab>(CM_UI::GetTab("Clubs"));
    if (tab !is null && tab.selectedConfig != "") {
        startnew(RunImportFlowInternalCommit, tab.selectedConfig);
    }
}

void RunImportFlowInternal(const string &in filename) {
    RunImportFlowCore(filename, true);
}

void RunImportFlowInternalCommit(const string &in filename) {
    RunImportFlowCore(filename, false);
}

void RunImportFlowCore(const string &in filename, bool isDryRun) {
    string path = IO::FromStorageFolder(filename);
    if (!IO::FileExists(path)) {
        UI::ShowNotification("Importer", "File not found: " + filename, vec4(0.8, 0.4, 0.1, 1), 7000);
        return;
    }

    Json::Value@ json = Json::FromFile(path);
    if (json is null || json.GetType() != Json::Type::Object) {
        UI::ShowNotification("Importer", "Failed to parse " + filename, vec4(0.8, 0.2, 0.2, 1), 7000);
        return;
    }

    ConfigImporter::Import(json, isDryRun);
}
