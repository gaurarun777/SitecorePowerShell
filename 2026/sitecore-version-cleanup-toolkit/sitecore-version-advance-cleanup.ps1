# --------------------------------------------------
# CONFIG
# --------------------------------------------------
$rootPath = "master:/sitecore/content/Home"
$databaseName = "master"
$versionsToKeep = 3
$dryRun = $true   # $true = report only, $false = actually delete old versions

# Replace with your actual Approved workflow state ID
$approvedWorkflowStateId = "{FCA998C5-0CC3-4F91-94D8-0A4E6CAECE88}"

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

if ([string]::IsNullOrWhiteSpace($approvedWorkflowStateId)) {
    Show-Alert "Approved workflow state ID is required."
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
$skippedNotEnoughApprovedCount = 0

foreach ($baseItem in $allItems) {

    foreach ($language in $baseItem.Languages) {

        $allVersions = @(
            Get-Item -Path $baseItem.Paths.Path -Database $database -Language $language -Version * -ErrorAction SilentlyContinue |
            Sort-Object { [int]$_.Version.Number } -Descending
        )

        if (-not $allVersions) {
            continue
        }

        $processedItemLanguageCount++

        if ($allVersions.Count -le $versionsToKeep) {
            continue
        }

        # Find approved versions only, in descending order
        $approvedVersions = @(
            $allVersions | Where-Object { $_["__Workflow state"] -eq $approvedWorkflowStateId }
        )

        # Need at least 3 approved versions to proceed
        if ($approvedVersions.Count -lt $versionsToKeep) {
            $skippedNotEnoughApprovedCount++

            $results.Add([PSCustomObject]@{
                ItemName                = $baseItem.Name
                ItemId                  = $baseItem.ID
                ItemPath                = $baseItem.Paths.Path
                Language                = $language.Name
                TotalVersions           = $allVersions.Count
                ApprovedVersionsFound   = ($approvedVersions | ForEach-Object { $_.Version.Number }) -join ", "
                VersionsKept            = ""
                VersionsDeleted         = ""
                Status                  = "Skipped - Fewer than $versionsToKeep approved versions"
            })

            continue
        }

        # Keep latest 3 approved versions
        $versionsToRetain = @($approvedVersions | Select-Object -First $versionsToKeep)

        # Delete everything else
        $retainVersionNumbers = @($versionsToRetain | ForEach-Object { [int]$_.Version.Number })
        $versionsToDelete = @(
            $allVersions | Where-Object { $retainVersionNumbers -notcontains [int]$_.Version.Number }
        )

        $matchedItemLanguageCount++

        foreach ($oldVersion in $versionsToDelete) {
            if (-not $dryRun) {
                try {
                    $oldVersion.Versions.RemoveVersion()
                    $deletedVersionCount++
                }
                catch {
                    Write-Host "Failed to delete version $($oldVersion.Version.Number) for item $($baseItem.Paths.Path) [$($language.Name)]"
                }
            }
        }

        $results.Add([PSCustomObject]@{
            ItemName                = $baseItem.Name
            ItemId                  = $baseItem.ID
            ItemPath                = $baseItem.Paths.Path
            Language                = $language.Name
            TotalVersions           = $allVersions.Count
            ApprovedVersionsFound   = ($approvedVersions | ForEach-Object { $_.Version.Number }) -join ", "
            VersionsKept            = ($versionsToRetain | ForEach-Object { $_.Version.Number }) -join ", "
            VersionsDeleted         = ($versionsToDelete | ForEach-Object { $_.Version.Number }) -join ", "
            Status                  = if ($dryRun) { "Dry Run - Ready to delete" } else { "Deleted old versions only" }
        })
    }
}

# --------------------------------------------------
# SUMMARY
# --------------------------------------------------
Write-Host "----------------------------------------"
Write-Host "Recursive Version Cleanup Summary"
Write-Host "Root Path                           : $rootPath"
Write-Host "Database                            : $databaseName"
Write-Host "Versions To Keep                    : $versionsToKeep"
Write-Host "Approved Workflow State ID          : $approvedWorkflowStateId"
Write-Host "Dry Run                             : $dryRun"
Write-Host "Items Scanned                       : $($allItems.Count)"
Write-Host "Processed Item/Languages            : $processedItemLanguageCount"
Write-Host "Matched Item/Languages              : $matchedItemLanguageCount"
Write-Host "Skipped - Not Enough Approved       : $skippedNotEnoughApprovedCount"
Write-Host "Deleted Version Count               : $deletedVersionCount"
Write-Host "----------------------------------------"

# --------------------------------------------------
# OUTPUT
# --------------------------------------------------
if ($results.Count -eq 0) {
    Show-Alert "No matching item/language versions found under '$rootPath'."
    return
}

$results | Show-ListView `
    -Property ItemName, ItemId, ItemPath, Language, TotalVersions, ApprovedVersionsFound, VersionsKept, VersionsDeleted, Status `
    -Title "Recursive Sitecore Version Cleanup Report"
