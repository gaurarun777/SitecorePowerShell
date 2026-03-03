# -----------------------------------------
# SXA: Read Sitemap cache settings per site
# Path pattern: .../Settings/Sitemap
# -----------------------------------------

# Fields on the Sitemap item
$fieldRefreshThreshold = "Refresh Threshold"
$fieldCacheType        = "Cache Type"
$fieldCacheExpiration  = "Cache Expiration"

$results = @()

# Find all "Settings" items under /sitecore/content (fast query by name)
$settingsItems = Get-Item -Path master: -Query "fast:/sitecore/content//*[@@name='Settings']"

foreach ($settings in $settingsItems) {

    # Get child Sitemap item under Settings
    $sitemapPath = "$($settings.Paths.FullPath)/Sitemap"
    $sitemapItem = Get-Item -Path ("master:" + $sitemapPath) -ErrorAction SilentlyContinue

    if ($null -ne $sitemapItem) {
        $results += [pscustomobject]@{
            SitemapItemName       = $sitemapItem.Name
            SitemapTemplate       = $sitemapItem.TemplateName
            SitemapPath           = $sitemapItem.Paths.FullPath
            "Refresh Threshold"   = $sitemapItem[$fieldRefreshThreshold]
            "Cache Type"          = $sitemapItem[$fieldCacheType]
            "Cache Expiration"    = $sitemapItem[$fieldCacheExpiration]
        }
    }
}

# Show in list view
$results | Show-ListView `
    -Title "SXA Sitemap Settings (Refresh Threshold / Cache Type / Cache Expiration)" `
    -Property SitemapItemName, SitemapTemplate, SitemapPath, "Refresh Threshold", "Cache Type", "Cache Expiration"

Write-Host ""
Write-Host "Total Sitemap items found under Settings: $($results.Count)" -ForegroundColor Green
