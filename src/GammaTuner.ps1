# ClearyDisplay 云母白中文调节器 - 显示 + 字体 + 预设
#Requires -Version 5.1
try {
  Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml, System.Windows.Forms
} catch {
  Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
  [System.Windows.Forms.MessageBox]::Show(
    "Failed to load WPF libraries.`nThis app needs a full Windows desktop (Win10/11) with .NET Framework.`n`n" + $_.Exception.Message,
    'ClearyDisplay')
  exit 1
}

$ErrorActionPreference = 'Continue'

# Install / EXE directory (ps2exe has no reliable $PSScriptRoot)
$script:appDir = $null
try {
  $mod = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
  if ($mod -and (Test-Path $mod)) { $script:appDir = Split-Path $mod -Parent }
} catch {}
if (-not $script:appDir -and $PSScriptRoot) { $script:appDir = $PSScriptRoot }
if (-not $script:appDir) { $script:appDir = Join-Path $env:LOCALAPPDATA 'ClearyDisplay' }

# User config always under LocalAppData (stable across reinstall / move)
$baseDir = Join-Path $env:LOCALAPPDATA 'ClearyDisplay'
try { New-Item -ItemType Directory -Force -Path $baseDir | Out-Null } catch {}
$profilePath = Join-Path $baseDir 'dim-profile.json'
$presetsPath = Join-Path $baseDir 'presets.json'
$uiSettingsPath = Join-Path $baseDir 'ui-settings.json'

if (-not ([System.Management.Automation.PSTypeName]'ClearyNative').Type) {
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class ClearyNative {
  [DllImport("gdi32.dll")] public static extern IntPtr CreateDC(string a, string b, string c, IntPtr d);
  [DllImport("gdi32.dll")] public static extern bool SetDeviceGammaRamp(IntPtr hdc, ref RAMP lpRamp);
  [DllImport("gdi32.dll")] public static extern bool DeleteDC(IntPtr hdc);
  [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
  [DllImport("user32.dll")] public static extern bool EnumDisplayMonitors(IntPtr a, IntPtr b, MonitorEnumProc c, IntPtr d);
  [DllImport("user32.dll")] public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, IntPtr pvParam, uint fWinIni);
  [DllImport("user32.dll")] public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, ref uint pvParam, uint fWinIni);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool AllowSetForegroundWindow(int dwProcessId);
  [DllImport("dxva2.dll", SetLastError=true)] public static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, ref uint n);
  [DllImport("dxva2.dll", SetLastError=true)] public static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, uint n, [Out] PHYSICAL_MONITOR[] arr);
  [DllImport("dxva2.dll", SetLastError=true)] public static extern bool SetMonitorBrightness(IntPtr h, uint v);
  [DllImport("dxva2.dll", SetLastError=true)] public static extern bool GetMonitorBrightness(IntPtr h, ref uint min, ref uint cur, ref uint max);
  [DllImport("dxva2.dll", SetLastError=true)] public static extern bool SetMonitorContrast(IntPtr h, uint v);
  [DllImport("dxva2.dll", SetLastError=true)] public static extern bool GetMonitorContrast(IntPtr h, ref uint min, ref uint cur, ref uint max);
  [DllImport("dxva2.dll", SetLastError=true)] public static extern bool DestroyPhysicalMonitors(uint n, [In] PHYSICAL_MONITOR[] arr);
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
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern bool EnumDisplayDevices(string lpDevice, uint iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, uint dwFlags);
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
  public const int DISPLAY_DEVICE_PRIMARY_DEVICE = 0x4;
  public const uint SPI_SETFONTSMOOTHING = 0x004B;
  public const uint SPI_GETFONTSMOOTHING = 0x004A;
  public const uint SPI_SETFONTSMOOTHINGTYPE = 0x200B;
  public const uint SPI_GETFONTSMOOTHINGGAMMA = 0x200C;
  public const uint SPI_SETFONTSMOOTHINGGAMMA = 0x200D;
  public const uint SPI_GETFONTSMOOTHINGORIENTATION = 0x2012;
  public const uint SPI_SETFONTSMOOTHINGORIENTATION = 0x2013;
  public const uint FE_FONTSMOOTHINGCLEARTYPE = 2;
  public const uint SPIF_UPDATEINIFILE = 0x01;
  public const uint SPIF_SENDCHANGE = 0x02;
  [DllImport("user32.dll", SetLastError=true)]
  public static extern bool SetProcessDpiAwarenessContext(IntPtr dpiContext);
  // DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2
  public static readonly IntPtr DpiPerMonitorV2 = new IntPtr(-4);
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

# 尽早开启 Per-Monitor DPI，避免高分屏上 WPF 界面字体发糊
try { [void][ClearyNative]::SetProcessDpiAwarenessContext([ClearyNative]::DpiPerMonitorV2) } catch {}

function Get-IsOnAc {
  # ACLineStatus: 0=Offline(电池), 1=Online(接电), 255=Unknown
  # 注意：Win32_Battery.BatteryStatus=2 是 Unknown，不是接电——旧逻辑会把接电误判成电池
  try {
    $sps = New-Object ClearyNative+SYSTEM_POWER_STATUS
    if ([ClearyNative]::GetSystemPowerStatus([ref]$sps)) {
      if ($sps.ACLineStatus -eq 1) { return $true }
      if ($sps.ACLineStatus -eq 0) { return $false }
    }
  } catch {}
  try {
    $pls = [System.Windows.Forms.SystemInformation]::PowerStatus.PowerLineStatus
    if ($pls -eq [System.Windows.Forms.PowerLineStatus]::Online) { return $true }
    if ($pls -eq [System.Windows.Forms.PowerLineStatus]::Offline) { return $false }
  } catch {}
  $bats = @(Get-CimInstance Win32_Battery -EA SilentlyContinue)
  if ($bats.Count -eq 0) { return $true }
  foreach ($bat in $bats) {
    $s = [int]$bat.BatteryStatus
    # 3=Fully Charged, 6–9=Charging* → 通常表示已接电
    if ($s -in 3, 6, 7, 8, 9) { return $true }
  }
  return $false
}

function Get-AllHMonitors {
  $script:hMonList = New-Object System.Collections.ArrayList
  $cb = [ClearyNative+MonitorEnumProc]{
    param($h,$hdc,$r,$d)
    [void]$script:hMonList.Add($h)
    $true
  }
  [void][ClearyNative]::EnumDisplayMonitors([IntPtr]::Zero,[IntPtr]::Zero,$cb,[IntPtr]::Zero)
  return @($script:hMonList)
}

function Get-PhysicalMonitor {
  $mons = Get-AllHMonitors
  if (-not $mons -or $mons.Count -eq 0) { return $null }
  $hMon = $mons[0]
  $n=[uint32]0
  if (-not [ClearyNative]::GetNumberOfPhysicalMonitorsFromHMONITOR($hMon,[ref]$n) -or $n -eq 0) { return $null }
  $arr = New-Object ClearyNative+PHYSICAL_MONITOR[] $n
  if (-not [ClearyNative]::GetPhysicalMonitorsFromHMONITOR($hMon,$n,$arr)) { return $null }
  return @{ Arr=$arr; N=$n; Handle=$arr[0].hPhysicalMonitor }
}

function Apply-Brightness([int]$v) {
  $last = -1
  try {
    foreach ($hMon in (Get-AllHMonitors)) {
      $n=[uint32]0
      if (-not [ClearyNative]::GetNumberOfPhysicalMonitorsFromHMONITOR($hMon,[ref]$n) -or $n -eq 0) { continue }
      $arr = New-Object ClearyNative+PHYSICAL_MONITOR[] $n
      if (-not [ClearyNative]::GetPhysicalMonitorsFromHMONITOR($hMon,$n,$arr)) { continue }
      try {
        for ($i=0; $i -lt $n; $i++) {
          $ph = $arr[$i].hPhysicalMonitor
          if ($ph -eq [IntPtr]::Zero) { continue }
          [void][ClearyNative]::SetMonitorBrightness($ph,[uint32]$v)
          $min=0;$cur=0;$max=0
          if ([ClearyNative]::GetMonitorBrightness($ph,[ref]$min,[ref]$cur,[ref]$max)) {
            $last = [int]$cur
          }
        }
      } finally {
        try { [void][ClearyNative]::DestroyPhysicalMonitors($n,$arr) } catch {}
      }
    }
  } catch {}
  return $last
}

function Apply-Contrast([int]$v) {
  $last = -1
  try {
    foreach ($hMon in (Get-AllHMonitors)) {
      $n=[uint32]0
      if (-not [ClearyNative]::GetNumberOfPhysicalMonitorsFromHMONITOR($hMon,[ref]$n) -or $n -eq 0) { continue }
      $arr = New-Object ClearyNative+PHYSICAL_MONITOR[] $n
      if (-not [ClearyNative]::GetPhysicalMonitorsFromHMONITOR($hMon,$n,$arr)) { continue }
      try {
        for ($i=0; $i -lt $n; $i++) {
          $ph = $arr[$i].hPhysicalMonitor
          if ($ph -eq [IntPtr]::Zero) { continue }
          [void][ClearyNative]::SetMonitorContrast($ph,[uint32]$v)
          $min=0;$cur=0;$max=0
          if ([ClearyNative]::GetMonitorContrast($ph,[ref]$min,[ref]$cur,[ref]$max)) {
            $last = [int]$cur
          }
        }
      } finally {
        try { [void][ClearyNative]::DestroyPhysicalMonitors($n,$arr) } catch {}
      }
    }
  } catch {}
  return $last
}

function Apply-Gamma([double]$power,[double]$scale) {
  try {
    if ($power -lt 0.3) { $power = 0.3 }
    if ($power -gt 3.0) { $power = 3.0 }
    if ($scale -lt 0.3) { $scale = 0.3 }
    if ($scale -gt 1.5) { $scale = 1.5 }
    $ramp = New-Object ClearyNative+RAMP
    $ramp.Red = New-Object 'System.UInt16[]' 256
    $ramp.Green = New-Object 'System.UInt16[]' 256
    $ramp.Blue = New-Object 'System.UInt16[]' 256
    for ($i=0;$i -lt 256;$i++) {
      $y = [Math]::Pow(($i/255.0), $power) * $scale
      if ($y -gt 1) { $y = 1 }
      if ($y -lt 0) { $y = 0 }
      $vv = [uint16]([Math]::Round($y * 65535))
      $ramp.Red[$i]=$vv; $ramp.Green[$i]=$vv; $ramp.Blue[$i]=$vv
    }
    $applied = $false
    for ($dev = 0; $dev -lt 16; $dev++) {
      $dd = New-Object ClearyNative+DISPLAY_DEVICE
      $dd.cb = [Runtime.InteropServices.Marshal]::SizeOf($dd)
      if (-not [ClearyNative]::EnumDisplayDevices($null, [uint32]$dev, [ref]$dd, 0)) { break }
      if (($dd.StateFlags -band [ClearyNative]::DISPLAY_DEVICE_ATTACHED_TO_DESKTOP) -eq 0) { continue }
      $hdc = [ClearyNative]::CreateDC('DISPLAY', $dd.DeviceName, $null, [IntPtr]::Zero)
      if ($hdc -eq [IntPtr]::Zero) { continue }
      try {
        if ([ClearyNative]::SetDeviceGammaRamp($hdc, [ref]$ramp)) { $applied = $true }
      } finally {
        [void][ClearyNative]::DeleteDC($hdc)
      }
    }
    if (-not $applied) {
      $hdc = [ClearyNative]::GetDC([IntPtr]::Zero)
      if ($hdc -ne [IntPtr]::Zero) {
        try { [void][ClearyNative]::SetDeviceGammaRamp($hdc,[ref]$ramp) }
        finally { [void][ClearyNative]::ReleaseDC([IntPtr]::Zero, $hdc) }
      }
    }
  } catch {}
}

function New-DefaultProfiles {
  $s=@{brightness=90;contrast=50;gammaPower=1.0;scale=1.0}
  return @{ ac=$s.Clone(); battery=$s.Clone() }
}

function Load-ActiveProfiles {
  $d = @{
    ac=@{brightness=90;contrast=50;gammaPower=1.0;scale=1.0}
    battery=@{brightness=90;contrast=50;gammaPower=1.0;scale=1.0}
  }
  if (-not (Test-Path $profilePath)) { return $d }
  try {
    $j = Get-Content $profilePath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($k in @('ac','battery')) {
      $n=$j.$k; if (-not $n) { continue }
      if ($null -ne $n.brightness) { $d.$k.brightness=[int]$n.brightness }
      if ($null -ne $n.contrast) { $d.$k.contrast=[int]$n.contrast }
      if ($null -ne $n.gammaPower) { $d.$k.gammaPower=[double]$n.gammaPower }
      if ($null -ne $n.scale) { $d.$k.scale=[double]$n.scale }
    }
  } catch {}
  return $d
}

function Save-ActiveProfiles($p) {
  $obj=[ordered]@{
    ac=[ordered]@{brightness=[int]$p.ac.brightness;contrast=[int]$p.ac.contrast;gammaPower=[math]::Round([double]$p.ac.gammaPower,2);scale=[math]::Round([double]$p.ac.scale,2)}
    battery=[ordered]@{brightness=[int]$p.battery.brightness;contrast=[int]$p.battery.contrast;gammaPower=[math]::Round([double]$p.battery.gammaPower,2);scale=[math]::Round([double]$p.battery.scale,2)}
  }
  ($obj|ConvertTo-Json -Depth 5)|Set-Content $profilePath -Encoding UTF8
}

function Load-Presets {
  $map=[ordered]@{}
  if (-not (Test-Path $presetsPath)) { return $map }
  try {
    $j=Get-Content $presetsPath -Raw -Encoding UTF8|ConvertFrom-Json
    foreach($prop in $j.PSObject.Properties){ $map[$prop.Name]=$prop.Value }
  } catch {}
  return $map
}

function Save-Presets($map) {
  $obj=[ordered]@{}
  foreach($k in $map.Keys){ $obj[$k]=$map[$k] }
  ($obj|ConvertTo-Json -Depth 6)|Set-Content $presetsPath -Encoding UTF8
}

function Get-FontGamma {
  try {
    $v = (Get-ItemProperty 'HKCU:\Control Panel\Desktop').FontSmoothingGamma
    return [math]::Round(([int]$v)/1000.0, 2)
  } catch { return 1.4 }
}

function Set-FontSmoothingSettings([bool]$enableClearType, [double]$gamma, [int]$orientation) {
  $flags = [ClearyNative]::SPIF_UPDATEINIFILE -bor [ClearyNative]::SPIF_SENDCHANGE
  $smooth = if ($enableClearType) { 1 } else { 0 }
  [void][ClearyNative]::SystemParametersInfo([ClearyNative]::SPI_SETFONTSMOOTHING, [uint32]$smooth, [IntPtr]::Zero, $flags)
  if ($enableClearType) {
    $type = [ClearyNative]::FE_FONTSMOOTHINGCLEARTYPE
    [void][ClearyNative]::SystemParametersInfo([ClearyNative]::SPI_SETFONTSMOOTHINGTYPE, 0, [ref]$type, $flags)
  }
  $g = [uint32]([Math]::Round($gamma * 1000))
  if ($g -lt 1000) { $g = 1000 }
  if ($g -gt 2200) { $g = 2200 }
  $gammaWant = [int]$g
  # IMPORTANT: Do NOT call SPI_SETFONTSMOOTHINGGAMMA/CONTRAST via P/Invoke on Win11.
  # On this host it leaves a corrupt live contrast value (billions) that crashes every
  # Java Swing app: "IllegalArgumentException: … incompatible with Text-specific LCD contrast key".
  # Registry persistence + SPI font-smoothing toggle is enough for ClearType after relaunch/reboot.
  $o = [uint32]$orientation
  [void][ClearyNative]::SystemParametersInfo([ClearyNative]::SPI_SETFONTSMOOTHINGORIENTATION, 0, [ref]$o, $flags)
  Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name FontSmoothing -Value ($(if($enableClearType){'2'}else{'0'}))
  Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name FontSmoothingType -Value ($(if($enableClearType){2}else{1})) -Type DWord
  Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name FontSmoothingGamma -Value $gammaWant -Type DWord
  Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name FontSmoothingOrientation -Value $orientation -Type DWord
  if (-not $script:uiSettings) { $script:uiSettings = @{} }
  $script:uiSettings.fontApplied = @{
    clearType   = [bool]$enableClearType
    gamma       = [math]::Round([double]$gamma, 2)
    orientation = [int]$orientation
  }
  try { Save-UiSettings $script:uiSettings } catch {}
}

function Get-SystemIsLight {
  try {
    $v = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -EA Stop).AppsUseLightTheme
    return ([int]$v -ne 0)
  } catch { return $true }
}

function Load-UiSettings {
  $d = @{ theme = 'light'; recommend = 'generic'; fontRecommend = 'generic'; lang = 'zh'; autoStart = $true }
  if (-not (Test-Path $uiSettingsPath)) { return $d }
  try {
    $j = Get-Content $uiSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($j.theme -in @('light','dark','github','apple','dsa','chrome','system')) { $d.theme = [string]$j.theme }
    if ($j.recommend -in @('apple','lg','huawei','asus','samsung','generic')) { $d.recommend = [string]$j.recommend }
    if ($j.fontRecommend -in @('apple','lg','huawei','asus','samsung','generic')) { $d.fontRecommend = [string]$j.fontRecommend }
    if ($j.lang -in @('zh','en')) { $d.lang = [string]$j.lang }
    if ($null -ne $j.autoStart) { $d.autoStart = [bool]$j.autoStart }
    if ($j.fontApplied) {
      $d.fontApplied = @{
        clearType   = [bool]$j.fontApplied.clearType
        gamma       = [double]$j.fontApplied.gamma
        orientation = [int]$j.fontApplied.orientation
      }
    }
  } catch {}
  return $d
}

function Save-UiSettings($s) {
  $rec = if ($s.recommend) { $s.recommend } else { 'generic' }
  $fontRec = if ($s.fontRecommend) { $s.fontRecommend } else { 'generic' }
  $lang = if ($s.lang -in @('zh','en')) { $s.lang } else { 'zh' }
  $theme = if ($s.theme) { $s.theme } else { 'light' }
  $auto = if ($null -ne $s.autoStart) { [bool]$s.autoStart } else { $true }
  $obj = [ordered]@{
    theme = $theme
    recommend = $rec
    fontRecommend = $fontRec
    lang = $lang
    autoStart = $auto
  }
  if ($s.fontApplied) {
    $obj.fontApplied = @{
      clearType   = [bool]$s.fontApplied.clearType
      gamma       = [math]::Round([double]$s.fontApplied.gamma, 2)
      orientation = [int]$s.fontApplied.orientation
    }
  }
  ($obj | ConvertTo-Json -Depth 5) | Set-Content $uiSettingsPath -Encoding UTF8
}

function Get-StartupApplyEnabled {
  try {
    $v = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'ClearyDisplayApply' -EA Stop).ClearyDisplayApply
    return [bool]$v
  } catch { return $false }
}

