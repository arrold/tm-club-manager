// Tabs/CurationTab.as - TMX search and subscription curation

class CurationTab : Tab {
    CurationTab() {
        super("TMX Search", Icons::Search);
    }

    void DrawInner() override {
        RenderFilters();
        UI::Separator();
        RenderResults();
    }

    // Helper for nice-looking toggle buttons
    bool DrawToggle(const string &in label, bool active, const vec4 &in activeColor = vec4(0.18f, 0.42f, 0.72f, 0.8f)) {
        if (active) {
            UI::PushStyleColor(UI::Col::Button, activeColor);
            UI::PushStyleColor(UI::Col::ButtonHovered, activeColor * 1.2f);
        } else {
            UI::PushStyleColor(UI::Col::Button, vec4(0.2f, 0.2f, 0.2f, 0.4f));
        }
        
        bool clicked = UI::Button(label);
        
        UI::PopStyleColor(active ? 2 : 1);
        return clicked;
    }



    void RenderFilters() {
        TmxSearchFilters@ f = State::tmxFilters;

        // --- Section 1: Baseline Search Parameters ---
        UI::PushItemWidth(150);
        f.MapName = UI::InputText("Map Name", f.MapName);
        UI::SameLine();
        
        string authorBuffer = string::Join(f.AuthorNames, ", ");
        string newAuthorBuffer = UI::InputText("Author(s)", authorBuffer);
        if (UI::IsItemHovered()) UI::SetTooltip("Use comma-separated names for multi-author search\nExample: hf.Zertrov, simon.tm");
        
        if (newAuthorBuffer != authorBuffer) {
            f.AuthorNames.RemoveRange(0, f.AuthorNames.Length);
            string[] split = newAuthorBuffer.Split(",");
            for (uint i = 0; i < split.Length; i++) {
                string s = split[i].Trim();
                if (s != "") f.AuthorNames.InsertLast(s);
            }
        }

        UI::SameLine();
        UI::PushItemWidth(100);
        f.ResultLimit = uint(UI::InputInt("Maps per Page", int(f.ResultLimit)));
        if (f.ResultLimit < 1) f.ResultLimit = 1;
        if (f.ResultLimit > 100) f.ResultLimit = 100;
        UI::PopItemWidth();
        UI::PopItemWidth();

        UI::Separator();

        // --- Section 2: Difficulty Selection Row ---
        UI::TextDisabled("Difficulties:");
        for (uint i = 0; i < TMX::DIFFICULTY_NAMES.Length; i++) {
            if (DrawToggle(TMX::DIFFICULTY_NAMES[i] + "###TmxDiff_" + i, f.Difficulties[i], vec4(0.2f, 0.6f, 0.2f, 0.8f))) {
                f.Difficulties[i] = !f.Difficulties[i];
            }
            if (i < TMX::DIFFICULTY_NAMES.Length - 1) UI::SameLine();
        }

        UI::Separator();

        // --- Section 3: Advanced Filtering & Sorting ---
        RenderTagsSection(); // Row A: Tags (Full Width)

        // Row B: Sorting & TOTD
        UI::PushItemWidth(150);
        int currentTotd = (f.InTOTD == 1) ? 1 : (f.InTOTD == 0 ? 2 : 0);
        int selectionDiff = DrawCombo("Track of the Day", currentTotd, {"Any", "TOTD Only", "Not TOTD"});
        if (selectionDiff == 1) f.InTOTD = 1;
        else if (selectionDiff == 2) f.InTOTD = 0;
        else f.InTOTD = -1;
        
        UI::SameLine();
        f.SortPrimary = DrawCombo("Primary Sort", f.SortPrimary, TMX::SORT_NAMES);
        UI::SameLine();
        f.SortSecondary = DrawCombo("Secondary Sort", f.SortSecondary, TMX::SORT_NAMES);
        UI::PopItemWidth();

        // Row C: Icon Toggles
        uint totalSelected = f.IncludeTags.Length;
        uint surfaceSelected = 0;
        for (uint i = 0; i < f.IncludeTags.Length; i++) {
            if (TMX::ArrayContains(TMX::SURFACE_TAGS, f.IncludeTags[i])) surfaceSelected++;
        }

        bool tagValid = totalSelected == 1;
        bool surfValid = surfaceSelected == 1;
        vec4 highlightColor = vec4(0.2f, 0.6f, 0.2f, 0.8f);

        UI::BeginDisabled(!tagValid);
        if (DrawToggle(Icons::Tag + " Primary Tag", f.PrimaryTagOnly, tagValid ? highlightColor : vec4(0.18f, 0.42f, 0.72f, 0.8f))) {
            f.PrimaryTagOnly = !f.PrimaryTagOnly;
            if (f.PrimaryTagOnly) f.PrimarySurfaceOnly = false;
        }
        UI::EndDisabled();
        if (!tagValid) {
            UI::SameLine();
            UI::TextDisabled(" (Select one tag)");
        }

        UI::SameLine();
        UI::BeginDisabled(!surfValid);
        if (DrawToggle(Icons::Leaf + " Primary Surface", f.PrimarySurfaceOnly, surfValid ? highlightColor : vec4(0.18f, 0.42f, 0.72f, 0.8f))) {
            f.PrimarySurfaceOnly = !f.PrimarySurfaceOnly;
            if (f.PrimarySurfaceOnly) f.PrimaryTagOnly = false;
        }
        UI::EndDisabled();
        if (!surfValid) {
            UI::SameLine();
            UI::TextDisabled(" (Select one surface tag)");
        }

        UI::SameLine(0, 20);
        string limitLabel = Icons::ExclamationTriangle + " Room Guardrails: ";
        vec4 limitColor = vec4(0.2f, 0.2f, 0.2f, 0.4f);
        if (f.LimitFilter == 1) { limitLabel += "Exclude Red"; limitColor = vec4(0.7f, 0.1f, 0.1f, 0.8f); }
        else if (f.LimitFilter == 2) { limitLabel += "Exclude Red+Yellow"; limitColor = vec4(0.9f, 0.9f, 0.1f, 0.8f); }
        else { limitLabel += "None"; }

        if (DrawToggle(limitLabel, f.LimitFilter > 0, limitColor)) {
            f.LimitFilter = (f.LimitFilter + 1) % 3;
        }
        if (UI::IsItemHovered()) UI::SetTooltip("Filter out maps that exceed Nadeo room limits (Display Cost / Item Size)");


        UI::Separator();

        // Row 5: Advanced Ranges (Date & Time)
        UI::BeginGroup();
        UI::TextDisabled("Uploaded Date Range (DD/MM/YYYY)");
        UI::PushItemWidth(120);
        f.UploadedFrom = UI::InputText("From##up_f", f.UploadedFrom); UI::SameLine();
        f.UploadedTo = UI::InputText("To##up_t", f.UploadedTo);
        UI::PopItemWidth();
        UI::EndGroup();

        UI::SameLine(0, 40);

        UI::BeginGroup();
        UI::TextDisabled("Author Time Range (HH:MM:SS)");
        UI::PushItemWidth(45);
        f.hFrom = UI::InputInt("##h_f", f.hFrom, 0); UI::SameLine(); UI::Text(":"); UI::SameLine();
        f.mFrom = UI::InputInt("##m_f", f.mFrom, 0); UI::SameLine(); UI::Text(":"); UI::SameLine();
        f.sFrom = UI::InputInt("##s_f", f.sFrom, 0); UI::SameLine(); UI::Text(" to "); UI::SameLine();
        f.hTo = UI::InputInt("##h_t", f.hTo, 0); UI::SameLine(); UI::Text(":"); UI::SameLine();
        f.mTo = UI::InputInt("##m_t", f.mTo, 0); UI::SameLine(); UI::Text(":"); UI::SameLine();
        f.sTo = UI::InputInt("##s_t", f.sTo, 0);
        UI::PopItemWidth();
        UI::EndGroup();

        UI::Separator();

        if (UI::Button(Icons::Search + " Search TMX")) {
            f.CurrentPage = 1;
            f.TimeFromMs = (f.hFrom * 3600000) + (f.mFrom * 60000) + (f.sFrom * 1000);
            f.TimeToMs = (f.hTo * 3600000) + (f.mTo * 60000) + (f.sTo * 1000);
            startnew(DoTmxSearch);
        }
        UI::SameLine();
        if (UI::Button(Icons::AngleLeft + " Prev")) {
            if (f.CurrentPage > 1) {
                f.CurrentPage--;
                startnew(DoTmxSearch);
            }
        }
        UI::SameLine();
        UI::Text("Page " + f.CurrentPage);
        UI::SameLine();
        if (UI::Button("Next " + Icons::AngleRight)) {
            f.CurrentPage++;
            startnew(DoTmxSearch);
        }
        UI::SameLine();
        if (UI::Button(Icons::Trash + " Clear All Filters")) {
            State::tmxFilters = TmxSearchFilters();
        }

        // Awards Most + Not TOTD fetches 100 results upfront; subsequent pages are instant from cache.
        if (f.SortPrimary == 0 && f.InTOTD == 0) {
            UI::PushStyleColor(UI::Col::Text, vec4(0.6f, 0.6f, 0.6f, 1.0f));
            UI::Text(Icons::ClockO + " 'Awards Most' + 'Not TOTD': first 100 results cached on search. Paging is instant within that set.");
            UI::PopStyleColor();
        }
    }

