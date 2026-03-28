// Models.as - Data Models & JSON Helpers

// --- Safe JSON Helpers ---

uint JsonGetUint(Json::Value@ json, const string &in key, uint defaultValue = 0) {
    if (json is null || json.GetType() != Json::Type::Object || !json.HasKey(key)) return defaultValue;
    Json::Value@ v = json[key];
    if (v.GetType() == Json::Type::Number) return uint(v);
    if (v.GetType() == Json::Type::String) return Text::ParseUInt(string(v));
    return defaultValue;
}

int JsonGetInt(Json::Value@ json, const string &in key, int defaultValue = 0) {
    if (json is null || json.GetType() != Json::Type::Object || !json.HasKey(key)) return defaultValue;
    Json::Value@ v = json[key];
    if (v.GetType() == Json::Type::Number) return int(v);
    if (v.GetType() == Json::Type::String) return Text::ParseInt(string(v));
    return defaultValue;
}

bool JsonGetBool(Json::Value@ json, const string &in key, bool defaultValue = false) {
    if (json is null || json.GetType() != Json::Type::Object || !json.HasKey(key)) return defaultValue;
    Json::Value@ v = json[key];
    if (v.GetType() == Json::Type::Boolean) return bool(v);
    if (v.GetType() == Json::Type::Number) return int(v) != 0;
    if (v.GetType() == Json::Type::String) {
        string s = string(v).ToLower();
        return s == "true" || s == "1";
    }
    return defaultValue;
}

string JsonGetString(Json::Value@ json, const string &in key, const string &in defaultValue = "") {
    if (json is null || json.GetType() != Json::Type::Object || !json.HasKey(key)) return defaultValue;
    Json::Value@ v = json[key];
    if (v.GetType() == Json::Type::String) return string(v);
    if (v.GetType() == Json::Type::Number || v.GetType() == Json::Type::Boolean) return Json::Write(v);
    return defaultValue;
}

Json::Value@ JsonDeepExtract(Json::Value@ json) {
    if (json is null || json.GetType() != Json::Type::Object) return json;
    
    // If it's a wrapper for a specific resource type
    if (json.HasKey("activity") && json["activity"].GetType() == Json::Type::Object) return json["activity"];
    if (json.HasKey("campaign") && json["campaign"].GetType() == Json::Type::Object) return json["campaign"];
    if (json.HasKey("room") && json["room"].GetType() == Json::Type::Object) return json["room"];
    if (json.HasKey("news") && json["news"].GetType() == Json::Type::Object) return json["news"];
    if (json.HasKey("folder") && json["folder"].GetType() == Json::Type::Object) return json["folder"];
    
    return json;
}

// --- Classes ---

