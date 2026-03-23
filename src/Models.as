// Club Manager - Models.as

class Club {
    uint Id;
    string Name;
    string Tag;
    string Description;
    string IconUrl;
    string VerticalUrl;
    string BackgroundUrl;
    string Role; // "MEMBER", "ADMIN", "CREATOR"
    string StadiumGrassUrl;
    string StadiumTerrainUrl;
    string StadiumLogoUrl;
    bool Public;

    Club() {}

    Club(Json::Value@ json) {
        if (json.GetType() != Json::Type::Object) return;
        Id = json.HasKey("id") ? uint(json["id"]) : 0;
        Name = json.HasKey("name") ? Text::StripFormatCodes(string(json["name"])) : "Unknown Club";
        Tag = json.HasKey("tag") ? Text::StripFormatCodes(string(json["tag"])) : "";
        Description = json.HasKey("description") ? string(json["description"]) : "";
        IconUrl = json.HasKey("iconUrl") ? string(json["iconUrl"]) : "";
        VerticalUrl = json.HasKey("verticalUrl") ? string(json["verticalUrl"]) : "";
        BackgroundUrl = json.HasKey("backgroundUrl") ? string(json["backgroundUrl"]) : "";
        StadiumGrassUrl = json.HasKey("stadiumGrassUrl") ? string(json["stadiumGrassUrl"]) : "";
        StadiumTerrainUrl = json.HasKey("stadiumTerrainUrl") ? string(json["stadiumTerrainUrl"]) : "";
        StadiumLogoUrl = json.HasKey("stadiumLogoUrl") ? string(json["stadiumLogoUrl"]) : "";
        Public = json.HasKey("public") ? bool(json["public"]) : true;
        if (json.HasKey("role")) {
            Role = json["role"];
        } else {
            Role = "Member";
        }
    }
}

class MapInfo {
    string Uid;
    string Name;
    string Author;
    string AuthorWebServicesId;

    MapInfo() {}
    MapInfo(Json::Value@ json) {
        if (json.GetType() != Json::Type::Object) return;
        // Nadeo API uses mapUid, but we handle variations for robustness
        if (json.HasKey("mapUid")) Uid = string(json["mapUid"]);
        else if (json.HasKey("uid")) Uid = string(json["uid"]);
        else if (json.HasKey("MapUid")) Uid = string(json["MapUid"]);
        else if (json.HasKey("MapUID")) Uid = string(json["MapUID"]);
        else Uid = "";
        Name = json.HasKey("name") ? Text::StripFormatCodes(string(json["name"])) : "Unknown Map";
        AuthorWebServicesId = json.HasKey("author") ? string(json["author"]) : "";
        Author = "Unknown Author";
    }
}

class Activity {
    uint Id;
    string Name;
    uint Position;
    uint FolderId;
    string Type; // "folder", "campaign", "room"
    bool Active;
    bool Public;
    bool Featured;
    uint CampaignId;
    string MirroringCampaignName = "";
    uint RoomId;
    uint ParticipantCount = 0;
    string ServerStatus = "";
    string Script = "";
    int MaxPlayers = 32;
    bool Scalable = true;
    string Region = "";
    string Password = "";
    string IconUrl = "";
    string VerticalUrl = "";
    string BackgroundUrl = "";
    MapInfo[] Maps;
    bool MapsLoaded = false;
    bool LoadingMaps = false;

    // UI state
    bool IsRenaming = false;
    string RenameBuffer = "";
    bool PendingDelete = false;
    bool IsManagingMaps = false;
    bool IsManagingSettings = false;
    MapInfo[] PendingMaps;

    // Audit results
    bool IsAuditing = false;
    bool AuditDone = false;
    bool AuditOrderMismatch = false;
    TmxMap[] AuditAdded;
    MapInfo[] AuditRemoved;

    Activity() {}

