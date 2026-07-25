# ClearyDisplay - apply AC/Battery profile + font to ALL attached displays (logon / power change)
param([switch]$Force)

$ErrorActionPreference = 'SilentlyContinue'
$logDir = Join-Path $env:LOCALAPPDATA 'ClearyDisplay'
$logFile = Join-Path $logDir 'apply.log'
$profilePath = Join-Path $logDir 'dim-profile.json'
$uiSettingsPath = Join-Path $logDir 'ui-settings.json'

function Write-Log([string]$msg) {
  $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
  Add-Content -Path $logFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
}

function Get-IsOnAc {
  # ACLineStatus: 0=Offline, 1=Online, 255=Unknown
  # Win32_Battery.BatteryStatus=2 是 Unknown，不是接电
  try {
    if (-not ('ClearyPower' -as [type])) {
      Add-Type @"
using System;
using System.Runtime.InteropServices;
public class ClearyPower {
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
    $sps = New-Object ClearyPower+SYSTEM_POWER_STATUS
    if ([ClearyPower]::GetSystemPowerStatus([ref]$sps)) {
      if ($sps.ACLineStatus -eq 1) { return $true }
      if ($sps.ACLineStatus -eq 0) { return $false }
    }
  } catch {}
  $bats = @(Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
  if ($bats.Count -eq 0) { return $true }
  foreach ($bat in $bats) {
    $s = [int]$bat.BatteryStatus
    if ($s -in 3, 6, 7, 8, 9) { return $true }
  }
  return $false
}

function Get-FontFromRecommend([string]$id) {
  switch ($id) {
    'apple'   { return @{ clearType = $true; gamma = 1.15; orientation = 1 } }
    'lg'      { return @{ clearType = $true; gamma = 1.68; orientation = 1 } }
    'huawei'  { return @{ clearType = $true; gamma = 1.55; orientation = 1 } }
    'asus'    { return @{ clearType = $true; gamma = 1.40; orientation = 1 } }
    'samsung' { return @{ clearType = $true; gamma = 1.50; orientation = 1 } }
    default   { return @{ clearType = $true; gamma = 1.40; orientation = 1 } }
  }
}

if (-not $Force) { Start-Sleep -Seconds 2 }

# 调节窗口打开时不要抢写硬件：否则插电瞬间亮度跳变，且易与 UI 线程 DDC 打架导致假死
try {
  if (Get-Process -Name 'ClearyDisplay' -ErrorAction SilentlyContinue) {
    Write-Log 'Skipped: ClearyDisplay UI is open (no hardware write on power change)'
    exit 0
  }
} catch {}

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
  [DllImport("user32.dll", SetLastError=true)] public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, ref uint pvParam, uint fWinIni);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, IntPtr pvParam, uint fWinIni);
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
  public const uint SPI_SETFONTSMOOTHING = 0x004B;
  public const uint SPI_SETFONTSMOOTHINGTYPE = 0x200B;
  public const uint SPI_SETFONTSMOOTHINGGAMMA = 0x200D;
  public const uint SPI_SETFONTSMOOTHINGORIENTATION = 0x2013;
  public const uint SPIF_UPDATEINIFILE = 0x01;
  public const uint SPIF_SENDCHANGE = 0x02;
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

# Restore ClearType / font gamma (registry usually persists; SPI refresh helps after logon)
$fontClear = $true
$fontGamma = 1.4
$fontOri = 1
try {
  if (Test-Path $uiSettingsPath) {
    $ui = Get-Content $uiSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($ui.fontApplied) {
      if ($null -ne $ui.fontApplied.clearType) { $fontClear = [bool]$ui.fontApplied.clearType }
      if ($null -ne $ui.fontApplied.gamma) { $fontGamma = [double]$ui.fontApplied.gamma }
      if ($null -ne $ui.fontApplied.orientation) { $fontOri = [int]$ui.fontApplied.orientation }
    } elseif ($ui.fontRecommend) {
      $ff = Get-FontFromRecommend ([string]$ui.fontRecommend)
      $fontClear = [bool]$ff.clearType
      $fontGamma = [double]$ff.gamma
      $fontOri = [int]$ff.orientation
    }
  }
} catch {}
try {
  $flags = [ClearyDisplayApply]::SPIF_UPDATEINIFILE -bor [ClearyDisplayApply]::SPIF_SENDCHANGE
  $smooth = if ($fontClear) { [uint32]1 } else { [uint32]0 }
  [void][ClearyDisplayApply]::SystemParametersInfo([ClearyDisplayApply]::SPI_SETFONTSMOOTHING, $smooth, [IntPtr]::Zero, $flags)
  if ($fontClear) {
    $type = [uint32]2
    [void][ClearyDisplayApply]::SystemParametersInfo([ClearyDisplayApply]::SPI_SETFONTSMOOTHINGTYPE, 0, [ref]$type, $flags)
  }
  $gWant = [int][Math]::Round($fontGamma * 1000)
  if ($gWant -lt 1000) { $gWant = 1000 }
  if ($gWant -gt 2200) { $gWant = 2200 }
  # Skip SPI_SETFONTSMOOTHINGGAMMA — P/Invoke corrupts live contrast on Win11 and breaks Java.
  $o = [uint32]$fontOri
  [void][ClearyDisplayApply]::SystemParametersInfo([ClearyDisplayApply]::SPI_SETFONTSMOOTHINGORIENTATION, 0, [ref]$o, $flags)
  Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name FontSmoothing -Value ($(if($fontClear){'2'}else{'0'}))
  Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name FontSmoothingType -Value ($(if($fontClear){2}else{1})) -Type DWord
  Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name FontSmoothingGamma -Value $gWant -Type DWord
  Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name FontSmoothingOrientation -Value $fontOri -Type DWord
} catch {
  Write-Log ('Font apply fail: ' + $_.Exception.Message)
}

Write-Log ("Applied ALL displays onAc={0} bright={1} contrast={2} readback={3} gamma={4} scale={5} gammaDevs={6} ddc={7} fontG={8}" -f $onAc, $brightness, $contrast, $cur, $gammaPower, $scale, $gammaOk, $ddcCount, $fontGamma)
exit 0