class Club {
    uint Id;
    string Name;
    string Tag;
    string Description;
    string Role;
    bool Public;
    Club() {}
    Club(Json::Value@ json) {
        if (json is null || json.GetType() != Json::Type::Object) return;
        
        if (json.HasKey("id")) Id = uint(json["id"]);
        else if (json.HasKey("clubId")) Id = uint(json["clubId"]);
        else Id = 0;

        Name = Text::StripFormatCodes(JsonGetString(json, "name", "Unknown Club"));
        Tag = JsonGetString(json, "tag");
        Description = JsonGetString(json, "description");
        Role = JsonGetString(json, "role", "Member");
        Public = JsonGetBool(json, "public");
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
        if (json is null || json.GetType() != Json::Type::Object) return;
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
    uint MirrorCampaignId = 0;
    
    MapInfo@[] Maps;

    
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
    bool Failed = false;
    
    // News specific
    string Headline;
    string Body;
    string Description;
    bool DetailsLoaded = false;

    void UpdateFromDetail(Json::Value@ json) {
        if (json is null || json.GetType() != Json::Type::Object) return;
        
        // Detail responses are often nested under a type key (e.g. "room": {...})
        Json::Value@ details = null;
        if (json.HasKey("room")) @details = json["room"];
        else if (json.HasKey("campaign")) @details = json["campaign"];
        else if (json.HasKey("news")) @details = json["news"];
        else @details = json;

        Description = JsonGetString(details, "description");
        if (Type == "news") {
            Headline = JsonGetString(details, "headline");
            Body = JsonGetString(details, "body");
            NewsLoaded = true;
        } else if (Type == "room") {
            // In the detailed room response, this is often called 'campaignId'
            MirrorCampaignId = JsonGetUint(details, "campaignId");
        }
        DetailsLoaded = true;
    }

    // Curation specific
    bool IsAuditing = false;
    bool AuditDone = false;
    bool AuditOrderMismatch = false;
    TmxMap@[] AuditAdded;
    MapInfo@[] AuditRemoved;
    string[] AuditFullUidList;

    Activity() {}
    Activity(Json::Value@ json) {
        if (json is null || json.GetType() != Json::Type::Object) return;
        
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
            MirrorCampaignId = JsonGetUint(json, "campaignId");
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
    uint DownloadCount;
    uint RecordCount;
    bool AtBeaten;
    string SizeWarning;
    string UploadedAt;
    bool ServerSizeExceeded;
    uint EmbeddedItemsSize;
    uint DisplayCost;
    string[] Tags;
    string[] Authors;
    bool HasScreenshot;

    TmxMap() {}

    TmxMap(Json::Value@ json) {
        if (json is null || json.GetType() != Json::Type::Object) return;
        TrackId = json.HasKey("MapId") ? int(json["MapId"]) : (json.HasKey("TrackId") ? int(json["TrackId"]) : 0);
        
        if (json.HasKey("MapUid")) Uid = string(json["MapUid"]);
        else if (json.HasKey("mapUid")) Uid = string(json["mapUid"]);
        else if (json.HasKey("uid")) Uid = string(json["uid"]);
        else Uid = "";

        Name = json.HasKey("Name") ? Text::StripFormatCodes(string(json["Name"])) : "Unknown Map";

        if (json.HasKey("Uploader") && json["Uploader"].GetType() == Json::Type::Object) {
            Author = json["Uploader"].HasKey("Name") ? Text::StripFormatCodes(string(json["Uploader"]["Name"])) : "Unknown Author";
        } else if (json.HasKey("UploaderName")) {
            Author = Text::StripFormatCodes(string(json["UploaderName"]));
        } else if (json.HasKey("Author")) {
            Author = string(json["Author"]);
        } else {
            Author = "Unknown Author";
        }
        
        // Always include primary uploader in Authors list
        Authors.InsertLast(Author);

        if (json.HasKey("Authors") && json["Authors"].GetType() == Json::Type::Array) {
            for (uint i = 0; i < json["Authors"].Length; i++) {
                Json::Value@ a = json["Authors"][i];
                string aName = "";
                if (a.GetType() == Json::Type::Object) {
                    if (a.HasKey("User") && a["User"].HasKey("Name")) {
                        aName = string(a["User"]["Name"]);
                    } else if (a.HasKey("Name")) {
                        aName = string(a["Name"]);
                    }
                } else if (a.GetType() == Json::Type::String) {
                    aName = string(a);
                }
                
                aName = Text::StripFormatCodes(aName).Trim();
                if (aName != "" && Authors.Find(aName) < 0) Authors.InsertLast(aName);
            }
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
            else if (json.HasKey("DifficultyName"))
                DifficultyName = string(json["DifficultyName"]);
            else
                DifficultyName = "Unknown";
        } else {
            Difficulty = 0;
            DifficultyName = "Unknown";
        }

        AwardCount = json.HasKey("AwardCount") ? uint(json["AwardCount"]) : 0;
        DownloadCount = json.HasKey("DownloadCount") ? uint(json["DownloadCount"]) : 0;
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
                Json::Value@ t = json["Tags"][i];
                if (t.GetType() == Json::Type::Object && t.HasKey("Name"))
                    Tags.InsertLast(string(t["Name"]));
            }
        }

        UploadedAt = json.HasKey("UploadedAt") ? string(json["UploadedAt"]) : "";
        HasScreenshot = json.HasKey("HasThumbnail") ? bool(json["HasThumbnail"]) : TrackId > 0;

        // Calculate size warnings based on strict user-defined thresholds
        if (ServerSizeExceeded || EmbeddedItemsSize > 4000000 || DisplayCost > 12000) {
            SizeWarning = "\\$f00" + Icons::ExclamationTriangle; // RED (Critical)
        } else if (EmbeddedItemsSize > 1000000 || DisplayCost > 8000) {
            SizeWarning = "\\$fd0" + Icons::ExclamationTriangle; // YELLOW (Caution)
        } else {
            SizeWarning = ""; // GREEN (Safe)
        }
        
        MetadataOverrides::Intercept(@this);
    }