    void RenderTagsSection() {
        TmxSearchFilters@ f = State::tmxFilters;
        string label = "Filter by Tags (" + (f.IncludeTags.Length + f.ExcludeTags.Length) + ")  -  (Click: Include > Exclude > None)###TagsHeader";
        
        UI::PushStyleVar(UI::StyleVar::FramePadding, vec2(10, 2));
        UI::PushStyleColor(UI::Col::Header, vec4(0.2f, 0.2f, 0.2f, 0.2f));
        bool isOpen = UI::CollapsingHeader(label);
        UI::PopStyleColor();
        UI::PopStyleVar();

        if (isOpen) {
            UI::PushStyleColor(UI::Col::Header, vec4(0, 0, 0, 0));
            UI::PushStyleColor(UI::Col::HeaderHovered, vec4(0, 0, 0, 0));
            UI::PushStyleColor(UI::Col::HeaderActive, vec4(0, 0, 0, 0));
            
            UI::Columns(6, "TagGrid", false);
            for (uint i = 0; i < TMX::TAG_NAMES.Length; i++) {
                string tag = TMX::TAG_NAMES[i];
                int state = 0; // 0=None, 1=Include, 2=Exclude
                
                if (TMX::ArrayContains(f.IncludeTags, tag)) state = 1;
                else if (TMX::ArrayContains(f.ExcludeTags, tag)) state = 2;

                if (state == 1) UI::PushStyleColor(UI::Col::Text, vec4(0.2f, 0.9f, 0.2f, 1));
                else if (state == 2) UI::PushStyleColor(UI::Col::Text, vec4(0.9f, 0.2f, 0.2f, 1));
                else UI::PushStyleColor(UI::Col::Text, vec4(0.6f, 0.6f, 0.6f, 1));
                
                if (UI::Selectable(tag, false, UI::SelectableFlags::None)) {
                    if (state == 0) {
                        f.IncludeTags.InsertLast(tag);
                    } else if (state == 1) {
                        TMX::ArrayRemove(f.IncludeTags, tag);
                        f.ExcludeTags.InsertLast(tag);
                    } else {
                        TMX::ArrayRemove(f.ExcludeTags, tag);
                    }
                }
                
                UI::PopStyleColor();
                UI::NextColumn();
            }
            UI::Columns(1);
            UI::PopStyleColor(3);
        }
    }

