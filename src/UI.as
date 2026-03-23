// Club Manager - UI.as

namespace UI {
    Club@ SelectedClub;
    Activity[] ClubActivities;
    Club[] MyClubs;

    bool refreshingClubs = false;
    bool refreshingActivities = false;
    uint lastClubRefresh = 0;
    uint lastActivityRefresh = 0;
    const uint REFRESH_COOLDOWN = 10000; // 10 seconds

    // Branding state
    string iconUrl, verticalUrl, backgroundUrl;
    string grassUrl, terrainUrl, logoUrl;
    string clubTag, clubDescription;
    bool clubPublic;

    // Curation state
    TmxSearchFilters tmxFilters;
    TmxMap[] tmxSearchResults;
    bool[] tmxSelected;
    bool searchInProgress = false;
    Activity@ TargetActivity;
    Activity@ batchTargetActivity;
    string manualClubId = "";

    void RenderDashboard() {
        if (MyClubs.Length == 0 && !refreshingClubs && Time::Now > lastClubRefresh + REFRESH_COOLDOWN) {
            startnew(RefreshClubs);
        }

        UI::Separator();

        // Local copy to avoid race conditions during iteration
        auto clubs = MyClubs;
        if (UI::BeginCombo("Select Club", SelectedClub is null ? "None" : SelectedClub.Name)) {
            if (UI::Selectable("None", SelectedClub is null)) {
                @SelectedClub = null;
            }
            for (uint i = 0; i < clubs.Length; i++) {
                // Determine if user has any management role
                string role = clubs[i].Role.ToUpper();
                bool isManager = (role == "ADMIN" || role == "CREATOR" || role == "CONTENT_CREATOR");
                
                if (!isManager) continue;

                if (UI::Selectable(clubs[i].Name, SelectedClub !is null && SelectedClub.Id == clubs[i].Id)) {
                    @SelectedClub = clubs[i];
                    iconUrl = SelectedClub.IconUrl;
                    verticalUrl = SelectedClub.VerticalUrl;
                    backgroundUrl = SelectedClub.BackgroundUrl;
                    grassUrl = SelectedClub.StadiumGrassUrl;
                    terrainUrl = SelectedClub.StadiumTerrainUrl;
                    logoUrl = SelectedClub.StadiumLogoUrl;
                    clubTag = SelectedClub.Tag;
                    clubDescription = SelectedClub.Description;
                    clubPublic = SelectedClub.Public;
                    startnew(RefreshActivities);
                }
            }
            UI::EndCombo();
        }

        UI::SameLine();
        if (UI::Button(Icons::Refresh + "##RefreshClubs")) {
            startnew(RefreshClubs);
        }

        UI::SameLine();
        if (UI::Button("Refresh List")) {
            startnew(RefreshClubs);
        }

        if (SelectedClub !is null) {
            UI::Separator();
            UI::Text("Club ID: " + SelectedClub.Id);
            UI::Text("Tag: " + SelectedClub.Tag);
            
            UI::BeginTabBar("ClubTabs");
            if (true) {
                if (UI::BeginTabItem("Activities")) {
                    RenderActivityTab();
                    UI::EndTabItem();
                }
                if (UI::BeginTabItem("Branding & Images")) {
                    RenderBrandingTab();
                    UI::EndTabItem();
                }
                if (UI::BeginTabItem("Smart Curation (TMX)")) {
                    RenderCurationTab();
                    UI::EndTabItem();
                }
                UI::EndTabBar();
            }
        }
    }

    uint[] renderedIds;

    string nextActivityName = "";
    bool createAsActive = true;
    bool showCreateFolderModal = false;
    bool showCreateCampaignModal = false;
    bool showCreateRoomModal = false;
    
    string nextRoomPassword = "";
    int nextRoomMaxPlayers = 32;
    string nextRoomScript = "TrackMania/TM_TimeAttack_Online.Script.txt";


    void RenderActivityTab() {
        if (UI::Button("Refresh Activities")) {
            startnew(RefreshActivities);
        }
        UI::SameLine();
        if (UI::Button("Create Folder")) {
            nextActivityName = "New Folder";
            showCreateFolderModal = true;
        }
        UI::SameLine();
        if (UI::Button("Create Campaign")) {
            nextActivityName = "New Campaign";
            showCreateCampaignModal = true;
        }
        UI::SameLine();
        if (UI::Button("Create Room")) {
            nextActivityName = "New Room";
            nextRoomPassword = "";
            nextRoomMaxPlayers = 32;
            nextRoomScript = "TrackMania/TM_TimeAttack_Online.Script.txt";
            showCreateRoomModal = true;
        }

        if (showCreateFolderModal) {
            UI::OpenPopup("Create Folder");
            showCreateFolderModal = false;
        }
        if (UI::BeginPopupModal("Create Folder", UI::WindowFlags::AlwaysAutoResize)) {
            nextActivityName = UI::InputText("Folder Name", nextActivityName);
            if (nextActivityName.Length > 20) nextActivityName = nextActivityName.SubStr(0, 20);
            if (nextActivityName.Length >= 20) UI::Text("\\$f00Maximum name length reached (20 chars)");
            createAsActive = UI::Checkbox("Create as Active", createAsActive);
            if (UI::Button("Create")) {
                startnew(DoCreateFolder);
                UI::CloseCurrentPopup();
            }
            UI::SameLine();
            if (UI::Button("Cancel")) UI::CloseCurrentPopup();
            UI::EndPopup();
        }

        if (showCreateCampaignModal) {
            UI::OpenPopup("Create Campaign");
            showCreateCampaignModal = false;
        }
        if (UI::BeginPopupModal("Create Campaign", UI::WindowFlags::AlwaysAutoResize)) {
            nextActivityName = UI::InputText("Campaign Name", nextActivityName);
            if (nextActivityName.Length > 20) nextActivityName = nextActivityName.SubStr(0, 20);
            if (nextActivityName.Length >= 20) UI::Text("\\$f00Maximum name length reached (20 chars)");
            createAsActive = UI::Checkbox("Create as Active", createAsActive);
            if (UI::Button("Create")) {
                startnew(DoCreateCampaign);
                UI::CloseCurrentPopup();
            }
            UI::SameLine();
            if (UI::Button("Cancel")) UI::CloseCurrentPopup();
            UI::EndPopup();
        }

        if (showCreateRoomModal) {
            UI::OpenPopup("Create Room");
            showCreateRoomModal = false;
        }
        if (UI::BeginPopupModal("Create Room", UI::WindowFlags::AlwaysAutoResize)) {
            nextActivityName = UI::InputText("Room Name", nextActivityName);
            if (nextActivityName.Length > 20) nextActivityName = nextActivityName.SubStr(0, 20);
            if (nextActivityName.Length >= 20) UI::Text("\\$f00Maximum name length reached (20 chars)");
            createAsActive = UI::Checkbox("Create as Active", createAsActive);
            
            if (UI::Button("Create")) {
                startnew(DoCreateRoom);
                UI::CloseCurrentPopup();
            }
            UI::SameLine();
            if (UI::Button("Cancel")) UI::CloseCurrentPopup();
            UI::EndPopup();
        }

        UI::Separator();

        // Local copy to avoid race conditions during iteration
        auto items = ClubActivities;
        
        if (items.Length == 0 && !refreshingActivities) {
            UI::TextDisabled("No activities found for this club.");
            return;
        }

        renderedIds.RemoveRange(0, renderedIds.Length);
        UI::BeginChild("ActivityExplorer");
        
        // 1. Render root items and their children
        RenderActivities(0, items);
        // 2. Render orphans (items whose parent folder wasn't found)
        bool hasOrphans = false;
        for (uint i = 0; i < items.Length; i++) {
            bool isOrphan = false;
            if (items[i].FolderId != 0) {
                bool foundParent = false;
                for (uint j = 0; j < items.Length; j++) {
                    if (items[j].Id == items[i].FolderId) {
                        foundParent = true;
                        break;
                    }
                }
                if (!foundParent) isOrphan = true;
            }
            if (isOrphan) {
                if (!hasOrphans) {
                    UI::Separator();
                    UI::TextDisabled("Misc / Unsorted Activities");
                    hasOrphans = true;
                }
                RenderActivityNode(items[i], items);
            }
        }
        
        UI::EndChild();
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
        else if (a.Type == "map-upload") icon = Icons::MapO;
        else if (a.Type == "skin-upload") icon = Icons::PaintBrush;

        bool nodeOpen = false;
        if (a.IsRenaming) {
            UI::SetNextItemWidth(200);
            a.RenameBuffer = UI::InputText("##rename", a.RenameBuffer);
            if (a.RenameBuffer.Length > 20) a.RenameBuffer = a.RenameBuffer.SubStr(0, 20);
            if (a.RenameBuffer.Length >= 20) {
                UI::SameLine();
                UI::Text("\\$f00(Max)");
            }
            UI::SameLine();
            if (UI::Button(Icons::Check + "##confirm")) {
                if (a.RenameBuffer.Length > 0) {
                    startnew(DoRenameActivity, a);
                    a.IsRenaming = false;
                } else {
                    Notify("Name cannot be empty");
                }
            }
            UI::SameLine();
            if (UI::Button(Icons::Times + "##cancel")) {
                a.IsRenaming = false;
            }
        } else {
            string label = icon + " " + a.Name;
            if (a.Type == "campaign" || a.Type == "room") {
                label += " (" + a.Maps.Length + " maps)";
            }
            if (a.Type == "room" && a.MapsLoaded) {
                label += " (" + a.ServerStatus + ": " + a.ParticipantCount + " players)";
            }
            
            // Add status summary to label
            if (!a.Active) label = "\\$f44" + Icons::ExclamationCircle + " " + label;
            if (!a.Public) label += " \\$888" + Icons::Lock;
            if (a.Featured) label += " \\$fd0" + Icons::Star;
            if (Subscriptions::GetByActivity(a.Id) !is null) label += " \\$f80" + Icons::Rss;

            nodeOpen = UI::TreeNode(label + "##node");
            
            UI::SameLine();
            if (UI::Button(Icons::Pencil + "##rename_btn")) {
                a.IsRenaming = true;
                a.RenameBuffer = a.Name;
            }

            // Reorder buttons
            auto siblings = GetSortedSiblings(a.FolderId, items);
            int idx = -1;
            for (uint i = 0; i < siblings.Length; i++) {
                if (siblings[i].Id == a.Id) { idx = i; break; }
            }

            UI::SameLine();
            UI::BeginDisabled(idx <= 0);
            if (UI::Button(Icons::ArrowUp + "##up")) {
                startnew(DoReorderActivity, array<uint> = {a.Id, siblings[idx-1].Id});
            }
            UI::EndDisabled();

            UI::SameLine();
            UI::BeginDisabled(idx < 0 || uint(idx) >= siblings.Length - 1);
            if (UI::Button(Icons::ArrowDown + "##down")) {
                startnew(DoReorderActivity, array<uint> = {a.Id, siblings[idx+1].Id});
            }
            UI::EndDisabled();

            // Move to folder
            UI::SameLine();
            UI::SetNextItemWidth(100);
            if (UI::BeginCombo("##move", "Move...", UI::ComboFlags::NoArrowButton)) {
                if (UI::Selectable("Root", a.FolderId == 0)) {
                    startnew(DoMoveActivity, array<uint> = {a.Id, 0});
                }
                for (uint i = 0; i < items.Length; i++) {
                    if (items[i].Type == "folder" && items[i].Id != a.Id) {
                        if (a.Type == "folder" && IsDescendant(a.Id, items[i].Id, items)) continue;
                        if (UI::Selectable(items[i].Name, a.FolderId == items[i].Id)) {
                            startnew(DoMoveActivity, array<uint> = {a.Id, items[i].Id});
                        }
                    }
                }
                UI::EndCombo();
            }

            // Delete button
            UI::SameLine();
            if (a.PendingDelete) {
                if (UI::Button("Confirm?##del")) {
                    startnew(DoDeleteActivity, a);
                    a.PendingDelete = false;
                }
                UI::SameLine();
                if (UI::Button(Icons::Times + "##cancel_del")) {
                    a.PendingDelete = false;
                }
            } else {
                if (UI::Button(Icons::Trash + "##del_btn")) {
                    a.PendingDelete = true;
                }
            }
        }

        if (nodeOpen) {
            RenderActivityStatusToggles(a);
            UI::Separator();

            if (a.Type == "folder") {
                RenderActivities(a.Id, items);
            } else {
                DisplayActivityContent(a);
            }
            UI::TreePop();
        }
        
        UI::PopID();
    }