    string get_PrimarySurface() {
        for (uint i = 0; i < Tags.Length; i++) {
            if (TMX::ArrayContains(TMX::SURFACE_TAGS, Tags[i])) return Tags[i];
        }
        return "None";
    }

    Json::Value@ ToJson() {
        Json::Value@ json = Json::Object();
        json["MapId"] = TrackId;
        json["MapUid"] = Uid;
        json["Name"] = Name;
        json["Author"] = Author;
        json["Length"] = LengthSecs * 1000;
        json["Difficulty"] = Difficulty - 1;
        json["DifficultyName"] = DifficultyName;
        json["AwardCount"] = AwardCount;
        json["DownloadCount"] = DownloadCount;
        return json;
    }
}

class TmxSearchFilters {
    string MapName = "";
    string[] AuthorNames = {};
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
    int LimitFilter = 0; // 0=None, 1=Filter Red, 2=Filter Yellow+Red
    int CurrentPage = 1;
    bool PrimaryTagOnly = false;
    bool PrimarySurfaceOnly = false;
    string PrimaryTag = "";
    string PrimarySurface = "";
    uint ResultLimit = 25;
    uint DisplayCostLimit = 10000;
    uint ItemSizeLimit = 1000000;

    TmxSearchFilters() {}

    TmxSearchFilters(Json::Value@ json) {
        if (json.GetType() != Json::Type::Object) return;
        MapName = JsonGetString(json, "MapName");
        
        if (json.HasKey("Authors") && json["Authors"].GetType() == Json::Type::String) {
            string s = string(json["Authors"]);
            string[] parts = s.Split(",");
            for (uint j = 0; j < parts.Length; j++) {
                string p = parts[j].Trim();
                if (p != "") AuthorNames.InsertLast(p);
            }
        } else if (json.HasKey("AuthorNames")) {
            if (json["AuthorNames"].GetType() == Json::Type::Array) {
                for (uint i = 0; i < json["AuthorNames"].Length; i++) {
                    string s = string(json["AuthorNames"][i]);
                    if (s.Contains(",")) {
                        string[] parts = s.Split(",");
                        for (uint j = 0; j < parts.Length; j++) {
                            string p = parts[j].Trim();
                            if (p != "") AuthorNames.InsertLast(p);
                        }
                    } else if (s.Trim() != "") {
                        AuthorNames.InsertLast(s.Trim());
                    }
                }
            } else if (json["AuthorNames"].GetType() == Json::Type::String) {
                string s = string(json["AuthorNames"]);
                string[] parts = s.Split(",");
                for (uint j = 0; j < parts.Length; j++) {
                    string p = parts[j].Trim();
                    if (p != "") AuthorNames.InsertLast(p);
                }
            }
        } else if (json.HasKey("AuthorName")) {
            // Backward compatibility for single string key
            string old = JsonGetString(json, "AuthorName");
            if (old != "") {
                string[] parts = old.Split(",");
                for (uint j = 0; j < parts.Length; j++) {
                    string p = parts[j].Trim();
                    if (p != "") AuthorNames.InsertLast(p);
                }
            }
        }

        Vehicle = JsonGetInt(json, "Vehicle", -1);
        Difficulty = JsonGetInt(json, "Difficulty", -1);
        
        if (json.HasKey("Difficulties") && json["Difficulties"].GetType() == Json::Type::Array) {
            for (uint i = 0; i < json["Difficulties"].Length && i < Difficulties.Length; i++) {
                if (json["Difficulties"][i].GetType() == Json::Type::Boolean) {
                    Difficulties[i] = bool(json["Difficulties"][i]);
                } else if (json["Difficulties"][i].GetType() == Json::Type::String) {
                    string d = string(json["Difficulties"][i]);
                    for (uint j = 0; j < TMX::DIFFICULTY_NAMES.Length; j++) {
                        if (TMX::DIFFICULTY_NAMES[j] == d) { Difficulties[j] = true; break; }
                    }
                }
            }
        }

        if (json.HasKey("IncludeTags") && json["IncludeTags"].GetType() == Json::Type::Array) {
            for (uint i = 0; i < json["IncludeTags"].Length; i++) IncludeTags.InsertLast(string(json["IncludeTags"][i]));
        }
        if (json.HasKey("ExcludeTags") && json["ExcludeTags"].GetType() == Json::Type::Array) {
            for (uint i = 0; i < json["ExcludeTags"].Length; i++) ExcludeTags.InsertLast(string(json["ExcludeTags"][i]));
        }

        if (json.HasKey("AuthorTimeRange")) {
            TimeFromMs = JsonGetUint(json["AuthorTimeRange"], "Min");
            TimeToMs = JsonGetUint(json["AuthorTimeRange"], "Max");
        } else {
            TimeFromMs = JsonGetUint(json, "TimeFromMs");
            TimeToMs = JsonGetUint(json, "TimeToMs");
        }

        if (json.HasKey("UploadDateRange")) {
            UploadedFrom = JsonGetString(json["UploadDateRange"], "From");
            UploadedTo = JsonGetString(json["UploadDateRange"], "To");
        } else {
            UploadedFrom = JsonGetString(json, "UploadedFrom");
            UploadedTo = JsonGetString(json, "UploadedTo");
        }

        SortPrimary = -1;
        if (json.HasKey("SortPrimary")) {
            if (json["SortPrimary"].GetType() == Json::Type::Number) {
                SortPrimary = int(json["SortPrimary"]);
            } else if (json["SortPrimary"].GetType() == Json::Type::String) {
                string sp = string(json["SortPrimary"]);
                for (uint i = 0; i < TMX::SORT_NAMES.Length; i++) {
                    if (TMX::SORT_NAMES[i] == sp) { SortPrimary = i; break; }
                }
            }
        } else if (json.HasKey("PrimarySort")) {
            string ps = JsonGetString(json, "PrimarySort");
            for (uint i = 0; i < TMX::SORT_NAMES.Length; i++) {
                if (TMX::SORT_NAMES[i] == ps) { SortPrimary = i; break; }
            }
        }

        SortSecondary = -1;
        if (json.HasKey("SortSecondary")) {
            if (json["SortSecondary"].GetType() == Json::Type::Number) {
                SortSecondary = int(json["SortSecondary"]);
            } else if (json["SortSecondary"].GetType() == Json::Type::String) {
                string ss = string(json["SortSecondary"]);
                for (uint i = 0; i < TMX::SORT_NAMES.Length; i++) {
                    if (TMX::SORT_NAMES[i] == ss) { SortSecondary = i; break; }
                }
            }
        } else if (json.HasKey("SecondarySort")) {
            string ss = JsonGetString(json, "SecondarySort");
            for (uint i = 0; i < TMX::SORT_NAMES.Length; i++) {
                if (TMX::SORT_NAMES[i] == ss) { SortSecondary = i; break; }
            }
        }

        InTOTD = JsonGetInt(json, "InTOTD", -1);
        InCollection = JsonGetInt(json, "InCollection", -1);
        HideOversized = JsonGetBool(json, "HideOversized");
        PrimaryTagOnly = JsonGetBool(json, "PrimaryTagOnly");
        PrimaryTag = JsonGetString(json, "PrimaryTag");
        if (PrimaryTag != "") PrimaryTagOnly = true;

        PrimarySurfaceOnly = JsonGetBool(json, "PrimarySurfaceOnly");
        PrimarySurface = JsonGetString(json, "PrimarySurface");
        if (PrimarySurface != "") PrimarySurfaceOnly = true;

        ResultLimit = JsonGetUint(json, "MapLimit", 25);
        if (ResultLimit == 25) ResultLimit = JsonGetUint(json, "ResultLimit", 25);
        
        if (json.HasKey("RoomGuardrails")) {
            DisplayCostLimit = JsonGetUint(json["RoomGuardrails"], "DisplayCost", 10000);
            ItemSizeLimit = JsonGetUint(json["RoomGuardrails"], "ItemSize", 1000000);
        } else {
            DisplayCostLimit = JsonGetUint(json, "DisplayCostLimit", 10000);
            ItemSizeLimit = JsonGetUint(json, "ItemSizeLimit", 1000000);
        }
        
        LimitFilter = JsonGetInt(json, "LimitFilter", 0);
        CurrentPage = JsonGetInt(json, "CurrentPage", 1);

        hFrom = (TimeFromMs / 3600000);
        mFrom = (TimeFromMs % 3600000) / 60000;
        sFrom = (TimeFromMs % 60000) / 1000;
        hTo = (TimeToMs / 3600000);
        mTo = (TimeToMs % 3600000) / 60000;
        sTo = (TimeToMs % 60000) / 1000;
    }

