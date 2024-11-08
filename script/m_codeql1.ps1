# Define URLs and file paths
$apiUrl = "https://api.github.com/repos/saideep11111/source2/code-scanning/analyses/313278899"
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
    runs = @(
        @{
            tool = @{
                driver = @{
                    name = "CodeQL"  # Replace with the name of your tool
                    informationUri = "https://codeql.github.com/docs/"  # Replace with the tool's information URL
                }
            }
            results = @()
        }
    )
}

# Convert JSON data to SARIF structure
foreach ($issue in $jsonData.issues) {  # Modify "issues" key based on your JSON structure
    $sarifResult = @{
        ruleId = $issue.ruleId
        level = $issue.severity
        message = @{
            text = $issue.message
        }
        locations = @(
            @{
                physicalLocation = @{
                    artifactLocation = @{
                        uri = $issue.filePath
                    }
                    region = @{
                        startLine = $issue.startLine
                        endLine = $issue.endLine
                    }
                }
            }
        )
    }
    $sarifData.runs[0].results += $sarifResult
}

# Convert SARIF data to JSON and save it as a .sarif file
$sarifData | ConvertTo-Json -Depth 10 | Set-Content -Path $sarifFile -Force

Write-Output "Conversion complete! SARIF file saved to $sarifFile"
