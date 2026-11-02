<#
.SYNOPSIS
    Extracts all links from a page item and from every datasource item used by
    that page's renderings. Optionally does the same for ALL descendants of the
    given item (not only direct children), fetched with Sitecore Fast Query.
    Results are shown in Show-ListView.

.NOTES
    Run in SPE ISE. Set the settings below and run.
    Covers: General Link, Internal Link, Droplink, Droptree, Multilist/Treelist
    variants, Image, File and Rich Text (href/src, ~/link.aspx, ~/media, <link id>).
#>

# ------------------------- Settings -------------------------
$pagePath                  = "/sitecore/content/Home"   # root item path
$pageId                    = ""                         # optional GUID, overrides $pagePath
$database                  = "master"
$language                  = "en"

$includeAllDescendants     = $true    # $true = root + ALL descendants (Fast Query), $false = root only
$pagesOnly                 = $true    # $true = only descendants that have presentation (real pages)
                                      # $false = scan every descendant item
$includeDatasourceChildren = $false   # also scan descendants of each datasource item (e.g. folders)
# ------------------------------------------------------------

$db   = [Sitecore.Configuration.Factory]::GetDatabase($database)
$lang = [Sitecore.Globalization.Language]::Parse($language)

if ($pageId) { $root = Get-Item -Path "$($database):" -ID $pageId -Language $language }
else         { $root = Get-Item -Path "$($database):$pagePath" -Language $language }

if (-not $root) {
    Show-Alert "Item not found."
    return
}

$results = New-Object System.Collections.Generic.List[object]
$currentPage = $null

# ---------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------

# Fast Query needs segments with spaces, dashes etc. wrapped in #...#
function ConvertTo-FastPath {
    param([string]$Path)

    $segments = $Path.Trim("/") -split "/"
    $out = foreach ($seg in $segments) {
        if ($seg -match '^\w+$') { $seg } else { "#$seg#" }
    }
    return "/" + ($out -join "/")
}

function Add-Result {
    param(
        $Scope,
        $Item,
        $Field,
        [string]$LinkType,
        [string]$Target = "",
        [string]$TargetId = "",
        $TargetItem = $null,
        [switch]$NonItem        # external url, mailto, anchor, javascript
    )

    if ($NonItem) {
        $exists = "n/a"
    }
    else {
        if ($TargetItem) {
            $exists = $true
            $Target = $TargetItem.Paths.FullPath
        }
        else {
            $exists = $false
            $Target = "[missing] $TargetId"
        }
    }

    $row = [PSCustomObject]@{
        Page         = $currentPage.Paths.FullPath
        Scope        = $Scope
        SourceItem   = $Item.Paths.FullPath
        SourceId     = $Item.ID.ToString()
        Field        = $Field.Name
        FieldType    = $Field.Type
        LinkType     = $LinkType
        Target       = $Target
        TargetId     = $TargetId
        TargetExists = $exists
    }
    $results.Add($row)
}

function Resolve-IdValue {
    param([string]$Value)

    $guid = [guid]::Empty
    if ([guid]::TryParse($Value, [ref]$guid)) {
        return $db.GetItem($guid.ToString("B"), $lang)
    }
    return $null
}

