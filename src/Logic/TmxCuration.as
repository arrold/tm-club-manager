// Logic/TmxCuration.as - Sequential TMX fetching and curation helpers

/*
 * Sequential TMX Fetching:
 * TMX API (V1) has stability issues with large offsets. This function implements 
 * a "cursor-based" sequential scan using TrackId (afterId) to reliably page through 
 * results. It also handles client-side filtering for attributes TMX cannot 
 * natively filter (e.g., precise time ranges or multi-tag combinations).
 */
TmxMap[] FetchMapsSequential(TmxSearchFilters@ f, uint limit, bool applyOffset = true) {
    TmxMap[] allResults;
    uint skipCount = (applyOffset && f.CurrentPage > 1) ? (f.CurrentPage - 1) * limit : 0;
    uint totalNeeded = skipCount + limit;
    
    // Optimization: if no client-side only filters are active, we can jump straight to the offset
    bool hasClientFilters = f.MapName != "" || f.AuthorName != "" || f.TimeFromMs > 0 || f.TimeToMs > 0;
    uint offset = hasClientFilters ? 0 : skipCount;
    uint lastId = 0;
    
    uint batchSize = Math::Min(Math::Max(limit, uint(25)), uint(50)); // Smaller batches for stability
    while (allResults.Length < totalNeeded) {
        auto json = TMX::SearchMaps(f, batchSize, offset, lastId);
        int fetchedCount = 0;
        TmxMap[] batch = FilterTmxResults(json, f, batchSize, fetchedCount);

        for (uint i = 0; i < batch.Length; i++) {
            if (allResults.Length < totalNeeded) {
                allResults.InsertLast(batch[i]);
            }
        }

        if (allResults.Length >= totalNeeded) break;
        if (fetchedCount < int(batchSize)) break; // No more results matching filters available

        // Advance the cursor: use TrackId for modern 'after' pagination,
        // fallback to offset if we don't have results but haven't reached end
        if (batch.Length > 0) {
            lastId = batch[batch.Length - 1].TrackId;
            offset = 0;
        } else {
            offset += fetchedCount;
        }
        
        yield(); // Let the UI breathe
    }
    
    // Slice only the requested page
    TmxMap[] pageResults;
    if (allResults.Length > skipCount) {
        for (uint i = skipCount; i < allResults.Length; i++) {
            pageResults.InsertLast(allResults[i]);
        }
    }
    
    // trace("[TMX] Scan complete. Found " + allResults.Length + " maps total. Returning page offset " + skipCount);
    return pageResults;
}

/*
 * Client-Side Result Filtering:
 * Applies secondary validation logic to TMX search results. 
 * This includes multi-difficulty matching, primary surface/tag isolation, 
 * and author time range validation. 
 */
TmxMap[] FilterTmxResults(Json::Value@ json, TmxSearchFilters@ f, uint requestedCount, int&out fetchedCount) {
    TmxMap[] filtered;
    fetchedCount = 0;

    if (json is null) return filtered;
    
    Json::Value@ results = json;
    if (json.GetType() == Json::Type::Object && json.HasKey("Results") && json["Results"].GetType() == Json::Type::Array) {
        @results = json["Results"];
    }

    if (results.GetType() != Json::Type::Array) return filtered;

    fetchedCount = results.Length;
    for (uint i = 0; i < results.Length; i++) {
        TmxMap m(results[i]);
        if (m.Uid == "") continue;

        // Apply secondary logic filters
        if (f.MapName != "" && !m.Name.ToLower().Contains(f.MapName.ToLower())) continue;
        if (f.AuthorName != "" && !m.Author.ToLower().Contains(f.AuthorName.ToLower())) continue;
        
        // Difficulty filter (Normalised 1-6)
        if (m.Difficulty > 0 && m.Difficulty <= 6) {
            bool diffPassed = false;
            bool anyDiffSet = false;
            for (uint d = 0; d < f.Difficulties.Length; d++) {
                if (f.Difficulties[d]) {
                    anyDiffSet = true;
                    if (m.Difficulty == int(d + 1)) { diffPassed = true; break; }
                }
            }
            if (anyDiffSet && !diffPassed) continue;
        }

        // Optional: Primary Tag (First tag out of all tags)
        if (f.PrimaryTagOnly && f.IncludeTags.Length > 0) {
            if (m.Tags.Length == 0) continue;
            bool found = false;
            for (uint j = 0; j < f.IncludeTags.Length; j++) {
                if (m.Tags[0] == f.IncludeTags[j]) { found = true; break; }
            }
            if (!found) continue;
        }
        
        // Optional: Primary Surface (First tag that is a surface)
        if (f.PrimarySurfaceOnly && f.IncludeTags.Length > 0) {
            string firstSurface = "";
            for (uint j = 0; j < m.Tags.Length; j++) {
                if (TMX::ArrayContains(TMX::SURFACE_TAGS, m.Tags[j])) {
                    firstSurface = m.Tags[j];
                    break;
                }
            }
            if (firstSurface == "") continue;
            bool found = false;
            for (uint j = 0; j < f.IncludeTags.Length; j++) {
                if (firstSurface == f.IncludeTags[j]) { found = true; break; }
            }
            if (!found) continue;
        }

        // Author Time Range Filter (Client-side safeguard)
        uint lengthMs = m.LengthSecs * 1000;
        if (f.TimeFromMs > 0 && lengthMs < f.TimeFromMs) continue;
        if (f.TimeToMs > 0 && lengthMs > f.TimeToMs) continue;

        filtered.InsertLast(m);
        if (filtered.Length >= requestedCount) break;
    }

    return filtered;
}

