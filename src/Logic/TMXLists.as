// Logic/TMXLists.as - Local List Management

namespace CustomLists {
    string GetStoragePath() {
        return IO::FromStorageFolder("custom_lists.json");
    }

    void Load() {
        string path = GetStoragePath();
        if (!IO::FileExists(path)) return;
        
        Json::Value@ json = Json::FromFile(path);
        if (json.GetType() == Json::Type::Object) {
            State::CustomListNames = json.GetKeys();
        }
    }

    void Save(const string &in listName, TmxMap@[]@ maps) {
        string path = GetStoragePath();
        Json::Value@ json = IO::FileExists(path) ? Json::FromFile(path) : Json::Object();
        
        Json::Value@ mapsArr = Json::Array();
        for (uint i = 0; i < maps.Length; i++) {
            mapsArr.Add(maps[i].ToJson()); // Store full map data for offline browsing
        }
        json[listName] = mapsArr;
        Json::ToFile(path, json);
        Load();
    }

    void Add(const string &in listName, TmxMap@ map) {
        TmxMap@[]@ maps = GetMaps(listName);
        // Prevent duplicates
        for (uint i = 0; i < maps.Length; i++) {
            if (maps[i].TrackId == map.TrackId) return;
        }
        maps.InsertLast(map);
        Save(listName, maps);
        if (State::SelectedListId == listName) {
            State::CustomListMaps = maps;
        }
        Notify("Added '" + map.Name + "' to local list '" + listName + "'");
    }

    void Remove(const string &in listName, int trackId) {
        TmxMap@[]@ maps = GetMaps(listName);
        for (uint i = 0; i < maps.Length; i++) {
            if (maps[i].TrackId == trackId) {
                maps.RemoveAt(i);
                Save(listName, maps);
                return;
            }
        }
    }

    TmxMap@[]@ GetMaps(const string &in listName) {
        TmxMap@[] listMaps;
        string path = GetStoragePath();
        if (!IO::FileExists(path)) return listMaps;
        
        Json::Value@ json = Json::FromFile(path);
        if (json.HasKey(listName) && json[listName].GetType() == Json::Type::Array) {
            for (uint i = 0; i < json[listName].Length; i++) {
                listMaps.InsertLast(TmxMap(json[listName][i]));
            }
        }
        return listMaps;
    }

    void DeleteList(const string &in listName) {
        string path = GetStoragePath();
        if (!IO::FileExists(path)) return;
        
        Json::Value@ json = Json::FromFile(path);
        if (json.HasKey(listName)) {
            json.Remove(listName);
            Json::ToFile(path, json);
            Load();
            Notify("Deleted local list '" + listName + "'");
        }
    }

    void Notify(const string &in msg) {
        UI::ShowNotification("Local Lists", msg);
    }
}
