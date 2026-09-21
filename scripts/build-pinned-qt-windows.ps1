param(
  [string]$Prefix = ".qt-windows/6.8.4",
  [string]$WorkDir = ".qt-windows-build",
  [string]$SourceArchive = "dist/compliance/source/qtbase-everywhere-opensource-src-6.8.4.tar.xz",
  [string]$PatchDir = "dist/compliance/source/patches"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$policy = Get-Content (Join-Path $repoRoot "release/qt-runtime-policy.json") -Raw | ConvertFrom-Json

if ($policy.qt_version -ne "6.8.4") {
  throw "unexpected Qt version in policy: $($policy.qt_version)"
}

$prefixPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $Prefix))
$workPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $WorkDir))
$archivePath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $SourceArchive))
$patchPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PatchDir))

if ((Test-Path (Join-Path $prefixPath "bin/qmake.exe")) -or
    (Test-Path (Join-Path $prefixPath "bin/qmake6.exe"))) {
  Write-Output "Using existing pinned Qt prefix: $prefixPath"
  exit 0
}

$sourceStage = Join-Path $workPath "source"
$buildDir = Join-Path $workPath "build"
Remove-Item -Recurse -Force $sourceStage, $buildDir, $prefixPath -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $buildDir, $prefixPath | Out-Null

$sourceOutput = & python (Join-Path $repoRoot "scripts/prepare-pinned-qt-source.py") `
  $archivePath $patchPath $sourceStage
if ($LASTEXITCODE -ne 0) { throw "failed to prepare pinned Qt source" }
$sourceDir = ($sourceOutput | Select-Object -Last 1).Trim()
$configure = Join-Path $sourceDir "configure.bat"
if (-not (Test-Path $configure)) { throw "Qt configure.bat was not found: $configure" }

Push-Location $buildDir
try {
  & $configure `
    -prefix $prefixPath `
    -release `
    -shared `
    -no-icu `
    -opengl dynamic `
    -qt-zlib `
    -qt-libpng `
    -qt-libjpeg `
    -qt-pcre `
    -nomake examples `
    -nomake tests `
    -- `
    -DQT_BUILD_EXAMPLES_BY_DEFAULT=OFF `
    -DQT_BUILD_TESTS_BY_DEFAULT=OFF
  if ($LASTEXITCODE -ne 0) { throw "Qt configure failed with exit code $LASTEXITCODE" }

  cmake --build . --parallel $(if ($env:BEZEL_QT_BUILD_JOBS) { $env:BEZEL_QT_BUILD_JOBS } else { "2" })
  if ($LASTEXITCODE -ne 0) { throw "Qt build failed with exit code $LASTEXITCODE" }
  cmake --install .
  if ($LASTEXITCODE -ne 0) { throw "Qt install failed with exit code $LASTEXITCODE" }
}
finally {
  Pop-Location
}

$qmake = @(
  (Join-Path $prefixPath "bin/qmake6.exe"),
  (Join-Path $prefixPath "bin/qmake.exe")
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $qmake) { throw "qmake missing from pinned Qt install" }
$pluginDir = (& $qmake -query QT_INSTALL_PLUGINS | Select-Object -First 1).Trim()

foreach ($required in @(
  (Join-Path $prefixPath "bin/Qt6Core.dll"),
  (Join-Path $prefixPath "bin/Qt6Gui.dll"),
  (Join-Path $prefixPath "bin/Qt6Widgets.dll"),
  (Join-Path $pluginDir "platforms/qwindows.dll"),
  (Join-Path $pluginDir "platforms/qoffscreen.dll")
)) {
  if (-not (Test-Path $required)) { throw "pinned Qt build missing: $required" }
}

@"
Qt version: $($policy.qt_version)
Source archive: $($policy.source_archive)
Source SHA-256: $($policy.source_sha256)
Security review date: $($policy.security_reviewed_through)
Build profile: windows-x86_64-source-shared-no-icu-official-security-patches
Linkage: shared DLLs
ICU: disabled
"@ | Set-Content -Path (Join-Path $prefixPath "BEZEL-QT-BUILD.txt") -Encoding utf8

Write-Output "Pinned Windows QtBase ready: $prefixPath"