void DoTmxSearch() {
    auto f = State::tmxFilters;
    State::searchInProgress = true;
    
    if (f.CurrentPage < 1) f.CurrentPage = 1;

    // Fetch exactly what the UI limit asks for
    State::tmxSearchResults = FetchMapsSequential(f, f.ResultLimit, true);
    
    State::tmxSelected.RemoveRange(0, State::tmxSelected.Length);
    for (uint i = 0; i < State::tmxSearchResults.Length; i++) State::tmxSelected.InsertLast(false);
    
    State::searchInProgress = false;
}

void DoBatchAdd() {
    if (State::TargetActivity is null) return;
    
    string[] toAdd;
    for (uint i = 0; i < State::tmxSearchResults.Length; i++) {
        if (State::tmxSelected[i]) {
            string uid = State::tmxSearchResults[i].Uid;
            if (!Nadeo::IsMapUploaded(uid)) {
                Nadeo::RegisterMap(uid);
                yield();
            }
            toAdd.InsertLast(uid);
        }
    }

    if (toAdd.Length == 0) return;

    // Check Limits
    uint addedCount = toAdd.Length;
    if (State::TargetActivity.Type == "campaign" && toAdd.Length > 25) {
        UI::ShowNotification("Capacity Exceeded", "Adding these maps would exceed the Nadeo Campaign limit of 25. Please remove some maps first or select fewer maps.", vec4(0.8, 0.2, 0.2, 1), 6000);
        return;
    } else if (State::TargetActivity.Type == "room" && toAdd.Length > 100) {
        UI::ShowNotification("Capacity Exceeded", "Adding these maps would exceed the Room limit of 100. Please remove some maps first or select fewer maps.", vec4(0.8, 0.2, 0.2, 1), 6000);
        return;
    }
    
    Notify("Appending " + addedCount + " maps to " + State::TargetActivity.Name + "...");
    ApplyBatchToActivity(State::TargetActivity, toAdd);
    startnew(RefreshActivities);
}

void ApplyBatchToActivity(Activity@ a, string[]@ uids) {
    if (a is null || State::SelectedClub is null) return;
    
    string[] finalUids;
    for (uint i = 0; i < uids.Length; i++) finalUids.InsertLast(uids[i]);

    if (a.Type == "campaign") {
        if (finalUids.Length > 25) {
            finalUids.RemoveRange(25, finalUids.Length - 25);
            Notify("Nadeo limits Campaigns to 25 maps! List truncated.");
        }
        auto current = API::GetCampaignMaps(State::SelectedClub.Id, a.CampaignId);
        API::SetCampaignMaps(State::SelectedClub.Id, a.CampaignId, a.Name, finalUids, current);
    } else if (a.Type == "room") {
        if (finalUids.Length > 100) {
            finalUids.RemoveRange(100, finalUids.Length - 100);
            Notify("Nadeo limits Rooms to 100 maps! List truncated.");
        }
        API::SetRoomMaps(State::SelectedClub.Id, a.RoomId, finalUids);
    }
}
