# ClearyDisplay - apply AC/Battery profile + font to ALL attached displays (logon / power change)
#
# 触发方式：HKCU\...\Run 中的 ClearyDisplayApply -> ApplyProfile.cmd -Force
#
# 本脚本与主程序 GammaTuner.ps1 是两条独立链路，但共用同一份配置：
#   presets.json     命名方案（ac / battery 两套子档位）
#   env-binds.json   环境绑定（显示器 + 网络 -> 方案名）
#   dim-profile.json 最后保存的活动档位（环境匹配失败时的回退）
#
# 关键约定：环境指纹算法必须与主程序保持一致，否则会出现
# 「开机套用 A 方案、打开界面又跳成 B 方案」的错位。
# 差异点：此处改用 EnumDisplayDevices 取显示器 ID，不用 WMI——
# 本机 wmiprvse 会被第三方 WMI 提供程序拖崩，登录瞬间更不能冒险。
param([switch]$Force)

$ErrorActionPreference = 'SilentlyContinue'
$logDir          = Join-Path $env:LOCALAPPDATA 'ClearyDisplay'
$logFile         = Join-Path $logDir 'apply.log'
$envLogFile      = Join-Path $logDir 'env-switch.log'
$profilePath     = Join-Path $logDir 'dim-profile.json'
$presetsPath     = Join-Path $logDir 'presets.json'
$envBindsPath    = Join-Path $logDir 'env-binds.json'
$uiSettingsPath  = Join-Path $logDir 'ui-settings.json'

function Write-Log([string]$msg) {
  $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
  Add-Content -Path $logFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
}

