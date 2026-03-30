package main

import (
	"fmt"
	"os"
	"strings"
)

func main() {
	fmt.Println("--- [TM Club Manager] Starting Go Integrity Verification ---")

	errors := 0

	// 1. TMX Nested Author Parsing (Syntax Pinning)
	// We MUST check for a["User"]["Name"] to ensure collaborator maps are not silently filtered.
	if !checkFileContains("src/Models.as", `a["User"]["Name"]`) {
		fmt.Println("[FAIL] src/Models.as: Missing nested Author parsing (a[\"User\"][\"Name\"]). Collaborators will be broken!")
		errors++
	}

	// 2. TMX Sort Indices Consistency
	// Awards Most must be index 12 in TMX V1.
	if !checkFileContains("src/API/TMX.as", "case 0:  return 12;") {
		fmt.Println("[FAIL] src/API/TMX.as: Awards Most (case 0) is not correctly mapped to Key 12.")
		errors++
	}
	if !checkFileContains("src/API/TMX.as", "case 1:  return 11;") {
		fmt.Println("[FAIL] src/API/TMX.as: Awards Least (case 1) is not correctly mapped to Key 11.")
		errors++
	}

	// 3. UI Constants
	if !checkFileContains("src/Models.as", `"Awards Least"`) {
		fmt.Println("[FAIL] src/Models.as: 'Awards Least' missing from SORT_NAMES.")
		errors++
	}

	// 4. TMX Search Filters & UI Elements (Pinning critical features)
	
	// Map Name & Author
	if !checkFileContains("src/Models.as", "string MapName = \"\";") {
		fmt.Println("[FAIL] TmxSearchFilters: Missing MapName field")
		errors++
	}
	if !checkFileContains("src/Models.as", "string[] AuthorNames = {};") {
		fmt.Println("[FAIL] TmxSearchFilters: Missing AuthorNames field")
		errors++
	}

	// Difficulties (6)
	if !checkFileContains("src/Models.as", "bool[] Difficulties = { false, false, false, false, false, false };") {
		fmt.Println("[FAIL] TmxSearchFilters: Missing or malformed Difficulties array (expects 6)")
		errors++
	}

	// Sorting Options (10)
	if !checkFileContains("src/API/TMX.as", "case 9:  return 2;  // Name Z-A") {
		fmt.Println("[FAIL] TMX API: Missing 10th sorting option (Name Z-A)")
		errors++
	}

	// Primary Tag & Surface
	if !checkFileContains("src/Models.as", "bool PrimaryTagOnly = false;") {
		fmt.Println("[FAIL] TmxSearchFilters: Missing PrimaryTagOnly toggle")
		errors++
	}
	if !checkFileContains("src/Models.as", "bool PrimarySurfaceOnly = false;") {
		fmt.Println("[FAIL] TmxSearchFilters: Missing PrimarySurfaceOnly toggle")
		errors++
	}

	// Room Guardrails
	if !checkFileContains("src/Models.as", "uint DisplayCostLimit = 10000;") {
		fmt.Println("[FAIL] TmxSearchFilters: Missing Room Guardrails (DisplayCostLimit)")
		errors++
	}

	// Upload Date Range & Author Time Range
	if !checkFileContains("src/Models.as", "string UploadedFrom = \"\";") || !checkFileContains("src/Models.as", "string UploadedTo = \"\";") {
		fmt.Println("[FAIL] TmxSearchFilters: Missing UploadDateRange fields")
		errors++
	}
	if !checkFileContains("src/Models.as", "uint TimeFromMs = 0;") || !checkFileContains("src/Models.as", "uint TimeToMs = 0;") {
		fmt.Println("[FAIL] TmxSearchFilters: Missing AuthorTimeRange fields")
		errors++
	}

	// UI Strings in CurationTab
	if !checkFileContains("src/Tabs/CurationTab.as", `Icons::Tag + " Primary Tag"`) {
		fmt.Println("[FAIL] src/Tabs/CurationTab.as: Missing 'Primary Tag' UI button")
		errors++
	}
	if !checkFileContains("src/Tabs/CurationTab.as", `Icons::Leaf + " Primary Surface"`) {
		fmt.Println("[FAIL] src/Tabs/CurationTab.as: Missing 'Primary Surface' UI button")
		errors++
	}
	if !checkFileContains("src/Tabs/CurationTab.as", `Icons::ExclamationTriangle + " Room Guardrails: "`) {
		fmt.Println("[FAIL] src/Tabs/CurationTab.as: Missing 'Room Guardrails' UI label")
		errors++
	}

	// 5. Handle-Based Memory Management (Regression Prevention)
	// Ensuring common collections use @Handles
	if !checkFileContains("src/Models.as", "TmxMap@[]") && !checkFileContains("src/Logic/TmxCuration.as", "TmxMap@[]") {
		fmt.Println("[FAIL] Handle regression: TmxMap collections should use @[] handles.")
		errors++
	}
	if !checkFileContains("src/Models.as", "MapInfo@[] Maps;") {
		fmt.Println("[FAIL] Handle regression: Activity.Maps should be a handle array (MapInfo@[]). Object slicing risk!")
		errors++
	}

	// 6. Mirrored Room Write Protection
	// Mirrored rooms must never be written to directly — their map list is owned by the source campaign.
	if !checkFileContains("src/Logic/TmxCuration.as", "MirrorCampaignId > 0") {
		fmt.Println("[FAIL] TmxCuration.as: Missing mirrored room write guard. Mirrored rooms can be silently overwritten!")
		errors++
	}
	if !checkFileContains("src/Tabs/CurationTab.as", "MirrorCampaignId > 0") {
		fmt.Println("[FAIL] CurationTab.as: Mirrored rooms are not excluded from the Target Activity dropdown!")
		errors++
	}

	// 7. Room Guardrail Thresholds
	// These specific numbers define Red/Yellow warning bands. They must not drift.
	if !checkFileContains("src/Logic/TmxCuration.as", "DisplayCost > 12000") {
		fmt.Println("[FAIL] TmxCuration.as: Red guardrail threshold (DisplayCost > 12000) is missing or changed.")
		errors++
	}
	if !checkFileContains("src/Logic/TmxCuration.as", "EmbeddedItemsSize > 4000000") {
		fmt.Println("[FAIL] TmxCuration.as: Red guardrail threshold (EmbeddedItemsSize > 4000000) is missing or changed.")
		errors++
	}

	// 8. Activity Capacity Limits
	// Nadeo hard limits: 25 maps for campaigns, 100 maps for rooms.
	if !checkFileContains("src/Logic/TmxCuration.as", "toAdd.Length > 25") {
		fmt.Println("[FAIL] TmxCuration.as: Campaign capacity limit check (25) is missing.")
		errors++
	}
	if !checkFileContains("src/Logic/TmxCuration.as", "toAdd.Length > 100") {
		fmt.Println("[FAIL] TmxCuration.as: Room capacity limit check (100) is missing.")
		errors++
	}

	// 9. Denylist Integration in FilterTmxResults
	// If this call is removed, maps on the denylist silently reappear in all search results.
	if !checkFileContains("src/Logic/TmxCuration.as", "Denylist::IsExcluded(m.Uid)") {
		fmt.Println("[FAIL] TmxCuration.as: Denylist check missing from FilterTmxResults. Excluded maps will appear in search results!")
		errors++
	}

	// 10. Tag Cycle UI (None -> Include -> Exclude -> None)
	// This three-state cycle is unique to this plugin and explicitly documented as fragile.
	if !checkFileContains("src/Tabs/CurationTab.as", "Click: Include > Exclude > None") {
		fmt.Println("[FAIL] CurationTab.as: Tag cycle header label missing. The three-state tag logic may have been broken.")
		errors++
	}

	// 11. CurrentPage included in subscription diff check
	// Without this, importing a config with CurrentPage:2 on an existing subscription with
	// CurrentPage:1 will be silently ignored — page-2+ campaigns will show the same maps as page 1.
	if !checkFileContains("src/Models.as", "CurrentPage != other.CurrentPage") {
		fmt.Println("[FAIL] Models.as: CurrentPage missing from GetDifference. Page-2+ subscription changes will be silently ignored on import.")
		errors++
	}

	// 12. ExportFolder must emit type=folder
	// Without this, sub-folders in the exported config have no type field and the importer
	// skips them entirely — no sub-folders will be created.
	if !checkFileContains("src/Logic/ConfigExporter.as", `json["type"] = "folder"`) {
		fmt.Println("[FAIL] ConfigExporter.as: ExportFolder must emit type=folder. Sub-folders will be silently skipped on import.")
		errors++
	}

	// 13. Activity ID extracted from raw response before JsonDeepExtract
	// JsonDeepExtract can return a campaign sub-object whose "id" is the campaign resource ID,
	// not the activity ID. Subscriptions saved with the wrong ID are never found on export.
	if !checkFileContains("src/Logic/ConfigImporter.as", `JsonGetUint(resp, "activityId")`) {
		fmt.Println("[FAIL] ConfigImporter.as: Activity ID must be read from raw response before JsonDeepExtract. Campaign subscriptions will be saved with wrong ID.")
		errors++
	}

	// 14. Campaign activation workaround (SetActivityStatus after SyncActivityMetadata)
	// Nadeo always creates campaigns inactive. The workaround must run AFTER SyncActivityMetadata
	// or the metadata edit will overwrite active=true back to false.
	if !checkFileContains("src/Logic/ConfigImporter.as", "Nadeo API bug workaround") {
		fmt.Println("[FAIL] ConfigImporter.as: Campaign activation workaround missing or comment removed. New campaigns will always be created inactive.")
		errors++
	}

	// 15. Two-pass position assignment in importer
	// Setting positions directly causes conflicts when a target slot is already occupied by
	// another item, cascading into wrong ordering. Pass 1 must move to temp positions first.
	if !checkFileContains("src/Logic/ConfigImporter.as", "ApplyPendingPositions") {
		fmt.Println("[FAIL] ConfigImporter.as: Two-pass position assignment missing. Positions will conflict and ordering will be scrambled during import.")
		errors++
	}
	if !checkFileContains("src/Logic/ConfigImporter.as", "const uint tempBase = 500") {
		fmt.Println("[FAIL] ConfigImporter.as: Temp position base should be 500 (not 10000 or other). Keeps positions in 3-digit range.")
		errors++
	}
	if !checkFileContains("src/Logic/ConfigImporter.as", "tempBase + i") {
		fmt.Println("[FAIL] ConfigImporter.as: Pass 1 (temp position relocation) missing from ApplyPendingPositions.")
		errors++
	}

	// 16. Slow-combo batchSize=100 in FetchMapsSequential
	// For Awards Most + Not TOTD searches, a small batch size causes a second page fetch which
	// times out, resulting in audit removals with no additions.
	if !checkFileContains("src/Logic/TmxCuration.as", "isSlowCombo ? 100") {
		fmt.Println("[FAIL] TmxCuration.as: Slow combo batchSize=100 missing. Not-TOTD audits will time out on page 2, removing maps without replacements.")
		errors++
	}

	if errors == 0 {
		fmt.Println("--- [TM Club Manager] ALL INTEGRITY CHECKS PASSED ---")
		os.Exit(0)
	} else {
		fmt.Printf("--- [TM Club Manager] VERIFICATION FAILED with %d issues ---\n", errors)
		os.Exit(1)
	}
}

func checkFileContains(path, search string) bool {
	content, err := os.ReadFile(path)
	if err != nil {
		fmt.Printf("Error reading %s: %v\n", path, err)
		return false
	}
	return strings.Contains(string(content), search)
}
