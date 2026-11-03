<#
.SYNOPSIS
    Finds pages (items with a layout) that reference a given link, either in
    page-level fields or in fields of datasource items used by the page's renderings.

.NOTES
    Run in Sitecore PowerShell Extensions (ISE or as a script in the Script Library).
    Edit the CONFIG block below, then run.
#>

# ============================== CONFIG ==============================
$Link                = "/sitecore/content/Sitecore/SXA201/Home/Search"  # media link, internal link/path/GUID, or external URL
$RootPath            = "/sitecore/content/Sitecore/SXA201/Home"                       # starting item path (or GUID)
$IncludeDescendants  = $true                                                     # $true = root + all descendants, $false = root item only
$Languages           = @("en", "fr", "en-CA")                                    # language codes to check
$DatabaseName        = "master"
$ExportCsv           = $false                                                    # $true = also write CSV to the Sitecore data folder
# ====================================================================

$db = [Sitecore.Configuration.Factory]::GetDatabase($DatabaseName)

# ---------------------------------------------------------------------
# 1. Build the set of strings to look for
# ---------------------------------------------------------------------
$variants = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$Link = $Link.Trim()
[void]$variants.Add($Link)
[void]$variants.Add([System.Net.WebUtility]::HtmlEncode($Link))   # link/rich text XML stores & as &amp;

$guidRegex   = '[0-9a-fA-F]{8}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{12}'
$mediaMarker = '(/-/media/|~/media/)'
$isExternal  = $Link -match '^https?://' -and $Link -notmatch $mediaMarker
$linkedItem  = $null

function Add-GuidVariants([guid]$g) {
    [void]$variants.Add($g.ToString("B"))   # {xxxxxxxx-xxxx-...}
    [void]$variants.Add($g.ToString("D"))   # xxxxxxxx-xxxx-...
    [void]$variants.Add($g.ToString("N"))   # 32 hex chars (used in /-/media/<id>.ashx)
}

if (-not $isExternal) {
    # GUID embedded in the supplied link
    $m = [regex]::Match($Link, $guidRegex)
    if ($m.Success) {
        $g = [guid]::Empty
        if ([guid]::TryParse($m.Value, [ref]$g)) {
            Add-GuidVariants $g
            $linkedItem = $db.GetItem([Sitecore.Data.ID]::Parse($g))
        }
    }

    # Sitecore path supplied (/sitecore/...)
    if (-not $linkedItem -and $Link -match '^/sitecore/') {
        $linkedItem = $db.GetItem($Link)
    }

    # Friendly media URL: /-/media/Project/x/file.ashx -> media library path (best effort)
    if (-not $linkedItem -and $Link -match $mediaMarker) {
        $mediaPart = ($Link -split $mediaMarker, 2)[2]
        $mediaPart = ($mediaPart -split '[?#]')[0]
        $mediaPart = [System.IO.Path]::ChangeExtension($mediaPart, $null).TrimEnd('.')
        $linkedItem = $db.GetItem("/sitecore/media library/$mediaPart")
    }

    if ($linkedItem) {
        Add-GuidVariants $linkedItem.ID.Guid
        [void]$variants.Add($linkedItem.Paths.FullPath)
    }
}

Write-Host "Searching for any of these values:" -ForegroundColor Cyan
$variants | ForEach-Object { Write-Host "  $_" }

# ---------------------------------------------------------------------
# 2. Helpers
# ---------------------------------------------------------------------
$devices = @(Get-ChildItem -Path "$($DatabaseName):/sitecore/layout/Devices" -Recurse |
             Where-Object { $_.TemplateName -eq "Device" })

function Test-HasLayout($item) {
    foreach ($d in $devices) {
        try { if ($item.Visualization.GetLayout($d)) { return $true } } catch {}
        try {
            if (Get-Rendering -Item $item -Device $d -FinalLayout -ErrorAction SilentlyContinue) { return $true }
            if (Get-Rendering -Item $item -Device $d -ErrorAction SilentlyContinue) { return $true }
        } catch {}
    }
    return $false
}

