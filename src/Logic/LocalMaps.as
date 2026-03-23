CGameCtnChallengeInfo@ TryGetMapInfo(const string &in fidsPath) {
    auto fid = Fids::GetUser(fidsPath);
    if (fid is null && fidsPath.StartsWith("Maps/")) @fid = Fids::GetUser(fidsPath.SubStr(5));
    if (fid is null) return null;

    auto nod = fid.Nod;
    if (nod is null) {
        yield();
        @nod = fid.Nod;
    }
    if (nod is null) return null;
    return cast<CGameCtnChallengeInfo>(nod);
}

// #region agent log
void DebugNDJSON(const string &in runId, const string &in hypothesisId, const string &in location, const string &in message, const string &in dataJson) {
    IO::File logFile;
    logFile.Open("c:/Users/simon/repos/tm/plugins/tm-club-manager/debug-d1d6a7.log", IO::FileMode::Append);
    uint64 ts = Time::Now;
    string line = "{\"sessionId\":\"d1d6a7\",\"runId\":\"" + runId +
        "\",\"hypothesisId\":\"" + hypothesisId +
        "\",\"location\":\"" + location +
        "\",\"message\":\"" + message +
        "\",\"data\":" + dataJson +
        ",\"timestamp\":" + tostring(ts) + "}";
    logFile.WriteLine(line);
    logFile.Close();
}
// #endregion

string ExtractLeafPath(const string &in fullPath) {
    // Handle mixed separators by splitting twice.
    array<string> partsBackslash = fullPath.Split("\\");
    string last = partsBackslash.Length > 0 ? partsBackslash[partsBackslash.Length - 1] : fullPath;
    array<string> partsSlash = last.Split("/");
    return partsSlash.Length > 0 ? partsSlash[partsSlash.Length - 1] : last;
}

string GetDisplayNameFromFilename(const string &in filename) {
    // Best-effort: show just the leaf name without TM extensions.
    string n = ExtractLeafPath(filename);
    string nLower = n.ToLower();
    if (nLower.EndsWith(".map.gbx")) n = n.SubStr(0, n.Length - uint(".map.gbx".Length));
    else if (nLower.EndsWith(".gbx")) n = n.SubStr(0, n.Length - uint(".gbx".Length));
    else {
        // Remove extension (up to first '.').
        array<string> parts = n.Split(".");
        if (parts.Length > 1) n = parts[0];
    }

    n = n.Trim();
    if (n == "") return "Known Map";
    return n;
}