function Set-StartupApply([bool]$enable) {
  # 不需要管理员：写当前用户 Run 即可。伽马/亮度重启后必须再写一次。
  $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
  $cmd = Join-Path $baseDir 'ApplyProfile.cmd'
  $ps1 = Join-Path $baseDir 'ApplyProfile.ps1'
  $srcPs1Candidates = @(
    (Join-Path $script:appDir 'ApplyProfile.ps1'),
    (Join-Path $baseDir 'ApplyProfile.ps1'),
    'H:\SOFTWARE\WIN11\ClearyDisplay\src\ApplyProfile.ps1'
  )
  $srcCmdCandidates = @(
    (Join-Path $script:appDir 'ApplyProfile.cmd'),
    (Join-Path $baseDir 'ApplyProfile.cmd'),
    'H:\SOFTWARE\WIN11\ClearyDisplay\src\ApplyProfile.cmd'
  )
  foreach ($c in $srcPs1Candidates) {
    if ($c -and (Test-Path $c) -and ($c -ne $ps1)) { try { Copy-Item -Force $c $ps1; break } catch {} }
  }
  foreach ($c in $srcCmdCandidates) {
    if ($c -and (Test-Path $c) -and ($c -ne $cmd)) { try { Copy-Item -Force $c $cmd; break } catch {} }
  }
  if (-not (Test-Path $cmd)) {
    "@echo off`r`nset `"APPDIR=%~dp0`"`r`npowershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"%APPDIR%ApplyProfile.ps1`" -Force`r`n" | Set-Content $cmd -Encoding ASCII
  }
  if ($enable) {
    Set-ItemProperty -Path $runKey -Name 'ClearyDisplayApply' -Value ('"' + $cmd + '"') -Type String
  } else {
    Remove-ItemProperty -Path $runKey -Name 'ClearyDisplayApply' -EA SilentlyContinue
  }
}

# --- i18n ---
$script:I18n = @{
  zh = [ordered]@{
    appTitle = '屏幕与字体调节'
    langTip = '切换到 English'
    statusAc = '当前：已接电源（AC）'
    statusBat = '当前：电池供电'
    tabDisplay = '显示'
    tabFont = '字体'
    tabTheme = '主题'
    powerTitle = '电源配置档'
    powerDesc = '分别为「接电」和「电池」保存独立参数。供电变化时单选与滑条会自动切换；不会自动改屏幕亮度，需点「立即应用」。'
    powerSwitchedAc = '已切换到接电档参数（屏幕未改，点「立即应用」写入）'
    powerSwitchedBat = '已切换到电池档参数（屏幕未改，点「立即应用」写入）'
    rbAc = '接电状态'
    rbBat = '电池状态'
    recTitleFmt = '推荐档 · {0}'
    recAcFmt = '接电：亮 {0} / 对比 {1} / γ {2:N2} / 缩放 {3:N2}'
    recBatFmt = '电池：亮 {0} / 对比 {1} / γ {2:N2} / 缩放 {3:N2}'
    recFontFmt = '字体：ClearType {0} · 平滑伽马 {1:N2} · {2}'
    recFontOn = '开'
    recFontOff = '关'
    recNote = '显示与字体风格相互独立：顶部胶囊只改屏幕；字体页胶囊只改 ClearType。均为软件近似，非官方 ICC。'
    fontRecTitle = '当前字体档（用顶部胶囊切换）'
    fontRecDesc = '顶部品牌胶囊在「字体」页只改 ClearType；在「显示」页只改屏幕。两套选择互不影响。'
    fontRecTitleFmt = '字体档 · {0}'
    presetTitle = '命名方案'
    presetDesc = '把当前「接电 + 电池」两套参数另存为方案，方便随时切换（例如：配置1、配置2）。'
    presetExisting = '已有方案'
    presetName = '方案名称'
    presetNameDefault = '配置1'
    btnSavePreset = '另存方案'
    btnLoadPreset = '载入方案'
    btnDelPreset = '删除方案'
    bright = '亮度'
    contrast = '对比度'
    gamma = '伽马幂次'
    gammaHint = '大于 1 更暗，小于 1 更亮'
    scale = '整体缩放'
    scaleHint = '整体明暗倍率，可细调'
    readbackDash = '硬件回读：—'
    readbackFmt = '硬件回读：亮度 {0} · 对比度 {1}'
    clearTypeTitle = 'ClearType 字体平滑'
    clearTypeDesc = '这是 Windows 系统级字体渲染。调整后部分程序需重新打开才完全生效。'
    enableClearType = '启用 ClearType'
    fontGamma = '字体平滑伽马'
    fontGammaHint = '通常 1.0～2.2。越高边缘越硬。变化偏细，请用记事本/资源管理器对比；Chrome 里往往不明显。'
    subpixel = '子像素排列'
    rgbCommon = 'RGB（常见）'
    btnApplyFont = '应用字体设置'
    btnClearTypeWizard = '打开系统 ClearType 向导'
    previewTitle = '预览'
    previewDesc = '下面文字用于观察边缘是否舒服（宋体/雅黑混排）。'
    previewSample = '屏幕与字体调节 ClearyDisplay'
    previewZh = '中文预览：清屏、亮度、对比度、伽马。字体渲染是否清晰细腻，一眼可辨。'
    themeTitle = '外观主题'
    themeHintPick = '选择界面风格。GITHUB / 苹果 / DSA / Chrome 为独立配色；「跟随系统」仅在浅/深之间切换。'
    themeHintLight = '当前界面：浅色（清爽）'
    themeHintDark = '当前界面：深色'
    themeHintGithub = '当前界面：GITHUB 风格'
    themeHintApple = '当前界面：苹果风格'
    themeHintDsa = '当前界面：DSA 风格'
    themeHintChrome = '当前界面：Chrome 风格'
    themeHintSystemFmt = '当前界面：跟随系统（当前 Windows 为{0}）'
    themeLightShort = '浅'
    themeLight = '浅色'
    themeLightDesc = '高对比清爽白底，接近 Claude 式信息层次'
    themeDarkShort = '深'
    themeDark = '深色'
    themeDarkDesc = '深色界面，夜间更护眼'
    themeGithubShort = 'GH'
    themeGithub = 'GITHUB'
    themeGithubDesc = 'GitHub 风：灰白底 + 链接蓝 #0969DA + 成功绿滑条/描边；胶囊偏方、细边框'
    themeAppleUiShort = '苹'
    themeAppleUi = '苹果风格'
    themeAppleUiDesc = 'Apple 风：#F5F5F7 冷灰底 + 系统蓝；胶囊大圆角并带描边'
    themeDsaShort = 'DSA'
    themeDsa = 'DSA'
    themeDsaDesc = 'DSA 风：柔和浅蓝底、粉彩蓝字、薄荷绿滑条/选中描边（每日选股分析同款）'
    themeChromeShort = 'C'
    themeChrome = 'Chrome'
    themeChromeDesc = 'Chrome 风：浅蓝底 + 白/蓝/红（#1A73E8 + #EA4335）'
    themeSysShort = '自'
    themeSystem = '跟随系统'
    themeSystemDesc = '自动跟随 Windows「深色 / 浅色」模式'
    lightWord = '浅色'
    darkWord = '深色'
    btnReset = '重置本档'
    btnApply = '立即应用'
    btnSaveClose = '保存并关闭'
    footerHint = '左右并排调节 · 拖动滑块实时预览 ·「立即应用」写入配置'
    autoStartTitle = '开机自动应用'
    autoStartDesc = '登录 Windows 时自动写回亮度/对比度/软件伽马（系统会重置软件伽马，不是权限问题）。'
    autoStartOn = '已开启开机自动应用'
    autoStartOff = '已关闭开机自动应用'
    colorCalibTitle = '颜色校准'
    colorCalibName = '显示颜色校准'
    colorCalibDesc = '校准显示颜色、亮度和对比度'
    btnColorCalib = '校准显示器'
    tip = '提示'
    apple = '苹果'
    huawei = '华为'
    asus = '华硕'
    samsung = '三星'
    generic = '通用显示'
    tipApple = '显示·苹果：干净中性白、偏软中间调（仅屏幕，不影响字体）'
    tipLg = '显示·LG：略冷、对比更利（仅屏幕）'
    tipHuawei = '显示·华为：更亮润白、中间调抬升（仅屏幕）'
    tipAsus = '显示·华硕 ProArt：参考亮度、标准伽马（仅屏幕）'
    tipSamsung = '显示·三星：AMOLED 偏通透、对比略冲（仅屏幕）'
    tipGeneric = '显示·通用：默认平衡档（仅屏幕）'
    tipFontApple = '字体·苹果：柔和 ClearType（γ≈1.15）'
    tipFontLg = '字体·LG：利落 ClearType（γ≈1.68）'
    tipFontHuawei = '字体·华为：略锐 ClearType（γ≈1.55）'
    tipFontAsus = '字体·华硕：标准 ClearType（γ=1.40）'
    tipFontSamsung = '字体·三星：偏锐 ClearType（γ≈1.50）'
    tipFontGeneric = '字体·通用：Windows 默认 ClearType（γ=1.40）'
    recAppleTarget = 'Studio Display：干净中性白、中间调略软'
    recLgTarget = 'UltraFine / Nano IPS：略冷、对比更利'
    recHuaweiTarget = 'Mate 旗舰屏：更亮润白、中间调抬升'
    recAsusTarget = 'ProArt 准色：参考亮度、标准伽马'
    recSamsungTarget = 'Galaxy / Odyssey：通透亮、对比略冲'
    recGenericTarget = '默认平衡档'
    fontAppleTarget = '柔和字缘，接近 macOS 观感'
    fontLgTarget = '更利落字缘，适合 IPS 锐利感'
    fontHuaweiTarget = '中文略锐，适合 Mate 系观感'
    fontAsusTarget = 'Windows 标准 ClearType'
    fontSamsungTarget = '偏锐字缘，接近 One UI 观感'
    fontGenericTarget = 'Windows 默认字体平滑'
    recAppleHint = '已套用苹果显示档（字体未改，请在字体页单独选择）'
    recLgHint = '已套用 LG 显示档（字体未改）'
    recHuaweiHint = '已套用华为显示档（字体未改）'
    recAsusHint = '已套用华硕显示档（字体未改）'
    recSamsungHint = '已套用三星显示档（字体未改）'
    recGenericHint = '已套用通用显示档（字体未改）'
    fontAppleHint = '已套用苹果字体档：柔和 ClearType（γ≈1.15）'
    fontLgHint = '已套用 LG 字体档：利落 ClearType（γ≈1.68）'
    fontHuaweiHint = '已套用华为字体档：略锐 ClearType（γ≈1.55）'
    fontAsusHint = '已套用华硕字体档：标准 ClearType（γ=1.40）'
    fontSamsungHint = '已套用三星字体档：偏锐 ClearType（γ≈1.50）'
    fontGenericHint = '已套用通用字体档：标准 ClearType（γ=1.40）'
    recPreviewFmt = '推荐档「{0}」已预览。可再微调，或点「立即应用」写入显示器。'
    previewPaused = '预览已暂停：正在编辑另一电源档（屏幕不变）'
    livePreviewFmt = '实时预览 · 亮度回读 {0} · 对比度回读 {1}'
    previewFail = '预览部分失败，可再点「立即应用」'
    fontApplied = '字体设置已应用。部分程序需重启后完全生效。'
    needPresetName = '请输入方案名称，例如：配置1'
    savedPresetFmt = '已另存方案：{0}'
    pickPreset = '请先在下拉框中选择已有方案'
    loadedPresetFmt = '已载入方案：{0}'
    pickDelPreset = '请先选择要删除的方案'
    deletedPresetFmt = '已删除方案：{0}'
    appliedFmt = '已应用并保存（{0}）：亮度 {1} · 对比度 {2} · 伽马 {3:N2} · 缩放 {4:N2}'
    appliedGammaOnly = '已应用伽马/缩放并保存（{0}）。亮度/对比度硬件回读失败，请再试一次'
    modeAc = '接电'
    modeBat = '电池'
    readyApply = '界面已就绪。亮度/对比度请点「立即应用」写入显示器。'
    readyNoPreview = '界面已就绪（预览未应用）。'
    initFail = '界面初始化失败：'
    startFail = '窗口启动失败：'
    bindWarn = '控件未绑定：'
    bindWarn2 = "`n界面可能不完整，但仍会尝试打开。"
  }
  en = [ordered]@{
    appTitle = 'Display and Font'
    langTip = 'Switch to 中文'
    statusAc = 'Power: AC plugged in'
    statusBat = 'Power: On battery'
    tabDisplay = 'Display'
    tabFont = 'Font'
    tabTheme = 'Theme'
    powerTitle = 'Power profiles'
    powerDesc = 'Separate AC/battery settings. Radios and sliders follow power changes; screen brightness is not auto-written — click Apply.'
    powerSwitchedAc = 'Switched to AC profile (screen unchanged — click Apply)'
    powerSwitchedBat = 'Switched to battery profile (screen unchanged — click Apply)'
    rbAc = 'On AC'
    rbBat = 'On battery'
    recTitleFmt = 'Preset · {0}'
    recAcFmt = 'AC: Bright {0} / Contrast {1} / γ {2:N2} / Scale {3:N2}'
    recBatFmt = 'Battery: Bright {0} / Contrast {1} / γ {2:N2} / Scale {3:N2}'
    recFontFmt = 'Font: ClearType {0} · gamma {1:N2} · {2}'
    recFontOn = 'On'
    recFontOff = 'Off'
    recNote = 'Display and font styles are independent: top chips change the screen only; Font-tab chips change ClearType only. Software approximation, not ICC.'
    fontRecTitle = 'Current font preset (use top chips)'
    fontRecDesc = 'Top brand chips change ClearType on the Font tab, and the screen on the Display tab. The two selections stay independent.'
    fontRecTitleFmt = 'Font preset · {0}'
    presetTitle = 'Named profiles'
    presetDesc = 'Save the current AC + battery pair as a named profile for quick switching.'
    presetExisting = 'Saved profiles'
    presetName = 'Profile name'
    presetNameDefault = 'Profile 1'
    btnSavePreset = 'Save as'
    btnLoadPreset = 'Load'
    btnDelPreset = 'Delete'
    bright = 'Brightness'
    contrast = 'Contrast'
    gamma = 'Gamma power'
    gammaHint = 'gt 1 darker, lt 1 brighter'
    scale = 'Overall scale'
    scaleHint = 'Global luminance multiplier'
    readbackDash = 'Hardware readback: —'
    readbackFmt = 'Hardware: Brightness {0} · Contrast {1}'
    clearTypeTitle = 'ClearType smoothing'
    clearTypeDesc = 'Windows system font rendering. Some apps need a restart to fully update.'
    enableClearType = 'Enable ClearType'
    fontGamma = 'Font smoothing gamma'
    fontGammaHint = 'Typically 1.0–2.2. Higher = harder edges. Changes are subtle—compare in Notepad/Explorer; Chrome often shows little difference.'
    subpixel = 'Subpixel layout'
    rgbCommon = 'RGB (common)'
    btnApplyFont = 'Apply font settings'
    btnClearTypeWizard = 'Open ClearType wizard'
    previewTitle = 'Preview'
    previewDesc = 'Sample text to judge edge comfort (serif / sans mix).'
    previewSample = 'Display & Font ClearyDisplay'
    previewZh = 'Chinese sample: clarity, brightness, contrast, gamma — judge sharpness at a glance.'
    themeTitle = 'Appearance'
    themeHintPick = 'Pick a UI style. GITHUB / Apple / DSA / Chrome are fixed palettes; System only toggles light/dark.'
    themeHintLight = 'UI theme: Light (clean)'
    themeHintDark = 'UI theme: Dark'
    themeHintGithub = 'UI theme: GITHUB'
    themeHintApple = 'UI theme: Apple'
    themeHintDsa = 'UI theme: DSA'
    themeHintChrome = 'UI theme: Chrome'
    themeHintSystemFmt = 'UI theme: System (Windows is {0})'
    themeLightShort = 'L'
    themeLight = 'Light'
    themeLightDesc = 'High-contrast clean white, Claude-like hierarchy'
    themeDarkShort = 'D'
    themeDark = 'Dark'
    themeDarkDesc = 'Dark UI, easier at night'
    themeGithubShort = 'GH'
    themeGithub = 'GITHUB'
    themeGithubDesc = 'GitHub: gray canvas + #0969DA text + green tracks/borders; squarer chips'
    themeAppleUiShort = 'A'
    themeAppleUi = 'Apple'
    themeAppleUiDesc = 'Apple: #F5F5F7 cool gray + system blue; large round stroked chips'
    themeDsaShort = 'DSA'
    themeDsa = 'DSA'
    themeDsaDesc = 'DSA: soft blue canvas, pastel blue text, mint green tracks/selection'
    themeChromeShort = 'C'
    themeChrome = 'Chrome'
    themeChromeDesc = 'Chrome: blue-tinted canvas; white/blue/red (#1A73E8 + #EA4335)'
    themeSysShort = 'S'
    themeSystem = 'System'
    themeSystemDesc = 'Follow Windows light / dark mode'
    lightWord = 'Light'
    darkWord = 'Dark'
    btnReset = 'Reset profile'
    btnApply = 'Apply now'
    btnSaveClose = 'Save & close'
    footerHint = 'Side-by-side controls · live slider preview · Apply writes settings'
    autoStartTitle = 'Apply at logon'
    autoStartDesc = 'Re-apply brightness/contrast/software gamma when Windows starts (gamma always resets; not a permission issue).'
    autoStartOn = 'Logon auto-apply enabled'
    autoStartOff = 'Logon auto-apply disabled'
    colorCalibTitle = 'Color calibration'
    colorCalibName = 'Display color calibration'
    colorCalibDesc = 'Calibrate display color, brightness, and contrast'
    btnColorCalib = 'Calibrate display'
    tip = 'Notice'
    apple = 'Apple'
    huawei = 'Huawei'
    asus = 'ASUS'
    samsung = 'Samsung'
    generic = 'Generic'
    tipApple = 'Display·Apple: clean white, soft mids (screen only)'
    tipLg = 'Display·LG: cooler, crisper (screen only)'
    tipHuawei = 'Display·Huawei: brighter white, lifted mids (screen only)'
    tipAsus = 'Display·ASUS ProArt: reference brightness (screen only)'
    tipSamsung = 'Display·Samsung: AMOLED punch, stronger contrast (screen only)'
    tipGeneric = 'Display·Generic: balanced defaults (screen only)'
    tipFontApple = 'Font·Apple: soft ClearType (γ≈1.15)'
    tipFontLg = 'Font·LG: crisp ClearType (γ≈1.68)'
    tipFontHuawei = 'Font·Huawei: slightly sharp ClearType (γ≈1.55)'
    tipFontAsus = 'Font·ASUS: standard ClearType (γ=1.40)'
    tipFontSamsung = 'Font·Samsung: sharper ClearType (γ≈1.50)'
    tipFontGeneric = 'Font·Generic: Windows default ClearType (γ=1.40)'
    recAppleTarget = 'Studio Display: clean white, soft mids'
    recLgTarget = 'UltraFine / Nano IPS: cooler, crisper'
    recHuaweiTarget = 'Mate flagship: luminous white, lifted mids'
    recAsusTarget = 'ProArt: reference brightness, standard gamma'
    recSamsungTarget = 'Galaxy / Odyssey: luminous, punchy contrast'
    recGenericTarget = 'Default balanced profile'
    fontAppleTarget = 'Softer edges, macOS-like feel'
    fontLgTarget = 'Crisper edges for IPS sharpness'
    fontHuaweiTarget = 'Slightly sharp CJK edges'
    fontAsusTarget = 'Windows standard ClearType'
    fontSamsungTarget = 'Sharper edges, One UI-like feel'
    fontGenericTarget = 'Windows default font smoothing'
    recAppleHint = 'Applied Apple display preset (fonts unchanged — set on Font tab)'
    recLgHint = 'Applied LG display preset (fonts unchanged)'
    recHuaweiHint = 'Applied Huawei display preset (fonts unchanged)'
    recAsusHint = 'Applied ASUS display preset (fonts unchanged)'
    recSamsungHint = 'Applied Samsung display preset (fonts unchanged)'
    recGenericHint = 'Applied generic display preset (fonts unchanged)'
    fontAppleHint = 'Applied Apple font preset: soft ClearType (γ≈1.15)'
    fontLgHint = 'Applied LG font preset: crisp ClearType (γ≈1.68)'
    fontHuaweiHint = 'Applied Huawei font preset: sharp ClearType (γ≈1.55)'
    fontAsusHint = 'Applied ASUS font preset: standard ClearType (γ=1.40)'
    fontSamsungHint = 'Applied Samsung font preset: sharper ClearType (γ≈1.50)'
    fontGenericHint = 'Applied generic font preset: standard ClearType (γ=1.40)'
    recPreviewFmt = 'Preset "{0}" previewed. Fine-tune, or Apply to write the monitor.'
    previewPaused = 'Preview paused: editing the other power profile'
    livePreviewFmt = 'Live preview · Bright {0} · Contrast {1}'
    previewFail = 'Partial preview failed — try Apply again'
    fontApplied = 'Font settings applied. Some apps need a restart.'
    needPresetName = 'Enter a profile name, e.g. Profile 1'
    savedPresetFmt = 'Saved profile: {0}'
    pickPreset = 'Select a saved profile first'
    loadedPresetFmt = 'Loaded profile: {0}'
    pickDelPreset = 'Select a profile to delete'
    deletedPresetFmt = 'Deleted profile: {0}'
    appliedFmt = 'Applied & saved ({0}): Bright {1} · Contrast {2} · γ {3:N2} · Scale {4:N2}'
    appliedGammaOnly = 'Gamma/scale saved ({0}). Brightness/contrast readback failed — try again'
    modeAc = 'AC'
    modeBat = 'Battery'
    readyApply = 'Ready. Click Apply to write brightness/contrast to the monitor.'
    readyNoPreview = 'Ready (preview not applied).'
    initFail = 'UI init failed: '
    startFail = 'Window failed to start: '
    bindWarn = 'Unbound controls: '
    bindWarn2 = "`nUI may be incomplete, but will still open."
  }
}

