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

# windeployqt focuses on the normal Windows QPA plugin. Bezel's automated
# tests and many CI/server users also need the offscreen backend, so include it
# explicitly when the Qt installation provides it.
$pluginDir = $null
$qtpaths = Get-Command qtpaths6.exe, qtpaths.exe -ErrorAction SilentlyContinue | Select-Object -First 1
if ($qtpaths) {
  $pluginDir = (& $qtpaths.Source --plugin-dir | Select-Object -First 1).Trim()
}
if (-not $pluginDir) {
  $qmake = Get-Command qmake6.exe, qmake.exe -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($qmake) {
    $pluginDir = (& $qmake.Source -query QT_INSTALL_PLUGINS | Select-Object -First 1).Trim()
  }
}
if ($pluginDir -and (Test-Path (Join-Path $pluginDir "platforms"))) {
  New-Item -ItemType Directory -Force -Path (Join-Path $root "platforms") | Out-Null
  foreach ($name in @("qoffscreen.dll", "qminimal.dll")) {
    $source = Join-Path $pluginDir "platforms/$name"
    if (Test-Path $source) { Copy-Item $source (Join-Path $root "platforms/$name") -Force }
  }
}

foreach ($required in @(
  "bezel.dll",
  "Qt6Core.dll",
  "Qt6Gui.dll",
  "Qt6Widgets.dll",
  "platforms/qwindows.dll",
  "platforms/qoffscreen.dll"
)) {
  $path = Join-Path $root $required
  if (-not (Test-Path $path)) { throw "required runtime file is missing: $required" }
}

Compress-Archive -Path $root -DestinationPath $archive -CompressionLevel Optimal
Write-Output $archive