    Activity(Json::Value@ json) {
        if (json.GetType() != Json::Type::Object) return;
        Id = json.HasKey("id") ? uint(json["id"]) : 0;
        string rawName = json.HasKey("name") ? string(json["name"]) : "Unknown Activity";
        // Strip |ClubActivity| and pipes
        Name = rawName.Replace("|ClubActivity|", "").Replace("|", "");
        Name = Text::StripFormatCodes(Name);
        Position = json.HasKey("position") ? uint(json["position"]) : 0;
        
        // Handle folderId/parentId safely (can be null)
        if (json.HasKey("folderId") && json["folderId"].GetType() != Json::Type::Null) {
            FolderId = uint(json["folderId"]);
        } else if (json.HasKey("parentId") && json["parentId"].GetType() != Json::Type::Null) {
            FolderId = uint(json["parentId"]);
        } else {
            FolderId = 0;
        }

        Type = json.HasKey("activityType") ? string(json["activityType"]) : (json.HasKey("type") ? string(json["type"]) : "");
        Active = json.HasKey("active") ? bool(json["active"]) : false;
        Public = json.HasKey("public") ? bool(json["public"]) : true;
        Featured = json.HasKey("featured") ? bool(json["featured"]) : false;
        Description = json.HasKey("description") ? string(json["description"]) : "";
        
        // News mapping basics
        if (Type == "news") {
            Headline = Name;
            Body = Description;
        }
        if (json.HasKey("campaignId") && json["campaignId"].GetType() != Json::Type::Null) {
            CampaignId = uint(json["campaignId"]);
        } else if (Type == "campaign" && json.HasKey("externalId")) {
            CampaignId = uint(json["externalId"]);
        }

        if (json.HasKey("roomId") && json["roomId"].GetType() != Json::Type::Null) {
            RoomId = uint(json["roomId"]);
        } else if (Type == "room") {
            RoomId = Id;
        }

        if (json.HasKey("participantCount") && json["participantCount"].GetType() != Json::Type::Null) {
            ParticipantCount = uint(json["participantCount"]);
        }

        if (json.HasKey("mediaUrlPngMedium") && string(json["mediaUrlPngMedium"]) != "") IconUrl = json["mediaUrlPngMedium"];
        else if (json.HasKey("mediaUrl") && string(json["mediaUrl"]) != "") IconUrl = json["mediaUrl"];
        else if (json.HasKey("iconUrl")) IconUrl = json["iconUrl"];
        else IconUrl = "";

        VerticalUrl = json.HasKey("mediaUrlPngLarge") ? string(json["mediaUrlPngLarge"]) : (json.HasKey("verticalUrl") ? string(json["verticalUrl"]) : "");
        BackgroundUrl = json.HasKey("mediaUrl") ? string(json["mediaUrl"]) : (json.HasKey("backgroundUrl") ? string(json["backgroundUrl"]) : "");
    }

    // Properties
    string Headline;
    string Body;
    string Description;
    bool NewsLoaded = false;
}

class TmxMap {
    int TrackId;
    string Uid;
    string Name;
    string Author;
    uint LengthSecs;
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
        // v2 API field names
        TrackId = json.HasKey("MapId") ? int(json["MapId"]) : 0;
        
        // TMX API uses MapUid, but we handle variations for robustness
        if (json.HasKey("MapUid")) Uid = string(json["MapUid"]);
        else if (json.HasKey("mapUid")) Uid = string(json["mapUid"]);
        else if (json.HasKey("MapUID")) Uid = string(json["MapUID"]);
        else if (json.HasKey("uid")) Uid = string(json["uid"]);
        else Uid = "";
        Name = json.HasKey("Name") ? Text::StripFormatCodes(string(json["Name"])) : "Unknown Map";

        // Uploader is a nested object in v2
        if (json.HasKey("Uploader") && json["Uploader"].GetType() == Json::Type::Object) {
            Author = json["Uploader"].HasKey("Name") ? Text::StripFormatCodes(string(json["Uploader"]["Name"])) : "Unknown Author";
        } else {
            Author = "Unknown Author";
        }

        // Length in v2 is milliseconds (same as AuthorTime in v1)
        if (json.HasKey("Medals") && json["Medals"].GetType() == Json::Type::Object && json["Medals"].HasKey("Author")) {
            LengthSecs = uint(json["Medals"]["Author"]) / 1000;
        } else if (json.HasKey("Length")) {
            LengthSecs = uint(json["Length"]) / 1000;
        } else {
            LengthSecs = 0;
        }

        // v2 Difficulty is an int enum: 0=Beginner,1=Intermediate,2=Advanced,3=Expert,4=Lunatic,5=Impossible
        if (json.HasKey("Difficulty")) {
            int diff = int(json["Difficulty"]);
            if (diff >= 0 && diff < int(TMX::DIFFICULTY_NAMES.Length))
                DifficultyName = TMX::DIFFICULTY_NAMES[diff];
            else
                DifficultyName = "Unknown";
        } else {
            DifficultyName = "Unknown";
        }

        AwardCount = json.HasKey("AwardCount") ? uint(json["AwardCount"]) : 0;
        RecordCount = json.HasKey("ReplayCount") ? uint(json["ReplayCount"]) : (json.HasKey("RecordCount") ? uint(json["RecordCount"]) : 0);

        SizeWarning = json.HasKey("SizeWarning") ? string(json["SizeWarning"]) : ""; // Keep just in case it exists too
        ServerSizeExceeded = json.HasKey("ServerSizeExceeded") ? bool(json["ServerSizeExceeded"]) : false;
        EmbeddedItemsSize = json.HasKey("EmbeddedItemsSize") ? uint(json["EmbeddedItemsSize"]) : 0;
        DisplayCost = json.HasKey("DisplayCost") ? uint(json["DisplayCost"]) : 0;