    void RenderActivityStatusToggles(Activity@ a) {
        UI::PushStyleVar(UI::StyleVar::ItemSpacing, vec2(10, 5));
        
        // Active Toggle
        if (a.Active) {
            UI::PushStyleColor(UI::Col::Button, vec4(0, 0.5f, 0, 0.6f));
            if (UI::Button(Icons::CheckCircle + " Active")) {
                startnew(DoToggleActivityActive, a);
            }
            UI::PopStyleColor();
        } else {
            UI::PushStyleColor(UI::Col::Button, vec4(0.5f, 0, 0, 0.6f));
            if (UI::Button(Icons::CircleO + " Inactive")) {
                startnew(DoToggleActivityActive, a);
            }
            UI::PopStyleColor();
        }
        UI::SameLine();

        // Public/Private Toggle
        if (a.Public) {
            UI::PushStyleColor(UI::Col::Button, vec4(0, 0.4f, 0.8f, 0.6f));
            if (UI::Button(Icons::Globe + " Public")) {
                startnew(DoToggleActivityPublic, a);
            }
            UI::PopStyleColor();
        } else {
            UI::PushStyleColor(UI::Col::Button, vec4(0.4f, 0.4f, 0.4f, 0.6f));
            if (UI::Button(Icons::Lock + " Private")) {
                startnew(DoToggleActivityPublic, a);
            }
            UI::PopStyleColor();
        }
        UI::SameLine();

        // Featured Toggle
        if (a.Featured) {
            UI::PushStyleColor(UI::Col::Button, vec4(0.9f, 0.7f, 0, 0.8f));
            if (UI::Button(Icons::Star + " Featured")) {
                startnew(DoToggleActivityFeatured, a);
            }
            UI::PopStyleColor();
        } else {
            if (UI::Button(Icons::StarO + " Feature")) {
                startnew(DoToggleActivityFeatured, a);
            }
        }

        UI::PopStyleVar();
    }

    void DisplayActivityContent(Activity@ a) {
        if (a.Type == "news") {
            if (!a.NewsLoaded && !a.LoadingMaps) {
                a.LoadingMaps = true; // Set before startnew!
                startnew(LoadActivityDetails, a);
            }
        } else if (!a.MapsLoaded && !a.LoadingMaps && a.Type != "folder") {
           a.LoadingMaps = true; // Set before startnew!
           startnew(LoadActivityMaps, a);
        }

        // RenderActivityStatusToggles(a); // Moved to RenderActivityNode
        // UI::Separator();

        if (a.LoadingMaps) {
            UI::TextDisabled("Loading content...");
        } else {
            if (a.Type == "campaign") {
                if (!a.IsManagingMaps) {
                    if (UI::Button(Icons::List + " Manage Map Order")) {
                        a.IsManagingMaps = true;
                        a.PendingMaps.RemoveRange(0, a.PendingMaps.Length);
                        for (uint i = 0; i < a.Maps.Length; i++) a.PendingMaps.InsertLast(a.Maps[i]);
                    }
                    UI::Separator();
                    for (uint i = 0; i < a.Maps.Length; i++) {
                        UI::Text(" " + (i + 1) + ". " + a.Maps[i].Name + " by " + a.Maps[i].Author);
                    }
                } else {
                    if (UI::BeginTable("MapList", 4, UI::TableFlags::RowBg | UI::TableFlags::Borders)) {
                        UI::TableSetupColumn("Order", UI::TableColumnFlags::WidthFixed, 60);
                        UI::TableSetupColumn("Map Name");
                        UI::TableSetupColumn("Author");
                        UI::TableSetupColumn("Actions", UI::TableColumnFlags::WidthFixed, 110);
                        UI::TableHeadersRow();

                        for (uint i = 0; i < a.PendingMaps.Length; i++) {
                            auto m = a.PendingMaps[i];
                            UI::PushID("map_" + i);
                            UI::TableNextRow();
                            UI::TableNextColumn();
                            UI::Text(tostring(i + 1));
                            UI::TableNextColumn();
                            UI::Text(m.Name);
                            UI::TableNextColumn();
                            UI::Text(m.Author);
                            UI::TableNextColumn();
                            
                            UI::BeginDisabled(i == 0);
                            if (UI::Button(Icons::ArrowUp + "##up")) {
                                auto temp = a.PendingMaps[i];
                                a.PendingMaps.RemoveAt(i);
                                a.PendingMaps.InsertAt(i - 1, temp);
                            }
                            UI::EndDisabled();
                            UI::SameLine();
                            UI::BeginDisabled(i == a.PendingMaps.Length - 1);
                            if (UI::Button(Icons::ArrowDown + "##down")) {
                                auto temp = a.PendingMaps[i];
                                a.PendingMaps.RemoveAt(i);
                                a.PendingMaps.InsertAt(i + 1, temp);
                            }
                            UI::EndDisabled();
                            UI::SameLine();
                            UI::PushStyleColor(UI::Col::Button, vec4(0.6, 0.1, 0.1, 1));
                            UI::PushStyleColor(UI::Col::ButtonHovered, vec4(0.8, 0.2, 0.2, 1));
                            if (UI::Button(Icons::Trash + "##del")) {
                                a.PendingMaps.RemoveAt(i);
                                UI::PopStyleColor(2);
                                UI::PopID();
                                break;
                            }
                            UI::PopStyleColor(2);
                            UI::PopID();
                        }
                        UI::EndTable();
                    }
                    if (UI::Button(Icons::FloppyO + " Save New Map Order")) {
                        startnew(DoSaveMapOrder, a);
                    }
                    UI::SameLine();
                    if (UI::Button(Icons::Times + " Cancel")) {
                        a.IsManagingMaps = false;
                    }
                    UI::TextDisabled("(Saving will update the campaign on Nadeo services)");
                }
            } else if (a.Type == "room") {
                if (a.CampaignId > 0) {
                    string campName = (a.MirroringCampaignName != "" ? a.MirroringCampaignName : "Campaign ID " + a.CampaignId);
                    UI::Text("\\$f80" + Icons::Link + "\\$z Mirroring Campaign: \\$fff" + campName);
                } else if (!a.IsManagingMaps) {
                    if (UI::Button(Icons::List + " Manage Map Order")) {
                        a.IsManagingMaps = true;
                        a.PendingMaps.RemoveRange(0, a.PendingMaps.Length);
                        for (uint i = 0; i < a.Maps.Length; i++) a.PendingMaps.InsertLast(a.Maps[i]);
                    }
                    UI::Separator();
                    


                    for (uint i = 0; i < a.Maps.Length; i++) {
                        UI::Text(" " + (i + 1) + ". " + a.Maps[i].Name + " by " + a.Maps[i].Author);
                    }
                } else {
                    if (UI::BeginTable("RoomMapList", 4, UI::TableFlags::RowBg | UI::TableFlags::Borders)) {
                        UI::TableSetupColumn("Order", UI::TableColumnFlags::WidthFixed, 60);
                        UI::TableSetupColumn("Map Name");
                        UI::TableSetupColumn("Author");
                        UI::TableSetupColumn("Actions", UI::TableColumnFlags::WidthFixed, 80);
                        UI::TableHeadersRow();

                        for (uint i = 0; i < a.PendingMaps.Length; i++) {
                            auto m = a.PendingMaps[i];
                            UI::PushID("rmap_" + i);
                            UI::TableNextRow();
                            UI::TableNextColumn();
                            UI::Text(tostring(i + 1));
                            UI::TableNextColumn();
                            UI::Text(m.Name);
                            UI::TableNextColumn();
                            UI::Text(m.Author);
                            UI::TableNextColumn();
                            
                            UI::BeginDisabled(i == 0);
                            if (UI::Button(Icons::ArrowUp + "##up")) {
                                auto temp = a.PendingMaps[i];
                                a.PendingMaps.RemoveAt(i);
                                a.PendingMaps.InsertAt(i - 1, temp);
                            }
                            UI::EndDisabled();
                            UI::SameLine();
                            UI::BeginDisabled(i == a.PendingMaps.Length - 1);
                            if (UI::Button(Icons::ArrowDown + "##down")) {
                                auto temp = a.PendingMaps[i];
                                a.PendingMaps.RemoveAt(i);
                                a.PendingMaps.InsertAt(i + 1, temp);
                            }
                            UI::EndDisabled();
                            UI::SameLine();
                            UI::PushStyleColor(UI::Col::Button, vec4(0.6, 0.1, 0.1, 1));
                            UI::PushStyleColor(UI::Col::ButtonHovered, vec4(0.8, 0.2, 0.2, 1));
                            if (UI::Button(Icons::Trash + "##del")) {
                                a.PendingMaps.RemoveAt(i);
                                UI::PopStyleColor(2);
                                UI::PopID();
                                break;
                            }
                            UI::PopStyleColor(2);
                            UI::PopID();
                        }
                        UI::EndTable();
                    }
                        if (UI::Button(Icons::FloppyO + " Save New Map Order")) {
                            startnew(DoSaveRoomMapOrder, a);
                        }
                        UI::SameLine();
                        if (UI::Button(Icons::Refresh + " Sync with Live Server")) {
                            startnew(DoSyncRoomInstance, a);
                        }

                        UI::SameLine();
                        if (UI::Button(Icons::Times + " Cancel")) {
                            a.IsManagingMaps = false;
                        }
                        UI::TextDisabled("(Saving will update the room on Nadeo services)");
                    }
                } else if (a.Type == "news") {
                UI::TextDisabled("News Content:");
                a.Headline = UI::InputText("Headline", a.Headline);
                a.Body = UI::InputTextMultiline("Body", a.Body, vec2(0, 150));
                if (UI::Button(Icons::FloppyO + " Save News Content")) {
                    startnew(DoSaveNews, a);
                }
            } else {
                for (uint i = 0; i < a.Maps.Length; i++) {
                    auto m = a.Maps[i];
                    UI::Text(" • " + m.Name + " by " + m.Author);
                }
            }
            RenderAuditSubscription(a);
        }
    }

