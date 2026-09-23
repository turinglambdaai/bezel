# sign-app-windows.ps1 — Authenticode signing helper for a packaged
# Bezel application (the folder produced by `raco bezel package`).
#
# Requires the Windows SDK signtool and a code-signing certificate in the
# local certificate store (or on a smart card / HSM referenced by
# thumbprint). For a cloud/HSM signing service, replace the signtool
# invocation with your provider's equivalent step.
#
# Usage:
#   ./scripts/sign-app-windows.ps1 -AppDir dist/MyApp `
#                                  -Thumbprint <cert-sha1-thumbprint> `
#                                  [-TimestampServer http://timestamp.digicert.com]

param(
    [Parameter(Mandatory = $true)]
    [string]$AppDir,

    [Parameter(Mandatory = $true)]
    [string]$Thumbprint,

    [string]$TimestampServer = "http://timestamp.digicert.com"
)

$ErrorActionPreference = "Stop"

$signtool = (Get-Command signtool.exe -ErrorAction SilentlyContinue)
if (-not $signtool) {
    # Fall back to the Windows SDK install location.
    $sdk = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin" `
        -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        Select-Object -First 1
    if ($sdk) {
        $candidate = Join-Path $sdk.FullName "x64\signtool.exe"
        if (Test-Path $candidate) { $signtool = $candidate }
    }
}
if (-not $signtool) {
    throw "signtool.exe not found. Install the Windows SDK (Signing Tools feature)."
}

$targets = @(Get-ChildItem -Path $AppDir -Recurse -Include *.exe, *.dll |
    ForEach-Object { $_.FullName })
if ($targets.Count -eq 0) {
    throw "No .exe/.dll files found under $AppDir"
}

Write-Host "Signing $($targets.Count) files under $AppDir"
foreach ($file in $targets) {
    & $signtool sign /fd SHA256 /td SHA256 /tr $TimestampServer /sha1 $Thumbprint $file
    if ($LASTEXITCODE -ne 0) { throw "signtool failed on $file" }
    & $signtool verify /pa /v $file
    if ($LASTEXITCODE -ne 0) { throw "signature verification failed on $file" }
    Write-Host "  signed: $file"
}
Write-Host "All files signed and verified."