        if (json.HasKey("AuthorBeaten")) {
            AtBeaten = bool(json["AuthorBeaten"]);
        } else if (json.HasKey("AuthorTimeBeaten")) {
            AtBeaten = bool(json["AuthorTimeBeaten"]);
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
            } else if (json.HasKey("ReplayWR.RecordTime")) {
                wr = uint(json["ReplayWR.RecordTime"]);
            }

            AtBeaten = (wr > 0 && wr < at);
        }

        // v2 Tags is an array of objects with TagId and Name
        if (json.HasKey("Tags") && json["Tags"].GetType() == Json::Type::Array) {
            for (uint i = 0; i < json["Tags"].Length; i++) {
                auto t = json["Tags"][i];
                if (t.GetType() == Json::Type::Object && t.HasKey("Name"))
                    Tags.InsertLast(string(t["Name"]));
            }
        }

        UploadedAt = json.HasKey("UploadedAt") ? string(json["UploadedAt"]) : "";
        HasScreenshot = json.HasKey("HasThumbnail") ? bool(json["HasThumbnail"]) : TrackId > 0;
    }
}

class TmxSearchFilters {
    string AuthorName = "";
    int Vehicle = -1; // -1 = any
    string[] IncludeTags = {};
    string[] ExcludeTags = {};
    int Difficulty = -1; // -1 = any
    uint TimeFromMs = 0;
    uint TimeToMs = 0;
    int hFrom = 0, mFrom = 0, sFrom = 0;
    int hTo = 0, mTo = 0, sTo = 0;
    string UploadedFrom = "";
    string UploadedTo = "";
    int SortPrimary = -1;
    int SortSecondary = -1;
    int InTOTD = -1;       // -1=any, 1=was TOTD, 0=was not TOTD
    int InOnlineRecords = -1; // -1=any, 1=has my record, 0=no record
    bool HideOversized = false;
    uint Offset = 0;
    int CurrentPage = 1;
    int[] PageStartingTrackIds = { 0 }; // TrackId to use with 'after' for each page. Page 1 starts at 0 (none).
    bool PrimaryTagOnly = false;
    bool PrimarySurfaceOnly = false;
    uint ResultLimit = 25;

    TmxSearchFilters() {}

    TmxSearchFilters(Json::Value@ json) {
        if (json.GetType() != Json::Type::Object) return;
        AuthorName = json.HasKey("AuthorName") ? string(json["AuthorName"]) : "";
        Vehicle = json.HasKey("Vehicle") ? int(json["Vehicle"]) : -1;
        Difficulty = json.HasKey("Difficulty") ? int(json["Difficulty"]) : -1;
        TimeFromMs = json.HasKey("TimeFromMs") ? uint(json["TimeFromMs"]) : 0;
        TimeToMs = json.HasKey("TimeToMs") ? uint(json["TimeToMs"]) : 0;
        UploadedFrom = json.HasKey("UploadedFrom") ? string(json["UploadedFrom"]) : "";
        UploadedTo = json.HasKey("UploadedTo") ? string(json["UploadedTo"]) : "";
        SortPrimary = json.HasKey("SortPrimary") ? int(json["SortPrimary"]) : -1;
        SortSecondary = json.HasKey("SortSecondary") ? int(json["SortSecondary"]) : -1;
        InTOTD = json.HasKey("InTOTD") ? int(json["InTOTD"]) : -1;
        InOnlineRecords = json.HasKey("InOnlineRecords") ? int(json["InOnlineRecords"]) : -1;
        HideOversized = json.HasKey("HideOversized") ? bool(json["HideOversized"]) : false;
        PrimaryTagOnly = json.HasKey("PrimaryTagOnly") ? bool(json["PrimaryTagOnly"]) : false;
        PrimarySurfaceOnly = json.HasKey("PrimarySurfaceOnly") ? bool(json["PrimarySurfaceOnly"]) : false;
        ResultLimit = json.HasKey("ResultLimit") ? uint(json["ResultLimit"]) : 25;
        CurrentPage = json.HasKey("CurrentPage") ? int(json["CurrentPage"]) : 1;

        if (json.HasKey("IncludeTags") && json["IncludeTags"].GetType() == Json::Type::Array) {
            for (uint i = 0; i < json["IncludeTags"].Length; i++) IncludeTags.InsertLast(string(json["IncludeTags"][i]));
        }
        if (json.HasKey("ExcludeTags") && json["ExcludeTags"].GetType() == Json::Type::Array) {
            for (uint i = 0; i < json["ExcludeTags"].Length; i++) ExcludeTags.InsertLast(string(json["ExcludeTags"][i]));
        }
        if (json.HasKey("PageStartingTrackIds") && json["PageStartingTrackIds"].GetType() == Json::Type::Array) {
            PageStartingTrackIds.RemoveRange(0, PageStartingTrackIds.Length);
            for (uint i = 0; i < json["PageStartingTrackIds"].Length; i++) PageStartingTrackIds.InsertLast(int(json["PageStartingTrackIds"][i]));
        } else {
            PageStartingTrackIds.InsertLast(0);
        }
    }

