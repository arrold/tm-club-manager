// Club Manager - Testing.as
// Developer-only verification framework.
//
// HOW TO USE:
// 1. Open the Openplanet console (tilde or F3 by default).
// 2. To run regression tests: Type "Testing::RunAll()" and press Enter.

namespace Testing {
    void Init() {
        // Reserved for future setup
    }

    void RunAll() {
        print("--- [TM Club Manager] Running Tests ---");
        
        bool ok = true;
        if (!Test_TmxSearchFilters_Serialization()) ok = false;
        if (!Test_MetadataOverride_SetGet()) ok = false;
        if (!Test_SortMaps_Logic()) ok = false;
        
        if (ok) {
            print("--- [TM Club Manager] ALL TESTS PASSED ---");
        } else {
            warn("--- [TM Club Manager] SOME TESTS FAILED ---");
        }
    }

    // Syncing of Metadata Names is now automated at startup in Main.as

    bool Test_TmxSearchFilters_Serialization() {
        TmxSearchFilters f;
        f.SortPrimary = 0; // Awards Most
        f.SortSecondary = 8; // Newest
        f.InTOTD = 1;
        f.AuthorNames.InsertLast("Arrold");
        
        Json::Value@ json = f.ToJson();
        
        // Verify string-based sorts
        if (JsonGetString(json, "SortPrimary") != "Awards Most") {
            warn("[Test] Failed: SortPrimary serialization should be 'Awards Most', got: " + JsonGetString(json, "SortPrimary"));
            return false;
        }
        if (JsonGetString(json, "SortSecondary") != "Newest") {
            warn("[Test] Failed: SortSecondary serialization should be 'Newest', got: " + JsonGetString(json, "SortSecondary"));
            return false;
        }

        // Verify Efficiency: A default field (like Vehicle) should NOT be in the JSON
        if (json.HasKey("Vehicle")) {
            warn("[Test] Failed: Efficiency check - 'Vehicle' should not be present in JSON if default.");
            return false;
        }

        // Round trip
        TmxSearchFilters f2(json);
        if (f2.SortPrimary != 0 || f2.SortSecondary != 8 || f2.InTOTD != 1) {
            warn("[Test] Failed: Round-trip serialization indices mismatch.");
            return false;
        }
        
        print("[Test] TmxSearchFilters Serialization (Efficient): OK");
        return true;
    }

    bool Test_MetadataOverride_SetGet() {
        string uid = "TEST_UID_123";
        MetadataOverrides::SetName(uid, "Test Map Name");
        
        // Ensure it's in the underlying data JSON
        if (!MetadataOverrides::data.HasKey(uid)) {
            warn("[Test] Failed: MetadataOverride name not in data JSON.");
            return false;
        }
        
        Json::Value@ ovr = MetadataOverrides::data[uid];
        if (JsonGetString(ovr, "Name") != "Test Map Name") {
            warn("[Test] Failed: MetadataOverride name mismatch in JSON. Got: " + JsonGetString(ovr, "Name"));
            return false;
        }
        
        print("[Test] MetadataOverride Persistence Logic: OK");
        return true;
    }

    bool Test_SortMaps_Logic() {
        TmxMap@[] maps;
        
        TmxMap@ m1 = TmxMap(); m1.TrackId = 1; m1.AwardCount = 10; m1.Name = "B"; m1.UploadedAt = "1000";
        TmxMap@ m2 = TmxMap(); m2.TrackId = 2; m2.AwardCount = 20; m2.Name = "A"; m2.UploadedAt = "2000";
        TmxMap@ m3 = TmxMap(); m3.TrackId = 3; m3.AwardCount = 10; m3.Name = "C"; m3.UploadedAt = "3000";
        
        maps.InsertLast(m1);
        maps.InsertLast(m2);
        maps.InsertLast(m3);
        
        // Sort by Awards Most (Primary), then Newest (Secondary)
        SortMaps(maps, 0, 8); 
        
        // Expected order: m2 (20 awards), m3 (10 awards, 3000 uploaded), m1 (10 awards, 1000 uploaded)
        if (maps[0].TrackId != 2 || maps[1].TrackId != 3 || maps[2].TrackId != 1) {
            warn("[Test] Failed: SortMaps result order incorrect. Got: " + maps[0].TrackId + ", " + maps[1].TrackId + ", " + maps[2].TrackId);
            return false;
        }
        
        print("[Test] SortMaps (Multi-level): OK");
        return true;
    }

