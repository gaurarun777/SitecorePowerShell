<#
.SYNOPSIS
    Extracts all links from a page item and from every datasource item used by
    that page's renderings (Sitecore PowerShell Extensions). Results are shown
    in Show-ListView.

.NOTES
    Run in SPE ISE. Set $pagePath (or $pageId), $database and $language below.
    Covers: General Link, Internal Link, Droplink, Droptree, Multilist/Treelist
    variants, Image, File and Rich Text (href/src, ~/link.aspx, ~/media, <link id>).
#>

# ------------------------- Settings -------------------------
$pagePath                  = "/sitecore/content/Home"   # page to analyse
$pageId                    = ""                         # optional GUID, overrides $pagePath
$database                  = "master"
$language                  = "en"
$includeDatasourceChildren = $false                     # also scan descendants of datasource items
# ------------------------------------------------------------

$db = [Sitecore.Configuration.Factory]::GetDatabase($database)

if ($pageId) { $page = Get-Item -Path "$($database):" -ID $pageId -Language $language }
else         { $page = Get-Item -Path "$($database):$pagePath" -Language $language }

if (-not $page) {
    Show-Alert "Page not found."
    return
}

$results = New-Object System.Collections.Generic.List[object]

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
        return $db.GetItem($guid.ToString("B"), $page.Language)
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

            # href / src attributes
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

# ---------- 1. Page-level links ----------
Get-LinksFromItem -Item $page -Scope "Page"

# ---------- 2. Datasource links ----------
$datasourceIds = @{}   # de-duplicate across devices / renderings
$devices = $db.Resources.Devices.GetAll()

foreach ($device in $devices) {
    $renderings = Get-Rendering -Item $page -Device $device -FinalLayout -ErrorAction SilentlyContinue

    foreach ($r in $renderings) {
        $ds = $r.Datasource
        if ([string]::IsNullOrWhiteSpace($ds)) { continue }

        $dsItems = @()

        if ($ds.StartsWith("local:", [StringComparison]::OrdinalIgnoreCase)) {
            $dsItems = @($db.GetItem($page.Paths.FullPath + $ds.Substring(6), $page.Language))
        }
        elseif ($ds.StartsWith("query:", [StringComparison]::OrdinalIgnoreCase)) {
            $dsItems = @($page.Axes.SelectItems($ds.Substring(6)))
        }
        else {
            $dsItems = @($db.GetItem($ds, $page.Language))
        }

        foreach ($dsItem in ($dsItems | Where-Object { $_ })) {
            $toScan = @($dsItem)
            if ($includeDatasourceChildren) { $toScan += @($dsItem.Axes.GetDescendants()) }

            foreach ($i in $toScan) {
                $key = $i.ID.ToString()
                if ($datasourceIds.ContainsKey($key)) { continue }
                $datasourceIds[$key] = $true
                Get-LinksFromItem -Item $i -Scope "Datasource"
            }
        }
    }
}

# ---------- 3. Output ----------
if ($results.Count -eq 0) {
    Show-Alert "No links found for $($page.Paths.FullPath)."
    return
}

$props = @(
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

$info = "$($results.Count) links found ($($datasourceIds.Count) datasource items scanned)"

$results | Show-ListView -Title "Links for $($page.Paths.FullPath)" -InfoTitle "Page + datasource links" -InfoDescription $info -PageSize 50 -Property $props