    Json::Value@ ToExportJson() {
        Json::Value@ json = Json::Object();
        if (MapName != "") json["MapName"] = MapName;
        if (AuthorNames.Length > 0) json["Authors"] = string::Join(AuthorNames, ", ");
        if (ResultLimit != 25) json["MapLimit"] = int(ResultLimit);

        Json::Value@ diffs = Json::Array();
        for (uint i = 0; i < Difficulties.Length; i++) {
            if (Difficulties[i]) diffs.Add(TMX::DIFFICULTY_NAMES[i]);
        }
        if (diffs.Length > 0) json["Difficulties"] = diffs;

        if (IncludeTags.Length > 0) {
            Json::Value@ arr = Json::Array();
            for (uint i = 0; i < IncludeTags.Length; i++) arr.Add(IncludeTags[i]);
            json["IncludeTags"] = arr;
        }
        if (ExcludeTags.Length > 0) {
            Json::Value@ arr = Json::Array();
            for (uint i = 0; i < ExcludeTags.Length; i++) arr.Add(ExcludeTags[i]);
            json["ExcludeTags"] = arr;
        }

        if (SortPrimary >= 0 && SortPrimary < int(TMX::SORT_NAMES.Length)) json["PrimarySort"] = TMX::SORT_NAMES[SortPrimary];
        if (SortSecondary >= 0 && SortSecondary < int(TMX::SORT_NAMES.Length)) json["SecondarySort"] = TMX::SORT_NAMES[SortSecondary];

        if (TimeFromMs > 0 || TimeToMs > 0) {
            Json::Value@ range = Json::Object();
            range["Min"] = int(TimeFromMs);
            range["Max"] = int(TimeToMs);
            json["AuthorTimeRange"] = range;
        }

        if (UploadedFrom != "" || UploadedTo != "") {
            Json::Value@ range = Json::Object();
            range["From"] = UploadedFrom;
            range["To"] = UploadedTo;
            json["UploadDateRange"] = range;
        }

        if (InTOTD != -1) json["InTOTD"] = InTOTD;
        if (InCollection != -1) json["InCollection"] = InCollection;
        if (PrimaryTagOnly) {
            json["PrimaryTagOnly"] = true;
            if (PrimaryTag != "") json["PrimaryTag"] = PrimaryTag;
        }
        if (PrimarySurfaceOnly) {
            json["PrimarySurfaceOnly"] = true;
            if (PrimarySurface != "") json["PrimarySurface"] = PrimarySurface;
        }

        if (DisplayCostLimit != 10000 || ItemSizeLimit != 1000000) {
            Json::Value@ g = Json::Object();
            g["DisplayCost"] = int(DisplayCostLimit);
            g["ItemSize"] = int(ItemSizeLimit);
            json["RoomGuardrails"] = g;
        }

        return json;
    }