    void Probe_Mapsearch2() {
        // Try both common URL patterns — one will 404, one should respond
        string[] candidates = {
            "https://trackmania.exchange/mapsearch2?count=1",
            "https://trackmania.exchange/api/mapsearch2?count=1",
            "https://trackmania.exchange/api/maps/search2?count=1"
        };

        for (uint c = 0; c < candidates.Length; c++) {
            string url = candidates[c];
            trace("[Probe] Trying: " + url);
            Net::HttpRequest@ req = Net::HttpRequest();
            req.Url = url;
            req.Headers["User-Agent"] = "TM_Plugin:ClubManager / contact=Arrold";
            req.Headers["Accept"] = "application/json";
            req.Method = Net::HttpMethod::Get;
            req.Start();
            uint64 start = Time::Now;
            while (!req.Finished()) {
                if (Time::Now > start + 10000) { req.Cancel(); trace("[Probe] Timed out: " + url); break; }
                yield();
            }
            if (!req.Finished()) continue;

            int code = req.ResponseCode();
            trace("[Probe] HTTP " + code + " for: " + url);
            if (code == 404 || code == 405) continue;

            // Got a real response — log the schema
            trace("[Probe] === mapsearch2 response (status " + code + ") ===");
            string body = req.String();
            trace("[Probe] Raw body (first 500 chars): " + body.SubStr(0, 500));

            Json::Value@ json = req.Json();
            if (json is null) { trace("[Probe] Failed to parse JSON."); continue; }

            // Find the results array
            Json::Value@ results = null;
            string[] topKeys = json.GetKeys();
            trace("[Probe] Top-level keys: " + string::Join(topKeys, ", "));
            for (uint i = 0; i < topKeys.Length; i++) {
                if (json[topKeys[i]].GetType() == Json::Type::Array && json[topKeys[i]].Length > 0) {
                    @results = json[topKeys[i]];
                    trace("[Probe] Results array found under key: '" + topKeys[i] + "' (" + results.Length + " entries)");
                    break;
                }
            }
            if (results is null && json.GetType() == Json::Type::Array && json.Length > 0) {
                @results = json;
                trace("[Probe] Response is a top-level array (" + results.Length + " entries)");
            }

            if (results !is null && results.Length > 0) {
                Json::Value@ first = results[0];
                string[] fields = first.GetKeys();
                trace("[Probe] Fields on first result (" + fields.Length + " total): " + string::Join(fields, ", "));

                // Specifically hunt for anything TOTD-related
                bool foundTotd = false;
                for (uint i = 0; i < fields.Length; i++) {
                    string k = fields[i].ToLower();
                    if (k.Contains("totd") || k.Contains("intotd") || k.Contains("totd")) {
                        trace("[Probe] *** TOTD field found: '" + fields[i] + "' = " + Json::Write(first[fields[i]]));
                        foundTotd = true;
                    }
                }
                if (!foundTotd) trace("[Probe] No TOTD-related field found in first result.");

                // Log a few key fields to confirm schema shape
                string[] interesting = {"id", "trackid", "mapid", "uid", "mapuid", "name", "difficulty", "awards", "awardcount"};
                for (uint i = 0; i < interesting.Length; i++) {
                    for (uint j = 0; j < fields.Length; j++) {
                        if (fields[j].ToLower() == interesting[i]) {
                            trace("[Probe] Schema: '" + fields[j] + "' = " + Json::Write(first[fields[j]]));
                        }
                    }
                }
            }
            trace("[Probe] === end mapsearch2 probe ===");
            return; // Stop after first successful response
        }
        trace("[Probe] All mapsearch2 URL candidates failed or timed out.");
    }
}
