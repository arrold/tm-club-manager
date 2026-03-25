// Models.as - Data Models & JSON Helpers

// --- Safe JSON Helpers ---

uint JsonGetUint(Json::Value@ json, const string &in key, uint defaultValue = 0) {
    if (json is null || !json.HasKey(key)) return defaultValue;
    auto v = json[key];
    if (v.GetType() == Json::Type::Number) return uint(v);
    if (v.GetType() == Json::Type::String) return Text::ParseUInt(string(v));
    return defaultValue;
}

int JsonGetInt(Json::Value@ json, const string &in key, int defaultValue = 0) {
    if (json is null || !json.HasKey(key)) return defaultValue;
    auto v = json[key];
    if (v.GetType() == Json::Type::Number) return int(v);
    if (v.GetType() == Json::Type::String) return Text::ParseInt(string(v));
    return defaultValue;
}

bool JsonGetBool(Json::Value@ json, const string &in key, bool defaultValue = false) {
    if (json is null || !json.HasKey(key)) return defaultValue;
    auto v = json[key];
    if (v.GetType() == Json::Type::Boolean) return bool(v);
    if (v.GetType() == Json::Type::Number) return int(v) != 0;
    if (v.GetType() == Json::Type::String) {
        string s = string(v).ToLower();
        return s == "true" || s == "1";
    }
    return defaultValue;
}

string JsonGetString(Json::Value@ json, const string &in key, const string &in defaultValue = "") {
    if (json is null || !json.HasKey(key)) return defaultValue;
    auto v = json[key];
    if (v.GetType() == Json::Type::String) return string(v);
    if (v.GetType() == Json::Type::Number || v.GetType() == Json::Type::Boolean) return Json::Write(v);
    return defaultValue;
}

// --- Classes ---

class Club {
    uint Id;
    string Name;
    string Tag;
    string Description;
    string Role;
    bool Public;
    string IconUrl;
    string VerticalUrl;
    string BackgroundUrl;
    string StadiumGrassUrl;
    string StadiumTerrainUrl;
    string StadiumLogoUrl;

    Club() {}
    Club(Json::Value@ json) {
        if (json.GetType() != Json::Type::Object) return;
        
        if (json.HasKey("id")) Id = uint(json["id"]);
        else if (json.HasKey("clubId")) Id = uint(json["clubId"]);
        else Id = 0;

        Name = Text::StripFormatCodes(JsonGetString(json, "name", "Unknown Club"));
        Tag = JsonGetString(json, "tag");
        Description = JsonGetString(json, "description");
        Role = JsonGetString(json, "role", "Member");
        Public = JsonGetBool(json, "public");
        
        IconUrl = JsonGetString(json, "iconUrl");
        VerticalUrl = JsonGetString(json, "verticalUrl");
        BackgroundUrl = JsonGetString(json, "backgroundUrl");
        StadiumGrassUrl = JsonGetString(json, "stadiumGrassUrl");
        StadiumTerrainUrl = JsonGetString(json, "stadiumTerrainUrl");
        StadiumLogoUrl = JsonGetString(json, "stadiumLogoUrl");
    }
}

class MapInfo {
    string Uid;
    string Name;
    string Author;
    string AuthorWebServicesId;
    bool PendingDelete = false;

    MapInfo() {}
    MapInfo(Json::Value@ json) {
        if (json.GetType() != Json::Type::Object) return;
        if (json.HasKey("mapUid")) Uid = string(json["mapUid"]);
        else if (json.HasKey("uid")) Uid = string(json["uid"]);
        else if (json.HasKey("MapUid")) Uid = string(json["MapUid"]);
        else if (json.HasKey("MapUID")) Uid = string(json["MapUID"]);
        else Uid = "";
        Name = json.HasKey("name") ? Text::StripFormatCodes(string(json["name"])) : "Unknown Map";
        AuthorWebServicesId = json.HasKey("author") ? string(json["author"]) : "";
        Author = "Unknown Author";
    }
    MapInfo(LocalMap@ lm) {
        Uid = lm.Uid;
        Name = lm.Name;
        Author = "Local Map";
    }
}

