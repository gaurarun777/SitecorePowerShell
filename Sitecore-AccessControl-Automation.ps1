<# Grant / Revoke / Deny selected rights for a role on pasted items
   - DB list from Factory.GetDatabases() (excluding 'filesystem')
   - Permissions checklist (Read/Write/Rename/Create/Delete/Administer + Inheritance)
   - Mode radio: Grant / Revoke / Deny
   - Grant: Add-ItemAcl (-Identity) AllowAccess
   - Deny:  Remove ALLOW rules (direct rules edit) -> Add-ItemAcl (-Identity) DenyAccess
            If Inheritance: remove AllowInheritance rules -> add DenyInheritance (via Add-ItemAcl)
   - Revoke: Remove ALLOW/DENY + inheritance rules (direct rules edit)
#>

Import-Module SPE -ErrorAction SilentlyContinue | Out-Null

# ---- Clean vars from prior runs
Remove-Variable DbName, RoleName, RawPaths, SelectedRights, ModeChoice, dbList, dbMap, defaultDb -ErrorAction SilentlyContinue

# ---- Databases from Factory.GetDatabases() (exclude 'filesystem')
$dbList = New-Object System.Collections.Generic.List[string]
[Sitecore.Configuration.Factory]::GetDatabases() | ForEach-Object {
    $n = [string]$_.Name
    if (![string]::IsNullOrWhiteSpace($n) -and $n -ne 'filesystem') { [void]$dbList.Add($n) }
}
if ($dbList.Count -eq 0) { [void]$dbList.Add("master"); [void]$dbList.Add("web"); [void]$dbList.Add("core") }

# Combo dropdown wants a mapping (display -> value)
$dbMap = New-Object 'System.Collections.Specialized.OrderedDictionary'
foreach ($db in $dbList) { $dbMap.Add($db,$db) }
$defaultDb = $dbList[0]

# ---- Permission checklist options (display -> value)
$permMap = New-Object 'System.Collections.Specialized.OrderedDictionary'
$permMap.Add('Read','Read')
$permMap.Add('Write','Write')
$permMap.Add('Rename','Rename')
$permMap.Add('Create','Create')
$permMap.Add('Delete','Delete')
$permMap.Add('Administer','Administer')
$permMap.Add('Inheritance','Inheritance')

# ---- Mode radio options (display -> value)
$modeMap = New-Object 'System.Collections.Specialized.OrderedDictionary'
$modeMap.Add('Grant (Allow)','Grant')
$modeMap.Add('Revoke (Remove explicit)','Revoke')
$modeMap.Add('Deny','Deny')

# ---- Dialog
$props = @{
  Parameters = @(
    @{ Name="DbName";   Title="Database"; Editor="combo"; Options=$dbMap; Value=$defaultDb },
    @{ Name="RoleName"; Title="Role";     Editor="role" },
    @{ Name="RawPaths"; Title="Item paths (one per line)"; Editor="multiline"; Lines=8; Placeholder="/sitecore/content/Home" },
    @{ Name="SelectedRights"; Title="Permissions"; Editor="checklist"; Options=$permMap;
       Tooltip="Choose rights to change. 'Inheritance' controls whether children inherit." },
    @{ Name="ModeChoice"; Title="Mode"; Editor="radiolist"; Options=$modeMap; Value="Grant" }
  )
  Title="Set Permissions for Role"
  Description="Grant, Revoke (remove explicit), or Deny permissions for the selected role."
  Width=780; Height=620; OkButtonName="Apply"; CancelButtonName="Cancel"
}
$result = Read-Variable @props
if ($result -ne "ok") { return }

# ---- Inputs
# Role picker may return an array; normalize to a single identity string
$roleIdentity = $RoleName
if ($roleIdentity -is [System.Array]) { $roleIdentity = $roleIdentity | Select-Object -First 1 }

$role = Get-Role -Identity $roleIdentity
if ($null -eq $role) { Show-Alert "Role not found: $roleIdentity"; return }

$paths = ($RawPaths -split "(`r`n|`n|`r)") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
if ($paths.Count -eq 0) { Show-Alert "No item paths provided."; return }

