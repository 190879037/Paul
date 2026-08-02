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
  public const uint SPI_SETFONTSMOOTHINGGAMMA = 0x200C;
  public const uint SPI_SETFONTSMOOTHINGORIENTATION = 0x2013;
  public const uint FE_FONTSMOOTHINGCLEARTYPE = 2;
  public const uint SPIF_UPDATEINIFILE = 0x01;
  public const uint SPIF_SENDCHANGE = 0x02;
}
"@
}

function Get-IsOnAc {
  $b = Get-CimInstance Win32_Battery -EA SilentlyContinue
  if (-not $b) { return $true }
  return ([int]$b.BatteryStatus -eq 2)
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
  [void][ClearyNative]::SystemParametersInfo([ClearyNative]::SPI_SETFONTSMOOTHINGGAMMA, 0, [ref]$g, $flags)
  $o = [uint32]$orientation
  [void][ClearyNative]::SystemParametersInfo([ClearyNative]::SPI_SETFONTSMOOTHINGORIENTATION, 0, [ref]$o, $flags)
  Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name FontSmoothing -Value ($(if($enableClearType){'2'}else{'0'}))
  Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name FontSmoothingType -Value ($(if($enableClearType){2}else{1})) -Type DWord
  Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name FontSmoothingGamma -Value ([int]$g) -Type DWord
  Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name FontSmoothingOrientation -Value $orientation -Type DWord
}

function Get-SystemIsLight {
  try {
    $v = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -EA Stop).AppsUseLightTheme
    return ([int]$v -ne 0)
  } catch { return $true }
}

function Load-UiSettings {
  $d = @{ theme = 'light'; recommend = 'generic'; lang = 'zh' }
  if (-not (Test-Path $uiSettingsPath)) { return $d }
  try {
    $j = Get-Content $uiSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($j.theme -in @('light','dark','system')) { $d.theme = [string]$j.theme }
    if ($j.recommend -in @('apple','lg','huawei','asus','generic')) { $d.recommend = [string]$j.recommend }
    if ($j.lang -in @('zh','en')) { $d.lang = [string]$j.lang }
  } catch {}
  return $d
}

