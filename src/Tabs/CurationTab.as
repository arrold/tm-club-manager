// Tabs/CurationTab.as - TMX Search & Curation (Zertrov Style)

class CurationTab : Tab {
    CurationTab() {
        super("TMX Curation", "\\$z\\$f93" + Icons::Search + "\\$z");
    }

    void DrawInner() override {
        RenderFilters();
        UI::Separator();
        RenderResults();
    }

    void RenderFilters() {
        auto f = State::tmxFilters;

        // --- Row 1: Author, Vehicle, Limit ---
        UI::Columns(3, "tmx_core_filters", false);
        UI::TextDisabled("Author");
        f.AuthorName = UI::InputText("##author", f.AuthorName);
        UI::NextColumn();
        
        UI::TextDisabled("Vehicle");
        int vehIdx = f.Vehicle;
        string currentVeh = (vehIdx >= 0 && vehIdx < int(TMX::VEHICLE_NAMES.Length)) ? TMX::VEHICLE_NAMES[vehIdx] : "Any";
        UI::PushItemWidth(-1);
        if (bool(UI::BeginCombo("##vehicle", currentVeh))) {
            if (UI::Selectable("Any", vehIdx == -1)) f.Vehicle = -1;
            for (uint i = 0; i < TMX::VEHICLE_NAMES.Length; i++) {
                if (UI::Selectable(TMX::VEHICLE_NAMES[i], vehIdx == int(i))) f.Vehicle = i;
            }
            UI::EndCombo();
        }
        UI::PopItemWidth();
        UI::NextColumn();

        UI::TextDisabled("Limit");
        f.ResultLimit = UI::InputInt("##limit", f.ResultLimit);
        if (f.ResultLimit < 1) f.ResultLimit = 1;
        if (f.ResultLimit > 100) f.ResultLimit = 100;
        UI::Columns(1);

        // --- Row 2: Sorts ---
        UI::Columns(2, "tmx_sort_filters", false);
        UI::TextDisabled("Primary Sort");
        int sortPri = f.SortPrimary;
        string currentSortPri = (sortPri >= 0 && sortPri < int(TMX::SORT_NAMES.Length)) ? TMX::SORT_NAMES[sortPri] : "Newest";
        UI::PushItemWidth(-1);
        if (bool(UI::BeginCombo("##sort1", currentSortPri))) {
            for (uint i = 0; i < TMX::SORT_NAMES.Length; i++) {
                if (UI::Selectable(TMX::SORT_NAMES[i], sortPri == int(i))) f.SortPrimary = i;
            }
            UI::EndCombo();
        }
        UI::PopItemWidth();
        UI::NextColumn();

        UI::TextDisabled("Secondary Sort");
        int sortSec = f.SortSecondary;
        string currentSortSec = (sortSec >= 0 && sortSec < int(TMX::SORT_NAMES.Length)) ? TMX::SORT_NAMES[sortSec] : "None";
        UI::PushItemWidth(-1);
        if (bool(UI::BeginCombo("##sort2", currentSortSec))) {
            if (UI::Selectable("None", sortSec == -1)) f.SortSecondary = -1;
            for (uint i = 0; i < TMX::SORT_NAMES.Length; i++) {
                if (UI::Selectable(TMX::SORT_NAMES[i], sortSec == int(i))) f.SortSecondary = i;
            }
            UI::EndCombo();
        }
        UI::PopItemWidth();
        UI::Columns(1);

        UI::Separator();

        // --- Difficulty ---
        UI::TextDisabled("Difficulty");
        for (uint i = 0; i < TMX::DIFFICULTY_NAMES.Length; i++) {
            if (i > 0) UI::SameLine();
            bool selected = f.Difficulties[i];
            if (selected) UI::PushStyleColor(UI::Col::Button, vec4(0, 0.4, 0.7, 0.8));
            if (UI::Button(TMX::DIFFICULTY_NAMES[i])) {
                f.Difficulties[i] = !selected;
            }
            if (selected) UI::PopStyleColor();
        }

        UI::Separator();

        // --- Row 3: Tags (Cloud format) ---
        if (UI::TreeNode("Tags Selection (Click once to Include, twice to Exclude)")) {
            UI::Columns(5, "tmx_tags_cloud", false);
            for (uint i = 0; i < TMX::TAG_NAMES.Length; i++) {
                string t = TMX::TAG_NAMES[i];
                bool inc = f.IncludeTags.Find(t) != -1;
                bool exc = f.ExcludeTags.Find(t) != -1;
                
                if (exc) UI::PushStyleColor(UI::Col::Text, vec4(1, 0.3, 0.3, 1));
                else if (inc) UI::PushStyleColor(UI::Col::Text, vec4(0.3, 1, 0.3, 1));

                if (UI::Selectable(t, inc || exc)) {
                    if (!inc && !exc) f.IncludeTags.InsertLast(t);
                    else if (inc) { f.IncludeTags.RemoveAt(f.IncludeTags.Find(t)); f.ExcludeTags.InsertLast(t); }
                    else f.ExcludeTags.RemoveAt(f.ExcludeTags.Find(t));
                }
                
                if (inc || exc) UI::PopStyleColor();
                UI::NextColumn();
            }
            UI::Columns(1);
            if (UI::Button("Clear All Tags")) {
                f.IncludeTags.RemoveRange(0, f.IncludeTags.Length);
                f.ExcludeTags.RemoveRange(0, f.ExcludeTags.Length);
            }
            UI::TreePop();
        }

        UI::Separator();

        // --- Row 4: Checkboxes (Manual Toggle) ---
        UI::Columns(4, "tmx_check_filters", false);
        if (UI::Button((f.InTOTD == 1 ? Icons::CheckSquare : Icons::Square) + " TOTD")) {
            f.InTOTD = (f.InTOTD == 1 ? -1 : 1);
        }
        UI::NextColumn();

        if (UI::Button((f.InOnlineRecords == 1 ? Icons::CheckSquare : Icons::Square) + " My Record")) {
            f.InOnlineRecords = (f.InOnlineRecords == 1 ? -1 : 1);
        }
        UI::NextColumn();

        if (UI::Button((f.PrimaryTagOnly ? Icons::CheckSquare : Icons::Square) + " Pri Tag Only")) {
            f.PrimaryTagOnly = !f.PrimaryTagOnly;
        }
        UI::NextColumn();

        if (UI::Button((f.PrimarySurfaceOnly ? Icons::CheckSquare : Icons::Square) + " Pri Surface Only")) {
            f.PrimarySurfaceOnly = !f.PrimarySurfaceOnly;
        }
        UI::Columns(1);

        UI::Separator();

        // --- Author Time Range ---
        UI::TextDisabled("Author Time Range (H : M : S)");
        UI::PushItemWidth(80);
        f.hFrom = Text::ParseInt(UI::InputText("##h_f", tostring(f.hFrom))); UI::SameLine();
        UI::Text(":"); UI::SameLine();
        f.mFrom = Text::ParseInt(UI::InputText("##m_f", tostring(f.mFrom))); UI::SameLine();
        UI::Text(":"); UI::SameLine();
        f.sFrom = Text::ParseInt(UI::InputText("##s_f", tostring(f.sFrom))); UI::SameLine();
        UI::Text(" to "); UI::SameLine();
        f.hTo = Text::ParseInt(UI::InputText("##h_t", tostring(f.hTo))); UI::SameLine();
        UI::Text(":"); UI::SameLine();
        f.mTo = Text::ParseInt(UI::InputText("##m_t", tostring(f.mTo))); UI::SameLine();
        UI::Text(":"); UI::SameLine();
        f.sTo = Text::ParseInt(UI::InputText("##s_t", tostring(f.sTo)));
        UI::PopItemWidth();

        UI::Separator();

        // --- Uploaded Date Range ---
        UI::TextDisabled("Uploaded Date Range (DD/MM/YYYY)");
        UI::PushItemWidth(120);
        f.UploadedFrom = UI::InputText("From##up_f", f.UploadedFrom); UI::SameLine();
        f.UploadedTo = UI::InputText("To##up_t", f.UploadedTo);
        UI::PopItemWidth();

        UI::Separator();

        if (UI::Button(Icons::Search + " Search TMX")) {
            f.PageStartingTrackIds.RemoveRange(0, f.PageStartingTrackIds.Length);
            f.PageStartingTrackIds.InsertLast(0);
            f.CurrentPage = 1;
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
        if (UI::Button(Icons::Trash + " Clear")) {
            State::tmxFilters = TmxSearchFilters();
        }
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
        UI::TextDisabled("Target Activity:"); UI::SameLine();
        string targetName = (State::TargetActivity !is null) ? State::TargetActivity.Name : "None Selected";
        UI::PushItemWidth(300);
        if (bool(UI::BeginCombo("##batch_target", targetName))) {
            if (State::SelectedClub !is null) {
                for (uint i = 0; i < State::ClubActivities.Length; i++) {
                    auto a = State::ClubActivities[i];
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
                Subscription@ sub = Subscription();
                sub.ActivityId = State::TargetActivity.Id;
                sub.ActivityName = State::TargetActivity.Name;
                @sub.Filters = TmxSearchFilters(State::tmxFilters.ToJson());
                sub.MapLimit = State::tmxFilters.ResultLimit;
                Subscriptions::Add(sub);
                UI::ShowNotification("Success", "Search saved as subscription for " + State::TargetActivity.Name);
            }
        }

        UI::BeginChild("tmx_results_scroll");
        UI::Columns(7, "tmx_results_cols");
        UI::Text("Sel"); UI::NextColumn();
        UI::Text("Name"); UI::NextColumn();
        UI::Text("Author"); UI::NextColumn();
        UI::Text("Length"); UI::NextColumn();
        UI::Text("Difficulty"); UI::NextColumn();
        UI::Text("Awards"); UI::NextColumn();
        UI::Text("Tags"); UI::NextColumn();
        UI::Separator();

        for (uint i = 0; i < State::tmxSearchResults.Length; i++) {
            auto m = State::tmxSearchResults[i];
            State::tmxSelected[i] = UI::Checkbox("##sel" + i, State::tmxSelected[i]); UI::NextColumn();
            UI::Text(m.Name); UI::NextColumn();
            UI::Text(m.Author); UI::NextColumn();
            UI::Text(Time::Format(m.LengthSecs * 1000)); UI::NextColumn();
            UI::Text(m.DifficultyName); UI::NextColumn();
            UI::Text("" + m.AwardCount); UI::NextColumn();
            UI::Text(string::Join(m.Tags, ", ")); UI::NextColumn();
        }
        UI::Columns(1);
        UI::EndChild();
    }
}