    void SyncTimeMs() {
        TimeFromMs = (hFrom * 3600000) + (mFrom * 60000) + (sFrom * 1000);
        TimeToMs = (hTo * 3600000) + (mTo * 60000) + (sTo * 1000);
    }

    TmxSearchFilters@ Clone() {
        SyncTimeMs();
        TmxSearchFilters@ other = TmxSearchFilters();
        other.MapName = MapName;
        for (uint i = 0; i < AuthorNames.Length; i++) other.AuthorNames.InsertLast(AuthorNames[i]);
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
        other.LimitFilter = LimitFilter;
        other.ResultLimit = ResultLimit;
        other.DisplayCostLimit = DisplayCostLimit;
        other.ItemSizeLimit = ItemSizeLimit;
        other.CurrentPage = CurrentPage;
        for (uint i = 0; i < IncludeTags.Length; i++) other.IncludeTags.InsertLast(IncludeTags[i]);
        for (uint i = 0; i < ExcludeTags.Length; i++) other.ExcludeTags.InsertLast(ExcludeTags[i]);
        return other;
    }

    Json::Value@ ToJson() {
        SyncTimeMs();
        TmxSearchFilters@ def = TmxSearchFilters();
        Json::Value@ json = Json::Object();
        
        if (MapName != def.MapName) json["MapName"] = MapName;
        
        if (AuthorNames.Length > 0) {
            Json::Value@ authors = Json::Array();
            for (uint i = 0; i < AuthorNames.Length; i++) authors.Add(AuthorNames[i]);
            json["AuthorNames"] = authors;
        }

        if (Vehicle != def.Vehicle) json["Vehicle"] = Vehicle;
        if (Difficulty != def.Difficulty) json["Difficulty"] = Difficulty;
        
        bool diffsChanged = false;
        for (uint i = 0; i < Difficulties.Length; i++) {
            if (Difficulties[i] != def.Difficulties[i]) { diffsChanged = true; break; }
        }
        if (diffsChanged) {
            Json::Value@ diffs = Json::Array();
            for (uint i = 0; i < Difficulties.Length; i++) diffs.Add(Difficulties[i]);
            json["Difficulties"] = diffs;
        }

        if (TimeFromMs != def.TimeFromMs) json["TimeFromMs"] = TimeFromMs;
        if (TimeToMs != def.TimeToMs) json["TimeToMs"] = TimeToMs;
        if (UploadedFrom != def.UploadedFrom) json["UploadedFrom"] = UploadedFrom;
        if (UploadedTo != def.UploadedTo) json["UploadedTo"] = UploadedTo;
        
        if (SortPrimary != def.SortPrimary) {
            if (SortPrimary >= 0 && uint(SortPrimary) < TMX::SORT_NAMES.Length) {
                json["SortPrimary"] = TMX::SORT_NAMES[SortPrimary];
            } else {
                json["SortPrimary"] = -1;
            }
        }

        if (SortSecondary != def.SortSecondary) {
            if (SortSecondary >= 0 && uint(SortSecondary) < TMX::SORT_NAMES.Length) {
                json["SortSecondary"] = TMX::SORT_NAMES[SortSecondary];
            } else {
                json["SortSecondary"] = -1;
            }
        }

        if (InTOTD != def.InTOTD) json["InTOTD"] = InTOTD;
        if (InCollection != def.InCollection) json["InCollection"] = InCollection;
        if (InOnlineRecords != def.InOnlineRecords) json["InOnlineRecords"] = InOnlineRecords;
        if (HideOversized != def.HideOversized) json["HideOversized"] = HideOversized;
        if (PrimaryTagOnly != def.PrimaryTagOnly) json["PrimaryTagOnly"] = PrimaryTagOnly;
        if (PrimarySurfaceOnly != def.PrimarySurfaceOnly) json["PrimarySurfaceOnly"] = PrimarySurfaceOnly;
        if (LimitFilter != def.LimitFilter) json["LimitFilter"] = LimitFilter;
        if (ResultLimit != def.ResultLimit) json["ResultLimit"] = ResultLimit;
        if (CurrentPage > 1) json["CurrentPage"] = CurrentPage;
        if (DisplayCostLimit != def.DisplayCostLimit) json["DisplayCostLimit"] = DisplayCostLimit;
        if (ItemSizeLimit != def.ItemSizeLimit) json["ItemSizeLimit"] = ItemSizeLimit;
        
        if (IncludeTags.Length > 0) {
            Json::Value@ inc = Json::Array();
            for (uint i = 0; i < IncludeTags.Length; i++) inc.Add(IncludeTags[i]);
            json["IncludeTags"] = inc;
        }
        
        if (ExcludeTags.Length > 0) {
            Json::Value@ exc = Json::Array();
            for (uint i = 0; i < ExcludeTags.Length; i++) exc.Add(ExcludeTags[i]);
            json["ExcludeTags"] = exc;
        }
        
        return json;
    }

