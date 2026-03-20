// Club Manager - Main.as
// Author: Arrold

// No #include needed for modern Openplanet plugins - all .as files in the folder are auto-loaded.

bool UserHasPermissions = false;
[Setting name="Show Window" category="General"]
bool windowVisible = false;

void Main() {
    if (!CheckPermissions()) return;
    UserHasPermissions = true;
    AddAudiences();
    Subscriptions::Load();
    trace("Club Manager Loaded");
}

bool notifiedPermissionsMissing = false;
bool CheckPermissions() {
    if (!OpenplanetHasFullPermissions()) {
        if (!notifiedPermissionsMissing)
            NotifyError("Missing permissions: This plugin will do nothing. You need club access.");
        notifiedPermissionsMissing = true;
        return false;
    }
    return true;
}

void AddAudiences() {
    NadeoServices::AddAudience("NadeoLiveServices");
    NadeoServices::AddAudience("NadeoServices");
    while (!NadeoServices::IsAuthenticated("NadeoLiveServices") || !NadeoServices::IsAuthenticated("NadeoServices")) yield();
}

void RenderInterface() {
    if (!windowVisible) return;
    
    UI::SetNextWindowSize(600, 400, UI::Cond::FirstUseEver);
    if (UI::Begin("Club Manager", windowVisible, UI::WindowFlags::MenuBar)) {
        if (!UserHasPermissions) {
            UI::Text("\\$f00Missing Openplanet Permissions (Club Access required)");
        } else {
            if (UI::BeginMenuBar()) {
                if (UI::BeginMenu("Settings")) {
                    if (UI::MenuItem("Hide Window")) windowVisible = false;
                    UI::EndMenu();
                }
                UI::EndMenuBar();
            }
            UI::RenderDashboard();
        }
    }
    UI::End();
}

/** Render function called when the menu is opened. */
void RenderMenu() {
    if (UI::MenuItem("Club Manager", "", windowVisible)) {
        windowVisible = !windowVisible;
        trace("Club Manager window toggled: " + windowVisible);
    }
}

void NotifyError(const string &in msg) {
    warn(msg);
    UI::ShowNotification(Meta::ExecutingPlugin().Name + ": Error", msg, vec4(.9, .3, .1, .3), 15000);
}
