$dialogParams = @{
    Title            = "Dialog title"
    Description      = "Description under title"
    OkButtonName     = "Execute"
    CancelButtonName = "Close"
    ShowHints        = $true
    Parameters       = @(
        @{
            Name        = "singleLineText"
            Title       = "Please enter text which need to be searched"
            Placeholder = "Text to be search"
            Tooltip     = "Please enter search keyword"
        }
        @{
            Name        = "itemPath"
            Title       = "Please enter item path"
            Placeholder = "Item Path"
            Tooltip     = "Please enter Item Path"
        }
    )
}

$dialogResult = Read-Variable @dialogParams
if ($dialogResult -eq "ok") {
    $startPath = "master:" + $itemPath
    Write-Host "Search started $(Get-Date -format 'u')"
    $list = [System.Collections.ArrayList]@()
    $itemsToProcess = Get-ChildItem -Path $startPath -Language * -Recurse
    if ($itemsToProcess -ne $null) {
        $itemsToProcess | ForEach-Object { 
            $match = 0;
            foreach ($field in $_.Fields) {
                if ($field -match '.*' + $singleLineText + '.*') {
                    $info = [PSCustomObject]@{
                        "ID"           = $_.Paths.FullPath
                        "Language"     = $_.Language
                        "TemplateName" = $_.TemplateName
                        "FieldName"    = $field.Name
                        "FieldType"    = $field.Type
                        "FieldValue"   = $field
                    }
                    [void]$list.Add($info)
                }
            }
        }
    }
    Write-Host "Search ended $(Get-Date -format 'u')"
    Write-Host "Items found: $($list.Count)"
    $list | Format-Table 
    
}
