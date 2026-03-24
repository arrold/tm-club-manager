// Logic/TmxCuration.as - Sequential TMX fetching and curation helpers (Zertrov Style)

TmxMap[] FetchMapsSequential(TmxSearchFilters@ f, uint limit, bool applyOffset = true) {
    TmxMap[] allResults;
    uint offset = 0;
    
    // Subscriptions and Curation searches use 'CurrentPage' for the base skip.
    // TMX V1 uses 1-based paging internally but '&skip=N' for absolute offset.
    if (applyOffset && f.CurrentPage > 1) {
        offset = (f.CurrentPage - 1) * 25;
    }

    uint batchSize = 100; // Efficient batching
    while (allResults.Length < limit) {
        auto json = TMX::SearchMaps(f, batchSize, offset);
        int fetchedCount = 0;
        TmxMap[] batch = FilterTmxResults(json, f, batchSize, fetchedCount);

        for (uint i = 0; i < batch.Length; i++) {
            if (allResults.Length < limit) {
                allResults.InsertLast(batch[i]);
            }
        }

        if (allResults.Length >= limit) break;
        if (fetchedCount < int(batchSize)) break; // No more results matching filters available

        // Advance the skip pointer by exactly what TMX gave us
        offset += fetchedCount;
    }
    
    trace("[TMX] Total results after logic filtering: " + allResults.Length);
    return allResults;
}

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

        // Primary Tag/Surface Only (TMX might return tags as hints, we enforce)
        if (f.PrimaryTagOnly && m.Tags.Length > 1) continue;
        if (f.PrimarySurfaceOnly) {
            bool hasSurface = false;
            for (uint t = 0; t < m.Tags.Length; t++) {
                string tag = m.Tags[t];
                if (tag == "Race" || tag == "FullSpeed" || tag == "Tech" || tag == "Dirt" || tag == "Grass" || tag == "Ice" || tag == "Plastic") {
                    hasSurface = true; break;
                }
            }
            // If it has multiple surface tags, it's not "Primary Surface Only"
            if (!hasSurface) continue;
        }

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