    int DrawCombo(const string &in label, int current, const string[]@ options) {
        string currentName = (current >= 0 && current < int(options.Length)) ? options[current] : "Any";
        int result = current;
        if (UI::BeginCombo(label, currentName)) {
            for (uint i = 0; i < options.Length; i++) {
                if (UI::Selectable(options[i], int(i) == current)) {
                    result = int(i);
                }
            }
            UI::EndCombo();
        }
        return result;
    }

    void RenderResults() {
        if (State::searchInProgress) {
            UI::Text(Icons::Refresh + " Searching...");
            return;
        }
        if (State::tmxSearchResults.Length == 0) {
            UI::Text("No results. Enter search criteria above.");
            return;
        }

        // --- Target Selection for Batch Add ---
        string limitStr = (State::TargetActivity !is null) ? (State::TargetActivity.Type == "campaign" ? " (Max 25)" : " (Max 100)") : "";
        UI::TextDisabled("Target Activity" + limitStr + ":"); UI::SameLine();
        string targetName = (State::TargetActivity !is null) ? State::TargetActivity.Name : "None Selected";
        UI::PushItemWidth(300);
        if (UI::BeginCombo("##batch_target", targetName)) {
            if (State::SelectedClub !is null) {
                for (uint i = 0; i < State::ClubActivities.Length; i++) {
                    Activity@ a = State::ClubActivities[i];
                    if (a.Type != "campaign" && a.Type != "room") continue;
                    if (a.Type == "room" && a.MirrorCampaignId > 0) continue; // Cannot manually add to mirrored rooms
                    if (UI::Selectable(a.Name, State::TargetActivity !is null && State::TargetActivity.Id == a.Id)) {
                        @State::TargetActivity = a;
                    }
                }
            } else {
                UI::TextDisabled("Select a club first in 'Clubs' tab.");
            }
            UI::EndCombo();
        }
        UI::PopItemWidth();

        UI::Text(State::tmxSearchResults.Length + " maps found.");
        UI::SameLine();
        if (UI::Button(Icons::Plus + " All")) {
            for (uint i = 0; i < State::tmxSelected.Length; i++) State::tmxSelected[i] = true;
        }
        UI::SameLine();
        if (UI::Button(Icons::Minus + " None")) {
            for (uint i = 0; i < State::tmxSelected.Length; i++) State::tmxSelected[i] = false;
        }
        UI::SameLine();
        if (UI::Button(Icons::Check + " Add Selected to Activity")) {
            if (State::TargetActivity is null) {
                UI::ShowNotification("Club Manager", "Please select a Target Activity from the dropdown first!");
            } else {
                startnew(DoBatchAdd);
            }
        }

        UI::SameLine();
        if (UI::Button(Icons::FloppyO + " Save as Subscription")) {
            if (State::TargetActivity is null) {
                UI::ShowNotification("Club Manager", "Please select a Target Activity first!");
            } else {
                TmxSearchFilters@ f = State::tmxFilters;
                // Recalculate time values from UI inputs before saving
                f.TimeFromMs = (f.hFrom * 3600000) + (f.mFrom * 60000) + (f.sFrom * 1000);
                f.TimeToMs = (f.hTo * 3600000) + (f.mTo * 60000) + (f.sTo * 1000);
                Subscription@ sub = Subscription();
                sub.ClubId = State::SelectedClub.Id;
                sub.ActivityId = State::TargetActivity.Id;
                sub.ActivityName = State::TargetActivity.Name;
                @sub.Filters = f.Clone();
                Subscriptions::Add(sub);

                UI::ShowNotification("Club Manager", "Subscription saved for " + State::TargetActivity.Name);
            }
        }

        if (UI::BeginTable("SearchResultTable", 11, UI::TableFlags::Resizable | UI::TableFlags::RowBg)) {
            UI::TableSetupColumn("Select", UI::TableColumnFlags::WidthFixed, 40);
            UI::TableSetupColumn("ID", UI::TableColumnFlags::WidthFixed, 60);
            UI::TableSetupColumn("Name", UI::TableColumnFlags::WidthStretch);
            UI::TableSetupColumn("Uploader", UI::TableColumnFlags::WidthStretch);
            UI::TableSetupColumn("Authors", UI::TableColumnFlags::WidthFixed, 30);
            UI::TableSetupColumn("Awards", UI::TableColumnFlags::WidthFixed, 60);
            UI::TableSetupColumn("Warn", UI::TableColumnFlags::WidthFixed, 40);
            UI::TableSetupColumn("Length", UI::TableColumnFlags::WidthFixed, 80);
            UI::TableSetupColumn("Difficulty", UI::TableColumnFlags::WidthFixed, 100);
            UI::TableSetupColumn("Tags", UI::TableColumnFlags::WidthStretch);
            UI::TableSetupColumn("Actions", UI::TableColumnFlags::WidthFixed, 80);
            UI::TableHeadersRow();

            for (uint i = 0; i < State::tmxSearchResults.Length; i++) {
                TmxMap@ m = State::tmxSearchResults[i];
                UI::TableNextRow();
                UI::TableNextColumn();
                State::tmxSelected[i] = UI::Checkbox("##sel" + i, State::tmxSelected[i]);
                UI::TableNextColumn();
                UI::Text(tostring(m.TrackId));
                UI::TableNextColumn();
                UI::Text(m.Name);
                MetadataOverrides::RenderOverrideMenu(m);
                UI::TableNextColumn();
                UI::Text(m.Author);
                UI::TableNextColumn();
                UI::Text(Icons::Users);
                if (UI::IsItemHovered()) {
                    UI::BeginTooltip();
                    UI::Text("Collaborators:");
                    for (uint j = 0; j < m.Authors.Length; j++) {
                        UI::Text("- " + m.Authors[j]);
                    }
                    UI::EndTooltip();
                }
                UI::TableNextColumn();
                UI::Text(tostring(m.AwardCount));
                UI::TableNextColumn();
                if (m.SizeWarning != "") {
                    UI::Text(m.SizeWarning);
                    if (UI::IsItemHovered()) {
                        UI::BeginTooltip();
                        UI::Text("Display Cost: " + m.DisplayCost);
                        UI::Text("Embedded Items: " + (m.EmbeddedItemsSize / 1024) + " KB");
                        if (m.ServerSizeExceeded) UI::Text("\\$f00Server Size Limit Exceeded!");
                        UI::EndTooltip();
                    }
                }
                UI::TableNextColumn();
                UI::Text(Time::Format(m.LengthSecs * 1000));
                UI::TableNextColumn();
                UI::Text(m.DifficultyName);
                UI::TableNextColumn();
                UI::Text(string::Join(m.Tags, ", "));
                UI::TableNextColumn();
                if (UI::Button(Icons::ExternalLink + "##tmx" + i)) {
                    OpenBrowserURL("https://trackmania.exchange/maps/" + m.TrackId);
                }
                UI::SameLine();
                if (UI::Button(Icons::Plus + "##addlist" + i)) {
                    UI::OpenPopup("AddToListPopup" + i);
                }
                if (UI::BeginPopup("AddToListPopup" + i)) {
                    UI::TextDisabled("Add to Local List:");
                    for (uint j = 0; j < State::CustomListNames.Length; j++) {
                        if (UI::MenuItem(State::CustomListNames[j])) {
                            CustomLists::Add(State::CustomListNames[j], m);
                        }
                    }
                    if (State::CustomListNames.Length == 0) {
                        UI::TextDisabled("(No lists found)");
                    }
                    UI::EndPopup();
                }
            }
            UI::EndTable();
        }
    }
}