    void RenderAuditSubscription(Activity@ a) {
        auto sub = Subscriptions::GetByActivity(a.Id);
        if (sub is null) return;

        UI::Separator();
        UI::Text("\\$f80" + Icons::MapMarker + "\\$z Subscription Curation Audit");
        UI::TextDisabled("This activity is pinned to a TMX search (" + sub.MapLimit + " maps).");
        
        if (a.IsAuditing) {
            UI::Text("\\$888" + Icons::HourglassHalf + " Auditing... comparing TMX with current maps...");
        } else {
            if (UI::Button(Icons::Search + " Audit Now")) {
                startnew(DoAuditSubscription, a);
            }
            if (sub.LastRun > 0) {
                UI::SameLine();
                UI::TextDisabled("Last audit: " + (sub.LastRun == 0 ? "Never" : "Recently"));
            }
        }

        if (a.AuditDone) {
            UI::Indent();
            if (a.AuditAdded.Length == 0 && a.AuditRemoved.Length == 0 && !a.AuditOrderMismatch) {
                UI::Text("\\$0f0" + Icons::Check + " Activity is up to date and correctly ordered.");
            } else {
                if (a.AuditOrderMismatch && a.AuditAdded.Length == 0 && a.AuditRemoved.Length == 0) {
                    UI::Text("\\$f00" + Icons::ExclamationTriangle + " Maps are out of order compared to TMX results.");
                    UI::TextDisabled("Apply changes to restore the correct TMX sequence.");
                } else if (a.AuditOrderMismatch) {
                    UI::Text("\\$f80" + Icons::ExclamationTriangle + " Content changes AND order mismatch detected.");
                }

                UI::Columns(2, "AuditCols", false);
                UI::Text("\\$0f0" + Icons::PlusCircle + " Maps to Add (" + a.AuditAdded.Length + ")");
                for (uint i = 0; i < a.AuditAdded.Length; i++) {
                    UI::TextDisabled(" • " + a.AuditAdded[i].Name);
                    if (UI::IsItemHovered()) UI::SetTooltip(a.AuditAdded[i].Author);
                }
                UI::NextColumn();
                UI::Text("\\$f00" + Icons::MinusCircle + " Maps to Remove (" + a.AuditRemoved.Length + ")");
                for (uint i = 0; i < a.AuditRemoved.Length; i++) {
                    UI::TextDisabled(" • " + a.AuditRemoved[i].Name);
                    if (UI::IsItemHovered()) UI::SetTooltip(a.AuditRemoved[i].Author);
                }
                UI::Columns(1);
                
                if (UI::Button(Icons::Play + " Apply Audit Changes")) {
                    startnew(DoApplyAudit, a);
                }
                if (UI::IsItemHovered()) {
                    string msg = "This will add the missing maps and remove the ones that dropped out";
                    if (a.AuditOrderMismatch) msg += ", and restore the correct TMX order";
                    UI::SetTooltip(msg + ".");
                }
            }
            UI::Unindent();
        }
    }

    void DoSyncRoomInstance(ref@ data) {
        Activity@ a = cast<Activity>(data);
        if (a is null || SelectedClub is null) return;
        
        Notify("Restarting room instance to sync template...");
        
        // Deactivate
        Json::Value@ offSettings = Json::Object();
        offSettings["active"] = false;
        API::EditClubActivity(SelectedClub.Id, a.Id, offSettings);
        
        yield(500); // Give Nadeo masterserver bit of time to kill the instance
        
        // Reactivate
        Json::Value@ onSettings = Json::Object();
        onSettings["active"] = true;
        API::EditClubActivity(SelectedClub.Id, a.Id, onSettings);
        
        Notify("Room instance restarted. Sync complete!");
        startnew(RefreshActivities); 
    }

    void DoSeverCampaignLink(ref@ data) {
        Activity@ a = cast<Activity>(data);
        if (a is null || SelectedClub is null) return;
        
        Notify("Severing campaign link...");
        
        Json::Value@ settings = Json::Object();
        settings["campaignId"] = Json::Value(); // Try null to clear
        auto res = API::EditClubActivity(SelectedClub.Id, a.Id, settings);
        
        if (res !is null) {
            a.CampaignId = 0;
            Notify("Room is now independent. Re-loading effective map list...");
            startnew(LoadActivityMaps, a);
        } else {
            Notify("Failed to sever campaign link.");
        }
    }

    void DoSaveRoomMapOrder(ref@ data) {
        Activity@ a = cast<Activity>(data);
        if (a is null || SelectedClub is null) return;

        string[] uids;
        for (uint i = 0; i < a.PendingMaps.Length; i++) {
            uids.InsertLast(a.PendingMaps[i].Uid);
        }

        auto res = API::SetRoomMaps(SelectedClub.Id, a.Id, uids);
        if (res !is null) {
            Notify("Room map order saved successfully!");
            NotifyInfo("Note: Use 'Sync with Live Server' to apply changes immediately.");
            a.IsManagingMaps = false;
            startnew(LoadActivityMaps, a);
        } else {
            Notify("Failed to save room map order. (Check if any maps are too large > 7MB)");
        }
    }

    void DoSaveMapOrder(ref@ data) {
        Activity@ a = cast<Activity>(data);
        if (a is null || SelectedClub is null) return;

        string[] uids;
        for (uint i = 0; i < a.PendingMaps.Length; i++) {
            uids.InsertLast(a.PendingMaps[i].Uid);
        }

        auto res = API::SetCampaignMaps(SelectedClub.Id, a.CampaignId, a.Name, uids);
        if (res !is null) {
            Notify("Campaign order saved successfully!");
            NotifyInfo("Reminder: Refresh your game/campaign in the club menu to see changes.");
            a.IsManagingMaps = false;
            startnew(LoadActivityMaps, a); // Force refresh
        } else {
            Notify("Failed to save campaign map order.");
        }
    }

    void DoRenameActivity(ref@ data) {
        Activity@ a = cast<Activity>(data);
        if (a is null || SelectedClub is null) return;

        string newName = a.RenameBuffer;
        auto json = API::RenameActivity(SelectedClub.Id, a.Id, newName);
        if (json !is null) {
            a.Name = newName;
            Notify("Activity renamed to " + newName);
        } else {
            Notify("Failed to rename activity.");
        }
    }

    Activity@[] GetSortedSiblings(uint folderId, Activity[]@ items) {
        Activity@[] siblings;
        for (uint i = 0; i < items.Length; i++) {
            if (items[i].FolderId == folderId) {
                siblings.InsertLast(items[i]);
            }
        }
        for (uint i = 0; i < siblings.Length; i++) {
            for (uint j = i + 1; j < siblings.Length; j++) {
                if (siblings[i].Position > siblings[j].Position) {
                    auto temp = siblings[i];
                    @siblings[i] = siblings[j];
                    @siblings[j] = temp;
                }
            }
        }
        return siblings;
    }

    bool IsDescendant(uint parentId, uint childId, Activity[]@ items) {
        uint currentId = childId;
        while (currentId != 0) {
            bool found = false;
            for (uint i = 0; i < items.Length; i++) {
                if (items[i].Id == currentId) {
                    if (items[i].FolderId == parentId) return true;
                    currentId = items[i].FolderId;
                    found = true;
                    break;
                }
            }
            if (!found) break;
        }
        return false;
    }

    void DoReorderActivity(ref@ data) {
        uint[] ids = cast<uint[]>(data);
        if (ids is null || ids.Length != 2 || SelectedClub is null) return;
        
        Activity@ a1; Activity@ a2;
        for (uint i = 0; i < ClubActivities.Length; i++) {
            if (ClubActivities[i].Id == ids[0]) @a1 = ClubActivities[i];
            if (ClubActivities[i].Id == ids[1]) @a2 = ClubActivities[i];
        }
        if (a1 is null || a2 is null) return;
        
        uint p1 = a1.Position; uint p2 = a2.Position;
        a1.Position = p2; a2.Position = p1; // Optimistic
        
        auto j1 = API::ReorderActivity(SelectedClub.Id, a1.Id, p2);
        auto j2 = API::ReorderActivity(SelectedClub.Id, a2.Id, p1);
        if (j1 is null || j2 is null) {
            a1.Position = p1; a2.Position = p2;
            Notify("Failed to reorder.");
        }
    }

    void DoMoveActivity(ref@ data) {
        uint[] ids = cast<uint[]>(data);
        if (ids is null || ids.Length != 2 || SelectedClub is null) return;
        
        Activity@ a;
        for (uint i = 0; i < ClubActivities.Length; i++) {
            if (ClubActivities[i].Id == ids[0]) { @a = ClubActivities[i]; break; }
        }
        if (a is null) return;
        
        uint oldFolder = a.FolderId;
        a.FolderId = ids[1]; // Optimistic
        
        auto json = API::MoveActivity(SelectedClub.Id, a.Id, ids[1]);
        if (json is null) {
            a.FolderId = oldFolder;
            Notify("Failed to move activity.");
        }
    }

    void DoDeleteActivity(ref@ data) {
        Activity@ a = cast<Activity>(data);
        if (a is null || SelectedClub is null) return;
        
        auto json = API::DeleteActivity(SelectedClub.Id, a.Id);
        if (json !is null) {
            for (uint i = 0; i < ClubActivities.Length; i++) {
                if (ClubActivities[i].Id == a.Id) {
                    ClubActivities.RemoveAt(i);
                    break;
                }
            }
            Notify("Activity deleted.");
        } else {
            Notify("Failed to delete activity.");
        }
    }

    void RenderBrandingTab() {
        UI::TextDisabled("General Settings");
        clubTag = UI::InputText("Club Tag", clubTag);
        clubDescription = UI::InputText("Description", clubDescription);
        clubPublic = UI::Checkbox("Public Club", clubPublic);

        UI::Separator();
        UI::TextDisabled("Branding Image URLs (PNG/DDS)");
        iconUrl = UI::InputText("Icon URL", iconUrl);
        verticalUrl = UI::InputText("Vertical URL", verticalUrl);
        backgroundUrl = UI::InputText("Background URL", backgroundUrl);
        
        UI::Separator();
        UI::TextDisabled("Stadium Assets");
        grassUrl = UI::InputText("Stadium Grass URL", grassUrl);
        terrainUrl = UI::InputText("Stadium Terrain URL", terrainUrl);
        logoUrl = UI::InputText("Stadium Logo URL", logoUrl);

        UI::TextWrapped("\\$iNote: For local paths, use the full path starting with C:/ or D:/. The plugin will attempt to handle them.");

        if (UI::Button("Update Branding")) {
            startnew(DoUpdateBranding);
        }
    }