function Get-UiLang {
  if ($script:uiSettings -and $script:uiSettings.lang -in @('zh','en')) { return $script:uiSettings.lang }
  return 'zh'
}

function T([string]$key) {
  $lang = Get-UiLang
  foreach ($tryLang in @($lang, 'zh')) {
    $dict = $script:I18n[$tryLang]
    if ($null -eq $dict) { continue }
    if ($dict -is [System.Collections.IDictionary] -and $dict.Contains($key)) {
      return [string]$dict[$key]
    }
  }
  return $key
}

function TF([string]$key) {
  $fmt = T $key
  $argsList = @($args)
  try {
    if ($argsList.Count -gt 0) { return ($fmt -f $argsList) }
  } catch {}
  return $fmt
}

# 品牌推荐档：显示参数与字体参数同表，但 Apply 时分开调用（互不联动）。
function Get-RecommendProfiles([string]$id) {
  switch ($id) {
    'apple' {
      return @{
        ac      = @{ brightness = 80; contrast = 50; gammaPower = 0.96; scale = 1.00 }
        battery = @{ brightness = 55; contrast = 50; gammaPower = 0.98; scale = 0.95 }
        font    = @{ clearType = $true; gamma = 1.15; orientation = 1 }
        label   = (T 'apple')
        target  = (T 'recAppleTarget')
        hint    = (T 'recAppleHint')
        fontTarget = (T 'fontAppleTarget')
        fontHint   = (T 'fontAppleHint')
      }
    }
    'lg' {
      return @{
        ac      = @{ brightness = 85; contrast = 55; gammaPower = 1.02; scale = 1.00 }
        battery = @{ brightness = 58; contrast = 52; gammaPower = 1.00; scale = 0.95 }
        font    = @{ clearType = $true; gamma = 1.68; orientation = 1 }
        label   = 'LG'
        target  = (T 'recLgTarget')
        hint    = (T 'recLgHint')
        fontTarget = (T 'fontLgTarget')
        fontHint   = (T 'fontLgHint')
      }
    }
    'huawei' {
      return @{
        ac      = @{ brightness = 92; contrast = 58; gammaPower = 0.88; scale = 0.98 }
        battery = @{ brightness = 62; contrast = 55; gammaPower = 0.92; scale = 0.95 }
        font    = @{ clearType = $true; gamma = 1.55; orientation = 1 }
        label   = (T 'huawei')
        target  = (T 'recHuaweiTarget')
        hint    = (T 'recHuaweiHint')
        fontTarget = (T 'fontHuaweiTarget')
        fontHint   = (T 'fontHuaweiHint')
      }
    }
    'asus' {
      return @{
        ac      = @{ brightness = 75; contrast = 50; gammaPower = 1.00; scale = 1.00 }
        battery = @{ brightness = 50; contrast = 50; gammaPower = 1.00; scale = 0.95 }
        font    = @{ clearType = $true; gamma = 1.40; orientation = 1 }
        label   = (T 'asus')
        target  = (T 'recAsusTarget')
        hint    = (T 'recAsusHint')
        fontTarget = (T 'fontAsusTarget')
        fontHint   = (T 'fontAsusHint')
      }
    }
    'samsung' {
      return @{
        ac      = @{ brightness = 90; contrast = 62; gammaPower = 0.98; scale = 1.00 }
        battery = @{ brightness = 48; contrast = 55; gammaPower = 1.05; scale = 0.92 }
        font    = @{ clearType = $true; gamma = 1.50; orientation = 1 }
        label   = (T 'samsung')
        target  = (T 'recSamsungTarget')
        hint    = (T 'recSamsungHint')
        fontTarget = (T 'fontSamsungTarget')
        fontHint   = (T 'fontSamsungHint')
      }
    }
    default {
      return @{
        ac      = @{ brightness = 90; contrast = 50; gammaPower = 1.00; scale = 1.00 }
        battery = @{ brightness = 70; contrast = 50; gammaPower = 1.00; scale = 0.95 }
        font    = @{ clearType = $true; gamma = 1.40; orientation = 1 }
        label   = (T 'generic')
        target  = (T 'recGenericTarget')
        hint    = (T 'recGenericHint')
        fontTarget = (T 'fontGenericTarget')
        fontHint   = (T 'fontGenericHint')
      }
    }
  }
}

function Set-FontUiFromRecommend($font) {
  if (-not $font) { return }
  $prev = $script:loading
  $script:loading = $true
  try {
    if ($ChkClearType) { $ChkClearType.IsChecked = [bool]$font.clearType }
    $g = [double]$font.gamma
    if ($g -lt 1.0) { $g = 1.0 }
    if ($g -gt 2.2) { $g = 2.2 }
    if ($SlFontGamma) { $SlFontGamma.Value = $g }
    if ($TxtFontGamma) { $TxtFontGamma.Text = ('{0:N2}' -f $g) }
    if ([int]$font.orientation -eq 0) {
      if ($RbBgr) { $RbBgr.IsChecked = $true }
    } else {
      if ($RbRgb) { $RbRgb.IsChecked = $true }
    }
  } finally {
    $script:loading = $prev
  }
}

function Update-RecommendPowerHighlight {
  # 与左上「当前：接电/电池」同步：当前供电对应的那一行用强调蓝
  $onAc = Get-IsOnAc
  $accent = Get-ResourceBrush 'Accent'
  $muted = Get-ResourceBrush 'TextSecondary'
  if ($TxtRecAcParams) {
    $TxtRecAcParams.Foreground = $(if ($onAc) { $accent } else { $muted })
  }
  if ($TxtRecBatParams) {
    $TxtRecBatParams.Foreground = $(if ($onAc) { $muted } else { $accent })
  }
}

function Update-RecommendDetailPanel {
  $id = if ($script:uiSettings -and $script:uiSettings.recommend) { $script:uiSettings.recommend } else { 'generic' }
  $rec = Get-RecommendProfiles $id
  $ac = $rec.ac
  $bat = $rec.battery
  if ($TxtRecTarget) { $TxtRecTarget.Text = $rec.target }
  if ($TxtRecAcParams) {
    $TxtRecAcParams.Text = (TF 'recAcFmt' $ac.brightness $ac.contrast $ac.gammaPower $ac.scale)
  }
  if ($TxtRecBatParams) {
    $TxtRecBatParams.Text = (TF 'recBatFmt' $bat.brightness $bat.contrast $bat.gammaPower $bat.scale)
  }
  Update-RecommendPowerHighlight
  if ($TxtRecFontParams) {
    $fid = if ($script:uiSettings -and $script:uiSettings.fontRecommend) { $script:uiSettings.fontRecommend } else { 'generic' }
    $frec = Get-RecommendProfiles $fid
    $TxtRecFontParams.Text = (TF 'fontRecTitleFmt' $frec.label) + ' · ' + $frec.fontTarget
  }
  if ($TxtRecNote) { $TxtRecNote.Text = (T 'recNote') }
}

function Update-FontRecommendDetailPanel {
  $id = if ($script:uiSettings -and $script:uiSettings.fontRecommend) { $script:uiSettings.fontRecommend } else { 'generic' }
  $rec = Get-RecommendProfiles $id
  $font = $rec.font
  if ($TxtFontRecTitle) { $TxtFontRecTitle.Text = (TF 'fontRecTitleFmt' $rec.label) }
  if ($TxtFontRecTarget) { $TxtFontRecTarget.Text = $rec.fontTarget }
  if ($TxtFontRecParams -and $font) {
    $ct = if ([bool]$font.clearType) { (T 'recFontOn') } else { (T 'recFontOff') }
    $oriLabel = if ([int]$font.orientation -eq 0) { 'BGR' } else { 'RGB' }
    $TxtFontRecParams.Text = (TF 'recFontFmt' $ct ([double]$font.gamma) $oriLabel)
  }
}

function Update-RecommendBadgeStyles {
  # 顶部胶囊：随当前页签切换高亮（显示档 / 字体档互不影响）
  $tab = 'display'
  try {
    if ($TabFont -and $TabFont.IsSelected) { $tab = 'font' }
    elseif ($TabTheme -and $TabTheme.IsSelected) { $tab = 'theme' }
  } catch {}

  if ($BdRecBar) {
    if ($tab -eq 'theme') {
      $BdRecBar.Visibility = [System.Windows.Visibility]::Collapsed
    } else {
      $BdRecBar.Visibility = [System.Windows.Visibility]::Visible
    }
  }
  if ($tab -eq 'theme') { return }

  $sel = if ($tab -eq 'font') {
    if ($script:uiSettings -and $script:uiSettings.fontRecommend) { $script:uiSettings.fontRecommend } else { 'generic' }
  } else {
    if ($script:uiSettings -and $script:uiSettings.recommend) { $script:uiSettings.recommend } else { 'generic' }
  }

  $items = @(
    @{ Id='apple';   Bd=$BdRecApple;   Txt=$TxtRecApple },
    @{ Id='lg';      Bd=$BdRecLg;      Txt=$TxtRecLg },
    @{ Id='huawei';  Bd=$BdRecHuawei;  Txt=$TxtRecHuawei },
    @{ Id='asus';    Bd=$BdRecAsus;    Txt=$TxtRecAsus },
    @{ Id='samsung'; Bd=$BdRecSamsung; Txt=$TxtRecSamsung },
    @{ Id='generic'; Bd=$BdRecGeneric; Txt=$TxtRecGeneric }
  )
  foreach ($it in $items) {
    if (-not $it.Bd -or -not $it.Txt) { continue }
    $on = ($it.Id -eq $sel)
    if ($on) {
      $it.Bd.Background = Get-ResourceBrush 'AccentSoft'
      $it.Txt.Foreground = Get-ResourceBrush 'Accent'
      try {
        $mode = if ($script:uiSettings) { $script:uiSettings.theme } else { 'light' }
        if ($mode -in @('apple','chrome','github','dsa')) {
          # Chrome 红 / GitHub·DSA 绿：选中描边用 BrandAlt，界面才能看到辅色（预览色块里有、别处没有）
          if ($mode -in @('chrome','github','dsa')) {
            $it.Bd.BorderBrush = Get-ResourceBrush 'BrandAlt'
            $it.Bd.BorderThickness = New-Object System.Windows.Thickness 2
          } else {
            $it.Bd.BorderBrush = Get-ResourceBrush 'Accent'
          }
        }
      } catch {}
    } else {
      $it.Bd.Background = Get-ResourceBrush 'GhostBg'
      $it.Txt.Foreground = Get-ResourceBrush 'TextSecondary'
      try {
        $mode = if ($script:uiSettings) { $script:uiSettings.theme } else { 'light' }
        if ($mode -in @('apple','chrome','github','dsa')) {
          $it.Bd.BorderBrush = Get-ResourceBrush 'CardBorder'
          if ($mode -eq 'dsa') {
            $it.Bd.BorderThickness = New-Object System.Windows.Thickness 0
          } elseif ($mode -eq 'github') {
            $it.Bd.BorderThickness = New-Object System.Windows.Thickness 1
          }
        }
      } catch {}
    }
  }

  # 工具提示随页签切换
  if ($tab -eq 'font') {
    if ($BdRecApple) { $BdRecApple.ToolTip = (T 'tipFontApple') }
    if ($BdRecLg) { $BdRecLg.ToolTip = (T 'tipFontLg') }
    if ($BdRecHuawei) { $BdRecHuawei.ToolTip = (T 'tipFontHuawei') }
    if ($BdRecAsus) { $BdRecAsus.ToolTip = (T 'tipFontAsus') }
    if ($BdRecSamsung) { $BdRecSamsung.ToolTip = (T 'tipFontSamsung') }
    if ($BdRecGeneric) { $BdRecGeneric.ToolTip = (T 'tipFontGeneric') }
  } else {
    if ($BdRecApple) { $BdRecApple.ToolTip = (T 'tipApple') }
    if ($BdRecLg) { $BdRecLg.ToolTip = (T 'tipLg') }
    if ($BdRecHuawei) { $BdRecHuawei.ToolTip = (T 'tipHuawei') }
    if ($BdRecAsus) { $BdRecAsus.ToolTip = (T 'tipAsus') }
    if ($BdRecSamsung) { $BdRecSamsung.ToolTip = (T 'tipSamsung') }
    if ($BdRecGeneric) { $BdRecGeneric.ToolTip = (T 'tipGeneric') }
  }
}

function Update-FontRecommendBadgeStyles {
  Update-RecommendBadgeStyles
}

function Apply-HeaderRecommend([string]$id) {
  $tab = 'display'
  try {
    if ($TabFont -and $TabFont.IsSelected) { $tab = 'font' }
    elseif ($TabTheme -and $TabTheme.IsSelected) { $tab = 'theme' }
  } catch {}
  if ($tab -eq 'font') { Apply-FontRecommend $id }
  elseif ($tab -eq 'display') { Apply-Recommend $id }
}

function Apply-Recommend([string]$id, [bool]$persist = $true) {
  if ($id -notin @('apple','lg','huawei','asus','samsung','generic')) { $id = 'generic' }
  $rec = Get-RecommendProfiles $id
  # 仅写入显示参数，不改字体
  $profiles.ac.brightness = [int]$rec.ac.brightness
  $profiles.ac.contrast = [int]$rec.ac.contrast
  $profiles.ac.gammaPower = [double]$rec.ac.gammaPower
  $profiles.ac.scale = [double]$rec.ac.scale
  $profiles.battery.brightness = [int]$rec.battery.brightness
  $profiles.battery.contrast = [int]$rec.battery.contrast
  $profiles.battery.gammaPower = [double]$rec.battery.gammaPower
  $profiles.battery.scale = [double]$rec.battery.scale

  if (-not $script:uiSettings) { $script:uiSettings = @{ theme = 'light'; recommend = $id; fontRecommend = 'generic' } }
  $script:uiSettings.recommend = $id
  Update-RecommendBadgeStyles
  Update-RecommendDetailPanel

  if ($RbAc -and $RbAc.IsChecked) { Set-SlidersFromProfile $profiles.ac }
  else { Set-SlidersFromProfile $profiles.battery }

  if ($persist) {
    try { Save-ActiveProfiles $profiles } catch {}
    try { Save-UiSettings $script:uiSettings } catch {}
  }
  Apply-If-Active
  Flash-Status $rec.hint
  if ($TxtReadback) {
    $TxtReadback.Text = (TF 'recPreviewFmt' $rec.label)
  }
}

function Apply-FontRecommend([string]$id, [bool]$persist = $true) {
  if ($id -notin @('apple','lg','huawei','asus','samsung','generic')) { $id = 'generic' }
  $rec = Get-RecommendProfiles $id
  if (-not $script:uiSettings) { $script:uiSettings = @{ theme = 'light'; recommend = 'generic'; fontRecommend = $id } }
  $script:uiSettings.fontRecommend = $id
  Update-FontRecommendBadgeStyles
  Update-FontRecommendDetailPanel
  Update-RecommendDetailPanel
  if ($rec.font) {
    Set-FontUiFromRecommend $rec.font
    try {
      Set-FontSmoothingSettings ([bool]$rec.font.clearType) ([double]$rec.font.gamma) ([int]$rec.font.orientation)
    } catch {}
  }
  if ($persist) {
    try { Save-UiSettings $script:uiSettings } catch {}
  }
  Flash-Status $rec.fontHint
}

function Set-ResourceBrush([string]$key, [string]$hex) {
  # PowerShell 里 New-Object SolidColorBrush $color 容易把 Color 误当成字符串，导致 Background 报 #AARRGGBB 无效
  $color = [System.Windows.Media.Color][System.Windows.Media.ColorConverter]::ConvertFromString($hex)
  $existing = $window.Resources[$key]
  if ($existing -is [System.Windows.Media.SolidColorBrush]) {
    if ($existing.IsFrozen) {
      $brush = $existing.Clone()
      $brush.Color = $color
      $window.Resources[$key] = $brush
    } else {
      $existing.Color = $color
    }
  } else {
    $brush = New-Object System.Windows.Media.SolidColorBrush
    $brush.Color = $color
    $window.Resources[$key] = $brush
  }
}

function Get-ResourceBrush([string]$key) {
  $b = $window.Resources[$key]
  if ($b -is [System.Windows.Media.SolidColorBrush]) { return $b }
  return [System.Windows.Media.Brushes]::Transparent
}

function Get-ThemePalette([string]$mode) {
  # 三套品牌风必须一眼可辨：底色 / 主色 / 辅色 / 圆角气质都不同
  switch ($mode) {
    'github' {
      return @{
        WinBg='#F6F8FA'; CardBg='#FFFFFF'; CardBorder='#D0D7DE'
        TextPrimary='#24292F'; TextSecondary='#57606A'; TextMuted='#8C959F'
        Accent='#0969DA'; AccentSoft='#DDF4FF'; BrandAlt='#1A7F37'
        GhostBg='#FFFFFF'; TrackBg='#1A7F37'
        InputBg='#FFFFFF'; InputBorder='#D0D7DE'; ThumbFill='#FFFFFF'
      }
    }
    'apple' {
      return @{
        WinBg='#F5F5F7'; CardBg='#FFFFFF'; CardBorder='#C7C7CC'
        TextPrimary='#1D1D1F'; TextSecondary='#6E6E73'; TextMuted='#86868B'
        Accent='#0071E3'; AccentSoft='#E8F1FB'; BrandAlt='#BF5AF2'
        GhostBg='#FFFFFF'; TrackBg='#0071E3'
        InputBg='#FFFFFF'; InputBorder='#C7C7CC'; ThumbFill='#FFFFFF'
      }
    }
    'dsa' {
      # 每日选股分析 DSA：柔和浅蓝浮层、粉彩蓝字 + 薄荷绿辅色（滑条/选中描边）
      return @{
        WinBg='#EAF2FA'; CardBg='#FFFFFF'; CardBorder='#C8DBEF'
        TextPrimary='#1E2A3A'; TextSecondary='#5A6B7D'; TextMuted='#8A9AAB'
        Accent='#6B9FD4'; AccentSoft='#DDEBFA'; BrandAlt='#5CBF9A'
        GhostBg='#F3F8FD'; TrackBg='#5CBF9A'
        InputBg='#FFFFFF'; InputBorder='#B7CFE8'; ThumbFill='#FFFFFF'
      }
    }
    'chrome' {
      # 首选：白 / 谷歌蓝 / 谷歌红（对照 Chrome 自定义外观色块）
      return @{
        WinBg='#E8F0FE'; CardBg='#FFFFFF'; CardBorder='#DADCE0'
        TextPrimary='#202124'; TextSecondary='#5F6368'; TextMuted='#80868B'
        Accent='#1A73E8'; AccentSoft='#D2E3FC'; BrandAlt='#EA4335'
        GhostBg='#FFFFFF'; TrackBg='#EA4335'
        InputBg='#FFFFFF'; InputBorder='#1A73E8'; ThumbFill='#FFFFFF'
      }
    }
    'dark' {
      return @{
        WinBg='#1C1C1E'; CardBg='#2C2C2E'; CardBorder='#3A3A3C'
        TextPrimary='#F2F2F7'; TextSecondary='#A1A1A6'; TextMuted='#8E8E93'
        Accent='#0A84FF'; AccentSoft='#1A3A5C'; BrandAlt='#FF9F0A'
        GhostBg='#3A3A3C'; TrackBg='#636366'
        InputBg='#1C1C1E'; InputBorder='#48484A'; ThumbFill='#2C2C2E'
      }
    }
    'system' {
      if (Get-SystemIsLight) { return Get-ThemePalette 'light' }
      return Get-ThemePalette 'dark'
    }
    default {
      return @{
        WinBg='#F7F7F8'; CardBg='#FFFFFF'; CardBorder='#E6E6E8'
        TextPrimary='#0F0F0F'; TextSecondary='#5C5C5C'; TextMuted='#8A8A8A'
        Accent='#2B6DEF'; AccentSoft='#EEF3FF'; BrandAlt='#2B6DEF'
        GhostBg='#F0F0F2'; TrackBg='#B8BCC4'
        InputBg='#FFFFFF'; InputBorder='#D4D4D8'; ThumbFill='#FFFFFF'
      }
    }
  }
}

