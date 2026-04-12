// Logic/TmxCuration.as - Sequential TMX fetching and curation helpers

/*
 * Sequential TMX Fetching:
 * Uses TMX's &after=<TrackId> positional cursor to page through results.
 * The cursor is always taken from the last raw entry in each API response - not the
 * last filtered entry - so client-side filtering (denylist, difficulty override) never
 * causes the same page to be re-fetched.
 */
TmxMap@[] FetchMapsSequential(TmxSearchFilters@ f, uint limit, bool applyOffset = true, bool useCache = true, int priorSmartIncludes = 0) {
    if (f.AuthorNames.Length > 1) {
        return FetchMultiAuthor(f, limit, applyOffset, useCache, priorSmartIncludes);
    }

    // TMX only supports a single &difficulty= param. When 2+ difficulties are selected,
    // make one API call per difficulty and merge client-side (same pattern as multi-author).
    uint selectedDiffCount = 0;
    for (uint i = 0; i < f.Difficulties.Length; i++) { if (f.Difficulties[i]) selectedDiffCount++; }
    if (selectedDiffCount > 1) {
        return FetchMultiDifficulty(f, limit, applyOffset, useCache, priorSmartIncludes);
    }

    TmxMap@[] allResults;
    int rawSkip = (applyOffset && f.CurrentPage > 1) ? int((f.CurrentPage - 1) * limit) - priorSmartIncludes : 0;
    uint skipCount = rawSkip > 0 ? uint(rawSkip) : 0;
    uint totalNeeded = skipCount + limit;
    
    uint offset = 0; 
    uint lastId = 0;
    
    int authorId = -1;
    if (f.AuthorNames.Length == 1) {
        authorId = TMX::GetUserId(f.AuthorNames[0]);
    }

    // For the expensive "Awards Most + Not TOTD" combo, fetch 100 maps per batch so the audit
    // can satisfy the limit (max 25) in a single API call, avoiding a second-page timeout.
    bool isSlowCombo = (f.InTOTD == 0 && f.SortPrimary == 0);
    uint batchSize = isSlowCombo ? 100 : Math::Min(Math::Max(limit, uint(25)), uint(50));
    uint targetLength = totalNeeded;
    uint safetyLimit = 0;
    const uint maxPages = 20;

    while (allResults.Length < targetLength && safetyLimit < maxPages) {
        safetyLimit++;
        Json::Value@ json = TMX::SearchMaps(f, batchSize, offset, lastId, useCache, "", authorId);
        if (json is null) break;

        // Read the last raw TrackId before filtering - used as the positional cursor for the next page.
        // &after=X is a positional cursor in the sorted result set, not a MapId filter.
        // We must advance by the raw batch boundary, not the filtered one, so client-side
        // filtering (denylist, difficulty override) never causes the same page to be re-fetched.
        uint rawLastId = 0;
        {
            Json::Value@ rawResults = null;
            if (json.GetType() == Json::Type::Array) @rawResults = json;
            else if (json.HasKey("Results") && json["Results"].GetType() == Json::Type::Array) @rawResults = json["Results"];
            else if (json.HasKey("results") && json["results"].GetType() == Json::Type::Array) @rawResults = json["results"];
            else if (json.HasKey("MapList") && json["MapList"].GetType() == Json::Type::Array) @rawResults = json["MapList"];
            if (rawResults !is null && rawResults.Length > 0) {
                Json::Value@ last = rawResults[rawResults.Length - 1];
                rawLastId = last.HasKey("MapId") ? uint(last["MapId"]) : (last.HasKey("TrackId") ? uint(last["TrackId"]) : 0);
            }
        }

        int fetchedCount = 0;
        TmxMap@[] batch = FilterTmxResults(json, f, batchSize, fetchedCount);

        for (uint i = 0; i < batch.Length; i++) {
            if (allResults.Length < targetLength) {
                allResults.InsertLast(batch[i]);
            }
        }

        if (allResults.Length >= targetLength) break;
        if (fetchedCount < int(batchSize)) break;
        if (!JsonGetBool(json, "More", true)) break;

        // Safety: If we've searched multiple pages and found ZERO matches for a specific author,
        // the server's author filter is almost certainly failing/ignored.
        if (allResults.Length == 0 && safetyLimit >= 2 && f.AuthorNames.Length > 0) {
            warn("[TMX] Server returned maps but none matched '" + f.AuthorNames[0] + "'. Stopping search to prevent loop.");
            break;
        }

        if (rawLastId > 0) {
            lastId = rawLastId;
            offset = 0;
        } else {
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

TmxMap@[] FetchMultiAuthor(TmxSearchFilters@ f, uint limit, bool applyOffset, bool useCache, int priorSmartIncludes = 0) {
    TmxMap@[] merged;
    int rawSkip = (applyOffset && f.CurrentPage > 1) ? int((f.CurrentPage - 1) * limit) - priorSmartIncludes : 0;
    uint skipCount = rawSkip > 0 ? uint(rawSkip) : 0;
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
            if (!JsonGetBool(json, "More", true)) break;

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

TmxMap@[] FetchMultiDifficulty(TmxSearchFilters@ f, uint limit, bool applyOffset, bool useCache, int priorSmartIncludes = 0) {
    TmxMap@[] merged;
    int rawSkip = (applyOffset && f.CurrentPage > 1) ? int((f.CurrentPage - 1) * limit) - priorSmartIncludes : 0;
    uint skipCount = rawSkip > 0 ? uint(rawSkip) : 0;
    uint totalNeeded = Math::Max(skipCount + limit, uint(100));

    dictionary seen;

    // One API call per selected difficulty index so TMX applies a proper server-side filter.
    // Results per difficulty are merged and sorted client-side before slicing.
    for (uint diffIdx = 0; diffIdx < f.Difficulties.Length; diffIdx++) {
        if (!f.Difficulties[diffIdx]) continue;

        TmxMap@[] diffResults;
        uint lastId = 0;
        uint offset = 0;
        uint batchSize = 50;
        uint safetyLimit = 0;
        const uint maxPages = 20;

        while (diffResults.Length < totalNeeded && safetyLimit < maxPages) {
            safetyLimit++;
            Json::Value@ json = TMX::SearchMaps(f, batchSize, offset, lastId, useCache, "", -1, int(diffIdx));
            if (json is null) break;

            int fetchedCount = 0;
            TmxMap@[] batch = FilterTmxResults(json, f, batchSize, fetchedCount);
            for (uint j = 0; j < batch.Length; j++) diffResults.InsertLast(batch[j]);

            if (fetchedCount < int(batchSize)) break;
            if (!JsonGetBool(json, "More", true)) break;

            if (batch.Length > 0) {
                lastId = batch[batch.Length - 1].TrackId;
                offset = 0;
            } else {
                offset += fetchedCount;
            }
            yield();
        }

        for (uint j = 0; j < diffResults.Length; j++) {
            if (!seen.Exists(diffResults[j].Uid)) {
                seen[diffResults[j].Uid] = true;
                merged.InsertLast(diffResults[j]);
            }
        }
    }

    SortMaps(merged, f.SortPrimary, f.SortSecondary);
    yield();

    TmxMap@[] pageResults;
    if (merged.Length > skipCount) {
        uint pageLimit = skipCount + limit;
        uint maxIdx = uint(Math::Min(int(merged.Length), int(pageLimit)));
        for (uint i = skipCount; i < maxIdx; i++) {
            pageResults.InsertLast(merged[i]);
        }
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
        if (f.InTOTD == 1) m.IsTOTD = true;
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

// Check whether a cached TmxMap passes the subscription's non-difficulty filters locally.
// Difficulty is intentionally skipped - the caller has already resolved the effective difficulty.
bool MatchesFiltersLocally(TmxMap@ map, TmxSearchFilters@ f) {
    if (map is null) return false;

    // Map name substring match
    if (f.MapName != "" && map.Name.ToLower().Contains(f.MapName.ToLower()) == false) return false;

    // Author filter
    if (f.AuthorNames.Length > 0) {
        bool authorMatch = false;
        for (uint i = 0; i < f.AuthorNames.Length; i++) {
            for (uint j = 0; j < map.Authors.Length; j++) {
                if (map.Authors[j].ToLower().Contains(f.AuthorNames[i].ToLower())) { authorMatch = true; break; }
            }
            if (authorMatch) break;
        }
        if (!authorMatch) return false;
    }

    // Include tags: map must have at least one
    if (f.IncludeTags.Length > 0) {
        bool hasInclude = false;
        for (uint i = 0; i < f.IncludeTags.Length; i++) {
            if (map.Tags.Find(f.IncludeTags[i]) >= 0) { hasInclude = true; break; }
        }
        if (!hasInclude) return false;
    }

    // Exclude tags: map must have none
    for (uint i = 0; i < f.ExcludeTags.Length; i++) {
        if (map.Tags.Find(f.ExcludeTags[i]) >= 0) return false;
    }

    // Author time range (LengthSecs * 1000 = ms)
    // If a time filter is active and length is unknown, reject conservatively.
    uint authorMs = map.LengthSecs * 1000;
    if ((f.TimeFromMs > 0 || f.TimeToMs > 0) && authorMs == 0) return false;
    if (f.TimeFromMs > 0 && authorMs < f.TimeFromMs) return false;
    if (f.TimeToMs > 0 && authorMs > f.TimeToMs) return false;

    // Upload date range.
    // map.UploadedAt is ISO (yyyy-MM-dd...), filter dates are stored as dd/MM/yyyy -
    // convert filter dates via TMX::FormatDate before comparing.
    // If the filter has a date constraint and the cached map has no UploadedAt, reject conservatively.
    if (f.RelativeDays > 0) {
        if (map.UploadedAt == "") return false;
        string cutoff = TMX::DateDaysAgo(f.RelativeDays);
        if (map.UploadedAt < cutoff) return false;
    } else {
        if (f.UploadedFrom != "" || f.UploadedTo != "") {
            if (map.UploadedAt == "") return false;
        }
        if (f.UploadedFrom != "") {
            string isoFrom = TMX::FormatDate(f.UploadedFrom);
            if (map.UploadedAt < isoFrom) return false;
        }
        if (f.UploadedTo != "") {
            string isoTo = TMX::FormatDate(f.UploadedTo);
            if (map.UploadedAt > isoTo) return false;
        }
    }

    // TOTD status: only inject maps that match the TOTD filter.
    // IsTOTD defaults to false, so TOTD-only (InTOTD==1) subscriptions will reject
    // any smart-include whose cached MapData doesn't confirm it as TOTD - which is the
    // safe behaviour: if the map truly is TOTD with a difficulty override, re-sync its
    // metadata (via the Sync button) so IsTOTD gets stored.
    if (f.InTOTD == 1 && !map.IsTOTD) return false;
    if (f.InTOTD == 0 && map.IsTOTD) return false;

    // Custom tags (local client-side filter - checks metadata_overrides per UID)
    if (f.IncludeCustomTags.Length > 0 || f.ExcludeCustomTags.Length > 0) {
        string[] mapCustomTags = MetadataOverrides::GetCustomTags(map.Uid);
        if (f.IncludeCustomTags.Length > 0) {
            bool hasInclude = false;
            for (uint i = 0; i < f.IncludeCustomTags.Length; i++) {
                if (mapCustomTags.Find(f.IncludeCustomTags[i]) >= 0) { hasInclude = true; break; }
            }
            if (!hasInclude) return false;
        }
        for (uint i = 0; i < f.ExcludeCustomTags.Length; i++) {
            if (mapCustomTags.Find(f.ExcludeCustomTags[i]) >= 0) return false;
        }
    }

    return true;
}

// Merge smart-include maps into TMX results and re-sort by the primary sort field.
// smart maps must not already be present in results (caller guarantees dedup).
TmxMap@[] MergeAndSort(TmxMap@[]@ results, TmxMap@[]@ smartMaps, int sortPrimary) {
    TmxMap@[] merged;
    for (uint i = 0; i < results.Length; i++) merged.InsertLast(results[i]);
    for (uint i = 0; i < smartMaps.Length; i++) merged.InsertLast(smartMaps[i]);

    if (sortPrimary < 0 || merged.Length < 2) return merged;

    // Bubble sort - small lists only (typically ≤ 25 + a handful of overrides)
    for (uint i = 0; i < merged.Length - 1; i++) {
        for (uint j = 0; j < merged.Length - i - 1; j++) {
            bool swap = false;
            switch (sortPrimary) {
                case 0: swap = merged[j].AwardCount    < merged[j+1].AwardCount;    break; // Awards Most
                case 1: swap = merged[j].AwardCount    > merged[j+1].AwardCount;    break; // Awards Least
                case 2: swap = merged[j].UploadedAt    > merged[j+1].UploadedAt;    break; // Uploaded Oldest
                case 3: swap = merged[j].DownloadCount < merged[j+1].DownloadCount; break; // Downloads Most
                case 4: swap = merged[j].DownloadCount > merged[j+1].DownloadCount; break; // Downloads Least
                case 5: swap = merged[j].UploadedAt    < merged[j+1].UploadedAt;    break; // Uploaded Newest
                case 6: swap = merged[j].Difficulty    > merged[j+1].Difficulty;    break; // Difficulty Easiest
                case 7: swap = merged[j].Difficulty    < merged[j+1].Difficulty;    break; // Difficulty Hardest
                case 8: swap = merged[j].Name          > merged[j+1].Name;          break; // Name A-Z
                case 9: swap = merged[j].Name          < merged[j+1].Name;          break; // Name Z-A
            }
            if (swap) {
                TmxMap@ tmp = merged[j];
                @merged[j] = merged[j+1];
                @merged[j+1] = tmp;
            }
        }
    }
    return merged;
}

// Count override-cached maps that match filters (no page boundary check).
// Used to adjust the TMX skip count for page N > 1 so bumped maps aren't lost.
// Only relevant when a difficulty filter is active - without one, TMX already returns
// the override maps naturally, so no skip adjustment is needed.
int CountMatchingSmartIncludes(TmxSearchFilters@ f) {
    if (State::SelectedClub is null) return 0;

    // Smart-includes only compensate for maps that TMX's server-side difficulty filter has excluded.
    // TMX only supports a single difficulty value - when 0 or 2+ difficulties are selected, no server
    // filter is applied and TMX already returns those maps naturally. No skip adjustment is needed.
    uint selectedDiffCount = 0;
    for (uint j = 0; j < f.Difficulties.Length; j++) { if (f.Difficulties[j]) selectedDiffCount++; }
    if (selectedDiffCount != 1) return 0;

    int count = 0;
    dictionary seen;

    string[] globalUids = MetadataOverrides::GetUidsWithCachedMap();
    for (uint i = 0; i < globalUids.Length; i++) {
        TmxMap@ cached = MetadataOverrides::GetCachedMap(globalUids[i]);
        if (cached is null) continue;
        int effectiveDiff = cached.Difficulty;
        Json::Value@ clubOvr = ClubOverrides::GetOverride(State::SelectedClub.Id, globalUids[i]);
        if (clubOvr !is null && clubOvr.HasKey("Difficulty")) effectiveDiff = int(clubOvr["Difficulty"]);
        int idx = effectiveDiff - 1;
        bool diffMatch = (idx >= 0 && idx < int(f.Difficulties.Length) && f.Difficulties[idx]);
        if (diffMatch && MatchesFiltersLocally(cached, f)) {
            count++;
            seen[globalUids[i]] = true;
        }
    }

    string[] clubUids = ClubOverrides::GetUidsWithCachedMap(State::SelectedClub.Id);
    for (uint i = 0; i < clubUids.Length; i++) {
        if (seen.Exists(clubUids[i])) continue;
        TmxMap@ cached = ClubOverrides::GetCachedMap(State::SelectedClub.Id, clubUids[i]);
        if (cached is null) continue;
        Json::Value@ clubOvr = ClubOverrides::GetOverride(State::SelectedClub.Id, clubUids[i]);
        int effectiveDiff = cached.Difficulty;
        if (clubOvr !is null && clubOvr.HasKey("Difficulty")) effectiveDiff = int(clubOvr["Difficulty"]);
        int idx = effectiveDiff - 1;
        bool diffMatch = (idx >= 0 && idx < int(f.Difficulties.Length) && f.Difficulties[idx]);
        if (diffMatch && MatchesFiltersLocally(cached, f)) count++;
    }

    return count;
}

// Collect override-cached maps that match the given filters and page context,
// merge them into results, sort, and trim to pageLimit.
// Safe to call from both audits and the live TMX search.
TmxMap@[] ApplySmartIncludes(TmxMap@[]@ results, TmxSearchFilters@ f, uint pageLimit) {
    if (State::SelectedClub is null) return results;

    dictionary resultUids;
    for (uint i = 0; i < results.Length; i++) resultUids[results[i].Uid] = true;

    TmxMap@[] smartCandidates;
    // For page 2+, skip override maps that sort better than the first result on this page -
    // they would belong in an earlier page's campaign.
    bool checkPageBoundary = (f.CurrentPage > 1 && results.Length > 0);

    // Helper lambda: check difficulty filter
    // (inline since AngelScript has no lambdas)

    // Collect from global overrides
    string[] globalUids = MetadataOverrides::GetUidsWithCachedMap();
    for (uint i = 0; i < globalUids.Length; i++) {
        if (resultUids.Exists(globalUids[i])) continue;
        TmxMap@ cached = MetadataOverrides::GetCachedMap(globalUids[i]);
        if (cached is null) continue;
        int effectiveDiff = cached.Difficulty;
        Json::Value@ clubOvr = ClubOverrides::GetOverride(State::SelectedClub.Id, globalUids[i]);
        if (clubOvr !is null && clubOvr.HasKey("Difficulty")) effectiveDiff = int(clubOvr["Difficulty"]);
        int idx = effectiveDiff - 1;
        bool diffMatch = (idx >= 0 && idx < int(f.Difficulties.Length) && f.Difficulties[idx]);
        bool noDiffFilter = true;
        for (uint j = 0; j < f.Difficulties.Length; j++) { if (f.Difficulties[j]) { noDiffFilter = false; break; } }
        if ((diffMatch || noDiffFilter) && MatchesFiltersLocally(cached, f)) {
            if (checkPageBoundary && ShouldSwap(results[0], cached, f.SortPrimary)) continue;
            smartCandidates.InsertLast(cached);
            resultUids[cached.Uid] = true;
        }
    }

    // Collect from club overrides (maps not already covered by global)
    string[] clubUids = ClubOverrides::GetUidsWithCachedMap(State::SelectedClub.Id);
    for (uint i = 0; i < clubUids.Length; i++) {
        if (resultUids.Exists(clubUids[i])) continue;
        TmxMap@ cached = ClubOverrides::GetCachedMap(State::SelectedClub.Id, clubUids[i]);
        if (cached is null) continue;
        Json::Value@ clubOvr = ClubOverrides::GetOverride(State::SelectedClub.Id, clubUids[i]);
        int effectiveDiff = cached.Difficulty;
        if (clubOvr !is null && clubOvr.HasKey("Difficulty")) effectiveDiff = int(clubOvr["Difficulty"]);
        int idx = effectiveDiff - 1;
        bool diffMatch = (idx >= 0 && idx < int(f.Difficulties.Length) && f.Difficulties[idx]);
        bool noDiffFilter = true;
        for (uint j = 0; j < f.Difficulties.Length; j++) { if (f.Difficulties[j]) { noDiffFilter = false; break; } }
        if ((diffMatch || noDiffFilter) && MatchesFiltersLocally(cached, f)) {
            if (checkPageBoundary && ShouldSwap(results[0], cached, f.SortPrimary)) continue;
            smartCandidates.InsertLast(cached);
            resultUids[cached.Uid] = true;
        }
    }

    TmxMap@[] merged = results;
    if (smartCandidates.Length > 0) {
        merged = MergeAndSort(results, smartCandidates, f.SortPrimary);
    }

    // Trim to page limit (smart-includes must not cause the list to exceed capacity)
    if (merged.Length > pageLimit) {
        merged.RemoveRange(pageLimit, merged.Length - pageLimit);
    }

    return merged;
}

void StartFreshTmxSearch() {
    // Clears the browse cache so DoTmxSearch rebuilds rather than serving stale results.
    // Called by the Search button; Prev/Next call DoTmxSearch directly to preserve the cache.
    State::tmxBrowseCache.RemoveRange(0, State::tmxBrowseCache.Length);
    State::tmxBrowseCacheExhausted = false;
    State::tmxBrowseCacheExtensionFailed = false;
    DoTmxSearch();
}

void DoTmxSearch() {
    TmxSearchFilters@ f = State::tmxFilters.Clone();
    if (f.CurrentPage < 1) f.CurrentPage = 1;
    int requestedPage = f.CurrentPage;
    bool isSlowCombo = (f.InTOTD == 0 && f.SortPrimary == 0);
    uint pageSize = uint(f.ResultLimit);

    if (isSlowCombo) {
        uint startIdx = uint(requestedPage - 1) * pageSize;

        const uint BROWSE_BATCH = 100;

        // Page is beyond the cache end - if exhausted or extension failed, bounce back rather than resetting.
        if (State::tmxBrowseCache.Length > 0 && startIdx >= State::tmxBrowseCache.Length
                && (State::tmxBrowseCacheExhausted || State::tmxBrowseCacheExtensionFailed)) {
            State::tmxFilters.CurrentPage = requestedPage - 1;
            if (State::tmxBrowseCacheExtensionFailed) {
                NotifyError("TMX timed out extending results - hit Search to retry.");
            } else {
                NotifyError("No more results.");
            }
            return;
        }

        // Serve from cache if it already covers this page.
        if (State::tmxBrowseCache.Length > startIdx) {
            TmxMap@[] page;
            for (uint i = startIdx; i < State::tmxBrowseCache.Length && i < startIdx + pageSize; i++) {
                page.InsertLast(State::tmxBrowseCache[i]);
            }

            // Page came back short and TMX may have more - extend the cache.
            if (page.Length < pageSize && !State::tmxBrowseCacheExhausted && !State::tmxBrowseCacheExtensionFailed) {
                State::searchInProgress = true;
                uint lastId = State::tmxBrowseCache[State::tmxBrowseCache.Length - 1].TrackId;
                TmxSearchFilters@ fBase = f.Clone();
                fBase.CurrentPage = 1;
                Json::Value@ more = TMX::SearchMaps(fBase, BROWSE_BATCH, 0, lastId, true);
                if (more !is null) {
                    int fetchedCount = 0;
                    TmxMap@[] extra = FilterTmxResults(more, fBase, BROWSE_BATCH, fetchedCount);
                    for (uint i = 0; i < extra.Length; i++) State::tmxBrowseCache.InsertLast(extra[i]);
                    if (fetchedCount < int(BROWSE_BATCH)) State::tmxBrowseCacheExhausted = true;
                    // Rebuild page from extended cache
                    page.RemoveRange(0, page.Length);
                    for (uint i = startIdx; i < State::tmxBrowseCache.Length && i < startIdx + pageSize; i++) {
                        page.InsertLast(State::tmxBrowseCache[i]);
                    }
                } else {
                    // Timeout or network error - mark as transient failure, not exhausted.
                    // The user can hit Search to retry; navigating to a deeper page will bounce back.
                    State::tmxBrowseCacheExtensionFailed = true;
                }
                State::searchInProgress = false;
            }

            if (page.Length == 0) {
                State::tmxFilters.CurrentPage = requestedPage - 1;
                NotifyError("No more results.");
            } else {
                page = ApplySmartIncludes(page, f, pageSize);
            }
            State::tmxSearchResults.RemoveRange(0, State::tmxSearchResults.Length);
            for (uint i = 0; i < page.Length; i++) State::tmxSearchResults.InsertLast(page[i]);
            State::tmxSelected.RemoveRange(0, State::tmxSelected.Length);
            for (uint i = 0; i < State::tmxSearchResults.Length; i++) State::tmxSelected.InsertLast(false);
            return;
        }

        // Cache miss (page 1, or fresh search): fetch first batch.
        State::searchInProgress = true;
        State::tmxBrowseCache.RemoveRange(0, State::tmxBrowseCache.Length);
        State::tmxBrowseCacheExhausted = false;
        State::tmxBrowseCacheExtensionFailed = false;

        TmxSearchFilters@ fBase = f.Clone();
        fBase.CurrentPage = 1;
        Json::Value@ json = TMX::SearchMaps(fBase, BROWSE_BATCH, 0, 0, false);
        if (json !is null) {
            int dummy = 0;
            TmxMap@[] allMaps = FilterTmxResults(json, fBase, BROWSE_BATCH, dummy);
            for (uint i = 0; i < allMaps.Length; i++) State::tmxBrowseCache.InsertLast(allMaps[i]);
            if (dummy < int(BROWSE_BATCH)) State::tmxBrowseCacheExhausted = true;
        }

        TmxMap@[] page;
        for (uint i = startIdx; i < State::tmxBrowseCache.Length && i < startIdx + pageSize; i++) {
            page.InsertLast(State::tmxBrowseCache[i]);
        }
        page = ApplySmartIncludes(page, f, pageSize);
        State::tmxSearchResults.RemoveRange(0, State::tmxSearchResults.Length);
        for (uint i = 0; i < page.Length; i++) State::tmxSearchResults.InsertLast(page[i]);
        State::tmxSelected.RemoveRange(0, State::tmxSelected.Length);
        for (uint i = 0; i < State::tmxSearchResults.Length; i++) State::tmxSelected.InsertLast(false);

        State::searchInProgress = false;
        return;
    }

    // Normal path.
    State::searchInProgress = true;

    int priorSmart = (f.CurrentPage > 1) ? CountMatchingSmartIncludes(f) : 0;
    TmxMap@[] results = FetchMapsSequential(f, pageSize, true, false, priorSmart);

    if (results.Length == 0 && requestedPage > 1) {
        State::tmxFilters.CurrentPage = requestedPage - 1;
        NotifyError("Page " + requestedPage + " timed out. Try adding a tag filter to speed up this search.");
        State::searchInProgress = false;
        return;
    }

    results = ApplySmartIncludes(results, f, pageSize);

    State::tmxSearchResults.RemoveRange(0, State::tmxSearchResults.Length);
    for (uint i = 0; i < results.Length; i++) State::tmxSearchResults.InsertLast(results[i]);
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
