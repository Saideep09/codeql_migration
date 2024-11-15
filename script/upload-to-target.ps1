# Define parameters
$owner = "saideep11112"  # Replace with the target repo's owner
$repo = "S1"  # Replace with the target repo name
$sarifFile = "C:\Users\saide\OneDrive\Desktop\bacd\codeql_migration\analysis.sarif"  # Path to your SARIF file
$githubToken = "Put_token"  # Replace with your GitHub token
$commitSHA = "93eb9b74e98ec27f04e04e561fb2b8dc3f5f4bac"  # Replace with the actual 40-character commit SHA
$branchRef = "refs/heads/main"  # The branch reference

# Verify the SARIF file exists
if (!(Test-Path -Path $sarifFile)) {
    Write-Output "SARIF file not found at $sarifFile"
    exit
}

# Read SARIF content
Write-Output "Reading SARIF file content..."
$sarifContent = Get-Content -Path $sarifFile -Raw

# Compress the SARIF content and encode it in Base64
Write-Output "Compressing and encoding SARIF content..."
$memoryStream = New-Object System.IO.MemoryStream
$gzipStream = New-Object System.IO.Compression.GzipStream($memoryStream, [System.IO.Compression.CompressionMode]::Compress)
$streamWriter = New-Object System.IO.StreamWriter($gzipStream)

$streamWriter.Write($sarifContent)
$streamWriter.Close()
$gzipBase64 = [Convert]::ToBase64String($memoryStream.ToArray())

# Upload SARIF file to GitHub
Write-Output "Uploading SARIF file to GitHub code scanning API..."
$response = Invoke-RestMethod -Uri "https://api.github.com/repos/$owner/$repo/code-scanning/sarifs" `
    -Headers @{
        Authorization = "token $githubToken"
        Accept = "application/vnd.github+json"
    } `
    -Method Post `
    -Body (@{
        commit_sha = $commitSHA
        ref = $branchRef
        sarif = $gzipBase64
        tool_name = "CodeQL"  # Adjust if your tool name differs
    } | ConvertTo-Json -Depth 10)

# Check the response
if ($response.id) {
    Write-Output "SARIF upload successful! Analysis ID: $($response.id)"
} else {
    Write-Output "Failed to upload SARIF file."
    Write-Output $response | Format-Table -AutoSize
}

# Cleanup
$memoryStream.Close()
$gzipStream.Close()