class Activity {
    uint Id;
    string Name;
    string Type; // campaign, room, folder, news
    bool Active;
    bool Public;
    bool Featured;
    uint FolderId;
    uint Position;
    
    // Metadata properties
    uint CampaignId = 0;
    string MirroringCampaignName = "";
    uint RoomId = 0;
    
    MapInfo[] Maps;
    MapInfo[] PendingMaps;
    
    // Metadata for UI
    bool MapsLoaded = false;
    bool LoadingMaps = false;
    bool NewsLoaded = false;
    bool IsRenaming = false;
    string RenameBuffer = "";
    bool IsMoving = false;
    bool PendingDelete = false;
    bool IsManagingMaps = false;
    bool HasMapChanges = false;

    // News specific
    string Headline;
    string Body;
    string Description;

    // Curation specific
    bool IsAuditing = false;
    bool AuditDone = false;
    bool AuditOrderMismatch = false;
    TmxMap[] AuditAdded;
    MapInfo[] AuditRemoved;

    Activity() {}
    Activity(Json::Value@ json) {
        if (json.GetType() != Json::Type::Object) return;
        
        if (json.HasKey("id")) Id = uint(json["id"]);
        else if (json.HasKey("activityId")) Id = uint(json["activityId"]);
        else Id = 0;

        Name = JsonGetString(json, "name", "Unknown Activity");
        // Cleanup |ClubActivity| tags
        Name = Name.Replace("|ClubActivity|", "").Replace("|", "");
        Name = Text::StripFormatCodes(Name);

        Type = JsonGetString(json, "activityType");
        Active = JsonGetBool(json, "active");
        Public = JsonGetBool(json, "public");
        Featured = JsonGetBool(json, "featured");
        FolderId = JsonGetUint(json, "folderId");
        if (FolderId == 0) FolderId = JsonGetUint(json, "parentId");
        Position = JsonGetUint(json, "position");
        
        Description = JsonGetString(json, "description");
        if (Type == "news") {
            Headline = Name;
            Body = Description;
        }
        
        // Resolve type-specific IDs
        if (Type == "campaign") {
            CampaignId = JsonGetUint(json, "campaignId");
            if (CampaignId == 0) CampaignId = Id; // fallback: activity ID often == resource ID for campaigns
        } else if (Type == "room") {
            RoomId = JsonGetUint(json, "roomId");
            if (RoomId == 0) RoomId = Id; // fallback
        }
    }
}

class TmxMap {
    int TrackId;
    string Uid;
    string Name;
    string Author;
    uint LengthSecs;
    int Difficulty; // 1-6 (Normalised for internal comparisons)
    string DifficultyName;
    uint AwardCount;
    uint RecordCount;
    bool AtBeaten;
    string SizeWarning;
    string UploadedAt;
    bool ServerSizeExceeded;
    uint EmbeddedItemsSize;
    uint DisplayCost;
    string[] Tags;
    bool HasScreenshot;

    TmxMap() {}

