# ClearyDisplay - apply AC/Battery profile to ALL attached displays
param([switch]$Force)

$ErrorActionPreference = 'SilentlyContinue'
$logDir = Join-Path $env:LOCALAPPDATA 'ClearyDisplay'
$logFile = Join-Path $logDir 'apply.log'
$profilePath = Join-Path $logDir 'dim-profile.json'

function Write-Log([string]$msg) {
  $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
  Add-Content -Path $logFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
}

function Get-IsOnAc {
  $b = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
  if (-not $b) { return $true }
  return ([int]$b.BatteryStatus -eq 2)
}

if (-not $Force) { Start-Sleep -Seconds 2 }

$onAc = Get-IsOnAc
$brightness = 90
$contrast = 50
$gammaPower = 1.0
$scale = 1.0
if (Test-Path $profilePath) {
  try {
    $j = Get-Content $profilePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $node = if ($onAc) { $j.ac } else { $j.battery }
    if (-not $node -and $j.brightness) { $node = $j }
    if ($node) {
      if ($null -ne $node.brightness) { $brightness = [int]$node.brightness }
      if ($null -ne $node.contrast) { $contrast = [int]$node.contrast }
      if ($null -ne $node.gammaPower) { $gammaPower = [double]$node.gammaPower }
      if ($null -ne $node.scale) { $scale = [double]$node.scale }
    }
  } catch {}
}

if (-not ([System.Management.Automation.PSTypeName]'ClearyDisplayApply').Type) {
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class ClearyDisplayApply {
  [DllImport("gdi32.dll")] public static extern IntPtr CreateDC(string a, string b, string c, IntPtr d);
  [DllImport("gdi32.dll")] public static extern bool SetDeviceGammaRamp(IntPtr hdc, ref RAMP lpRamp);
  [DllImport("gdi32.dll")] public static extern bool DeleteDC(IntPtr hdc);
  [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern bool EnumDisplayDevices(string lpDevice, uint iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, uint dwFlags);
  [DllImport("dxva2.dll", SetLastError=true)] public static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, ref uint n);
  [DllImport("dxva2.dll", SetLastError=true)] public static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, uint n, [Out] PHYSICAL_MONITOR[] arr);
  [DllImport("dxva2.dll", SetLastError=true)] public static extern bool SetMonitorBrightness(IntPtr h, uint v);
  [DllImport("dxva2.dll", SetLastError=true)] public static extern bool SetMonitorContrast(IntPtr h, uint v);
  [DllImport("dxva2.dll", SetLastError=true)] public static extern bool GetMonitorBrightness(IntPtr h, ref uint min, ref uint cur, ref uint max);
  [DllImport("dxva2.dll", SetLastError=true)] public static extern bool DestroyPhysicalMonitors(uint n, [In] PHYSICAL_MONITOR[] arr);
  [DllImport("user32.dll")] public static extern bool EnumDisplayMonitors(IntPtr a, IntPtr b, MonitorEnumProc c, IntPtr d);
  public delegate bool MonitorEnumProc(IntPtr h, IntPtr hdc, IntPtr r, IntPtr data);
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Auto)]
  public struct PHYSICAL_MONITOR {
    public IntPtr hPhysicalMonitor;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string szPhysicalMonitorDescription;
  }
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Ansi)]
  public struct RAMP {
    [MarshalAs(UnmanagedType.ByValArray, SizeConst=256)] public ushort[] Red;
    [MarshalAs(UnmanagedType.ByValArray, SizeConst=256)] public ushort[] Green;
    [MarshalAs(UnmanagedType.ByValArray, SizeConst=256)] public ushort[] Blue;
  }
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct DISPLAY_DEVICE {
    public int cb;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string DeviceName;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceString;
    public int StateFlags;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceID;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceKey;
  }
  public const int DISPLAY_DEVICE_ATTACHED_TO_DESKTOP = 0x1;
}
"@
}

