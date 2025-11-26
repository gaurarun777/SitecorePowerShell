<# RUN in Sitecore PowerShell Extensions (SPE) #>

# ---- Inline CSV (edit rows) ----
$csv = @"
UserName,Domain,FullName,Email,Comment,Password,Roles
jdoe,sitecore,John Doe,john.doe@yourdomain.com,Marketing author,P@ssw0rd!,sitecore\Author|sitecore\Sitecore Client Users
asmith,sitecore,Alice Smith,alice.smith@yourdomain.com,Content approver,P@ssw0rd!,sitecore\Author|sitecore\Sitecore Client Users
"@

$users = ($csv | ConvertFrom-Csv) | ForEach-Object {
    [pscustomobject]@{
        UserName = $_.UserName.Trim()
        Domain   = $_.Domain.Trim()
        FullName = $_.FullName
        Email    = $_.Email
        Comment  = $_.Comment
        Password = $_.Password
        Roles    = ($_.Roles -split '\|') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    }
}

function Write-Status($msg, [ConsoleColor]$color='Gray') {
    Write-Host ("[{0}] {1}" -f (Get-Date).ToString('HH:mm:ss'), $msg) -ForegroundColor $color
}

foreach ($u in $users) {
    if (-not $u.UserName -or -not $u.Domain) {
        Write-Status "Skipping row with missing UserName/Domain." 'Yellow'
        continue
    }

    $identity = "{0}\{1}" -f $u.Domain, $u.UserName
    $user = Get-User -Identity $identity -ErrorAction SilentlyContinue

    if ($user) {
        Write-Status ("User exists -> updating: {0}" -f $identity) 'Cyan'
    } else {
        Write-Status ("Creating user: {0}" -f $identity) 'Green'
        New-User -Identity $identity -Password $u.Password | Out-Null
        $user = Get-User -Identity $identity -ErrorAction Stop
    }

    # Update profile
    Set-User -Identity $identity -FullName $u.FullName -Email $u.Email -Comment $u.Comment -Enabled | Out-Null

    # Assign roles
    foreach ($r in $u.Roles) {
        $role = Get-Role -Identity $r -ErrorAction SilentlyContinue
        if (-not $role) {
            Write-Status ("Role not found, skipping: {0}" -f $r) 'Yellow'
            continue
        }

        $already = Get-RoleMember -Identity $r -ErrorAction SilentlyContinue |
                   Where-Object { $_ -is [Sitecore.Security.Accounts.User] -and $_.Name -ieq $identity }

        if (-not $already) {
            try {
                Add-RoleMember -Identity $r -Member $identity | Out-Null
                Write-Status ("Added {0} to role: {1}" -f $identity, $r)
            } catch {
                Write-Status ("Failed to add {0} to {1}: {2}" -f $identity, $r, $_.Exception.Message) 'Yellow'
            }
        } else {
            Write-Status ("{0} already in role: {1}" -f $identity, $r)
        }
    }
}

Write-Status "Done." 'Green'