    TmxMap(Json::Value@ json) {
        if (json.GetType() != Json::Type::Object) return;
        TrackId = json.HasKey("MapId") ? int(json["MapId"]) : 0;
        
        if (json.HasKey("MapUid")) Uid = string(json["MapUid"]);
        else if (json.HasKey("mapUid")) Uid = string(json["mapUid"]);
        else if (json.HasKey("uid")) Uid = string(json["uid"]);
        else Uid = "";

        Name = json.HasKey("Name") ? Text::StripFormatCodes(string(json["Name"])) : "Unknown Map";

        if (json.HasKey("Uploader") && json["Uploader"].GetType() == Json::Type::Object) {
            Author = json["Uploader"].HasKey("Name") ? Text::StripFormatCodes(string(json["Uploader"]["Name"])) : "Unknown Author";
        } else {
            Author = "Unknown Author";
        }

        if (json.HasKey("Medals") && json["Medals"].GetType() == Json::Type::Object && json["Medals"].HasKey("Author")) {
            LengthSecs = uint(json["Medals"]["Author"]) / 1000;
        } else if (json.HasKey("Length")) {
            LengthSecs = uint(json["Length"]) / 1000;
        } else {
            LengthSecs = 0;
        }

        if (json.HasKey("Difficulty")) {
            int dVal = int(json["Difficulty"]); // 0-5 from V2 API
            Difficulty = dVal + 1; // Normalise to 1-6
            if (dVal >= 0 && dVal < int(TMX::DIFFICULTY_NAMES.Length))
                DifficultyName = TMX::DIFFICULTY_NAMES[dVal];
            else
                DifficultyName = "Unknown";
        } else {
            Difficulty = 0;
            DifficultyName = "Unknown";
        }

        AwardCount = json.HasKey("AwardCount") ? uint(json["AwardCount"]) : 0;
        RecordCount = json.HasKey("ReplayCount") ? uint(json["ReplayCount"]) : (json.HasKey("RecordCount") ? uint(json["RecordCount"]) : 0);

        ServerSizeExceeded = json.HasKey("ServerSizeExceeded") ? bool(json["ServerSizeExceeded"]) : false;
        EmbeddedItemsSize = json.HasKey("EmbeddedItemsSize") ? uint(json["EmbeddedItemsSize"]) : 0;
        DisplayCost = json.HasKey("DisplayCost") ? uint(json["DisplayCost"]) : 0;

        if (json.HasKey("AuthorBeaten")) {
            AtBeaten = bool(json["AuthorBeaten"]);
        } else {
            uint at = 0;
            if (json.HasKey("Medals") && json["Medals"].GetType() == Json::Type::Object) {
                at = json["Medals"].HasKey("Author") ? uint(json["Medals"]["Author"]) : 0;
            } else if (json.HasKey("AuthorTime")) {
                at = uint(json["AuthorTime"]);
            }

            uint wr = 0;
            if (json.HasKey("ReplayWR") && json["ReplayWR"].GetType() == Json::Type::Object) {
                wr = json["ReplayWR"].HasKey("RecordTime") ? uint(json["ReplayWR"]["RecordTime"]) : 0;
            }
            AtBeaten = (wr > 0 && wr < at);
        }

        if (json.HasKey("Tags") && json["Tags"].GetType() == Json::Type::Array) {
            for (uint i = 0; i < json["Tags"].Length; i++) {
                auto t = json["Tags"][i];
                if (t.GetType() == Json::Type::Object && t.HasKey("Name"))
                    Tags.InsertLast(string(t["Name"]));
            }
        }

        UploadedAt = json.HasKey("UploadedAt") ? string(json["UploadedAt"]) : "";
        HasScreenshot = json.HasKey("HasThumbnail") ? bool(json["HasThumbnail"]) : TrackId > 0;

        // Calculate size warnings for club rooms
        if (ServerSizeExceeded || EmbeddedItemsSize > 4000000 || DisplayCost > 100000) {
            SizeWarning = "\\$f00" + Icons::ExclamationTriangle;
        } else if (EmbeddedItemsSize > 2500000 || DisplayCost > 60000) {
            SizeWarning = "\\$fd0" + Icons::ExclamationTriangle;
        } else {
            SizeWarning = "";
        }
    }
}

class TmxSearchFilters {
    string MapName = "";
    string AuthorName = "";
    int Vehicle = -1; 
    string[] IncludeTags = {};
    string[] ExcludeTags = {};
    
    // Multi-select difficulty
    bool[] Difficulties = { false, false, false, false, false, false };
    int Difficulty = -1; // Single difficulty for API mapping

    uint TimeFromMs = 0;
    uint TimeToMs = 0;
    int hFrom = 0, mFrom = 0, sFrom = 0;
    int hTo = 0, mTo = 0, sTo = 0;
    string UploadedFrom = "";
    string UploadedTo = "";
    int SortPrimary = -1;
    int SortSecondary = -1;
    int InTOTD = -1;
    int InCollection = -1;
    int InOnlineRecords = -1; // Retained for compatibility
    bool HideOversized = false;
    int CurrentPage = 1;
    bool PrimaryTagOnly = false;
    bool PrimarySurfaceOnly = false;
    uint ResultLimit = 25;

    TmxSearchFilters() {}