    Json::Value@ ToJson() {
        Json::Value@ json = Json::Object();
        trace("  DEBUG [Models.as]: Filters.CurrentPage is " + CurrentPage);
        json["AuthorName"] = AuthorName;
        json["Vehicle"] = Vehicle;
        json["Difficulty"] = Difficulty;
        json["TimeFromMs"] = TimeFromMs;
        json["TimeToMs"] = TimeToMs;
        json["UploadedFrom"] = UploadedFrom;
        json["UploadedTo"] = UploadedTo;
        json["SortPrimary"] = SortPrimary;
        json["SortSecondary"] = SortSecondary;
        json["InTOTD"] = InTOTD;
        json["InOnlineRecords"] = InOnlineRecords;
        json["HideOversized"] = HideOversized;
        json["PrimaryTagOnly"] = PrimaryTagOnly;
        json["PrimarySurfaceOnly"] = PrimarySurfaceOnly;
        json["ResultLimit"] = ResultLimit;
        json["CurrentPage"] = CurrentPage;
        // trace("TmxSearchFilters::ToJson - Page: " + CurrentPage);
        
        Json::Value@ inc = Json::Array();
        for (uint i = 0; i < IncludeTags.Length; i++) inc.Add(IncludeTags[i]);
        json["IncludeTags"] = inc;
        
        Json::Value@ exc = Json::Array();
        for (uint i = 0; i < ExcludeTags.Length; i++) exc.Add(ExcludeTags[i]);
        json["ExcludeTags"] = exc;
        
        Json::Value@ ptid = Json::Array();
        for (uint i = 0; i < PageStartingTrackIds.Length; i++) ptid.Add(PageStartingTrackIds[i]);
        json["PageStartingTrackIds"] = ptid;
        
        return json;
    }
}

class Subscription {
    uint ActivityId;
    string ActivityName;
    TmxSearchFilters@ Filters;
    uint MapLimit = 25;
    uint LastRun = 0;
    string[] CurrentMapUids;

    Subscription() {
        @Filters = TmxSearchFilters();
    }

    Subscription(Json::Value@ json) {
        if (json.GetType() != Json::Type::Object) return;
        ActivityId = json.HasKey("ActivityId") ? uint(json["ActivityId"]) : 0;
        ActivityName = json.HasKey("ActivityName") ? string(json["ActivityName"]) : "";
        @Filters = json.HasKey("Filters") ? TmxSearchFilters(json["Filters"]) : TmxSearchFilters();
        MapLimit = json.HasKey("MapLimit") ? uint(json["MapLimit"]) : 25;
        LastRun = json.HasKey("LastRun") ? uint(json["LastRun"]) : 0;
        
        if (json.HasKey("CurrentMapUids") && json["CurrentMapUids"].GetType() == Json::Type::Array) {
            for (uint i = 0; i < json["CurrentMapUids"].Length; i++) CurrentMapUids.InsertLast(string(json["CurrentMapUids"][i]));
        }
    }

    Json::Value@ ToJson() {
        Json::Value@ json = Json::Object();
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
    // Tag names and their real TMX IDs (from trackmania.exchange/api/tags/gettags)
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

    // Corresponding real TMX tag IDs (index-matched to TAG_NAMES)
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

    const string[] SORT_OPTIONS = {
        "Awards Most", "Awards Least", "Downloads Most", "Activity Newest",
        "Comments Most", "Comments Least", "Difficulty Easiest", "Difficulty Hardest",
        "Length Shortest", "Length Longest", "Name A-Z", "Name Z-A",
        "Online Rating Most", "Online Rating Least",
        "Uploaded Newest", "Uploaded Oldest",
        "Awards This Week", "Awards This Month"
    };

    const string[] SURFACE_TAGS = { "Bobsleigh", "Dirt", "Grass", "Ice", "Mixed", "Plastic", "Tech", "Water", "Wood" };
    const string[] VEHICLE_NAMES = { "CarSport", "CarSnow", "CarRally", "CarDesert" };
    const string[] DIFFICULTY_NAMES = { "Beginner", "Intermediate", "Advanced", "Expert", "Lunatic", "Impossible" };
}
