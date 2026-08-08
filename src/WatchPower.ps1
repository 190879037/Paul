# ClearyDisplay - re-apply AC/Battery profile on power change
# Polling implementation using GetSystemPowerStatus (kernel32, no WMI).
# The old Register-WmiEvent approach depended on WMI event infrastructure, which is
# unreliable here (third-party WMI providers crash wmiprvse) and silently did nothing
# once registration failed. Polling is dependency-free and always works.
$ErrorActionPreference = 'SilentlyContinue'
$apply = Join-Path $env:LOCALAPPDATA 'ClearyDisplay\ApplyProfile.ps1'
$logFile = Join-Path $env:LOCALAPPDATA 'ClearyDisplay\watch.log'

if (-not ('ClearyWatchPower' -as [type])) {
  Add-Type @"
using System;
using System.Runtime.InteropServices;
public class ClearyWatchPower {
  [StructLayout(LayoutKind.Sequential)]
  public struct SYSTEM_POWER_STATUS {
    public byte ACLineStatus;
    public byte BatteryFlag;
    public byte BatteryLifePercent;
    public byte SystemStatusFlag;
    public int BatteryLifeTime;
    public int BatteryFullLifeTime;
  }
  [DllImport("kernel32.dll")]
  public static extern bool GetSystemPowerStatus(out SYSTEM_POWER_STATUS sps);
}
"@
}

function Write-Log([string]$msg) {
  Add-Content -Path $logFile -Value (('{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg)) -Encoding UTF8 -EA SilentlyContinue
}

# returns $true / $false, or $null when unknown (never trigger on unknown)
function Get-OnAc {
  try {
    $sps = New-Object ClearyWatchPower+SYSTEM_POWER_STATUS
    if ([ClearyWatchPower]::GetSystemPowerStatus([ref]$sps)) {
      if ($sps.ACLineStatus -eq 1) { return $true }
      if ($sps.ACLineStatus -eq 0) { return $false }
    }
  } catch {}
  return $null
}

function Invoke-Apply([string]$reason) {
  Write-Log ("Trigger: {0}" -f $reason)
  if (Test-Path $apply) {
    Start-Sleep -Seconds 2
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $apply -Force
  }
}

Write-Log 'Watcher started (polling mode)'
Invoke-Apply 'startup'

$last = Get-OnAc
$changedCount = 0
while ($true) {
  Start-Sleep -Seconds 5
  $now = Get-OnAc
  if ($null -eq $now) { continue }
  if ($null -eq $last) { $last = $now; continue }
  if ($now -ne $last) {
    # debounce: require the new state to persist for 2 consecutive polls (~10s)
    $changedCount++
    if ($changedCount -ge 2) {
      Invoke-Apply ('power -> ' + $(if ($now) { 'AC' } else { 'battery' }))
      $last = $now
      $changedCount = 0
    }
  } else {
    $changedCount = 0
  }
}
