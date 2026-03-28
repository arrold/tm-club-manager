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