$ramp = New-Object ClearyDisplayApply+RAMP
$ramp.Red = New-Object 'System.UInt16[]' 256
$ramp.Green = New-Object 'System.UInt16[]' 256
$ramp.Blue = New-Object 'System.UInt16[]' 256
for ($i = 0; $i -lt 256; $i++) {
  $base = $i / 255.0
  $y = [Math]::Pow($base, $gammaPower) * $scale
  if ($y -gt 1) { $y = 1 }
  if ($y -lt 0) { $y = 0 }
  $v = [uint16]([Math]::Round($y * 65535))
  $ramp.Red[$i] = $v; $ramp.Green[$i] = $v; $ramp.Blue[$i] = $v
}

$gammaOk = 0
for ($dev = 0; $dev -lt 16; $dev++) {
  $dd = New-Object ClearyDisplayApply+DISPLAY_DEVICE
  $dd.cb = [Runtime.InteropServices.Marshal]::SizeOf($dd)
  if (-not [ClearyDisplayApply]::EnumDisplayDevices($null, [uint32]$dev, [ref]$dd, 0)) { break }
  if (($dd.StateFlags -band [ClearyDisplayApply]::DISPLAY_DEVICE_ATTACHED_TO_DESKTOP) -eq 0) { continue }
  $hdc = [ClearyDisplayApply]::CreateDC('DISPLAY', $dd.DeviceName, $null, [IntPtr]::Zero)
  if ($hdc -eq [IntPtr]::Zero) { continue }
  try {
    if ([ClearyDisplayApply]::SetDeviceGammaRamp($hdc, [ref]$ramp)) { $gammaOk++ }
  } finally {
    [void][ClearyDisplayApply]::DeleteDC($hdc)
  }
}
if ($gammaOk -eq 0) {
  $hdc = [ClearyDisplayApply]::GetDC([IntPtr]::Zero)
  if ($hdc -ne [IntPtr]::Zero) {
    try { [void][ClearyDisplayApply]::SetDeviceGammaRamp($hdc, [ref]$ramp) }
    finally { [void][ClearyDisplayApply]::ReleaseDC([IntPtr]::Zero, $hdc) }
  }
}

$script:hMons = New-Object System.Collections.ArrayList
$cb = [ClearyDisplayApply+MonitorEnumProc]{ param($h,$hdc,$r,$d) [void]$script:hMons.Add($h); $true }
[void][ClearyDisplayApply]::EnumDisplayMonitors([IntPtr]::Zero,[IntPtr]::Zero,$cb,[IntPtr]::Zero)

$cur = -1
$ddcCount = 0
foreach ($hMon in @($script:hMons)) {
  $n = [uint32]0
  if (-not [ClearyDisplayApply]::GetNumberOfPhysicalMonitorsFromHMONITOR($hMon,[ref]$n) -or $n -eq 0) { continue }
  $arr = New-Object ClearyDisplayApply+PHYSICAL_MONITOR[] $n
  if (-not [ClearyDisplayApply]::GetPhysicalMonitorsFromHMONITOR($hMon,$n,$arr)) { continue }
  try {
    for ($i = 0; $i -lt $n; $i++) {
      $ph = $arr[$i].hPhysicalMonitor
      [void][ClearyDisplayApply]::SetMonitorBrightness($ph, [uint32]$brightness)
      [void][ClearyDisplayApply]::SetMonitorContrast($ph, [uint32]$contrast)
      $min=0;$c=0;$max=0
      if ([ClearyDisplayApply]::GetMonitorBrightness($ph,[ref]$min,[ref]$c,[ref]$max)) { $cur = [int]$c }
      $ddcCount++
    }
  } finally {
    [void][ClearyDisplayApply]::DestroyPhysicalMonitors($n,$arr)
  }
}

try {
  powercfg /SETACVALUEINDEX SCHEME_CURRENT SUB_VIDEO VIDEONORMALLEVEL $brightness | Out-Null
  powercfg /SETDCVALUEINDEX SCHEME_CURRENT SUB_VIDEO VIDEONORMALLEVEL $brightness | Out-Null
  powercfg /SETACTIVE SCHEME_CURRENT | Out-Null
} catch {}

Write-Log ("Applied ALL displays onAc={0} bright={1} contrast={2} readback={3} gamma={4} scale={5} gammaDevs={6} ddc={7}" -f $onAc, $brightness, $contrast, $cur, $gammaPower, $scale, $gammaOk, $ddcCount)
exit 0