    TmxSearchFilters(Json::Value@ json) {
        if (json.GetType() != Json::Type::Object) return;
        MapName = JsonGetString(json, "MapName");
        AuthorName = JsonGetString(json, "AuthorName");
        Vehicle = JsonGetInt(json, "Vehicle", -1);
        Difficulty = JsonGetInt(json, "Difficulty", -1);
        
        if (json.HasKey("Difficulties") && json["Difficulties"].GetType() == Json::Type::Array) {
            for (uint i = 0; i < json["Difficulties"].Length && i < Difficulties.Length; i++)
                Difficulties[i] = bool(json["Difficulties"][i]);
        }

        TimeFromMs = JsonGetUint(json, "TimeFromMs");
        TimeToMs = JsonGetUint(json, "TimeToMs");
        UploadedFrom = JsonGetString(json, "UploadedFrom");
        UploadedTo = JsonGetString(json, "UploadedTo");
        SortPrimary = JsonGetInt(json, "SortPrimary", -1);
        SortSecondary = JsonGetInt(json, "SortSecondary", -1);
        InTOTD = JsonGetInt(json, "InTOTD", -1);
        InCollection = JsonGetInt(json, "InCollection", -1);
        InOnlineRecords = JsonGetInt(json, "InOnlineRecords", -1);
        HideOversized = JsonGetBool(json, "HideOversized");
        PrimaryTagOnly = JsonGetBool(json, "PrimaryTagOnly");
        PrimarySurfaceOnly = JsonGetBool(json, "PrimarySurfaceOnly");
        ResultLimit = JsonGetUint(json, "ResultLimit", 25);
        CurrentPage = JsonGetInt(json, "CurrentPage", 1);

        hFrom = (TimeFromMs / 3600000);
        mFrom = (TimeFromMs % 3600000) / 60000;
        sFrom = (TimeFromMs % 60000) / 1000;
        hTo = (TimeToMs / 3600000);
        mTo = (TimeToMs % 3600000) / 60000;
        sTo = (TimeToMs % 60000) / 1000;

        if (json.HasKey("IncludeTags") && json["IncludeTags"].GetType() == Json::Type::Array) {
            for (uint i = 0; i < json["IncludeTags"].Length; i++) IncludeTags.InsertLast(string(json["IncludeTags"][i]));
        }
        if (json.HasKey("ExcludeTags") && json["ExcludeTags"].GetType() == Json::Type::Array) {
            for (uint i = 0; i < json["ExcludeTags"].Length; i++) ExcludeTags.InsertLast(string(json["ExcludeTags"][i]));
        }
    }

    void SyncTimeMs() {
        TimeFromMs = (hFrom * 3600000) + (mFrom * 60000) + (sFrom * 1000);
        TimeToMs = (hTo * 3600000) + (mTo * 60000) + (sTo * 1000);
    }

    TmxSearchFilters@ Clone() {
        SyncTimeMs();
        auto other = TmxSearchFilters();
        other.MapName = MapName;
        other.AuthorName = AuthorName;
        other.Vehicle = Vehicle;
        other.Difficulty = Difficulty;
        for (uint i = 0; i < Difficulties.Length; i++) other.Difficulties[i] = Difficulties[i];
        other.TimeFromMs = TimeFromMs;
        other.TimeToMs = TimeToMs;
        other.hFrom = hFrom; other.mFrom = mFrom; other.sFrom = sFrom;
        other.hTo = hTo; other.mTo = mTo; other.sTo = sTo;
        other.UploadedFrom = UploadedFrom;
        other.UploadedTo = UploadedTo;
        other.SortPrimary = SortPrimary;
        other.SortSecondary = SortSecondary;
        other.InTOTD = InTOTD;
        other.InCollection = InCollection;
        other.InOnlineRecords = InOnlineRecords;
        other.HideOversized = HideOversized;
        other.PrimaryTagOnly = PrimaryTagOnly;
        other.PrimarySurfaceOnly = PrimarySurfaceOnly;
        other.ResultLimit = ResultLimit;
        other.CurrentPage = CurrentPage;
        for (uint i = 0; i < IncludeTags.Length; i++) other.IncludeTags.InsertLast(IncludeTags[i]);
        for (uint i = 0; i < ExcludeTags.Length; i++) other.ExcludeTags.InsertLast(ExcludeTags[i]);
        return other;
    }

