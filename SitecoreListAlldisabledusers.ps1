# Get all users (from all domains)
$allUsers = Get-User -Filter "*"
 
# Filter disabled users (IsEnabled = $false)
$disabledUsers = $allUsers | Where-Object { $_.IsEnabled -eq $false }
 
# Add parsed domain info for each user
$disabledUsersWithDomain = $disabledUsers | ForEach-Object {
    $splitName = $_.Name -split '\\'
    [PSCustomObject]@{
        Name      = $_.Name
        Domain    = if ($splitName.Length -eq 2) { $splitName[0] } else { "unknown" }
        UserName  = if ($splitName.Length -eq 2) { $splitName[1] } else { $_.Name }
        IsEnabled = $_.IsEnabled
    }
}
 
# Show in interactive list view
$disabledUsersWithDomain | Show-ListView -Title "Disabled Users" -Property Name, Domain, UserName, IsEnabled