function Apply-ThemeShape([string]$mode) {
  # 只改控件实例，不改 Style.Setters（密封后会抛错，导致后续交互异常）
  $chipR = 20.0
  $chipBorder = 0.0
  $cardR = 14.0
  switch ($mode) {
    'github' { $chipR = 6;  $chipBorder = 1;   $cardR = 8 }
    'apple'  { $chipR = 22; $chipBorder = 1.5; $cardR = 18 }
    'dsa'    { $chipR = 20; $chipBorder = 0;   $cardR = 20 }
    'chrome' { $chipR = 24; $chipBorder = 1.5; $cardR = 20 }
    'dark'   { $chipR = 18; $chipBorder = 0;   $cardR = 12 }
    default  { $chipR = 20; $chipBorder = 0;   $cardR = 14 }
  }
  $chips = @($BdLang, $BdRecApple, $BdRecLg, $BdRecHuawei, $BdRecAsus, $BdRecSamsung, $BdRecGeneric)
  foreach ($c in $chips) {
    if (-not $c) { continue }
    try {
      $c.CornerRadius = New-Object System.Windows.CornerRadius $chipR
      $c.BorderThickness = New-Object System.Windows.Thickness $chipBorder
      if ($chipBorder -gt 0) {
        $c.BorderBrush = Get-ResourceBrush 'CardBorder'
      }
    } catch {}
  }
  foreach ($bd in @($BdThemeLight,$BdThemeDark,$BdThemeGithub,$BdThemeApple,$BdThemeDsa,$BdThemeChrome,$BdThemeSystem)) {
    if (-not $bd) { continue }
    try { $bd.CornerRadius = New-Object System.Windows.CornerRadius $cardR } catch {}
  }
}

function Update-ThemeCardStyles([string]$mode) {
  $cards = @{
    light  = $BdThemeLight
    dark   = $BdThemeDark
    github = $BdThemeGithub
    apple  = $BdThemeApple
    dsa    = $BdThemeDsa
    chrome = $BdThemeChrome
    system = $BdThemeSystem
  }
  $marks = @{
    light  = $TxtThemeLightMark
    dark   = $TxtThemeDarkMark
    github = $TxtThemeGithubMark
    apple  = $TxtThemeAppleMark
    dsa    = $TxtThemeDsaMark
    chrome = $TxtThemeChromeMark
    system = $TxtThemeSystemMark
  }
  foreach ($k in $cards.Keys) {
    $bd = $cards[$k]
    $mk = $marks[$k]
    if (-not $bd) { continue }
    if ($k -eq $mode) {
      # GitHub / DSA / Chrome：选中卡用 BrandAlt（绿/绿/红），与色块预览一致
      $selBrush = if ($mode -in @('github','dsa','chrome')) { Get-ResourceBrush 'BrandAlt' } else { Get-ResourceBrush 'Accent' }
      $bd.BorderBrush = $selBrush
      $bd.BorderThickness = New-Object System.Windows.Thickness 2
      $bd.Background = Get-ResourceBrush 'AccentSoft'
      if ($mk) {
        $mk.Text = '✓'
        $mk.Foreground = $selBrush
      }
    } else {
      $bd.BorderBrush = Get-ResourceBrush 'CardBorder'
      $bd.BorderThickness = New-Object System.Windows.Thickness 1
      $bd.Background = Get-ResourceBrush 'CardBg'
      if ($mk) {
        $mk.Text = ''
        $mk.Foreground = Get-ResourceBrush 'Accent'
      }
    }
  }
}

function Apply-UiTheme([string]$mode) {
  try {
    if (-not $script:uiSettings) { $script:uiSettings = @{ theme = 'light' } }
    if (-not $mode) { $mode = 'light' }
    if ($mode -notin @('light','dark','github','apple','dsa','chrome','system')) { $mode = 'light' }
    $script:uiSettings.theme = $mode
    $pal = Get-ThemePalette $mode
    foreach ($k in $pal.Keys) {
      Set-ResourceBrush $k $pal[$k]
    }

    if ($window) { $window.Background = Get-ResourceBrush 'WinBg' }
    Apply-ThemeShape $mode
    if ($TxtThemeHint) {
      switch ($mode) {
        'light'  { $TxtThemeHint.Text = (T 'themeHintLight') }
        'dark'   { $TxtThemeHint.Text = (T 'themeHintDark') }
        'github' { $TxtThemeHint.Text = (T 'themeHintGithub') }
        'apple'  { $TxtThemeHint.Text = (T 'themeHintApple') }
        'dsa'    { $TxtThemeHint.Text = (T 'themeHintDsa') }
        'chrome' { $TxtThemeHint.Text = (T 'themeHintChrome') }
        default {
          $sys = if (Get-SystemIsLight) { T 'lightWord' } else { T 'darkWord' }
          $TxtThemeHint.Text = (TF 'themeHintSystemFmt' $sys)
        }
      }
    }
    Update-ThemeCardStyles $mode
    Update-RecommendBadgeStyles
    Update-FontRecommendBadgeStyles
    Save-UiSettings $script:uiSettings
  } catch {
    # theme apply best-effort
  }
}

function Apply-UiLanguage([string]$lang, [bool]$persist = $true) {
  if ($lang -notin @('zh','en')) { $lang = 'zh' }
  if (-not $script:uiSettings) { $script:uiSettings = @{ theme = 'light'; recommend = 'generic'; lang = $lang } }
  $script:uiSettings.lang = $lang

  if ($window) { $window.Title = (T 'appTitle') }
  if ($TxtPageTitle) { $TxtPageTitle.Text = (T 'appTitle') }
  if ($TxtLangCode) { $TxtLangCode.Text = $(if ($lang -eq 'en') { 'EN' } else { '中' }) }
  if ($BdLang) { $BdLang.ToolTip = (T 'langTip') }

  if ($TabDisplay) { $TabDisplay.Header = (T 'tabDisplay') }
  if ($TabFont) { $TabFont.Header = (T 'tabFont') }
  if ($TabTheme) { $TabTheme.Header = (T 'tabTheme') }

  if ($TxtPowerTitle) { $TxtPowerTitle.Text = (T 'powerTitle') }
  if ($TxtPowerDesc) { $TxtPowerDesc.Text = (T 'powerDesc') }
  if ($RbAc) { $RbAc.Content = (T 'rbAc') }
  if ($RbBat) { $RbBat.Content = (T 'rbBat') }

  if ($TxtPresetTitle) { $TxtPresetTitle.Text = (T 'presetTitle') }
  if ($TxtPresetDesc) { $TxtPresetDesc.Text = (T 'presetDesc') }
  if ($TxtPresetExisting) { $TxtPresetExisting.Text = (T 'presetExisting') }
  if ($TxtPresetNameLabel) { $TxtPresetNameLabel.Text = (T 'presetName') }
  if ($BtnSavePreset) { $BtnSavePreset.Content = (T 'btnSavePreset') }
  if ($BtnLoadPreset) { $BtnLoadPreset.Content = (T 'btnLoadPreset') }
  if ($BtnDelPreset) { $BtnDelPreset.Content = (T 'btnDelPreset') }

  if ($TxtBrightLabel) { $TxtBrightLabel.Text = (T 'bright') }
  if ($TxtContrastLabel) { $TxtContrastLabel.Text = (T 'contrast') }
  if ($TxtGammaLabel) { $TxtGammaLabel.Text = (T 'gamma') }
  if ($TxtGammaHint) { $TxtGammaHint.Text = (T 'gammaHint') }
  if ($TxtScaleLabel) { $TxtScaleLabel.Text = (T 'scale') }
  if ($TxtScaleHint) { $TxtScaleHint.Text = (T 'scaleHint') }
  if ($TxtAutoStartTitle) { $TxtAutoStartTitle.Text = (T 'autoStartTitle') }
  if ($TxtAutoStartDesc) { $TxtAutoStartDesc.Text = (T 'autoStartDesc') }
  if ($ChkAutoStart) { $ChkAutoStart.Content = (T 'autoStartTitle') }
  if ($TxtColorCalibTitle) { $TxtColorCalibTitle.Text = (T 'colorCalibTitle') }
  if ($TxtColorCalibName) { $TxtColorCalibName.Text = (T 'colorCalibName') }
  if ($TxtColorCalibDesc) { $TxtColorCalibDesc.Text = (T 'colorCalibDesc') }
  if ($BtnColorCalib) { $BtnColorCalib.Content = (T 'btnColorCalib') }

  if ($TxtClearTypeTitle) { $TxtClearTypeTitle.Text = (T 'clearTypeTitle') }
  if ($TxtClearTypeDesc) { $TxtClearTypeDesc.Text = (T 'clearTypeDesc') }
  if ($ChkClearType) { $ChkClearType.Content = (T 'enableClearType') }
  if ($TxtFontGammaLabel) { $TxtFontGammaLabel.Text = (T 'fontGamma') }
  if ($TxtFontGammaHint) { $TxtFontGammaHint.Text = (T 'fontGammaHint') }
  if ($TxtSubpixelLabel) { $TxtSubpixelLabel.Text = (T 'subpixel') }
  if ($RbRgb) { $RbRgb.Content = (T 'rgbCommon') }
  if ($BtnApplyFont) { $BtnApplyFont.Content = (T 'btnApplyFont') }
  if ($BtnClearTypeWizard) { $BtnClearTypeWizard.Content = (T 'btnClearTypeWizard') }
  if ($TxtPreviewTitle) { $TxtPreviewTitle.Text = (T 'previewTitle') }
  if ($TxtPreviewDesc) { $TxtPreviewDesc.Text = (T 'previewDesc') }
  if ($TxtPreviewSample) { $TxtPreviewSample.Text = (T 'previewSample') }
  if ($TxtPreviewZh) { $TxtPreviewZh.Text = (T 'previewZh') }

  if ($TxtThemeTitle) { $TxtThemeTitle.Text = (T 'themeTitle') }
  if ($TxtThemeHint -and $script:uiSettings -and $script:uiSettings.theme -eq $null) { $TxtThemeHint.Text = (T 'themeHintPick') }
  if ($TxtThemeLightShort) { $TxtThemeLightShort.Text = (T 'themeLightShort') }
  if ($TxtThemeLightName) { $TxtThemeLightName.Text = (T 'themeLight') }
  if ($TxtThemeLightDesc) { $TxtThemeLightDesc.Text = (T 'themeLightDesc') }
  if ($TxtThemeDarkShort) { $TxtThemeDarkShort.Text = (T 'themeDarkShort') }
  if ($TxtThemeDarkName) { $TxtThemeDarkName.Text = (T 'themeDark') }
  if ($TxtThemeDarkDesc) { $TxtThemeDarkDesc.Text = (T 'themeDarkDesc') }
  if ($TxtThemeGithubShort) { $TxtThemeGithubShort.Text = (T 'themeGithubShort') }
  if ($TxtThemeGithubName) { $TxtThemeGithubName.Text = (T 'themeGithub') }
  if ($TxtThemeGithubDesc) { $TxtThemeGithubDesc.Text = (T 'themeGithubDesc') }
  if ($TxtThemeAppleShort) { $TxtThemeAppleShort.Text = (T 'themeAppleUiShort') }
  if ($TxtThemeAppleName) { $TxtThemeAppleName.Text = (T 'themeAppleUi') }
  if ($TxtThemeAppleDesc) { $TxtThemeAppleDesc.Text = (T 'themeAppleUiDesc') }
  if ($TxtThemeDsaName) { $TxtThemeDsaName.Text = (T 'themeDsa') }
  if ($TxtThemeDsaDesc) { $TxtThemeDsaDesc.Text = (T 'themeDsaDesc') }
  if ($TxtThemeChromeShort) { $TxtThemeChromeShort.Text = (T 'themeChromeShort') }
  if ($TxtThemeChromeName) { $TxtThemeChromeName.Text = (T 'themeChrome') }
  if ($TxtThemeChromeDesc) { $TxtThemeChromeDesc.Text = (T 'themeChromeDesc') }
  if ($TxtThemeSysShort) { $TxtThemeSysShort.Text = (T 'themeSysShort') }
  if ($TxtThemeSysName) { $TxtThemeSysName.Text = (T 'themeSystem') }
  if ($TxtThemeSysDesc) { $TxtThemeSysDesc.Text = (T 'themeSystemDesc') }

  if ($BtnReset) { $BtnReset.Content = (T 'btnReset') }
  if ($BtnApply) { $BtnApply.Content = (T 'btnApply') }
  if ($BtnSaveClose) { $BtnSaveClose.Content = (T 'btnSaveClose') }
  if ($TxtFooterHint) { $TxtFooterHint.Text = (T 'footerHint') }

  if ($TxtRecApple) { $TxtRecApple.Text = (T 'apple') }
  if ($TxtRecHuawei) { $TxtRecHuawei.Text = (T 'huawei') }
  if ($TxtRecAsus) { $TxtRecAsus.Text = (T 'asus') }
  if ($TxtRecSamsung) { $TxtRecSamsung.Text = (T 'samsung') }
  if ($TxtRecGeneric) { $TxtRecGeneric.Text = (T 'generic') }
  if ($BdRecApple) { $BdRecApple.ToolTip = (T 'tipApple') }
  if ($BdRecLg) { $BdRecLg.ToolTip = (T 'tipLg') }
  if ($BdRecHuawei) { $BdRecHuawei.ToolTip = (T 'tipHuawei') }
  if ($BdRecAsus) { $BdRecAsus.ToolTip = (T 'tipAsus') }
  if ($BdRecSamsung) { $BdRecSamsung.ToolTip = (T 'tipSamsung') }
  if ($BdRecGeneric) { $BdRecGeneric.ToolTip = (T 'tipGeneric') }

  if ($TxtFontRecSection) { $TxtFontRecSection.Text = (T 'fontRecTitle') }
  if ($TxtFontRecDesc) { $TxtFontRecDesc.Text = (T 'fontRecDesc') }

  Update-RecommendBadgeStyles
  Update-RecommendDetailPanel
  Update-FontRecommendDetailPanel
  Update-PowerStatus
  if ($script:uiSettings.theme) {
    $m = $script:uiSettings.theme
    if ($TxtThemeHint) {
      switch ($m) {
        'light'  { $TxtThemeHint.Text = (T 'themeHintLight') }
        'dark'   { $TxtThemeHint.Text = (T 'themeHintDark') }
        'github' { $TxtThemeHint.Text = (T 'themeHintGithub') }
        'apple'  { $TxtThemeHint.Text = (T 'themeHintApple') }
        'dsa'    { $TxtThemeHint.Text = (T 'themeHintDsa') }
        'chrome' { $TxtThemeHint.Text = (T 'themeHintChrome') }
        default {
          $sys = if (Get-SystemIsLight) { T 'lightWord' } else { T 'darkWord' }
          $TxtThemeHint.Text = (TF 'themeHintSystemFmt' $sys)
        }
      }
    }
  }
  if ($persist) { Save-UiSettings $script:uiSettings }
}

function Toggle-UiLanguage {
  $cur = Get-UiLang
  $next = if ($cur -eq 'en') { 'zh' } else { 'en' }
  Apply-UiLanguage $next
}

