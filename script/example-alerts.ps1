# Define paths for SARIF files
$workingDirectory = "C:\Users\saide\OneDrive\Desktop\bacd"
$sarifPath = Join-Path -Path $workingDirectory -ChildPath "minimal.sarif"
$compressedPath = "$sarifPath.gz"

# Create minimal SARIF JSON
$minimalSarifObject = @{
    version = "2.1.0"
    "`$schema" = "https://json.schemastore.org/sarif-2.1.0.json"
    runs = @(
        @{
            tool = @{
                driver = @{
                    name = "MinimalTool"
                    version = "1.0.0"
                    informationUri = "https://example.com/minimaltool"
                    rules = @(
                        @{
                            id = "MINIMAL001"
                            name = "Minimal Alert"
                            shortDescription = @{ text = "Minimal alert for SARIF testing." }
                        }
                    )
                }
            }
            results = @(
                @{
                    ruleId = "MINIMAL001"
                    message = @{ text = "Testing minimal SARIF upload functionality." }
                    locations = @(
                        @{
                            physicalLocation = @{
                                artifactLocation = @{ uri = "minimalfile.js" }
                                region = @{ startLine = 1 }
                            }
                        }
                    )
                }
            )
        }
    )
}

# Convert SARIF object to JSON and save to file
$minimalSarifJson = $minimalSarifObject | ConvertTo-Json -Depth 10
$minimalSarifJson | Out-File -FilePath $sarifPath -Encoding utf8
Write-Host "Successfully created minimal SARIF JSON file."

# Compress SARIF file to .gz
try {
    [System.IO.Compression.CompressionLevel]::Optimal | Out-Null
    $inputFile = [System.IO.File]::OpenRead($sarifPath)
    $outputFile = [System.IO.File]::Create($compressedPath)
    $gzipStream = New-Object System.IO.Compression.GzipStream($outputFile, [System.IO.Compression.CompressionMode]::Compress)
    $inputFile.CopyTo($gzipStream)
    $gzipStream.Close()
    $outputFile.Close()
    $inputFile.Close()
    Write-Host "Successfully compressed SARIF file."
}
catch {
    Write-Host "Error compressing SARIF file: $_"
    exit 1
}

# Base64 encode the .gz file
$minimalSarifBase64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($compressedPath))

# Set up API request headers
$headers = @{
    Authorization = "token put_token"  # Replace with your actual GitHub token
    Accept = "application/vnd.github+json"
}

# Define the API request body
$body = @{
    commit_sha = "dd10f1307219da1a70d8201d9b31e846632f02b1"  # Replace with actual commit SHA
    ref = "refs/heads/main"
    sarif = $minimalSarifBase64
} | ConvertTo-Json

# Output the request body for debugging
Write-Host "Request body (first 500 characters):"
Write-Host $body.Substring(0, [math]::Min(500, $body.Length))

# Upload the SARIF file to GitHub
try {
    $response = Invoke-RestMethod -Uri "https://api.github.com/repos/saideep11112/s2/code-scanning/sarifs" `
        -Method Post -Headers $headers -Body $body -ContentType "application/json"
    Write-Host "Minimal SARIF upload successful."
    Write-Host "Response:" $response
}
catch {
    Write-Host "Error uploading minimal SARIF file: $_"
}
