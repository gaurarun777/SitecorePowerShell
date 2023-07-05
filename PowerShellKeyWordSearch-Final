$radioOptions = [ordered]@{
    "Include Direct Child Items"                 = 1
    "Include N Level of Child Items Recurcively" = 2
}


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
            Name    = "radioSelector"
            Title   = "Include Child item"
            Editor  = "radio"
            Options = $radioOptions 
            Tooltip = "Select one or more options"
            Value   = 0
        }
        @{
            Name      = "languageSelection"
            Title     = "Select a Proper Language"
            Editor    = "droptree"
            Source    = "/sitecore/system/Languages"
            Tooltip   = "Please select a valid Language."
            Mandatory = $true
        }
        @{
            Name    = "dropTreeSelector"
            Title   = "Select the parent node"
            Editor  = "droptree"
            Source  = "/sitecore/content"
            Tooltip = "Select from dropdown tree"
        }
    )
    
    Validator        = {
        $selectedLang = $variables.languageSelection.Value
 
        if ($selectedLang.TemplateID -ne "{F68F13A6-3395-426A-B9A1-FA2DC60D94EB}") {
            $variables.languageSelection.Error = "Please choose a valid Language."
        }
    }
}
 
$dialogResult = Read-Variable @dialogParams
if ($dialogResult -eq "ok") {
    $startPath = "master:" + $dropTreeSelector.ItemPath
    Write-Host "Search started $(Get-Date -format 'u')"
    $list = [System.Collections.ArrayList]@()
    if ($radioSelector -eq 1) {
        $itemsToProcess = Get-ChildItem -Path $startPath -Language $languageSelection.Name
    }
    elseif ($radioSelector -eq 2) {
        $itemsToProcess = Get-ChildItem -Path $startPath -Language $languageSelection.Name -Recurse
    }
    else {
        $itemsToProcess = Get-Item -Path $startPath -Language $languageSelection.Name
    }

    if ($itemsToProcess -ne $null) {
        $itemsToProcess | ForEach-Object { 
            $match = 0;
            foreach ($field in $_.Fields) {
                if ($field -match '.*' + $singleLineText + '.*') {
                    $info = [PSCustomObject]@{
                        "Path"           = $_.Paths.FullPath
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
Remove-Variable * -ErrorAction SilentlyContinue