    void DoUpdateBranding() {
        if (SelectedClub is null) return;
        Json::Value@ data = Json::Object();
        data["name"] = SelectedClub.Name;
        data["tag"] = clubTag;
        data["description"] = clubDescription;
        data["public"] = clubPublic;
        data["iconUrl"] = iconUrl;
        data["verticalUrl"] = verticalUrl;
        data["backgroundUrl"] = backgroundUrl;
        data["stadiumGrassUrl"] = grassUrl;
        data["stadiumTerrainUrl"] = terrainUrl;
        data["stadiumLogoUrl"] = logoUrl;
        
        auto res = API::SetClubDetails(SelectedClub.Id, data);
        if (res !is null) {
            SelectedClub.IconUrl = iconUrl;
            SelectedClub.VerticalUrl = verticalUrl;
            SelectedClub.BackgroundUrl = backgroundUrl;
            SelectedClub.StadiumGrassUrl = grassUrl;
            SelectedClub.StadiumTerrainUrl = terrainUrl;
            SelectedClub.StadiumLogoUrl = logoUrl;
            SelectedClub.Tag = clubTag;
            SelectedClub.Description = clubDescription;
            SelectedClub.Public = clubPublic;
            Notify("Branding updated.");
        } else {
            Notify("Failed to update branding.");
        }
    }

    string FormatLength(uint secs) {
        uint m = secs / 60;
        uint s = secs % 60;
        return m + ":" + (s < 10 ? "0" : "") + s;
    }

    bool ArrayContains(const string[] &in arr, const string &in value) {
        for (uint i = 0; i < arr.Length; i++) {
            if (arr[i] == value) return true;
        }
        return false;
    }

    void ArrayRemove(string[] &inout arr, const string &in value) {
        for (uint i = 0; i < arr.Length; i++) {
            if (arr[i] == value) {
                arr.RemoveAt(i);
                return;
            }
        }
    }

    void RenderCurationTab() {
        UI::BeginChild("TMXFilters", vec2(0, 300), true);

        UI::PushItemWidth(250);
        tmxFilters.AuthorName = UI::InputText("Author Name", tmxFilters.AuthorName);
        UI::PopItemWidth();
        UI::Columns(2, "VehDiffCols", false);
        UI::PushItemWidth(120);
        if (UI::BeginCombo("Vehicle", tmxFilters.Vehicle == -1 ? "Any" : TMX::VEHICLE_NAMES[tmxFilters.Vehicle])) {
            if (UI::Selectable("Any", tmxFilters.Vehicle == -1)) tmxFilters.Vehicle = -1;
            for (uint i = 0; i < TMX::VEHICLE_NAMES.Length; i++) {
                if (UI::Selectable(TMX::VEHICLE_NAMES[i], tmxFilters.Vehicle == int(i))) tmxFilters.Vehicle = i;
            }
            UI::EndCombo();
        }
        UI::NextColumn();
        if (UI::BeginCombo("Difficulty", tmxFilters.Difficulty == -1 ? "Any" : TMX::DIFFICULTY_NAMES[tmxFilters.Difficulty])) {
            if (UI::Selectable("Any", tmxFilters.Difficulty == -1)) tmxFilters.Difficulty = -1;
            for (uint i = 0; i < TMX::DIFFICULTY_NAMES.Length; i++) {
                if (UI::Selectable(TMX::DIFFICULTY_NAMES[i], tmxFilters.Difficulty == int(i))) tmxFilters.Difficulty = i;
            }
            UI::EndCombo();
        }
        UI::PopItemWidth();
        UI::Columns(1);

        // Tags section as a collapsible header
        if (UI::CollapsingHeader("Tags")) {
            UI::Indent();
            UI::TextDisabled("Include (map must have tag):");
            UI::Columns(5, "TagIncCols", false);
            for (uint i = 0; i < TMX::TAG_NAMES.Length; i++) {
                string tag = TMX::TAG_NAMES[i];
                bool checked = ArrayContains(tmxFilters.IncludeTags, tag);
                bool newVal = UI::Checkbox(tag + "##inc", checked);
                if (newVal != checked) {
                    if (newVal) tmxFilters.IncludeTags.InsertLast(tag);
                    else ArrayRemove(tmxFilters.IncludeTags, tag);
                }
                UI::NextColumn();
            }
            UI::Columns(1);

            UI::Separator();
            UI::TextDisabled("Exclude (map must NOT have tag):");
            UI::Columns(5, "TagExcCols", false);
            for (uint i = 0; i < TMX::TAG_NAMES.Length; i++) {
                string tag = TMX::TAG_NAMES[i];
                bool checked = ArrayContains(tmxFilters.ExcludeTags, tag);
                bool newVal = UI::Checkbox(tag + "##exc", checked);
                if (newVal != checked) {
                    if (newVal) tmxFilters.ExcludeTags.InsertLast(tag);
                    else ArrayRemove(tmxFilters.ExcludeTags, tag);
                }
                UI::NextColumn();
            }
            UI::Columns(1);
            UI::Unindent();
        }

        UI::Text("Time Range (H:M:S)");
        UI::BeginGroup();
        UI::PushItemWidth(50);
        tmxFilters.hFrom = UI::InputInt("##hf", tmxFilters.hFrom, 0); UI::SameLine(); UI::Text(":"); UI::SameLine();
        tmxFilters.mFrom = UI::InputInt("##mf", tmxFilters.mFrom, 0); UI::SameLine(); UI::Text(":"); UI::SameLine();
        tmxFilters.sFrom = UI::InputInt("##sf", tmxFilters.sFrom, 0); UI::SameLine(); UI::Text("to"); UI::SameLine();
        tmxFilters.hTo = UI::InputInt("##ht", tmxFilters.hTo, 0); UI::SameLine(); UI::Text(":"); UI::SameLine();
        tmxFilters.mTo = UI::InputInt("##mt", tmxFilters.mTo, 0); UI::SameLine(); UI::Text(":"); UI::SameLine();
        tmxFilters.sTo = UI::InputInt("##st", tmxFilters.sTo, 0);
        UI::PopItemWidth();
        UI::EndGroup();
        tmxFilters.TimeFromMs = (tmxFilters.hFrom * 3600 + tmxFilters.mFrom * 60 + tmxFilters.sFrom) * 1000;
        tmxFilters.TimeToMs = (tmxFilters.hTo * 3600 + tmxFilters.mTo * 60 + tmxFilters.sTo) * 1000;

        UI::Columns(2, "DateCols", false);
        UI::PushItemWidth(100);
        tmxFilters.UploadedFrom = UI::InputText("Uploaded From", tmxFilters.UploadedFrom);
        if (UI::IsItemHovered()) UI::SetTooltip("DD/MM/YYYY");
        UI::NextColumn();
        tmxFilters.UploadedTo = UI::InputText("Uploaded To", tmxFilters.UploadedTo);
        if (UI::IsItemHovered()) UI::SetTooltip("DD/MM/YYYY");
        UI::PopItemWidth();
        UI::Columns(1);

        // Collection & Sort filters on one row
        UI::Columns(3, "SortCols", false);
        string totdLabel = tmxFilters.InTOTD == -1 ? "Any TOTD" : (tmxFilters.InTOTD == 1 ? "Was TOTD" : "Not TOTD");
        UI::PushItemWidth(120);
        if (UI::BeginCombo("TOTD", totdLabel)) {
            if (UI::Selectable("Any", tmxFilters.InTOTD == -1)) tmxFilters.InTOTD = -1;
            if (UI::Selectable("Was TOTD", tmxFilters.InTOTD == 1)) tmxFilters.InTOTD = 1;
            if (UI::Selectable("Not TOTD", tmxFilters.InTOTD == 0)) tmxFilters.InTOTD = 0;
            UI::EndCombo();
        }
        UI::NextColumn();
        if (UI::BeginCombo("Primary Sort", tmxFilters.SortPrimary == -1 ? "Relevance" : TMX::SORT_OPTIONS[tmxFilters.SortPrimary])) {
            if (UI::Selectable("Relevance", tmxFilters.SortPrimary == -1)) tmxFilters.SortPrimary = -1;
            for (uint i = 0; i < TMX::SORT_OPTIONS.Length; i++) {
                if (UI::Selectable(TMX::SORT_OPTIONS[i], tmxFilters.SortPrimary == int(i))) tmxFilters.SortPrimary = i;
            }
            UI::EndCombo();
        }
        UI::NextColumn();
        if (UI::BeginCombo("Secondary Sort", tmxFilters.SortSecondary == -1 ? "None" : TMX::SORT_OPTIONS[tmxFilters.SortSecondary])) {
            if (UI::Selectable("None", tmxFilters.SortSecondary == -1)) tmxFilters.SortSecondary = -1;
            for (uint i = 0; i < TMX::SORT_OPTIONS.Length; i++) {
                if (UI::Selectable(TMX::SORT_OPTIONS[i], tmxFilters.SortSecondary == int(i))) tmxFilters.SortSecondary = i;
            }
            UI::EndCombo();
        }
        UI::PopItemWidth();
        UI::Columns(1);

        UI::Separator();
        tmxFilters.PrimaryTagOnly = UI::Checkbox("Primary Tag Only", tmxFilters.PrimaryTagOnly);
        UI::SameLine();
        tmxFilters.PrimarySurfaceOnly = UI::Checkbox("Primary Surface Only", tmxFilters.PrimarySurfaceOnly);
        if (tmxFilters.PrimarySurfaceOnly) tmxFilters.PrimaryTagOnly = false;
        if (tmxFilters.PrimaryTagOnly) tmxFilters.PrimarySurfaceOnly = false;
        UI::SameLine();
        tmxFilters.HideOversized = UI::Checkbox("Hide Over-sized Maps", tmxFilters.HideOversized);
        UI::EndChild();

        UI::SetNextItemWidth(100);
        tmxFilters.ResultLimit = uint(UI::InputInt("Limit", int(tmxFilters.ResultLimit)));
        if (tmxFilters.ResultLimit < 1) tmxFilters.ResultLimit = 1;
        if (tmxFilters.ResultLimit > 100) tmxFilters.ResultLimit = 100;
        
        UI::SameLine();
        if (UI::Button("Find Maps on TMX") && !searchInProgress) {
            tmxFilters.CurrentPage = 1;
            tmxFilters.PageStartingTrackIds.RemoveRange(0, tmxFilters.PageStartingTrackIds.Length);
            tmxFilters.PageStartingTrackIds.InsertLast(0);
            startnew(SearchTMX);
        }
        UI::SameLine();
        if (UI::Button(Icons::AngleLeft + " Prev Page") && !searchInProgress && tmxFilters.CurrentPage > 1) {
            tmxFilters.CurrentPage--;
            startnew(SearchTMX);
        }
        UI::SameLine();
        UI::Text("Page " + tmxFilters.CurrentPage);
        UI::SameLine();
        bool canGoNext = tmxFilters.CurrentPage < int(tmxFilters.PageStartingTrackIds.Length);
        if (UI::Button("Next Page " + Icons::AngleRight) && !searchInProgress && canGoNext) {
            tmxFilters.CurrentPage++;
            startnew(SearchTMX);
        }
        if (searchInProgress) {
            UI::SameLine(); UI::TextDisabled("Searching... (Offset: " + tmxFilters.Offset + ")");
        }

        auto results = tmxSearchResults;
        if (results.Length > 0) {
            UI::Separator();
            UI::BeginGroup();
            UI::TextDisabled("Batch Add to Campaign:");
            UI::SameLine();
            UI::SetNextItemWidth(200);
            if (UI::BeginCombo("##batch_target", batchTargetActivity is null ? "Select Campaign..." : batchTargetActivity.Name)) {
                for (uint i = 0; i < ClubActivities.Length; i++) {
                    if (ClubActivities[i].Type == "campaign" || ClubActivities[i].Type == "room") {
                        if (UI::Selectable(ClubActivities[i].Name + " (" + ClubActivities[i].Type + ")", batchTargetActivity !is null && batchTargetActivity.Id == ClubActivities[i].Id)) {
                            @batchTargetActivity = ClubActivities[i];
                        }
                    }
                }
                UI::EndCombo();
            }
            UI::SameLine();
            uint selectCount = 0;
            for (uint i = 0; i < tmxSelected.Length; i++) if (tmxSelected[i]) selectCount++;
            UI::BeginDisabled(batchTargetActivity is null || selectCount == 0);
            if (UI::Button("Add " + selectCount + " Selected Maps")) {
                startnew(DoBatchAdd);
            }
            UI::EndDisabled();

            UI::SameLine();
            UI::BeginDisabled(batchTargetActivity is null);
            auto existingSub = Subscriptions::GetByActivity(batchTargetActivity is null ? 0 : batchTargetActivity.Id);
            if (existingSub is null) {
                if (UI::Button(Icons::MapMarker + " Pin Search")) {
                    Subscription sub;
                    sub.ActivityId = batchTargetActivity.Id;
                    sub.ActivityName = batchTargetActivity.Name;
                    trace("Pinning search. Current Page in UI: " + tmxFilters.CurrentPage);
                    @sub.Filters = TmxSearchFilters(tmxFilters.ToJson()); // Clone
                    Subscriptions::Add(sub);
                    Notify("Search pinned to " + batchTargetActivity.Name);
                }
                if (UI::IsItemHovered()) UI::SetTooltip("Save these filters as a 'Subscription' for this activity.\nYou can then 'Audit' the activity to see which maps should be added/removed.");
            } else {
                if (UI::Button(Icons::MapMarker + " Update Pin")) {
                    @existingSub.Filters = TmxSearchFilters(tmxFilters.ToJson()); // Clone
                    existingSub.ActivityName = batchTargetActivity.Name;
                    Subscriptions::Save();
                    Notify("Subscription updated for " + batchTargetActivity.Name);
                }
                UI::SameLine();
                UI::PushStyleColor(UI::Col::Button, vec4(0.6, 0.2, 0.2, 0.6));
                if (UI::Button(Icons::Times + "##unpin")) {
                    Subscriptions::Remove(batchTargetActivity.Id);
                    Notify("Subscription removed.");
                }
                UI::PopStyleColor();
                if (UI::IsItemHovered()) UI::SetTooltip("Remove subscription");
            }
            UI::EndDisabled();
            UI::EndGroup();
            UI::Separator();
            UI::Separator();
            
            if (UI::Button("Select All")) {
                for (uint i = 0; i < tmxSelected.Length; i++) tmxSelected[i] = true;
            }
            UI::SameLine();
            if (UI::Button("Deselect All")) {
                for (uint i = 0; i < tmxSelected.Length; i++) tmxSelected[i] = false;
            }

            UI::Separator();

            UI::SetNextItemWidth(UI::GetContentRegionAvail().x * 0.95f);
            if (UI::BeginTable("TMX Results", 11, UI::TableFlags::RowBg | UI::TableFlags::ScrollY | UI::TableFlags::Resizable)) {
                UI::TableSetupColumn("Sel", UI::TableColumnFlags::WidthFixed, 30);
                UI::TableSetupColumn("Thumb", UI::TableColumnFlags::WidthFixed, 40);
                UI::TableSetupColumn("Map Name");
                UI::TableSetupColumn("Author");
                UI::TableSetupColumn("Length");
                UI::TableSetupColumn("Difficulty");
                UI::TableSetupColumn("Awards");
                UI::TableSetupColumn("Tags");
                UI::TableSetupColumn("Size", UI::TableColumnFlags::WidthFixed, 50);
                UI::TableSetupColumn("AT Beaten", UI::TableColumnFlags::WidthFixed, 60);
                UI::TableSetupColumn("TMX ID", UI::TableColumnFlags::WidthFixed, 60);
                UI::TableHeadersRow();

                for (uint i = 0; i < results.Length; i++) {
                    auto m = results[i];
                    UI::TableNextRow();
                    
                    UI::TableNextColumn();
                    if (i < tmxSelected.Length) {
                        tmxSelected[i] = UI::Checkbox("##sel" + i, tmxSelected[i]);
                    } else {
                        UI::TextDisabled("...");
                    }

                    UI::TableNextColumn();
                    if (m.HasScreenshot) UI::Text(Icons::PictureO); else UI::Text("");

                    UI::TableNextColumn(); UI::Text(m.Name);
                    UI::TableNextColumn(); UI::Text(m.Author);
                    UI::TableNextColumn(); UI::Text(FormatTime(m.LengthSecs * 1000));
                    UI::TableNextColumn(); UI::Text(m.DifficultyName);
                    UI::TableNextColumn(); UI::Text(tostring(m.AwardCount));
                    
                    UI::TableNextColumn(); 
                    string tagsStr = "";
                    for (uint j = 0; j < m.Tags.Length; j++) {
                        tagsStr += (j > 0 ? ", " : "") + m.Tags[j];
                    }
                    UI::Text(tagsStr);
                    
                    UI::TableNextColumn();
                    bool hardLimit = m.ServerSizeExceeded || m.EmbeddedItemsSize > 6500000;
                    bool softLimit = !hardLimit && (m.EmbeddedItemsSize > 4000000 || m.DisplayCost > 13000);
                    
                    if (hardLimit) {
                        UI::PushStyleColor(UI::Col::Text, vec4(1, 0, 0, 1)); // Red
                        UI::Text(Icons::ExclamationTriangle);
                        UI::PopStyleColor();
                    } else if (softLimit) {
                        UI::PushStyleColor(UI::Col::Text, vec4(1, 1, 0, 1)); // Yellow
                        UI::Text(Icons::ExclamationTriangle);
                        UI::PopStyleColor();
                    } else if (m.EmbeddedItemsSize > 0) {
                        UI::TextDisabled(tostring(m.EmbeddedItemsSize / 1024) + " KB");
                    }
                    
                    if ((hardLimit || softLimit || m.EmbeddedItemsSize > 0) && UI::IsItemHovered()) {
                        string tt = "";
                        if (hardLimit) tt += "\\$f00Critical: Exceeds room size limits.\\$z\n";
                        else if (softLimit) tt += "\\$ff0Warning: High item size or cost.\\$z\n";
                        
                        tt += "Items Size: " + (m.EmbeddedItemsSize / 1024) + " KB";
                        if (m.DisplayCost > 0) tt += "\nDisplay Cost: " + m.DisplayCost;
                        UI::SetTooltip(tt);
                    }
                    
                    UI::TableNextColumn(); UI::Text(m.AtBeaten ? Icons::Check : "-");
                    
                    UI::TableNextColumn();
                    if (UI::Button(tostring(m.TrackId) + "##id")) {
                        OpenBrowserURL("https://trackmania.exchange/maps/" + m.TrackId);
                    }
                }
                UI::EndTable();
            }

        }
    }

