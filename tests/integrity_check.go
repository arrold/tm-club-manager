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

	// 4. Handle-Based Memory Management (Regression Prevention)
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
