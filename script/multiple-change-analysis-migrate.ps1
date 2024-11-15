# Define parameters
$sourceOwner = "saideep11111"  # Source repository owner
$sourceRepo = "S1"  # Source repository name
$targetOwner = "saideep11112"  # Target repository owner
$targetRepo = "S2"  # Target repository name
$githubToken = "Put_token"  # GitHub token
$sarifDirectory = "C:\Users\saide\OneDrive\Desktop\bacd\codeql_migration"  # Directory for SARIF files
$branchRef = "refs/heads/main"  # Branch reference

# Create SARIF directory if it doesn't exist
if (!(Test-Path -Path $sarifDirectory)) {
    New-Item -ItemType Directory -Path $sarifDirectory
}

# Step 1: Fetch all analyses from the source repository
$analysesUrl = "https://api.github.com/repos/$sourceOwner/$sourceRepo/code-scanning/analyses"
$analysesList = & gh api -X GET $analysesUrl | ConvertFrom-Json

# Step 2: Iterate over each analysis in the source repository
foreach ($analysis in $analysesList) {
    $analysisId = $analysis.id
    $commitSHA = $analysis.commit_sha
    $jsonFile = "$sarifDirectory\analysis_$analysisId.json"  # Temp file for JSON data
    $sarifFile = "$sarifDirectory\analysis_$analysisId.sarif"  # Output SARIF file

    # Download JSON data for the specific analysis ID
    $apiUrl = "https://api.github.com/repos/$sourceOwner/$sourceRepo/code-scanning/analyses/$analysisId"
    Write-Output "Downloading JSON data for analysis ID $analysisId from GitHub API..."
    & gh api -X GET $apiUrl > $jsonFile

    # Verify the JSON file was downloaded
    if (!(Test-Path -Path $jsonFile)) {
        Write-Output "Failed to download JSON data for analysis ID $analysisId."
        continue
    }

    # Load JSON data
    $jsonData = Get-Content -Path $jsonFile | ConvertFrom-Json

    # Create SARIF template
    $sarifData = @{
        version = "2.1.0"
        '$schema' = "https://schemastore.azurewebsites.net/schemas/json/sarif-2.1.0-rtm.4.json"
        runs = @()
    }

    # Define a complete list of 74 rules (adjust as per actual rules if available)
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
                name = $jsonData.tool.name
                version = $jsonData.tool.version
                informationUri = "https://github.com/github/codeql"
                rules = $fullRulesList
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
                            startLine = 10 + $i
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
    Write-Output "Conversion complete! SARIF file saved to $sarifFile for analysis ID $analysisId."

    # Step 3: Upload SARIF file to target repository
    Write-Output "Uploading SARIF file to GitHub for analysis ID $analysisId..."
    $sarifContent = Get-Content -Path $sarifFile -Raw
    $memoryStream = New-Object System.IO.MemoryStream
    $gzipStream = New-Object System.IO.Compression.GzipStream($memoryStream, [System.IO.Compression.CompressionMode]::Compress)
    $streamWriter = New-Object System.IO.StreamWriter($gzipStream)

    try {
        $streamWriter.Write($sarifContent)
        $streamWriter.Close()
        $gzipBase64 = [Convert]::ToBase64String($memoryStream.ToArray())
    } catch {
        Write-Output ("Error during compression and encoding for analysis ID ${analysisId}: " + $_)
        continue
    } finally {
        $memoryStream.Close()
        $gzipStream.Close()
    }

    $response = Invoke-RestMethod -Uri "https://api.github.com/repos/$targetOwner/$targetRepo/code-scanning/sarifs" `
        -Headers @{
            Authorization = "token $githubToken"
            Accept = "application/vnd.github+json"
        } `
        -Method Post `
        -Body (@{
            commit_sha = $commitSHA
            ref = $branchRef
            sarif = $gzipBase64
            tool_name = "CodeQL"
        } | ConvertTo-Json -Depth 10)

    if ($response -and $response.id) {
        Write-Output "SARIF upload successful for analysis ID $analysisId! Analysis ID: $($response.id)"
    } else {
        Write-Output "Failed to upload SARIF file for analysis ID $analysisId."
        Write-Output $response | Format-Table -AutoSize
    }
}

Write-Output "All analyses processed."