$sel = @(); if ($SelectedRights) { $sel = @($SelectedRights) }
$setInheritance = $sel -contains 'Inheritance'
$rightsChosen   = $sel | Where-Object { $_ -ne 'Inheritance' }
if ($rightsChosen.Count -eq 0 -and -not $setInheritance) { Show-Alert "Nothing selected."; return }

$mode = if ([string]::IsNullOrWhiteSpace($ModeChoice)) { "Grant" } else { $ModeChoice }

# ---- Map checkbox names -> security access-right strings
$rightNameToAccessString = @{
  Read       = "item:read"
  Write      = "item:write"
  Rename     = "item:rename"
  Create     = "item:create"
  Delete     = "item:delete"
  Administer = "item:admin"
}

# ---- Helpers
function Resolve-ItemFromDb([string]$path, [string]$db) {
  if ($path -match "^\w+:\\") { Get-Item -Path $path -ErrorAction SilentlyContinue }
  else { Get-Item -Path ("{0}:\{1}" -f $db, $path.TrimStart("\")) -ErrorAction SilentlyContinue }
}

# Remove rules from an item for a role using a predicate over rules
function Remove-Rules {
  param(
    [Parameter(Mandatory=$true)] $Item,
    [Parameter(Mandatory=$true)] [string] $RoleName,
    [Parameter(Mandatory=$true)] [scriptblock] $Predicate
  )
  $changed = $false
  $rules = $Item.Security.GetAccessRules()
  $matches = @($rules | Where-Object { $_.Account.Name -ieq $RoleName -and (& $Predicate $_) })
  if ($matches.Count -gt 0) {
    $Item.Editing.BeginEdit() | Out-Null
    try {
      foreach ($r in $matches) { [void]$rules.Remove($r) }
      $Item.Security.SetAccessRules($rules)
      $Item.Editing.EndEdit() | Out-Null
      $changed = $true
    } catch {
      if ($Item.Editing.IsEditing) { $Item.Editing.CancelEdit() }
      throw
    }
  }
  return $changed
}

# ---- Header
$rightsText  = if ($rightsChosen.Count -gt 0) { ($rightsChosen -join ', ') } else { "(none)" }
$inheritText = if ($setInheritance) { "Yes" } else { "No" }
Write-Host ""
Write-Host "========== Apply Permissions =========="
Write-Host ("Database   : {0}" -f $DbName)
Write-Host ("Role       : {0}" -f $role.Name)
Write-Host ("Mode       : {0}" -f $mode)
Write-Host ("Rights     : {0}" -f $rightsText)
Write-Host ("Inheritance: {0}" -f $inheritText)
Write-Host "---------------------------------------"

foreach ($p in $paths) {
  $item = Resolve-ItemFromDb -path $p -db $DbName
  if ($null -eq $item) { Write-Host ("[SKIP] Not found: {0}" -f $p); continue }

  switch ($mode) {

    "Grant" {
      # Add ALLOW per selected rights
      foreach ($rName in $rightsChosen) {
        $accStr = $rightNameToAccessString[$rName]; if (-not $accStr) { continue }
        try {
          Add-ItemAcl -Item $item -Identity $role.Name -AccessRight $accStr -SecurityPermission AllowAccess -PropagationType Any
          Write-Host ("[OK]  {0} -> Grant {1}" -f $item.Paths.FullPath, $rName)
        } catch { Write-Host ("[ERR] {0} -> Grant {1}: {2}" -f $item.Paths.FullPath, $rName, $_.Exception.Message) }
      }
      if ($setInheritance) {
        try {
          Add-ItemAcl -Item $item -Identity $role.Name -AccessRight "*" -SecurityPermission AllowInheritance -PropagationType Any
          Write-Host ("[OK]  {0} -> Inheritance: Allow" -f $item.Paths.FullPath)
        } catch { Write-Host ("[ERR] {0} -> Inheritance Allow: {1}" -f $item.Paths.FullPath, $_.Exception.Message) }
      }
    }

    "Deny" {
      if ($rightsChosen.Count -eq 0) {
        # Only inheritance: remove AllowInheritance, then add DenyInheritance
        try { [void](Remove-Rules -Item $item -RoleName $role.Name -Predicate { $_.SecurityPermission.ToString() -eq 'AllowInheritance' }) } catch {}
        try {
          Add-ItemAcl -Item $item -Identity $role.Name -AccessRight "*" -SecurityPermission DenyInheritance -PropagationType Any
          Write-Host ("[OK]  {0} -> Inheritance: Deny" -f $item.Paths.FullPath)
        } catch { Write-Host ("[ERR] {0} -> Inheritance Deny: {1}" -f $item.Paths.FullPath, $_.Exception.Message) }
      } else {
        foreach ($rName in $rightsChosen) {
          $accStr = $rightNameToAccessString[$rName]; if (-not $accStr) { continue }

          # 1) Remove ALLOW rule(s) for this role/right
          try {
            [void](Remove-Rules -Item $item -RoleName $role.Name -Predicate {
              ($_.AccessRight.Name -eq $accStr) -and ($_.SecurityPermission.ToString() -eq 'AllowAccess')
            })
          } catch { }

          # 2) Add DENY for this role/right
          try {
            Add-ItemAcl -Item $item -Identity $role.Name -AccessRight $accStr -SecurityPermission DenyAccess -PropagationType Any
            Write-Host ("[OK]  {0} -> Deny {1}" -f $item.Paths.FullPath, $rName)
          } catch { Write-Host ("[ERR] {0} -> Deny {1}: {2}" -f $item.Paths.FullPath, $rName, $_.Exception.Message) }
        }
      }

      if ($setInheritance) {
        # Make sure AllowInheritance is gone; then add DenyInheritance
        try { [void](Remove-Rules -Item $item -RoleName $role.Name -Predicate { $_.SecurityPermission.ToString() -eq 'AllowInheritance' }) } catch {}
        try {
          Add-ItemAcl -Item $item -Identity $role.Name -AccessRight "*" -SecurityPermission DenyInheritance -PropagationType Any
          Write-Host ("[OK]  {0} -> Inheritance: Deny" -f $item.Paths.FullPath)
        } catch { Write-Host ("[ERR] {0} -> Inheritance Deny: {1}" -f $item.Paths.FullPath, $_.Exception.Message) }
      }
    }

    "Revoke" {
      # Remove explicit ALLOW/DENY for chosen rights
      foreach ($rName in $rightsChosen) {
        $accStr = $rightNameToAccessString[$rName]; if (-not $accStr) { continue }
        try {
          $removed = Remove-Rules -Item $item -RoleName $role.Name -Predicate {
            ($_.AccessRight.Name -eq $accStr) -and
            (($_.SecurityPermission.ToString() -eq 'AllowAccess') -or ($_.SecurityPermission.ToString() -eq 'DenyAccess'))
          }
          if ($removed) { Write-Host ("[OK]  {0} -> Revoke {1}" -f $item.Paths.FullPath, $rName) }
          else { Write-Host ("[..]  {0} -> Revoke {1}: no explicit ACEs" -f $item.Paths.FullPath, $rName) }
        } catch {
          Write-Host ("[ERR] {0} -> Revoke {1}: {2}" -f $item.Paths.FullPath, $rName, $_.Exception.Message)
        }
      }
      # Remove inheritance flags for this role
      if ($setInheritance) {
        try {
          $removedInh = Remove-Rules -Item $item -RoleName $role.Name -Predicate {
            ($_.SecurityPermission.ToString() -eq 'AllowInheritance') -or ($_.SecurityPermission.ToString() -eq 'DenyInheritance')
          }
          if ($removedInh) { Write-Host ("[OK]  {0} -> Inheritance: Revoke flags" -f $item.Paths.FullPath) }
          else { Write-Host ("[..]  {0} -> Inheritance: no flags to revoke" -f $item.Paths.FullPath) }
        } catch {
          Write-Host ("[ERR] {0} -> Inheritance revoke: {1}" -f $item.Paths.FullPath, $_.Exception.Message)
        }
      }
    }
  } # switch
} # foreach item

Write-Host "=========================== Done ==========================="
Write-Host ""