function Get-LinksFromItem {
    param($Item, [string]$Scope)

    $Item.Fields.ReadAll()

    foreach ($field in $Item.Fields) {
        if ($field.Name.StartsWith("__")) { continue }   # skip standard fields
        if (-not $field.HasValue)         { continue }

        $type = $field.Type

        if ($type -like "General Link*") {
            $lf = [Sitecore.Data.Fields.LinkField]$field
            $lt = $lf.LinkType
            if ([string]::IsNullOrEmpty($lt)) { continue }

            if ($lt -eq "internal" -or $lt -eq "media") {
                Add-Result -Scope $Scope -Item $Item -Field $field -LinkType $lt -TargetId $lf.TargetID.ToString() -TargetItem $lf.TargetItem
            }
            elseif ($lt -eq "anchor") {
                Add-Result -Scope $Scope -Item $Item -Field $field -LinkType $lt -Target $lf.Anchor -NonItem
            }
            else {
                Add-Result -Scope $Scope -Item $Item -Field $field -LinkType $lt -Target $lf.Url -NonItem
            }
        }
        elseif ("Internal Link","Droplink","Droptree","Lookup","Reference","Grouped Droplink" -contains $type) {
            $t = Resolve-IdValue $field.Value
            Add-Result -Scope $Scope -Item $Item -Field $field -LinkType "reference" -TargetId $field.Value -TargetItem $t
        }
        elseif ("Multilist","Multilist with Search","Treelist","Treelist with Search","TreelistEx","Checklist","Tree List" -contains $type) {
            $ids = $field.Value -split "\|" | Where-Object { $_ }
            foreach ($id in $ids) {
                $t = Resolve-IdValue $id
                Add-Result -Scope $Scope -Item $Item -Field $field -LinkType "reference" -TargetId $id -TargetItem $t
            }
        }
        elseif ($type -eq "Image") {
            $img = [Sitecore.Data.Fields.ImageField]$field
            if ($img.MediaID -and $img.MediaID -ne [Sitecore.Data.ID]::Null) {
                Add-Result -Scope $Scope -Item $Item -Field $field -LinkType "media" -TargetId $img.MediaID.ToString() -TargetItem $img.MediaItem
            }
        }
        elseif ($type -eq "File") {
            $file = [Sitecore.Data.Fields.FileField]$field
            if ($file.MediaID -and $file.MediaID -ne [Sitecore.Data.ID]::Null) {
                Add-Result -Scope $Scope -Item $Item -Field $field -LinkType "media" -TargetId $file.MediaID.ToString() -TargetItem $file.MediaItem
            }
        }
        elseif ($type -eq "Rich Text") {
            $html = $field.Value

            $attrPattern = '(?i)\b(?:href|src)\s*=\s*["'']([^"'']+)["'']'
            $idPattern   = '(?i)(?:_id=|/media/)\{?([0-9a-f]{32}|[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12})\}?'

            foreach ($match in [regex]::Matches($html, $attrPattern)) {
                $url = $match.Groups[1].Value
                $m   = [regex]::Match($url, $idPattern)

                if ($m.Success) {
                    $raw = $m.Groups[1].Value
                    if ($raw.Length -eq 32) { $raw = [guid]::Parse($raw).ToString() }
                    $t  = Resolve-IdValue $raw
                    $lt = "internal"
                    if ($url -match "(?i)/media/") { $lt = "media" }
                    Add-Result -Scope $Scope -Item $Item -Field $field -LinkType $lt -TargetId $raw -TargetItem $t
                }
                elseif ($url -match "(?i)^mailto:")     { Add-Result -Scope $Scope -Item $Item -Field $field -LinkType "mailto"     -Target $url -NonItem }
                elseif ($url -match "^#")               { Add-Result -Scope $Scope -Item $Item -Field $field -LinkType "anchor"     -Target $url -NonItem }
                elseif ($url -match "(?i)^javascript:") { Add-Result -Scope $Scope -Item $Item -Field $field -LinkType "javascript" -Target $url -NonItem }
                else                                    { Add-Result -Scope $Scope -Item $Item -Field $field -LinkType "url"        -Target $url -NonItem }
            }

            # Link-manager style: <link linktype="internal" id="{GUID}" />
            $linkPattern = '(?i)<link[^>]*\bid="(\{?[0-9a-f-]{32,38}\}?)"[^>]*>'
            foreach ($match in [regex]::Matches($html, $linkPattern)) {
                $rawId = $match.Groups[1].Value.Trim("{","}")
                if ($rawId.Length -eq 32) { $rawId = [guid]::Parse($rawId).ToString() }
                $t = Resolve-IdValue $rawId
                Add-Result -Scope $Scope -Item $Item -Field $field -LinkType "internal" -TargetId $rawId -TargetItem $t
            }
        }
    }
}

