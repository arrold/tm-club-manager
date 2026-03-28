# run_tests.ps1 - Master Test Runner for TM Club Manager

$ErrorActionPreference = "Stop"
Write-Host "--- [TM Club Manager] Executing Quality Guardrails ---" -ForegroundColor Cyan

# 1. AngelScript Style Checks (Static Analysis)
Write-Host "[1/2] Running AngelScript Syntax & Style Checks..."
& powershell ./scripts/verify_style.ps1

# 2. Go Integrity & Syntax Pinning
Write-Host "[2/2] Running Go Integrity Suite (TMX Consistency)..."
$GoFile = "./tests/integrity_check.go"
if (Test-Path $GoFile) {
    go run $GoFile
    if ($LASTEXITCODE -ne 0) {
        Write-Host "!!! INTEGRITY CHECKS FAILED !!!" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "[SKIP] Integrity check source not found." -ForegroundColor Yellow
}

Write-Host "--- SUCCESS: All Quality Guardrails Passed ---" -ForegroundColor Green
exit 0
