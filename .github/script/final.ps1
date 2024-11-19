param(
    [string]$sourceOrg,
    [string]$sourceRepo,
    [string]$targetOrg,
    [string]$targetRepo,
    [string]$sourceToken,
    [string]$targetToken
)

# Define parameters
$sourceOwner = $sourceOrg
$sourceRepo = $sourceRepo
$targetOwner = $targetOrg
$targetRepo = $targetRepo
$sarifDirectory = "./sarif_files"  # Directory to store SARIF files
$branchRef = "refs/heads/main"     # Branch reference in the target repository

# Create SARIF directory if it doesn't exist
if (!(Test-Path -Path $sarifDirectory)) {
    New-Item -ItemType Directory -Path $sarifDirectory
}

# --- Fetch the Latest Commit SHA from Target Repository ---
Write-Output "Fetching the latest commit SHA from the target repository..."
$latestCommitUrl = "https://api.github.com/repos/$targetOwner/$targetRepo/commits/$branchRef"
$latestCommit = & gh api -X GET $latestCommitUrl -H "Authorization: token $targetToken" | ConvertFrom-Json

if ($latestCommit.sha) {
    $latestCommitSha = $latestCommit.sha
    Write-Output "Using commit SHA: $latestCommitSha for SARIF uploads."
} else {
    Write-Error "Failed to fetch the latest commit SHA. Exiting."
    exit
}

# --- Migrate Alerts ---
Write-Output "Fetching alerts from the source repository..."
$alertsUrl = "https://api.github.com/repos/$sourceOwner/$sourceRepo/code-scanning/alerts"
$alertsList = & gh api -X GET $alertsUrl -H "Authorization: token $sourceToken" | ConvertFrom-Json

if ($alertsList) {
    Write-Output "Converting alerts to SARIF format..."
    $sarifDataAlerts = @{
        version = "2.1.0"
        '$schema' = "https://schemastore.azurewebsites.net/schemas/json/sarif-2.1.0-rtm.4.json"
        runs = @()
    }

    $sarifRunAlerts = @{
        tool = @{
            driver = @{
                name = "CodeQL"
                version = "2.19.3"
                informationUri = "https://github.com/github/codeql"
                rules = @()
            }
        }
        results = @()
    }

    foreach ($alert in $alertsList) {
        $ruleId = $alert.rule.id

        # Add rule to SARIF rules section if not already added
        if (-not ($sarifRunAlerts.tool.driver.rules | Where-Object { $_.id -eq $ruleId })) {
            $sarifRunAlerts.tool.driver.rules += @{
                id = $ruleId
                name = $alert.rule.name
                fullDescription = @{ text = $alert.rule.full_description }
                helpUri = "https://github.com/github/codeql"
                properties = @{
                    tags = $alert.rule.tags
                    severity = $alert.rule.severity
                }
            }
        }

        # Add alert data to SARIF results
        $sarifRunAlerts.results += @{
            ruleId = $ruleId
            message = @{
                text = $alert.most_recent_instance.message.text
            }
            locations = @(
                @{
                    physicalLocation = @{
                        artifactLocation = @{
                            uri = $alert.most_recent_instance.location.path
                        }
                        region = @{
                            startLine = $alert.most_recent_instance.location.start_line
                            endLine = $alert.most_recent_instance.location.end_line
                            startColumn = $alert.most_recent_instance.location.start_column
                            endColumn = $alert.most_recent_instance.location.end_column
                        }
                    }
                }
            )
            properties = @{
                state = $alert.state
                severity = $alert.rule.severity
                fixedAt = $alert.fixed_at
            }
        }
    }

    # Add run to SARIF data
    $sarifDataAlerts.runs += $sarifRunAlerts

    # Save SARIF file for alerts
    $sarifFileAlerts = "$sarifDirectory\alerts.sarif"
    $sarifDataAlerts | ConvertTo-Json -Depth 10 | Set-Content -Path $sarifFileAlerts -Force
    Write-Output "SARIF file for alerts created at $sarifFileAlerts."
}

