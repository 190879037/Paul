# Build ClearyDisplay.exe from GammaTuner.ps1
$ErrorActionPreference = 'Stop'
$src = Join-Path $env:LOCALAPPDATA 'ClearyDisplay\GammaTuner.ps1'
$outDir = Join-Path $env:LOCALAPPDATA 'ClearyDisplay\dist'
$outExe = Join-Path $outDir 'ClearyDisplay.exe'
$deskExe = Join-Path ([Environment]::GetFolderPath('Desktop')) 'ClearyDisplay.exe'

if (-not (Test-Path $src)) { throw "Missing: $src" }
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$raw = [IO.File]::ReadAllText($src)
[IO.File]::WriteAllText($src, $raw, (New-Object System.Text.UTF8Encoding $true))

if (-not (Get-Module -ListAvailable -Name ps2exe)) {
  Write-Host 'Installing ps2exe module...'
  Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
  Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
  Install-Module ps2exe -Scope CurrentUser -Force -AllowClobber
}
Import-Module ps2exe -Force

$iconFile = Join-Path $env:LOCALAPPDATA 'ClearyDisplay\ClearyDisplay.ico'
if (-not (Test-Path $iconFile)) { throw "Missing icon: $iconFile" }

Write-Host "Building $outExe ..."
# ASCII-only metadata to avoid encoding issues with Invoke-ps2exe
ps2exe -inputFile $src -outputFile $outExe -noConsole -sta `
  -iconFile $iconFile `
  -title 'ClearyDisplay' `
  -description 'Display and font tuner' `
  -company 'ClearyDisplay' `
  -product 'ClearyDisplay' `
  -version '1.8.0.1'

if (-not (Test-Path $outExe)) { throw 'Build failed: exe not created' }
Copy-Item -Force $outExe $deskExe
$size = [math]::Round((Get-Item $outExe).Length / 1KB, 1)
Write-Host "OK: $outExe ($size KB)"
Write-Host "Desktop: $deskExe"
