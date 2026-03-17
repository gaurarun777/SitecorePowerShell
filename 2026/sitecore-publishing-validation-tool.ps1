# --------------------------------------------
# Default values
# --------------------------------------------
$directItemPathsInput = @"

"@
 
$recursiveRootPathsInput = @"

"@
 
$languageInput = "en"
$sourceDatabaseInput = "master"
$targetDatabaseInput = "web"
 
# --------------------------------------------
# Prompt for input
# --------------------------------------------
$result = Read-Variable -Parameters @(
    @{
        Name = "directItemPathsInput"
        Title = "Direct Item Paths"
        Tooltip = "Enter one item path per line."
        Lines = 8
    },
    @{
        Name = "recursiveRootPathsInput"
        Title = "Recursive Root Paths"
        Tooltip = "Enter root paths to validate recursively."
        Lines = 8
    },
    @{
        Name = "languageInput"
        Title = "Language"
    },
    @{
        Name = "sourceDatabaseInput"
        Title = "Source Database"
    },
    @{
        Name = "targetDatabaseInput"
        Title = "Target Database"
    }
) -Title "Item Comparison Input"
 
if ($result -ne "ok") { return }
 
# --------------------------------------------
# Validate databases
# --------------------------------------------
$sourceDatabase = Get-Database $sourceDatabaseInput
$targetDatabase = Get-Database $targetDatabaseInput
 
if (-not $sourceDatabase) {
    Show-Alert "Source database '$sourceDatabaseInput' not found."
    return
}
 
if (-not $targetDatabase) {
    Show-Alert "Target database '$targetDatabaseInput' not found."
    return
}
 
# --------------------------------------------
# Parse language
# --------------------------------------------
$language = [Sitecore.Globalization.Language]::Parse($languageInput)
 
# --------------------------------------------
# Normalize paths
# --------------------------------------------
$directPaths = $directItemPathsInput -split "`r?`n" |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ }
 
$recursiveRootPaths = $recursiveRootPathsInput -split "`r?`n" |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ }
 
# --------------------------------------------
# Collect paths
# --------------------------------------------
$allPaths = New-Object System.Collections.Generic.List[string]
 
foreach ($path in $directPaths) {
    if (-not $allPaths.Contains($path)) {
        $allPaths.Add($path)
    }
}
 
foreach ($rootPath in $recursiveRootPaths) {
    if (-not $allPaths.Contains($rootPath)) {
        $allPaths.Add($rootPath)
    }
 
    $rootItem = Get-Item "${sourceDatabaseInput}:$rootPath" -Language $language -ErrorAction SilentlyContinue
 
    if ($rootItem) {
        Get-ChildItem $rootItem.ProviderPath -Recurse -Language $language -ErrorAction SilentlyContinue | ForEach-Object {
            if (-not $allPaths.Contains($_.Paths.Path)) {
                $allPaths.Add($_.Paths.Path)
            }
        }
    }
}
 
# --------------------------------------------
# Counters
# --------------------------------------------
$sourceCount = 0
$targetCount = 0
 
# --------------------------------------------
# Build results
# --------------------------------------------
$results = foreach ($path in $allPaths) {
 
    $sourceItem = Get-Item "${sourceDatabaseInput}:$path" -Language $language -ErrorAction SilentlyContinue
    $targetItem = Get-Item "${targetDatabaseInput}:$path" -Language $language -ErrorAction SilentlyContinue
 
    $sourceItemVersion = if ($sourceItem) { $sourceItem.Version } else { 0 }
    $targetItemVersion = if ($targetItem) { $targetItem.Version } else { 0 }
    if ($sourceItem) { $sourceCount++ }
    if ($targetItem) { $targetCount++ }
 
    $sourceRevision = if ($sourceItem) { $sourceItem["__Revision"] } else { "" }
    $targetRevision = if ($targetItem) { $targetItem["__Revision"] } else { "" }
 
    $sourceUpdated = if ($sourceItem) { $sourceItem["__Updated"] } else { "" }
    $targetUpdated = if ($targetItem) { $targetItem["__Updated"] } else { "" }
 
    $comparisonStatus = if (-not $sourceItem -and -not $targetItem) {
        "Missing in Both"
    }
    elseif ($sourceItem -and -not $targetItem) {
        "Missing in Target"
    }
    elseif (-not $sourceItem -and $targetItem) {
        "Missing in Source"
    }
    elseif ($sourceRevision -ne $targetRevision) {
        "Revision Mismatch"
    }
    elseif ($sourceUpdated -ne $targetUpdated) {
        "Updated Date Mismatch"
    }
    else {
        "Match"
    }
    
    #Compare version
    $versionComparisonStatus = if (-not $sourceItem -and -not $targetItem) {
        "Missing in Both"
    }
    elseif ($sourceItem -and -not $targetItem) {
        "Missing in Target"
    }
    elseif (-not $sourceItem -and $targetItem) {
        "Missing in Source"
    }
    elseif ($sourceItemVersion -ne $targetItemVersion) {
        "Version Mismatch"
    }
    else {
        "Match"
    }
 
    [PSCustomObject]@{
        Path              = $path
        ExistsInSource    = if ($sourceItem) { "Yes" } else { "No" }
        ExistsInTarget    = if ($targetItem) { "Yes" } else { "No" }
        SourceRevisionId  = $sourceRevision
        TargetRevisionId  = $targetRevision
        SourceUpdatedDate = $sourceUpdated
        TargetUpdatedDate = $targetUpdated
        ComparisonStatus  = $comparisonStatus
        VersionComparisonStatus = $versionComparisonStatus
        SourceItemVersion = $sourceItemVersion
        TargetItemVersion = $targetItemVersion
    }
}
 
# --------------------------------------------
# Log counts
# --------------------------------------------
Write-Host "----------------------------------------"
Write-Host "Database Comparison Summary"
Write-Host "Source Database : $sourceDatabaseInput"
Write-Host "Target Database : $targetDatabaseInput"
Write-Host "Items found in Source DB : $sourceCount"
Write-Host "Items found in Target DB : $targetCount"
Write-Host "----------------------------------------"
 
# --------------------------------------------
# Show results
# --------------------------------------------
$results | Show-ListView `
    -Property Path, ExistsInSource, ExistsInTarget, SourceRevisionId, TargetRevisionId, SourceUpdatedDate, TargetUpdatedDate, ComparisonStatus, VersionComparisonStatus, SourceItemVersion, TargetItemVersion `
    -Title "Item Compare Result [$sourceDatabaseInput vs $targetDatabaseInput]"