    void AddTmxMapToCampaign(ref@ m_raw) {
        TmxMap@ m = cast<TmxMap>(m_raw);
        if (m is null || TargetActivity is null || SelectedClub is null) return;
        
        uint clubId = SelectedClub.Id;
        uint campaignId = TargetActivity.CampaignId;
        string activityName = TargetActivity.Name;
        
        Notify("Adding " + m.Name + " to " + activityName);
        
        auto mapsJson = API::GetCampaignMaps(clubId, campaignId);
        string[] uids;
        string campaignName = activityName;

        // Extract campaign name from response if available
        if (mapsJson !is null && mapsJson.HasKey("campaign") && mapsJson["campaign"].GetType() == Json::Type::Object) {
            auto camp = mapsJson["campaign"];
            if (camp.HasKey("name")) campaignName = string(camp["name"]);
        }

        Json::Value@ list = GetMapListFromJson(mapsJson);
        if (list is null && mapsJson !is null && mapsJson.HasKey("campaign")) @list = GetMapListFromJson(mapsJson["campaign"]);
        
        if (list !is null && list.GetType() == Json::Type::Array) {
            for (uint i = 0; i < list.Length; i++) {
                auto item = list[i];
                if (item.HasKey("mapUid")) uids.InsertLast(item["mapUid"]);
                else if (item.GetType() == Json::Type::String) uids.InsertLast(item);
            }
        }
        
        if (uids.Find(m.Uid) < 0) {
            uids.InsertLast(m.Uid);
            API::SetCampaignMaps(clubId, campaignId, campaignName, uids);
            Notify("Map added successfully to " + activityName);
        } else {
            Notify("Map already in campaign.");
        }
    }