$profiles = Load-ActiveProfiles
$presets = Load-Presets
$script:uiSettings = Load-UiSettings
if (-not $script:uiSettings -or -not $script:uiSettings.theme) {
  $script:uiSettings = @{ theme = 'light'; recommend = 'generic'; fontRecommend = 'generic'; lang = 'zh' }
}
if (-not $script:uiSettings.recommend) { $script:uiSettings.recommend = 'generic' }
if (-not $script:uiSettings.fontRecommend) { $script:uiSettings.fontRecommend = 'generic' }
if ($null -eq $script:uiSettings.autoStart) { $script:uiSettings.autoStart = $true }
if (-not $script:uiSettings.lang) { $script:uiSettings.lang = 'zh' }
# 默认确保开机写回（伽马重启必丢；不需要管理员权限）
try {
  if ([bool]$script:uiSettings.autoStart) { Set-StartupApply $true }
} catch {}
$script:loading = $true

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="屏幕与字体调节"
        Height="820" Width="940"
        MinHeight="720" MinWidth="860"
        WindowStartupLocation="CenterScreen"
        ResizeMode="CanResizeWithGrip"
        Topmost="True"
        Background="{DynamicResource WinBg}"
        FontFamily="Segoe UI, Microsoft YaHei UI, Segoe UI"
        FontSize="14"
        FontWeight="Normal"
        Foreground="{DynamicResource TextPrimary}"
        UseLayoutRounding="True"
        SnapsToDevicePixels="True"
        TextOptions.TextFormattingMode="Display"
        TextOptions.TextRenderingMode="Grayscale"
        TextOptions.TextHintingMode="Fixed"
        RenderOptions.ClearTypeHint="Auto"
        RenderOptions.BitmapScalingMode="HighQuality">
  <Window.Resources>
    <SolidColorBrush x:Key="WinBg" Color="#F7F7F8"/>
    <SolidColorBrush x:Key="CardBg" Color="#FFFFFF"/>
    <SolidColorBrush x:Key="CardBorder" Color="#E6E6E8"/>
    <SolidColorBrush x:Key="Accent" Color="#2B6DEF"/>
    <SolidColorBrush x:Key="AccentSoft" Color="#EEF3FF"/>
    <SolidColorBrush x:Key="BrandAlt" Color="#2B6DEF"/>
    <SolidColorBrush x:Key="TextPrimary" Color="#0F0F0F"/>
    <SolidColorBrush x:Key="TextSecondary" Color="#5C5C5C"/>
    <SolidColorBrush x:Key="TextMuted" Color="#8A8A8A"/>
    <SolidColorBrush x:Key="GhostBg" Color="#F0F0F2"/>
    <SolidColorBrush x:Key="TrackBg" Color="#B8BCC4"/>
    <SolidColorBrush x:Key="InputBg" Color="#FFFFFF"/>
    <SolidColorBrush x:Key="InputBorder" Color="#D4D4D8"/>
    <SolidColorBrush x:Key="ThumbFill" Color="#FFFFFF"/>
    <Style TargetType="TextBlock">
      <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
      <Setter Property="FontWeight" Value="Normal"/>
      <Setter Property="TextOptions.TextFormattingMode" Value="Display"/>
      <Setter Property="TextOptions.TextRenderingMode" Value="Grayscale"/>
      <Setter Property="RenderOptions.ClearTypeHint" Value="Auto"/>
    </Style>
    <Style x:Key="PageTitle" TargetType="TextBlock">
      <Setter Property="FontSize" Value="24"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
    </Style>
    <Style x:Key="SectionTitle" TargetType="TextBlock">
      <Setter Property="FontSize" Value="15"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
    </Style>
    <Style x:Key="FieldTitle" TargetType="TextBlock">
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
    </Style>
    <Style TargetType="TabItem">
      <Setter Property="Padding" Value="18,10"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="Foreground" Value="{DynamicResource TextSecondary}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TabItem">
            <Border x:Name="Bd" Background="Transparent" BorderThickness="0,0,0,2" BorderBrush="Transparent" Margin="0,0,8,0" Padding="{TemplateBinding Padding}">
              <ContentPresenter ContentSource="Header" HorizontalAlignment="Center"
                                TextElement.FontWeight="{TemplateBinding FontWeight}"
                                TextElement.Foreground="{TemplateBinding Foreground}"
                                TextElement.FontSize="{TemplateBinding FontSize}"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource Accent}"/>
                <Setter Property="Foreground" Value="{DynamicResource Accent}"/>
                <Setter Property="FontWeight" Value="Bold"/>
              </Trigger>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#180078D4"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Card" TargetType="Border">
      <Setter Property="Background" Value="{DynamicResource CardBg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource CardBorder}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="14"/>
      <Setter Property="Padding" Value="20"/>
      <Setter Property="Margin" Value="0,0,0,14"/>
      <Setter Property="SnapsToDevicePixels" Value="True"/>
      <Setter Property="UseLayoutRounding" Value="True"/>
      <Setter Property="Effect">
        <Setter.Value>
          <DropShadowEffect BlurRadius="12" ShadowDepth="0" Opacity="0.04" Color="#000000"/>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="SliderTrackBtn" TargetType="RepeatButton">
      <Setter Property="OverridesDefaultStyle" Value="True"/>
      <Setter Property="IsTabStop" Value="False"/>
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RepeatButton">
            <Border Background="Transparent" Height="10"/>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="SliderTrackFill" TargetType="RepeatButton">
      <Setter Property="OverridesDefaultStyle" Value="True"/>
      <Setter Property="IsTabStop" Value="False"/>
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RepeatButton">
            <Border Background="{DynamicResource Accent}" CornerRadius="5" Height="10"/>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="SliderThumb" TargetType="Thumb">
      <Setter Property="Width" Value="22"/>
      <Setter Property="Height" Value="22"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Thumb">
            <Grid Background="Transparent">
              <Ellipse Width="22" Height="22" Fill="#1A1A1A" Opacity="0.10" Margin="1,2,0,0" IsHitTestVisible="False"/>
              <Ellipse x:Name="Ring" Width="20" Height="20" Fill="{DynamicResource ThumbFill}" Stroke="{DynamicResource Accent}" StrokeThickness="3"
                       HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Ring" Property="StrokeThickness" Value="3.5"/>
              </Trigger>
              <Trigger Property="IsDragging" Value="True">
                <Setter TargetName="Ring" Property="StrokeThickness" Value="4"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="Slider">
      <Setter Property="Height" Value="40"/>
      <Setter Property="Margin" Value="0,8,0,4"/>
      <Setter Property="IsMoveToPointEnabled" Value="True"/>
      <Setter Property="IsSnapToTickEnabled" Value="False"/>
      <Setter Property="Focusable" Value="True"/>
      <Setter Property="OverridesDefaultStyle" Value="True"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Slider">
            <Grid VerticalAlignment="Center" Background="Transparent" MinHeight="32">
              <!-- 装饰轨道不参与命中，否则会挡住拖动 -->
              <Border Height="10" Background="{DynamicResource TrackBg}" CornerRadius="5"
                      VerticalAlignment="Center" Margin="11,0" IsHitTestVisible="False"/>
              <Track x:Name="PART_Track" VerticalAlignment="Center">
                <Track.DecreaseRepeatButton>
                  <RepeatButton Style="{StaticResource SliderTrackFill}" Command="Slider.DecreaseLarge"/>
                </Track.DecreaseRepeatButton>
                <Track.Thumb>
                  <Thumb Style="{StaticResource SliderThumb}"/>
                </Track.Thumb>
                <Track.IncreaseRepeatButton>
                  <RepeatButton Style="{StaticResource SliderTrackBtn}" Command="Slider.IncreaseLarge"/>
                </Track.IncreaseRepeatButton>
              </Track>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="PrimaryBtn" TargetType="Button">
      <Setter Property="Background" Value="{DynamicResource Accent}"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="16,8"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Background="{TemplateBinding Background}" CornerRadius="8" Padding="{TemplateBinding Padding}"
                    SnapsToDevicePixels="True" UseLayoutRounding="True">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"
                                TextOptions.TextFormattingMode="Display"
                                TextOptions.TextRenderingMode="ClearType"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="GhostBtn" TargetType="Button" BasedOn="{StaticResource PrimaryBtn}">
      <Setter Property="Background" Value="{DynamicResource GhostBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
    </Style>
    <Style TargetType="ComboBoxItem">
      <Setter Property="SnapsToDevicePixels" Value="True"/>
      <Setter Property="Padding" Value="10,8"/>
      <Setter Property="FontWeight" Value="Light"/>
      <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBoxItem">
            <Border x:Name="ItemBd" Background="{TemplateBinding Background}" CornerRadius="6" Padding="{TemplateBinding Padding}" Margin="2,1">
              <ContentPresenter VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsHighlighted" Value="True">
                <Setter TargetName="ItemBd" Property="Background" Value="{DynamicResource AccentSoft}"/>
              </Trigger>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="ItemBd" Property="Background" Value="{DynamicResource AccentSoft}"/>
                <Setter Property="Foreground" Value="{DynamicResource Accent}"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Foreground" Value="{DynamicResource TextMuted}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ComboBox">
      <Setter Property="Height" Value="36"/>
      <Setter Property="Padding" Value="10,6"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="FontWeight" Value="Light"/>
      <Setter Property="Background" Value="{DynamicResource InputBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource InputBorder}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="ScrollViewer.HorizontalScrollBarVisibility" Value="Auto"/>
      <Setter Property="ScrollViewer.VerticalScrollBarVisibility" Value="Auto"/>
      <Setter Property="OverridesDefaultStyle" Value="True"/>
      <Setter Property="SnapsToDevicePixels" Value="True"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBox">
            <Grid>
              <ToggleButton x:Name="ToggleButton" Focusable="False" ClickMode="Press"
                            IsChecked="{Binding Path=IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}">
                <ToggleButton.Template>
                  <ControlTemplate TargetType="ToggleButton">
                    <Border x:Name="Chrome" Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource InputBorder}"
                            BorderThickness="1" CornerRadius="8">
                      <Grid>
                        <Grid.ColumnDefinitions>
                          <ColumnDefinition Width="*"/>
                          <ColumnDefinition Width="30"/>
                        </Grid.ColumnDefinitions>
                        <Path Grid.Column="1" HorizontalAlignment="Center" VerticalAlignment="Center"
                              Data="M 0 0 L 4 4 L 8 0" Stroke="{DynamicResource TextSecondary}" StrokeThickness="1.5"/>
                      </Grid>
                    </Border>
                  </ControlTemplate>
                </ToggleButton.Template>
              </ToggleButton>
              <ContentPresenter Margin="12,0,34,0" IsHitTestVisible="False"
                                VerticalAlignment="Center" HorizontalAlignment="Left"
                                Content="{TemplateBinding SelectionBoxItem}"
                                ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
                                ContentTemplateSelector="{TemplateBinding ItemTemplateSelector}"
                                TextElement.Foreground="{DynamicResource TextPrimary}"/>
              <Popup x:Name="Popup" Placement="Bottom" AllowsTransparency="True" Focusable="False"
                     IsOpen="{TemplateBinding IsDropDownOpen}" PopupAnimation="Fade">
                <Border x:Name="DropDownBorder" Margin="0,4,0,0" Padding="4"
                        Background="{DynamicResource CardBg}" BorderBrush="{DynamicResource InputBorder}"
                        BorderThickness="1" CornerRadius="10"
                        MinWidth="{TemplateBinding ActualWidth}" MaxHeight="{TemplateBinding MaxDropDownHeight}">
                  <Border.Effect>
                    <DropShadowEffect BlurRadius="16" ShadowDepth="2" Opacity="0.28" Color="#000000"/>
                  </Border.Effect>
                  <ScrollViewer SnapsToDevicePixels="True">
                    <ItemsPresenter KeyboardNavigation.DirectionalNavigation="Contained"/>
                  </ScrollViewer>
                </Border>
              </Popup>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="TextBox">
      <Setter Property="Height" Value="36"/>
      <Setter Property="Padding" Value="10,6"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="FontWeight" Value="Light"/>
      <Setter Property="Background" Value="{DynamicResource InputBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource InputBorder}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CaretBrush" Value="{DynamicResource TextPrimary}"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
    </Style>
    <Style TargetType="RadioButton">
      <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
      <Setter Property="FontWeight" Value="Light"/>
    </Style>
    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
      <Setter Property="FontWeight" Value="Light"/>
    </Style>
  </Window.Resources>

  <Grid Margin="20">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- Header -->
    <Border Grid.Row="0" Style="{StaticResource Card}" Padding="20,16">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <StackPanel>
          <TextBlock x:Name="TxtPageTitle" Text="屏幕与字体调节" Style="{StaticResource PageTitle}"/>
          <TextBlock x:Name="TxtStatus" Text="当前：—" Margin="0,6,0,0" Foreground="{DynamicResource TextSecondary}"/>
        </StackPanel>
        <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
          <Border x:Name="BdLang" Background="{DynamicResource AccentSoft}" CornerRadius="20" Padding="12,7" Margin="0,0,12,0"
                  Cursor="Hand" BorderBrush="{DynamicResource CardBorder}" BorderThickness="1"
                  ToolTip="切换到 English">
            <StackPanel Orientation="Horizontal">
              <Grid Width="18" Height="16" Margin="0,0,6,0" VerticalAlignment="Center">
                <TextBlock Text="文" FontSize="10" FontWeight="Bold" Foreground="{DynamicResource Accent}"
                           HorizontalAlignment="Left" VerticalAlignment="Top" Margin="0,-1,0,0"/>
                <TextBlock Text="A" FontSize="10" FontWeight="Bold" Foreground="{DynamicResource Accent}"
                           HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,0,0,-1"/>
              </Grid>
              <TextBlock x:Name="TxtLangCode" Text="中" FontSize="13" FontWeight="Bold"
                         Foreground="{DynamicResource Accent}" VerticalAlignment="Center"/>
            </StackPanel>
          </Border>
          <StackPanel x:Name="BdRecBar" Orientation="Horizontal" VerticalAlignment="Center">
            <Border x:Name="BdRecApple" Background="{DynamicResource GhostBg}" CornerRadius="20" Padding="14,8" Margin="0,0,8,0" Cursor="Hand"
                    ToolTip="显示·苹果">
              <TextBlock x:Name="TxtRecApple" Text="苹果" Foreground="{DynamicResource TextSecondary}" FontWeight="SemiBold"/>
            </Border>
            <Border x:Name="BdRecLg" Background="{DynamicResource GhostBg}" CornerRadius="20" Padding="14,8" Margin="0,0,8,0" Cursor="Hand"
                    ToolTip="显示·LG">
              <TextBlock x:Name="TxtRecLg" Text="LG" Foreground="{DynamicResource TextSecondary}" FontWeight="SemiBold"/>
            </Border>
            <Border x:Name="BdRecHuawei" Background="{DynamicResource GhostBg}" CornerRadius="20" Padding="14,8" Margin="0,0,8,0" Cursor="Hand"
                    ToolTip="显示·华为">
              <TextBlock x:Name="TxtRecHuawei" Text="华为" Foreground="{DynamicResource TextSecondary}" FontWeight="SemiBold"/>
            </Border>
            <Border x:Name="BdRecAsus" Background="{DynamicResource GhostBg}" CornerRadius="20" Padding="14,8" Margin="0,0,8,0" Cursor="Hand"
                    ToolTip="显示·华硕">
              <TextBlock x:Name="TxtRecAsus" Text="华硕" Foreground="{DynamicResource TextSecondary}" FontWeight="SemiBold"/>
            </Border>
            <Border x:Name="BdRecSamsung" Background="{DynamicResource GhostBg}" CornerRadius="20" Padding="14,8" Margin="0,0,8,0" Cursor="Hand"
                    ToolTip="显示·三星">
              <TextBlock x:Name="TxtRecSamsung" Text="三星" Foreground="{DynamicResource TextSecondary}" FontWeight="SemiBold"/>
            </Border>
            <Border x:Name="BdRecGeneric" Background="{DynamicResource AccentSoft}" CornerRadius="20" Padding="14,8" Cursor="Hand"
                    ToolTip="显示·通用">
              <TextBlock x:Name="TxtRecGeneric" Text="通用显示" Foreground="{DynamicResource Accent}" FontWeight="SemiBold"/>
            </Border>
          </StackPanel>
        </StackPanel>
      </Grid>
    </Border>

    <TabControl x:Name="MainTabs" Grid.Row="1" Background="Transparent" BorderThickness="0" Padding="0" ClipToBounds="True">
      <!-- 显示 -->
      <TabItem x:Name="TabDisplay" Header="显示">
        <ScrollViewer VerticalScrollBarVisibility="Auto" Margin="0,12,0,0">
          <StackPanel>
            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="14"/>
                <ColumnDefinition Width="*"/>
              </Grid.ColumnDefinitions>
              <Border Grid.Column="0" Style="{StaticResource Card}">
                <StackPanel>
                  <TextBlock x:Name="TxtPowerTitle" Text="电源配置档" Style="{StaticResource SectionTitle}"/>
                  <TextBlock x:Name="TxtPowerDesc" Text="分别为「接电」和「电池」保存独立参数。仅编辑当前电源状态时会实时预览。" Foreground="{DynamicResource TextSecondary}" TextWrapping="Wrap" Margin="0,4,0,12"/>
                  <StackPanel Orientation="Horizontal">
                    <RadioButton x:Name="RbAc" GroupName="PowerMode" Content="接电状态" Margin="0,0,24,0" IsChecked="True"/>
                    <RadioButton x:Name="RbBat" GroupName="PowerMode" Content="电池状态"/>
                  </StackPanel>
                </StackPanel>
              </Border>
              <Border Grid.Column="2" Style="{StaticResource Card}">
                <StackPanel>
                  <TextBlock x:Name="TxtRecTarget" Text="默认平衡档" Style="{StaticResource SectionTitle}" TextWrapping="Wrap" Margin="0,0,0,10"/>
                  <TextBlock x:Name="TxtRecAcParams" Text="接电：—" Foreground="{DynamicResource TextSecondary}" TextWrapping="Wrap" Margin="0,0,0,4"/>
                  <TextBlock x:Name="TxtRecBatParams" Text="电池：—" Foreground="{DynamicResource Accent}" TextWrapping="Wrap" Margin="0,0,0,4"/>
                  <TextBlock x:Name="TxtRecFontParams" Text="字体档：—" Foreground="{DynamicResource TextMuted}" TextWrapping="Wrap" Margin="0,0,0,10"/>
                  <TextBlock x:Name="TxtRecNote" Text="显示与字体相互独立。" Foreground="{DynamicResource TextMuted}" TextWrapping="Wrap" FontSize="12"/>
                </StackPanel>
              </Border>
            </Grid>

            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock x:Name="TxtPresetTitle" Text="命名方案" Style="{StaticResource SectionTitle}"/>
                <TextBlock x:Name="TxtPresetDesc" Text="把当前「接电 + 电池」两套参数另存为方案，方便随时切换（例如：配置1、配置2）。" Foreground="{DynamicResource TextSecondary}" TextWrapping="Wrap" Margin="0,4,0,12"/>
                <Grid>
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="12"/>
                    <ColumnDefinition Width="*"/>
                  </Grid.ColumnDefinitions>
                  <StackPanel Grid.Column="0">
                    <TextBlock x:Name="TxtPresetExisting" Text="已有方案" Margin="0,0,0,6" Foreground="{DynamicResource TextSecondary}"/>
                    <ComboBox x:Name="CmbPreset" IsEditable="False"/>
                  </StackPanel>
                  <StackPanel Grid.Column="2">
                    <TextBlock x:Name="TxtPresetNameLabel" Text="方案名称" Margin="0,0,0,6" Foreground="{DynamicResource TextSecondary}"/>
                    <TextBox x:Name="TxtPresetName" Text="配置1"/>
                  </StackPanel>
                </Grid>
                <StackPanel Orientation="Horizontal" Margin="0,14,0,0">
                  <Button x:Name="BtnSavePreset" Style="{StaticResource PrimaryBtn}" Content="另存方案" Margin="0,0,10,0"/>
                  <Button x:Name="BtnLoadPreset" Style="{StaticResource GhostBtn}" Content="载入方案" Margin="0,0,10,0"/>
                  <Button x:Name="BtnDelPreset" Style="{StaticResource GhostBtn}" Content="删除方案"/>
                </StackPanel>
              </StackPanel>
            </Border>

            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="14"/>
                <ColumnDefinition Width="*"/>
              </Grid.ColumnDefinitions>
              <Border Grid.Column="0" Style="{StaticResource Card}">
                <StackPanel>
                  <Grid>
                    <TextBlock x:Name="TxtBrightLabel" Text="亮度" Style="{StaticResource FieldTitle}"/>
                    <TextBlock x:Name="TxtBright" Text="90" HorizontalAlignment="Right" Foreground="{DynamicResource Accent}" FontWeight="SemiBold"/>
                  </Grid>
                  <Slider x:Name="SlBright" Minimum="0" Maximum="100" Value="90"
                          SmallChange="1" LargeChange="5"/>
                </StackPanel>
              </Border>
              <Border Grid.Column="2" Style="{StaticResource Card}">
                <StackPanel>
                  <Grid>
                    <TextBlock x:Name="TxtContrastLabel" Text="对比度" Style="{StaticResource FieldTitle}"/>
                    <TextBlock x:Name="TxtContrast" Text="50" HorizontalAlignment="Right" Foreground="{DynamicResource Accent}" FontWeight="SemiBold"/>
                  </Grid>
                  <Slider x:Name="SlContrast" Minimum="0" Maximum="100" Value="50"
                          SmallChange="1" LargeChange="5"/>
                </StackPanel>
              </Border>
            </Grid>
            <TextBlock x:Name="TxtReadback" Text="硬件回读：—" Foreground="{DynamicResource TextMuted}" Margin="2,0,0,12" FontSize="12"/>

            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="14"/>
                <ColumnDefinition Width="*"/>
              </Grid.ColumnDefinitions>
              <Border Grid.Column="0" Style="{StaticResource Card}">
                <StackPanel>
                  <Grid>
                    <TextBlock x:Name="TxtGammaLabel" Text="伽马幂次" Style="{StaticResource FieldTitle}"/>
                    <TextBlock x:Name="TxtGamma" Text="1.00" HorizontalAlignment="Right" Foreground="{DynamicResource Accent}" FontWeight="SemiBold"/>
                  </Grid>
                  <TextBlock x:Name="TxtGammaHint" Text="大于 1 更暗，小于 1 更亮" Foreground="{DynamicResource TextSecondary}" FontSize="12" Margin="0,2,0,0"/>
                  <Slider x:Name="SlGamma" Minimum="0.70" Maximum="1.50" Value="1.0"
                          SmallChange="0.01" LargeChange="0.05"/>
                </StackPanel>
              </Border>
              <Border Grid.Column="2" Style="{StaticResource Card}">
                <StackPanel>
                  <Grid>
                    <TextBlock x:Name="TxtScaleLabel" Text="整体缩放" Style="{StaticResource FieldTitle}"/>
                    <TextBlock x:Name="TxtScale" Text="1.00" HorizontalAlignment="Right" Foreground="{DynamicResource Accent}" FontWeight="SemiBold"/>
                  </Grid>
                  <TextBlock x:Name="TxtScaleHint" Text="整体明暗倍率，可细调" Foreground="{DynamicResource TextSecondary}" FontSize="12" Margin="0,2,0,0"/>
                  <Slider x:Name="SlScale" Minimum="0.70" Maximum="1.10" Value="1.0"
                          SmallChange="0.01" LargeChange="0.05"/>
                </StackPanel>
              </Border>
            </Grid>

            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock x:Name="TxtAutoStartTitle" Text="开机自动应用" Style="{StaticResource SectionTitle}"/>
                <TextBlock x:Name="TxtAutoStartDesc" Text="登录 Windows 时自动写回亮度/对比度/软件伽马（系统会重置软件伽马，不是权限问题）。" Foreground="{DynamicResource TextSecondary}" TextWrapping="Wrap" Margin="0,4,0,10"/>
                <CheckBox x:Name="ChkAutoStart" Content="登录时自动应用当前显示配置" IsChecked="True"/>
              </StackPanel>
            </Border>

            <TextBlock x:Name="TxtColorCalibTitle" Text="颜色校准" Style="{StaticResource SectionTitle}" Margin="2,6,0,10"/>
            <Border Style="{StaticResource Card}" Padding="16,14">
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="Auto"/>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <!-- 校准图标：中心圆 + 放射小点，贴近系统设置样式 -->
                <Grid Width="36" Height="36" Margin="0,0,14,0" VerticalAlignment="Center">
                  <Ellipse Width="10" Height="10" Fill="{DynamicResource TextPrimary}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  <Ellipse Width="4" Height="4" Fill="{DynamicResource TextPrimary}" HorizontalAlignment="Center" VerticalAlignment="Top" Margin="0,2,0,0"/>
                  <Ellipse Width="4" Height="4" Fill="{DynamicResource TextPrimary}" HorizontalAlignment="Center" VerticalAlignment="Bottom" Margin="0,0,0,2"/>
                  <Ellipse Width="4" Height="4" Fill="{DynamicResource TextPrimary}" HorizontalAlignment="Left" VerticalAlignment="Center" Margin="2,0,0,0"/>
                  <Ellipse Width="4" Height="4" Fill="{DynamicResource TextPrimary}" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,2,0"/>
                  <Ellipse Width="3.5" Height="3.5" Fill="{DynamicResource TextPrimary}" HorizontalAlignment="Left" VerticalAlignment="Top" Margin="6,6,0,0"/>
                  <Ellipse Width="3.5" Height="3.5" Fill="{DynamicResource TextPrimary}" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,6,6,0"/>
                  <Ellipse Width="3.5" Height="3.5" Fill="{DynamicResource TextPrimary}" HorizontalAlignment="Left" VerticalAlignment="Bottom" Margin="6,0,0,6"/>
                  <Ellipse Width="3.5" Height="3.5" Fill="{DynamicResource TextPrimary}" HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,0,6,6"/>
                </Grid>
                <StackPanel Grid.Column="1" VerticalAlignment="Center">
                  <TextBlock x:Name="TxtColorCalibName" Text="显示颜色校准" FontSize="14" FontWeight="SemiBold" Foreground="{DynamicResource TextPrimary}"/>
                  <TextBlock x:Name="TxtColorCalibDesc" Text="校准显示颜色、亮度和对比度" FontSize="12" Foreground="{DynamicResource TextSecondary}" Margin="0,3,0,0" TextWrapping="Wrap"/>
                </StackPanel>
                <Button x:Name="BtnColorCalib" Grid.Column="2" Style="{StaticResource GhostBtn}" Content="校准显示器"
                        MinWidth="108" Margin="12,0,0,0" VerticalAlignment="Center" Padding="16,8"/>
              </Grid>
            </Border>
          </StackPanel>
        </ScrollViewer>
      </TabItem>

      <!-- 字体 -->
      <TabItem x:Name="TabFont" Header="字体">
        <ScrollViewer VerticalScrollBarVisibility="Auto" Margin="0,12,0,0">
          <StackPanel>
            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock x:Name="TxtFontRecSection" Text="当前字体档（用顶部胶囊切换）" Style="{StaticResource SectionTitle}"/>
                <TextBlock x:Name="TxtFontRecDesc" Text="顶部品牌胶囊在「字体」页只改 ClearType；在「显示」页只改屏幕。两套选择互不影响。" Foreground="{DynamicResource TextSecondary}" TextWrapping="Wrap" Margin="0,4,0,12"/>
                <TextBlock x:Name="TxtFontRecTitle" Text="字体档 · 通用显示" Foreground="{DynamicResource Accent}" FontWeight="SemiBold" Margin="0,0,0,4"/>
                <TextBlock x:Name="TxtFontRecTarget" Text="Windows 默认字体平滑" Foreground="{DynamicResource TextSecondary}" TextWrapping="Wrap" Margin="0,0,0,4"/>
                <TextBlock x:Name="TxtFontRecParams" Text="字体：—" Foreground="{DynamicResource TextSecondary}" TextWrapping="Wrap"/>
              </StackPanel>
            </Border>

            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock x:Name="TxtClearTypeTitle" Text="ClearType 字体平滑" Style="{StaticResource SectionTitle}"/>
                <TextBlock x:Name="TxtClearTypeDesc" Text="这是 Windows 系统级字体渲染。调整后部分程序需重新打开才完全生效。" TextWrapping="Wrap" Foreground="{DynamicResource TextSecondary}" Margin="0,4,0,12"/>
                <CheckBox x:Name="ChkClearType" Content="启用 ClearType" IsChecked="True" Margin="0,0,0,12"/>
                <Grid>
                  <TextBlock x:Name="TxtFontGammaLabel" Text="字体平滑伽马" Style="{StaticResource FieldTitle}"/>
                  <TextBlock x:Name="TxtFontGamma" Text="1.40" HorizontalAlignment="Right" Foreground="{DynamicResource Accent}" FontWeight="SemiBold"/>
                </Grid>
                <TextBlock x:Name="TxtFontGammaHint" Text="通常 1.0～2.2。数值越高，文字边缘对比越强。" Foreground="{DynamicResource TextSecondary}" FontSize="12"/>
                <Slider x:Name="SlFontGamma" Minimum="1.0" Maximum="2.2" Value="1.4"
                        SmallChange="0.05" LargeChange="0.1" IsMoveToPointEnabled="True" IsSnapToTickEnabled="False"/>
                <TextBlock x:Name="TxtSubpixelLabel" Text="子像素排列" Style="{StaticResource FieldTitle}" Margin="0,12,0,6"/>
                <StackPanel Orientation="Horizontal">
                  <RadioButton x:Name="RbRgb" Content="RGB（常见）" IsChecked="True" Margin="0,0,20,0"/>
                  <RadioButton x:Name="RbBgr" Content="BGR"/>
                </StackPanel>
                <StackPanel Orientation="Horizontal" Margin="0,16,0,0">
                  <Button x:Name="BtnApplyFont" Style="{StaticResource PrimaryBtn}" Content="应用字体设置" Margin="0,0,10,0"/>
                  <Button x:Name="BtnClearTypeWizard" Style="{StaticResource GhostBtn}" Content="打开系统 ClearType 向导"/>
                </StackPanel>
              </StackPanel>
            </Border>

            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock x:Name="TxtPreviewTitle" Text="预览" Style="{StaticResource SectionTitle}"/>
                <TextBlock x:Name="TxtPreviewDesc" Text="下面文字用于观察边缘是否舒服（宋体/雅黑混排）。" Foreground="{DynamicResource TextSecondary}" Margin="0,4,0,10"/>
                <Border Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource CardBorder}" BorderThickness="1" CornerRadius="12" Padding="16">
                  <StackPanel>
                    <TextBlock x:Name="TxtPreviewSample" FontSize="22" FontWeight="SemiBold" Text="屏幕与字体调节 ClearyDisplay"/>
                    <TextBlock FontSize="15" Margin="0,10,0,0" Text="The quick brown fox jumps over the lazy dog. 0123456789"/>
                    <TextBlock x:Name="TxtPreviewZh" FontSize="14" Margin="0,10,0,0" TextWrapping="Wrap" LineHeight="22"
                               Text="中文预览：清屏、亮度、对比度、伽马。字体渲染是否清晰细腻，一眼可辨。"/>
                  </StackPanel>
                </Border>
              </StackPanel>
            </Border>
          </StackPanel>
        </ScrollViewer>
      </TabItem>

      <!-- 主题 -->
      <TabItem x:Name="TabTheme" Header="主题">
        <ScrollViewer VerticalScrollBarVisibility="Auto" Margin="0,12,0,0">
          <StackPanel>
            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock x:Name="TxtThemeTitle" Text="外观主题" Style="{StaticResource SectionTitle}"/>
                <TextBlock x:Name="TxtThemeHint" Text="选择界面风格。" Foreground="{DynamicResource TextSecondary}" TextWrapping="Wrap" Margin="0,4,0,16"/>

                <Border x:Name="BdThemeLight" CornerRadius="14" BorderThickness="2" Padding="16" Margin="0,0,0,10" Cursor="Hand"
                        BorderBrush="{DynamicResource Accent}" Background="{DynamicResource AccentSoft}">
                  <Grid>
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="Auto"/>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <Border Width="40" Height="40" CornerRadius="20" Background="#F7F7F8" BorderBrush="#E6E6E8" BorderThickness="1" Margin="0,0,14,0">
                      <TextBlock x:Name="TxtThemeLightShort" Text="浅" FontSize="16" FontWeight="SemiBold" HorizontalAlignment="Center" VerticalAlignment="Center" Foreground="#0F0F0F"/>
                    </Border>
                    <StackPanel Grid.Column="1" VerticalAlignment="Center">
                      <TextBlock x:Name="TxtThemeLightName" Text="浅色" FontSize="15" FontWeight="SemiBold"/>
                      <TextBlock x:Name="TxtThemeLightDesc" Text="高对比清爽白底" Foreground="{DynamicResource TextSecondary}" Margin="0,2,0,0"/>
                    </StackPanel>
                    <TextBlock x:Name="TxtThemeLightMark" Grid.Column="2" Text="✓" FontSize="18" Foreground="{DynamicResource Accent}" VerticalAlignment="Center"/>
                  </Grid>
                </Border>

                <Border x:Name="BdThemeDark" CornerRadius="14" BorderThickness="1" Padding="16" Margin="0,0,0,10" Cursor="Hand"
                        BorderBrush="{DynamicResource CardBorder}" Background="{DynamicResource CardBg}">
                  <Grid>
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="Auto"/>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <Border Width="40" Height="40" CornerRadius="20" Background="#2C2C2E" BorderBrush="#3A3A3C" BorderThickness="1" Margin="0,0,14,0">
                      <TextBlock x:Name="TxtThemeDarkShort" Text="深" FontSize="16" FontWeight="SemiBold" HorizontalAlignment="Center" VerticalAlignment="Center" Foreground="#F2F2F7"/>
                    </Border>
                    <StackPanel Grid.Column="1" VerticalAlignment="Center">
                      <TextBlock x:Name="TxtThemeDarkName" Text="深色" FontSize="15" FontWeight="SemiBold"/>
                      <TextBlock x:Name="TxtThemeDarkDesc" Text="深色界面，夜间更护眼" Foreground="{DynamicResource TextSecondary}" Margin="0,2,0,0"/>
                    </StackPanel>
                    <TextBlock x:Name="TxtThemeDarkMark" Grid.Column="2" Text="" FontSize="18" Foreground="{DynamicResource Accent}" VerticalAlignment="Center"/>
                  </Grid>
                </Border>

                <Border x:Name="BdThemeGithub" CornerRadius="8" BorderThickness="1" Padding="16" Margin="0,0,0,10" Cursor="Hand"
                        BorderBrush="{DynamicResource CardBorder}" Background="{DynamicResource CardBg}">
                  <Grid>
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="Auto"/>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <Border Width="44" Height="44" CornerRadius="8" BorderBrush="#D0D7DE" BorderThickness="1" Margin="0,0,14,0" ClipToBounds="True">
                      <Grid>
                        <Grid.RowDefinitions>
                          <RowDefinition Height="*"/>
                          <RowDefinition Height="*"/>
                        </Grid.RowDefinitions>
                        <Grid.ColumnDefinitions>
                          <ColumnDefinition Width="*"/>
                          <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Border Grid.Row="0" Grid.ColumnSpan="2" Background="#F6F8FA"/>
                        <Border Grid.Row="1" Grid.Column="0" Background="#0969DA"/>
                        <Border Grid.Row="1" Grid.Column="1" Background="#1A7F37"/>
                      </Grid>
                    </Border>
                    <StackPanel Grid.Column="1" VerticalAlignment="Center">
                      <TextBlock x:Name="TxtThemeGithubName" Text="GITHUB" FontSize="15" FontWeight="SemiBold"/>
                      <TextBlock x:Name="TxtThemeGithubDesc" Text="GitHub 风：灰白底 + 蓝字 + 绿滑条" Foreground="{DynamicResource TextSecondary}" Margin="0,2,0,0" TextWrapping="Wrap"/>
                    </StackPanel>
                    <TextBlock x:Name="TxtThemeGithubMark" Grid.Column="2" Text="" FontSize="18" Foreground="{DynamicResource Accent}" VerticalAlignment="Center"/>
                  </Grid>
                </Border>

                <Border x:Name="BdThemeApple" CornerRadius="18" BorderThickness="1" Padding="16" Margin="0,0,0,10" Cursor="Hand"
                        BorderBrush="{DynamicResource CardBorder}" Background="{DynamicResource CardBg}">
                  <Grid>
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="Auto"/>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <Border Width="44" Height="44" CornerRadius="22" BorderBrush="#C7C7CC" BorderThickness="1.5" Margin="0,0,14,0" ClipToBounds="True" Background="#FFFFFF">
                      <Grid>
                        <Grid.RowDefinitions>
                          <RowDefinition Height="*"/>
                          <RowDefinition Height="*"/>
                        </Grid.RowDefinitions>
                        <Border Grid.Row="0" Background="#F5F5F7"/>
                        <Border Grid.Row="1" Background="#0071E3"/>
                      </Grid>
                    </Border>
                    <StackPanel Grid.Column="1" VerticalAlignment="Center">
                      <TextBlock x:Name="TxtThemeAppleName" Text="苹果风格" FontSize="15" FontWeight="SemiBold"/>
                      <TextBlock x:Name="TxtThemeAppleDesc" Text="Apple 风：浅灰底 + 圆角描边胶囊" Foreground="{DynamicResource TextSecondary}" Margin="0,2,0,0" TextWrapping="Wrap"/>
                    </StackPanel>
                    <TextBlock x:Name="TxtThemeAppleMark" Grid.Column="2" Text="" FontSize="18" Foreground="{DynamicResource Accent}" VerticalAlignment="Center"/>
                  </Grid>
                </Border>

                <Border x:Name="BdThemeDsa" CornerRadius="20" BorderThickness="1" Padding="16" Margin="0,0,0,10" Cursor="Hand"
                        BorderBrush="{DynamicResource CardBorder}" Background="{DynamicResource CardBg}">
                  <Grid>
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="Auto"/>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <Border Width="44" Height="44" CornerRadius="14" BorderBrush="#C8DBEF" BorderThickness="1" Margin="0,0,14,0" ClipToBounds="True">
                      <Grid>
                        <Grid.RowDefinitions>
                          <RowDefinition Height="*"/>
                          <RowDefinition Height="*"/>
                        </Grid.RowDefinitions>
                        <Grid.ColumnDefinitions>
                          <ColumnDefinition Width="*"/>
                          <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Border Grid.Row="0" Grid.ColumnSpan="2" Background="#EAF2FA"/>
                        <Border Grid.Row="1" Grid.Column="0" Background="#6B9FD4"/>
                        <Border Grid.Row="1" Grid.Column="1" Background="#5CBF9A"/>
                      </Grid>
                    </Border>
                    <StackPanel Grid.Column="1" VerticalAlignment="Center">
                      <TextBlock x:Name="TxtThemeDsaName" Text="DSA" FontSize="15" FontWeight="SemiBold"/>
                      <TextBlock x:Name="TxtThemeDsaDesc" Text="DSA 风：浅蓝底、粉彩蓝字、薄荷绿辅色" Foreground="{DynamicResource TextSecondary}" Margin="0,2,0,0" TextWrapping="Wrap"/>
                    </StackPanel>
                    <TextBlock x:Name="TxtThemeDsaMark" Grid.Column="2" Text="" FontSize="18" Foreground="{DynamicResource Accent}" VerticalAlignment="Center"/>
                  </Grid>
                </Border>

                <Border x:Name="BdThemeChrome" CornerRadius="20" BorderThickness="1" Padding="16" Margin="0,0,0,10" Cursor="Hand"
                        BorderBrush="{DynamicResource CardBorder}" Background="{DynamicResource CardBg}">
                  <Grid>
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="Auto"/>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <Border Width="44" Height="44" CornerRadius="10" BorderBrush="#DADCE0" BorderThickness="1" Margin="0,0,14,0" ClipToBounds="True">
                      <Grid>
                        <Grid.RowDefinitions>
                          <RowDefinition Height="*"/>
                          <RowDefinition Height="*"/>
                        </Grid.RowDefinitions>
                        <Grid.ColumnDefinitions>
                          <ColumnDefinition Width="*"/>
                          <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Border Grid.Row="0" Grid.ColumnSpan="2" Background="#FFFFFF"/>
                        <Border Grid.Row="1" Grid.Column="0" Background="#1A73E8"/>
                        <Border Grid.Row="1" Grid.Column="1" Background="#EA4335"/>
                      </Grid>
                    </Border>
                    <StackPanel Grid.Column="1" VerticalAlignment="Center">
                      <TextBlock x:Name="TxtThemeChromeName" Text="Chrome" FontSize="15" FontWeight="SemiBold"/>
                      <TextBlock x:Name="TxtThemeChromeDesc" Text="Chrome 风：白 / 蓝 / 红" Foreground="{DynamicResource TextSecondary}" Margin="0,2,0,0" TextWrapping="Wrap"/>
                    </StackPanel>
                    <TextBlock x:Name="TxtThemeChromeMark" Grid.Column="2" Text="" FontSize="18" Foreground="{DynamicResource Accent}" VerticalAlignment="Center"/>
                  </Grid>
                </Border>

                <Border x:Name="BdThemeSystem" CornerRadius="14" BorderThickness="1" Padding="16" Cursor="Hand"
                        BorderBrush="{DynamicResource CardBorder}" Background="{DynamicResource CardBg}">
                  <Grid>
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="Auto"/>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <Border Width="40" Height="40" CornerRadius="20" Background="#EEF3FF" BorderBrush="#2B6DEF" BorderThickness="1" Margin="0,0,14,0">
                      <TextBlock x:Name="TxtThemeSysShort" Text="自" FontSize="16" FontWeight="SemiBold" HorizontalAlignment="Center" VerticalAlignment="Center" Foreground="{DynamicResource Accent}"/>
                    </Border>
                    <StackPanel Grid.Column="1" VerticalAlignment="Center">
                      <TextBlock x:Name="TxtThemeSysName" Text="跟随系统" FontSize="15" FontWeight="SemiBold"/>
                      <TextBlock x:Name="TxtThemeSysDesc" Text="自动跟随 Windows「深色 / 浅色」模式" Foreground="{DynamicResource TextSecondary}" Margin="0,2,0,0"/>
                    </StackPanel>
                    <TextBlock x:Name="TxtThemeSystemMark" Grid.Column="2" Text="" FontSize="18" Foreground="{DynamicResource Accent}" VerticalAlignment="Center"/>
                  </Grid>
                </Border>
              </StackPanel>
            </Border>
          </StackPanel>
        </ScrollViewer>
      </TabItem>
    </TabControl>

    <Border Grid.Row="2" Margin="0,8,0,0" Padding="4,10,4,0" Panel.ZIndex="10">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <TextBlock x:Name="TxtFooterHint" Grid.Column="0" VerticalAlignment="Center"
                   Foreground="{DynamicResource TextMuted}" FontSize="12" TextWrapping="NoWrap"
                   TextTrimming="CharacterEllipsis" Margin="0,0,16,0" IsHitTestVisible="False"
                   Text="左右并排调节 · 拖动滑块实时预览 ·「立即应用」写入配置"/>
        <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center" Panel.ZIndex="20">
          <Button x:Name="BtnReset" Style="{StaticResource GhostBtn}" Content="重置本档" Margin="0,0,8,0" MinWidth="96"/>
          <Button x:Name="BtnApply" Style="{StaticResource GhostBtn}" Content="立即应用" Margin="0,0,8,0" MinWidth="96"/>
          <Button x:Name="BtnSaveClose" Style="{StaticResource PrimaryBtn}" Content="保存并关闭" MinWidth="110"/>
        </StackPanel>
      </Grid>
    </Border>
  </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)
