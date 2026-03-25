// Tabs/Tab.as - Base class for UI tabs

class Tab {
    string tabName;
    string icon;
    bool tabOpen = true;

    Tab(const string &in name, const string &in icon = "") {
        this.tabName = name;
        this.icon = icon;
    }

    int get_TabFlags() {
        return UI::TabItemFlags::NoCloseWithMiddleMouseButton | UI::TabItemFlags::NoReorder;
    }

    void DrawTab() {
        if (!tabOpen) return;
        string label = (icon != "" ? icon + " " : "") + tabName;
        if (UI::BeginTabItem(label, TabFlags)) {
            UI::BeginChild("tab_child_" + tabName);
            DrawInner();
            UI::EndChild();
            
            UI::EndTabItem();
        }
    }

    void DrawInner() {
        UI::Text("Empty Tab: " + tabName);
    }
}
