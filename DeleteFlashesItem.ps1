# Define the template Name for the Settings item
$dataFolderTemplate = "DataFolder"

# List to hold matching flashes items
$matchingFlashes = @()

# Fast query to get all Settings items under /sitecore/content with the specified template ID
$dataItems = Get-Item -Path master: -Query "fast:/sitecore/content//*[@@templatename='$dataFolderTemplate']"

foreach ($dataItem in $dataItems) {
    
    # Check if the Settings item has a flashes item under it
    $flashPath = "$($dataItem.Paths.FullPath)/Flashes"
    $flashItem = Get-Item -Path $flashPath -ErrorAction SilentlyContinue

    # If flashes item exists and matches the target template ID
    if ($flashItem -ne $null) {
        #$flashItem | Set-ItemTemplate -Template $targetTemplateId
        #Publish-Item -Item $flashItem -Target "web" -Recurse
        
        $matchingFlashes += $flashItem
        #$flashItem | Remove-Item
        #Write-Host "  Found flashes: $($flashItem.Paths.FullPath)"
    }
    else{
        Write-Host " Not Found flashes: $($dataItem.Paths.FullPath)"
    }
}

# Output matched flashes items
#$matchingFlashes | Select-Object Name, TemplateName, @{Name="Path";Expression={$_.Paths.FullPath}}
$matchingFlashes | Show-ListView -Property Name, TemplateName, @{Name="Path";Expression={$_.Paths.FullPath}} -Title "Flash under Home"
# Show total count of matching $matchingFlashescts items
Write-Host ""
Write-Host "Total matching flashes items: $($matchingFlashes.Count)" -ForegroundColor Green
