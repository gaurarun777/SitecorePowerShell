<#
.SYNOPSIS
    Extracts all links from a page item and from every datasource item used by
    that page's renderings (Sitecore PowerShell Extensions).

.NOTES
    Run in SPE ISE / as a Script Library script.
    Set $pagePath (or $pageId), $database and $language below.
    Covers: General Link, Internal Link, Droplink, Droptree, Multilist/Treelist
    variants, Image, File and Rich Text (href/src, ~/link.aspx, ~/media).
#>

# ------------------------- Settings -------------------------
$pagePath                   = "/sitecore/content/Home"   # page to analyse
$pageId                     = ""                         # optional: GUID, overrides $pagePath
$database                   = "master"
$language                   = "en"
$includeDatasourceChildren  = $false                     # also scan children of datasource items (e.g. folders)
# ------------------------------------------------------------

$db = [Sitecore.Configuration.Factory]::GetDatabase($database)

if ($pageId) { $page = Get-Item -Path "$($database):" -ID $pageId -Language $language }
else         { $page = Get-Item -Path "$($database):$pagePath" -Language $language }

if (-not $page) {
    Show-Alert "Page not found."
    exit
}

$results = [System.Collections.Generic.List[object]]::new()

function Add-Result {
    param($Scope, $Item, $Field, $LinkType, $Target, $TargetId, $TargetItem)

    $results.Add([PSCustomObject]@{
        Scope        = $Scope                       # Page / Datasource
        SourceItem   = $Item.Paths.FullPath
        SourceId     = $Item.ID.ToString()
        Field        = $Field.Name
        FieldType    = $Field.Type
        LinkType     = $LinkType
        Target       = $Target
        TargetId     = $TargetId
        TargetExists = if ($LinkType -in "external","mailto","anchor","javascript","url") { "n/a" } else { [bool]$TargetItem }
    })
}

function Resolve-IdValue {
    param([string]$Value)
    $guid = [guid]::Empty
    if ([guid]::TryParse($Value, [ref]$guid)) {
        return $db.GetItem([Sitecore.Data.ID]::Parse($guid), $page.Language)
    }
    return $null
}

