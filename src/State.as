// State.as - Global state container to prevent circular dependencies
// Following the State Container Pattern

namespace State {
    // Selection State
    Club@ SelectedClub;
    Activity[] ClubActivities;
    Club[] MyClubs;
    Activity@ PersonalTracksProxy;

    // Refresh State
    bool refreshingClubs = false;
    bool refreshingActivities = false;
    uint lastClubRefresh = 0;
    uint lastActivityRefresh = 0;
    const uint REFRESH_COOLDOWN = 10000; // 10 seconds
    bool isInitialised = false; // Tracks eager loading for the current club session

    // Branding State (Current values for the selected club)
    string clubTag, clubDescription;
    bool clubPublic;

    // TMX / Curation State
    TmxSearchFilters tmxFilters;
    TmxMap[] tmxSearchResults;
    bool[] tmxSelected;
    Activity@ TargetActivity;
    bool searchInProgress = false;
    bool bulkAuditInProgress = false;
    bool bulkAuditComplete = false; // Flag to show "Apply All"
    uint bulkAuditUpdatesAvailable = 0; // Number of activities with changes
    string bulkAuditStatus = "";
    float bulkAuditProgress = 0.0f;


    // Local Maps State
    LocalMap@[] LocalMaps;
    bool refreshingLocalMaps = false;
    uint localMapsCount = 0;

    // Modal Buffers (Avoid passing strings/arrays via ref@ in startnew)
    string nextActivityName = "New Folder";
    bool nextActivityActive = true;
    uint[] reorderIds;
    uint64 lastActionTime = 0;
    uint nextRoomMirrorCampaignId = 0;
}
