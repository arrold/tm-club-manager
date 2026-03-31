#!/usr/bin/env bash
# run_tests.sh - Master Test Runner for TM Club Manager (Mac/Linux)

set -e

echo "--- [TM Club Manager] Executing Quality Guardrails ---"

# 1. AngelScript Style Checks (Static Analysis)
echo "[1/2] Running AngelScript Syntax & Style Checks..."
bash ./scripts/verify_style.sh

# 2. Go Integrity & Syntax Pinning
echo "[2/2] Running Go Integrity Suite (TMX Consistency)..."
GO_FILE="./tests/integrity_check.go"
if [ -f "$GO_FILE" ]; then
    go run "$GO_FILE"
else
    echo "[SKIP] Integrity check source not found."
fi

echo "--- SUCCESS: All Quality Guardrails Passed ---"
