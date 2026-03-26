CGameCtnChallengeInfo@ TryGetMapInfo(const string &in fidsPath) {
    CSystemFidFile@ fid = Fids::GetUser(fidsPath);
    if (fid is null && fidsPath.StartsWith("Maps/")) @fid = Fids::GetUser(fidsPath.SubStr(5));
    if (fid is null) return null;

    if (fid is null) return null;
    return cast<CGameCtnChallengeInfo>(fid.Nod);
}



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



    string mapsDir = IO::FromUserGameFolder("Maps/");
    string mapsDirNorm = mapsDir.Replace("\\", "/");
    if (!mapsDirNorm.EndsWith("/")) mapsDirNorm += "/";
    
    // trace("[Local] Indexing maps in directory: " + mapsDir);
    
    array<string> files = IO::IndexFolder(mapsDir, true);
    // trace("[Local] IO::IndexFolder found " + files.Length + " files.");
    
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
            Gbx::MapHeader@ header = Gbx::ReadHeader(absPath);
            if (header !is null && header.Uid != "") {
                LocalMap@ m = LocalMap();
                m.Uid = header.Uid;
                m.Filename = "Maps/" + relPath; // Clean relative path
                m.Name = header.Name != "" ? header.Name : GetDisplayNameFromFilename(absPath);
                m.IsPlayable = true;
                m.IsValidated = header.IsValidated; // Use editor validation
                
                manualParsed++;
                if (m.IsValidated) manualValidated++;
                State::LocalMaps.InsertLast(m);
            } else {
                // Secondary Strategy: Fids as Fallback
                string fidsPath = "Maps/" + relPath;
                CGameCtnChallengeInfo@ info = TryGetMapInfo(fidsPath);
                if (info !is null) {
                    LocalMap@ m = LocalMap(info);
                    m.Filename = fidsPath;
                    m.Name = GetDisplayNameFromFilename(m.Filename);
                    if (m.IsValidated) fidsValidated++;
                    State::LocalMaps.InsertLast(m);
                }
            }
        }
        if (i % 10 == 0) yield();
    }
    
    if (State::LocalMaps.Length == 0 && mapGbxCount > 0) {
        warn("[Local] Found " + mapGbxCount + " .Map.Gbx files but failed to retrieve MapInfo for any.");
    }

    // Sort by Filename
    for (uint i = 0; i < State::LocalMaps.Length; i++) {
        for (uint j = i + 1; j < State::LocalMaps.Length; j++) {
            if (State::LocalMaps[i].Filename > State::LocalMaps[j].Filename) {
                LocalMap@ temp = State::LocalMaps[i];
                @State::LocalMaps[i] = State::LocalMaps[j];
                @State::LocalMaps[j] = temp;
            }
        }
    }

    // print("[Local] Indexed " + State::LocalMaps.Length + " maps.");

    // Final "validated" pass: only show maps that are already uploaded/registered on Nadeo.
    uint serverValidated = 0;
    string[] checkedUids;
    bool[] checkedUploaded;
    for (uint i = 0; i < State::LocalMaps.Length; i++) {
        LocalMap@ m = State::LocalMaps[i];
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


    State::refreshingLocalMaps = false;
}

void WalkFidsFolder(const string &in folderPath) {
    CSystemFidFile@ fid = Fids::GetUser(folderPath);
    if (fid is null) return;
    CMwNod@ nod = fid.Nod;
    yield();
}

void DoAddLocalMap(ref@ r) {
    LocalMap@ m = cast<LocalMap>(r);
    if (m is null || State::SelectedClub is null || State::TargetActivity is null) return;

    if (!State::TargetActivity.MapsLoaded && !State::TargetActivity.LoadingMaps) {
        // trace("DoAddLocalMap: Loading existing maps for " + State::TargetActivity.Name + " first...");
        LoadActivityMaps(State::TargetActivity);
    }

    if (!Nadeo::IsMapUploaded(m.Uid)) {
        UI::ShowNotification("Club Manager", "Map '" + m.Name + "' is not registered. Registering now...", vec4(1, .8, .1, .8), 5000);
        if (!Nadeo::RegisterMap(m.Uid)) {
            UI::ShowNotification("Club Manager", "Failed to register map: " + m.Name, vec4(1, .2, .2, .8), 10000);
            return;
        }
        yield();
    }

    // trace("[LocalMaps] Immediate Add: Adding " + m.Uid + " to " + State::TargetActivity.Name);
    
    // 1. Prepare new UID list from current in-memory maps (buffered or not)
    string[] uids;
    for (uint i = 0; i < State::TargetActivity.Maps.Length; i++) {
        if (!State::TargetActivity.Maps[i].PendingDelete)
            uids.InsertLast(State::TargetActivity.Maps[i].Uid);
    }
    
    // Avoid duplicates if already in list
    if (uids.Find(m.Uid) < 0) uids.InsertLast(m.Uid);
    else {
        UI::ShowNotification("Club Manager", "Map already in activity: " + m.Name);
        return;
    }

    // 2. Commit to server (Skip if personal)
    if (State::TargetActivity.Id != 0xFFFFFFFF) {
        ApplyBatchToActivity(State::TargetActivity, uids);
        State::TargetActivity.HasMapChanges = false;
        UI::ShowNotification("Club Manager", "Successfully added '" + m.Name + "' to " + State::TargetActivity.Name, vec4(0, 1, 0, 1));
        startnew(LoadActivityMaps, State::TargetActivity);
    } else {
        UI::ShowNotification("Club Manager", "Map '" + m.Name + "' registered to Nadeo Personal Tracks.", vec4(0.2, 0.8, 0.2, 1));
        m.IsUploaded = true;
    }
}

void DoAddSelectedLocalMaps() {
    if (State::SelectedClub is null || State::TargetActivity is null) return;
    
    Activity@ a = State::TargetActivity;
    if (!a.MapsLoaded && !a.LoadingMaps) {
        // trace("DoAddSelectedLocalMaps: Loading existing maps first...");
        LoadActivityMaps(a);
    }

    string[] uids;
    for (uint i = 0; i < a.Maps.Length; i++) {
        if (!a.Maps[i].PendingDelete) uids.InsertLast(a.Maps[i].Uid);
    }

    uint count = 0;
    for (uint i = 0; i < State::LocalMaps.Length; i++) {
        LocalMap@ m = State::LocalMaps[i];
        if (m !is null && m.Selected) {
            if (!Nadeo::IsMapUploaded(m.Uid)) {
                if (!Nadeo::RegisterMap(m.Uid)) continue;
                yield(); // Research suggested delay after registration
            }
            if (uids.Find(m.Uid) < 0) {
                uids.InsertLast(m.Uid);
                count++;
            }
            m.Selected = false; // Reset
        }
    }
    
    if (count > 0) {
        if (a.Id != 0xFFFFFFFF) {
            // trace("[LocalMaps] Immediate Bulk Add: Committing " + count + " maps to " + a.Name);
            ApplyBatchToActivity(a, uids);
            a.HasMapChanges = false;
            UI::ShowNotification("Club Manager", "Successfully added " + count + " maps to " + a.Name, vec4(0, 1, 0, 1));
            startnew(LoadActivityMaps, a);
        } else {
             UI::ShowNotification("Club Manager", "Uploaded " + count + " maps to Nadeo Personal Tracks.", vec4(0.2, 0.8, 0.2, 1));
             startnew(RefreshLocalMaps);
        }
    }
}

