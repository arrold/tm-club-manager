// Logic/TmxCuration.as - TMX search & curation business logic (Zertrov Style)

void DoTmxSearch() {
    if (State::searchInProgress) return;
    State::searchInProgress = true;
    
    State::tmxSearchResults.RemoveRange(0, State::tmxSearchResults.Length);
    
    auto tmxMaps = FetchMapsSequential(State::tmxFilters, State::tmxFilters.ResultLimit, false);
    for (uint i = 0; i < tmxMaps.Length; i++) {
        State::tmxSearchResults.InsertLast(tmxMaps[i]);
    }

    State::tmxSelected.RemoveRange(0, State::tmxSelected.Length);
    for (uint i = 0; i < State::tmxSearchResults.Length; i++) State::tmxSelected.InsertLast(false);
    
    print("[TMX] Found " + State::tmxSearchResults.Length + " maps.");
    State::searchInProgress = false;
}

TmxMap[] FetchMapsSequential(TmxSearchFilters@ f, uint limit, bool applyOffset = true) {
    TmxMap[] allMatches;
    TmxSearchFilters@ tempFilters = TmxSearchFilters(f.ToJson());
    int lastAnalysedId = 0;
    bool usingAfterId = false;

    if (f.CurrentPage > 1 && f.CurrentPage <= int(f.PageStartingTrackIds.Length)) {
        lastAnalysedId = f.PageStartingTrackIds[f.CurrentPage - 1];
        usingAfterId = (lastAnalysedId > 0);
    }
    
    // Global skip count across all batches if we aren't using an 'after' ID
    f.remainingSkip = (applyOffset && f.CurrentPage > 1 && !usingAfterId) ? (uint(f.CurrentPage - 1) * limit) : 0;
    
    uint batches = 0;
    bool hasMore = true;
    
    // Increased batch limit to 20 to handle large Top TOTD clubs (150+ maps)
    while (allMatches.Length < limit && hasMore && batches < 20) {
        batches++;
        auto json = TMX::SearchMaps(tempFilters, 100);
        if (json is null) break;
        
        auto results = (json.HasKey("Results")) ? json["Results"] : json;
        if (results.GetType() != Json::Type::Array || results.Length == 0) break;
        
        int batchLastId = 0;
        auto batch = FilterTmxResults(results, f, limit - allMatches.Length, batchLastId);
        
        if (batchLastId > 0) lastAnalysedId = batchLastId;
        for (uint i = 0; i < batch.Length; i++) allMatches.InsertLast(batch[i]);
        
        hasMore = json.HasKey("More") && bool(json["More"]);
        if (hasMore) {
            tempFilters.PageStartingTrackIds.InsertLast(lastAnalysedId);
            // Sync current page to the end of our current tracked IDs so the NEXT batch uses this cursor
            tempFilters.CurrentPage = tempFilters.PageStartingTrackIds.Length;
            
            // Sync the progress back to the original filter so the NEXT page knows where to start
            if (int(tempFilters.PageStartingTrackIds.Length) > int(f.PageStartingTrackIds.Length)) {
                f.PageStartingTrackIds.InsertLast(lastAnalysedId);
            }
        }
    }
    
    // Final sync of the starting ID for the next page if not already there
    if (f.CurrentPage == int(f.PageStartingTrackIds.Length) && hasMore) {
        f.PageStartingTrackIds.InsertLast(lastAnalysedId);
    }
    return allMatches;
}

bool IsSurfaceTag(const string &in tag) {
    for (uint i = 0; i < TMX::SURFACE_TAGS.Length; i++) {
        if (TMX::SURFACE_TAGS[i] == tag) return true;
    }
    return false;
}