function Get-FieldMatches($item) {
    # Returns names of non-system fields whose value contains any variant
    $found = @()
    $item.Fields.ReadAll()
    foreach ($f in $item.Fields) {
        if ($f.Name.StartsWith("__")) { continue }
        $val = $f.Value
        if ([string]::IsNullOrEmpty($val)) { continue }
        foreach ($v in $variants) {
            if ($val.IndexOf($v, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $found += $f.Name
                break
            }
        }
    }
    return $found
}

function Get-Datasources($item) {
    $list = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($d in $devices) {
        $renderings = @()
        try { $renderings += Get-Rendering -Item $item -Device $d -FinalLayout -ErrorAction SilentlyContinue } catch {}
        try { $renderings += Get-Rendering -Item $item -Device $d -ErrorAction SilentlyContinue } catch {}
        foreach ($r in $renderings) {
            if ($r -and -not [string]::IsNullOrWhiteSpace($r.Datasource)) { [void]$list.Add($r.Datasource.Trim()) }
        }
    }
    return $list
}

function Resolve-Datasource([string]$ds, $page, $langObj) {
    $g = [guid]::Empty
    if ($ds -like "local:*") {
        return $db.GetItem($page.Paths.FullPath + $ds.Substring(6), $langObj)
    }
    elseif ([guid]::TryParse($ds, [ref]$g)) {
        return $db.GetItem([Sitecore.Data.ID]::Parse($g), $langObj)
    }
    elseif ($ds.StartsWith("/")) {
        return $db.GetItem($ds, $langObj)
    }
    return $null   # query: / other formats not supported
}

# ---------------------------------------------------------------------
# 3. Collect items in scope
# ---------------------------------------------------------------------
$rootItem = $null
$gTmp = [guid]::Empty
if ([guid]::TryParse($RootPath, [ref]$gTmp)) { $rootItem = $db.GetItem([Sitecore.Data.ID]::Parse($gTmp)) }
else { $rootItem = $db.GetItem($RootPath) }

if (-not $rootItem) {
    Show-Alert "Root item '$RootPath' not found in '$DatabaseName'."
    return
}

$scopeIds = New-Object System.Collections.Generic.List[Sitecore.Data.ID]
$scopeIds.Add($rootItem.ID)
if ($IncludeDescendants) {
    foreach ($d in $rootItem.Axes.GetDescendants()) { $scopeIds.Add($d.ID) }
}
Write-Host "Items in scope: $($scopeIds.Count)" -ForegroundColor Cyan

# ---------------------------------------------------------------------
# 4. Scan
# ---------------------------------------------------------------------
$report        = New-Object System.Collections.Generic.List[object]
$dsCache       = @{}   # "id|lang" -> matching field names
$skippedDs     = 0

foreach ($lang in $Languages) {
    $langObj = $null
    try { $langObj = [Sitecore.Globalization.Language]::Parse($lang) } catch {
        Write-Host "Invalid language code '$lang' - skipped." -ForegroundColor Yellow
        continue
    }
    Write-Host "Language: $lang" -ForegroundColor Cyan

    foreach ($id in $scopeIds) {
        $page = $db.GetItem($id, $langObj)
        if (-not $page -or $page.Versions.Count -eq 0) { continue }   # no version in this language
        if (-not (Test-HasLayout $page)) { continue }                 # folder-like / structural item

        # ---- page-level fields ----
        foreach ($fieldName in (Get-FieldMatches $page)) {
            $report.Add([PSCustomObject]@{
                "Page ID"         = $page.ID.ToString()
                "Page Name"       = $page.Name
                "Page Path"       = $page.Paths.FullPath
                "Language"        = $page.Language.Name
                "Version"         = $page.Version.Number
                "Found In"        = "Page field"
                "Field Name"      = $fieldName
                "Datasource Path" = ""
                "Datasource ID"   = ""
            })
        }

        # ---- datasource items from presentation ----
        foreach ($ds in (Get-Datasources $page)) {
            $dsItem = Resolve-Datasource $ds $page $langObj
            if (-not $dsItem) { $skippedDs++; continue }
            if ($dsItem.Versions.Count -eq 0) { continue }

            $key = "$($dsItem.ID)|$lang"
            if (-not $dsCache.ContainsKey($key)) { $dsCache[$key] = @(Get-FieldMatches $dsItem) }

            foreach ($fieldName in $dsCache[$key]) {
                $report.Add([PSCustomObject]@{
                    "Page ID"         = $page.ID.ToString()
                    "Page Name"       = $page.Name
                    "Page Path"       = $page.Paths.FullPath
                    "Language"        = $page.Language.Name
                    "Version"         = $page.Version.Number
                    "Found In"        = "Datasource"
                    "Field Name"      = $fieldName
                    "Datasource Path" = $dsItem.Paths.FullPath
                    "Datasource ID"   = $dsItem.ID.ToString()
                })
            }
        }
    }
}

# ---------------------------------------------------------------------
# 5. Output
# ---------------------------------------------------------------------
$uniquePages = $report | Select-Object -ExpandProperty "Page ID" -Unique
Write-Host ""
Write-Host "Matches: $($report.Count) | Unique pages: $(@($uniquePages).Count)" -ForegroundColor Green
if ($skippedDs -gt 0) {
    Write-Host "Skipped $skippedDs datasource value(s) that could not be resolved (e.g. query: datasources)." -ForegroundColor Yellow
}

if ($ExportCsv -and $report.Count -gt 0) {
    $csvPath = Join-Path $SitecoreDataFolder ("LinkUsage_{0}.csv" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
    $report | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
    Write-Host "CSV written to $csvPath" -ForegroundColor Green
}

if ($report.Count -gt 0) {
    $report | Show-ListView -Title "Link usage: $Link" -Property `
        "Page ID", "Page Name", "Page Path", "Language", "Version", "Found In", "Field Name", "Datasource Path", "Datasource ID"
}
else {
    Show-Alert "No pages found referencing the supplied link."
}
