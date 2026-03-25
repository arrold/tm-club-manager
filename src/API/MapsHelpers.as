// API/MapsHelpers.as - Map processing utilities

namespace Maps {
    Json::Value@ GetListFromJson(Json::Value@ json) {
        if (json is null) return null;
        if (json.GetType() == Json::Type::Array) return json;
        if (json.GetType() != Json::Type::Object) return null;

        string[] keys = {"playlist", "maps", "mapList", "mapUidList", "list"};
        for (uint i = 0; i < keys.Length; i++) {
            if (json.HasKey(keys[i]) && json[keys[i]].GetType() == Json::Type::Array) return json[keys[i]];
        }

        string[] nested = {"campaign", "room", "resource"};
        for (uint i = 0; i < nested.Length; i++) {
            if (json.HasKey(nested[i]) && json[nested[i]].GetType() == Json::Type::Object) {
                auto res = GetListFromJson(json[nested[i]]);
                if (res !is null) return res;
            }
        }
        return null;
    }

    bool IsSurface(const string &in tag) {
        for (uint i = 0; i < TMX::SURFACE_TAGS.Length; i++) {
            if (TMX::SURFACE_TAGS[i] == tag) return true;
        }
        return false;
    }
}