TmxMap[] FilterTmxResults(Json::Value@ results, TmxSearchFilters@ f, uint limit, int &out lastTrackId) {
    TmxMap[] filtered;
    lastTrackId = 0;
    if (results is null || results.GetType() != Json::Type::Array) return filtered;
    
    // uint skipCount = (applyOffset && f.CurrentPage > 1) ? (uint(f.CurrentPage - 1) * limit) : 0;
    // matchesFound = 0;

    bool hasDiffFilter = false;
    for (uint j = 0; j < f.Difficulties.Length; j++) if (f.Difficulties[j]) { hasDiffFilter = true; break; }

    for (uint i = 0; i < results.Length; i++) {
        lastTrackId = int(results[i]["MapId"]);
        TmxMap m(results[i]);
        
        // Multi-select difficulty local filter (for sequential fetching robustness)
        if (hasDiffFilter) {
            if (m.Difficulty < 1 || m.Difficulty > 6 || !f.Difficulties[m.Difficulty - 1]) continue;
        }

        if (f.PrimaryTagOnly && f.IncludeTags.Length > 0) {
            if (m.Tags.Length == 0 || m.Tags[0] != f.IncludeTags[0]) continue;
        }

        if (f.PrimarySurfaceOnly && f.IncludeTags.Length > 0) {
            string searchTag = f.IncludeTags[0];
            string firstSurface = "";
            for (uint j = 0; j < m.Tags.Length; j++) {
                if (IsSurfaceTag(m.Tags[j])) {
                    firstSurface = m.Tags[j];
                    break;
                }
            }
            if (firstSurface != searchTag) continue;
        }

        if (f.HideOversized) {
            if (m.ServerSizeExceeded || m.EmbeddedItemsSize > 4000000 || m.DisplayCost > 13000) continue;
        }
        
        if (f.remainingSkip > 0) {
            f.remainingSkip--;
            continue;
        }
        filtered.InsertLast(m);
        if (filtered.Length >= limit) break;
    }
    return filtered;
}

void DoBatchAdd() {
    if (State::TargetActivity is null || State::SelectedClub is null) return;
    
    string[] toAdd;
    for (uint i = 0; i < State::tmxSearchResults.Length; i++) {
        if (i < State::tmxSelected.Length && State::tmxSelected[i]) toAdd.InsertLast(State::tmxSearchResults[i].Uid);
    }
    if (toAdd.Length == 0) return;
    
    Notify("Adding " + toAdd.Length + " maps to " + State::TargetActivity.Name + "...");
    ApplyBatchToActivity(State::TargetActivity, toAdd);
}

void ApplyBatchToActivity(Activity@ a, string[]@ uids) {
    if (a is null || State::SelectedClub is null) return;
    if (a.Type == "campaign") {
        API::SetCampaignMaps(State::SelectedClub.Id, a.CampaignId, a.Name, uids);
    } else if (a.Type == "room") {
        API::SetRoomMaps(State::SelectedClub.Id, a.RoomId, uids);
    }
}

void DoBulkAudit() {
    if (State::bulkAuditInProgress) return;
    State::bulkAuditInProgress = true;
    State::bulkAuditProgress = 0.0f;
    State::bulkAuditStatus = "Starting...";

    trace("[Audit] Starting Bulk Audit...");
    auto subs = Subscriptions::All;
    if (subs.Length == 0) {
        State::bulkAuditInProgress = false;
        return;
    }

    for (uint i = 0; i < subs.Length; i++) {
        auto sub = subs[i];
        State::bulkAuditProgress = float(i) / float(subs.Length);
        State::bulkAuditStatus = "Checking activity: " + sub.ActivityName + " (" + (i+1) + "/" + subs.Length + ")";
        
        trace("[Audit] Processing: " + sub.ActivityName);
        
        Activity@ act = null;
        for (uint j = 0; j < State::ClubActivities.Length; j++) {
            if (State::ClubActivities[j].Id == sub.ActivityId) {
                @act = State::ClubActivities[j];
                break;
            }
        }

        if (act is null) {
            warn("[Audit] Activity " + sub.ActivityId + " not found in current club selection.");
            continue;
        }

        auto results = FetchMapsSequential(sub.Filters, sub.MapLimit, false);
        if (results.Length == 0) continue;

        string[] newUids;
        for (uint j = 0; j < results.Length; j++) newUids.InsertLast(results[j].Uid);

        for (uint j = 0; j < newUids.Length; j++) {
            if (!Nadeo::IsMapUploaded(newUids[j])) {
                Nadeo::RegisterMap(newUids[j]);
                yield(); 
            }
        }

        ApplyBatchToActivity(act, newUids);
        
        yield();
        sleep(2000); 
    }

    State::bulkAuditStatus = "Complete!";
    State::bulkAuditProgress = 1.0f;
    sleep(3000);
    State::bulkAuditInProgress = false;
}
