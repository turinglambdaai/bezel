param(
  [string]$BuildDir = "bezel-shim/build",
  [string]$DistDir = "dist",
  [string]$ComplianceDir = "dist/compliance/runtime-licenses"
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

if (-not (Test-Path $ComplianceDir -PathType Container)) {
  throw "license compliance material is missing: $ComplianceDir"
}

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
# Public Bezel binaries intentionally redistribute Bezel + Qt only. Compiler
# runtimes and optional Microsoft graphics fallback DLLs are host prerequisites,
# avoiding accidental third-party redistribution under unrelated license terms.
& $deploy --release --no-translations --no-compiler-runtime `
  --no-system-d3d-compiler --no-system-dxc-compiler --no-opengl-sw `
  --dir $root $probe
if ($LASTEXITCODE -ne 0) { throw "windeployqt failed with exit code $LASTEXITCODE" }

Copy-Item $shim (Join-Path $root "bezel.dll") -Force
Copy-Item $ComplianceDir (Join-Path $root "LICENSES") -Recurse -Force

# windeployqt focuses on the normal Windows QPA plugin. Include offscreen too
# for CI/rendering while keeping it inside the same QtBase provenance boundary.
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

@"
Bezel's official public Windows runtime does not redistribute the Microsoft
Visual C++ runtime. A compatible Microsoft Visual C++ 2015-2022 Redistributable
for the target architecture is an operating-system/application prerequisite.
Racket itself may already require and install a compatible runtime.
"@ | Set-Content -Path (Join-Path $root "SYSTEM-DEPENDENCIES.txt") -Encoding utf8

foreach ($required in @(
  "bezel.dll",
  "Qt6Core.dll",
  "Qt6Gui.dll",
  "Qt6Widgets.dll",
  "platforms/qwindows.dll",
  "platforms/qoffscreen.dll",
  "LICENSES/NOTICE.md",
  "LICENSES/RELINKING.md"
)) {
  $path = Join-Path $root $required
  if (-not (Test-Path $path)) { throw "required runtime file is missing: $required" }
}

# Fail closed if deployment starts copying compiler/Microsoft runtime DLLs or
# another unrelated top-level runtime into a public archive.
$forbidden = @(
  "MSVCP140.dll", "MSVCP140_1.dll", "VCRUNTIME140.dll", "VCRUNTIME140_1.dll",
  "concrt140.dll", "D3Dcompiler_47.dll", "dxcompiler.dll", "dxil.dll",
  "opengl32sw.dll"
)
foreach ($name in $forbidden) {
  if (Test-Path (Join-Path $root $name)) {
    throw "forbidden non-Qt redistributable found in public runtime: $name"
  }
}

Get-ChildItem -Path $root -File -Filter "*.dll" | ForEach-Object {
  if ($_.Name -ne "bezel.dll" -and $_.Name -notlike "Qt6*.dll") {
    throw "unexpected non-Qt top-level DLL in public runtime: $($_.Name)"
  }
}

$dumpbin = (Get-Command dumpbin.exe -ErrorAction Stop).Source
$dependencies = (& $dumpbin /DEPENDENTS $shim | Out-String)
foreach ($qtDll in @("Qt6Core.dll", "Qt6Gui.dll", "Qt6Widgets.dll")) {
  if ($dependencies -notmatch [regex]::Escape($qtDll)) {
    throw "bezel.dll is not dynamically linked to required $qtDll"
  }
}

Compress-Archive -Path $root -DestinationPath $archive -CompressionLevel Optimal
Write-Output $archive