    void DoBatchAdd() {
        if (batchTargetActivity is null || SelectedClub is null) return;
        
        string[] toAdd;
        for (uint i = 0; i < tmxSearchResults.Length; i++) {
            if (i < tmxSelected.Length && tmxSelected[i]) {
                toAdd.InsertLast(tmxSearchResults[i].Uid);
            }
        }
        
        if (toAdd.Length == 0) return;
        
        Notify("Batch adding " + toAdd.Length + " maps to " + batchTargetActivity.Name + "...");
        
        uint clubId = SelectedClub.Id;
        string campaignName = batchTargetActivity.Name;
        Json::Value@ mapsJson;
        if (batchTargetActivity.Type == "campaign") {
            @mapsJson = API::GetCampaignMaps(clubId, batchTargetActivity.CampaignId);
        } else if (batchTargetActivity.Type == "room") {
            @mapsJson = API::GetClubRoom(clubId, batchTargetActivity.RoomId);
        }
        string[] currentUids;
        // Extract campaign name from response if available
        if (batchTargetActivity.Type == "campaign" && mapsJson !is null && mapsJson.GetType() == Json::Type::Object && mapsJson.HasKey("campaign") && mapsJson["campaign"].GetType() == Json::Type::Object) {
            auto camp = mapsJson["campaign"];
            if (camp.HasKey("name")) campaignName = string(camp["name"]);
        }

        Json::Value@ list = GetMapListFromJson(mapsJson);
        if (list is null && mapsJson !is null && mapsJson.GetType() == Json::Type::Object) {
            if (mapsJson.HasKey("campaign")) @list = GetMapListFromJson(mapsJson["campaign"]);
            else if (mapsJson.HasKey("room")) @list = GetMapListFromJson(mapsJson["room"]);
        }
        
        if (list !is null && list.GetType() == Json::Type::Array) {
            for (uint i = 0; i < list.Length; i++) {
                auto item = list[i];
                if (item.GetType() == Json::Type::Object && item.HasKey("mapUid")) currentUids.InsertLast(item["mapUid"]);
                else if (item.GetType() == Json::Type::String) currentUids.InsertLast(item);
            }
        }
        
        uint added = 0;
        uint skipped = 0;
        string[] finalUids = currentUids;
        for (uint i = 0; i < toAdd.Length; i++) {
            if (finalUids.Find(toAdd[i]) < 0) {
                finalUids.InsertLast(toAdd[i]);
                added++;
            } else {
                skipped++;
            }
        }
        
        if (added > 0) {
            Json::Value@ res;
            if (batchTargetActivity.Type == "campaign") {
                @res = API::SetCampaignMaps(clubId, batchTargetActivity.CampaignId, campaignName, finalUids);
            } else if (batchTargetActivity.Type == "room") {
                @res = API::SetRoomMaps(clubId, batchTargetActivity.RoomId, finalUids);
            }
            if (res !is null) {
                Notify("Added " + added + " maps (" + skipped + " already present)");
                NotifyInfo("Maps added. Reminder: Refresh your game/campaign in the club menu to see changes.");
                // Optionally reset selection
                for (uint i = 0; i < tmxSelected.Length; i++) tmxSelected[i] = false;
            } else {
                Notify("Failed to save " + batchTargetActivity.Type + " maps.");
            }
        } else {
            Notify("No new maps added (" + skipped + " already present)");
        }
    }

    TmxMap[] FetchMapsSequential(TmxSearchFilters@ f, uint limit, bool applyOffset = true) {
        TmxMap[] allMatches;
        TmxSearchFilters@ tempFilters = TmxSearchFilters(f.ToJson());
        int lastAnalysedId = 0;
        if (f.CurrentPage > 1 && f.CurrentPage <= int(f.PageStartingTrackIds.Length)) {
            lastAnalysedId = f.PageStartingTrackIds[f.CurrentPage - 1];
        }
        uint batches = 0;
        bool hasMore = true;
        
        while (allMatches.Length < limit && hasMore && batches < 5) {
            batches++;
            auto json = API::SearchMaps(tempFilters, 100);
            if (json is null) break;
            
            Json::Value@ results = (json.HasKey("Results")) ? json["Results"] : json;
            if (results.GetType() != Json::Type::Array || results.Length == 0) break;
            
            // Only apply offset on the first batch, and only if requested (audits do, UI doesn't)
            int batchLastId = 0;
            auto batch = FilterTmxResults(results, f, limit - allMatches.Length, applyOffset && (batches == 1), batchLastId);
            if (batchLastId > 0) lastAnalysedId = batchLastId;
            for (uint i = 0; i < batch.Length; i++) allMatches.InsertLast(batch[i]);
            
            hasMore = json.HasKey("More") && bool(json["More"]);
            if (!hasMore) break;
            
            // Advance cursor for next batch
            tempFilters.PageStartingTrackIds.InsertLast(lastAnalysedId);
            tempFilters.CurrentPage++;
        }
        
        // Save the TrackId for the next page in the original filters object
        if (f.CurrentPage == int(f.PageStartingTrackIds.Length)) {
            if (hasMore) {
                f.PageStartingTrackIds.InsertLast(lastAnalysedId);
            }
        }
        return allMatches;
    }

    bool IsSurfaceTag(const string &in tag) {
        for (uint i = 0; i < TMX::SURFACE_TAGS.Length; i++) {
            if (TMX::SURFACE_TAGS[i] == tag) return true;
        }
        return false;
    }

    void SearchTMX() {
        if (searchInProgress) return;
        searchInProgress = true;
        
        tmxSearchResults.RemoveRange(0, tmxSearchResults.Length);
        
        // We want to update the cursors as we go, so we use a temp internal loop
        TmxSearchFilters@ tempFilters = TmxSearchFilters(tmxFilters.ToJson());
        int lastAnalysedId = 0;
        if (tmxFilters.CurrentPage > 1 && tmxFilters.CurrentPage <= int(tmxFilters.PageStartingTrackIds.Length)) {
            lastAnalysedId = tmxFilters.PageStartingTrackIds[tmxFilters.CurrentPage - 1];
        }
        uint batches = 0;
        bool hasMore = true;
        
        while (tmxSearchResults.Length < tmxFilters.ResultLimit && hasMore && batches < 5) {
            batches++;
            auto json = API::SearchMaps(tempFilters, 100);
            if (json is null) break;
            
            Json::Value@ results = (json.HasKey("Results")) ? json["Results"] : json;
            if (results.GetType() != Json::Type::Array || results.Length == 0) break;
            
            int batchLastId = 0;
            auto batch = FilterTmxResults(results, tmxFilters, tmxFilters.ResultLimit - tmxSearchResults.Length, false, batchLastId);
            if (batchLastId > 0) lastAnalysedId = batchLastId;
            for (uint i = 0; i < batch.Length; i++) tmxSearchResults.InsertLast(batch[i]);
            
            hasMore = json.HasKey("More") && bool(json["More"]);
            // Advance cursor for next batch
            tempFilters.PageStartingTrackIds.InsertLast(lastAnalysedId);
            tempFilters.CurrentPage++;
        }
        
        if (hasMore) {
            // The TrackId for the NEXT page should always be updated to our last analysed ID
            if (int(tmxFilters.PageStartingTrackIds.Length) <= tmxFilters.CurrentPage) {
                tmxFilters.PageStartingTrackIds.InsertLast(lastAnalysedId);
            } else {
                tmxFilters.PageStartingTrackIds[tmxFilters.CurrentPage] = lastAnalysedId;
            }
        }

        // Always ensure selection array matches results, even if we crashed/returned early
        tmxSelected.RemoveRange(0, tmxSelected.Length);
        for (uint i = 0; i < tmxSearchResults.Length; i++) tmxSelected.InsertLast(false);
        
        print("Found " + tmxSearchResults.Length + " maps on TMX (after " + batches + " batches).");
        searchInProgress = false;
    }

    TmxMap[] FilterTmxResults(Json::Value@ results, TmxSearchFilters@ f, uint limit, bool applyOffset, int &out lastTrackId) {
        TmxMap[] filtered;
        if (results is null || results.GetType() != Json::Type::Array) return filtered;
        
        uint skipCount = (applyOffset && f.CurrentPage > 1) ? (uint(f.CurrentPage - 1) * limit) : 0;
        uint matchesFound = 0;
        trace("FilterTmxResults: Page=" + f.CurrentPage + " limit=" + limit + " skipCount=" + skipCount + " applyOffset=" + applyOffset + " results=" + results.Length);

        lastTrackId = 0;
        for (uint i = 0; i < results.Length; i++) {
            lastTrackId = int(results[i]["MapId"]);
            TmxMap m(results[i]);
            // Filter by primary tag if enabled
            if (f.PrimaryTagOnly && f.IncludeTags.Length > 0) {
                string searchTag = f.IncludeTags[0];
                if (m.Tags.Length == 0 || m.Tags[0] != searchTag) continue;
            }

            if (f.PrimarySurfaceOnly && f.IncludeTags.Length > 0) {
                string searchTag = f.IncludeTags[0];
                string firstSurface = "";
                for (uint j = 0; j < m.Tags.Length; j++) {
                    if (IsSurfaceTag(m.Tags[j])) {
                        firstSurface = m.Tags[j];
                        break;
                    }
                }
                if (firstSurface != searchTag) continue;
            }
            // Filter by size/cost if enabled
            if (f.HideOversized) {
                bool hardLimit = m.ServerSizeExceeded || m.EmbeddedItemsSize > 6500000;
                bool softLimit = m.EmbeddedItemsSize > 4000000 || m.DisplayCost > 13000;
                if (hardLimit || softLimit) continue;
            }
            
            matchesFound++;
            if (matchesFound <= skipCount) continue;

            filtered.InsertLast(m);
            if (filtered.Length >= limit) break;
        }
        return filtered;
    }

    Json::Value@ GetMapListFromJson(Json::Value@ json) {
        if (json is null) return null;
        if (json.GetType() == Json::Type::Array) return json;
        if (json.GetType() != Json::Type::Object) return null;

        // Check various keys for playlist/map list
        string[] keys = {"playlist", "maps", "mapList", "mapUidList", "list"};
        for (uint i = 0; i < keys.Length; i++) {
            if (json.HasKey(keys[i]) && json[keys[i]].GetType() == Json::Type::Array) return json[keys[i]];
        }

        // Campaign/Room nested objects
        string[] nested = {"campaign", "room", "resource"};
        for (uint i = 0; i < nested.Length; i++) {
            if (json.HasKey(nested[i]) && json[nested[i]].GetType() == Json::Type::Object) {
                auto res = GetMapListFromJson(json[nested[i]]);
                if (res !is null) return res;
            }
        }

        return null;
    }

    void LoadActivityDetails(ref@ data) {
        Activity@ a = cast<Activity>(data);
        if (a is null || SelectedClub is null) return;
        
        auto json = API::GetActivity(SelectedClub.Id, a.Id, a.Type);
        if (json !is null) {
            if (a.Type == "room") {
                if (json.HasKey("room") && json["room"].GetType() == Json::Type::Object) {
                    auto r = json["room"];
                    if (r.HasKey("script")) a.Script = string(r["script"]);
                    if (r.HasKey("maxPlayers")) a.MaxPlayers = int(r["maxPlayers"]);
                    if (r.HasKey("password")) a.Password = string(r["password"]);
                }
            }
            // Handle both nested and flat responses
            auto act = (json.HasKey("activity") ? json["activity"] : 
                       (json.HasKey("news") ? json["news"] : json));
            
            
            if (act.HasKey("headline")) a.Headline = string(act["headline"]);
            else if (act.HasKey("name")) a.Headline = string(act["name"]);
            
            if (act.HasKey("body")) {
                a.Body = string(act["body"]);
            } else if (act.HasKey("description")) {
                a.Body = string(act["description"]);
            } else {
                warn("No body or description field found in details for " + a.Type + " " + a.Id);
            }
            
        } else {
            warn("Failed to load details for " + a.Type + " " + a.Id);
        }
        a.NewsLoaded = true; // Set this even on failure to stop infinite reload loops
        a.LoadingMaps = false;
    }

    void DoToggleActivityActive(ref@ data) {
        Activity@ a = cast<Activity>(data);
        if (a is null || SelectedClub is null) return;
        
        bool newState = !a.Active;
        auto json = API::SetActivityStatus(SelectedClub.Id, a.Id, newState);
        if (json !is null) {
            a.Active = newState;
            Notify("Activity " + (newState ? "activated" : "deactivated"));
        } else {
            Notify("Failed to change activity status.");
        }
    }

