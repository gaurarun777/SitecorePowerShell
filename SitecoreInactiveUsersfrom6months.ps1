Add-Type -AssemblyName "System.Web"
 
# Get the membership provider (adjust provider name if custom)
$provider = [System.Web.Security.Membership]::Provider
 
# Set cutoff date to 6 months ago
$cutoffDate = (Get-Date).AddMonths(-6)
 
# Prepare list for inactive users
$inactiveUsers = @()
 
# Paging parameters
$pageSize = 1000
$pageIndex = 0
$totalRecords = 0
 
do {
    # Retrieve a page of users
    $usersPage = $provider.GetAllUsers($pageIndex, $pageSize, [ref]$totalRecords)
 
    foreach ($user in $usersPage) {
        # Get LastLoginDate from membership user
        $lastLoginDate = $user.LastLoginDate
 
        if ($lastLoginDate -eq $null -or $lastLoginDate -lt $cutoffDate) {
            # Try to get Sitecore user for profile info
            $sitecoreUser = Get-User -Identity $user.UserName -ErrorAction SilentlyContinue
 
            $inactiveUsers += [PSCustomObject]@{
                "Username"  = if ($sitecoreUser) { $sitecoreUser.Name } else { $user.UserName }
                "FullName"  = if ($sitecoreUser) { $sitecoreUser.Profile.FullName } else { "" }
                "Email"     = if ($sitecoreUser) { $sitecoreUser.Profile.Email } else { "" }
                "LastLogin" = if ($lastLoginDate) { $lastLoginDate } else { "Never Logged In" }
            }
        }
    }
 
    $pageIndex++
} while ($pageIndex * $pageSize -lt $totalRecords)
 
# Output the inactive users sorted by last login date
$inactiveUsers | Sort-Object LastLogin | Show-ListView -Title "Users Not Logged In Last 6 Months" -Property Username, FullName, Email, LastLogin
