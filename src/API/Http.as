// API/Http.as - Low-level network helpers (Zertrov Style)

namespace API {
    /* Nadeo Service Task Helpers */
    
    CWebServicesTaskResult@[] tasksToClear;

    void WaitAndClearTaskLater(CWebServicesTaskResult@ task, CMwNod@ owner) {
        if (task is null) return;
        while (task.IsProcessing) yield();
        tasksToClear.InsertLast(task);
    }

    void ClearTasks() {
        auto app = cast<CGameManiaPlanet>(GetApp());
        if (app.MenuManager is null || app.MenuManager.MenuCustom_CurrentManiaApp is null) return;
        auto userMgr = app.MenuManager.MenuCustom_CurrentManiaApp.UserMgr;
        for (uint i = 0; i < tasksToClear.Length; i++) {
            userMgr.TaskResult_Release(tasksToClear[i].Id);
        }
        tasksToClear.RemoveRange(0, tasksToClear.Length);
    }
}
