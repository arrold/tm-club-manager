# verify_style.ps1 - Developer verification script for TM Club Manager
# Checks for common pitfalls and code style consistency.

$files = Get-ChildItem -Path "src" -Filter "*.as" -Recurse

$errors = 0

foreach ($file in $files) {
    $content = Get-Content $file.FullName
    
    # 1. Check for invalid handle assignment syntax @= (common regression)
    $lineNum = 1
    foreach ($line in $content) {
        if ($line -match "@=") {
            Write-Warning "$($file.Name):$lineNum - Found '@=' syntax. Use '@handle = @object' instead for this compiler."
            $errors++
        }

        # 2. Check for invalid null comparisons (== null / != null on handles)
        # In AngelScript, these call opEquals on the object and crash if it is actually null.
        # Use 'is null' / '!is null' instead.
        if ($line -match "==\s*null" -or $line -match "!=\s*null") {
            Write-Warning "$($file.Name):$lineNum - Found '== null' or '!= null'. Use 'is null' / '!is null' for handle identity checks."
            $errors++
        }

        $lineNum++
    }
}

if ($errors -eq 0) {
    Write-Host "--- Style Check Passed ---" -ForegroundColor Green
} else {
    Write-Error "--- Style Check Failed with $errors issues ---"
    exit 1
}