    Json::Value@ ToJson() {
        SyncTimeMs();
        Json::Value@ json = Json::Object();
        json["MapName"] = MapName;
        json["AuthorName"] = AuthorName;
        json["Vehicle"] = Vehicle;
        json["Difficulty"] = Difficulty;
        
        Json::Value@ diffs = Json::Array();
        for (uint i = 0; i < Difficulties.Length; i++) diffs.Add(Difficulties[i]);
        json["Difficulties"] = diffs;

        json["TimeFromMs"] = TimeFromMs;
        json["TimeToMs"] = TimeToMs;
        json["UploadedFrom"] = UploadedFrom;
        json["UploadedTo"] = UploadedTo;
        json["SortPrimary"] = SortPrimary;
        json["SortSecondary"] = SortSecondary;
        json["InTOTD"] = InTOTD;
        json["InCollection"] = InCollection;
        json["InOnlineRecords"] = InOnlineRecords;
        json["HideOversized"] = HideOversized;
        json["PrimaryTagOnly"] = PrimaryTagOnly;
        json["PrimarySurfaceOnly"] = PrimarySurfaceOnly;
        json["ResultLimit"] = ResultLimit;
        json["CurrentPage"] = CurrentPage;
        
        Json::Value@ inc = Json::Array();
        for (uint i = 0; i < IncludeTags.Length; i++) inc.Add(IncludeTags[i]);
        json["IncludeTags"] = inc;
        
        Json::Value@ exc = Json::Array();
        for (uint i = 0; i < ExcludeTags.Length; i++) exc.Add(ExcludeTags[i]);
        json["ExcludeTags"] = exc;
        
        return json;
    }
}

class Subscription {
    uint ClubId; // For safe cleanup
    uint ActivityId;
    string ActivityName;
    TmxSearchFilters@ Filters;
    uint MapLimit = 25;
    uint LastRun = 0;
    string[] CurrentMapUids;

    Subscription() { @Filters = TmxSearchFilters(); }
    Subscription(Json::Value@ json) {
        if (json.GetType() != Json::Type::Object) return;
        ClubId = JsonGetUint(json, "ClubId");
        ActivityId = JsonGetUint(json, "ActivityId");
        ActivityName = JsonGetString(json, "ActivityName");
        @Filters = json.HasKey("Filters") ? TmxSearchFilters(json["Filters"]) : TmxSearchFilters();
        MapLimit = JsonGetUint(json, "MapLimit", 25);
        LastRun = JsonGetUint(json, "LastRun");
        
        if (json.HasKey("CurrentMapUids") && json["CurrentMapUids"].GetType() == Json::Type::Array) {
            for (uint i = 0; i < json["CurrentMapUids"].Length; i++) CurrentMapUids.InsertLast(string(json["CurrentMapUids"][i]));
        }
    }

    Json::Value@ ToJson() {
        Json::Value@ json = Json::Object();
        json["ClubId"] = ClubId;
        json["ActivityId"] = ActivityId;
        json["ActivityName"] = ActivityName;
        json["Filters"] = Filters.ToJson();
        json["MapLimit"] = MapLimit;
        json["LastRun"] = LastRun;
        
        Json::Value@ maps = Json::Array();
        for (uint i = 0; i < CurrentMapUids.Length; i++) maps.Add(CurrentMapUids[i]);
        json["CurrentMapUids"] = maps;
        
        return json;
    }
}

namespace TMX {
    const string[] TAG_NAMES = {
        "Altered Nadeo", "Arena", "Backwards", "Bobsleigh", "Bugslide", "Bumper",
        "Clones", "Competitive", "Cruise Control", "DesertCar", "Dirt", "Educational",
        "Endurance", "Engine Off", "FlagRush", "Fragile", "Freeblocking", "Freestyle",
        "FullSpeed", "Grass", "Ice", "Kacky", "LOL", "Magnet",
        "Mini", "Minigame", "Mixed", "MixedCar", "Moving Items", "Mudslide",
        "MultiLap", "Nascar", "No Brakes", "No Grip", "No Steering", "Obstacle",
        "Offroad", "Pathfinding", "Pipes", "Plastic", "Platform", "Precision",
        "Press Forward", "Puzzle", "Race", "RallyCar", "Reactor", "Remake",
        "Royal", "RPG", "RPG-Immersive", "Sausage", "Scenery", "Signature",
        "Slow Motion", "SnowCar", "SpeedDrift", "SpeedFun", "SpeedMapping", "SpeedTech",
        "Stunt", "Tech", "Transitional", "Trial", "Turtle", "Underwater",
        "Water", "Wood", "ZrT"
    };