if (-not $window) { throw 'XAML 加载失败，窗口为空' }

# 强制本窗 ClearType + 像素对齐（避免 Ideal 模式发糊）
try {
  [System.Windows.Media.TextOptions]::SetTextFormattingMode($window, [System.Windows.Media.TextFormattingMode]::Display)
  [System.Windows.Media.TextOptions]::SetTextRenderingMode($window, [System.Windows.Media.TextRenderingMode]::Grayscale)
  [System.Windows.Media.TextOptions]::SetTextHintingMode($window, [System.Windows.Media.TextHintingMode]::Fixed)
  [System.Windows.Media.RenderOptions]::SetClearTypeHint($window, [System.Windows.Media.ClearTypeHint]::Auto)
  $window.UseLayoutRounding = $true
  $window.SnapsToDevicePixels = $true
} catch {}

# 窗口标题栏 / 任务栏图标（优先安装目录，其次配置目录）
try {
  $iconPath = $null
  foreach ($cand in @(
    (Join-Path $script:appDir 'ClearyDisplay.ico'),
    (Join-Path $baseDir 'ClearyDisplay.ico')
  )) {
    if ($cand -and (Test-Path $cand)) { $iconPath = $cand; break }
  }
  if ($iconPath) {
    $window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create(
      [Uri]::new($iconPath),
      [System.Windows.Media.Imaging.BitmapCreateOptions]::None,
      [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
  }
} catch {}

# 诊断：关键控件是否绑定成功
$missing = @()
foreach ($n in @('TxtStatus','SlBright','BtnApply','BdThemeLight','CmbPreset')) {
  if (-not $window.FindName($n)) { $missing += $n }
}
if ($missing.Count -gt 0) {
  [System.Windows.MessageBox]::Show(((T 'bindWarn') + ($missing -join ', ') + (T 'bindWarn2')), (T 'appTitle'))
}

# Bind controls
$TxtPageTitle = $window.FindName('TxtPageTitle')
$TxtStatus = $window.FindName('TxtStatus')
$BdLang = $window.FindName('BdLang')
$TxtLangCode = $window.FindName('TxtLangCode')
$TabDisplay = $window.FindName('TabDisplay')
$TabFont = $window.FindName('TabFont')
$TabTheme = $window.FindName('TabTheme')
$TxtPowerTitle = $window.FindName('TxtPowerTitle')
$TxtPowerDesc = $window.FindName('TxtPowerDesc')
$RbAc = $window.FindName('RbAc')
$RbBat = $window.FindName('RbBat')
$TxtPresetTitle = $window.FindName('TxtPresetTitle')
$TxtPresetDesc = $window.FindName('TxtPresetDesc')
$TxtPresetExisting = $window.FindName('TxtPresetExisting')
$TxtPresetNameLabel = $window.FindName('TxtPresetNameLabel')
$TxtBrightLabel = $window.FindName('TxtBrightLabel')
$TxtContrastLabel = $window.FindName('TxtContrastLabel')
$TxtGammaLabel = $window.FindName('TxtGammaLabel')
$TxtGammaHint = $window.FindName('TxtGammaHint')
$TxtScaleLabel = $window.FindName('TxtScaleLabel')
$TxtScaleHint = $window.FindName('TxtScaleHint')
$TxtClearTypeTitle = $window.FindName('TxtClearTypeTitle')
$TxtClearTypeDesc = $window.FindName('TxtClearTypeDesc')
$TxtFontGammaLabel = $window.FindName('TxtFontGammaLabel')
$TxtFontGammaHint = $window.FindName('TxtFontGammaHint')
$TxtSubpixelLabel = $window.FindName('TxtSubpixelLabel')
$TxtPreviewTitle = $window.FindName('TxtPreviewTitle')
$TxtPreviewDesc = $window.FindName('TxtPreviewDesc')
$TxtPreviewSample = $window.FindName('TxtPreviewSample')
$TxtPreviewZh = $window.FindName('TxtPreviewZh')
$TxtThemeTitle = $window.FindName('TxtThemeTitle')
$TxtThemeLightShort = $window.FindName('TxtThemeLightShort')
$TxtThemeLightName = $window.FindName('TxtThemeLightName')
$TxtThemeLightDesc = $window.FindName('TxtThemeLightDesc')
$TxtThemeDarkShort = $window.FindName('TxtThemeDarkShort')
$TxtThemeDarkName = $window.FindName('TxtThemeDarkName')
$TxtThemeDarkDesc = $window.FindName('TxtThemeDarkDesc')
$TxtThemeSysShort = $window.FindName('TxtThemeSysShort')
$TxtThemeSysName = $window.FindName('TxtThemeSysName')
$TxtThemeSysDesc = $window.FindName('TxtThemeSysDesc')
$TxtFooterHint = $window.FindName('TxtFooterHint')
$SlBright = $window.FindName('SlBright')
$SlContrast = $window.FindName('SlContrast')
$SlGamma = $window.FindName('SlGamma')
$SlScale = $window.FindName('SlScale')
$TxtBright = $window.FindName('TxtBright')
$TxtContrast = $window.FindName('TxtContrast')
$TxtGamma = $window.FindName('TxtGamma')
$TxtScale = $window.FindName('TxtScale')
$TxtReadback = $window.FindName('TxtReadback')
$ChkClearType = $window.FindName('ChkClearType')
$ChkAutoStart = $window.FindName('ChkAutoStart')
$TxtAutoStartTitle = $window.FindName('TxtAutoStartTitle')
$TxtAutoStartDesc = $window.FindName('TxtAutoStartDesc')
$TxtColorCalibTitle = $window.FindName('TxtColorCalibTitle')
$TxtColorCalibName = $window.FindName('TxtColorCalibName')
$TxtColorCalibDesc = $window.FindName('TxtColorCalibDesc')
$BtnColorCalib = $window.FindName('BtnColorCalib')
$SlFontGamma = $window.FindName('SlFontGamma')
$TxtFontGamma = $window.FindName('TxtFontGamma')
$RbRgb = $window.FindName('RbRgb')
$RbBgr = $window.FindName('RbBgr')
$BtnApplyFont = $window.FindName('BtnApplyFont')
$BtnClearTypeWizard = $window.FindName('BtnClearTypeWizard')
$CmbPreset = $window.FindName('CmbPreset')
$TxtPresetName = $window.FindName('TxtPresetName')
$BtnSavePreset = $window.FindName('BtnSavePreset')
$BtnLoadPreset = $window.FindName('BtnLoadPreset')
$BtnDelPreset = $window.FindName('BtnDelPreset')
$BtnReset = $window.FindName('BtnReset')
$BtnApply = $window.FindName('BtnApply')
$BtnSaveClose = $window.FindName('BtnSaveClose')
$BdRecApple = $window.FindName('BdRecApple')
$BdRecLg = $window.FindName('BdRecLg')
$BdRecHuawei = $window.FindName('BdRecHuawei')
$BdRecAsus = $window.FindName('BdRecAsus')
$BdRecSamsung = $window.FindName('BdRecSamsung')
$BdRecGeneric = $window.FindName('BdRecGeneric')
$TxtRecApple = $window.FindName('TxtRecApple')
$TxtRecLg = $window.FindName('TxtRecLg')
$TxtRecHuawei = $window.FindName('TxtRecHuawei')
$TxtRecAsus = $window.FindName('TxtRecAsus')
$TxtRecSamsung = $window.FindName('TxtRecSamsung')
$TxtRecGeneric = $window.FindName('TxtRecGeneric')
$TxtRecTitle = $null
$TxtRecTarget = $window.FindName('TxtRecTarget')
$TxtRecAcParams = $window.FindName('TxtRecAcParams')
$TxtRecBatParams = $window.FindName('TxtRecBatParams')
$TxtRecFontParams = $window.FindName('TxtRecFontParams')
$TxtRecNote = $window.FindName('TxtRecNote')
$TxtFontRecSection = $window.FindName('TxtFontRecSection')
$TxtFontRecDesc = $window.FindName('TxtFontRecDesc')
$TxtFontRecTitle = $window.FindName('TxtFontRecTitle')
$TxtFontRecTarget = $window.FindName('TxtFontRecTarget')
$TxtFontRecParams = $window.FindName('TxtFontRecParams')
$BdRecBar = $window.FindName('BdRecBar')
$MainTabs = $window.FindName('MainTabs')
$BdThemeLight = $window.FindName('BdThemeLight')
$BdThemeDark = $window.FindName('BdThemeDark')
$BdThemeGithub = $window.FindName('BdThemeGithub')
$BdThemeApple = $window.FindName('BdThemeApple')
$BdThemeDsa = $window.FindName('BdThemeDsa')
$BdThemeChrome = $window.FindName('BdThemeChrome')
$BdThemeSystem = $window.FindName('BdThemeSystem')
$TxtThemeAppleMark = $window.FindName('TxtThemeAppleMark')
$TxtThemeDsaMark = $window.FindName('TxtThemeDsaMark')
$TxtThemeDsaName = $window.FindName('TxtThemeDsaName')
$TxtThemeDsaDesc = $window.FindName('TxtThemeDsaDesc')
$TxtThemeChromeMark = $window.FindName('TxtThemeChromeMark')
$TxtThemeHint = $window.FindName('TxtThemeHint')
$TxtThemeTitle = $window.FindName('TxtThemeTitle')
$TxtThemeLightShort = $window.FindName('TxtThemeLightShort')
$TxtThemeLightName = $window.FindName('TxtThemeLightName')
$TxtThemeLightDesc = $window.FindName('TxtThemeLightDesc')
$TxtThemeDarkShort = $window.FindName('TxtThemeDarkShort')
$TxtThemeDarkName = $window.FindName('TxtThemeDarkName')
$TxtThemeDarkDesc = $window.FindName('TxtThemeDarkDesc')
$TxtThemeGithubShort = $window.FindName('TxtThemeGithubShort')
$TxtThemeGithubName = $window.FindName('TxtThemeGithubName')
$TxtThemeGithubDesc = $window.FindName('TxtThemeGithubDesc')
$TxtThemeAppleShort = $window.FindName('TxtThemeAppleShort')
$TxtThemeAppleName = $window.FindName('TxtThemeAppleName')
$TxtThemeAppleDesc = $window.FindName('TxtThemeAppleDesc')
$TxtThemeChromeShort = $window.FindName('TxtThemeChromeShort')
$TxtThemeChromeName = $window.FindName('TxtThemeChromeName')
$TxtThemeChromeDesc = $window.FindName('TxtThemeChromeDesc')
$TxtThemeSysShort = $window.FindName('TxtThemeSysShort')
$TxtThemeSysName = $window.FindName('TxtThemeSysName')
$TxtThemeSysDesc = $window.FindName('TxtThemeSysDesc')
$TxtThemeLightMark = $window.FindName('TxtThemeLightMark')
$TxtThemeDarkMark = $window.FindName('TxtThemeDarkMark')
$TxtThemeGithubMark = $window.FindName('TxtThemeGithubMark')
$TxtThemeAppleMark = $window.FindName('TxtThemeAppleMark')
$TxtThemeChromeMark = $window.FindName('TxtThemeChromeMark')
$TxtThemeSystemMark = $window.FindName('TxtThemeSystemMark')

$script:timer = New-Object System.Windows.Threading.DispatcherTimer
$script:timer.Interval = [TimeSpan]::FromMilliseconds(180)
$script:themeWatch = New-Object System.Windows.Threading.DispatcherTimer
$script:themeWatch.Interval = [TimeSpan]::FromSeconds(2)
$script:lastSystemLight = $null
$script:lastOnAc = $null

function Update-PowerStatus {
  $onAc = [bool](Get-IsOnAc)
  if ($TxtStatus) {
    if ($onAc) { $TxtStatus.Text = (T 'statusAc') }
    else { $TxtStatus.Text = (T 'statusBat') }
  }
  Update-RecommendPowerHighlight

  # 顶部状态与「电源配置档」单选同步；只改界面滑条，绝不在这里写屏
  # （写屏会在插电时把亮度瞬间拉高，且 DDC 堵在 UI 线程会导致窗口假死）
  $radioAc = ($RbAc -and [bool]$RbAc.IsChecked)
  $mismatch = ($radioAc -ne $onAc)
  $changed = ($null -eq $script:lastOnAc) -or ($script:lastOnAc -ne $onAc)
  if ($mismatch -or $changed) {
    $hadPrior = ($null -ne $script:lastOnAc)
    if ($mismatch -and -not $script:loading) {
      try { Persist-Sliders } catch {}
    }
    Sync-PowerRadioToActual
    if (-not $script:loading) {
      if ($onAc) {
        if ($profiles.ac) { Set-SlidersFromProfile $profiles.ac }
      } else {
        if ($profiles.battery) { Set-SlidersFromProfile $profiles.battery }
      }
      if ($hadPrior -and $changed -and $TxtReadback) {
        $TxtReadback.Text = $(if ($onAc) { T 'powerSwitchedAc' } else { T 'powerSwitchedBat' })
      }
    }
  }
  $script:lastOnAc = $onAc
}

function Is-EditingActive {
  # 始终允许预览：接电/电池只是「正在编辑哪套参数」，不要挡住实际写屏
  return $true
}

function Get-EditingProfile {
  if ($RbAc -and $RbAc.IsChecked) { return $profiles.ac }
  return $profiles.battery
}

function Sync-PowerRadioToActual {
  $onAc = Get-IsOnAc
  $prev = $script:loading
  $script:loading = $true
  try {
    if ($onAc) {
      if ($RbAc) { $RbAc.IsChecked = $true }
    } else {
      if ($RbBat) { $RbBat.IsChecked = $true }
    }
  } finally {
    $script:loading = $prev
  }
}

function Set-SlidersFromProfile($p) {
  if (-not $p) { return }
  $prev = $script:loading
  $script:loading = $true
  try {
    if ($SlBright) { $SlBright.Value = [double]$p.brightness }
    if ($SlContrast) { $SlContrast.Value = [double]$p.contrast }
    if ($SlGamma) { $SlGamma.Value = [double]$p.gammaPower }
    if ($SlScale) { $SlScale.Value = [double]$p.scale }
  } finally {
    $script:loading = $prev
  }
  Update-ValueLabels
}

function Update-ValueLabels {
  if ($TxtBright -and $SlBright) { $TxtBright.Text = ('{0:N0}' -f $SlBright.Value) }
  if ($TxtContrast -and $SlContrast) { $TxtContrast.Text = ('{0:N0}' -f $SlContrast.Value) }
  if ($TxtGamma -and $SlGamma) { $TxtGamma.Text = ('{0:N2}' -f $SlGamma.Value) }
  if ($TxtScale -and $SlScale) { $TxtScale.Text = ('{0:N2}' -f $SlScale.Value) }
  if ($TxtFontGamma -and $SlFontGamma) { $TxtFontGamma.Text = ('{0:N2}' -f $SlFontGamma.Value) }
}

function Persist-Sliders {
  $t = Get-EditingProfile
  if (-not $t) { return }
  if ($SlBright) { $t.brightness = [int][Math]::Round($SlBright.Value) }
  if ($SlContrast) { $t.contrast = [int][Math]::Round($SlContrast.Value) }
  if ($SlGamma) { $t.gammaPower = [double]$SlGamma.Value }
  if ($SlScale) { $t.scale = [double]$SlScale.Value }
}

function Apply-DisplayValues($b,$c,$g,$s) {
  Apply-Gamma $g $s
  $rb = Apply-Brightness ([int]$b)
  $rc = Apply-Contrast ([int]$c)
  if ($TxtReadback) {
    $TxtReadback.Text = (TF 'readbackFmt' $rb $rc)
  }
  return @{ Brightness=$rb; Contrast=$rc }
}

function Flash-Status([string]$msg) {
  if (-not $TxtStatus) { return }
  $TxtStatus.Text = $msg
  if (-not $script:statusRestore) {
    $script:statusRestore = New-Object System.Windows.Threading.DispatcherTimer
    $script:statusRestore.Interval = [TimeSpan]::FromSeconds(2.2)
    $script:statusRestore.Add_Tick({
      $script:statusRestore.Stop()
      Update-PowerStatus
    })
  }
  $script:statusRestore.Stop()
  $script:statusRestore.Start()
}

function Apply-If-Active {
  try {
    if ($SlGamma -and $SlScale) {
      Apply-Gamma ([double]$SlGamma.Value) ([double]$SlScale.Value)
    }
    $rb = -1; $rc = -1
    if ($SlBright) { $rb = Apply-Brightness ([int][Math]::Round($SlBright.Value)) }
    if ($SlContrast) { $rc = Apply-Contrast ([int][Math]::Round($SlContrast.Value)) }
    if ($TxtReadback) {
      $TxtReadback.Text = (TF 'livePreviewFmt' $rb $rc)
    }
  } catch {
    if ($TxtReadback) { $TxtReadback.Text = (T 'previewFail') }
  }
}

function On-SliderChanged {
  if ($script:loading) { return }
  Persist-Sliders
  Update-ValueLabels
  if ($script:timer) {
    $script:timer.Stop()
    $script:timer.Start()
  }
}

$script:timer.Add_Tick({
  $script:timer.Stop()
  Apply-If-Active
})

function Refresh-PresetCombo([string]$sel) {
  if (-not $CmbPreset) { return }
  $CmbPreset.Items.Clear()
  foreach ($k in @($presets.Keys | Sort-Object)) { [void]$CmbPreset.Items.Add([string]$k) }
  if ($sel -and $CmbPreset.Items.Contains($sel)) {
    $CmbPreset.SelectedItem = $sel
    if ($TxtPresetName) { $TxtPresetName.Text = $sel }
  }
  elseif ($CmbPreset.Items.Count -gt 0) {
    $CmbPreset.SelectedIndex = 0
    if ($TxtPresetName) { $TxtPresetName.Text = [string]$CmbPreset.SelectedItem }
  }
}

function Get-SelectedPresetName {
  if ($CmbPreset -and $null -ne $CmbPreset.SelectedItem -and "$($CmbPreset.SelectedItem)".Trim()) {
    return [string]$CmbPreset.SelectedItem
  }
  if ($TxtPresetName) {
    $t = $TxtPresetName.Text.Trim()
    if ($t) { return $t }
  }
  return ''
}

# Init font controls
$fg = Get-FontGamma
if ($SlFontGamma) { $SlFontGamma.Value = $fg }
$ori = 1
try { $ori = [int](Get-ItemProperty 'HKCU:\Control Panel\Desktop').FontSmoothingOrientation } catch {}
if ($ori -eq 0) { if ($RbBgr) { $RbBgr.IsChecked = $true } }
elseif ($RbRgb) { $RbRgb.IsChecked = $true }
$fs = '2'
try { $fs = [string](Get-ItemProperty 'HKCU:\Control Panel\Desktop').FontSmoothing } catch {}
if ($ChkClearType) { $ChkClearType.IsChecked = ($fs -eq '2') }
if ($ChkAutoStart) {
  $chk = if ($null -ne $script:uiSettings.autoStart) { [bool]$script:uiSettings.autoStart } else { $true }
  # 与注册表实际状态对齐
  if (Get-StartupApplyEnabled) { $chk = $true }
  $ChkAutoStart.IsChecked = $chk
  $ChkAutoStart.Add_Checked({
    if ($script:loading) { return }
    $script:uiSettings.autoStart = $true
    Set-StartupApply $true
    Save-UiSettings $script:uiSettings
    Flash-Status (T 'autoStartOn')
  })
  $ChkAutoStart.Add_Unchecked({
    if ($script:loading) { return }
    $script:uiSettings.autoStart = $false
    Set-StartupApply $false
    Save-UiSettings $script:uiSettings
    Flash-Status (T 'autoStartOff')
  })
}

# Events — 全部加空值保护，避免 FindName 失败导致启动中断
if ($SlBright) { $SlBright.Add_ValueChanged({ On-SliderChanged }) }
if ($SlContrast) { $SlContrast.Add_ValueChanged({ On-SliderChanged }) }
if ($SlGamma) { $SlGamma.Add_ValueChanged({ On-SliderChanged }) }
if ($SlScale) { $SlScale.Add_ValueChanged({ On-SliderChanged }) }
if ($SlFontGamma) { $SlFontGamma.Add_ValueChanged({ if (-not $script:loading -and $TxtFontGamma) { $TxtFontGamma.Text = ('{0:N2}' -f $SlFontGamma.Value) } }) }

if ($CmbPreset) {
  $CmbPreset.Add_SelectionChanged({
    if ($null -ne $CmbPreset.SelectedItem -and $TxtPresetName) {
      $TxtPresetName.Text = [string]$CmbPreset.SelectedItem
    }
  })
}

if ($BdThemeLight) { $BdThemeLight.Add_MouseLeftButtonUp({ Apply-UiTheme 'light' }) }
if ($BdThemeDark) { $BdThemeDark.Add_MouseLeftButtonUp({ Apply-UiTheme 'dark' }) }
if ($BdThemeGithub) { $BdThemeGithub.Add_MouseLeftButtonUp({ Apply-UiTheme 'github' }) }
if ($BdThemeApple) { $BdThemeApple.Add_MouseLeftButtonUp({ Apply-UiTheme 'apple' }) }
if ($BdThemeDsa) { $BdThemeDsa.Add_MouseLeftButtonUp({ Apply-UiTheme 'dsa' }) }
if ($BdThemeChrome) { $BdThemeChrome.Add_MouseLeftButtonUp({ Apply-UiTheme 'chrome' }) }
if ($BdThemeSystem) { $BdThemeSystem.Add_MouseLeftButtonUp({ Apply-UiTheme 'system' }) }

if ($BdLang) { $BdLang.Add_MouseLeftButtonUp({ Toggle-UiLanguage }) }
if ($BdRecApple) { $BdRecApple.Add_MouseLeftButtonUp({ Apply-HeaderRecommend 'apple' }) }
if ($BdRecLg) { $BdRecLg.Add_MouseLeftButtonUp({ Apply-HeaderRecommend 'lg' }) }
if ($BdRecHuawei) { $BdRecHuawei.Add_MouseLeftButtonUp({ Apply-HeaderRecommend 'huawei' }) }
if ($BdRecAsus) { $BdRecAsus.Add_MouseLeftButtonUp({ Apply-HeaderRecommend 'asus' }) }
if ($BdRecSamsung) { $BdRecSamsung.Add_MouseLeftButtonUp({ Apply-HeaderRecommend 'samsung' }) }
if ($BdRecGeneric) { $BdRecGeneric.Add_MouseLeftButtonUp({ Apply-HeaderRecommend 'generic' }) }

if ($MainTabs) {
  $MainTabs.Add_SelectionChanged({
    param($sender, $e)
    # 忽略下拉框等子控件冒泡，只响应真正切页签
    try {
      if ($e.AddedItems.Count -eq 1 -and $e.AddedItems[0] -is [System.Windows.Controls.TabItem]) {
        Update-RecommendBadgeStyles
      }
    } catch {
      Update-RecommendBadgeStyles
    }
  })
}

if ($script:themeWatch) {
  $script:themeWatch.Add_Tick({
    try { Update-PowerStatus } catch {}
    if (-not $script:uiSettings -or $script:uiSettings.theme -ne 'system') { return }
    $now = Get-SystemIsLight
    if ($null -eq $script:lastSystemLight -or $now -ne $script:lastSystemLight) {
      $script:lastSystemLight = $now
      Apply-UiTheme 'system'
    }
  })
}

if ($RbAc) {
  $RbAc.Add_Checked({
    if ($script:loading) { return }
    if ($RbAc.IsChecked) {
      Persist-Sliders
      Set-SlidersFromProfile $profiles.ac
      Apply-If-Active
    }
  })
}
if ($RbBat) {
  $RbBat.Add_Checked({
    if ($script:loading) { return }
    if ($RbBat.IsChecked) {
      Persist-Sliders
      Set-SlidersFromProfile $profiles.battery
      Apply-If-Active
    }
  })
}

if ($BtnApplyFont) {
  $BtnApplyFont.Add_Click({
    $ori = if ($RbRgb -and $RbRgb.IsChecked) { 1 } else { 0 }
    $en = if ($ChkClearType) { [bool]$ChkClearType.IsChecked } else { $true }
    $fg = if ($SlFontGamma) { [double]$SlFontGamma.Value } else { 1.4 }
    Set-FontSmoothingSettings $en $fg $ori
    [System.Windows.MessageBox]::Show((T 'fontApplied'), (T 'appTitle'))
  })
}

if ($BtnClearTypeWizard) {
  $BtnClearTypeWizard.Add_Click({
    # 主窗体 Topmost 会导致 cttune 被压在下面；临时取消置顶并把向导拉到前台
    try {
      $script:prevTopmost = [bool]$window.Topmost
      $window.Topmost = $false
      try { [void][ClearyNative]::AllowSetForegroundWindow(-1) } catch {}
      $script:ctProc = Start-Process -FilePath "$env:SystemRoot\System32\cttune.exe" -PassThru
      $script:ctAttempts = 0
      if ($script:ctBringTimer) { try { $script:ctBringTimer.Stop() } catch {} }
      $script:ctBringTimer = New-Object System.Windows.Threading.DispatcherTimer
      $script:ctBringTimer.Interval = [TimeSpan]::FromMilliseconds(250)
      $script:ctBringTimer.Add_Tick({
        $script:ctAttempts++
        $raised = $false
        try {
          $list = @()
          if ($script:ctProc -and -not $script:ctProc.HasExited) {
            $script:ctProc.Refresh()
            $list += $script:ctProc
          }
          $list += @(Get-Process -Name 'cttune' -ErrorAction SilentlyContinue)
          foreach ($pr in $list) {
            if (-not $pr) { continue }
            $hwnd = $pr.MainWindowHandle
            if ($hwnd -ne [IntPtr]::Zero) {
              [void][ClearyNative]::ShowWindow($hwnd, 9) # SW_RESTORE
              [void][ClearyNative]::BringWindowToTop($hwnd)
              [void][ClearyNative]::SetForegroundWindow($hwnd)
              $raised = $true
            }
          }
        } catch {}
        if ($raised -or $script:ctAttempts -ge 24) {
          try { $script:ctBringTimer.Stop() } catch {}
          if (-not $script:ctWatchTimer) {
            $script:ctWatchTimer = New-Object System.Windows.Threading.DispatcherTimer
            $script:ctWatchTimer.Interval = [TimeSpan]::FromMilliseconds(700)
            $script:ctWatchTimer.Add_Tick({
              $alive = $false
              try {
                if ($script:ctProc) {
                  $script:ctProc.Refresh()
                  if (-not $script:ctProc.HasExited) { $alive = $true }
                }
                if (-not $alive) {
                  $alive = [bool](Get-Process -Name 'cttune' -ErrorAction SilentlyContinue)
                }
              } catch {}
              if (-not $alive) {
                try { $script:ctWatchTimer.Stop() } catch {}
                try { $window.Topmost = [bool]$script:prevTopmost } catch {}
              }
            })
          }
          try { $script:ctWatchTimer.Start() } catch {}
        }
      })
      $script:ctBringTimer.Start()
    } catch {
      try { $window.Topmost = [bool]$script:prevTopmost } catch {}
    }
  })
}

if ($BtnColorCalib) {
  $BtnColorCalib.Add_Click({
    # 打开系统「显示颜色校准」向导 (dccw.exe)
    try {
      $script:prevTopmostCal = [bool]$window.Topmost
      $window.Topmost = $false
      try { [void][ClearyNative]::AllowSetForegroundWindow(-1) } catch {}
      $dccw = Join-Path $env:SystemRoot 'System32\dccw.exe'
      if (-not (Test-Path $dccw)) { $dccw = 'dccw.exe' }
      $script:calProc = Start-Process -FilePath $dccw -PassThru
      $script:calAttempts = 0
      if ($script:calBringTimer) { try { $script:calBringTimer.Stop() } catch {} }
      $script:calBringTimer = New-Object System.Windows.Threading.DispatcherTimer
      $script:calBringTimer.Interval = [TimeSpan]::FromMilliseconds(250)
      $script:calBringTimer.Add_Tick({
        $script:calAttempts++
        $raised = $false
        try {
          $list = @()
          if ($script:calProc -and -not $script:calProc.HasExited) {
            $script:calProc.Refresh()
            $list += $script:calProc
          }
          $list += @(Get-Process -Name 'dccw' -ErrorAction SilentlyContinue)
          foreach ($pr in $list) {
            if (-not $pr) { continue }
            $hwnd = $pr.MainWindowHandle
            if ($hwnd -ne [IntPtr]::Zero) {
              [void][ClearyNative]::ShowWindow($hwnd, 9)
              [void][ClearyNative]::BringWindowToTop($hwnd)
              [void][ClearyNative]::SetForegroundWindow($hwnd)
              $raised = $true
            }
          }
        } catch {}
        if ($raised -or $script:calAttempts -ge 24) {
          try { $script:calBringTimer.Stop() } catch {}
          if (-not $script:calWatchTimer) {
            $script:calWatchTimer = New-Object System.Windows.Threading.DispatcherTimer
            $script:calWatchTimer.Interval = [TimeSpan]::FromMilliseconds(700)
            $script:calWatchTimer.Add_Tick({
              $alive = $false
              try {
                if ($script:calProc) {
                  $script:calProc.Refresh()
                  if (-not $script:calProc.HasExited) { $alive = $true }
                }
                if (-not $alive) {
                  $alive = [bool](Get-Process -Name 'dccw' -ErrorAction SilentlyContinue)
                }
              } catch {}
              if (-not $alive) {
                try { $script:calWatchTimer.Stop() } catch {}
                try { $window.Topmost = [bool]$script:prevTopmostCal } catch {}
              }
            })
          }
          try { $script:calWatchTimer.Start() } catch {}
        }
      })
      $script:calBringTimer.Start()
    } catch {
      try { $window.Topmost = [bool]$script:prevTopmostCal } catch {}
      [System.Windows.MessageBox]::Show(($_.Exception.Message), (T 'appTitle'))
    }
  })
}

if ($BtnSavePreset) {
  $BtnSavePreset.Add_Click({
    Persist-Sliders
    $name = ''
    if ($TxtPresetName) { $name = $TxtPresetName.Text.Trim() }
    if (-not $name) { $name = Get-SelectedPresetName }
    if (-not $name) {
      [System.Windows.MessageBox]::Show((T 'needPresetName'), (T 'tip')); return
    }
    $presets[$name] = [ordered]@{
      ac=[ordered]@{brightness=[int]$profiles.ac.brightness;contrast=[int]$profiles.ac.contrast;gammaPower=[math]::Round([double]$profiles.ac.gammaPower,2);scale=[math]::Round([double]$profiles.ac.scale,2)}
      battery=[ordered]@{brightness=[int]$profiles.battery.brightness;contrast=[int]$profiles.battery.contrast;gammaPower=[math]::Round([double]$profiles.battery.gammaPower,2);scale=[math]::Round([double]$profiles.battery.scale,2)}
    }
    Save-Presets $presets
    Save-ActiveProfiles $profiles
    Refresh-PresetCombo $name
    [System.Windows.MessageBox]::Show((TF 'savedPresetFmt' $name), (T 'appTitle'))
  })
}

if ($BtnLoadPreset) {
  $BtnLoadPreset.Add_Click({
    $name = Get-SelectedPresetName
    if (-not $name -or -not $presets.Contains($name)) {
      [System.Windows.MessageBox]::Show((T 'pickPreset'), (T 'tip')); return
    }
    $n = $presets[$name]
    $profiles.ac = @{ brightness=[int]$n.ac.brightness; contrast=[int]$n.ac.contrast; gammaPower=[double]$n.ac.gammaPower; scale=[double]$n.ac.scale }
    $profiles.battery = @{ brightness=[int]$n.battery.brightness; contrast=[int]$n.battery.contrast; gammaPower=[double]$n.battery.gammaPower; scale=[double]$n.battery.scale }
    Save-ActiveProfiles $profiles
    if ($RbAc -and $RbAc.IsChecked) { Set-SlidersFromProfile $profiles.ac } else { Set-SlidersFromProfile $profiles.battery }
    $use = if (Get-IsOnAc) { $profiles.ac } else { $profiles.battery }
    Apply-DisplayValues $use.brightness $use.contrast $use.gammaPower $use.scale
    if ($TxtPresetName) { $TxtPresetName.Text = $name }
    [System.Windows.MessageBox]::Show((TF 'loadedPresetFmt' $name), (T 'appTitle'))
  })
}

if ($BtnDelPreset) {
  $BtnDelPreset.Add_Click({
    $name = Get-SelectedPresetName
    if (-not $name -or -not $presets.Contains($name)) {
      [System.Windows.MessageBox]::Show((T 'pickDelPreset'), (T 'tip')); return
    }
    $presets.Remove($name)
    Save-Presets $presets
    Refresh-PresetCombo $null
    [System.Windows.MessageBox]::Show((TF 'deletedPresetFmt' $name), (T 'appTitle'))
  })
}

function Apply-FontFromUi {
  $ori = if ($RbRgb -and $RbRgb.IsChecked) { 1 } else { 0 }
  $en = if ($ChkClearType) { [bool]$ChkClearType.IsChecked } else { $true }
  $fg = if ($SlFontGamma) { [double]$SlFontGamma.Value } else { 1.4 }
  Set-FontSmoothingSettings $en $fg $ori
}

function Get-IsFontTabActive {
  try {
    if ($TabFont -and $TabFont.IsSelected) { return $true }
  } catch {}
  return $false
}

if ($BtnReset) {
  $BtnReset.Add_Click({
    if (Get-IsFontTabActive) {
      if ($ChkClearType) { $ChkClearType.IsChecked = $true }
      if ($SlFontGamma) { $SlFontGamma.Value = 1.4 }
      if ($RbRgb) { $RbRgb.IsChecked = $true }
      Apply-FontFromUi
      Flash-Status (T 'fontApplied')
      return
    }
    if ($SlBright) { $SlBright.Value=90 }
    if ($SlContrast) { $SlContrast.Value=50 }
    if ($SlGamma) { $SlGamma.Value=1.0 }
    if ($SlScale) { $SlScale.Value=1.0 }
    Persist-Sliders; Update-ValueLabels; Apply-If-Active
  })
}

if ($BtnApply) {
  $BtnApply.Add_Click({
    if (Get-IsFontTabActive) {
      Apply-FontFromUi
      Flash-Status (T 'fontApplied')
      return
    }
    Persist-Sliders
    Save-ActiveProfiles $profiles
    if ($script:uiSettings.autoStart -ne $false) {
      $script:uiSettings.autoStart = $true
      try { Set-StartupApply $true } catch {}
      try { Save-UiSettings $script:uiSettings } catch {}
    }
    $r = Apply-DisplayValues $SlBright.Value $SlContrast.Value $SlGamma.Value $SlScale.Value
    $mode = if ($RbAc -and $RbAc.IsChecked) { T 'modeAc' } else { T 'modeBat' }
    $okB = ($r.Brightness -ge 0)
    $okC = ($r.Contrast -ge 0)
    if ($okB -or $okC) {
      Flash-Status (TF 'appliedFmt' $mode $SlBright.Value $SlContrast.Value $SlGamma.Value $SlScale.Value)
    } else {
      Flash-Status (TF 'appliedGammaOnly' $mode)
    }
  })
}

if ($BtnSaveClose) {
  $BtnSaveClose.Add_Click({
    if (Get-IsFontTabActive) {
      try { Apply-FontFromUi } catch {}
    }
    Persist-Sliders
    Save-ActiveProfiles $profiles
    $use = if (Get-IsOnAc) { $profiles.ac } else { $profiles.battery }
    Apply-DisplayValues $use.brightness $use.contrast $use.gammaPower $use.scale
    $window.Close()
  })
}

$window.Add_Loaded({
  try {
    $script:loading = $true
    Apply-UiTheme $script:uiSettings.theme
    Apply-UiLanguage (Get-UiLang) $false
    Update-RecommendBadgeStyles
    Update-FontRecommendBadgeStyles
    Update-RecommendDetailPanel
    Update-FontRecommendDetailPanel
    Update-PowerStatus
    if ($CmbPreset) { Refresh-PresetCombo $null }
    Sync-PowerRadioToActual
    if (Get-IsOnAc) {
      if ($profiles.ac) { Set-SlidersFromProfile $profiles.ac }
    } else {
      if ($profiles.battery) { Set-SlidersFromProfile $profiles.battery }
    }
    Update-ValueLabels
    $script:lastSystemLight = Get-SystemIsLight
    if ($script:themeWatch) { $script:themeWatch.Start() }

    $script:deferTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:deferTimer.Interval = [TimeSpan]::FromMilliseconds(400)
    $script:deferTimer.Add_Tick({
      try { $script:deferTimer.Stop() } catch {}
      try {
        if ($SlGamma -and $SlScale) {
          Apply-Gamma ([double]$SlGamma.Value) ([double]$SlScale.Value)
          if ($TxtReadback) { $TxtReadback.Text = (T 'readyApply') }
        }
      } catch {
        if ($TxtReadback) { $TxtReadback.Text = (T 'readyNoPreview') }
      }
    })
    $script:deferTimer.Start()
  } catch {
    [System.Windows.MessageBox]::Show(((T 'initFail') + $_.Exception.Message), (T 'appTitle'))
  } finally {
    $script:loading = $false
  }
})

$window.Add_Closed({
  try { if ($script:timer) { $script:timer.Stop() } } catch {}
  try { if ($script:themeWatch) { $script:themeWatch.Stop() } } catch {}
  try { if ($script:deferTimer) { $script:deferTimer.Stop() } } catch {}
})

# Startup error surface (helps diagnose other PCs)
try {
  if (-not $window) { throw 'Window object is null (XAML failed to load)' }
  [void]$window.ShowDialog()
} catch {
  $msg = (T 'startFail') + $_.Exception.Message + "`n`n" + $_.ScriptStackTrace
  try {
    [System.Windows.MessageBox]::Show($msg, (T 'appTitle'))
  } catch {
    # Fallback if WPF MessageBox unavailable
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    [System.Windows.Forms.MessageBox]::Show($msg, 'ClearyDisplay')
  }
}


