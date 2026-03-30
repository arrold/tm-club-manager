// Logic/TmxCuration.as - Sequential TMX fetching and curation helpers

/*
 * Sequential TMX Fetching:
 * TMX API (V1) has stability issues with large offsets. This function implements 
 * a "cursor-based" sequential scan using TrackId (afterId) to reliably page through 
 * results. It also handles client-side filtering for attributes TMX cannot 
 * natively filter (e.g., precise time ranges or multi-tag combinations).
 */
TmxMap@[] FetchMapsSequential(TmxSearchFilters@ f, uint limit, bool applyOffset = true, bool useCache = true) {
    if (f.AuthorNames.Length > 1) {
        return FetchMultiAuthor(f, limit, applyOffset, useCache);
    }

    TmxMap@[] allResults;
    uint skipCount = (applyOffset && f.CurrentPage > 1) ? (f.CurrentPage - 1) * limit : 0;
    uint totalNeeded = skipCount + limit;
    
    uint offset = 0; 
    uint lastId = 0;
    
    int authorId = -1;
    if (f.AuthorNames.Length == 1) {
        authorId = TMX::GetUserId(f.AuthorNames[0]);
    }

    uint batchSize = Math::Min(Math::Max(limit, uint(25)), uint(50));
    uint targetLength = totalNeeded;
    uint safetyLimit = 0;
    const uint maxPages = 20;

    while (allResults.Length < targetLength && safetyLimit < maxPages) {
        safetyLimit++;
        Json::Value@ json = TMX::SearchMaps(f, batchSize, offset, lastId, useCache, "", authorId);
        if (json is null) break;

        int fetchedCount = 0;
        TmxMap@[] batch = FilterTmxResults(json, f, batchSize, fetchedCount);

        for (uint i = 0; i < batch.Length; i++) {
            if (allResults.Length < targetLength) {
                allResults.InsertLast(batch[i]);
            }
        }

        if (allResults.Length >= targetLength) break;
        if (fetchedCount < int(batchSize)) break;
        if (json.HasKey("More") && !bool(json["More"])) break;

        // Safety: If we've searched multiple pages and found ZERO matches for a specific author, 
        // the server's author filter is almost certainly failing/ignored.
        if (allResults.Length == 0 && safetyLimit >= 2 && f.AuthorNames.Length > 0) {
            warn("[TMX] Server returned maps but none matched '" + f.AuthorNames[0] + "'. Stopping search to prevent loop.");
            break;
        }

        if (batch.Length > 0 && int(batch.Length) == fetchedCount) {
            // No client-side filtering occurred — safe to use cursor (avoids large-offset instability in TMX V1)
            lastId = batch[batch.Length - 1].TrackId;
            offset = 0;
        } else {
            // Client-side filtering removed some maps (denylist / difficulty override).
            // The TMX &after= parameter means MapId > X, not a positional cursor. Using
            // the last valid map's TrackId as the cursor would skip valid replacements that
            // have a lower MapId (older high-award maps). Advance by raw count via offset instead.
            offset += fetchedCount;
            lastId = 0;
        }

        yield();
    }

    // Slice only the requested
    TmxMap@[] pageResults;
    uint startIdx = skipCount;
    if (allResults.Length > startIdx) {
        for (uint i = startIdx; i < allResults.Length; i++) {
            pageResults.InsertLast(allResults[i]);
        }
    }
    
    // trace("[TMX] Scan complete. Found " + allResults.Length + " maps total. Returning page offset " + skipCount);
    yield();
    return pageResults;
}

TmxMap@[] FetchMultiAuthor(TmxSearchFilters@ f, uint limit, bool applyOffset, bool useCache) {
    TmxMap@[] merged;
    uint skipCount = (applyOffset && f.CurrentPage > 1) ? (f.CurrentPage - 1) * limit : 0;
    // Fetch a bit more per author to ensure better sorting of the merged list
    uint totalNeeded = Math::Max(skipCount + limit, uint(100)); 
    
    // For each author, fetch up to totalNeeded maps
    for (uint i = 0; i < f.AuthorNames.Length; i++) {
        string author = f.AuthorNames[i];
        TmxMap@[] authorResults;
        uint lastId = 0;
        uint offset = 0;
        uint batchSize = 50;

        uint safetyLimit = 0;
        const uint maxPages = 20;
        int authorId = TMX::GetUserId(author);

        while (authorResults.Length < totalNeeded && safetyLimit < maxPages) {
            safetyLimit++;
            Json::Value@ json = TMX::SearchMaps(f, batchSize, offset, lastId, useCache, "", authorId);
            if (json is null) break;

            int fetchedCount = 0;
            TmxMap@[] batch = FilterTmxResults(json, f, batchSize, fetchedCount);
            for (uint j = 0; j < batch.Length; j++) authorResults.InsertLast(batch[j]);
            
            if (fetchedCount < int(batchSize)) break;
            if (json.HasKey("More") && !bool(json["More"])) break;

            if (batch.Length > 0) {
                lastId = batch[batch.Length - 1].TrackId;
                offset = 0;
            } else {
                offset += fetchedCount;
            }
            yield();
        }
        
        for (uint j = 0; j < authorResults.Length; j++) merged.InsertLast(authorResults[j]);
    }

    // Client-side Sort
    SortMaps(merged, f.SortPrimary, f.SortSecondary);
    yield();

    // Slice
    TmxMap@[] pageResults;
    if (merged.Length > skipCount) {
        uint pageLimit = skipCount + limit;
        uint maxIdx = uint(Math::Min(int(merged.Length), int(pageLimit)));
        for (uint i = skipCount; i < maxIdx; i++) {
            pageResults.InsertLast(merged[i]);
        }
    }
    
    if (f.AuthorNames.Length > 1) {
        Notify("Multi-Mapper Search: Aggregated " + merged.Length + " maps from " + f.AuthorNames.Length + " mappers.");
    }
    return pageResults;
}