    const int[] TAG_IDS = {
        49, 40, 34, 44, 56, 20,
        69, 13, 62, 59, 15, 42,
        24, 35, 46, 21, 48, 41,
        2, 33, 14, 23, 5, 66,
        25, 30, 27, 55, 58, 57,
        8, 28, 61, 67, 63, 31,
        9, 45, 65, 39, 18, 68,
        6, 47, 1, 54, 17, 26,
        37, 4, 64, 43, 22, 36,
        19, 50, 29, 12, 60, 7,
        16, 3, 32, 10, 53, 52,
        38, 51, 11
    };

    const string[] SORT_NAMES = {
        "Awards Most", "Awards Least", "Downloads Most", "Activity Newest",
        "Comments Most", "Comments Least", "Difficulty Easiest", "Difficulty Hardest",
        "Length Shortest", "Length Longest", "Name A-Z", "Name Z-A",
        "Online Rating Most", "Online Rating Least",
        "Uploaded Newest", "Uploaded Oldest",
        "Awards This Week", "Awards This Month"
    };

    const string[] COLLECTION_NAMES = { "Track of the Day", "ManiaClub", "World Tour", "Classic", "Map Pack" };
    const string[] SURFACE_TAGS = { "Bobsleigh", "Dirt", "Grass", "Ice", "Mixed", "Plastic", "Tech", "Water", "Wood" };
    const string[] VEHICLE_NAMES = { "CarSport", "CarSnow", "CarRally", "CarDesert" };
    const string[] DIFFICULTY_NAMES = { "Beginner", "Intermediate", "Advanced", "Expert", "Lunatic", "Impossible" };
    const string[] DIFFICULTY_WITH_ANY = { "Any", "Beginner", "Intermediate", "Advanced", "Expert", "Lunatic", "Impossible" };
}

class LocalMap {
    string Uid;
    string Name;
    string Filename;
    bool IsPlayable;
    bool IsValidated;
    bool IsUploaded;
    bool Selected = false;
    string SizeWarning;

    LocalMap() {}
    LocalMap(CGameCtnChallengeInfo@ info) {
        if (info is null) return;
        Uid = info.MapUid;
        Name = Text::StripFormatCodes(info.Name);
        if (Name == "") Name = "Known Map";
        Filename = info.FileName;
        IsPlayable = info.IsPlayable;
        // Treat "validated" as "playable/usable" as provided by Fids.
        IsValidated = IsPlayable;
    }
}

class FolderNode {
    string Name;
    FolderNode@[] Subfolders;
    LocalMap@[] Maps;

    FolderNode() {}
    FolderNode(const string &in name) {
        Name = name;
    }

    FolderNode@ GetOrCreateSubfolder(const string &in subName) {
        for (uint i = 0; i < Subfolders.Length; i++) {
            if (Subfolders[i].Name == subName) return Subfolders[i];
        }
        auto node = FolderNode(subName);
        Subfolders.InsertLast(node);
        return node;
    }

    void Sort() {
        // Sort subfolders by name
        for (uint i = 0; i < Subfolders.Length; i++) {
            for (uint j = i + 1; j < Subfolders.Length; j++) {
                if (Subfolders[i].Name > Subfolders[j].Name) {
                    auto temp = Subfolders[i]; @Subfolders[i] = Subfolders[j]; @Subfolders[j] = temp;
                }
            }
            Subfolders[i].Sort();
        }
        // Sort maps by name
        for (uint i = 0; i < Maps.Length; i++) {
            for (uint j = i + 1; j < Maps.Length; j++) {
                if (Maps[i].Name > Maps[j].Name) {
                    auto temp = Maps[i]; @Maps[i] = Maps[j]; @Maps[j] = temp;
                }
            }
        }
    }
}
