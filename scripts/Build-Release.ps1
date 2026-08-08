# Build ClearyDisplay.exe + Inno Setup installer
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

$iscc = Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'
if (-not (Test-Path $iscc)) {
  $iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
}
if (-not (Test-Path $iscc)) { throw "Inno Setup ISCC.exe not found. Install JRSoftware.InnoSetup via winget." }

$src = Join-Path $root 'src\GammaTuner.ps1'
$outExe = Join-Path $root 'dist\ClearyDisplay.exe'
$ico = Join-Path $root 'assets\ClearyDisplay.ico'
New-Item -ItemType Directory -Force -Path (Join-Path $root 'dist') | Out-Null

# Ensure UTF-8 BOM for ps2exe
$raw = [IO.File]::ReadAllText($src)
[IO.File]::WriteAllText($src, $raw, (New-Object System.Text.UTF8Encoding $true))

if (-not (Get-Module -ListAvailable -Name ps2exe)) {
  Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
  Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
  Install-Module ps2exe -Scope CurrentUser -Force -AllowClobber
}
Import-Module ps2exe -Force

Write-Host "Building EXE..."
ps2exe -inputFile $src -outputFile $outExe -noConsole -sta `
  -iconFile $ico `
  -title 'ClearyDisplay' `
  -description 'Display and font tuner' `
  -company 'ClearyDisplay' `
  -product 'ClearyDisplay' `
  -version '1.7.13.0'

if (-not (Test-Path $outExe)) { throw 'EXE build failed' }

Write-Host "Building installer..."
& $iscc (Join-Path $root 'installer\ClearyDisplay.iss')
$setup = Get-ChildItem (Join-Path $root 'dist') -Filter 'ClearyDisplay-Setup-*.exe' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $setup) { throw 'Installer not produced' }

Write-Host "OK:"
Write-Host "  EXE:  $outExe"
Write-Host "  Setup: $($setup.FullName) ($([math]::Round($setup.Length/1KB,1)) KB)"