void SortMaps(TmxMap@[]& arr, int sort1, int sort2 = -1) {
    if (arr.Length < 2) return;
    if (sort1 < 0 || sort1 > 9) return; 
    uint compareCount = 0;
    for (uint i = 0; i < arr.Length; i++) {
        for (uint j = i + 1; j < arr.Length; j++) {
            if (++compareCount % 100 == 0) yield(); 
            if (CompareMaps(arr[i], arr[j], sort1, sort2)) {
                TmxMap@ temp = arr[i]; @arr[i] = arr[j]; @arr[j] = temp;
            }
        }
    }
}

bool CompareMaps(TmxMap@ a, TmxMap@ b, int s1, int s2) {
    bool swap = ShouldSwap(a, b, s1);
    bool equal = !swap && !ShouldSwap(b, a, s1);
    
    if (equal && s2 >= 0 && s2 <= 9) {
        return ShouldSwap(a, b, s2);
    }
    return swap;
}

bool ShouldSwap(TmxMap@ a, TmxMap@ b, int sortIdx) {
    switch (sortIdx) {
        case 0: return a.AwardCount < b.AwardCount; // Awards Most
        case 1: return a.AwardCount > b.AwardCount; // Awards Least
        case 2: return a.UploadedAt > b.UploadedAt; // Oldest
        case 3: return a.DownloadCount < b.DownloadCount; // Downloads Most
        case 4: return a.DownloadCount > b.DownloadCount; // Downloads Least
        case 5: return a.UploadedAt < b.UploadedAt; // Newest
        case 6: return a.Difficulty > b.Difficulty; // Easiest
        case 7: return a.Difficulty < b.Difficulty; // Hardest
        case 8: return a.Name > b.Name; // A-Z
        case 9: return a.Name < b.Name; // Z-A
    }
    return false;
}

/*
 * Client-Side Result Filtering:
 * Applies secondary validation logic to TMX search results. 
 * This includes multi-difficulty matching, primary surface/tag isolation, 
 * and author time range validation. 
 */