void RefreshLocalMaps() {
    if (State::refreshingLocalMaps) return;
    State::refreshingLocalMaps = true;
    State::LocalMaps.RemoveRange(0, State::LocalMaps.Length);

    // Truncate debug log at start of refresh
    IO::File logTruncate;
    logTruncate.Open("c:/Users/simon/repos/tm/plugins/tm-club-manager/debug-d1d6a7.log", IO::FileMode::Write);
    logTruncate.Close();

    string mapsDir = IO::FromUserGameFolder("Maps/");
    string mapsDirNorm = mapsDir.Replace("\\", "/");
    if (!mapsDirNorm.EndsWith("/")) mapsDirNorm += "/";
    
    trace("[Local] Indexing maps in directory: " + mapsDir);
    
    array<string> files = IO::IndexFolder(mapsDir, true);
    trace("[Local] IO::IndexFolder found " + files.Length + " files.");
    
    uint mapGbxCount = 0;
    uint fidsValidated = 0;
    uint manualParsed = 0;
    uint manualValidated = 0;
    for (uint i = 0; i < files.Length; i++) {
        string absPath = files[i];
        string fileNorm = absPath.Replace("\\", "/");
        
        string relPath = fileNorm;
        if (relPath.StartsWith(mapsDirNorm)) {
            relPath = relPath.SubStr(mapsDirNorm.Length);
        }

        string relLower = relPath.ToLower();
        if (relLower.Contains("/autosaves/") || relLower.StartsWith("autosaves/")) {
            continue;
        }

        if (relLower.EndsWith(".map.gbx")) {
            mapGbxCount++;
            
            // Primary Strategy: Manual Gbx Parsing (Fast & Reliable)
            auto header = Gbx::ReadHeader(absPath);
            if (header !is null && header.Uid != "") {
                if (mapGbxCount < 5) trace("[Local] Parsed: " + relPath + " (UID: " + header.Uid + ", Validated: " + header.IsValidated + ")");
                LocalMap@ m = LocalMap();
                m.Uid = header.Uid;
                m.Filename = "Maps/" + relPath; // Clean relative path
                m.Name = header.Name != "" ? header.Name : GetDisplayNameFromFilename(absPath);
                m.IsPlayable = true;
                m.IsValidated = header.IsValidated; // Use editor validation
                
                manualParsed++;
                if (m.IsValidated) manualValidated++;
                State::LocalMaps.InsertLast(m);
                if (State::LocalMaps.Length == 1) trace("[Local] Indexed first map (Manual Gbx): " + m.Name);
            } else {
                // Secondary Strategy: Fids as Fallback
                string fidsPath = "Maps/" + relPath;
                auto info = TryGetMapInfo(fidsPath);
                if (info !is null) {
                    LocalMap@ m = LocalMap(info);
                    m.Filename = fidsPath;
                    m.Name = GetDisplayNameFromFilename(m.Filename);
                    if (m.IsValidated) fidsValidated++;
                    State::LocalMaps.InsertLast(m);
                    if (State::LocalMaps.Length == 1) trace("[Local] Indexed first map (Fids): " + info.Name);
                } else {
                    // Trace why we skipped this .Map.Gbx
                    if (mapGbxCount < 10) trace("[Local] Skipped non-parsed map: " + relPath);
                }
            }
        }
        if (i % 100 == 0) yield();
    }
    
    if (State::LocalMaps.Length == 0 && mapGbxCount > 0) {
        warn("[Local] Found " + mapGbxCount + " .Map.Gbx files but failed to retrieve MapInfo for any.");
    }

    // Sort by Filename
    for (uint i = 0; i < State::LocalMaps.Length; i++) {
        for (uint j = i + 1; j < State::LocalMaps.Length; j++) {
            if (State::LocalMaps[i].Filename > State::LocalMaps[j].Filename) {
                auto temp = State::LocalMaps[i];
                @State::LocalMaps[i] = State::LocalMaps[j];
                @State::LocalMaps[j] = temp;
            }
        }
    }

    print("[Local] Indexed " + State::LocalMaps.Length + " maps.");

    // Final "validated" pass: only show maps that are already uploaded/registered on Nadeo.
    uint serverValidated = 0;
    string[] checkedUids;
    bool[] checkedUploaded;
    for (uint i = 0; i < State::LocalMaps.Length; i++) {
        auto@ m = State::LocalMaps[i];
        if (m is null || m.Uid == "") {
            if (m !is null) m.IsValidated = false;
            continue;
        }

        int cachedIdx = checkedUids.Find(m.Uid);
        bool uploaded = false;
        if (cachedIdx >= 0) {
            uploaded = checkedUploaded[uint(cachedIdx)];
        } else {
            uploaded = Nadeo::IsMapUploaded(m.Uid);
            checkedUids.InsertLast(m.Uid);
            checkedUploaded.InsertLast(uploaded);
        }

        m.IsUploaded = uploaded;
        if (uploaded) serverValidated++;

        if (i % 10 == 0) yield();
    }

    // #region agent log
    DebugNDJSON("post-fix-3", "LocalMapsValidation", "LocalMaps.as:RefreshLocalMaps", "Local map validation counters",
        "{\"total\":" + tostring(State::LocalMaps.Length) +
        ",\"fidsValidated\":" + tostring(fidsValidated) +
        ",\"manualParsed\":" + tostring(manualParsed) +
        ",\"manualValidated\":" + tostring(manualValidated) +
        ",\"serverValidated\":" + tostring(serverValidated) +
        "}");
    // #endregion
    State::refreshingLocalMaps = false;
}

void WalkFidsFolder(const string &in folderPath) {
    auto fid = Fids::GetUser(folderPath);
    if (fid is null) return;
    auto nod = fid.Nod;
    yield();
}

void DoAddLocalMap(ref@ r) {
    LocalMap@ m = cast<LocalMap>(r);
    if (m is null || State::SelectedClub is null || State::TargetActivity is null) return;

    if (!Nadeo::IsMapUploaded(m.Uid)) {
        UI::ShowNotification("Club Manager", "Map '" + m.Name + "' is not registered. Registering now...", vec4(1, .8, .1, .8), 5000);
        if (!Nadeo::RegisterMap(m.Uid)) {
            UI::ShowNotification("Club Manager", "Failed to register map: " + m.Name, vec4(1, .2, .2, .8), 10000);
            return;
        }
    }

    string[] uids = { m.Uid };
    if (State::TargetActivity.Type == "campaign") {
        API::SetCampaignMaps(State::SelectedClub.Id, State::TargetActivity.Id, State::TargetActivity.Name, uids);
    } else if (State::TargetActivity.Type == "room") {
        API::SetRoomMaps(State::SelectedClub.Id, State::TargetActivity.Id, uids);
    }
    
    UI::ShowNotification("Club Manager", "Added '" + m.Name + "' to " + State::TargetActivity.Name);
    startnew(RefreshActivities);
}