function Write-EnvLog([string]$msg) {
  # 与主程序共用同一份环境切换审计日志，便于按时间线对照两条链路
  try {
    Add-Content -LiteralPath $envLogFile -Value ((Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + '  [开机自启] ' + $msg) -Encoding UTF8
    $f = Get-Item -LiteralPath $envLogFile -ErrorAction SilentlyContinue
    if ($f -and $f.Length -gt 200000) {
      $keep = @(Get-Content -LiteralPath $envLogFile -Encoding UTF8 | Select-Object -Last 800)
      Set-Content -LiteralPath $envLogFile -Value $keep -Encoding UTF8
    }
  } catch {}
}

function Get-IsOnAc {
  # ACLineStatus: 0=Offline, 1=Online, 255=Unknown
  # 注意：不要走 WMI (Win32_Battery) 回退——本机 wmiprvse 会被第三方 WMI 提供程序
  # (Foxit Print-to-Evernote fenvpr_ui.dll) 拖崩，导致查询超时/失败（"断开"根因之一）。
  # GetSystemPowerStatus 是 kernel32 直调，稳定可靠；失败时按台式机惯例视为接电。
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
  return $true
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
  // IntPtr overload: PowerShell turns $null into "" for string params, which breaks adapter enumeration
  [DllImport("user32.dll", CharSet=CharSet.Unicode, EntryPoint="EnumDisplayDevices")] public static extern bool EnumDisplayDevicesPtr(IntPtr lpDevice, uint iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, uint dwFlags);
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

# =====================================================================
#  环境指纹 —— 与 GammaTuner.ps1 的 Get-EnvDisplays / Get-EnvNetwork 等价
# =====================================================================

function Get-EnvDisplayId {
  # 从 MONITOR\IOC9193\{GUID}\0002 里取中间那段（如 IOC9193），
  # 与主程序用 WmiMonitorID 拼出的 ManufacturerName + ProductCodeID 结果一致。
  $ids = New-Object System.Collections.ArrayList
  $lbs = New-Object System.Collections.ArrayList
  try {
    for ($dev = 0; $dev -lt 16; $dev++) {
      $dd = New-Object ClearyDisplayApply+DISPLAY_DEVICE
      $dd.cb = [Runtime.InteropServices.Marshal]::SizeOf($dd)
      if (-not [ClearyDisplayApply]::EnumDisplayDevicesPtr([IntPtr]::Zero, [uint32]$dev, [ref]$dd, 0)) { break }
      if (($dd.StateFlags -band [ClearyDisplayApply]::DISPLAY_DEVICE_ATTACHED_TO_DESKTOP) -eq 0) { continue }
      for ($m = 0; $m -lt 8; $m++) {
        $md = New-Object ClearyDisplayApply+DISPLAY_DEVICE
        $md.cb = [Runtime.InteropServices.Marshal]::SizeOf($md)
        if (-not [ClearyDisplayApply]::EnumDisplayDevices([string]$dd.DeviceName, [uint32]$m, [ref]$md, 0)) { break }
        $seg = @(([string]$md.DeviceID) -split '\\')
        if ($seg.Count -lt 2) { continue }
        $code = ([string]$seg[1]).Trim()
        if (-not $code) { continue }
        [void]$ids.Add($code)
        $nm = ([string]$md.DeviceString).Trim()
        [void]$lbs.Add($(if ($nm) { $nm } else { $code }))
      }
    }
  } catch {}
  $u = @($ids | Sort-Object -Unique)
  $v = @($lbs | Sort-Object -Unique)
  return [pscustomobject]@{ key = ($u -join '+'); label = ($v -join ' + '); count = $u.Count }
}

function Get-EnvNetwork {
  $o = [ordered]@{ wifi = ''; ipseg = ''; kind = 'none'; label = '' }
  try {
    foreach ($ni in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
      if ($ni.OperationalStatus -ne 'Up') { continue }
      if ($ni.NetworkInterfaceType -eq 'Loopback') { continue }
      $ips = @()
      try {
        $ips = @($ni.GetIPProperties().UnicastAddresses |
          Where-Object { $_.Address.AddressFamily -eq 'InterNetwork' } |
          ForEach-Object { $_.Address.IPAddressToString } |
          Where-Object { $_ -and ($_ -notlike '169.254.*') })
      } catch {}
      if ($ips.Count -eq 0) { continue }
      $seg = ($ips[0] -split '\.')[0..2] -join '.'
      if ($ni.NetworkInterfaceType -eq 'Wireless80211') { $o.kind = 'wifi' }
      elseif ($o.kind -eq 'none') { $o.kind = 'ethernet' }
      if (-not $o.ipseg) { $o.ipseg = $seg }
    }
  } catch {}
  if ($o.kind -eq 'wifi') {
    try {
      $w = (& netsh.exe wlan show interfaces) 2>$null | Out-String
      foreach ($l in ($w -split "`r?`n")) {
        if ($l -match '^\s*SSID\s*:\s*(\S.*)$') { $o.wifi = $Matches[1].Trim(); break }
      }
    } catch {}
  }
  if ($o.wifi) { $o.label = $o.wifi }
  elseif ($o.ipseg) { $o.label = $(if ($o.kind -eq 'wifi') { 'Wi-Fi ' } else { '有线 ' }) + $o.ipseg + '.x' }
  return [pscustomobject]$o
}

function Get-EnvFingerprint {
  $d = Get-EnvDisplayId
  $n = Get-EnvNetwork
  $parts = @()
  if ($d.key) { $parts += $d.key }
  if ($n.label) { $parts += $n.label }
  return [pscustomobject]@{
    display  = [string]$d.key
    wifi     = [string]$n.wifi
    ipseg    = [string]$n.ipseg
    kind     = [string]$n.kind
    netLabel = [string]$n.label
    label    = ($parts -join ' · ')
  }
}

function Load-EnvBinds {
  $d = @{ enabled = $false; autoApply = $true; binds = @() }
  try {
    if (Test-Path $envBindsPath) {
      $j = Get-Content $envBindsPath -Raw -Encoding UTF8 | ConvertFrom-Json
      if ($null -ne $j.enabled)   { $d.enabled   = [bool]$j.enabled }
      if ($null -ne $j.autoApply) { $d.autoApply = [bool]$j.autoApply }
      $b = New-Object System.Collections.ArrayList
      foreach ($x in @($j.binds)) {
        if (-not $x -or -not $x.preset) { continue }
        [void]$b.Add([ordered]@{
          preset  = [string]$x.preset
          display = [string]$x.display
          wifi    = [string]$x.wifi
          ipseg   = [string]$x.ipseg
          label   = [string]$x.label
        })
      }
      $d.binds = @($b)
    }
  } catch {}
  return $d
}

function Find-EnvMatch($fp, $binds) {
  $best = $null; $bestScore = 0
  foreach ($b in @($binds)) {
    $score = 0
    if ($b.display -and $fp.display -and ($b.display -eq $fp.display)) { $score += 2 }
    if ($b.wifi    -and $fp.wifi    -and ($b.wifi    -eq $fp.wifi))    { $score += 2 }
    if ($b.ipseg   -and $fp.ipseg   -and ($b.ipseg   -eq $fp.ipseg))   { $score += 1 }
    if ($score -gt $bestScore) { $bestScore = $score; $best = $b }
  }
  if ($best -and $bestScore -ge 2) { return [pscustomobject]@{ Bind = $best; Score = $bestScore } }
  return $null
}

# =====================================================================
#  决定用哪一组档位：环境方案优先，失败回退 dim-profile.json
# =====================================================================

$onAc = Get-IsOnAc
$sub  = $(if ($onAc) { 'ac' } else { 'battery' })
$srcName   = 'dim-profile.json'
$srcDetail = '上次保存的档位'
$node      = $null
$matchedPreset = ''

try {
  $eb = Load-EnvBinds
  if ($eb.enabled -and $eb.autoApply -and (@($eb.binds).Count -gt 0)) {
    $fp = Get-EnvFingerprint
    $m = Find-EnvMatch $fp $eb.binds
    if ($m) {
      $pn = [string]$m.Bind.preset
      $presets = $null
      if (Test-Path $presetsPath) {
        try { $presets = Get-Content $presetsPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
      }
      $p = $null
      if ($presets) {
        foreach ($prop in @($presets.PSObject.Properties)) {
          if ([string]$prop.Name -eq $pn) { $p = $prop.Value; break }
        }
      }
      if ($p -and ($p.ac -or $p.battery)) {
        $node = $(if ($onAc) { $p.ac } else { $p.battery })
        if (-not $node) { $node = $(if ($onAc) { $p.battery } else { $p.ac }) }
        $matchedPreset = $pn
        $srcName   = '环境方案「' + $pn + '」'
        $srcDetail = '匹配分 ' + $m.Score
        Write-EnvLog ('套用方案「' + $pn + '」　匹配分 ' + $m.Score + '　子档位 ' + $sub + '　指纹：' + $fp.label + '　绑定标签：' + $m.Bind.label)
      } else {
        Write-EnvLog ('匹配到「' + $pn + '」但 presets.json 中无该方案，回退 dim-profile.json　指纹：' + $fp.label)
      }
    } else {
      Write-EnvLog ('未匹配到任何环境方案，回退 dim-profile.json　当前指纹：' + $fp.label)
    }
  }
} catch {
  Write-EnvLog ('环境匹配异常，回退 dim-profile.json：' + $_.Exception.Message)
}

$brightness = 90
$contrast   = 50
$gammaPower = 1.0
$scale      = 1.0

if ($node) {
  if ($null -ne $node.brightness) { $brightness = [int]$node.brightness }
  if ($null -ne $node.contrast)   { $contrast   = [int]$node.contrast }
  if ($null -ne $node.gammaPower) { $gammaPower = [double]$node.gammaPower }
  if ($null -ne $node.scale)      { $scale      = [double]$node.scale }
} elseif (Test-Path $profilePath) {
  try {
    $j = Get-Content $profilePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $n2 = $(if ($onAc) { $j.ac } else { $j.battery })
    if (-not $n2 -and $j.brightness) { $n2 = $j }
    if ($n2) {
      if ($null -ne $n2.brightness) { $brightness = [int]$n2.brightness }
      if ($null -ne $n2.contrast)   { $contrast   = [int]$n2.contrast }
      if ($null -ne $n2.gammaPower) { $gammaPower = [double]$n2.gammaPower }
      if ($null -ne $n2.scale)      { $scale      = [double]$n2.scale }
    }
  } catch {}
}

# 用环境方案写屏后，顺手把活动档位同步回 dim-profile.json，
# 这样下次环境匹配失败时回退到的就是最近一次真实生效的值。
if ($matchedPreset) {
  try {
    $presets2 = Get-Content $presetsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $p2 = $null
    foreach ($prop in @($presets2.PSObject.Properties)) {
      if ([string]$prop.Name -eq $matchedPreset) { $p2 = $prop.Value; break }
    }
    if ($p2 -and $p2.ac -and $p2.battery) {
      $obj = [ordered]@{
        ac      = [ordered]@{ brightness = [int]$p2.ac.brightness;      contrast = [int]$p2.ac.contrast;      gammaPower = [math]::Round([double]$p2.ac.gammaPower,2);      scale = [math]::Round([double]$p2.ac.scale,2) }
        battery = [ordered]@{ brightness = [int]$p2.battery.brightness; contrast = [int]$p2.battery.contrast; gammaPower = [math]::Round([double]$p2.battery.gammaPower,2); scale = [math]::Round([double]$p2.battery.scale,2) }
      }
      ($obj | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $profilePath -Encoding UTF8
    }
  } catch {}
}

# =====================================================================
#  写硬件：软件伽马 -> DDC/CI 亮度对比度 -> 电源方案 -> ClearType
# =====================================================================

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
  if (-not [ClearyDisplayApply]::EnumDisplayDevicesPtr([IntPtr]::Zero, [uint32]$dev, [ref]$dd, 0)) { break }
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
  if (-not [ClearyDisplayApply]::GetPhysicalMonitorsFromHMONITOR($hMon,$n,$arr)) {
    Write-Log ('DDC open failed for one monitor (err=' + [Runtime.InteropServices.Marshal]::GetLastWin32Error() + ')')
    continue
  }
  try {
    for ($i = 0; $i -lt $n; $i++) {
      $ph = $arr[$i].hPhysicalMonitor
      # DDC/CI over I2C is slow: give the monitor settle time, retry once on failure
      $okB = [ClearyDisplayApply]::SetMonitorBrightness($ph, [uint32]$brightness)
      if (-not $okB) { Start-Sleep -Milliseconds 120; $okB = [ClearyDisplayApply]::SetMonitorBrightness($ph, [uint32]$brightness) }
      Start-Sleep -Milliseconds 50
      $okC = [ClearyDisplayApply]::SetMonitorContrast($ph, [uint32]$contrast)
      if (-not $okC) { Start-Sleep -Milliseconds 120; $okC = [ClearyDisplayApply]::SetMonitorContrast($ph, [uint32]$contrast) }
      Start-Sleep -Milliseconds 50
      $min=0;$c=0;$max=0
      if ([ClearyDisplayApply]::GetMonitorBrightness($ph,[ref]$min,[ref]$c,[ref]$max)) { $cur = [int]$c }
      if (-not ($okB -or $okC)) { Write-Log ('DDC write unresponsive on physical monitor ' + $i) }
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

Write-Log ("Applied ALL displays src={0} ({1}) sub={2} onAc={3} bright={4} contrast={5} readback={6} gamma={7} scale={8} gammaDevs={9} ddc={10} fontG={11}" -f $srcName, $srcDetail, $sub, $onAc, $brightness, $contrast, $cur, $gammaPower, $scale, $gammaOk, $ddcCount, $fontGamma)
exit 0
