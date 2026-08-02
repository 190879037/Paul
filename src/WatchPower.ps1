# ClearyDisplay - re-apply AC/Battery profile on power change
$ErrorActionPreference = 'SilentlyContinue'
$apply = Join-Path $env:LOCALAPPDATA 'ClearyDisplay\ApplyProfile.ps1'
$logFile = Join-Path $env:LOCALAPPDATA 'ClearyDisplay\watch.log'
function Write-Log([string]$msg) {
  Add-Content -Path $logFile -Value (('{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg)) -Encoding UTF8 -EA SilentlyContinue
}
function Invoke-Apply([string]$reason) {
  Write-Log ("Trigger: {0}" -f $reason)
  if (Test-Path $apply) {
    Start-Sleep -Seconds 2
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $apply -Force
  }
}
Write-Log 'Watcher started'
Invoke-Apply 'startup'
try {
  Register-WmiEvent -Query 'SELECT * FROM Win32_PowerManagementEvent WHERE EventType = 10' -SourceIdentifier 'ClearyDisplayPower' -Action {
    Start-Sleep -Seconds 2
    $script = Join-Path $env:LOCALAPPDATA 'ClearyDisplay\ApplyProfile.ps1'
    if (Test-Path $script) {
      & powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $script -Force
    }
  } | Out-Null
  Write-Log 'Registered power event'
} catch {
  Write-Log ('WMI fail: ' + $_.Exception.Message)
}
while ($true) { Start-Sleep -Seconds 3600 }