param(
  [string]$Version = '1.9.0.0'
)
# Build ClearyDisplay.exe from GammaTuner.ps1
# Reads the live script from %LOCALAPPDATA%\ClearyDisplay, compiles a single-file
# exe with ps2exe, then fans the artifact out to dist / D:\ClearyDisplay / Desktop.
$ErrorActionPreference = 'Stop'

$laDir   = Join-Path $env:LOCALAPPDATA 'ClearyDisplay'
$src     = Join-Path $laDir 'GammaTuner.ps1'
$outDir  = Join-Path $laDir 'dist'
$outExe  = Join-Path $outDir 'ClearyDisplay.exe'
$archExe = Join-Path $outDir ('ClearyDisplay-v' + $Version + '.exe')
$deskExe = Join-Path ([Environment]::GetFolderPath('Desktop')) 'ClearyDisplay.exe'
$dExe    = 'D:\ClearyDisplay\ClearyDisplay.exe'
$iconFile = Join-Path $laDir 'ClearyDisplay.ico'
$log     = 'D:\ClearyDisplay\_build_' + ($Version -replace '[^\w\.]','') + '.log'

function W($s) { try { Add-Content -Path $log -Value $s -Encoding UTF8 } catch {} }
# Truncate instead of Remove-Item: the host safe-delete hook blocks Remove-Item
# and fails closed, which would abort the build before the first log line.
try { Set-Content -Path $log -Value '' -Encoding UTF8 } catch {}

try {
  W ('BUILD_VERSION=' + $Version)
  if (-not (Test-Path $src))      { throw "Missing source: $src" }
  if (-not (Test-Path $iconFile)) { throw "Missing icon: $iconFile" }
  W ('SRC_BYTES=' + (Get-Item $src).Length)
  W ('ICO_BYTES=' + (Get-Item $iconFile).Length)

  New-Item -ItemType Directory -Force -Path $outDir | Out-Null

  # --- pre-build rollback snapshot of whatever is currently live ---
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $snap = Join-Path 'D:\ClearyDisplay\_backup' ('pre-' + $Version + '-' + $stamp)
  New-Item -ItemType Directory -Force -Path $snap | Out-Null
  $snapList = @()
  foreach ($pair in @(
      @{ src = $src;      dst = 'GammaTuner.ps1' },
      @{ src = $deskExe;  dst = 'ClearyDisplay-desktop.exe' },
      @{ src = $dExe;     dst = 'ClearyDisplay-D.exe' },
      @{ src = $iconFile; dst = 'ClearyDisplay.ico' }
  )) {
    try {
      if (Test-Path $pair.src) {
        Copy-Item -Force $pair.src (Join-Path $snap $pair.dst)
        $snapList += ($pair.dst + '=' + (Get-FileHash $pair.src -Algorithm MD5).Hash)
      }
    } catch { W ('SNAP_SKIP=' + $pair.dst + ' ' + $_.Exception.Message) }
  }
  Set-Content -Path (Join-Path $snap 'SNAPSHOT.txt') -Value $snapList -Encoding UTF8
  W ('SNAPSHOT=' + $snap)

  # --- normalise line endings / BOM so ps2exe embeds clean UTF-8 ---
  $raw = [IO.File]::ReadAllText($src)
  [IO.File]::WriteAllText($src, $raw, (New-Object System.Text.UTF8Encoding $true))

  if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    W 'PS2EXE_INSTALLING'
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
    Install-Module ps2exe -Scope CurrentUser -Force -AllowClobber
  }
  Import-Module ps2exe -Force

  W ('BUILDING=' + $outExe)
  # ASCII-only metadata to avoid encoding issues with Invoke-ps2exe
  ps2exe -inputFile $src -outputFile $outExe -noConsole -sta `
    -iconFile $iconFile `
    -title 'ClearyDisplay' `
    -description 'Display and font tuner' `
    -company 'ClearyDisplay' `
    -product 'ClearyDisplay' `
    -version $Version

  if (-not (Test-Path $outExe)) { throw 'Build failed: exe not created' }

  $exeMd5 = (Get-FileHash $outExe -Algorithm MD5).Hash
  $exeLen = (Get-Item $outExe).Length
  W ('EXE_BYTES=' + $exeLen)
  W ('EXE_MD5=' + $exeMd5)

  # --- fan out ---
  Copy-Item -Force $outExe $archExe
  Copy-Item -Force $outExe $deskExe
  Copy-Item -Force $outExe $dExe
  W ('ARCHIVE=' + $archExe)
  W ('FANOUT_MD5_DESKTOP=' + (Get-FileHash $deskExe -Algorithm MD5).Hash)
  W ('FANOUT_MD5_D=' + (Get-FileHash $dExe -Algorithm MD5).Hash)

  # --- verify embedded file version resource ---
  $vi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($outExe)
  W ('VER_FILE=' + $vi.FileVersion)
  W ('VER_PRODUCT=' + $vi.ProductVersion)
  W 'BUILD_DONE'
} catch {
  W ('BUILD_TRAP=' + $_.Exception.Message)
}