# Page-level links + datasource links for ONE page
function Get-PageLinks {
    param($PageItem)

    $currentPage = $PageItem   # visible to Add-Result via dynamic scope

    # 1. page-level links
    Get-LinksFromItem -Item $PageItem -Scope "Page"

    # 2. datasource links (de-duplicated per page)
    $seen = @{}

    foreach ($device in $db.Resources.Devices.GetAll()) {
        $renderings = Get-Rendering -Item $PageItem -Device $device -FinalLayout -ErrorAction SilentlyContinue

        foreach ($r in $renderings) {
            $ds = $r.Datasource
            if ([string]::IsNullOrWhiteSpace($ds)) { continue }

            $dsItems = @()

            if ($ds.StartsWith("local:", [StringComparison]::OrdinalIgnoreCase)) {
                $dsItems = @($db.GetItem($PageItem.Paths.FullPath + $ds.Substring(6), $lang))
            }
            elseif ($ds.StartsWith("query:", [StringComparison]::OrdinalIgnoreCase)) {
                $dsItems = @($PageItem.Axes.SelectItems($ds.Substring(6)))
            }
            else {
                $dsItems = @($db.GetItem($ds, $lang))
            }

            foreach ($dsItem in ($dsItems | Where-Object { $_ })) {
                $toScan = @($dsItem)
                if ($includeDatasourceChildren) { $toScan += @($dsItem.Axes.GetDescendants()) }

                foreach ($i in $toScan) {
                    $key = $i.ID.ToString()
                    if ($seen.ContainsKey($key)) { continue }
                    $seen[$key] = $true
                    Get-LinksFromItem -Item $i -Scope "Datasource"
                }
            }
        }
    }

    return $seen.Count
}

# ---------------------------------------------------------------
# Collect items (root + descendants via Fast Query)
# ---------------------------------------------------------------
$items = New-Object System.Collections.Generic.List[object]
$items.Add($root)

if ($includeAllDescendants) {
    $fastQuery = "fast:" + (ConvertTo-FastPath $root.Paths.FullPath) + "//*"

    $descendants = Get-Item -Path "$($database):" -Query $fastQuery -Language $language

    foreach ($d in $descendants) {
        if ($d.Versions.Count -lt 1) { continue }   # no version in this language

        if ($pagesOnly) {
            # has presentation (item-level or from standard values)
            $hasLayout = -not [string]::IsNullOrEmpty($d["__Renderings"]) -or
                         -not [string]::IsNullOrEmpty($d["__Final Renderings"])
            if (-not $hasLayout) { continue }
        }
        $items.Add($d)
    }
}

# ---------------------------------------------------------------
# Process
# ---------------------------------------------------------------
$total          = $items.Count
$index          = 0
$datasourceScan = 0

foreach ($pageItem in $items) {
    $index++
    Write-Progress -Activity "Extracting links" -Status "$index / $total  $($pageItem.Paths.FullPath)" -PercentComplete (($index / $total) * 100)

    $out = @(Get-PageLinks -PageItem $pageItem)
    $datasourceScan += [int]$out[-1]
}

Write-Progress -Activity "Extracting links" -Completed

# ---------------------------------------------------------------
# Output
# ---------------------------------------------------------------
if ($results.Count -eq 0) {
    Show-Alert "No links found under $($root.Paths.FullPath)."
    return
}

$props = @(
    @{ Label = "Page";          Expression = { $_.Page } },
    @{ Label = "Scope";         Expression = { $_.Scope } },
    @{ Label = "Source Item";   Expression = { $_.SourceItem } },
    @{ Label = "Field";         Expression = { $_.Field } },
    @{ Label = "Field Type";    Expression = { $_.FieldType } },
    @{ Label = "Link Type";     Expression = { $_.LinkType } },
    @{ Label = "Target";        Expression = { $_.Target } },
    @{ Label = "Target Exists"; Expression = { $_.TargetExists } },
    @{ Label = "Target ID";     Expression = { $_.TargetId } },
    @{ Label = "Source ID";     Expression = { $_.SourceId } }
)

$info = "$($results.Count) links found | $total page(s) scanned | $datasourceScan datasource item(s) scanned"

$results | Show-ListView -Title "Links under $($root.Paths.FullPath)" -InfoTitle "Page + datasource links" -InfoDescription $info -PageSize 50 -Property $props