function Save-UiSettings($s) {
  $rec = if ($s.recommend) { $s.recommend } else { 'generic' }
  $lang = if ($s.lang -in @('zh','en')) { $s.lang } else { 'zh' }
  (@{ theme = $s.theme; recommend = $rec; lang = $lang } | ConvertTo-Json) | Set-Content $uiSettingsPath -Encoding UTF8
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
    powerDesc = '分别为「接电」和「电池」保存独立参数。仅编辑当前电源状态时会实时预览。'
    rbAc = '接电状态'
    rbBat = '电池状态'
    recTitleFmt = '推荐档 · {0}'
    recAcFmt = '接电：亮 {0} / 对比 {1} / γ {2:N2} / 缩放 {3:N2}'
    recBatFmt = '电池：亮 {0} / 对比 {1} / γ {2:N2} / 缩放 {3:N2}'
    recNote = '软件近似观感，非官方 ICC。点顶部胶囊切换；「立即应用」写入显示器。'
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
    fontGammaHint = '通常 1.0～2.2。数值越高，文字边缘对比越强。'
    subpixel = '子像素排列'
    rgbCommon = 'RGB（常见）'
    btnApplyFont = '应用字体设置'
    btnClearTypeWizard = '打开系统 ClearType 向导'
    previewTitle = '预览'
    previewDesc = '下面文字用于观察边缘是否舒服（宋体/雅黑混排）。'
    previewSample = '屏幕与字体调节 ClearyDisplay'
    previewZh = '中文预览：清屏、亮度、对比度、伽马。字体渲染是否清晰细腻，一眼可辨。'
    themeTitle = '外观主题'
    themeHintPick = '选择 Apple Native、Windows 11 Mica / Acrylic、Gitcode 风格，或跟随 Windows 系统。'
    themeHintFmt = '当前界面：{0}'
    themeAppleShort = '苹'
    themeApple = 'Apple Native'
    themeAppleDesc = 'macOS Big Sur 风：干净中性白、SF 系统字体观感、柔和分隔线'
    themeMicaShort = 'M'
    themeMica = 'Windows 11 Mica'
    themeMicaDesc = 'Win11 原生云母：微妙桌面取色、Segoe UI 观感、卡片半透叠加桌面'
    themeAcrylicShort = 'A'
    themeAcrylic = 'Windows 11 Acrylic'
    themeAcrylicDesc = 'Win11 亚克力：高斯模糊背景 + 微高光，类开始菜单/操作中心玻璃质感'
    themeGitcodeShort = 'G'
    themeGitcode = 'Gitcode'
    themeGitcodeDesc = 'GitHub 暗色 IDE 风：深色卡片 + 绿色重音，长时间编码更护眼'
    themeSysShort = '自'
    themeSystem = '跟随系统'
    themeSystemDesc = '自动跟随 Windows「深色 / 浅色」模式（同时切换 Apple Native 风格）'
    lightWord = '浅色'
    darkWord = '深色'
    btnReset = '重置本档'
    btnApply = '立即应用'
    btnSaveClose = '保存并关闭'
    footerHint = '左右并排调节 · 拖动滑块实时预览 ·「立即应用」写入配置'
    tip = '提示'
    apple = '苹果'
    huawei = '华为'
    asus = '华硕'
    generic = '通用显示'
    tipApple = '苹果 Studio Display 风：干净中性白、偏软中间调，接近 D65 参考白点'
    tipLg = 'LG UltraFine / Nano IPS 风：相对苹果略冷、对比更利落'
    tipHuawei = '华为 Mate 旗舰屏风：更亮、略冷、中间调抬亮，接近手机 OLED 的润白'
    tipAsus = '华硕 ProArt 准色风：参考亮度、标准伽马，偏专业校色观感'
    tipGeneric = '通用显示：本机默认平衡档（亮度 90 / 对比度 50 / 线性伽马）'
    recAppleTarget = 'Studio Display：干净中性白、中间调略软'
    recLgTarget = 'UltraFine / Nano IPS：相对苹果略冷、对比更利'
    recHuaweiTarget = 'Mate 旗舰屏：更亮润白、中间调抬升'
    recAsusTarget = 'ProArt 准色：参考亮度、标准伽马'
    recGenericTarget = '默认平衡档'
    recAppleHint = '已套用苹果风：干净中性白、偏软中间调（参考 Studio Display）'
    recLgHint = '已套用 LG 风：略冷、对比更利（参考 UltraFine / Nano IPS）'
    recHuaweiHint = '已套用华为风：更亮润白、中间调抬升（参考 Mate 旗舰屏）'
    recAsusHint = '已套用华硕风：准色参考档（参考 ProArt）'
    recGenericHint = '已套用通用显示：默认平衡档'
    recPreviewFmt = '推荐档「{0}」已预览。可再微调，或点「立即应用」写入显示器。'
    previewPaused = '预览已暂停：正在编辑另一电源档（屏幕不变）'
    livePreviewFmt = '实时预览 · 亮度回读 {0} · 对比度回读 {1}'
    previewFail = '预览部分失败，可再点「立即应用」'
    fontApplied = '字体设置已应用。部分程序需重启后完全生效。'
    fontApplyPartial = '字体设置部分失败，但显示设置已应用。'
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
    appTitle = 'Display & Font'
    langTip = 'Switch to 中文'
    statusAc = 'Power: AC plugged in'
    statusBat = 'Power: On battery'
    tabDisplay = 'Display'
    tabFont = 'Font'
    tabTheme = 'Theme'
    powerTitle = 'Power profiles'
    powerDesc = 'Separate settings for AC and battery. Live preview only when editing the active power state.'
    rbAc = 'On AC'
    rbBat = 'On battery'
    recTitleFmt = 'Preset · {0}'
    recAcFmt = 'AC: Bright {0} / Contrast {1} / γ {2:N2} / Scale {3:N2}'
    recBatFmt = 'Battery: Bright {0} / Contrast {1} / γ {2:N2} / Scale {3:N2}'
    recNote = 'Software approximation, not an official ICC. Switch via top chips; Apply writes to the monitor.'
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
    gammaHint = '> 1 darker, < 1 brighter'
    scale = 'Overall scale'
    scaleHint = 'Global luminance multiplier'
    readbackDash = 'Hardware readback: —'
    readbackFmt = 'Hardware: Brightness {0} · Contrast {1}'
    clearTypeTitle = 'ClearType smoothing'
    clearTypeDesc = 'Windows system font rendering. Some apps need a restart to fully update.'
    enableClearType = 'Enable ClearType'
    fontGamma = 'Font smoothing gamma'
    fontGammaHint = 'Typically 1.0–2.2. Higher = stronger edge contrast.'
    subpixel = 'Subpixel layout'
    rgbCommon = 'RGB (common)'
    btnApplyFont = 'Apply font settings'
    btnClearTypeWizard = 'Open ClearType wizard'
    previewTitle = 'Preview'
    previewDesc = 'Sample text to judge edge comfort (serif / sans mix).'
    previewSample = 'Display & Font ClearyDisplay'
    previewZh = 'Chinese sample: clarity, brightness, contrast, gamma — judge sharpness at a glance.'
    themeTitle = 'Appearance'
    themeHintPick = 'Pick Apple Native, Windows 11 Mica / Acrylic, Gitcode, or follow Windows.'
    themeHintFmt = 'UI theme: {0}'
    themeAppleShort = 'A'
    themeApple = 'Apple Native'
    themeAppleDesc = 'macOS Big Sur look: clean neutral white, SF vibe, soft separators'
    themeMicaShort = 'M'
    themeMica = 'Windows 11 Mica'
    themeMicaDesc = 'Win11 mica material: subtle desktop tinting, Segoe UI feel, layered cards'
    themeAcrylicShort = 'A'
    themeAcrylic = 'Windows 11 Acrylic'
    themeAcrylicDesc = 'Win11 acrylic: blurred background with light highlights, glassy menu feel'
    themeGitcodeShort = 'G'
    themeGitcode = 'Gitcode'
    themeGitcodeDesc = 'GitHub dark IDE: deep cards with green accents, easier on the eyes'
    themeSysShort = 'S'
    themeSystem = 'System'
    themeSystemDesc = 'Follow Windows light / dark mode (with Apple Native look)'
    lightWord = 'Light'
    darkWord = 'Dark'
    btnReset = 'Reset profile'
    btnApply = 'Apply now'
    btnSaveClose = 'Save & close'
    footerHint = 'Side-by-side controls · live slider preview · Apply writes settings'
    tip = 'Notice'
    apple = 'Apple'
    huawei = 'Huawei'
    asus = 'ASUS'
    generic = 'Generic'
    tipApple = 'Apple Studio Display look: clean neutral white, soft midtones, near D65'
    tipLg = 'LG UltraFine / Nano IPS: cooler and crisper than Apple'
    tipHuawei = 'Huawei Mate look: brighter, slightly cool, lifted midtones'
    tipAsus = 'ASUS ProArt look: reference brightness, standard gamma'
    tipGeneric = 'Generic balanced defaults (Bright 90 / Contrast 50 / linear gamma)'
    recAppleTarget = 'Studio Display: clean neutral white, soft midtones'
    recLgTarget = 'UltraFine / Nano IPS: cooler, crisper than Apple'
    recHuaweiTarget = 'Mate flagship: brighter luminous white, lifted mids'
    recAsusTarget = 'ProArt: reference brightness, standard gamma'
    recGenericTarget = 'Default balanced profile'
    recAppleHint = 'Applied Apple look: clean neutral white, soft midtones'
    recLgHint = 'Applied LG look: cooler, crisper contrast'
    recHuaweiHint = 'Applied Huawei look: brighter luminous white'
    recAsusHint = 'Applied ASUS ProArt reference look'
    recGenericHint = 'Applied generic balanced profile'
    recPreviewFmt = 'Preset "{0}" previewed. Fine-tune, or Apply to write the monitor.'
    previewPaused = 'Preview paused: editing the other power profile'
    livePreviewFmt = 'Live preview · Bright {0} · Contrast {1}'
    previewFail = 'Partial preview failed — try Apply again'
    fontApplied = 'Font settings applied. Some apps need a restart.'
    fontApplyPartial = 'Font apply had issues; display settings saved.'
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

# 品牌推荐档：用本软件可控参数近似各厂「常见出厂观感」，非官方 ICC。
function Get-RecommendProfiles([string]$id) {
  switch ($id) {
    'apple' {
      return @{
        ac      = @{ brightness = 80; contrast = 50; gammaPower = 0.96; scale = 1.00 }
        battery = @{ brightness = 55; contrast = 50; gammaPower = 0.98; scale = 0.95 }
        fontGamma    = 1.10
        fontSubpixel = 1
        label   = (T 'apple')
        target  = (T 'recAppleTarget')
        hint    = (T 'recAppleHint')
      }
    }
    'lg' {
      return @{
        ac      = @{ brightness = 85; contrast = 55; gammaPower = 1.02; scale = 1.00 }
        battery = @{ brightness = 58; contrast = 52; gammaPower = 1.00; scale = 0.95 }
        fontGamma    = 1.40
        fontSubpixel = 1
        label   = 'LG'
        target  = (T 'recLgTarget')
        hint    = (T 'recLgHint')
      }
    }
    'huawei' {
      return @{
        ac      = @{ brightness = 92; contrast = 58; gammaPower = 0.88; scale = 0.98 }
        battery = @{ brightness = 62; contrast = 55; gammaPower = 0.92; scale = 0.95 }
        fontGamma    = 1.20
        fontSubpixel = 1
        label   = (T 'huawei')
        target  = (T 'recHuaweiTarget')
        hint    = (T 'recHuaweiHint')
      }
    }
    'asus' {
      return @{
        ac      = @{ brightness = 75; contrast = 50; gammaPower = 1.00; scale = 1.00 }
        battery = @{ brightness = 50; contrast = 50; gammaPower = 1.00; scale = 0.95 }
        fontGamma    = 1.00
        fontSubpixel = 1
        label   = (T 'asus')
        target  = (T 'recAsusTarget')
        hint    = (T 'recAsusHint')
      }
    }
    default {
      return @{
        ac      = @{ brightness = 90; contrast = 50; gammaPower = 1.00; scale = 1.00 }
        battery = @{ brightness = 70; contrast = 50; gammaPower = 1.00; scale = 0.95 }
        fontGamma    = 1.40
        fontSubpixel = 1
        label   = (T 'generic')
        target  = (T 'recGenericTarget')
        hint    = (T 'recGenericHint')
      }
    }
  }
}

function Update-RecommendDetailPanel {
  $id = if ($script:uiSettings -and $script:uiSettings.recommend) { $script:uiSettings.recommend } else { 'generic' }
  $rec = Get-RecommendProfiles $id
  $ac = $rec.ac
  $bat = $rec.battery
  if ($TxtRecTitle) { $TxtRecTitle.Text = (TF 'recTitleFmt' $rec.label) }
  if ($TxtRecTarget) { $TxtRecTarget.Text = $rec.target }
  if ($TxtRecAcParams) {
    $TxtRecAcParams.Text = (TF 'recAcFmt' $ac.brightness $ac.contrast $ac.gammaPower $ac.scale)
  }
  if ($TxtRecBatParams) {
    $TxtRecBatParams.Text = (TF 'recBatFmt' $bat.brightness $bat.contrast $bat.gammaPower $bat.scale)
  }
  if ($TxtRecNote) { $TxtRecNote.Text = (T 'recNote') }
}

function Update-RecommendBadgeStyles {
  $sel = if ($script:uiSettings -and $script:uiSettings.recommend) { $script:uiSettings.recommend } else { 'generic' }
  $items = @(
    @{ Id='apple';   Bd=$BdRecApple;   Txt=$TxtRecApple },
    @{ Id='lg';      Bd=$BdRecLg;      Txt=$TxtRecLg },
    @{ Id='huawei';  Bd=$BdRecHuawei;  Txt=$TxtRecHuawei },
    @{ Id='asus';    Bd=$BdRecAsus;    Txt=$TxtRecAsus },
    @{ Id='generic'; Bd=$BdRecGeneric; Txt=$TxtRecGeneric }
  )
  foreach ($it in $items) {
    if (-not $it.Bd -or -not $it.Txt) { continue }
    $on = ($it.Id -eq $sel)
    if ($on) {
      $it.Bd.Background = Get-ResourceBrush 'AccentSoft'
      $it.Txt.Foreground = Get-ResourceBrush 'Accent'
    } else {
      $it.Bd.Background = Get-ResourceBrush 'GhostBg'
      $it.Txt.Foreground = Get-ResourceBrush 'TextSecondary'
    }
  }
}

function Apply-Recommend([string]$id, [bool]$persist = $true) {
  if ($id -notin @('apple','lg','huawei','asus','generic')) { $id = 'generic' }
  $rec = Get-RecommendProfiles $id
  # 接电 / 电池两套都写入推荐值
  $profiles.ac.brightness = [int]$rec.ac.brightness
  $profiles.ac.contrast = [int]$rec.ac.contrast
  $profiles.ac.gammaPower = [double]$rec.ac.gammaPower
  $profiles.ac.scale = [double]$rec.ac.scale
  $profiles.battery.brightness = [int]$rec.battery.brightness
  $profiles.battery.contrast = [int]$rec.battery.contrast
  $profiles.battery.gammaPower = [double]$rec.battery.gammaPower
  $profiles.battery.scale = [double]$rec.battery.scale

  if (-not $script:uiSettings) { $script:uiSettings = @{ theme = 'apple'; recommend = $id } }
  $script:uiSettings.recommend = $id
  Update-RecommendBadgeStyles
  Update-RecommendDetailPanel

  if ($RbAc -and $RbAc.IsChecked) { Set-SlidersFromProfile $profiles.ac }
  else { Set-SlidersFromProfile $profiles.battery }

  # 字体平滑伽马：随品牌预设同步（Apple 风偏软、LG 风利落）
  if ($SlFontGamma) {
    $script:loading = $true
    try { $SlFontGamma.Value = [double]$rec.fontGamma } finally { $script:loading = $false }
    if ($TxtFontGamma) { $TxtFontGamma.Text = ('{0:N2}' -f $SlFontGamma.Value) }
  }
  if ($RbBgr -and ([int]$rec.fontSubpixel -eq 0)) { $RbBgr.IsChecked = $true }
  elseif ($RbRgb) { $RbRgb.IsChecked = $true }
  $en = if ($ChkClearType) { [bool]$ChkClearType.IsChecked } else { $true }
  $ori = if ($RbRgb -and $RbRgb.IsChecked) { 1 } else { 0 }
  $fg = if ($SlFontGamma) { [double]$SlFontGamma.Value } else { [double]$rec.fontGamma }
  try { Set-FontSmoothingSettings $en $fg $ori } catch {}

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

function Update-ThemeCardStyles([string]$mode) {
  $cards = @{
    apple    = $BdThemeApple
    mica     = $BdThemeMica
    acrylic  = $BdThemeAcrylic
    gitcode  = $BdThemeGitcode
    system   = $BdThemeSystem
  }
  $marks = @{
    apple    = $TxtThemeAppleMark
    mica     = $TxtThemeMicaMark
    acrylic  = $TxtThemeAcrylicMark
    gitcode  = $TxtThemeGitcodeMark
    system   = $TxtThemeSystemMark
  }
  foreach ($k in $cards.Keys) {
    $bd = $cards[$k]
    $mk = $marks[$k]
    if (-not $bd) { continue }
    if ($k -eq $mode) {
      $bd.BorderBrush = Get-ResourceBrush 'Accent'
      $bd.BorderThickness = New-Object System.Windows.Thickness 2
      $bd.Background = Get-ResourceBrush 'AccentSoft'
      if ($mk) { $mk.Text = '✓' }
    } else {
      $bd.BorderBrush = Get-ResourceBrush 'CardBorder'
      $bd.BorderThickness = New-Object System.Windows.Thickness 1
      $bd.Background = Get-ResourceBrush 'CardBg'
      if ($mk) { $mk.Text = '' }
    }
  }
}

function Apply-UiTheme([string]$mode) {
  try {
    if (-not $script:uiSettings) { $script:uiSettings = @{ theme = 'apple' } }
    if (-not $mode) { $mode = 'apple' }
    if ($mode -notin @('apple','mica','acrylic','gitcode','system','light','dark')) { $mode = 'apple' }
    # 兼容老设置：light/dark 都迁移到 apple（最接近原观感）
    if ($mode -eq 'light') { $mode = 'apple' }
    elseif ($mode -eq 'dark') { $mode = 'gitcode' }
    $script:uiSettings.theme = $mode

    # 'system' 跟随 Windows；其它品牌主题按各自色板强制应用
    $effectiveDark = $false
    $forcedBrand = $true
    switch ($mode) {
      'apple'   { $effectiveDark = $false }
      'mica'    { $effectiveDark = $false }
      'acrylic' { $effectiveDark = $false }
      'gitcode' { $effectiveDark = $true }
      'system'  { $forcedBrand = $false; $effectiveDark = -not (Get-SystemIsLight) }
      default   { $mode = 'apple'; $forcedBrand = $true; $effectiveDark = $false }
    }

    # Apple Native 色板
    $appleLight = @{
      WinBg        = '#F5F5F7'; CardBg = '#FFFFFF'; CardBorder = '#D2D2D7'
      TextPrimary  = '#1D1D1F'; TextSecondary = '#6E6E73'; TextMuted = '#8E8E93'
      Accent       = '#007AFF'; AccentSoft = '#E5F1FE'
      GhostBg      = '#F2F2F4'; TrackBg = '#B8BCC4'
      InputBg      = '#FFFFFF'; InputBorder = '#C8CCD4'
      ThumbFill    = '#FFFFFF'
    }
    $appleDark = @{
      WinBg        = '#1C1C1E'; CardBg = '#2C2C2E'; CardBorder = '#3A3A3C'
      TextPrimary  = '#F5F5F7'; TextSecondary = '#AEAEB2'; TextMuted = '#8E8E93'
      Accent       = '#0A84FF'; AccentSoft = '#1A3A5C'
      GhostBg      = '#3A3A3C'; TrackBg = '#636366'
      InputBg      = '#1C1C1E'; InputBorder = '#48484A'
      ThumbFill    = '#2C2C2E'
    }
    # Windows 11 Mica（Win11 原生云母，浅色偏冷）
    $micaLight = @{
      WinBg        = '#F3F3F3'; CardBg = '#FAFAFA'; CardBorder = '#E5E5E5'
      TextPrimary  = '#1C1C1C'; TextSecondary = '#5C5C5C'; TextMuted = '#8A8A8A'
      Accent       = '#0078D4'; AccentSoft = '#EAF6FD'
      GhostBg      = '#F0F0F0'; TrackBg = '#BFBFBF'
      InputBg      = '#FFFFFF'; InputBorder = '#C8C8C8'
      ThumbFill    = '#FFFFFF'
    }
    $micaDark = @{
      WinBg        = '#202020'; CardBg = '#2B2B2B'; CardBorder = '#383838'
      TextPrimary  = '#F0F0F0'; TextSecondary = '#A8A8A8'; TextMuted = '#7A7A7A'
      Accent       = '#4CC2FF'; AccentSoft = '#1F3A52'
      GhostBg      = '#353535'; TrackBg = '#5C5C5C'
      InputBg      = '#2B2B2B'; InputBorder = '#404040'
      ThumbFill    = '#2B2B2B'
    }
    # Windows 11 Acrylic（Win11 亚克力，浅色更亮 + 微冷调）
    $acrylicLight = @{
      WinBg        = '#ECECEC'; CardBg = '#F5F5F5'; CardBorder = '#D0D0D0'
      TextPrimary  = '#1F1F1F'; TextSecondary = '#5A5A5A'; TextMuted = '#888888'
      Accent       = '#0078D4'; AccentSoft = '#E5F1FB'
      GhostBg      = '#EEEEEE'; TrackBg = '#B8B8B8'
      InputBg      = '#FAFAFA'; InputBorder = '#C0C0C0'
      ThumbFill    = '#FAFAFA'
    }
    $acrylicDark = @{
      WinBg        = '#1F1F1F'; CardBg = '#2D2D2D'; CardBorder = '#3A3A3A'
      TextPrimary  = '#EFEFEF'; TextSecondary = '#AAAAAA'; TextMuted = '#7C7C7C'
      Accent       = '#4CC2FF'; AccentSoft = '#1A3A5C'
      GhostBg      = '#383838'; TrackBg = '#5A5A5A'
      InputBg      = '#2D2D2D'; InputBorder = '#424242'
      ThumbFill    = '#2D2D2D'
    }
    # Gitcode（GitHub 风：暗色卡片 + 绿色重音）
    $gitcodeLight = @{
      WinBg        = '#F6F8FA'; CardBg = '#FFFFFF'; CardBorder = '#D0D7DE'
      TextPrimary  = '#1F2328'; TextSecondary = '#57606A'; TextMuted = '#8C959F'
      Accent       = '#1F883D'; AccentSoft = '#DAFBE1'
      GhostBg      = '#EAEEF2'; TrackBg = '#AFB8C1'
      InputBg      = '#FFFFFF'; InputBorder = '#D0D7DE'
      ThumbFill    = '#FFFFFF'
    }
    $gitcodeDark = @{
      WinBg        = '#0D1117'; CardBg = '#161B22'; CardBorder = '#30363D'
      TextPrimary  = '#C9D1D9'; TextSecondary = '#8B949E'; TextMuted = '#6E7681'
      Accent       = '#2EA043'; AccentSoft = '#103518'
      GhostBg      = '#21262D'; TrackBg = '#484F58'
      InputBg      = '#0D1117'; InputBorder = '#30363D'
      ThumbFill    = '#161B22'
    }

    $palette = $null
    if ($mode -eq 'apple')      { $palette = if ($effectiveDark) { $appleDark }     else { $appleLight } }
    elseif ($mode -eq 'mica')   { $palette = if ($effectiveDark) { $micaDark }      else { $micaLight } }
    elseif ($mode -eq 'acrylic'){ $palette = if ($effectiveDark) { $acrylicDark }   else { $acrylicLight } }
    elseif ($mode -eq 'gitcode'){ $palette = $gitcodeDark } # Gitcode 始终暗色，仅一种风格
    elseif ($mode -eq 'system') {
      # 跟随系统：以 Apple Native 风格为基底，跟随 Windows 深浅
      $palette = if ($effectiveDark) { $appleDark } else { $appleLight }
      $script:uiSettings.theme = 'system'
    }

    if ($palette) {
      foreach ($k in $palette.Keys) { Set-ResourceBrush $k $palette[$k] }
    }

    if ($window) { $window.Background = Get-ResourceBrush 'WinBg' }
    if ($TxtThemeHint) {
      $label = switch ($mode) {
        'apple'   { T 'themeApple' }
        'mica'    { T 'themeMica' }
        'acrylic' { T 'themeAcrylic' }
        'gitcode' { T 'themeGitcode' }
        default   {
          $sys = if (Get-SystemIsLight) { T 'lightWord' } else { T 'darkWord' }
          ('{0}（{1}）' -f (T 'themeSystem'), $sys)
        }
      }
      $TxtThemeHint.Text = (TF 'themeHintFmt' $label)
    }
    Update-ThemeCardStyles $mode
    Update-RecommendBadgeStyles
    Save-UiSettings $script:uiSettings
  } catch {
    # 主题失败不阻断窗口
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
  if ($TxtThemeAppleShort) { $TxtThemeAppleShort.Text = (T 'themeAppleShort') }
  if ($TxtThemeAppleName) { $TxtThemeAppleName.Text = (T 'themeApple') }
  if ($TxtThemeAppleDesc) { $TxtThemeAppleDesc.Text = (T 'themeAppleDesc') }
  if ($TxtThemeMicaShort) { $TxtThemeMicaShort.Text = (T 'themeMicaShort') }
  if ($TxtThemeMicaName) { $TxtThemeMicaName.Text = (T 'themeMica') }
  if ($TxtThemeMicaDesc) { $TxtThemeMicaDesc.Text = (T 'themeMicaDesc') }
  if ($TxtThemeAcrylicShort) { $TxtThemeAcrylicShort.Text = (T 'themeAcrylicShort') }
  if ($TxtThemeAcrylicName) { $TxtThemeAcrylicName.Text = (T 'themeAcrylic') }
  if ($TxtThemeAcrylicDesc) { $TxtThemeAcrylicDesc.Text = (T 'themeAcrylicDesc') }
  if ($TxtThemeGitcodeShort) { $TxtThemeGitcodeShort.Text = (T 'themeGitcodeShort') }
  if ($TxtThemeGitcodeName) { $TxtThemeGitcodeName.Text = (T 'themeGitcode') }
  if ($TxtThemeGitcodeDesc) { $TxtThemeGitcodeDesc.Text = (T 'themeGitcodeDesc') }
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
  if ($TxtRecGeneric) { $TxtRecGeneric.Text = (T 'generic') }
  if ($BdRecApple) { $BdRecApple.ToolTip = (T 'tipApple') }
  if ($BdRecLg) { $BdRecLg.ToolTip = (T 'tipLg') }
  if ($BdRecHuawei) { $BdRecHuawei.ToolTip = (T 'tipHuawei') }
  if ($BdRecAsus) { $BdRecAsus.ToolTip = (T 'tipAsus') }
  if ($BdRecGeneric) { $BdRecGeneric.ToolTip = (T 'tipGeneric') }

  Update-RecommendBadgeStyles
  Update-RecommendDetailPanel
  Update-PowerStatus
  if ($script:uiSettings.theme) {
    $m = $script:uiSettings.theme
    if ($TxtThemeHint) {
      $label = switch ($m) {
        'apple'   { T 'themeApple' }
        'mica'    { T 'themeMica' }
        'acrylic' { T 'themeAcrylic' }
        'gitcode' { T 'themeGitcode' }
        default   {
          $sys = if (Get-SystemIsLight) { T 'lightWord' } else { T 'darkWord' }
          ('{0}（{1}）' -f (T 'themeSystem'), $sys)
        }
      }
      $TxtThemeHint.Text = (TF 'themeHintFmt' $label)
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
  $script:uiSettings = @{ theme = 'apple'; recommend = 'generic'; lang = 'zh' }
}
# 旧值迁移：light/dark 映射到最接近的新主题
if ($script:uiSettings.theme -eq 'light') { $script:uiSettings.theme = 'apple' }
elseif ($script:uiSettings.theme -eq 'dark') { $script:uiSettings.theme = 'gitcode' }
if ($script:uiSettings.theme -notin @('apple','mica','acrylic','gitcode','system')) {
  $script:uiSettings.theme = 'apple'
}
if (-not $script:uiSettings.recommend) { $script:uiSettings.recommend = 'generic' }
if (-not $script:uiSettings.lang) { $script:uiSettings.lang = 'zh' }
$script:loading = $true

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="屏幕与字体调节"
        Height="800" Width="920"
        MinHeight="720" MinWidth="860"
        WindowStartupLocation="CenterScreen"
        ResizeMode="CanResizeWithGrip"
        Topmost="True"
        Background="{DynamicResource WinBg}"
        FontFamily="Segoe UI Variable Text, Segoe UI, Microsoft YaHei UI, Segoe UI"
        FontSize="13"
        FontWeight="Normal"
        Foreground="{DynamicResource TextPrimary}"
        UseLayoutRounding="True"
        SnapsToDevicePixels="True"
        TextOptions.TextFormattingMode="Display"
        TextOptions.TextRenderingMode="ClearType"
        TextOptions.TextHintingMode="Animated">
  <Window.Resources>
    <SolidColorBrush x:Key="WinBg" Color="#F7F8FA"/>
    <SolidColorBrush x:Key="CardBg" Color="#FFFFFF"/>
    <SolidColorBrush x:Key="CardBorder" Color="#E8EAEF"/>
    <SolidColorBrush x:Key="Accent" Color="#0078D4"/>
    <SolidColorBrush x:Key="AccentSoft" Color="#EEF6FF"/>
    <SolidColorBrush x:Key="TextPrimary" Color="#1A1A1A"/>
    <SolidColorBrush x:Key="TextSecondary" Color="#5C5C5C"/>
    <SolidColorBrush x:Key="TextMuted" Color="#8A8A8A"/>
    <SolidColorBrush x:Key="GhostBg" Color="#F0F2F5"/>
    <SolidColorBrush x:Key="TrackBg" Color="#B8BCC4"/>
    <SolidColorBrush x:Key="InputBg" Color="#FFFFFF"/>
    <SolidColorBrush x:Key="InputBorder" Color="#C8CCD4"/>
    <SolidColorBrush x:Key="ThumbFill" Color="#FFFFFF"/>
    <Style TargetType="TextBlock">
      <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
      <Setter Property="FontWeight" Value="Normal"/>
      <Setter Property="TextOptions.TextFormattingMode" Value="Display"/>
      <Setter Property="TextOptions.TextRenderingMode" Value="ClearType"/>
      <Setter Property="UseLayoutRounding" Value="True"/>
      <Setter Property="SnapsToDevicePixels" Value="True"/>
    </Style>
    <Style x:Key="PageTitle" TargetType="TextBlock">
      <Setter Property="FontSize" Value="22"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
    </Style>
    <Style x:Key="SectionTitle" TargetType="TextBlock">
      <Setter Property="FontSize" Value="15"/>
      <Setter Property="FontWeight" Value="Bold"/>
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
      <Setter Property="CornerRadius" Value="12"/>
      <Setter Property="Padding" Value="18"/>
      <Setter Property="Margin" Value="0,0,0,12"/>
      <Setter Property="Effect">
        <Setter.Value>
          <DropShadowEffect BlurRadius="18" ShadowDepth="1" Opacity="0.08" Color="#000000"/>
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
            <Grid Height="10">
              <Border Background="{DynamicResource Accent}" CornerRadius="1.5" Height="3" VerticalAlignment="Center"/>
            </Grid>
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
              <Border Height="3" Background="{DynamicResource TrackBg}" CornerRadius="1.5"
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
      <Setter Property="FontWeight" Value="Light"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Background="{TemplateBinding Background}" CornerRadius="8" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="GhostBtn" TargetType="Button" BasedOn="{StaticResource PrimaryBtn}">
      <Setter Property="Background" Value="{DynamicResource GhostBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
      <Setter Property="FontWeight" Value="Light"/>
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
    <!-- 细线滚动条：8px 宽，Thumb 圆角，悬停才显形 -->
    <Style x:Key="ThinScrollBarBtn" TargetType="RepeatButton">
      <Setter Property="OverridesDefaultStyle" Value="True"/>
      <Setter Property="IsTabStop" Value="False"/>
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RepeatButton">
            <Border Background="Transparent" Width="0" Height="0"/>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="ThinScrollBarThumb" TargetType="Thumb">
      <Setter Property="OverridesDefaultStyle" Value="True"/>
      <Setter Property="IsTabStop" Value="False"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Thumb">
            <Border x:Name="Bd" Background="{DynamicResource TextMuted}" CornerRadius="3" Opacity="0.55" Margin="2,0"/>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.85"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="ThinScrollBar" TargetType="ScrollBar">
      <Setter Property="Width" Value="8"/>
      <Setter Property="MinWidth" Value="8"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="OverridesDefaultStyle" Value="True"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Grid x:Name="GridRoot" Width="8" Background="{TemplateBinding Background}">
              <Track x:Name="PART_Track" IsDirectionReversed="True">
                <Track.Thumb>
                  <Thumb Style="{StaticResource ThinScrollBarThumb}"/>
                </Track.Thumb>
                <Track.IncreaseRepeatButton>
                  <RepeatButton Style="{StaticResource ThinScrollBarBtn}" Command="ScrollBar.PageDownCommand"/>
                </Track.IncreaseRepeatButton>
                <Track.DecreaseRepeatButton>
                  <RepeatButton Style="{StaticResource ThinScrollBarBtn}" Command="ScrollBar.PageUpCommand"/>
                </Track.DecreaseRepeatButton>
              </Track>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="ThinScrollViewer" TargetType="ScrollViewer">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="VerticalScrollBarVisibility" Value="Auto"/>
      <Setter Property="OverridesDefaultStyle" Value="True"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollViewer">
            <Grid Background="{TemplateBinding Background}">
              <ScrollContentPresenter x:Name="PART_ScrollContentPresenter"
                                      CanContentScroll="{TemplateBinding CanContentScroll}"
                                      CanHorizontallyScroll="False" CanVerticallyScroll="True"
                                      Content="{TemplateBinding Content}"
                                      ContentTemplate="{TemplateBinding ContentTemplate}"
                                      Margin="{TemplateBinding Padding}"/>
              <ScrollBar x:Name="PART_VerticalScrollBar" Style="{StaticResource ThinScrollBar}"
                         HorizontalAlignment="Right" Orientation="Vertical"
                         Value="{TemplateBinding VerticalOffset}"
                         Maximum="{TemplateBinding ScrollableHeight}"
                         ViewportSize="{TemplateBinding ViewportHeight}"
                         Visibility="{TemplateBinding ComputedVerticalScrollBarVisibility}"/>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
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
          <Border x:Name="BdRecApple" Background="{DynamicResource GhostBg}" CornerRadius="20" Padding="14,8" Margin="0,0,8,0" Cursor="Hand"
                  ToolTip="苹果 Studio Display 风：干净中性白、偏软中间调，接近 D65 参考白点">
            <TextBlock x:Name="TxtRecApple" Text="苹果" Foreground="{DynamicResource TextSecondary}" FontWeight="SemiBold"/>
          </Border>
          <Border x:Name="BdRecLg" Background="{DynamicResource GhostBg}" CornerRadius="20" Padding="14,8" Margin="0,0,8,0" Cursor="Hand"
                  ToolTip="LG UltraFine / Nano IPS 风：相对苹果略冷、对比更利落">
            <TextBlock x:Name="TxtRecLg" Text="LG" Foreground="{DynamicResource TextSecondary}" FontWeight="SemiBold"/>
          </Border>
          <Border x:Name="BdRecHuawei" Background="{DynamicResource GhostBg}" CornerRadius="20" Padding="14,8" Margin="0,0,8,0" Cursor="Hand"
                  ToolTip="华为 Mate 旗舰屏风：更亮、略冷、中间调抬亮，接近手机 OLED 的润白">
            <TextBlock x:Name="TxtRecHuawei" Text="华为" Foreground="{DynamicResource TextSecondary}" FontWeight="SemiBold"/>
          </Border>
          <Border x:Name="BdRecAsus" Background="{DynamicResource GhostBg}" CornerRadius="20" Padding="14,8" Margin="0,0,8,0" Cursor="Hand"
                  ToolTip="华硕 ProArt 准色风：参考亮度、标准伽马，偏专业校色观感">
            <TextBlock x:Name="TxtRecAsus" Text="华硕" Foreground="{DynamicResource TextSecondary}" FontWeight="SemiBold"/>
          </Border>
          <Border x:Name="BdRecGeneric" Background="{DynamicResource AccentSoft}" CornerRadius="20" Padding="14,8" Cursor="Hand"
                  ToolTip="通用显示：本机默认平衡档（亮度 90 / 对比度 50 / 线性伽马）">
            <TextBlock x:Name="TxtRecGeneric" Text="通用显示" Foreground="{DynamicResource Accent}" FontWeight="SemiBold"/>
          </Border>
        </StackPanel>
      </Grid>
    </Border>

    <TabControl Grid.Row="1" Background="Transparent" BorderThickness="0" Padding="0">
      <!-- 显示 -->
      <TabItem x:Name="TabDisplay" Header="显示">
        <ScrollViewer Style="{StaticResource ThinScrollViewer}" Margin="0,12,0,0">
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
                    <RadioButton x:Name="RbAc" Content="接电状态" Margin="0,0,24,0" IsChecked="True"/>
                    <RadioButton x:Name="RbBat" Content="电池状态"/>
                  </StackPanel>
                </StackPanel>
              </Border>
              <Border Grid.Column="2" Style="{StaticResource Card}">
                <StackPanel>
                  <TextBlock x:Name="TxtRecTitle" Text="推荐档 · 通用显示" Style="{StaticResource SectionTitle}"/>
                  <TextBlock x:Name="TxtRecTarget" Text="默认平衡档" Foreground="{DynamicResource TextSecondary}" TextWrapping="Wrap" Margin="0,6,0,10"/>
                  <TextBlock x:Name="TxtRecAcParams" Text="接电：—" Foreground="{DynamicResource Accent}" TextWrapping="Wrap" Margin="0,0,0,4"/>
                  <TextBlock x:Name="TxtRecBatParams" Text="电池：—" Foreground="{DynamicResource TextSecondary}" TextWrapping="Wrap" Margin="0,0,0,10"/>
                  <TextBlock x:Name="TxtRecNote" Text="软件近似观感，非官方 ICC。" Foreground="{DynamicResource TextMuted}" TextWrapping="Wrap" FontSize="12"/>
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
                    <TextBlock x:Name="TxtBright" Text="90" HorizontalAlignment="Right" Foreground="{DynamicResource Accent}" FontWeight="Light"/>
                  </Grid>
                  <Slider x:Name="SlBright" Minimum="0" Maximum="100" Value="90"
                          SmallChange="1" LargeChange="5"/>
                </StackPanel>
              </Border>
              <Border Grid.Column="2" Style="{StaticResource Card}">
                <StackPanel>
                  <Grid>
                    <TextBlock x:Name="TxtContrastLabel" Text="对比度" Style="{StaticResource FieldTitle}"/>
                    <TextBlock x:Name="TxtContrast" Text="50" HorizontalAlignment="Right" Foreground="{DynamicResource Accent}" FontWeight="Light"/>
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
                    <TextBlock x:Name="TxtGamma" Text="1.00" HorizontalAlignment="Right" Foreground="{DynamicResource Accent}" FontWeight="Light"/>
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
                    <TextBlock x:Name="TxtScale" Text="1.00" HorizontalAlignment="Right" Foreground="{DynamicResource Accent}" FontWeight="Light"/>
                  </Grid>
                  <TextBlock x:Name="TxtScaleHint" Text="整体明暗倍率，可细调" Foreground="{DynamicResource TextSecondary}" FontSize="12" Margin="0,2,0,0"/>
                  <Slider x:Name="SlScale" Minimum="0.70" Maximum="1.10" Value="1.0"
                          SmallChange="0.01" LargeChange="0.05"/>
                </StackPanel>
              </Border>
            </Grid>
          </StackPanel>
        </ScrollViewer>
      </TabItem>

      <!-- 字体 -->
      <TabItem x:Name="TabFont" Header="字体">
        <ScrollViewer Style="{StaticResource ThinScrollViewer}" Margin="0,12,0,0">
          <StackPanel>
            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock x:Name="TxtClearTypeTitle" Text="ClearType 字体平滑" Style="{StaticResource SectionTitle}"/>
                <TextBlock x:Name="TxtClearTypeDesc" Text="这是 Windows 系统级字体渲染。调整后部分程序需重新打开才完全生效。" TextWrapping="Wrap" Foreground="{DynamicResource TextSecondary}" Margin="0,4,0,12"/>
                <CheckBox x:Name="ChkClearType" Content="启用 ClearType" IsChecked="True" Margin="0,0,0,12"/>
                <Grid>
                  <TextBlock x:Name="TxtFontGammaLabel" Text="字体平滑伽马" Style="{StaticResource FieldTitle}"/>
                  <TextBlock x:Name="TxtFontGamma" Text="1.40" HorizontalAlignment="Right" Foreground="{DynamicResource Accent}" FontWeight="Light"/>
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
                <Border Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource CardBorder}" BorderThickness="1" CornerRadius="8" Padding="14">
                  <StackPanel>
                    <TextBlock x:Name="TxtPreviewSample" FontSize="22" FontWeight="Light" Text="屏幕与字体调节 ClearyDisplay"/>
                    <TextBlock FontSize="15" Margin="0,8,0,0" Text="The quick brown fox jumps over the lazy dog. 0123456789"/>
                    <TextBlock x:Name="TxtPreviewZh" FontSize="14" Margin="0,8,0,0" TextWrapping="Wrap"
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
        <ScrollViewer Style="{StaticResource ThinScrollViewer}" Margin="0,12,0,0">
          <StackPanel>
            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock x:Name="TxtThemeTitle" Text="外观主题" Style="{StaticResource SectionTitle}"/>
                <TextBlock x:Name="TxtThemeHint" Text="选择 Apple Native、Windows 11 Mica / Acrylic、Gitcode 风格，或跟随 Windows 系统。" Foreground="{DynamicResource TextSecondary}" TextWrapping="Wrap" Margin="0,4,0,16"/>

                <Border x:Name="BdThemeApple" CornerRadius="12" BorderThickness="2" Padding="16" Margin="0,0,0,10" Cursor="Hand"
                        BorderBrush="{DynamicResource Accent}" Background="{DynamicResource AccentSoft}">
                  <Grid>
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="Auto"/>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <Border Width="40" Height="40" CornerRadius="20" Background="#F5F5F7" BorderBrush="#D2D2D7" BorderThickness="1" Margin="0,0,14,0">
                      <TextBlock x:Name="TxtThemeAppleShort" Text="苹" FontSize="16" FontWeight="Light" HorizontalAlignment="Center" VerticalAlignment="Center" Foreground="#1D1D1F"/>
                    </Border>
                    <StackPanel Grid.Column="1" VerticalAlignment="Center">
                      <TextBlock x:Name="TxtThemeAppleName" Text="Apple Native" FontSize="15" FontWeight="SemiBold"/>
                      <TextBlock x:Name="TxtThemeAppleDesc" Text="macOS Big Sur 风：干净中性白、SF 系统字体观感、柔和分隔线" Foreground="{DynamicResource TextSecondary}" Margin="0,2,0,0" TextWrapping="Wrap"/>
                    </StackPanel>
                    <TextBlock x:Name="TxtThemeAppleMark" Grid.Column="2" Text="✓" FontSize="18" Foreground="{DynamicResource Accent}" VerticalAlignment="Center"/>
                  </Grid>
                </Border>

                <Border x:Name="BdThemeMica" CornerRadius="12" BorderThickness="1" Padding="16" Margin="0,0,0,10" Cursor="Hand"
                        BorderBrush="{DynamicResource CardBorder}" Background="{DynamicResource CardBg}">
                  <Grid>
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="Auto"/>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <Border Width="40" Height="40" CornerRadius="20" Background="#F3F3F3" BorderBrush="#E0E0E0" BorderThickness="1" Margin="0,0,14,0">
                      <TextBlock x:Name="TxtThemeMicaShort" Text="M" FontSize="16" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center" Foreground="#0078D4"/>
                    </Border>
                    <StackPanel Grid.Column="1" VerticalAlignment="Center">
                      <TextBlock x:Name="TxtThemeMicaName" Text="Windows 11 Mica" FontSize="15" FontWeight="SemiBold"/>
                      <TextBlock x:Name="TxtThemeMicaDesc" Text="Win11 原生云母：微妙桌面取色、Segoe UI 观感、卡片半透叠加桌面" Foreground="{DynamicResource TextSecondary}" Margin="0,2,0,0" TextWrapping="Wrap"/>
                    </StackPanel>
                    <TextBlock x:Name="TxtThemeMicaMark" Grid.Column="2" Text="" FontSize="18" Foreground="{DynamicResource Accent}" VerticalAlignment="Center"/>
                  </Grid>
                </Border>

                <Border x:Name="BdThemeAcrylic" CornerRadius="12" BorderThickness="1" Padding="16" Margin="0,0,0,10" Cursor="Hand"
                        BorderBrush="{DynamicResource CardBorder}" Background="{DynamicResource CardBg}">
                  <Grid>
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="Auto"/>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <Border Width="40" Height="40" CornerRadius="20" Background="#ECECEC" BorderBrush="#C8C8C8" BorderThickness="1" Margin="0,0,14,0">
                      <TextBlock x:Name="TxtThemeAcrylicShort" Text="A" FontSize="16" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center" Foreground="#0078D4"/>
                    </Border>
                    <StackPanel Grid.Column="1" VerticalAlignment="Center">
                      <TextBlock x:Name="TxtThemeAcrylicName" Text="Windows 11 Acrylic" FontSize="15" FontWeight="SemiBold"/>
                      <TextBlock x:Name="TxtThemeAcrylicDesc" Text="Win11 亚克力：高斯模糊背景 + 微高光，类开始菜单/操作中心玻璃质感" Foreground="{DynamicResource TextSecondary}" Margin="0,2,0,0" TextWrapping="Wrap"/>
                    </StackPanel>
                    <TextBlock x:Name="TxtThemeAcrylicMark" Grid.Column="2" Text="" FontSize="18" Foreground="{DynamicResource Accent}" VerticalAlignment="Center"/>
                  </Grid>
                </Border>

                <Border x:Name="BdThemeGitcode" CornerRadius="12" BorderThickness="1" Padding="16" Margin="0,0,0,10" Cursor="Hand"
                        BorderBrush="{DynamicResource CardBorder}" Background="{DynamicResource CardBg}">
                  <Grid>
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="Auto"/>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <Border Width="40" Height="40" CornerRadius="20" Background="#0D1117" BorderBrush="#30363D" BorderThickness="1" Margin="0,0,14,0">
                      <TextBlock x:Name="TxtThemeGitcodeShort" Text="G" FontSize="16" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center" Foreground="#2EA043"/>
                    </Border>
                    <StackPanel Grid.Column="1" VerticalAlignment="Center">
                      <TextBlock x:Name="TxtThemeGitcodeName" Text="Gitcode" FontSize="15" FontWeight="SemiBold"/>
                      <TextBlock x:Name="TxtThemeGitcodeDesc" Text="GitHub 暗色 IDE 风：深色卡片 + 绿色重音，长时间编码更护眼" Foreground="{DynamicResource TextSecondary}" Margin="0,2,0,0" TextWrapping="Wrap"/>
                    </StackPanel>
                    <TextBlock x:Name="TxtThemeGitcodeMark" Grid.Column="2" Text="" FontSize="18" Foreground="{DynamicResource Accent}" VerticalAlignment="Center"/>
                  </Grid>
                </Border>

                <Border x:Name="BdThemeSystem" CornerRadius="12" BorderThickness="1" Padding="16" Cursor="Hand"
                        BorderBrush="{DynamicResource CardBorder}" Background="{DynamicResource CardBg}">
                  <Grid>
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="Auto"/>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <Border Width="40" Height="40" CornerRadius="20" Background="#EEF6FF" BorderBrush="#0078D4" BorderThickness="1" Margin="0,0,14,0">
                      <TextBlock x:Name="TxtThemeSysShort" Text="自" FontSize="16" FontWeight="Light" HorizontalAlignment="Center" VerticalAlignment="Center" Foreground="#0078D4"/>
                    </Border>
                    <StackPanel Grid.Column="1" VerticalAlignment="Center">
                      <TextBlock x:Name="TxtThemeSysName" Text="跟随系统" FontSize="15" FontWeight="SemiBold"/>
                      <TextBlock x:Name="TxtThemeSysDesc" Text="自动跟随 Windows「深色 / 浅色」模式（同时切换 Apple Native 风格）" Foreground="{DynamicResource TextSecondary}" Margin="0,2,0,0" TextWrapping="Wrap"/>
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

    <Border Grid.Row="2" Margin="0,8,0,0" Padding="4,10,4,0">
      <Grid>
        <TextBlock x:Name="TxtFooterHint" VerticalAlignment="Center" HorizontalAlignment="Left"
                   Foreground="{DynamicResource TextMuted}" FontSize="12" IsHitTestVisible="False"
                   Text="左右并排调节 · 拖动滑块实时预览 ·「立即应用」写入配置"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
          <Button x:Name="BtnReset" Style="{StaticResource GhostBtn}" Content="重置本档" Margin="0,0,8,0"/>
          <Button x:Name="BtnApply" Style="{StaticResource GhostBtn}" Content="立即应用" Margin="0,0,8,0"/>
          <Button x:Name="BtnSaveClose" Style="{StaticResource PrimaryBtn}" Content="保存并关闭"/>
        </StackPanel>
      </Grid>
    </Border>
  </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)
if (-not $window) { throw 'XAML 加载失败，窗口为空' }

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
foreach ($n in @('TxtStatus','SlBright','BtnApply','BdThemeApple','CmbPreset')) {
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
$BdRecGeneric = $window.FindName('BdRecGeneric')
$TxtRecApple = $window.FindName('TxtRecApple')
$TxtRecLg = $window.FindName('TxtRecLg')
$TxtRecHuawei = $window.FindName('TxtRecHuawei')
$TxtRecAsus = $window.FindName('TxtRecAsus')
$TxtRecGeneric = $window.FindName('TxtRecGeneric')
$TxtRecTitle = $window.FindName('TxtRecTitle')
$TxtRecTarget = $window.FindName('TxtRecTarget')
$TxtRecAcParams = $window.FindName('TxtRecAcParams')
$TxtRecBatParams = $window.FindName('TxtRecBatParams')
$TxtRecNote = $window.FindName('TxtRecNote')
$BdThemeApple = $window.FindName('BdThemeApple')
$BdThemeMica = $window.FindName('BdThemeMica')
$BdThemeAcrylic = $window.FindName('BdThemeAcrylic')
$BdThemeGitcode = $window.FindName('BdThemeGitcode')
$BdThemeSystem = $window.FindName('BdThemeSystem')
$TxtThemeHint = $window.FindName('TxtThemeHint')
$TxtThemeAppleShort = $window.FindName('TxtThemeAppleShort')
$TxtThemeAppleName = $window.FindName('TxtThemeAppleName')
$TxtThemeAppleDesc = $window.FindName('TxtThemeAppleDesc')
$TxtThemeAppleMark = $window.FindName('TxtThemeAppleMark')
$TxtThemeMicaShort = $window.FindName('TxtThemeMicaShort')
$TxtThemeMicaName = $window.FindName('TxtThemeMicaName')
$TxtThemeMicaDesc = $window.FindName('TxtThemeMicaDesc')
$TxtThemeMicaMark = $window.FindName('TxtThemeMicaMark')
$TxtThemeAcrylicShort = $window.FindName('TxtThemeAcrylicShort')
$TxtThemeAcrylicName = $window.FindName('TxtThemeAcrylicName')
$TxtThemeAcrylicDesc = $window.FindName('TxtThemeAcrylicDesc')
$TxtThemeAcrylicMark = $window.FindName('TxtThemeAcrylicMark')
$TxtThemeGitcodeShort = $window.FindName('TxtThemeGitcodeShort')
$TxtThemeGitcodeName = $window.FindName('TxtThemeGitcodeName')
$TxtThemeGitcodeDesc = $window.FindName('TxtThemeGitcodeDesc')
$TxtThemeGitcodeMark = $window.FindName('TxtThemeGitcodeMark')
$TxtThemeSysShort = $window.FindName('TxtThemeSysShort')
$TxtThemeSysName = $window.FindName('TxtThemeSysName')
$TxtThemeSysDesc = $window.FindName('TxtThemeSysDesc')
$TxtThemeSystemMark = $window.FindName('TxtThemeSystemMark')

$script:timer = New-Object System.Windows.Threading.DispatcherTimer
$script:timer.Interval = [TimeSpan]::FromMilliseconds(180)
$script:themeWatch = New-Object System.Windows.Threading.DispatcherTimer
$script:themeWatch.Interval = [TimeSpan]::FromSeconds(2)
$script:lastSystemLight = $null

function Update-PowerStatus {
  if (-not $TxtStatus) { return }
  if (Get-IsOnAc) { $TxtStatus.Text = (T 'statusAc') }
  else { $TxtStatus.Text = (T 'statusBat') }
}

function Is-EditingActive {
  $onAc = Get-IsOnAc
  if ($RbAc -and $RbAc.IsChecked) { return [bool]$onAc }
  return (-not $onAc)
}

function Get-EditingProfile {
  if ($RbAc -and $RbAc.IsChecked) { return $profiles.ac }
  return $profiles.battery
}

function Set-SlidersFromProfile($p) {
  if (-not $p) { return }
  $script:loading = $true
  try {
    if ($SlBright) { $SlBright.Value = [double]$p.brightness }
    if ($SlContrast) { $SlContrast.Value = [double]$p.contrast }
    if ($SlGamma) { $SlGamma.Value = [double]$p.gammaPower }
    if ($SlScale) { $SlScale.Value = [double]$p.scale }
  } finally {
    $script:loading = $false
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
  if (-not (Is-EditingActive)) {
    if ($TxtReadback) { $TxtReadback.Text = (T 'previewPaused') }
    return
  }
  try {
    # 拖动时完整预览（伽马即时；亮度/对比度也写入，失败不中断）
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

if ($BdThemeApple) { $BdThemeApple.Add_MouseLeftButtonUp({ Apply-UiTheme 'apple' }) }
if ($BdThemeMica) { $BdThemeMica.Add_MouseLeftButtonUp({ Apply-UiTheme 'mica' }) }
if ($BdThemeAcrylic) { $BdThemeAcrylic.Add_MouseLeftButtonUp({ Apply-UiTheme 'acrylic' }) }
if ($BdThemeGitcode) { $BdThemeGitcode.Add_MouseLeftButtonUp({ Apply-UiTheme 'gitcode' }) }
if ($BdThemeSystem) { $BdThemeSystem.Add_MouseLeftButtonUp({ Apply-UiTheme 'system' }) }

if ($BdLang) { $BdLang.Add_MouseLeftButtonUp({ Toggle-UiLanguage }) }
if ($BdRecApple) { $BdRecApple.Add_MouseLeftButtonUp({ Apply-Recommend 'apple' }) }
if ($BdRecLg) { $BdRecLg.Add_MouseLeftButtonUp({ Apply-Recommend 'lg' }) }
if ($BdRecHuawei) { $BdRecHuawei.Add_MouseLeftButtonUp({ Apply-Recommend 'huawei' }) }
if ($BdRecAsus) { $BdRecAsus.Add_MouseLeftButtonUp({ Apply-Recommend 'asus' }) }
if ($BdRecGeneric) { $BdRecGeneric.Add_MouseLeftButtonUp({ Apply-Recommend 'generic' }) }

if ($script:themeWatch) {
  $script:themeWatch.Add_Tick({
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

if ($BtnReset) {
  $BtnReset.Add_Click({
    if ($SlBright) { $SlBright.Value=90 }
    if ($SlContrast) { $SlContrast.Value=50 }
    if ($SlGamma) { $SlGamma.Value=1.0 }
    if ($SlScale) { $SlScale.Value=1.0 }
    Persist-Sliders; Update-ValueLabels; Apply-If-Active
  })
}

if ($BtnApply) {
  $BtnApply.Add_Click({
    try {
      Persist-Sliders
      # 1) 先应用显示效果（亮度/对比度/伽马/缩放）
      $r = Apply-DisplayValues $SlBright.Value $SlContrast.Value $SlGamma.Value $SlScale.Value
      # 2) 再应用字体效果（ClearType/字体伽马/子像素），无论用户在哪个 Tab
      $fontOk = $true
      try {
        $en = if ($ChkClearType) { [bool]$ChkClearType.IsChecked } else { $true }
        $ori = if ($RbRgb -and $RbRgb.IsChecked) { 1 } else { 0 }
        $fg = if ($SlFontGamma) { [double]$SlFontGamma.Value } else { 1.4 }
        Set-FontSmoothingSettings $en $fg $ori
      } catch { $fontOk = $false }
      # 3) 最后保存配置（保存失败不影响显示与字体效果）
      try { Save-ActiveProfiles $profiles } catch {}
      $mode = if ($RbAc -and $RbAc.IsChecked) { T 'modeAc' } else { T 'modeBat' }
      $okB = ($r.Brightness -ge 0)
      $okC = ($r.Contrast -ge 0)
      if ($okB -or $okC) {
        Flash-Status (TF 'appliedFmt' $mode $SlBright.Value $SlContrast.Value $SlGamma.Value $SlScale.Value)
      } else {
        Flash-Status (TF 'appliedGammaOnly' $mode)
      }
      if (-not $fontOk) { Flash-Status (T 'fontApplyPartial') }
    } catch {
      [System.Windows.MessageBox]::Show((T 'initFail') + $_.Exception.Message, (T 'appTitle'))
    }
  })
}

if ($BtnSaveClose) {
  $BtnSaveClose.Add_Click({
    try {
      Persist-Sliders
      $use = if (Get-IsOnAc) { $profiles.ac } else { $profiles.battery }
      Apply-DisplayValues $use.brightness $use.contrast $use.gammaPower $use.scale
      try {
        $en = if ($ChkClearType) { [bool]$ChkClearType.IsChecked } else { $true }
        $ori = if ($RbRgb -and $RbRgb.IsChecked) { 1 } else { 0 }
        $fg = if ($SlFontGamma) { [double]$SlFontGamma.Value } else { 1.4 }
        Set-FontSmoothingSettings $en $fg $ori
      } catch {}
      try { Save-ActiveProfiles $profiles } catch {}
      $window.Close()
    } catch {
      [System.Windows.MessageBox]::Show((T 'initFail') + $_.Exception.Message, (T 'appTitle'))
    }
  })
}

$window.Add_Loaded({
  try {
    $script:loading = $true
    Apply-UiTheme $script:uiSettings.theme
    Apply-UiLanguage (Get-UiLang) $false
    Update-RecommendBadgeStyles
    Update-RecommendDetailPanel
    Update-PowerStatus
    if ($CmbPreset) { Refresh-PresetCombo $null }
    if (Get-IsOnAc) {
      if ($RbAc) { $RbAc.IsChecked = $true }
      if ($profiles.ac) { Set-SlidersFromProfile $profiles.ac }
    } else {
      if ($RbBat) { $RbBat.IsChecked = $true }
      if ($profiles.battery) { Set-SlidersFromProfile $profiles.battery }
    }
    Update-ValueLabels
    $script:loading = $false
    $script:lastSystemLight = Get-SystemIsLight
    if ($script:themeWatch) { $script:themeWatch.Start() }

    $script:deferTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:deferTimer.Interval = [TimeSpan]::FromMilliseconds(400)
    $script:deferTimer.Add_Tick({
      try { $script:deferTimer.Stop() } catch {}
      try {
        if ($SlGamma -and $SlScale -and (Is-EditingActive)) {
          Apply-Gamma ([double]$SlGamma.Value) ([double]$SlScale.Value)
          if ($TxtReadback) {
            $TxtReadback.Text = (T 'readyApply')
          }
        }
      } catch {
        if ($TxtReadback) { $TxtReadback.Text = (T 'readyNoPreview') }
      }
    })
    $script:deferTimer.Start()
  } catch {
    $script:loading = $false
    [System.Windows.MessageBox]::Show(((T 'initFail') + $_.Exception.Message), (T 'appTitle'))
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
