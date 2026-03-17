# --------------------------------------------------
# CONFIG
# --------------------------------------------------
$rootPath = "master:/sitecore/content/Home"
$databaseName = "master"
$versionsToKeep = 3
$dryRun = $true   # $true = report only, $false = actually delete

# --------------------------------------------------
# VALIDATION
# --------------------------------------------------
$database = Get-Database $databaseName
if (-not $database) {
    Show-Alert "Database '$databaseName' not found."
    return
}

$rootItem = Get-Item -Path $rootPath -Database $database -ErrorAction SilentlyContinue
if (-not $rootItem) {
    Show-Alert "Root path '$rootPath' not found."
    return
}

# --------------------------------------------------
# GET ROOT + ALL CHILD ITEMS RECURSIVELY
# --------------------------------------------------
$allItems = @($rootItem)

$childItems = Get-ChildItem -Path $rootItem.ProviderPath -Recurse -ErrorAction SilentlyContinue
if ($childItems) {
    $allItems += $childItems
}

# --------------------------------------------------
# PROCESS
# --------------------------------------------------
$results = New-Object System.Collections.Generic.List[object]
$deletedVersionCount = 0
$processedItemLanguageCount = 0
$matchedItemLanguageCount = 0

foreach ($baseItem in $allItems) {

    foreach ($language in $baseItem.Languages) {

        $allVersions = @(Get-Item -Path $baseItem.Paths.Path -Database $database -Language $language -Version * -ErrorAction SilentlyContinue |
            Sort-Object { [int]$_.Version.Number } -Descending)

        if (-not $allVersions) {
            continue
        }

        $processedItemLanguageCount++

        if ($allVersions.Count -le $versionsToKeep) {
            continue
        }

        $matchedItemLanguageCount++

        $versionsToRetain = @($allVersions | Select-Object -First $versionsToKeep)
        $versionsToDelete = @($allVersions | Select-Object -Skip $versionsToKeep)

        foreach ($oldVersion in $versionsToDelete) {
            if (-not $dryRun) {
                #Remove-Item -Path $oldVersion.ItemPath -Permanently -ErrorAction SilentlyContinue
                $oldVersion.Versions.RemoveVersion()
                $deletedVersionCount++
            }
        }

        $results.Add([PSCustomObject]@{
            ItemName        = $baseItem.Name
            ItemId          = $baseItem.ID
            ItemPath        = $baseItem.Paths.Path
            Language        = $language.Name
            TotalVersions   = $allVersions.Count
            VersionsKept    = ($versionsToRetain | ForEach-Object { $_.Version.Number }) -join ", "
            VersionsDeleted = ($versionsToDelete | ForEach-Object { $_.Version.Number }) -join ", "
            Status          = if ($dryRun) { "Dry Run - Ready to delete" } else { "Deleted" }
        })
    }
}

# --------------------------------------------------
# SUMMARY
# --------------------------------------------------
Write-Host "----------------------------------------"
Write-Host "Recursive Version Cleanup Summary"
Write-Host "Root Path                    : $rootPath"
Write-Host "Database                     : $databaseName"
Write-Host "Versions To Keep             : $versionsToKeep"
Write-Host "Dry Run                      : $dryRun"
Write-Host "Items Scanned                : $($allItems.Count)"
Write-Host "Processed Item/Languages     : $processedItemLanguageCount"
Write-Host "Matched Item/Languages       : $matchedItemLanguageCount"
Write-Host "Deleted Version Count        : $deletedVersionCount"
Write-Host "----------------------------------------"

# --------------------------------------------------
# OUTPUT
# --------------------------------------------------
if ($results.Count -eq 0) {
    Show-Alert "No item/language versions found with more than $versionsToKeep versions under '$rootPath'."
    return
}

$results | Show-ListView `
    -Property ItemName, ItemId, ItemPath, Language, TotalVersions, VersionsKept, VersionsDeleted, Status `
    -Title "Recursive Sitecore Version Cleanup Report"