TmxMap@[] FilterTmxResults(Json::Value@ json, TmxSearchFilters@ f, uint requestedCount, int&out fetchedCount) {
    TmxMap@[] filtered;
    fetchedCount = 0;

    if (json is null) return filtered;
    
    Json::Value@ results = null;
    if (json.GetType() == Json::Type::Array) {
        @results = @json;
    } else if (json.GetType() == Json::Type::Object) {
        if (json.HasKey("Results") && json["Results"].GetType() == Json::Type::Array) {
            @results = @json["Results"];
        } else if (json.HasKey("results") && json["results"].GetType() == Json::Type::Array) {
            @results = @json["results"];
        } else if (json.HasKey("MapList") && json["MapList"].GetType() == Json::Type::Array) {
            @results = @json["MapList"];
        }
    }

    if (results is null || results.GetType() != Json::Type::Array) {
        if (json.GetType() == Json::Type::Object) trace("[TMX] MapList/Results not found. Keys: " + string::Join(json.GetKeys(), ", "));
        else trace("[TMX] Response is not an object! Type: " + tostring(json.GetType()));
        return filtered;
    }

    fetchedCount = results.Length;
    for (uint i = 0; i < results.Length; i++) {
        if (i % 10 == 0) yield(); // Yield to prevent UI hang during large JSON processing
        TmxMap m(results[i]);
        if (m.Uid == "") continue;
        if (Denylist::IsExcluded(m.Uid)) continue;

        // Author filter (handles collaborations and tags)
        if (f.AuthorNames.Length > 0) {
            bool authorMatch = false;
            for (uint j = 0; j < f.AuthorNames.Length; j++) {
                string searchName = f.AuthorNames[j].ToLower();
                // Check primary uploader + collaborators
                for (uint k = 0; k < m.Authors.Length; k++) {
                    if (m.Authors[k].ToLower().Contains(searchName)) {
                        authorMatch = true; 
                        trace("[TMX] Match found for '" + searchName + "' in Authors[] of map: " + m.Name);
                        break;
                    }
                }
                if (authorMatch) break;
                // Check tags (sometimes authors are tagged)
                for (uint k = 0; k < m.Tags.Length; k++) {
                    if (m.Tags[k].ToLower().Contains(searchName)) {
                        authorMatch = true; break;
                    }
                }
                if (authorMatch) break;
            }
            if (!authorMatch) continue;
        }

        // Apply secondary logic filters
        if (f.MapName != "" && !m.Name.ToLower().Contains(f.MapName.ToLower())) continue;

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
        if (f.PrimaryTagOnly) {
            if (m.Tags.Length == 0) continue;
            string primary = m.Tags[0];
            if (f.PrimaryTag != "") {
                if (primary.ToLower() != f.PrimaryTag.ToLower()) continue;
            } else if (f.IncludeTags.Length > 0) {
                bool found = false;
                for (uint j = 0; j < f.IncludeTags.Length; j++) {
                    if (primary == f.IncludeTags[j]) { found = true; break; }
                }
                if (!found) continue;
            }
        }
        
        // Optional: Primary Surface (First tag that is a surface)
        if (f.PrimarySurfaceOnly) {
            string firstSurface = "";
            for (uint j = 0; j < m.Tags.Length; j++) {
                if (TMX::ArrayContains(TMX::SURFACE_TAGS, m.Tags[j])) {
                    firstSurface = m.Tags[j];
                    break;
                }
            }
            if (firstSurface == "") continue;
            
            if (f.PrimarySurface != "") {
                if (firstSurface.ToLower() != f.PrimarySurface.ToLower()) continue;
            } else if (f.IncludeTags.Length > 0) {
                bool found = false;
                for (uint j = 0; j < f.IncludeTags.Length; j++) {
                    if (firstSurface == f.IncludeTags[j]) { found = true; break; }
                }
                if (!found) continue;
            }
        }

        // Author Time Range Filter (Client-side safeguard)
        uint lengthMs = m.LengthSecs * 1000;
        if (f.TimeFromMs > 0 && lengthMs < f.TimeFromMs) continue;
        if (f.TimeToMs > 0 && lengthMs > f.TimeToMs) continue;

        // Room Guardrails (General)
        if (m.EmbeddedItemsSize > f.ItemSizeLimit || m.DisplayCost > f.DisplayCostLimit) continue;
        if (m.ServerSizeExceeded) continue; // Always omit oversized for safety

        // Multi-State Limit Filter Guardrails
        if (f.LimitFilter >= 1) {
            // State 1: Filter out Red Warning Maps
            if (m.ServerSizeExceeded || m.EmbeddedItemsSize > 4000000 || m.DisplayCost > 12000) continue;
        }
        if (f.LimitFilter >= 2) {
            // State 2: Filter out Yellow Warning Maps (and Red already filtered above)
            if (m.EmbeddedItemsSize > 1000000 || m.DisplayCost > 8000) continue;
        }

        AuditCache::Register(m);
        filtered.InsertLast(m);
        trace("[TMX] Map added to filtered results: " + m.Name + " (Uid: " + m.Uid + ")");
        if (filtered.Length >= requestedCount) break;
    }

    return filtered;
}

void DoTmxSearch() {
    TmxSearchFilters@ f = State::tmxFilters.Clone();
    State::searchInProgress = true;
    State::tmxSearchResults.RemoveRange(0, State::tmxSearchResults.Length);

    if (f.CurrentPage < 1) f.CurrentPage = 1;

    TmxMap@[] results = FetchMapsSequential(f, uint(f.ResultLimit), true, false);
    
    // TMX.as will handle warnings for timeouts.

    for (uint i = 0; i < results.Length; i++) {
        State::tmxSearchResults.InsertLast(results[i]);
    }
    
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
    if (a.Type == "room" && a.MirrorCampaignId > 0) {
        warn("Attempted to write maps to mirrored room " + a.Id + ". Operation cancelled.");
        return;
    }
    
    string[] finalUids;
    for (uint i = 0; i < uids.Length; i++) finalUids.InsertLast(uids[i]);

    if (a.Type == "campaign") {
        if (finalUids.Length > 25) {
            finalUids.RemoveRange(25, finalUids.Length - 25);
            Notify("Nadeo limits Campaigns to 25 maps! List truncated.");
        }
        Json::Value@ current = API::GetCampaignMaps(State::SelectedClub.Id, a.CampaignId);
        API::SetCampaignMaps(State::SelectedClub.Id, a.CampaignId, a.Name, finalUids, current);
    } else if (a.Type == "room") {
        if (finalUids.Length > 100) {
            finalUids.RemoveRange(100, finalUids.Length - 100);
            Notify("Nadeo limits Rooms to 100 maps! List truncated.");
        }
        API::SetRoomMaps(State::SelectedClub.Id, a.RoomId, finalUids);
    }
}
