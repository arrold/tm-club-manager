// API/NadeoRegistration.as - Nadeo map registration & upload

namespace Nadeo {
    bool IsMapUploaded(const string &in uid) {
        auto app = cast<CGameManiaPlanet>(GetApp());
        auto cma = app.MenuManager.MenuCustom_CurrentManiaApp;
        auto dfm = cma.DataFileMgr;
        auto userId = cma.UserMgr.Users[0].Id;
        
        auto task = dfm.Map_NadeoServices_GetFromUid(userId, uid);
        while (task.IsProcessing) yield();
        
        if (task.HasSucceeded) {
            return task.Map !is null;
        }
        
        if (task.ErrorDescription.Contains("Unknown map")) return false;
        
        warn("GetFromUid failed: " + task.ErrorDescription);
        return false;
    }

    bool RegisterMap(const string &in uid) {
        auto app = cast<CGameManiaPlanet>(GetApp());
        auto cma = app.MenuManager.MenuCustom_CurrentManiaApp;
        auto dfm = cma.DataFileMgr;
        auto userId = cma.UserMgr.Users[0].Id;

        // trace("Registering map " + uid + " with Nadeo...");
        auto task = dfm.Map_NadeoServices_Register(userId, uid);
        while (task.IsProcessing) yield();

        if (task.HasSucceeded) {
            // print("Map registered successfully: " + uid);
            return true;
        }

        warn("Registration failed: " + task.ErrorDescription);
        return false;
    }
}
