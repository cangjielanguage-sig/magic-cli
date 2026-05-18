# line-stats.ps1 — reports line count for each .cj file in src/replay/
Get-ChildItem src\replay\*.cj | ForEach-Object {
    $lines = (Get-Content $_.FullName).Count
    "$($_.Name): $lines lines"
} | Sort-Object


