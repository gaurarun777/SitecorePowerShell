# Define the source folder (the folder whose contents will be copied)
$sourceFolder = "C:\SolrCore\sample"

# Define the destination folder names (the folders where the content will be copied)
$destinationFolders = @("sitecore_core_index","sitecore_master_index","sitecore_web_index") # Add your folder names here

# Define the path where all the destination folders will be created
$baseDestinationPath = "C:\SolrCore\final"

# Define the dummy file content with a placeholder for the folder name
$dummyContentTemplate = @"
#Written by CorePropertiesLocator
#Mon May 27 06:30:54 UTC 2024
name=[FOLDER_NAME]
update.autoCreateFields=false
"@

# Loop through each folder name and perform the operations
foreach ($folderName in $destinationFolders) {
    # Define the full path to the current destination folder
    $destinationFolderPath = Join-Path $baseDestinationPath $folderName

    # Check if the destination folder already exists
    if (Test-Path $destinationFolderPath) {
        Write-Host "Folder '$folderName' already exists, skipping copy operation."
    } else {
        # Create the destination folder if it doesn't exist
        New-Item -Path $destinationFolderPath -ItemType Directory

        # Copy the contents of the source folder to the destination folder
        Copy-Item -Path "$sourceFolder\*" -Destination $destinationFolderPath -Recurse -Force
        Write-Host "Folder '$folderName' created and content copied."

        # Replace the placeholder in the dummy content with the actual folder name
        $dummyContent = $dummyContentTemplate -replace "\[FOLDER_NAME\]", $folderName

        # Define the path to the dummy file to be created
        $dummyFilePath = Join-Path $destinationFolderPath "core.properties"

        # Write the dummy content to the file
        Set-Content -Path $dummyFilePath -Value $dummyContent

        Write-Host "Dummy file created in '$folderName'."
    }
}

Write-Host "Operation completed!"