    string GetDifference(TmxSearchFilters@ other) {
        if (other is null) return "Other filter is null";
        string diff = "";
        if (MapName != other.MapName) diff += "MapName: '" + MapName + "' != '" + other.MapName + "', ";
        if (AuthorNames.Length != other.AuthorNames.Length) {
            diff += "AuthorCount: " + AuthorNames.Length + " != " + other.AuthorNames.Length + ", ";
        } else {
            for (uint i = 0; i < AuthorNames.Length; i++) {
                if (AuthorNames[i] != other.AuthorNames[i]) {
                    diff += "AuthorNames mismatch, ";
                    break;
                }
            }
        }
        if (Vehicle != other.Vehicle) diff += "Vehicle: " + Vehicle + " != " + other.Vehicle + ", ";
        if (Difficulty != other.Difficulty) diff += "Difficulty: " + Difficulty + " != " + other.Difficulty + ", ";
        if (TimeFromMs != other.TimeFromMs) diff += "TimeFrom: " + TimeFromMs + " != " + other.TimeFromMs + ", ";
        if (TimeToMs != other.TimeToMs) diff += "TimeTo: " + TimeToMs + " != " + other.TimeToMs + ", ";
        if (UploadedFrom != other.UploadedFrom) diff += "UploadedFrom: " + UploadedFrom + " != " + other.UploadedFrom + ", ";
        if (UploadedTo != other.UploadedTo) diff += "UploadedTo: " + UploadedTo + " != " + other.UploadedTo + ", ";
        if (SortPrimary != other.SortPrimary) {
            string p1 = (SortPrimary >= 0 && uint(SortPrimary) < TMX::SORT_NAMES.Length) ? TMX::SORT_NAMES[uint(SortPrimary)] : "Unknown";
            string p2 = (other.SortPrimary >= 0 && uint(other.SortPrimary) < TMX::SORT_NAMES.Length) ? TMX::SORT_NAMES[uint(other.SortPrimary)] : "Unknown";
            diff += "SortPrimary: " + p1 + " != " + p2 + ", ";
        }
        if (InTOTD != other.InTOTD) diff += "InTOTD: " + InTOTD + " != " + other.InTOTD + ", ";
        if (InCollection != other.InCollection) diff += "InCollection: " + InCollection + " != " + other.InCollection + ", ";
        
        if (IncludeTags.Length != other.IncludeTags.Length) {
            diff += "IncludeTags count mismatch, ";
        } else {
            for (uint i = 0; i < IncludeTags.Length; i++) {
                if (IncludeTags[i] != other.IncludeTags[i]) {
                    diff += "IncludeTags values mismatch, ";
                    break;
                }
            }
        }
        
        if (diff.EndsWith(", ")) diff = diff.SubStr(0, diff.Length - 2);
        return diff;
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

    // Source Selection (0 = Search filters, 1 = TMX/Custom List)
    int SourceType = 0;
    string ListId = "";
    string ListType = ""; // "favorites", "playlater", "custom", "set"

    Subscription() { @Filters = TmxSearchFilters(); }
    Subscription(Json::Value@ json) {
        if (json.GetType() != Json::Type::Object) return;
        ClubId = JsonGetUint(json, "ClubId");
        ActivityId = JsonGetUint(json, "ActivityId");
        ActivityName = JsonGetString(json, "ActivityName");
        @Filters = json.HasKey("Filters") ? TmxSearchFilters(json["Filters"]) : TmxSearchFilters();
        MapLimit = JsonGetUint(json, "MapLimit", 25);
        LastRun = JsonGetUint(json, "LastRun");
        
        SourceType = JsonGetInt(json, "SourceType", 0);
        ListId = JsonGetString(json, "ListId");
        ListType = JsonGetString(json, "ListType");

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
        
        json["SourceType"] = SourceType;
        json["ListId"] = ListId;
        json["ListType"] = ListType;
        
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
        "Awards Most", "Awards Least", "Uploaded Oldest", 
        "Downloads Most", "Downloads Least",
        "Uploaded Newest", "Difficulty Easiest",
        "Difficulty Hardest", "Name A-Z", "Name Z-A"
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
        FolderNode@ node = FolderNode(subName);
        Subfolders.InsertLast(node);
        return node;
    }

    void Sort() {
        // Sort subfolders by name
        for (uint i = 0; i < Subfolders.Length; i++) {
            for (uint j = i + 1; j < Subfolders.Length; j++) {
                if (Subfolders[i].Name > Subfolders[j].Name) {
                    FolderNode@ temp = Subfolders[i]; @Subfolders[i] = Subfolders[j]; @Subfolders[j] = temp;
                }
            }
            Subfolders[i].Sort();
        }
        // Sort maps by name
        for (uint i = 0; i < Maps.Length; i++) {
            for (uint j = i + 1; j < Maps.Length; j++) {
                if (Maps[i].Name > Maps[j].Name) {
                    LocalMap@ temp = Maps[i]; @Maps[i] = Maps[j]; @Maps[j] = temp;
                }
            }
        }
    }
}
