param(
  [string]$BuildDir = "bezel-shim/build",
  [string]$DistDir = "dist"
)

$ErrorActionPreference = "Stop"

$arch = $env:PROCESSOR_ARCHITECTURE
switch ($arch) {
  "AMD64" { $arch = "x86_64" }
  "ARM64" { $arch = "aarch64" }
  default { $arch = $arch.ToLowerInvariant() }
}

$asset = "bezel-native-windows-$arch"
$root = Join-Path $DistDir $asset
$archive = Join-Path $DistDir "$asset.zip"

Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
Remove-Item -Force $archive -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $root | Out-Null

$probe = @(
  (Join-Path $BuildDir "bezel-deploy-probe.exe"),
  (Join-Path $BuildDir "Release/bezel-deploy-probe.exe")
) | Where-Object { Test-Path $_ } | Select-Object -First 1

$shim = @(
  (Join-Path $BuildDir "bezel.dll"),
  (Join-Path $BuildDir "Release/bezel.dll")
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $probe) { throw "bezel-deploy-probe.exe was not found in $BuildDir" }
if (-not $shim) { throw "bezel.dll was not found in $BuildDir" }

$deploy = (Get-Command windeployqt.exe -ErrorAction Stop).Source
& $deploy --release --no-translations --dir $root $probe
if ($LASTEXITCODE -ne 0) { throw "windeployqt failed with exit code $LASTEXITCODE" }

Copy-Item $shim (Join-Path $root "bezel.dll") -Force

foreach ($required in @(
  "bezel.dll",
  "Qt6Core.dll",
  "Qt6Gui.dll",
  "Qt6Widgets.dll",
  "platforms/qwindows.dll"
)) {
  $path = Join-Path $root $required
  if (-not (Test-Path $path)) { throw "required runtime file is missing: $required" }
}

Compress-Archive -Path $root -DestinationPath $archive -CompressionLevel Optimal
Write-Output $archive
