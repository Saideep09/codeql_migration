# Define URLs and file paths
$apiUrl = "https://api.github.com/repos/saideep11111/source2/code-scanning/analyses/314668247"
$jsonFile = "analysis.json"  # Temp file for JSON data
$sarifFile = "analysis.sarif"  # Output SARIF file

# Download JSON data using gh CLI and save it as analysis.json
Write-Output "Downloading JSON data from GitHub API..."
& gh api -X GET $apiUrl > $jsonFile

# Verify the JSON file was downloaded
if (!(Test-Path -Path $jsonFile)) {
    Write-Output "Failed to download JSON data."
    exit
}

# Load JSON data
$jsonData = Get-Content -Path $jsonFile | ConvertFrom-Json

# Create SARIF template
$sarifData = @{
    version = "2.1.0"
    '$schema' = "https://schemastore.azurewebsites.net/schemas/json/sarif-2.1.0-rtm.4.json"
    runs = @()
}

# Convert JSON data to SARIF structure for each analysis
foreach ($analysis in $jsonData) {
    # Create a run for each analysis
    $sarifRun = @{
        tool = @{
            driver = @{
                name = $analysis.tool.name  # Tool name from JSON
                version = $analysis.tool.version  # Tool version from JSON
                informationUri = $analysis.url  # Analysis URL
            }
        }
        properties = @{
            commit_sha = $analysis.commit_sha
            analysis_key = $analysis.analysis_key
            ref = $analysis.ref
            created_at = $analysis.created_at
            sarif_id = $analysis.sarif_id
        }
        # Empty results array, as individual issues aren't in the JSON
        results = @()
    }

    # Append each run to SARIF runs
    $sarifData.runs += $sarifRun
}

# Convert SARIF data to JSON and save it as a .sarif file
$sarifData | ConvertTo-Json -Depth 10 | Set-Content -Path $sarifFile -Force

Write-Output "Conversion complete! SARIF file saved to $sarifFile"
