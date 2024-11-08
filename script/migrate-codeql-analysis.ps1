# Set the source and target repository details
$SOURCE_REPO = "saideep11111/source2"   # Replace with your source repo
$TARGET_REPO = "saideep11112/source2"   # Replace with your target repo
$TARGET_REF = "refs/heads/main"         # Target branch reference

# Retrieve the latest commit SHA for the target branch in the target repository
Write-Output "Retrieving the latest commit SHA for the target repository..."
$TARGET_COMMIT_SHA = gh api -X GET "/repos/$TARGET_REPO/commits/main" --jq '.sha'

# Ensure the commit SHA was retrieved
if (!$TARGET_COMMIT_SHA) {
    Write-Output "Failed to retrieve the latest commit SHA for the target repository. Exiting."
    exit 1
}
Write-Output "Using commit SHA: $TARGET_COMMIT_SHA"

# Process each analysis in the source repository
$analysis_ids = gh api -X GET "/repos/$SOURCE_REPO/code-scanning/analyses" --jq '.[].id'

foreach ($analysis_id in $analysis_ids) {
    Write-Output "Processing analysis ID: $analysis_id from source repository..."

    # Download SARIF content for the current analysis and save it to a file
    $sarif_content = gh api -X GET "/repos/$SOURCE_REPO/code-scanning/analyses/$analysis_id" --jq '.sarif' | Out-String
    $sarif_path = "temp_analysis_$analysis_id.sarif"
    $sarif_compressed_path = "$sarif_path.gz"
    $sarif_base64_path = "$sarif_compressed_path.b64"

    # Debugging output: Check if SARIF content is correctly fetched
    if (-not $sarif_content.Trim()) {
        Write-Output "SARIF content is empty. Skipping analysis ID $analysis_id."
        continue
    }
    
    Write-Output "Debug: SARIF Content Preview (first 500 characters):"
    Write-Output $sarif_content.Substring(0, [Math]::Min(500, $sarif_content.Length))

    # Save the SARIF content to a file
    Out-File -FilePath $sarif_path -InputObject $sarif_content -Encoding UTF8
    Write-Output "SARIF content saved to $sarif_path."

    # Compress the SARIF file using gzip
    Write-Output "Compressing SARIF file..."
    try {
        gzip -c $sarif_path > $sarif_compressed_path
    } catch {
        Write-Output "Error during gzip compression for analysis ID $analysis_id. Skipping."
        continue
    }
    Write-Output "Compression successful: $sarif_compressed_path"

    # Convert the compressed SARIF file to Base64
    Write-Output "Encoding compressed SARIF to Base64..."
    try {
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($sarif_compressed_path)) | Out-File -Encoding ASCII -NoNewline $sarif_base64_path
        $sarif_base64 = Get-Content -Path $sarif_base64_path -Raw
    } catch {
        Write-Output "Error during Base64 encoding for analysis ID $analysis_id. Skipping."
        continue
    }
    Write-Output "Base64 encoding completed."

    # Upload the SARIF content to the target repository
    Write-Output "Uploading SARIF for analysis ID: $analysis_id to the target repository..."
    $response = gh api -X POST `
        -H "Authorization: token $env:GITHUB_TOKEN" `
        -H "Accept: application/vnd.github+json" `
        repos/$TARGET_REPO/code-scanning/sarifs `
        -F "commit_sha=$TARGET_COMMIT_SHA" `
        -F "ref=$TARGET_REF" `
        -F "sarif=$sarif_base64"

    Write-Output "Upload response: $response"

    # Cleanup
    Remove-Item -Path $sarif_path, $sarif_compressed_path, $sarif_base64_path
}

Write-Output "Migration of all analyses completed."