function Get-LinksFromItem {
    param($Item, [string]$Scope)

    $Item.Fields.ReadAll()

    foreach ($field in $Item.Fields) {
        if ($field.Name.StartsWith("__")) { continue }   # skip standard fields
        if (-not $field.HasValue)         { continue }

        switch -Wildcard ($field.Type) {

            "General Link*" {
                $lf = [Sitecore.Data.Fields.LinkField]$field
                if (-not $lf.LinkType) { break }
                switch ($lf.LinkType) {
                    { $_ -in "internal","media" } {
                        $t = $lf.TargetItem
                        Add-Result $Scope $Item $field $lf.LinkType $(if ($t) { $t.Paths.FullPath } else { "[missing] $($lf.TargetID)" }) $lf.TargetID.ToString() $t
                    }
                    "anchor" { Add-Result $Scope $Item $field "anchor" $lf.Anchor "" $null }
                    default  { Add-Result $Scope $Item $field $lf.LinkType $lf.Url "" $null }
                }
            }

            { $_ -in "Internal Link","Droplink","Droptree","Lookup","Reference","Grouped Droplink" } {
                $t = Resolve-IdValue $field.Value
                Add-Result $Scope $Item $field "reference" $(if ($t) { $t.Paths.FullPath } else { "[missing] $($field.Value)" }) $field.Value $t
            }

            { $_ -in "Multilist","Multilist with Search","Treelist","Treelist with Search","TreelistEx","Checklist","Tree List" } {
                foreach ($id in ($field.Value -split "\|" | Where-Object { $_ })) {
                    $t = Resolve-IdValue $id
                    Add-Result $Scope $Item $field "reference" $(if ($t) { $t.Paths.FullPath } else { "[missing] $id" }) $id $t
                }
            }

            "Image" {
                $img = [Sitecore.Data.Fields.ImageField]$field
                if ($img.MediaID -and $img.MediaID -ne [Sitecore.Data.ID]::Null) {
                    $t = $img.MediaItem
                    Add-Result $Scope $Item $field "media" $(if ($t) { $t.Paths.FullPath } else { "[missing] $($img.MediaID)" }) $img.MediaID.ToString() $t
                }
            }

            "File" {
                $file = [Sitecore.Data.Fields.FileField]$field
                if ($file.MediaID -and $file.MediaID -ne [Sitecore.Data.ID]::Null) {
                    $t = $file.MediaItem
                    Add-Result $Scope $Item $field "media" $(if ($t) { $t.Paths.FullPath } else { "[missing] $($file.MediaID)" }) $file.MediaID.ToString() $t
                }
            }

            "Rich Text" {
                $html = $field.Value

                # href / src attributes
                [regex]::Matches($html, '(?i)\b(?:href|src)\s*=\s*["'']([^"'']+)["'']') | ForEach-Object {
                    $url = $_.Groups[1].Value
                    $id  = $null
                    $m   = [regex]::Match($url, '(?i)(?:_id=|/media/)\{?([0-9a-f]{32}|[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12})\}?')
                    if ($m.Success) {
                        $raw = $m.Groups[1].Value
                        if ($raw.Length -eq 32) { $raw = [guid]::Parse($raw).ToString() }
                        $id = $raw
                    }
                    if ($id) {
                        $t = Resolve-IdValue $id
                        $type = if ($url -match "(?i)/media/") { "media" } else { "internal" }
                        Add-Result $Scope $Item $field $type $(if ($t) { $t.Paths.FullPath } else { "[missing] $id" }) $id $t
                    }
                    elseif ($url -match "(?i)^mailto:")  { Add-Result $Scope $Item $field "mailto" $url "" $null }
                    elseif ($url -match "^#")            { Add-Result $Scope $Item $field "anchor" $url "" $null }
                    elseif ($url -match "(?i)^javascript:") { Add-Result $Scope $Item $field "javascript" $url "" $null }
                    else                                 { Add-Result $Scope $Item $field "url" $url "" $null }
                }

                # Link-manager style: <link linktype="internal" id="{GUID}" />
                [regex]::Matches($html, '(?i)<link[^>]*\bid="(\{?[0-9a-f-]{32,38}\}?)"[^>]*>') | ForEach-Object {
                    $id = $_.Groups[1].Value
                    $t  = Resolve-IdValue $id
                    Add-Result $Scope $Item $field "internal" $(if ($t) { $t.Paths.FullPath } else { "[missing] $id" }) $id $t
                }
            }
        }
    }
}

# ---------- 1. Page-level links ----------
Get-LinksFromItem -Item $page -Scope "Page"

# ---------- 2. Datasource links ----------
$datasourceIds = @{}   # de-duplicate across devices / renderings

foreach ($device in (Get-LayoutDevice)) {
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
                if ($datasourceIds.ContainsKey($i.ID.ToString())) { continue }
                $datasourceIds[$i.ID.ToString()] = $true
                Get-LinksFromItem -Item $i -Scope "Datasource"
            }
        }
    }
}

# ---------- 3. Output ----------
if ($results.Count -eq 0) {
    Show-Alert "No links found for $($page.Paths.FullPath)."
    exit
}

$results | Show-ListView -Title "Links for $($page.Paths.FullPath)" `
    -InfoTitle "Page + datasource links" `
    -InfoDescription "$($results.Count) links found ($($datasourceIds.Count) datasource items scanned)" `
    -PageSize 50 `
    -Property @{Label="Scope";        Expression={ $_.Scope }},
              @{Label="Source Item";  Expression={ $_.SourceItem }},
              @{Label="Field";        Expression={ $_.Field }},
              @{Label="Field Type";   Expression={ $_.FieldType }},
              @{Label="Link Type";    Expression={ $_.LinkType }},
              @{Label="Target";       Expression={ $_.Target }},
              @{Label="Target Exists";Expression={ $_.TargetExists }},
              @{Label="Target ID";    Expression={ $_.TargetId }},
              @{Label="Source ID";    Expression={ $_.SourceId }}