    void DoToggleActivityPublic(ref@ data) {
        Activity@ a = cast<Activity>(data);
        if (a is null || SelectedClub is null) return;
        
        bool newState = !a.Public;
        auto json = API::SetActivityPrivacy(SelectedClub.Id, a.Id, newState);
        if (json !is null) {
            a.Public = newState;
            Notify("Activity set to " + (newState ? "Public" : "Private"));
        } else {
            Notify("Failed to change privacy status.");
        }
    }

    void DoToggleActivityFeatured(ref@ data) {
        Activity@ a = cast<Activity>(data);
        if (a is null || SelectedClub is null) return;
        
        bool newState = !a.Featured;
        auto json = API::SetActivityFeatured(SelectedClub.Id, a.Id, newState);
        if (json !is null) {
            a.Featured = newState;
            Notify("Activity " + (newState ? "featured" : "unfeatured"));
        } else {
            Notify("Failed to change featured status.");
        }
    }

    void DoSaveNews(ref@ data) {
        Activity@ a = cast<Activity>(data);
        if (a is null || SelectedClub is null) return;
        
        auto json = API::SetNewsDetails(SelectedClub.Id, a.Id, a.Name, a.Headline, a.Body);
        if (json !is null) {
            Notify("News content saved.");
        } else {
            Notify("Failed to save news content.");
        }
    }

    void LoadActivityMaps(ref@ data) {
        Activity@ a = cast<Activity>(data);
        if (a is null || SelectedClub is null) return;
        
        a.LoadingMaps = true;
        a.Maps.RemoveRange(0, a.Maps.Length);
        uint clubId = SelectedClub.Id;
        string[] uids;

        if (a.Type == "campaign") {
            auto json = API::GetCampaignMaps(clubId, a.CampaignId);
            trace("GetCampaignMaps(" + a.CampaignId + ") raw response: " + (json is null ? "null" : Json::Write(json)));
            if (json !is null) {
                // Check top level, then check inside "campaign" object
                Json::Value@ list = GetMapListFromJson(json);
                if (list is null && json.HasKey("campaign")) @list = GetMapListFromJson(json["campaign"]);

                if (list !is null && list.GetType() == Json::Type::Array) {
                    for (uint i = 0; i < list.Length; i++) {
                        auto item = list[i];
                        if (item.HasKey("mapUid")) {
                            uids.InsertLast(string(item["mapUid"]).Trim());
                        }
                    }
                }
            }
        } else if (a.Type == "room") {
            auto json = API::GetClubRoom(clubId, a.RoomId);
            trace("GetClubRoom(" + a.RoomId + ") raw response: " + (json is null ? "null" : Json::Write(json)));
            if (json !is null) {
                // Check if this room is mirroring a campaign
                uint campaignId = 0;
                if (json.HasKey("campaignId") && json["campaignId"].GetType() == Json::Type::Number) {
                    campaignId = uint(json["campaignId"]);
                } else if (json.HasKey("room") && json["room"].HasKey("campaignId") && json["room"]["campaignId"].GetType() == Json::Type::Number) {
                    campaignId = uint(json["room"]["campaignId"]);
                }
                a.CampaignId = campaignId; // Update so SEVER button shows up
                
                Json::Value@ list = null;
                if (campaignId > 0) {
                    trace("Room " + a.Id + " is mirroring Campaign ID " + campaignId + ". Fetching campaign maps.");
                    uint campaignActivityId = 0;
                    for (uint i = 0; i < ClubActivities.Length; i++) {
                        if (ClubActivities[i].Type == "campaign" && ClubActivities[i].CampaignId == campaignId) {
                            campaignActivityId = ClubActivities[i].Id;
                            a.MirroringCampaignName = ClubActivities[i].Name;
                            break;
                        }
                    }
                    if (campaignActivityId > 0) {
                        auto campJson = API::GetCampaignMaps(clubId, campaignActivityId);
                        @list = GetMapListFromJson(campJson);
                        if (list is null && campJson.HasKey("campaign")) @list = GetMapListFromJson(campJson["campaign"]);
                    } else {
                        trace("Could not find campaign activity for mirroring campaignId " + campaignId);
                    }
                }

                if (list is null) {
                    @list = GetMapListFromJson(json);
                    if (list is null && json.HasKey("room")) @list = GetMapListFromJson(json["room"]);
                }

                if (list !is null && list.GetType() == Json::Type::Array) {
                    for (uint i = 0; i < list.Length; i++) {
                        auto item = list[i];
                        string uid = "";
                        if (item.GetType() == Json::Type::Object && item.HasKey("mapUid")) uid = string(item["mapUid"]).Trim();
                        else if (item.GetType() == Json::Type::String) uid = string(item).Trim();
                        
                        if (uid != "" && !uid.Contains(":error-")) uids.InsertLast(uid);
                    }
                }
            }
        }

        trace("Found " + uids.Length + " map UIDs for " + a.Name);
        if (uids.Length > 0) {
            trace("Fetching metadata for " + uids.Length + " maps...");
            
            // Process in batches of 100 (API limit)
            for (uint i = 0; i < uids.Length; i += 100) {
                string[] batch;
                for (uint j = i; j < i + 100 && j < uids.Length; j++) {
                    batch.InsertLast(uids[j]);
                }
                
                auto mapsJson = API::GetMapsInfo(batch);
                if (mapsJson !is null) {
                    Json::Value@ list = null;
                    if (mapsJson.GetType() == Json::Type::Array) @list = mapsJson;
                    else if (mapsJson.HasKey("mapList")) @list = mapsJson["mapList"];

                    if (list !is null) {
                        for (uint k = 0; k < list.Length; k++) {
                            a.Maps.InsertLast(MapInfo(list[k]));
                        }
                    }
                }
            }

            // Important: API might return maps in different order. Reorder a.Maps to match 'uids' array.
            MapInfo[] ordered;
            for (uint i = 0; i < uids.Length; i++) {
                for (uint j = 0; j < a.Maps.Length; j++) {
                    if (a.Maps[j].Uid == uids[i]) {
                        ordered.InsertLast(a.Maps[j]);
                        break;
                    }
                }
            }
            a.Maps = ordered;

            // Fallback for any UIDs that didn't get metadata
            if (a.Maps.Length < uids.Length) {
                for (uint i = 0; i < uids.Length; i++) {
                    bool found = false;
                    for (uint j = 0; j < a.Maps.Length; j++) {
                        if (a.Maps[j].Uid == uids[i]) {
                            found = true;
                            break;
                        }
                    }
                    if (!found) {
                        MapInfo m;
                        m.Uid = uids[i];
                        m.Name = "Unknown Map (" + uids[i] + ")";
                        m.Author = "Unknown";
                        a.Maps.InsertLast(m);
                    }
                }
            }

            // Resolve author names
            string[] authorIds;
            for (uint i = 0; i < a.Maps.Length; i++) {
                if (a.Maps[i].AuthorWebServicesId != "" && authorIds.Find(a.Maps[i].AuthorWebServicesId) < 0) {
                    authorIds.InsertLast(a.Maps[i].AuthorWebServicesId);
                }
            }
            
            if (authorIds.Length > 0) {
                trace("Resolving " + authorIds.Length + " author names...");
                auto resolvedNames = API::GetDisplayNames(authorIds);
                for (uint i = 0; i < a.Maps.Length; i++) {
                    int idx = authorIds.Find(a.Maps[i].AuthorWebServicesId);
                    if (idx >= 0 && uint(idx) < resolvedNames.Length) {
                        a.Maps[i].Author = resolvedNames[idx];
                    }
                }
            }
        }

        a.MapsLoaded = true;
        a.LoadingMaps = false;
        trace("Finished loading " + a.Maps.Length + " maps for " + a.Name);
    }

    void RefreshClubs() {
        if (refreshingClubs) return;
        refreshingClubs = true;
        lastClubRefresh = Time::Now;

        trace("Refreshing clubs...");
        Club[] items;

        try {
            auto resp = API::GetMyClubs(100, 0);
            if (resp is null || !resp.HasKey("clubList")) {
                warn("GetMyClubs: unexpected response - " + (resp is null ? "null" : Json::Write(resp)));
                refreshingClubs = false;
                return;
            }

            auto list = resp["clubList"];
            uint maxPage = resp.HasKey("maxPage") ? uint(resp["maxPage"]) : 1;

            for (uint i = 0; i < list.Length; i++) {
                try {
                    Club c(list[i]);
                    if (c.Id != 0) {
                        items.InsertLast(c);
                        trace("Found Club: " + c.Name + " (ID: " + c.Id + ") | Role: " + c.Role);
                    }
                } catch {
                    warn("Failed to parse club " + i);
                }
            }

            // Fetch additional pages if needed (page 2 onwards)
            for (uint page = 2; page <= maxPage; page++) {
                auto pageResp = API::GetMyClubs(100, (page - 1) * 100);
                if (pageResp is null || !pageResp.HasKey("clubList")) break;
                auto pageList = pageResp["clubList"];
                for (uint i = 0; i < pageList.Length; i++) {
                    try {
                        Club c(pageList[i]);
                        if (c.Id != 0) {
                            items.InsertLast(c);
                            trace("Found Club (p" + page + "): " + c.Name + " (ID: " + c.Id + ")");
                        }
                    } catch {
                        warn("Failed to parse club on page " + page + " idx " + i);
                    }
                }
            }
        } catch {
            warn("RefreshClubs exception: " + getExceptionInfo());
        }

        MyClubs = items;
        print("Loaded " + MyClubs.Length + " manageable clubs.");
        refreshingClubs = false;
    }

    void RefreshActivities() {
        if (SelectedClub is null) return;
        uint clubId = SelectedClub.Id;
        string role = SelectedClub.Role.ToUpper();
        bool isManager = (role == "ADMIN" || role == "CREATOR" || role == "CONTENT_CREATOR" || role == "CONTENT CREATOR");

        if (refreshingActivities) return;
        refreshingActivities = true;
        lastActivityRefresh = Time::Now;
        
        trace("Refreshing activities for club " + clubId + " (Role: " + role + ")");
        Activity[] items;
        
        // Fetch active activities (everyone can see these)
        FetchActivitiesForStatus(clubId, true, items);
        
        // Fetch inactive activities (only if admin/managed)
        if (isManager) {
            FetchActivitiesForStatus(clubId, false, items);
        } else {
            trace("Skipping inactive activities for club " + clubId + " due to role: " + role);
        }

        // Only update if we're still looking at the same club
        if (SelectedClub !is null && SelectedClub.Id == clubId) {
            ClubActivities = items;
            print("Loaded " + ClubActivities.Length + " activities for club " + clubId);
        }
        refreshingActivities = false;
    }

