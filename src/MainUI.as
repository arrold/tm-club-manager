// MainUI.as - UI Entry Point

namespace CM_UI {
    Tab@[] tabs;

    void Render() {
        if (!windowVisible) return;
        if (tabs.Length < 3) return;

        UI::SetNextWindowSize(700, 500, UI::Cond::FirstUseEver);
        bool open = UI::Begin("Club Manager", windowVisible, UI::WindowFlags::MenuBar);
        if (open) {
            if (UI::BeginMenuBar()) {
                if (UI::BeginMenu("Settings")) {
                    if (UI::MenuItem("Refresh Data")) {
                        startnew(RefreshClubs);
                        startnew(RefreshActivities);
                    }
                    UI::Separator();
                    if (UI::MenuItem(Icons::Flask + " Probe mapsearch2 (dev)")) {
                        startnew(Testing::Probe_Mapsearch2);
                    }
                    UI::EndMenu();
                }
                UI::EndMenuBar();
            }

            // Using void-style call for this specific OP version
            UI::BeginTabBar("MainTabBar");
            for (uint i = 0; i < tabs.Length; i++) {
                tabs[i].DrawTab();
            }
            UI::EndTabBar();
        }
        UI::End(); // MUST be called regardless of whether Begin() returns true or false
    }

    Tab@ GetTab(const string &in name) {
        for (uint i = 0; i < tabs.Length; i++) {
            if (tabs[i].tabName == name) return tabs[i];
        }
        return null;
    }
}
