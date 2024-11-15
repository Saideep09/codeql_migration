# Set the source and target repository details
$SOURCE_REPO = "saideep11111/source2"   # Replace with your source repo
$TARGET_REPO = "saideep11112/s2"   # Replace with your target repo
$TARGET_REF = "refs/heads/main"         # Target branch reference
$githubToken = "Put_Token"      # Replace with your GitHub token

# Set the base directory for all files
$baseDir = "C:\Users\saide\OneDrive\Desktop\bacd\codeql_migration"
Write-Output "Using base directory: $baseDir"

# Retrieve the latest commit SHA for the target branch in the target repository
Write-Output "Retrieving the latest commit SHA for the target repository..."
$TARGET_COMMIT_SHA = gh api -X GET "/repos/$TARGET_REPO/commits/main" --jq '.sha'

# Ensure the commit SHA was retrieved
if (-not $TARGET_COMMIT_SHA) {
    Write-Output "Failed to retrieve the latest commit SHA for the target repository. Exiting."
    exit 1
}
Write-Output "Using commit SHA: $TARGET_COMMIT_SHA"

# Process each analysis in the source repository
$analysis_ids = gh api -X GET "/repos/$SOURCE_REPO/code-scanning/analyses" --jq '.[].id'

foreach ($analysis_id in $analysis_ids) {
    Write-Output "Processing analysis ID: $analysis_id from source repository..."

    # Define absolute paths for temporary files
    $jsonFile = Join-Path -Path $baseDir -ChildPath "temp_analysis_$analysis_id.json"
    $sarifFile = Join-Path -Path $baseDir -ChildPath "temp_analysis_$analysis_id.sarif"
    $gzipFile = "$sarifFile.gz"

    # Download JSON data for the current analysis
    Write-Output "Downloading JSON data for analysis ID: $analysis_id..."
    & gh api -X GET "/repos/$SOURCE_REPO/code-scanning/analyses/$analysis_id" > $jsonFile

    # Verify the JSON file was downloaded
    if (!(Test-Path -Path $jsonFile)) {
        Write-Output "Failed to download JSON data for analysis ID: $analysis_id. Skipping."
        continue
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

    # Save the SARIF data to a file and confirm its existence
    $sarifData | ConvertTo-Json -Depth 10 | Set-Content -Path $sarifFile -Force
    Write-Output "Conversion complete! SARIF file saved to $sarifFile"

    if (!(Test-Path -Path $sarifFile)) {
        Write-Output "Error: SARIF file not found after creation: $sarifFile. Skipping analysis ID $analysis_id."
        continue
    }

    # Compress the SARIF file and encode it in Base64
    Write-Output "Compressing and encoding SARIF file..."
    
    try {
        # Ensure the gzip file does not already exist
        if (Test-Path -Path $gzipFile) {
            Remove-Item -Path $gzipFile -Force
        }

        # Compress SARIF file with GzipStream
        $sarifContent = [System.IO.File]::ReadAllBytes($sarifFile)
        $gzipStream = New-Object System.IO.MemoryStream
        $gzipCompressor = New-Object System.IO.Compression.GzipStream $gzipStream, ([System.IO.Compression.CompressionMode]::Compress)

        $gzipCompressor.Write($sarifContent, 0, $sarifContent.Length)
        $gzipCompressor.Close()

        # Write compressed content to gzip file
        [System.IO.File]::WriteAllBytes($gzipFile, $gzipStream.ToArray())
        Write-Output "Gzip compression complete."

        if (!(Test-Path -Path $gzipFile)) {
            Write-Output "Failed to create gzip file: $gzipFile. Skipping this analysis."
            continue
        }

        # Convert the compressed file to Base64
        $gzipBase64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($gzipFile))
        Write-Output "Compression and encoding successful."

    } catch {
        Write-Output "Error during compression and encoding for analysis ID $analysis_id. Skipping."
        Write-Output "Exception Message: $($_.Exception.Message)"
        continue
    }

    # Upload the SARIF content to the target repository
    Write-Output "Uploading SARIF for analysis ID: $analysis_id to the target repository..."
    $response = Invoke-RestMethod -Uri "https://api.github.com/repos/$TARGET_REPO/code-scanning/sarifs" `
        -Headers @{
            Authorization = "token $githubToken"
            Accept = "application/vnd.github+json"
        } `
        -Method Post `
        -Body (@{
            commit_sha = $TARGET_COMMIT_SHA
            ref = $TARGET_REF
            sarif = $gzipBase64
            tool_name = "CodeQL"  # Replace with the name of the tool generating the SARIF
        } | ConvertTo-Json -Depth 10)

    # Check the response
    if ($response.id) {
        Write-Output "SARIF upload successful! Analysis ID: $($response.id)"
    } else {
        Write-Output "Failed to upload SARIF file."
        Write-Output $response | Format-Table -AutoSize
    }

    # Cleanup
    Remove-Item -Path $jsonFile, $sarifFile, $gzipFile
}

Write-Output "Migration of all analyses completed."