    void FetchActivitiesForStatus(uint clubId, bool active, Activity[]@ items) {
        uint length = 100;
        
        try {
            auto resp = API::GetClubActivities(clubId, active, length, 0);
            trace("GetClubActivities(" + clubId + ", active=" + active + ") response: " + (resp is null ? "null" : Json::Write(resp)));
            if (resp is null || !resp.HasKey("activityList")) return;

            auto list = resp["activityList"];
            uint maxPage = resp.HasKey("maxPage") ? uint(resp["maxPage"]) : 1;

            AddActivitiesToList(list, items, clubId);
            trace("Loaded " + items.Length + " activities so far for club " + clubId + " (Status: " + (active ? "Active" : "Inactive") + ")");

            for (uint page = 2; page <= maxPage; page++) {
                auto pageResp = API::GetClubActivities(clubId, active, length, (page - 1) * length);
                if (pageResp is null || !pageResp.HasKey("activityList")) break;
                AddActivitiesToList(pageResp["activityList"], items, clubId);
                trace("Loaded " + items.Length + " activities so far for club " + clubId + " (Page " + page + ")");
            }
        } catch {
            warn("FetchActivitiesForStatus exception: " + getExceptionInfo());
        }
    }

    void AddActivitiesToList(Json::Value@ list, Activity[]@ items, uint clubId) {
        if (list.GetType() != Json::Type::Array) return;
        for (uint i = 0; i < list.Length; i++) {
            try {
                Activity a(list[i]);
                if (a.Id != 0) {
                    bool duplicate = false;
                    for (uint j = 0; j < items.Length; j++) {
                        if (items[j].Id == a.Id) {
                            duplicate = true;
                            break;
                        }
                    }
                    if (!duplicate) items.InsertLast(a);
                }
            } catch {
                warn("Failed to parse activity " + i + " for club " + clubId);
            }
        }
    }

    void DoCreateFolder() {
        if (SelectedClub is null) return;
        auto json = API::CreateClubActivity(SelectedClub.Id, nextActivityName, "folder");
        if (json !is null) {
            if (createAsActive && json.HasKey("activityId")) {
                uint actId = uint(json["activityId"]);
                API::SetActivityStatus(SelectedClub.Id, actId, true);
            }
            trace("DoCreateFolder success: " + Json::Write(json));
            Notify("Folder created: " + nextActivityName);
            startnew(RefreshActivities);
        } else {
            Notify("Failed to create folder.");
        }
    }

    void DoCreateCampaign() {
        if (SelectedClub is null) return;
        auto json = API::CreateClubActivity(SelectedClub.Id, nextActivityName, "campaign");
        if (json !is null) {
            if (createAsActive && json.HasKey("activityId")) {
                uint actId = uint(json["activityId"]);
                API::SetActivityStatus(SelectedClub.Id, actId, true);
            }
            Notify("Campaign created: " + nextActivityName);
            startnew(RefreshActivities);
        } else {
            Notify("Failed to create campaign.");
        }
    }

    void DoCreateRoom() {
        if (SelectedClub is null) return;
        auto json = API::CreateClubActivity(SelectedClub.Id, nextActivityName, "room");
        if (json !is null && json.HasKey("activityId")) {
            uint actId = uint(json["activityId"]);
            
            // Note: API::CreateClubActivity now handles required room defaults (script, region, etc.)
            if (!createAsActive) {
                API::SetActivityStatus(SelectedClub.Id, actId, false);
            }
            
            Notify("Room created: " + nextActivityName);
            startnew(RefreshActivities);
        } else {
            Notify("Failed to create room.");
        }
    }

    void DoAuditSubscription(ref@ data) {
        Activity@ a = cast<Activity>(data);
        if (a is null) return;
        
        auto sub = Subscriptions::GetByActivity(a.Id);
        if (sub is null) return;
        
        a.IsAuditing = true;
        a.AuditDone = false;
        a.AuditAdded.RemoveRange(0, a.AuditAdded.Length);
        a.AuditRemoved.RemoveRange(0, a.AuditRemoved.Length);
        
        trace("Auditing subscription for " + a.Name + " (Limit: " + sub.MapLimit + ")");
        trace("  Filters: From=" + sub.Filters.UploadedFrom + ", To=" + sub.Filters.UploadedTo + ", PrimaryTagOnly=" + sub.Filters.PrimaryTagOnly);
        
        // Force always reloading maps for a fresh audit
        a.MapsLoaded = false;
        if (!a.LoadingMaps) {
            a.LoadingMaps = true; // Set here to prevent race condition before coroutine starts
            startnew(LoadActivityMaps, a);
        }
        while (a.LoadingMaps) yield();
        
        uint fetchLimit = sub.Filters.PrimaryTagOnly ? 100 : sub.MapLimit;
        bool applyOffset = uint(sub.Filters.PageStartingTrackIds.Length) < uint(sub.Filters.CurrentPage);
        auto tmxMaps = FetchMapsSequential(sub.Filters, sub.MapLimit, applyOffset);
        if (tmxMaps.Length > 0) {
            
            string[] tmxUids;
            for (uint i = 0; i < tmxMaps.Length; i++) {
                tmxUids.InsertLast(tmxMaps[i].Uid);
            }
            
            // Check for new maps to add
            for (uint i = 0; i < tmxMaps.Length; i++) {
                bool found = false;
                for (uint j = 0; j < a.Maps.Length; j++) {
                    if (a.Maps[j].Uid == tmxMaps[i].Uid) {
                        found = true;
                        break;
                    }
                }
                if (!found) a.AuditAdded.InsertLast(tmxMaps[i]);
            }
            
            // Check for maps to remove (strict curation: if they dropped out of top X)
            for (uint i = 0; i < a.Maps.Length; i++) {
                if (tmxUids.Find(a.Maps[i].Uid) < 0) {
                    a.AuditRemoved.InsertLast(a.Maps[i]);
                }
            }
            
            // Check for order mismatch
            a.AuditOrderMismatch = false;
            trace("DEBUG: Checking order for " + a.Name + ". TMX: " + tmxUids.Length + ", ACT: " + a.Maps.Length);
            for (uint i = 0; i < tmxUids.Length; i++) {
                string tmxUid = tmxUids[i].Trim();
                string actUid = (i < a.Maps.Length) ? a.Maps[i].Uid.Trim() : "NONE";
                
                // Tracing every map for debugging with quotes to see hidden spaces
                trace("  [" + i + "] TMX: '" + tmxUid + "' | ACT: '" + actUid + "'");
                
                if (i >= a.Maps.Length || actUid != tmxUid) {
                    a.AuditOrderMismatch = true;
                    trace("  >>> MISMATCH DETECTED at index " + i + " ('" + tmxUid + "' vs '" + actUid + "')");
                    if (uint(tmxUid.Length) == uint(actUid.Length)) {
                        for (uint k = 0; k < uint(tmxUid.Length); k++) {
                            if (tmxUid[k] != actUid[k]) {
                                trace("      Char mismatch at index " + k + ": TMX='" + tmxUid[k] + "' (" + uint(tmxUid[k]) + ") vs ACT='" + actUid[k] + "' (" + uint(actUid[k]) + ")");
                            }
                        }
                    } else {
                        trace("      Length mismatch: TMX=" + tmxUid.Length + ", ACT=" + actUid.Length);
                    }
                    break;
                }
            }
            if (!a.AuditOrderMismatch && a.Maps.Length > tmxUids.Length) {
                a.AuditOrderMismatch = true; // Activity has extra maps at the end
            }
            
            a.AuditDone = true;
            sub.LastRun = Time::Now;
            Subscriptions::Save();
            trace("Audit done for " + a.Name + ": " + a.AuditAdded.Length + " to add, " + a.AuditRemoved.Length + " to remove, Mismatch: " + a.AuditOrderMismatch);
        } else {
            Notify("Audit failed: TMX search error.");
        }
        
        a.IsAuditing = false;
    }

    void DoApplyAudit(ref@ data) {
        Activity@ a = cast<Activity>(data);
        if (a is null) return;
        
        if (SelectedClub is null) {
            Notify("Audit failed: No club selected.");
            return;
        }

        auto sub = Subscriptions::GetByActivity(a.Id);
        if (sub is null) return;

        trace("Applying audit for: " + a.Name);
        trace("  Filters: From=" + sub.Filters.UploadedFrom + ", To=" + sub.Filters.UploadedTo);

        // Perform audit again to get the latest TMX UIDs in the right scope
        uint fetchLimit = sub.Filters.PrimaryTagOnly ? 100 : sub.MapLimit;
        bool applyOffset = uint(sub.Filters.PageStartingTrackIds.Length) < uint(sub.Filters.CurrentPage);
        auto tmxMaps = FetchMapsSequential(sub.Filters, sub.MapLimit, applyOffset);
        
        if (tmxMaps.Length == 0) {
            Notify("Failed to apply audit: TMX search returned no maps.");
            return;
        }

        string[] newUids;
        for (uint i = 0; i < tmxMaps.Length; i++) {
            newUids.InsertLast(tmxMaps[i].Uid);
        }
        
        // Update Activity
        Json::Value@ res;
        if (a.Type == "campaign") {
            trace("Updating campaign: " + a.CampaignId);
            @res = API::SetCampaignMaps(SelectedClub.Id, a.CampaignId, a.Name, newUids);
            // Also update the parent Activity to refresh map count visibility
            if (res !is null) {
                API::SetActivityDetails(SelectedClub.Id, a.Id, a.Name, true, newUids.Length);
            }
        } else if (a.Type == "room") {
            trace("Updating room: " + a.Id);
            @res = API::SetRoomMaps(SelectedClub.Id, a.Id, newUids);
        }
        
        if (res !is null) {
            Notify("Audit applied successfully! " + newUids.Length + " maps synchronized.");
            a.AuditDone = false;
            a.AuditOrderMismatch = false;
            // Short delay to let Nadeo API update its internal cache before we reload
            yield(2000); 
            startnew(LoadActivityMaps, a);
        } else {
            Notify("Failed to apply audit. (Check permission or map sizes)");
        }
    }

    void Notify(const string &in msg) {
        UI::ShowNotification(Meta::ExecutingPlugin().Name, msg);
    }

    void NotifyInfo(const string &in msg) {
        UI::ShowNotification(Meta::ExecutingPlugin().Name, msg, vec4(.2, .5, .9, .3));
    }

    string FormatTime(uint ms) {
        uint s = ms / 1000;
        uint m = s / 60;
        s %= 60;
        return m + ":" + (s < 10 ? "0" : "") + s;
    }



    void DoSaveRoomSettings(ref@ data) {
        Activity@ a = cast<Activity>(data);
        if (a is null || SelectedClub is null) return;

        Json::Value@ room = Json::Object();
        room["name"] = a.Name;
        room["script"] = a.Script;
        room["maxPlayers"] = a.MaxPlayers;
        room["password"] = a.Password;

        auto res = API::SetRoomDetails(SelectedClub.Id, a.RoomId, room);
        if (res !is null) {
            Notify("Room settings saved!");
            a.IsManagingSettings = false;
        } else {
            Notify("Failed to save room settings.");
        }
    }

}

 
 
