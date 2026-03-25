# Trackmania Club Manager Plugin

A powerful Openplanet plugin for Trackmania (2020) designed to streamline the management of Club Campaigns, Rooms, and Activity folders.

## **Core Features**

### **1. Campaign & Activity Management**
*   **Playlist Synchronization**: Easily update campaign playlists with map UIDs.
*   **Automated Visibility**: Automatically syncs the `itemsCount` on the parent Club Activity so that all maps in your playlist are immediately visible to players.
*   **Organizational Folders**: Create and manage folders to group your campaigns and rooms within the club.
*   **Rename & Reorder**: Real-time renaming and reordering of maps and activities.

### **2. Club Room Synchronization**
*   **Mirroring Logic**: Link a Room to a Campaign, ensuring that any map changes in the campaign are automatically reflected in the live server room.
*   **Live Sync Control**: Dedicated tools to deactivate/reactivate rooms to force server-side playlist refreshes.
*   **Configuration**: Manage room settings like privacy, max players, and scripts.

### **3. Dynamic Curation (Subscriptions)**
*   **Pin TMX Searches**: Associate a specific TMX search filter (e.g., "Top 25 Dirt TOTD") with any club activity.
*   **Automated Audits**: Run a "Curation Audit" to see exactly which maps have entered/dropped from your criteria versus what is currently in-game.
*   **Batch Application**: Apply audit results in one click to sync your club content with the latest community rankings.

### **4. Integrated TMX Search**
*   **Advanced Filtering**: Filter maps by awards, vehicle type (Snow, Rally, etc.), primary tags, difficulty, and more.
*   **Pagination Support**: Browse results page-by-page directly within the plugin.
*   **Visibility Validation**: Highlights maps that might be too large for server embedding or have excessive display costs.

## **Installation**

1.  Clone this repository or download the source.
2.  Create a symbolic link (or copy) to your Openplanet Plugins folder:
    *   `C:\Users\<User>\OpenplanetNext\Plugins\ClubManager` -> `path/to/tm-club-manager`
3.  Ensure the `info.toml` is in the root of the plugin directory.

## **Requirements**
*   **Openplanet for Trackmania** with **Club Access** permissions.
*   **NadeoServices** and **NadeoLiveServices** audiences authenticated.

## **Architecture**
*   **src/Main.as**: Entry point and permission handling.
*   **src/MainUI.as**: Root UI rendering and tab management.
*   **src/API/**: Modularized API wrappers for Nadeo Live Services, TMX, and Map Helpers.
*   **src/Logic/**: Core business logic for audits, map synchronization, and activity management.
*   **src/Tabs/**: Component-based UI for Clubs, Search, and local map views.
*   **src/Models.as**: Shared data structures for Clubs, Activities, and Maps.
*   **src/State.as**: Centralized state management for the plugin.

## **License**
This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.

---
*Created by Arrold*
