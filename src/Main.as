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
    CustomLists::Load();
    MetadataOverrides::Load();
    AuditCache::Init();
    Testing::Init();
    startnew(MetadataOverrides::SyncAllNames);
    
    // Initialize UI Tabs
    CM_UI::tabs.InsertLast(ClubsTab());
    CM_UI::tabs.InsertLast(CurationTab());
    CM_UI::tabs.InsertLast(TMXListsTab());
    CM_UI::tabs.InsertLast(GlobalOverridesTab());
    CM_UI::tabs.InsertLast(LocalMapsTab());
    
    // trace("Club Manager Loaded (Modular Architecture)");
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

void Notify(const string &in msg) {
    UI::ShowNotification(Meta::ExecutingPlugin().Name, msg);
}

void NotifyError(const string &in msg) {
    warn(msg);
    UI::ShowNotification(Meta::ExecutingPlugin().Name + ": Error", msg, vec4(.9, .3, .1, .3), 15000);
}

void RenderInterface() {
    CM_UI::Render();
}

/** Render function called when the menu is opened. */
void RenderMenu() {
    if (UI::MenuItem("Club Manager", "", windowVisible)) {
        windowVisible = !windowVisible;
    }
}
