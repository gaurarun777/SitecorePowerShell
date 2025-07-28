# Prompt for comma-separated list (e.g., amgen\pia,sitecore\admin)
$userList = Read-Host "Enter comma-separated list of usernames or fully qualified usernames to enable"
 
# Split and clean the input
$userNames = $userList -split ',' | ForEach-Object { $_.Trim() }
 
foreach ($userName in $userNames) {
    if ([string]::IsNullOrWhiteSpace($userName)) {
        Write-Host "⚠️ Skipped empty username entry." -ForegroundColor DarkYellow
        continue
    }
 
    # Check if user exists
    $user = Get-User -Identity $userName -ErrorAction SilentlyContinue
 
    if ($user -ne $null) {
        if (-not $user.IsEnabled) {
            try {
                Enable-User -Identity $userName
                Write-Host "✅ Enabled: $userName" -ForegroundColor Green
            } catch {
                Write-Host "❌ Failed to enable $userName — $($_.Exception.Message)" -ForegroundColor Red
            }
        } else {
            Write-Host "ℹ️ Already enabled: $userName" -ForegroundColor Yellow
        }
    } else {
        Write-Host "❌ User not found: $userName" -ForegroundColor Red
    }
}