# --- Migrate Analyses ---
Write-Output "Fetching analyses from the source repository..."
$analysesUrl = "https://api.github.com/repos/$sourceOwner/$sourceRepo/code-scanning/analyses"
$analysesList = & gh api -X GET $analysesUrl -H "Authorization: token $sourceToken" | ConvertFrom-Json

foreach ($analysis in $analysesList) {
    $analysisId = $analysis.id
    $sarifFileAnalysis = "$sarifDirectory\analysis_$analysisId.sarif"

    # Fetch analysis data
    $analysisDetailsUrl = "https://api.github.com/repos/$sourceOwner/$sourceRepo/code-scanning/analyses/$analysisId"
    $analysisData = & gh api -X GET $analysisDetailsUrl -H "Authorization: token $sourceToken" | ConvertFrom-Json

    if (-not $analysisData.results_count -or $analysisData.results_count -eq 0) {
        Write-Output "Skipping analysis $analysisId as it has no results."
        continue
    }

    $sarifDataAnalysis = @{
        version = "2.1.0"
        '$schema' = "https://schemastore.azurewebsites.net/schemas/json/sarif-2.1.0-rtm.4.json"
        runs = @()
    }

    $sarifRunAnalysis = @{
        tool = @{
            driver = @{
                name = $analysisData.tool.name
                version = $analysisData.tool.version
                informationUri = "https://github.com/github/codeql"
            }
        }
        results = @()
    }

    foreach ($result in $analysisData.results) {
        $sarifRunAnalysis.results += @{
            ruleId = $result.ruleId
            message = @{
                text = $result.message.text
            }
            locations = @(
                @{
                    physicalLocation = @{
                        artifactLocation = @{
                            uri = $result.location.path
                        }
                        region = @{
                            startLine = $result.location.startLine
                            endLine = $result.location.endLine
                            startColumn = $result.location.startColumn
                            endColumn = $result.location.endColumn
                        }
                    }
                }
            )
        }
    }

    $sarifDataAnalysis.runs += $sarifRunAnalysis

    # Save SARIF file for analysis
    $sarifDataAnalysis | ConvertTo-Json -Depth 10 | Set-Content -Path $sarifFileAnalysis -Force
    Write-Output "SARIF file for analysis $analysisId created at $sarifFileAnalysis."
}

# --- Upload All SARIF Files ---
$allSarifFiles = Get-ChildItem -Path $sarifDirectory -Filter *.sarif

foreach ($sarifFile in $allSarifFiles) {
    Write-Output "Uploading $($sarifFile.Name) to target repository..."
    $sarifContent = Get-Content -Path $sarifFile.FullName -Raw
    $memoryStream = New-Object System.IO.MemoryStream
    $gzipStream = New-Object System.IO.Compression.GzipStream($memoryStream, [System.IO.Compression.CompressionMode]::Compress)
    $streamWriter = New-Object System.IO.StreamWriter($gzipStream)

    try {
        $streamWriter.Write($sarifContent)
        $streamWriter.Close()
        $gzipBase64 = [Convert]::ToBase64String($memoryStream.ToArray())
    } catch {
        Write-Error "Error compressing SARIF file: $($_.Exception.Message)"
        continue
    } finally {
        $memoryStream.Close()
        $gzipStream.Close()
    }

    $response = Invoke-RestMethod -Uri "https://api.github.com/repos/$targetOwner/$targetRepo/code-scanning/sarifs" `
        -Headers @{
            Authorization = "token $targetToken"
            Accept = "application/vnd.github+json"
        } `
        -Method Post `
        -Body (@{
            commit_sha = $latestCommitSha
            ref = $branchRef
            sarif = $gzipBase64
            tool_name = "CodeQL"
        } | ConvertTo-Json -Depth 10)

    if ($response -and $response.id) {
        Write-Output "Uploaded SARIF file: $($sarifFile.Name) successfully. Analysis ID: $($response.id)"
    } else {
        Write-Error "Failed to upload SARIF file: $($sarifFile.Name)."
    }
}

Write-Output "Migration process completed."
