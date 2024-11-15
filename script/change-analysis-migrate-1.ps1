# Define URLs and file paths
$apiUrl = "https://api.github.com/repos/saideep11111/s1/code-scanning/analyses/326224495"
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

# Define a complete list of 74 rules (this is a simplified example, replace with actual rule details if available)
$fullRulesList = @()
for ($i = 1; $i -le 74; $i++) {
    $rule = @{
        id = "RULE00$i"
        name = "Example rule $i"
        fullDescription = @{ text = "Description for rule $i." }
        helpUri = "https://codeql.github.com/docs/codeql-for-java/"
        properties = @{
            tags = @("java", "example")
        }
    }
    $fullRulesList += $rule
}

# Convert JSON data to SARIF structure for the analysis
$sarifRun = @{
    tool = @{
        driver = @{
            name = $jsonData.tool.name  # Tool name from JSON
            version = $jsonData.tool.version  # Tool version from JSON
            informationUri = "https://github.com/github/codeql"  # Information about the tool
            rules = $fullRulesList  # Add the complete list of 74 rules
        }
    }
    properties = @{
        commit_sha = $jsonData.commit_sha
        analysis_key = $jsonData.analysis_key
        ref = $jsonData.ref
        created_at = $jsonData.created_at
        sarif_id = $jsonData.sarif_id
    }
    results = @()
}

# Add placeholder results based on results_count
for ($i = 1; $i -le $jsonData.results_count; $i++) {
    $result = @{
        ruleId = "RULE00$i"  # Associate with each rule ID up to results_count
        message = @{ text = "This is a placeholder message for result $i." }
        locations = @(
            @{
                physicalLocation = @{
                    artifactLocation = @{ uri = "example.java" }
                    region = @{
                        startLine = 10 + $i  # Example line number
                    }
                }
            }
        )
    }
    $sarifRun.results += $result
}

# Append the run to SARIF runs
$sarifData.runs += $sarifRun

# Convert SARIF data to JSON and save it as a .sarif file
$sarifData | ConvertTo-Json -Depth 10 | Set-Content -Path $sarifFile -Force

Write-Output "Conversion complete! SARIF file saved to $sarifFile"
