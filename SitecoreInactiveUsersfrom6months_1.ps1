Add-Type -AssemblyName "System.Web"
 
# Set the cutoff date (6 months ago)
$cutoffDate = (Get-Date).AddMonths(-6)
 
# Get all Sitecore users
$allUsers = Get-User -Filter *
 
# Create a list of inactive users
$inactiveUsers = @()
 
foreach ($sitecoreUser in $allUsers) {
    $userName = $sitecoreUser.Name
 
    # Get Membership user for accurate LastLoginDate
    $membershipUser = [System.Web.Security.Membership]::GetUser($userName, $false)
 
    # Skip if membership user doesn't exist
    if ($membershipUser -eq $null) {
        continue
    }
 
    $lastLogin = $membershipUser.LastLoginDate
 
    if ($lastLogin -eq $null -or $lastLogin -lt $cutoffDate) {
        $inactiveUsers += [PSCustomObject]@{
            Username   = $sitecoreUser.Name
            FullName   = $sitecoreUser.Profile.FullName
            Email      = $sitecoreUser.Profile.Email
            LastLogin  = if ($lastLogin) { $lastLogin } else { "Never Logged In" }
        }
    }
}
 
# Show the list
$inactiveUsers | Sort-Object LastLogin | Show-ListView -Title "Users Not Logged In in Last 6 Months (Accurate)" -Property Username, FullName, Email, LastLogin
