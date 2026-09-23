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
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
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
  // IntPtr overload: PowerShell turns $null into "" for string params, breaking adapter enumeration
  [DllImport("user32.dll", CharSet=CharSet.Unicode, EntryPoint="EnumDisplayDevices")] public static extern bool EnumDisplayDevicesPtr(IntPtr lpDevice, uint iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, uint dwFlags);
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
  public const uint SPI_GETFONTSMOOTHINGTYPE = 0x200A;
  // Correct values per winuser.h (were wrong: gamma used 0x200C/D which are CONTRAST,
  // orientation used 0x2012/3 which are undefined). Fixed 2026-09-07.
  public const uint SPI_GETFONTSMOOTHINGCONTRAST = 0x200C;
  public const uint SPI_SETFONTSMOOTHINGCONTRAST = 0x200D;
  public const uint SPI_GETFONTSMOOTHINGGAMMA = 0x200E;
  public const uint SPI_SETFONTSMOOTHINGGAMMA = 0x200F;
  public const uint SPI_GETFONTSMOOTHINGORIENTATION = 0x2010;
  public const uint SPI_SETFONTSMOOTHINGORIENTATION = 0x2011;
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
# >>> BG_KERNEL_BEGIN  (generated by _embed_kernel.py - do not edit by hand)
# ---------------------------------------------------------------------------
# 去背景图像内核（纯 C#，零外部依赖，不需要 Python / numpy / 外部进程）
#
# 为什么内嵌源码：ps2exe 产出的是单文件 exe，运行期目录下没有 bg_filter.cs /
# bg_trace.cs，因此只能用 Add-Type -TypeDefinition 从内联源码字符串编译。
#
# 为什么惰性编译：源码约 58KB，CodeDom 编译需要一两百毫秒，放在启动路径上会
# 明显拖慢开窗；改成首次进入「画图」页时才编译，之后命中类型缓存直接返回。
#
# 源码经 _embed_kernel.py 校验：纯 ASCII、无 here-string 终止符、无 C# 6/7 语法。
# 用单引号 here-string 装载，杜绝任何变量插值风险。
# ---------------------------------------------------------------------------
$script:BG_CS_SRC = @'
// =====================================================================
// ClearyBg kernel - merged for inlining into GammaTuner.ps1
// Generated by _embed_kernel.py from: bg_filter.cs, bg_trace.cs
// using directives hoisted here: C# requires them before any type
// declaration (CS1529), which concatenation would otherwise violate.
// =====================================================================
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

// =====================================================================
// ClearyBg - background removal kernel, part 1: numeric primitives
// ---------------------------------------------------------------------
// Self-contained pure C# (C# 5 compatible, compiled by Add-Type).
// Ported from the numpy/scipy reference implementation used by WMBao:
//   imgtools_core.py  ->  MorphFilter / BoxBlur / Gauss / Hist / Holes / CCL
// No System.Drawing, no numpy, no external process. Zero dependencies.
//
// NOTE: all comments are ASCII on purpose - Add-Type reads source as ANSI
// when the file has no BOM, so non-ASCII here would be corrupted.
// =====================================================================

namespace ClearyBg
{
    public class BgOut
    {
        public byte[] Rgba;
        public int Width;
        public int Height;
        public string Info;
        public string Log;
    }

    public class SvgOut
    {
        public string Svg;
        public string Info;
    }

    // ---------------- numeric utilities ----------------
    public static class NU
    {
        public static double Clamp(double v, double lo, double hi)
        {
            if (v < lo) return lo;
            if (v > hi) return hi;
            return v;
        }

        public static int ClampI(int v, int lo, int hi)
        {
            if (v < lo) return lo;
            if (v > hi) return hi;
            return v;
        }

        public static double Max(double a, double b) { return a > b ? a : b; }
        public static double Min(double a, double b) { return a < b ? a : b; }

        // exact k-th smallest (0-based) via quickselect. Reorders 'a'.
        public static double Select(double[] a, int k)
        {
            int n = a.Length;
            if (n == 0) return 0.0;
            if (k < 0) k = 0;
            if (k >= n) k = n - 1;
            int lo = 0, hi = n - 1;
            while (lo < hi)
            {
                double pivot = a[(lo + hi) >> 1];
                int i = lo, j = hi;
                while (i <= j)
                {
                    while (a[i] < pivot) i++;
                    while (a[j] > pivot) j--;
                    if (i <= j)
                    {
                        double t = a[i]; a[i] = a[j]; a[j] = t;
                        i++; j--;
                    }
                }
                if (k <= j) hi = j;
                else if (k >= i) lo = i;
                else break;
            }
            return a[k];
        }

        // np.median analogue (averages the two middles when n is even)
        public static double Median(double[] src)
        {
            int n = src.Length;
            if (n == 0) return 0.0;
            if (n == 1) return src[0];
            double[] c = (double[])src.Clone();
            if ((n & 1) == 1) return Select(c, n >> 1);
            double lo = Select(c, (n >> 1) - 1);
            double hi = Select(c, n >> 1);
            return (lo + hi) * 0.5;
        }

        // percentile with linear interpolation, histogram accelerated.
        // bins = 65536 keeps the error well below one 8-bit level.
        public static double Percentile(double[] v, double pct)
        {
            int n = v.Length;
            if (n == 0) return 0.0;
            if (n == 1) return v[0];
            double mn = double.MaxValue, mx = double.MinValue;
            for (int i = 0; i < n; i++)
            {
                double t = v[i];
                if (t < mn) mn = t;
                if (t > mx) mx = t;
            }
            if (mx - mn <= 1e-12) return mn;
            int B = 65536;
            int[] hist = new int[B];
            double scale = (B - 1) / (mx - mn);
            for (int i = 0; i < n; i++)
            {
                int b = (int)((v[i] - mn) * scale);
                if (b < 0) b = 0;
                if (b >= B) b = B - 1;
                hist[b]++;
            }
            double target = pct / 100.0 * (n - 1);
            if (target < 0) target = 0;
            long cum = 0;
            int bin = 0;
            for (; bin < B; bin++)
            {
                if (cum + hist[bin] > target) break;
                cum += hist[bin];
            }
            if (bin >= B) bin = B - 1;
            int h = hist[bin];
            if (h < 1) h = 1;
            double lo = mn + bin / scale;
            double frac = (target - cum) / h;
            return lo + frac / scale;
        }
    }

    // ---------------- separable min/max filter ----------------
    // Monotonic deque => O(n) per pass, exactly like numpy maximum_filter /
    // minimum_filter but with edge clamping instead of mirror padding.
    public static class MorphFilter
    {
        public static double[] Run(double[] src, int w, int h, int radius, bool useMax)
        {
            if (radius < 1) return (double[])src.Clone();
            double[] tmp = new double[src.Length];
            double[] dst = new double[src.Length];
            int cap = Math.Max(w, h) + 8;
            int[] dq = new int[cap];

            // ---- horizontal ----
            for (int y = 0; y < h; y++)
            {
                int row = y * w;
                int head = 0, tail = 0;
                int stop = w + radius;
                for (int x = -radius; x < stop; x++)
                {
                    if (x < w)
                    {
                        double v = src[row + NU.ClampI(x, 0, w - 1)];
                        while (tail > head)
                        {
                            double bv = src[row + NU.ClampI(dq[tail - 1], 0, w - 1)];
                            if (useMax ? (bv <= v) : (bv >= v)) tail--;
                            else break;
                        }
                        if (tail >= cap) tail = cap - 1;
                        dq[tail++] = x;
                    }
                    int ox = x - radius;
                    if (ox >= 0 && ox < w)
                    {
                        while (head < tail && dq[head] < ox - radius) head++;
                        tmp[row + ox] = src[row + NU.ClampI(dq[head], 0, w - 1)];
                    }
                }
            }

            // ---- vertical ----
            for (int x = 0; x < w; x++)
            {
                int head = 0, tail = 0;
                int stop = h + radius;
                for (int y = -radius; y < stop; y++)
                {
                    if (y < h)
                    {
                        double v = tmp[NU.ClampI(y, 0, h - 1) * w + x];
                        while (tail > head)
                        {
                            double bv = tmp[NU.ClampI(dq[tail - 1], 0, h - 1) * w + x];
                            if (useMax ? (bv <= v) : (bv >= v)) tail--;
                            else break;
                        }
                        if (tail >= cap) tail = cap - 1;
                        dq[tail++] = y;
                    }
                    int oy = y - radius;
                    if (oy >= 0 && oy < h)
                    {
                        while (head < tail && dq[head] < oy - radius) head++;
                        dst[oy * w + x] = tmp[NU.ClampI(dq[head], 0, h - 1) * w + x];
                    }
                }
            }
            return dst;
        }
    }

    // ---------------- separable box blur (running sum) ----------------
    public static class BoxBlur
    {
        public static double[] Run(double[] src, int w, int h, int r)
        {
            if (r < 1) return (double[])src.Clone();
            int win = 2 * r + 1;
            double inv = 1.0 / win;
            double[] tmp = new double[src.Length];
            double[] dst = new double[src.Length];

            for (int y = 0; y < h; y++)
            {
                int row = y * w;
                double sum = 0.0;
                for (int k = -r; k <= r; k++) sum += src[row + NU.ClampI(k, 0, w - 1)];
                for (int x = 0; x < w; x++)
                {
                    tmp[row + x] = sum * inv;
                    sum -= src[row + NU.ClampI(x - r, 0, w - 1)];
                    sum += src[row + NU.ClampI(x + r + 1, 0, w - 1)];
                }
            }

            for (int x = 0; x < w; x++)
            {
                double sum = 0.0;
                for (int k = -r; k <= r; k++) sum += tmp[NU.ClampI(k, 0, h - 1) * w + x];
                for (int y = 0; y < h; y++)
                {
                    dst[y * w + x] = sum * inv;
                    sum -= tmp[NU.ClampI(y - r, 0, h - 1) * w + x];
                    sum += tmp[NU.ClampI(y + r + 1, 0, h - 1) * w + x];
                }
            }
            return dst;
        }
    }

    // ---------------- gaussian via 3 box passes ----------------
    // Standard approximation (Kovesi): error under ~3%, ~30x faster than a
    // true separable FIR at sigma=15, which is what flatten_bg uses.
    public static class Gauss
    {
        public static double[] Run(double[] src, int w, int h, double sigma)
        {
            if (sigma <= 0.1) return (double[])src.Clone();
            int n = 3;
            double wIdeal = Math.Sqrt((12.0 * sigma * sigma / n) + 1.0);
            int wl = (int)Math.Floor(wIdeal);
            if (wl % 2 == 0) wl--;
            if (wl < 1) wl = 1;
            int wu = wl + 2;
            double mIdeal = (12.0 * sigma * sigma - n * wl * wl - 4.0 * n * wl - 3.0 * n)
                            / (-4.0 * wl - 4.0);
            int m = (int)Math.Round(mIdeal);
            if (m < 0) m = 0;
            if (m > n) m = n;

            double[] cur = src;
            for (int i = 0; i < n; i++)
            {
                int win = (i < m) ? wl : wu;
                int r = (win - 1) / 2;
                if (r < 1) r = 1;
                cur = BoxBlur.Run(cur, w, h, r);
            }
            return cur;
        }
    }

    // ---------------- 3x3 median ----------------
    public static class Median3
    {
        public static double[] Run(double[] a, int w, int h)
        {
            double[] o = new double[a.Length];
            double[] b = new double[9];
            for (int y = 0; y < h; y++)
            {
                for (int x = 0; x < w; x++)
                {
                    int n = 0;
                    for (int dy = -1; dy <= 1; dy++)
                    {
                        int yy = NU.ClampI(y + dy, 0, h - 1) * w;
                        for (int dx = -1; dx <= 1; dx++)
                            b[n++] = a[yy + NU.ClampI(x + dx, 0, w - 1)];
                    }
                    for (int i = 1; i < 9; i++)
                    {
                        double v = b[i];
                        int j = i - 1;
                        while (j >= 0 && b[j] > v) { b[j + 1] = b[j]; j--; }
                        b[j + 1] = v;
                    }
                    o[y * w + x] = b[4];
                }
            }
            return o;
        }
    }

    // ---------------- border connected background ----------------
    // scipy.ndimage.binary_fill_holes analogue. 'fg' true = subject.
    // Returns a mask that is true where background is reachable from the
    // image border (i.e. NOT a hole).
    public static class Holes
    {
        public static bool[] OuterBg(bool[] fg, int w, int h)
        {
            bool[] vis = new bool[w * h];
            int[] st = new int[w * h];
            int sp = 0;

            for (int x = 0; x < w; x++)
            {
                int a = x;
                int b = (h - 1) * w + x;
                if (!fg[a] && !vis[a]) { vis[a] = true; st[sp++] = a; }
                if (!fg[b] && !vis[b]) { vis[b] = true; st[sp++] = b; }
            }
            for (int y = 0; y < h; y++)
            {
                int a = y * w;
                int b = y * w + w - 1;
                if (!fg[a] && !vis[a]) { vis[a] = true; st[sp++] = a; }
                if (!fg[b] && !vis[b]) { vis[b] = true; st[sp++] = b; }
            }

            while (sp > 0)
            {
                int cur = st[--sp];
                int cy = cur / w;
                int cx = cur - cy * w;
                if (cy > 0)
                {
                    int ni = cur - w;
                    if (!fg[ni] && !vis[ni]) { vis[ni] = true; st[sp++] = ni; }
                }
                if (cy < h - 1)
                {
                    int ni = cur + w;
                    if (!fg[ni] && !vis[ni]) { vis[ni] = true; st[sp++] = ni; }
                }
                if (cx > 0)
                {
                    int ni = cur - 1;
                    if (!fg[ni] && !vis[ni]) { vis[ni] = true; st[sp++] = ni; }
                }
                if (cx < w - 1)
                {
                    int ni = cur + 1;
                    if (!fg[ni] && !vis[ni]) { vis[ni] = true; st[sp++] = ni; }
                }
            }
            return vis;
        }
    }

    // ---------------- 4-connected labelling ----------------
    // scipy.ndimage.label default structure is the cross (4-neighbour).
    public static class CCL
    {
        public static int[] Run(bool[] m, int w, int h, out int count, out int[] sizes)
        {
            int n = w * h;
            int[] lab = new int[n];
            int[] par = new int[n / 2 + 16];
            int[] rnk = new int[n / 2 + 16];
            int next = 1;

            for (int y = 0; y < h; y++)
            {
                int row = y * w;
                for (int x = 0; x < w; x++)
                {
                    int i = row + x;
                    if (!m[i]) { lab[i] = 0; continue; }
                    int a = (x > 0) ? lab[i - 1] : 0;
                    int b = (y > 0) ? lab[i - w] : 0;
                    if (a == 0 && b == 0)
                    {
                        if (next < par.Length) { par[next] = next; rnk[next] = 0; }
                        lab[i] = next;
                        next++;
                    }
                    else if (a != 0 && b == 0) lab[i] = a;
                    else if (a == 0 && b != 0) lab[i] = b;
                    else
                    {
                        int ra = Find(par, a);
                        int rb = Find(par, b);
                        if (ra != rb)
                        {
                            if (rnk[ra] < rnk[rb]) { par[ra] = rb; }
                            else if (rnk[ra] > rnk[rb]) { par[rb] = ra; }
                            else { par[rb] = ra; rnk[ra]++; }
                            lab[i] = ra;
                        }
                        else lab[i] = ra;
                    }
                }
            }

            int maxLab = next;
            int[] remap = new int[maxLab + 1];
            int cnt = 0;
            int[] sz = new int[maxLab + 1];
            for (int i = 0; i < n; i++)
            {
                int v = lab[i];
                if (v == 0) continue;
                int r = Find(par, v);
                lab[i] = r;
                sz[r]++;
            }
            for (int i = 0; i < n; i++)
            {
                int v = lab[i];
                if (v == 0) continue;
                if (remap[v] == 0) { cnt++; remap[v] = cnt; }
                lab[i] = remap[v];
            }
            int[] outSz = new int[cnt + 1];
            for (int i = 0; i < n; i++)
            {
                int v = lab[i];
                if (v != 0) outSz[v]++;
            }
            count = cnt;
            sizes = outSz;
            return lab;
        }

        static int Find(int[] par, int x)
        {
            while (par[x] != x)
            {
                if (par[x] < 1 || par[x] >= par.Length) break;
                par[x] = par[par[x]];
                x = par[x];
            }
            return x;
        }
    }
}

// =====================================================================
// ClearyBg - background removal kernel, part 2: matting + vector tracing
// ---------------------------------------------------------------------
// Self-contained pure C# (strictly C# 5 compatible - no local functions,
// no string interpolation, no null-conditional: ps2exe hosts this under
// Windows PowerShell 5.1 whose CodeDom compiler rejects newer syntax).
//
// Ported from the numpy/scipy reference used by WMBao:
//   imgtools_core.py  ->  Bg (alpha_channel / alpha_solid / compose)
//   svg_trace.py      ->  Vec (marching squares -> RDP -> bezier)
//
// NEW vs the reference: lightMode / "dark background" support.
// The reference flatten_bg uses maximum_filter, which implicitly assumes a
// BRIGHT background with dark strokes ("paper and ink"). On a dark
// background that assumption inverts and the normalisation blows up.
// Fix: invert the channel first, run the same bright-background pipeline,
// then invert back. Algebraically this drives the backdrop to 0 while the
// subject stays bright, and the gaussian still captures and removes any
// low-frequency gradient across the dark backdrop.
// =====================================================================

namespace ClearyBg
{
    public static class Bg
    {
        static readonly string[] Can = { "R", "G", "B", "R-G", "R-B", "G-R", "G-B", "B-G", "B-R" };
        const int FLAT_WIN = 41;
        const double FLAT_SIGMA = 15.0;

        // ---------- channel extraction ----------
        static double[] GetChan(double[] r, double[] g, double[] b, string name)
        {
            string a = name, bb = null;
            int dash = name.IndexOf('-');
            if (dash > 0) { a = name.Substring(0, dash); bb = name.Substring(dash + 1); }
            double[] src = PickArr(r, g, b, a);
            double[] x = new double[src.Length];
            Array.Copy(src, x, src.Length);
            if (bb != null)
            {
                double[] y = PickArr(r, g, b, bb);
                for (int i = 0; i < x.Length; i++) x[i] = x[i] - y[i] + 128.0;
            }
            return x;
        }

        static double[] PickArr(double[] r, double[] g, double[] b, string k)
        {
            if (k == "R") return r;
            if (k == "G") return g;
            return b;
        }

        static void Polarity(double[] x, out double med, out double sign)
        {
            med = NU.Median(x);
            double p999 = NU.Percentile(x, 99.9);
            double p001 = NU.Percentile(x, 0.1);
            double hi = p999 - med;
            double lo = med - p001;
            sign = (hi >= lo) ? 1.0 : -1.0;
        }

        // signal-to-noise x foreground saturation; neutral grey shadow -> ~0
        // NOTE: r/g/b here are the ALREADY-FLATTENED channels, and are indexed
        // directly instead of being interleaved into a 3N array - that avoided
        // a 24-bytes-per-pixel allocation (matters on multi-megapixel images).
        static string PickChannel(double[] r, double[] g, double[] b,
                                  int w, int h, StringBuilder log)
        {
            string best = null;
            double bestScore = -1.0;
            int n = w * h;
            for (int ci = 0; ci < Can.Length; ci++)
            {
                string name = Can[ci];
                double[] x = GetChan(r, g, b, name);
                double med, sign;
                Polarity(x, out med, out sign);

                double[] dev = new double[n];
                for (int i = 0; i < n; i++) dev[i] = Math.Abs(x[i] - med);
                double mad = NU.Median(dev) * 1.4826 + 1e-6;
                double p999 = NU.Percentile(dev, 99.9);
                double snr = p999 / mad;

                double thr = 3.0 * mad;
                int fgCount = 0;
                double satSum = 0.0;
                for (int i = 0; i < n; i++)
                {
                    if ((x[i] - med) * sign > thr)
                    {
                        fgCount++;
                        double mx = r[i];
                        double mn = mx;
                        if (g[i] > mx) mx = g[i];
                        if (b[i] > mx) mx = b[i];
                        if (g[i] < mn) mn = g[i];
                        if (b[i] < mn) mn = b[i];
                        if (mx < 1.0) mx = 1.0;
                        satSum += (mx - mn) / mx;
                    }
                }
                if (fgCount < 100)
                {
                    if (log != null) log.AppendLine("  " + name + ": foreground too small, skipped");
                    continue;
                }
                double sat = satSum / fgCount;
                double score = snr * sat;
                if (log != null)
                {
                    log.AppendLine("  " + name
                        + ": snr=" + snr.ToString("F1", CultureInfo.InvariantCulture)
                        + " sat=" + sat.ToString("F3", CultureInfo.InvariantCulture)
                        + " score=" + score.ToString("F1", CultureInfo.InvariantCulture));
                }
                if (score > bestScore) { best = name; bestScore = score; }
            }
            if (log != null) log.AppendLine("  picked channel: " + (best == null ? "(none)" : best));
            return best;
        }

        // ---------- background flattening ----------
        // dark=false: divide by smoothed local max  (bright paper, dark ink)
        // dark=true : invert, divide, invert back   (dark backdrop, any gradient)
        public static double[] FlattenChan(double[] ch, int w, int h, bool dark)
        {
            int n = ch.Length;
            double[] src = ch;
            if (dark)
            {
                src = new double[n];
                for (int i = 0; i < n; i++) src[i] = 255.0 - ch[i];
            }
            double[] mx = MorphFilter.Run(src, w, h, (FLAT_WIN - 1) / 2, true);
            double[] bgf = Gauss.Run(mx, w, h, FLAT_SIGMA);
            double[] o = new double[n];
            for (int i = 0; i < n; i++)
            {
                double d = bgf[i];
                if (d < 1.0) d = 1.0;
                o[i] = NU.Clamp(src[i] / d * 255.0, 0.0, 255.0);
            }
            if (dark)
                for (int i = 0; i < n; i++) o[i] = 255.0 - o[i];
            return o;
        }

        // Decide whether the backdrop is darker than its subject.
        //
        // NOTE: comparing the border-band median against the WHOLE-FRAME median
        // is far too fragile - on a dark backdrop the frame median is itself
        // dark, so the two are nearly equal and any noise flips the verdict.
        // (That misclassified a red seal on paper as "dark".)
        //
        // Robust rule: the border band is (almost by definition) backdrop, so
        // compare it against a HIGH luminance percentile - i.e. ask "is the
        // backdrop markedly darker than the brightest thing in the frame?".
        public static bool IsDarkBg(double[] r, double[] g, double[] b, int w, int h)
        {
            int n = w * h;
            int k = Math.Max(2, Math.Min(w, h) / 20);
            double[] lum = new double[n];
            for (int i = 0; i < n; i++) lum[i] = 0.299 * r[i] + 0.587 * g[i] + 0.114 * b[i];
            List<double> edge = new List<double>();
            for (int y = 0; y < h; y++)
            {
                bool yEdge = (y < k) || (y >= h - k);
                for (int x = 0; x < w; x++)
                {
                    if (yEdge || x < k || x >= w - k) edge.Add(lum[y * w + x]);
                }
            }
            double em = NU.Median(edge.ToArray());
            double pHigh = NU.Percentile(lum, 99.0);
            return em < pHigh * 0.55;
        }

        // ---------- alpha: channel mode ----------
        public static double[] AlphaChannel(double[] r, double[] g, double[] b,
            int w, int h, string channel, double bgPct, double fgPct, StringBuilder log)
        {
            int n = w * h;
            string name;
            if (string.IsNullOrEmpty(channel) || channel.ToLower() == "auto")
            {
                if (log != null) log.AppendLine("channel candidates:");
                name = PickChannel(r, g, b, w, h, log);
            }
            else name = channel.ToUpper();
            if (name == null) name = "R";

            double[] x = GetChan(r, g, b, name);
            double med, sign;
            Polarity(x, out med, out sign);

            double[] d = new double[n];
            for (int i = 0; i < n; i++) d[i] = (x[i] - med) * sign;

            double black = NU.Percentile(d, bgPct);
            double white = NU.Percentile(d, fgPct);
            if (white < black + 1.0) white = black + 1.0;
            double span = white - black;
            if (span < 1e-6) span = 1e-6;

            double[] alpha = new double[n];
            for (int i = 0; i < n; i++) alpha[i] = NU.Clamp((d[i] - black) / span, 0.0, 1.0);

            alpha = Median3.Run(alpha, w, h);

            // drop specks
            bool[] fg = new bool[n];
            for (int i = 0; i < n; i++) fg[i] = alpha[i] > 0.15;
            int cnt;
            int[] sizes;
            int[] lab = CCL.Run(fg, w, h, out cnt, out sizes);
            long minSz = (long)Math.Max(8.0, n * 1e-6);
            if (cnt > 0)
            {
                int killed = 0;
                for (int i = 0; i < n; i++)
                {
                    int L = lab[i];
                    if (L != 0 && sizes[L] < minSz) { alpha[i] = 0.0; killed++; }
                }
                if (log != null) log.AppendLine("components=" + cnt + "  specks removed=" + killed);
            }
            return alpha;
        }

        // ---------- alpha: solid backdrop mode ----------
        // Sample the backdrop colour from the FOUR CORNER BLOCKS only.
        // (Do NOT widen this to the whole border band: on a page with a
        // lighting gradient the band median differs from the corner median,
        // which shifts dist[] and visibly changes the matte.)
        public static double[] DetectBg(double[] r, double[] g, double[] b, int w, int h)
        {
            int k = Math.Max(2, Math.Min(w, h) / 20);
            List<double> cr = new List<double>(), cg = new List<double>(), cb = new List<double>();
            for (int y = 0; y < h; y++)
            {
                bool yc = (y < k) || (y >= h - k);
                if (!yc) continue;
                for (int x = 0; x < w; x++)
                {
                    if (!(x < k || x >= w - k)) continue;
                    int i = y * w + x;
                    cr.Add(r[i]); cg.Add(g[i]); cb.Add(b[i]);
                }
            }
            return new double[] { NU.Median(cr.ToArray()), NU.Median(cg.ToArray()), NU.Median(cb.ToArray()) };
        }

        public static double[] AlphaSolid(double[] r, double[] g, double[] b,
            int w, int h, double tol, double soft, double maxHole, bool noHoles,
            double[] bgIn, StringBuilder log)
        {
            int n = w * h;
            double[] bg = (bgIn == null) ? DetectBg(r, g, b, w, h) : bgIn;

            double[] dist = new double[n];
            double s3 = Math.Sqrt(3.0);
            for (int i = 0; i < n; i++)
            {
                double dr = r[i] - bg[0], dg = g[i] - bg[1], db = b[i] - bg[2];
                dist[i] = Math.Sqrt(dr * dr + dg * dg + db * db) / s3;
            }

            if (tol < 1.0) tol = 1.0;
            double inner = tol * (1.0 - NU.Clamp(soft, 0.0, 1.0));
            double span = tol - inner;
            if (span < 1e-6) span = 1e-6;

            bool[] cand = new bool[n];
            bool[] subject = new bool[n];
            for (int i = 0; i < n; i++) { cand[i] = dist[i] < tol; subject[i] = !cand[i]; }

            bool[] reachBg = Holes.OuterBg(subject, w, h);
            bool[] holes = new bool[n];
            bool anyHole = false;
            for (int i = 0; i < n; i++)
            {
                holes[i] = !reachBg[i] && !subject[i];
                if (holes[i]) anyHole = true;
            }

            bool[] outer = new bool[n];
            for (int i = 0; i < n; i++) outer[i] = cand[i] && !holes[i];

            int holePx = 0;
            if (!noHoles && anyHole)
            {
                double limit = Math.Max(1.0, maxHole * n);
                int cnt; int[] sizes;
                int[] lab = CCL.Run(holes, w, h, out cnt, out sizes);
                for (int i = 0; i < n; i++)
                {
                    int L = lab[i];
                    if (L != 0 && sizes[L] <= limit) { outer[i] = true; holePx++; }
                }
            }

            double[] alpha = new double[n];
            for (int i = 0; i < n; i++)
            {
                if (outer[i] && dist[i] <= inner) alpha[i] = 0.0;
                else if (outer[i] && dist[i] > inner && dist[i] < tol) alpha[i] = (dist[i] - inner) / span;
                else alpha[i] = 1.0;
            }
            if (log != null)
            {
                log.AppendLine("bg=" + (int)bg[0] + "," + (int)bg[1] + "," + (int)bg[2]
                               + "  tol=" + tol.ToString("F0", CultureInfo.InvariantCulture)
                               + "  holePx=" + holePx);
            }
            return alpha;
        }

        // ---------- compose ----------
        static byte[] Compose(double[] r, double[] g, double[] b, double[] alpha,
                              int w, int h, string colorMode)
        {
            int n = w * h;
            byte[] rgba = new byte[n * 4];
            string cm = string.IsNullOrEmpty(colorMode) ? "keep" : colorMode.ToLower();

            if (cm == "main")
            {
                List<double> sr = new List<double>(), sg = new List<double>(), sb = new List<double>();
                for (int i = 0; i < n; i++)
                    if (alpha[i] > 0.5) { sr.Add(r[i]); sg.Add(g[i]); sb.Add(b[i]); }
                if (sr.Count == 0)
                    for (int i = 0; i < n; i++)
                        if (alpha[i] > 0.2) { sr.Add(r[i]); sg.Add(g[i]); sb.Add(b[i]); }
                double cr = sr.Count > 0 ? NU.Median(sr.ToArray()) : 0.0;
                double cg = sg.Count > 0 ? NU.Median(sg.ToArray()) : 0.0;
                double cb = sb.Count > 0 ? NU.Median(sb.ToArray()) : 0.0;
                for (int i = 0; i < n; i++)
                {
                    rgba[i * 4] = (byte)NU.Clamp(cr, 0, 255);
                    rgba[i * 4 + 1] = (byte)NU.Clamp(cg, 0, 255);
                    rgba[i * 4 + 2] = (byte)NU.Clamp(cb, 0, 255);
                    rgba[i * 4 + 3] = (byte)NU.Clamp(alpha[i] * 255.0, 0, 255);
                }
            }
            else if (cm == "unmix")
            {
                List<double> br = new List<double>(), bg2 = new List<double>(), bb2 = new List<double>();
                for (int i = 0; i < n; i++)
                    if (alpha[i] < 0.02) { br.Add(r[i]); bg2.Add(g[i]); bb2.Add(b[i]); }
                double cr = br.Count > 0 ? NU.Median(br.ToArray()) : 255.0;
                double cg = bg2.Count > 0 ? NU.Median(bg2.ToArray()) : 255.0;
                double cb = bb2.Count > 0 ? NU.Median(bb2.ToArray()) : 255.0;
                for (int i = 0; i < n; i++)
                {
                    double a3 = NU.Clamp(alpha[i], 0.05, 1.0);
                    double k = (1.0 - a3);
                    rgba[i * 4] = (byte)NU.Clamp((r[i] - k * cr) / a3, 0, 255);
                    rgba[i * 4 + 1] = (byte)NU.Clamp((g[i] - k * cg) / a3, 0, 255);
                    rgba[i * 4 + 2] = (byte)NU.Clamp((b[i] - k * cb) / a3, 0, 255);
                    rgba[i * 4 + 3] = (byte)NU.Clamp(alpha[i] * 255.0, 0, 255);
                }
            }
            else
            {
                for (int i = 0; i < n; i++)
                {
                    rgba[i * 4] = (byte)NU.Clamp(r[i], 0, 255);
                    rgba[i * 4 + 1] = (byte)NU.Clamp(g[i], 0, 255);
                    rgba[i * 4 + 2] = (byte)NU.Clamp(b[i], 0, 255);
                    rgba[i * 4 + 3] = (byte)NU.Clamp(alpha[i] * 255.0, 0, 255);
                }
            }
            return rgba;
        }

        static double Coverage(double[] alpha)
        {
            int c = 0;
            for (int i = 0; i < alpha.Length; i++) if (alpha[i] > 0.05) c++;
            return alpha.Length > 0 ? (double)c * 100.0 / alpha.Length : 0.0;
        }

        // ---------- interop helpers for the WPF host ----------
        // WPF's 32-bit alpha format is Bgra32 (B,G,R,A in memory) while the
        // kernel emits R,G,B,A. Doing the swap in compiled code matters: a
        // PowerShell loop over multi-megapixel buffers is 100x slower.
        public static byte[] ToBgra(byte[] rgba)
        {
            if (rgba == null) return null;
            int n = rgba.Length / 4;
            byte[] o = new byte[rgba.Length];
            for (int i = 0; i < n; i++)
            {
                o[i * 4] = rgba[i * 4 + 2];
                o[i * 4 + 1] = rgba[i * 4 + 1];
                o[i * 4 + 2] = rgba[i * 4];
                o[i * 4 + 3] = rgba[i * 4 + 3];
            }
            return o;
        }

        // Area-average downscale, used to clamp very large imports so the
        // double-precision pipeline cannot exhaust memory. Returns the input
        // untouched when it already fits.
        public static byte[] DownscaleRgb(byte[] rgb, int w, int h, int maxSide,
                                          out int nw, out int nh)
        {
            if (rgb == null) { nw = 0; nh = 0; return null; }
            if (maxSide <= 0 || (w <= maxSide && h <= maxSide)) { nw = w; nh = h; return rgb; }
            double r = (double)maxSide / (double)Math.Max(w, h);
            nw = Math.Max(1, (int)Math.Round(w * r));
            nh = Math.Max(1, (int)Math.Round(h * r));
            byte[] o = new byte[nw * nh * 3];
            for (int y = 0; y < nh; y++)
            {
                int sy0 = (int)((long)y * h / nh);
                int sy1 = (int)((long)(y + 1) * h / nh);
                if (sy1 <= sy0) sy1 = sy0 + 1;
                if (sy1 > h) sy1 = h;
                for (int x = 0; x < nw; x++)
                {
                    int sx0 = (int)((long)x * w / nw);
                    int sx1 = (int)((long)(x + 1) * w / nw);
                    if (sx1 <= sx0) sx1 = sx0 + 1;
                    if (sx1 > w) sx1 = w;
                    long sr = 0, sg = 0, sb = 0;
                    int cnt = 0;
                    for (int sy = sy0; sy < sy1; sy++)
                    {
                        int rowBase = sy * w;
                        for (int sx = sx0; sx < sx1; sx++)
                        {
                            int i = (rowBase + sx) * 3;
                            sr += rgb[i]; sg += rgb[i + 1]; sb += rgb[i + 2];
                            cnt++;
                        }
                    }
                    if (cnt < 1) cnt = 1;
                    int j = (y * nw + x) * 3;
                    o[j] = (byte)(sr / cnt);
                    o[j + 1] = (byte)(sg / cnt);
                    o[j + 2] = (byte)(sb / cnt);
                }
            }
            return o;
        }

        // ---------- entry point: full-res RGBA matting ----------
        public static BgOut Process(byte[] rgb, int w, int h,
            string mode, string lightMode, string channel,
            double bgPct, double fgPct, bool flatten,
            string colorMode, double tol, double soft, double maxHole, bool noHoles,
            string bgColorStr)
        {
            if (rgb == null || w < 2 || h < 2) return null;
            int n = w * h;
            double[] r = new double[n], g = new double[n], b = new double[n];
            for (int i = 0; i < n; i++)
            {
                r[i] = rgb[i * 3]; g[i] = rgb[i * 3 + 1]; b[i] = rgb[i * 3 + 2];
            }

            StringBuilder log = new StringBuilder();
            bool dark;
            string lm = string.IsNullOrEmpty(lightMode) ? "auto" : lightMode.ToLower();
            if (lm == "dark") dark = true;
            else if (lm == "light") dark = false;
            else dark = IsDarkBg(r, g, b, w, h);
            log.AppendLine("lightMode=" + lm + " -> darkBackdrop=" + (dark ? "1" : "0"));

            string md = string.IsNullOrEmpty(mode) ? "channel" : mode.ToLower();
            byte[] rgba;
            double coverage;

            if (md == "solid")
            {
                double[] bgIn = null;
                if (!string.IsNullOrEmpty(bgColorStr))
                {
                    string[] ps = bgColorStr.Split(',');
                    if (ps.Length >= 3)
                    {
                        double v0, v1, v2;
                        if (double.TryParse(ps[0].Trim(), out v0) &&
                            double.TryParse(ps[1].Trim(), out v1) &&
                            double.TryParse(ps[2].Trim(), out v2))
                            bgIn = new double[] { v0, v1, v2 };
                    }
                }
                double[] alpha = AlphaSolid(r, g, b, w, h, tol, soft, maxHole, noHoles, bgIn, log);
                rgba = Compose(r, g, b, alpha, w, h, colorMode);
                coverage = Coverage(alpha);
            }
            else
            {
                double[] fr = r, fg2 = g, fb = b;
                if (flatten)
                {
                    log.AppendLine("flatten: win=" + FLAT_WIN + " sigma=" + FLAT_SIGMA
                                   + " dark=" + (dark ? "1" : "0"));
                    fr = FlattenChan(r, w, h, dark);
                    fg2 = FlattenChan(g, w, h, dark);
                    fb = FlattenChan(b, w, h, dark);
                }
                double[] alpha = AlphaChannel(fr, fg2, fb, w, h, channel, bgPct, fgPct, log);
                // colours come from the ORIGINAL pixels, not the flattened ones
                rgba = Compose(r, g, b, alpha, w, h, colorMode);
                coverage = Coverage(alpha);
            }

            BgOut o = new BgOut();
            o.Rgba = rgba;
            o.Width = w;
            o.Height = h;
            o.Info = "size=" + w + "x" + h
                     + " coverage=" + coverage.ToString("F1", CultureInfo.InvariantCulture) + "%";
            o.Log = log.ToString();
            return o;
        }

        // ---------- alpha mask -> SVG ----------
        public static SvgOut ToSvg(byte[] rgba, int w, int h,
            double thr, double minArea, double eps, bool smooth)
        {
            if (rgba == null || w < 2 || h < 2) return null;
            int n = w * h;
            double[] alpha = new double[n];
            List<double> sr = new List<double>(), sg = new List<double>(), sb = new List<double>();
            for (int i = 0; i < n; i++)
            {
                alpha[i] = rgba[i * 4 + 3] / 255.0;
                if (alpha[i] > 0.5)
                {
                    sr.Add(rgba[i * 4]); sg.Add(rgba[i * 4 + 1]); sb.Add(rgba[i * 4 + 2]);
                }
            }
            string fill;
            if (sr.Count > 0)
            {
                fill = "#" + ((int)NU.Clamp(NU.Median(sr.ToArray()), 0, 255)).ToString("X2")
                            + ((int)NU.Clamp(NU.Median(sg.ToArray()), 0, 255)).ToString("X2")
                            + ((int)NU.Clamp(NU.Median(sb.ToArray()), 0, 255)).ToString("X2");
            }
            else fill = "#000000";

            VecStat st;
            List<double[]> contours = Vec.Trace(alpha, w, h, thr, minArea, eps, smooth, out st);
            string d = Vec.BuildPath(contours, 2, smooth);
            string svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"" + w + "\" height=\"" + h
                         + "\" viewBox=\"0 0 " + w + " " + h + "\">\n"
                         + "  <path fill=\"" + fill + "\" fill-rule=\"evenodd\" d=\"" + d + "\"/>\n"
                         + "</svg>\n";

            SvgOut o = new SvgOut();
            o.Svg = svg;
            o.Info = "contours=" + st.Total + " kept=" + st.Kept + " points=" + st.Points
                     + " truncated=" + (st.Truncated ? "1" : "0")
                     + " width=" + w + " height=" + h + " fill=" + fill;
            return o;
        }
    }

    public class VecStat
    {
        public int Total;
        public int Kept;
        public int Points;
        public bool Truncated;
    }

    // =====================================================================
    // Vector tracing: marching squares (sub-pixel) -> ring assembly ->
    // RDP simplify -> corner detection -> Catmull-Rom to cubic bezier.
    // =====================================================================
    public static class Vec
    {
        const double CORNER_DOT = 0.30;
        const int MAX_CONTOURS = 20000;

        // Point registry + adjacency for one marching-squares pass.
        public class Grid
        {
            public int W;
            public double[] P;
            public double Thr;
            public int HBase;
            public Dictionary<int, int> Id = new Dictionary<int, int>();
            public List<double> PX = new List<double>();
            public List<double> PY = new List<double>();
            public List<int> A1 = new List<int>();
            public List<int> A2 = new List<int>();
            public List<int> EA = new List<int>();
            public List<int> EB = new List<int>();

            public double Cross(double a1, double a2)
            {
                double d = a2 - a1;
                if (d == 0) return 0.5;
                return NU.Clamp((Thr - a1) / d, 0.0, 1.0);
            }

            public int Pt(int key)
            {
                int id;
                if (Id.TryGetValue(key, out id)) return id;
                double X, Y;
                if (key < HBase)
                {
                    int r = key / W;
                    int c = key - r * W;
                    double t = Cross(P[r * W + c], P[r * W + c + 1]);
                    X = c - 1.0 + t; Y = r - 1.0;
                }
                else
                {
                    int k2 = key - HBase;
                    int r = k2 / W;
                    int c = k2 - r * W;
                    double t = Cross(P[r * W + c], P[(r + 1) * W + c]);
                    X = c - 1.0; Y = r - 1.0 + t;
                }
                id = PX.Count;
                Id[key] = id;
                PX.Add(X); PY.Add(Y);
                A1.Add(-1); A2.Add(-1);
                return id;
            }

            public void Link(int ka, int kb)
            {
                int e = EA.Count;
                EA.Add(ka); EB.Add(kb);
                if (A1[ka] < 0) A1[ka] = e; else A2[ka] = e;
                if (A1[kb] < 0) A1[kb] = e; else A2[kb] = e;
            }
        }

        public static List<double[]> Trace(double[] alpha, int w, int h,
            double thr, double minArea, double eps, bool smooth, out VecStat stat)
        {
            stat = new VecStat();
            List<double[]> outList = new List<double[]>();

            int W = w + 2, HR = h + 2;
            double[] p = new double[W * HR];
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                    p[(y + 1) * W + (x + 1)] = alpha[y * w + x];

            Grid g = new Grid();
            g.W = W; g.P = p; g.Thr = thr; g.HBase = W * HR;

            int cellsX = w + 1, cellsY = h + 1;
            for (int r = 0; r < cellsY; r++)
            {
                for (int c = 0; c < cellsX; c++)
                {
                    bool tl = p[r * W + c] > thr;
                    bool tr = p[r * W + c + 1] > thr;
                    bool br = p[(r + 1) * W + c + 1] > thr;
                    bool bl = p[(r + 1) * W + c] > thr;
                    int cs = (tl ? 8 : 0) | (tr ? 4 : 0) | (br ? 2 : 0) | (bl ? 1 : 0);
                    if (cs == 0 || cs == 15) continue;

                    int kT = r * W + c;
                    int kB = (r + 1) * W + c;
                    int kL = g.HBase + r * W + c;
                    int kR = g.HBase + r * W + c + 1;

                    if (cs == 5 || cs == 10)
                    {
                        double mid = (p[r * W + c] + p[r * W + c + 1]
                                      + p[(r + 1) * W + c] + p[(r + 1) * W + c + 1]) / 4.0;
                        bool hi = mid > thr;
                        if (cs == 5)
                        {
                            if (hi) { g.Link(g.Pt(kT), g.Pt(kL)); g.Link(g.Pt(kB), g.Pt(kR)); }
                            else { g.Link(g.Pt(kT), g.Pt(kR)); g.Link(g.Pt(kL), g.Pt(kB)); }
                        }
                        else
                        {
                            if (hi) { g.Link(g.Pt(kT), g.Pt(kR)); g.Link(g.Pt(kL), g.Pt(kB)); }
                            else { g.Link(g.Pt(kT), g.Pt(kL)); g.Link(g.Pt(kB), g.Pt(kR)); }
                        }
                        continue;
                    }

                    switch (cs)
                    {
                        case 1: g.Link(g.Pt(kL), g.Pt(kB)); break;
                        case 2: g.Link(g.Pt(kB), g.Pt(kR)); break;
                        case 3: g.Link(g.Pt(kL), g.Pt(kR)); break;
                        case 4: g.Link(g.Pt(kT), g.Pt(kR)); break;
                        case 6: g.Link(g.Pt(kT), g.Pt(kB)); break;
                        case 7: g.Link(g.Pt(kT), g.Pt(kL)); break;
                        case 8: g.Link(g.Pt(kT), g.Pt(kL)); break;
                        case 9: g.Link(g.Pt(kT), g.Pt(kB)); break;
                        case 11: g.Link(g.Pt(kT), g.Pt(kR)); break;
                        case 12: g.Link(g.Pt(kL), g.Pt(kR)); break;
                        case 13: g.Link(g.Pt(kB), g.Pt(kR)); break;
                        case 14: g.Link(g.Pt(kL), g.Pt(kB)); break;
                    }
                }
            }

            int nEdges = g.EA.Count;
            if (nEdges == 0) return outList;

            bool[] used = new bool[nEdges];
            for (int s = 0; s < nEdges; s++)
            {
                if (used[s]) continue;
                int ka = g.EA[s], kb = g.EB[s];
                used[s] = true;
                List<int> loop = new List<int>();
                loop.Add(ka); loop.Add(kb);
                int cur = kb;
                int guard = 0;
                int guardMax = nEdges * 4 + 16;
                while (true)
                {
                    if (cur == loop[0]) break;
                    if (++guard > guardMax) break;
                    int nxt = -1;
                    int e1 = g.A1[cur], e2 = g.A2[cur];
                    if (e1 >= 0 && !used[e1])
                    {
                        used[e1] = true;
                        nxt = (g.EA[e1] == cur) ? g.EB[e1] : g.EA[e1];
                    }
                    else if (e2 >= 0 && !used[e2])
                    {
                        used[e2] = true;
                        nxt = (g.EA[e2] == cur) ? g.EB[e2] : g.EA[e2];
                    }
                    if (nxt < 0) break;
                    if (nxt == loop[0]) break;
                    loop.Add(nxt);
                    cur = nxt;
                }
                int m = loop.Count;
                if (m < 4) continue;

                double[] pts = new double[m * 2];
                for (int i = 0; i < m; i++)
                {
                    pts[i * 2] = g.PX[loop[i]];
                    pts[i * 2 + 1] = g.PY[loop[i]];
                }
                double area = PolyArea(pts, m);
                if (area < minArea) continue;
                outList.Add(pts);
            }

            stat.Total = outList.Count;

            if (eps > 0)
            {
                List<double[]> red = new List<double[]>();
                for (int i = 0; i < outList.Count; i++)
                {
                    int nn = outList[i].Length / 2;
                    double[] s2 = RdpClosed(outList[i], nn, eps);
                    if (s2.Length / 2 >= 3) red.Add(s2);
                }
                outList = red;
            }

            if (outList.Count > MAX_CONTOURS)
            {
                stat.Truncated = true;
                outList.Sort(CompareByAreaDesc);
                outList.RemoveRange(MAX_CONTOURS, outList.Count - MAX_CONTOURS);
            }

            stat.Kept = outList.Count;
            int total = 0;
            for (int i = 0; i < outList.Count; i++) total += outList[i].Length / 2;
            stat.Points = total;

            List<double[]> fin = new List<double[]>();
            for (int i = 0; i < outList.Count; i++)
            {
                double[] src = outList[i];
                int m = src.Length / 2;
                if (smooth)
                {
                    fin.Add(MarkCorners(src));
                }
                else
                {
                    // layout: [x,y,...,cornerFlags...] with every flag 0
                    double[] dst = new double[m * 3];
                    for (int j = 0; j < m; j++)
                    {
                        dst[j * 2] = src[j * 2];
                        dst[j * 2 + 1] = src[j * 2 + 1];
                        dst[2 * m + j] = 0.0;
                    }
                    fin.Add(dst);
                }
            }
            return fin;
        }

        static int CompareByAreaDesc(double[] x, double[] y)
        {
            double ax = PolyArea(x, x.Length / 2);
            double ay = PolyArea(y, y.Length / 2);
            return ay.CompareTo(ax);
        }

        static double PolyArea(double[] pts, int n)
        {
            double s = 0.0;
            for (int i = 0; i < n; i++)
            {
                int j = (i + 1) % n;
                s += pts[i * 2] * pts[j * 2 + 1] - pts[j * 2] * pts[i * 2 + 1];
            }
            return Math.Abs(s) / 2.0;
        }

        // ---- RDP on a closed polyline (matches the numpy reference) ----
        static double[] RdpClosed(double[] pts, int n, double eps)
        {
            if (n < 4 || eps <= 0) return pts;
            bool[] keep = new bool[n];
            keep[0] = true;
            keep[n - 1] = true;
            int[] stack = new int[n * 4 + 8];
            int sp = 0;
            stack[sp++] = 0;
            stack[sp++] = n - 1;
            while (sp > 0)
            {
                int j = stack[--sp];
                int i = stack[--sp];
                if (j <= i + 1) continue;
                double ax = pts[i * 2], ay = pts[i * 2 + 1];
                double bx = pts[j * 2], by = pts[j * 2 + 1];
                double abx = bx - ax, aby = by - ay;
                double L = Math.Sqrt(abx * abx + aby * aby);
                double best = -1.0;
                int bk = -1;
                for (int t = i + 1; t < j; t++)
                {
                    double dx = pts[t * 2] - ax, dy = pts[t * 2 + 1] - ay;
                    double d;
                    if (L < 1e-12) d = Math.Sqrt(dx * dx + dy * dy);
                    else d = Math.Abs(dx * aby - dy * abx) / L;
                    if (d > best) { best = d; bk = t; }
                }
                if (bk >= 0 && best > eps)
                {
                    keep[bk] = true;
                    if (sp + 4 > stack.Length) break;
                    stack[sp++] = i; stack[sp++] = bk;
                    stack[sp++] = bk; stack[sp++] = j;
                }
            }
            int m = 0;
            for (int i = 0; i < n; i++) if (keep[i]) m++;
            if (m < 3) return pts;
            double[] o = new double[m * 2];
            int k = 0;
            for (int i = 0; i < n; i++)
            {
                if (!keep[i]) continue;
                o[k * 2] = pts[i * 2];
                o[k * 2 + 1] = pts[i * 2 + 1];
                k++;
            }
            return o;
        }

        // ---- corner detection ----
        // out layout: [x0,y0,x1,y1,... | flag0,flag1,...]
        static double[] MarkCorners(double[] pts)
        {
            int n = pts.Length / 2;
            double[] outP = new double[n * 3];
            double[] cosang = new double[n];
            for (int i = 0; i < n; i++)
            {
                int im = (i - 1 + n) % n, ip = (i + 1) % n;
                double v1x = pts[i * 2] - pts[im * 2];
                double v1y = pts[i * 2 + 1] - pts[im * 2 + 1];
                double v2x = pts[ip * 2] - pts[i * 2];
                double v2y = pts[ip * 2 + 1] - pts[i * 2 + 1];
                double n1 = Math.Sqrt(v1x * v1x + v1y * v1y);
                double n2 = Math.Sqrt(v2x * v2x + v2y * v2y);
                if (n1 == 0) n1 = 1.0;
                if (n2 == 0) n2 = 1.0;
                cosang[i] = (v1x * v2x + v1y * v2y) / (n1 * n2);
            }
            int shift = 0;
            for (int i = 0; i < n; i++)
            {
                if (cosang[i] < CORNER_DOT) { shift = i; break; }
            }
            for (int i = 0; i < n; i++)
            {
                int src = (i + shift) % n;
                outP[i * 2] = pts[src * 2];
                outP[i * 2 + 1] = pts[src * 2 + 1];
                outP[2 * n + i] = (cosang[src] < CORNER_DOT) ? 1.0 : 0.0;
            }
            return outP;
        }

        // ---- emit SVG path "d" ----
        public static string BuildPath(List<double[]> contours, int prec, bool smooth)
        {
            StringBuilder sb = new StringBuilder();
            string fmt = "0." + new string('0', prec);
            for (int ci = 0; ci < contours.Count; ci++)
            {
                double[] item = contours[ci];
                int n = item.Length / 3;
                if (n < 3) continue;
                bool[] corners = new bool[n];
                bool any = false;
                for (int i = 0; i < n; i++)
                {
                    corners[i] = item[2 * n + i] > 0.5;
                    if (corners[i]) any = true;
                }
                if (!any) corners = null;

                AppendMove(sb, item, 0, fmt);
                if (corners == null)
                {
                    for (int i = 0; i < n; i++)
                    {
                        int im = (i - 1 + n) % n, ip = (i + 1) % n, ip2 = (i + 2) % n;
                        double c1x = item[i * 2] + (item[ip * 2] - item[im * 2]) / 6.0;
                        double c1y = item[i * 2 + 1] + (item[ip * 2 + 1] - item[im * 2 + 1]) / 6.0;
                        double c2x = item[ip * 2] - (item[ip2 * 2] - item[i * 2]) / 6.0;
                        double c2y = item[ip * 2 + 1] - (item[ip2 * 2 + 1] - item[i * 2 + 1]) / 6.0;
                        AppendCubic(sb, c1x, c1y, c2x, c2y, item[ip * 2], item[ip * 2 + 1], fmt);
                    }
                    sb.Append("Z ");
                    continue;
                }

                int t2 = 1;
                while (t2 <= n)
                {
                    int curi = t2 % n;
                    int im = (curi - 1 + n) % n;
                    if (corners[curi])
                    {
                        AppendLine(sb, item[curi * 2], item[curi * 2 + 1], fmt);
                    }
                    else
                    {
                        int ip = (curi + 1) % n, ip2 = (curi + 2) % n;
                        double c1x = item[curi * 2] + (item[ip * 2] - item[im * 2]) / 6.0;
                        double c1y = item[curi * 2 + 1] + (item[ip * 2 + 1] - item[im * 2 + 1]) / 6.0;
                        double c2x = item[ip * 2] - (item[ip2 * 2] - item[curi * 2]) / 6.0;
                        double c2y = item[ip * 2 + 1] - (item[ip2 * 2 + 1] - item[curi * 2 + 1]) / 6.0;
                        AppendCubic(sb, c1x, c1y, c2x, c2y, item[ip * 2], item[ip * 2 + 1], fmt);
                        t2++;
                    }
                    t2++;
                }
                sb.Append("Z ");
            }
            return sb.ToString();
        }

        static void AppendMove(StringBuilder sb, double[] pts, int i, string fmt)
        {
            sb.Append("M ").Append(pts[i * 2].ToString(fmt, CultureInfo.InvariantCulture))
              .Append(' ').Append(pts[i * 2 + 1].ToString(fmt, CultureInfo.InvariantCulture)).Append(' ');
        }

        static void AppendLine(StringBuilder sb, double x, double y, string fmt)
        {
            sb.Append("L ").Append(x.ToString(fmt, CultureInfo.InvariantCulture))
              .Append(' ').Append(y.ToString(fmt, CultureInfo.InvariantCulture)).Append(' ');
        }

        static void AppendCubic(StringBuilder sb, double c1x, double c1y, double c2x, double c2y,
                                double x, double y, string fmt)
        {
            sb.Append("C ").Append(c1x.ToString(fmt, CultureInfo.InvariantCulture))
              .Append(' ').Append(c1y.ToString(fmt, CultureInfo.InvariantCulture))
              .Append(' ').Append(c2x.ToString(fmt, CultureInfo.InvariantCulture))
              .Append(' ').Append(c2y.ToString(fmt, CultureInfo.InvariantCulture))
              .Append(' ').Append(x.ToString(fmt, CultureInfo.InvariantCulture))
              .Append(' ').Append(y.ToString(fmt, CultureInfo.InvariantCulture)).Append(' ');
        }
    }
}
'@

$script:BgKernelError = ''

function Initialize-BgKernel {
  # 惰性编译图像内核；成功返回 $true，失败返回 $false 并把原因写进 $script:BgKernelError
  if (([System.Management.Automation.PSTypeName]'ClearyBg.Bg').Type) { return $true }
  try {
    Add-Type -TypeDefinition $script:BG_CS_SRC -ErrorAction Stop
    return $true
  } catch {
    $msg = ''
    try { $msg = [string]$_.Exception.Message } catch {}
    if (-not $msg) {
      try {
        $rec = $Error[0]
        if ($rec -and $rec.Exception) { $msg = [string]$rec.Exception.Message }
        if (-not $msg -and $rec) { $msg = [string]$rec }
      } catch {}
    }
    if (-not $msg) { $msg = 'unknown compiler error' }
    $script:BgKernelError = $msg
    return $false
  }
}
# <<< BG_KERNEL_END

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
  # 不走 WMI (Win32_Battery) 回退：本机 wmiprvse 会被第三方 WMI 提供程序拖崩，
  # CIM 查询可能超时/失败，造成"断开"假象。台式机无电池，默认按接电处理。
  return $true
}

function Get-BatteryPercent {
  # 电量百分比 0-100；无电池或读取失败返回 -1（255 是"未知"）
  try {
    $sps = New-Object ClearyNative+SYSTEM_POWER_STATUS
    if ([ClearyNative]::GetSystemPowerStatus([ref]$sps)) {
      $p = [int]$sps.BatteryLifePercent
      if ($p -le 100) { return $p }
      return -1
    }
  } catch {}
  try {
    $f = [System.Windows.Forms.SystemInformation]::PowerStatus.BatteryLifePercent
    return [int][math]::Round([double]$f * 100)
  } catch {}
  return -1
}

function Get-BatteryAlertThreshold {
  try {
    if ($script:uiSettings -and $script:uiSettings.batteryAlertThreshold) {
      $v = [int]$script:uiSettings.batteryAlertThreshold
      if ($v -ge 10 -and $v -le 95) { return $v }
    }
  } catch {}
  return 73
}

function Get-BatteryAlertEnabled {
  try {
    if ($script:uiSettings -and ($null -ne $script:uiSettings.batteryAlertEnabled)) {
      return [bool]$script:uiSettings.batteryAlertEnabled
    }
  } catch {}
  return $true
}

function Save-BatteryAlertSettings {
  if (-not $script:uiSettings) { $script:uiSettings = @{} }
  $script:uiSettings.batteryAlertEnabled = [bool](Get-BatteryAlertEnabled)
  $script:uiSettings.batteryAlertThreshold = [int](Get-BatteryAlertThreshold)
  try { Save-UiSettings $script:uiSettings } catch {}
}

# ---- 强制置顶提醒弹窗（低电量等）----
# 系统 MessageBox 无法保证置顶，会被别的程序盖住；改为自建 Window + Topmost + ShowDialog。
$script:alertOpen = $false
$script:alertDlg  = $null

function Show-TopmostAlert {
  param([string]$Title, [string]$Message, [string]$Kind = 'warn')
  if ($script:alertOpen) { return }
  $script:alertOpen = $true
  try {
    [xml]$ax = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="提示" Width="430" SizeToContent="Height" ResizeMode="NoResize"
        WindowStartupLocation="CenterScreen" ShowInTaskbar="False" Topmost="True"
        Background="#FFFFFF" FontFamily="Microsoft YaHei UI,Segoe UI" FontSize="13"
        UseLayoutRounding="True" SnapsToDevicePixels="True">
  <Grid Margin="22,20,22,20">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <StackPanel Grid.Row="0" Orientation="Horizontal">
      <Border x:Name="AlIconBox" Width="28" Height="28" CornerRadius="14" Background="#FEF0E0" Margin="0,0,10,0">
        <TextBlock x:Name="AlIcon" Text="!" FontSize="16" FontWeight="Bold" Foreground="#B45309"
                   HorizontalAlignment="Center" VerticalAlignment="Center"/>
      </Border>
      <TextBlock x:Name="AlTitle" VerticalAlignment="Center" FontSize="15" FontWeight="SemiBold" Foreground="#1F2328"/>
    </StackPanel>
    <TextBlock x:Name="AlMsg" Grid.Row="1" Margin="38,14,0,0" TextWrapping="Wrap" LineHeight="22" Foreground="#3F4650"/>
    <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,22,0,0">
      <Button x:Name="AlOk" Content="知道了" Height="32" MinWidth="104" Foreground="White" Cursor="Hand">
        <Button.Template>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" CornerRadius="6" Background="#2B6DEF" Padding="18,0">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#1E5FD0"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#1A54BB"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Button.Template>
      </Button>
    </StackPanel>
  </Grid>
</Window>
'@
    $reader = New-Object System.Xml.XmlNodeReader $ax
    $dlg = [Windows.Markup.XamlReader]::Load($reader)
    $dlg.Title = $Title
    if ($Kind -eq 'info') {
      try {
        $dlg.FindName('AlIconBox').Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xE6, 0xF1, 0xFB)))
        $ic = $dlg.FindName('AlIcon')
        $ic.Text = 'i'
        $ic.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x18, 0x5F, 0xA5)))
      } catch {}
    }
    $dlg.FindName('AlTitle').Text = $Title
    $dlg.FindName('AlMsg').Text = $Message
    $script:alertDlg = $dlg
    $dlg.FindName('AlOk').Add_Click({ try { $script:alertDlg.Close() } catch {} })
    if ($window) { try { $dlg.Owner = $window } catch {} }
    [void]$dlg.ShowDialog()
  } catch {
    try {
      [void][System.Windows.MessageBox]::Show($window, $Message, $Title,
        [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
    } catch {}
  } finally {
    $script:alertDlg = $null
    $script:alertOpen = $false
  }
}

function Check-BatteryAlert {
  if ($script:loading) { return }
  try {
    $pct = Get-BatteryPercent
    # 顶部/面板实时显示电量
    if ($TxtBatNow) {
      $state = if (Get-IsOnAc) { T 'statusAc' } else { T 'statusBat' }
      if ($pct -ge 0) { $TxtBatNow.Text = (TF 'batAlertNowFmt' $state $pct) }
      else { $TxtBatNow.Text = (T 'batAlertNoBattery') }
    }
    if ($pct -lt 0) { return }
    if ([bool](Get-IsOnAc)) {
      # 插上电源即复位，下次拔电重新提醒
      $script:batAlertAt = $null
      return
    }
    if (-not (Get-BatteryAlertEnabled)) { return }
    $thr = Get-BatteryAlertThreshold
    if ($pct -gt $thr) { return }
    # 未插电时每 10 分钟最多重复提醒一次（从关掉弹窗那一刻开始计时）
    $now = [DateTime]::Now
    if ($script:batAlertAt -and (($now - $script:batAlertAt).TotalMinutes -lt 10)) { return }
    $msg = TF 'batAlertMsgFmt' $pct $thr
    Show-TopmostAlert (T 'batAlertTitleBox') $msg 'warn'
    $script:batAlertAt = [DateTime]::Now
  } catch {}
}

# ==================== 黑屏报告（异常掉电黑屏 → 重启后诊断） ====================
# 判据一：Windows 事件日志（Kernel-Power 41 / EventLog 6008 = 未正常关机、BugCheck 1001 = 蓝屏）
# 判据二：本程序心跳快照（正常退出会打 cleanExit 标记；异常掉电不会）—— 用于给出「黑屏前电量」
$script:blackoutStatePath  = Join-Path $baseDir 'session-state.json'
$script:blackoutReportPath = Join-Path $baseDir 'blackout-report.html'
$script:blackoutReportDir  = Join-Path $baseDir 'reports'
$script:blackoutAckPath    = Join-Path $baseDir 'blackout-ack.json'
$script:blackoutHit        = $null
$script:blackoutChecked    = $false

function Get-BlackoutReportEnabled {
  try {
    if ($script:uiSettings -and ($null -ne $script:uiSettings.blackoutReportEnabled)) {
      return [bool]$script:uiSettings.blackoutReportEnabled
    }
  } catch {}
  return $true
}

function Save-BlackoutSetting {
  if (-not $script:uiSettings) { $script:uiSettings = @{} }
  $script:uiSettings.blackoutReportEnabled = [bool](Get-BlackoutReportEnabled)
  try { Save-UiSettings $script:uiSettings } catch {}
}

function Get-SystemBootTime {
  try { return (Get-Date).AddMilliseconds(-1 * [int64][System.Environment]::TickCount64) } catch {}
  try { return (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime } catch {}
  return $null
}

function Write-SessionBeat([bool]$clean) {
  try {
    $o = [ordered]@{
      pid        = $PID
      lastBeat   = (Get-Date).ToString('o')
      cleanExit  = $clean
      batteryPct = (Get-BatteryPercent)
      onAc       = [bool](Get-IsOnAc)
      brightness = $(if ($SlBright) { [int][math]::Round([double]$SlBright.Value) } else { -1 })
      contrast   = $(if ($SlContrast) { [int][math]::Round([double]$SlContrast.Value) } else { -1 })
    }
    ($o | ConvertTo-Json -Compress) | Set-Content -LiteralPath $script:blackoutStatePath -Encoding UTF8
  } catch {}
}

function Get-PrevSessionBeat {
  try {
    if (-not (Test-Path $script:blackoutStatePath)) { return $null }
    return (Get-Content $script:blackoutStatePath -Raw -Encoding UTF8 | ConvertFrom-Json)
  } catch { return $null }
}

function Get-PowerEventTimeline([int]$days = 3) {
  $list = New-Object System.Collections.ArrayList
  $since = (Get-Date).AddDays(-1 * [math]::Abs($days))
  try {
    $ev = Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 41, 6008, 6005, 6009, 1074, 109, 1001; StartTime = $since } -MaxEvents 80 -ErrorAction Stop
    foreach ($e in $ev) {
      $kind = ''
      switch ([int]$e.Id) {
        41   { $kind = 'bad' }
        6008 { $kind = 'bad' }
        1001 { $kind = 'bug' }
        6005 { $kind = 'boot' }
        6009 { $kind = 'boot' }
        1074 { $kind = 'user' }
        109  { $kind = 'kp' }
      }
      if (-not $kind) { continue }
      $first = ''
      try { $first = ((($e.Message -split "`r?`n") | Where-Object { $_.Trim() }) | Select-Object -First 1) } catch {}
      [void]$list.Add([pscustomobject]@{ Time = $e.TimeCreated; Id = [int]$e.Id; Kind = $kind; Text = [string]$first })
    }
  } catch {}
  return @($list | Sort-Object Time)
}

function ConvertTo-HtmlSafe([string]$s) {
  if ($null -eq $s) { return '' }
  return ($s -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;')
}

function Get-BatteryHealthInfo {
  $o = [ordered]@{ design = -1; full = -1; cycles = -1; wearing = -1 }
  try { $o.design = [int](Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData -ErrorAction Stop).DesignedCapacity } catch {}
  try { $o.full = [int](Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity -ErrorAction Stop).FullChargedCapacity } catch {}
  try { $o.cycles = [int](Get-CimInstance -Namespace root\wmi -ClassName BatteryCycleCount -ErrorAction Stop).CycleCount } catch {}
  $designCache = Join-Path $baseDir 'battery-design-cache.json'
  if ($o.design -le 0) {
    # 设计容量不随老化变化 → 读缓存（部分机型 BatteryStaticData 类不可用）
    try {
      if (Test-Path $designCache) {
        $c = Get-Content $designCache -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([int]$c.design -gt 0) { $o.design = [int]$c.design }
      }
    } catch {}
  }
  if ($o.design -le 0) {
    # 兜底：powercfg 电池报告 XML（较慢，仅首次）
    try {
      $tmp = Join-Path $env:TEMP ('cleary-batt-' + $PID + '.xml')
      Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
      & powercfg.exe /batteryreport /xml /output $tmp 2>$null | Out-Null
      if (Test-Path $tmp) {
        $x = Get-Content $tmp -Raw -Encoding UTF8
        $md = [regex]::Match($x, '<DesignCapacity>(\d+)</DesignCapacity>')
        if ($md.Success -and [int]$md.Groups[1].Value -gt 0) {
          $o.design = [int]$md.Groups[1].Value
          if ($o.full -le 0) {
            $mf = [regex]::Match($x, '<FullChargeCapacity>(\d+)</FullChargeCapacity>')
            if ($mf.Success -and [int]$mf.Groups[1].Value -gt 0) { $o.full = [int]$mf.Groups[1].Value }
          }
          try { (@{ design = $o.design } | ConvertTo-Json -Compress) | Set-Content -LiteralPath $designCache -Encoding UTF8 } catch {}
        }
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
      }
    } catch {}
  }
  if ($o.design -gt 0 -and $o.full -gt 0) { $o.wearing = [int][math]::Round(100 - ($o.full * 100.0 / $o.design)) }
  return $o
}

function Get-BlackoutAckKey($r) {
  try {
    if ($r -and $r.Event) { return ([string]$r.Event.Time.ToString('o') + '#' + [string]$r.Event.Id) }
  } catch {}
  return ''
}

function Test-BlackoutAcked([string]$key) {
  if (-not $key) { return $false }
  try {
    if (-not (Test-Path $script:blackoutAckPath)) { return $false }
    $j = Get-Content $script:blackoutAckPath -Raw -Encoding UTF8 | ConvertFrom-Json
    return (@($j.keys) -contains $key)
  } catch { return $false }
}

function Set-BlackoutAcked([string]$key) {
  if (-not $key) { return }
  try {
    $keys = @()
    if (Test-Path $script:blackoutAckPath) {
      try { $keys = @((Get-Content $script:blackoutAckPath -Raw -Encoding UTF8 | ConvertFrom-Json).keys) } catch {}
    }
    if (@($keys) -notcontains $key) { $keys = @($keys) + $key }
    if (@($keys).Count -gt 30) { $keys = @(@($keys) | Select-Object -Last 30) }
    (@{ keys = @($keys) } | ConvertTo-Json -Compress) | Set-Content -LiteralPath $script:blackoutAckPath -Encoding UTF8
  } catch {}
}

function Find-LastBlackout([int]$days = 3) {
  $events   = Get-PowerEventTimeline $days
  $bootTime = Get-SystemBootTime
  $prev     = Get-PrevSessionBeat
  $bootEv   = @($events | Where-Object { $_.Kind -eq 'boot' } | Sort-Object Time)
  $lastBoot = if ($bootEv.Count -gt 0) { $bootEv[$bootEv.Count - 1].Time } else { $bootTime }

  $bad = @($events | Where-Object { $_.Kind -eq 'bad' -or $_.Kind -eq 'bug' } | Sort-Object Time)
  # 最新一次黑屏 = 范围内最后一条；同一次掉电若 41 与 6008 并存，优先 Kernel-Power 41（时间最接近掉电瞬间）
  $latest = $null
  if ($bad.Count -gt 0) {
    $h41 = @($bad | Where-Object { $_.Id -eq 41 })
    $latest = if ($h41.Count -gt 0) { $h41[$h41.Count - 1] } else { $bad[$bad.Count - 1] }
  }

  # Fresh = 本次开机就是由这次黑屏引起的（启动时弹窗只针对这种）
  $fresh = $false
  if ($latest -and $lastBoot) {
    $fresh = ($latest.Time -ge $lastBoot.AddHours(-12)) -and ($latest.Time -le $lastBoot)
  }

  # 心跳佐证：上次运行未打「正常退出」标记
  $beatBad = $false
  if ($prev) {
    $clean = $true
    try { if ($null -ne $prev.cleanExit) { $clean = [bool]$prev.cleanExit } } catch {}
    if (-not $clean) {
      $bt = $null
      try { $bt = [DateTime]::Parse([string]$prev.lastBeat) } catch {}
      if ($bt -and (($bt -lt (Get-Date).AddMinutes(-3)))) { $beatBad = $true }
    }
  }

  # 事件日志完全不可读时（无任何相关事件），退化为心跳判据
  $found = ($null -ne $latest)
  if (-not $found -and $beatBad -and $events.Count -eq 0) { $found = $true }

  return [pscustomobject]@{
    Found    = $found
    Fresh    = $fresh
    Event    = $latest
    Events   = $events
    Prev     = $prev
    BeatBad  = $beatBad
    LastBoot = $lastBoot
    Days     = $days
  }
}

function New-BlackoutReport([int]$days = 14) {
  $isZh  = ((Get-UiLang) -ne 'en')
  $now   = Get-Date
  $res   = Find-LastBlackout $days
  $pct   = Get-BatteryPercent
  $onAc  = [bool](Get-IsOnAc)
  $bat   = Get-BatteryHealthInfo
  $monN  = 0
  try { $monN = @(Get-AllHMonitors).Count } catch {}

  $kindLabel = @{
    bad  = $(if ($isZh) { '异常关机 / 掉电' } else { 'Unexpected power-off' })
    bug  = $(if ($isZh) { '蓝屏 BugCheck' } else { 'Bug check' })
    boot = $(if ($isZh) { '系统启动' } else { 'System boot' })
    user = $(if ($isZh) { '正常关机 / 重启' } else { 'Normal shutdown / restart' })
    kp   = $(if ($isZh) { '内核电源事件' } else { 'Kernel power' })
  }

  $rows = New-Object System.Collections.ArrayList
  foreach ($e in @($res.Events)) {
    $lb = $kindLabel[[string]$e.Kind]
    if (-not $lb) { $lb = [string]$e.Kind }
    [void]$rows.Add('<tr><td>' + (ConvertTo-HtmlSafe $e.Time.ToString('yyyy-MM-dd HH:mm:ss')) + '</td><td>' + $e.Id + '</td><td>' + (ConvertTo-HtmlSafe $lb) + '</td><td>' + (ConvertTo-HtmlSafe $e.Text) + '</td></tr>')
  }
  $eventTableBody = if ($rows.Count -gt 0) { ($rows -join '') } else {
    '<tr><td colspan="4">' + $(if ($isZh) { '未能读取系统事件日志（可能需要管理员权限）' } else { 'System event log unavailable (may require admin)' }) + '</td></tr>'
  }

  $beatTitle = $(if ($isZh) { '二、黑屏前最后记录（本程序心跳）' } else { '2. Last state before the blackout (heartbeat)' })
  $beatHtml = $(if ($isZh) { '暂无本程序心跳记录。' } else { 'No heartbeat record from this app yet.' })
  if ($res.Prev) {
    $pb = -1
    try { if ($null -ne $res.Prev.batteryPct) { $pb = [int]$res.Prev.batteryPct } } catch {}
    $ba = '—'
    try { if ($null -ne $res.Prev.onAc) { $ba = $(if ([bool]$res.Prev.onAc) { $(if ($isZh) { '接电' } else { 'AC' }) } else { $(if ($isZh) { '电池' } else { 'Battery' }) }) } } catch {}
    $bt = [string]$res.Prev.lastBeat
    $bx = ''
    $sync = $false
    try {
      $bx = ([DateTime]::Parse($bt)).ToString('yyyy-MM-dd HH:mm:ss')
      if ($res.Event) {
        # 心跳时间落在黑屏前 12 小时内 → 才算「黑屏前状态」
        $dh = ($res.Event.Time - [DateTime]::Parse($bt)).TotalHours
        if ($dh -ge -0.5 -and $dh -le 12) { $sync = $true }
      }
    } catch { $bx = $bt }
    if (-not $sync) {
      $beatTitle = $(if ($isZh) { '二、本程序最近一次心跳记录（与黑屏时间不同步，仅供参考）' } else { '2. Latest heartbeat from this app (not in sync with the blackout; reference only)' })
    }
    $cleanTxt = $(if ($isZh) { '正常退出' } else { 'Clean exit' })
    try { if ($res.Prev.cleanExit -eq $false) { $cleanTxt = $(if ($isZh) { '未正常退出（掉电/被强杀）' } else { 'No clean exit (power loss / killed)' }) } } catch {}
    $beatHtml = '<div class="kv"><span>' + $(if ($isZh) { '最后心跳时间' } else { 'Last heartbeat' }) + '</span><b>' + (ConvertTo-HtmlSafe $bx) + '</b></div>' +
                '<div class="kv"><span>' + $(if ($isZh) { '退出状态' } else { 'Exit state' }) + '</span><b>' + $cleanTxt + '</b></div>' +
                '<div class="kv"><span>' + $(if ($isZh) { '当时电量' } else { 'Charge then' }) + '</span><b>' + $(if ($pb -ge 0) { ([string]$pb + '%') } else { '—' }) + '</b></div>' +
                '<div class="kv"><span>' + $(if ($isZh) { '当时供电' } else { 'Power then' }) + '</span><b>' + $ba + '</b></div>'
  }

  $verdictCls   = $(if ($res.Found) { 'bad' } else { 'ok' })
  $verdictTitle = $(if ($res.Found) {
    $(if ($isZh) { '最新一次黑屏（异常掉电关机）' } else { 'Most recent blackout (unexpected power loss)' })
  } else {
    $(if ($isZh) { ('近 ' + $days + ' 天未检测到黑屏记录') } else { ('No blackout in the last ' + $days + ' days') })
  })
  $verdictSub = ''
  if ($res.Found -and $res.Event) {
    $span = (Get-Date) - $res.Event.Time
    $agoTxt = if ($span.TotalMinutes -lt 60) { $(if ($isZh) { '刚刚' } else { 'just now' }) }
              elseif ($span.TotalHours -lt 24) { $(if ($isZh) { ([string][int]$span.TotalHours + ' 小时前') } else { ([string][int]$span.TotalHours + ' h ago') }) }
              else { $(if ($isZh) { ([string][int]$span.TotalDays + ' 天前') } else { ([string][int]$span.TotalDays + ' d ago') }) }
    $verdictSub = $(if ($isZh) { '最近一次异常关机：' } else { 'Most recent unexpected shutdown: ' }) + $res.Event.Time.ToString('yyyy-MM-dd HH:mm:ss') +
                  '（' + $(if ($isZh) { '事件 ID' } else { 'Event ID' }) + ' ' + $res.Event.Id + '）· ' + $agoTxt
    if ($res.Fresh) { $verdictSub += '　' + $(if ($isZh) { '本次开机即由它引起' } else { 'this boot was caused by it' }) }
  } elseif ($res.Found) {
    $verdictSub = $(if ($isZh) { '依据本程序心跳记录判定（事件日志不可读）' } else { 'Judged from heartbeat (event log unreadable)' })
  } else {
    $verdictSub = $(if ($isZh) { ('近 ' + $days + ' 天没有异常掉电关机事件。') } else { ('No unexpected power-off in the last ' + $days + ' days.') })
  }
  if ($res.LastBoot) {
    $verdictSub += '　' + $(if ($isZh) { '本次开机：' } else { 'This boot: ' }) + $res.LastBoot.ToString('yyyy-MM-dd HH:mm:ss')
  }

  $wearTxt = '—'
  if ($bat.wearing -ge 0) { $wearTxt = ([string]$bat.wearing + '%') }
  $capTxt = '—'
  if ($bat.design -gt 0 -and $bat.full -gt 0) { $capTxt = ([string]$bat.full + ' / ' + [string]$bat.design + ' mWh') }
  $cycTxt = $(if ($bat.cycles -ge 0) { [string]$bat.cycles } else { '—' })

  $advice = New-Object System.Collections.ArrayList
  if ($res.Found) {
    [void]$advice.Add($(if ($isZh) { '把「低电量插电提醒」阈值提到 70% 以上，或直接长期接着电源使用。' } else { 'Raise the low-battery threshold above 70%, or keep the charger connected.' }))
    [void]$advice.Add($(if ($isZh) { '外接显示器比内置屏更耗电，掉电黑屏多发生在电池供电 + 外接屏的组合。' } else { 'An external monitor draws more power; blackouts mostly happen on battery + external display.' }))
  } else {
    [void]$advice.Add($(if ($isZh) { '继续保持「启用低电量提醒」，掉电黑屏后重启会自动出现本报告。' } else { 'Keep the low-battery alert on; this report reappears automatically after a blackout reboot.' }))
  }
  if ($bat.wearing -ge 25) {
    [void]$advice.Add($(if ($isZh) { ('电池损耗已达 ' + [string]$bat.wearing + '%，纯电池模式容量跳变风险高，建议优先插电或更换电池。') } else { ('Battery wear is ' + [string]$bat.wearing + '%; prefer AC power or replace the battery.') }))
  }
  $adviceHtml = ($advice | ForEach-Object { '<li>' + (ConvertTo-HtmlSafe $_) + '</li>' }) -join ''

  $H = New-Object System.Collections.ArrayList
  [void]$H.Add('<!doctype html><html lang="zh-CN"><head><meta charset="utf-8">')
  [void]$H.Add('<meta name="viewport" content="width=device-width,initial-scale=1">')
  [void]$H.Add('<title>' + $(if ($isZh) { '黑屏报告' } else { 'Blackout report' }) + ' · ClearyDisplay</title>')
  [void]$H.Add('<style>')
  [void]$H.Add('*{box-sizing:border-box}body{margin:0;padding:28px;background:#f4f5f7;color:#1f2328;font:14px/1.65 "Segoe UI","Microsoft YaHei",system-ui,sans-serif}')
  [void]$H.Add('.wrap{max-width:920px;margin:0 auto}h1{font-size:20px;margin:0 0 4px}.meta{color:#6b7280;font-size:12px;margin-bottom:18px}')
  [void]$H.Add('.card{background:#fff;border:1px solid #e5e7eb;border-radius:12px;padding:18px 20px;margin-bottom:16px;box-shadow:0 1px 2px rgba(16,24,40,.04)}')
  [void]$H.Add('.card h2{font-size:14px;margin:0 0 12px;color:#111827}')
  [void]$H.Add('.verdict{border-left:5px solid #16a34a;background:#f0fdf4}.verdict.bad{border-left-color:#dc2626;background:#fef2f2}')
  [void]$H.Add('.verdict .t{font-size:16px;font-weight:600}.verdict.bad .t{color:#b91c1c}.verdict .s{color:#4b5563;font-size:13px;margin-top:4px}')
  [void]$H.Add('table{width:100%;border-collapse:collapse;font-size:13px}th,td{text-align:left;padding:8px 10px;border-bottom:1px solid #eef0f3;vertical-align:top}')
  [void]$H.Add('th{color:#6b7280;font-weight:500;background:#fafbfc}td:first-child{white-space:nowrap}')
  [void]$H.Add('.kv{display:flex;justify-content:space-between;gap:16px;padding:7px 0;border-bottom:1px dashed #eef0f3}.kv:last-child{border-bottom:0}.kv span{color:#6b7280}')
  [void]$H.Add('ul{margin:0;padding-left:20px}li{margin:4px 0}.foot{color:#9ca3af;font-size:12px;text-align:center;margin-top:8px}')
  [void]$H.Add('</style></head><body><div class="wrap">')
  [void]$H.Add('<h1>' + $(if ($isZh) { '黑屏报告' } else { 'Blackout report' }) + '</h1>')
  [void]$H.Add('<div class="meta">ClearyDisplay · ' + $(if ($isZh) { '生成时间' } else { 'Generated' }) + ' ' + $now.ToString('yyyy-MM-dd HH:mm:ss') + '</div>')
  [void]$H.Add('<div class="card verdict ' + $verdictCls + '"><div class="t">' + (ConvertTo-HtmlSafe $verdictTitle) + '</div><div class="s">' + (ConvertTo-HtmlSafe $verdictSub) + '</div></div>')
  [void]$H.Add('<div class="card"><h2>' + $(if ($isZh) { ('一、关机 / 开机事件时间线（近 ' + $days + ' 天）') } else { ('1. Shutdown / boot timeline (last ' + $days + ' days)') }) + '</h2><table><thead><tr><th>' + $(if ($isZh) { '时间' } else { 'Time' }) + '</th><th>ID</th><th>' + $(if ($isZh) { '类型' } else { 'Type' }) + '</th><th>' + $(if ($isZh) { '摘要' } else { 'Summary' }) + '</th></tr></thead><tbody>' + $eventTableBody + '</tbody></table></div>')
  [void]$H.Add('<div class="card"><h2>' + $beatTitle + '</h2>' + $beatHtml + '</div>')
  [void]$H.Add('<div class="card"><h2>' + $(if ($isZh) { '三、当前电源 / 电池 / 显示器' } else { '3. Current power / battery / display' }) + '</h2>' +
               '<div class="kv"><span>' + $(if ($isZh) { '供电状态' } else { 'Power source' }) + '</span><b>' + $(if ($onAc) { $(if ($isZh) { '已接电源（AC）' } else { 'AC' }) } else { $(if ($isZh) { '电池供电' } else { 'Battery' }) }) + '</b></div>' +
               '<div class="kv"><span>' + $(if ($isZh) { '当前电量' } else { 'Charge now' }) + '</span><b>' + $(if ($pct -ge 0) { ([string]$pct + '%') } else { '—' }) + '</b></div>' +
               '<div class="kv"><span>' + $(if ($isZh) { '电池满充/设计容量' } else { 'Full / design capacity' }) + '</span><b>' + $capTxt + '</b></div>' +
               '<div class="kv"><span>' + $(if ($isZh) { '电池损耗' } else { 'Battery wear' }) + '</span><b>' + $wearTxt + '</b></div>' +
               '<div class="kv"><span>' + $(if ($isZh) { '循环次数' } else { 'Cycle count' }) + '</span><b>' + $cycTxt + '</b></div>' +
               '<div class="kv"><span>' + $(if ($isZh) { '显示器数量' } else { 'Monitors' }) + '</span><b>' + $monN + '</b></div>' +
               '<div class="kv"><span>' + $(if ($isZh) { '亮度 / 对比度' } else { 'Brightness / contrast' }) + '</span><b>' + $(if ($SlBright) { [int][math]::Round([double]$SlBright.Value) } else { '—' }) + ' / ' + $(if ($SlContrast) { [int][math]::Round([double]$SlContrast.Value) } else { '—' }) + '</b></div>' +
               '</div>')
  [void]$H.Add('<div class="card"><h2>' + $(if ($isZh) { '四、建议' } else { '4. Recommendations' }) + '</h2><ul>' + $adviceHtml + '</ul></div>')
  [void]$H.Add('<div class="foot">' + $(if ($isZh) { '本报告由 ClearyDisplay 本地生成，仅读取系统事件日志与电池状态，不会上传任何数据。' } else { 'Generated locally by ClearyDisplay. Reads system event log and battery state only; nothing is uploaded.' }) + '</div>')
  [void]$H.Add('</div></body></html>')

  $html = ($H -join '')
  try {
    New-Item -ItemType Directory -Force -Path $script:blackoutReportDir | Out-Null
    Set-Content -LiteralPath $script:blackoutReportPath -Value $html -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $script:blackoutReportDir ('blackout-' + $now.ToString('yyyyMMdd-HHmmss') + '.html')) -Value $html -Encoding UTF8
    # 历史报告只留最近 20 份
    $old = @(Get-ChildItem -LiteralPath $script:blackoutReportDir -Filter 'blackout-*.html' -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -Skip 20)
    foreach ($f in $old) { try { Remove-Item -LiteralPath $f.FullName -Force } catch {} }
  } catch {}

  return [pscustomobject]@{ Path = $script:blackoutReportPath; Found = $res.Found; Event = $res.Event; Prev = $res.Prev; At = $now }
}

function Open-BlackoutReport([string]$path) {
  if (-not $path -or -not (Test-Path $path)) { return $false }
  try { Start-Process -FilePath $path | Out-Null; return $true } catch {}
  try { Start-Process -FilePath 'explorer.exe' -ArgumentList ('"' + $path + '"') | Out-Null; return $true } catch {}
  return $false
}

function Update-BlackoutHint {
  if (-not $TxtBlackoutHint) { return }
  try {
    $h = $script:blackoutHit
    if ($h -and $h.Found) {
      $t = ''
      if ($h.Event) { $t = $h.Event.Time.ToString('MM-dd HH:mm') }
      $p = -1
      if ($h.Prev) { try { if ($null -ne $h.Prev.batteryPct) { $p = [int]$h.Prev.batteryPct } } catch {} }
      if ($t -and $p -ge 0) { $TxtBlackoutHint.Text = (TF 'blackoutHintFoundFmt' $t $p) }
      elseif ($t) { $TxtBlackoutHint.Text = $t }
      else { $TxtBlackoutHint.Text = (T 'blackoutHintNone') }
    } else {
      $TxtBlackoutHint.Text = (T 'blackoutHintNone')
    }
  } catch {}
}

function Test-BlackoutOnStartup {
  if ($script:blackoutChecked) { return }
  $script:blackoutChecked = $true
  try {
    if (-not (Get-BlackoutReportEnabled)) { Update-BlackoutHint; return }
    # 状态位始终展示「最新一次黑屏」（可回溯 14 天）
    $res = Find-LastBlackout 14
    $script:blackoutHit = $res
    Update-BlackoutHint
    # 只有「本次开机就是黑屏重启」才弹窗；同一次黑屏只提示一次
    if ($res.Found -and $res.Fresh) {
      # 同一次黑屏事件只提示一次
      $key = Get-BlackoutAckKey $res
      if (Test-BlackoutAcked $key) { return }
      $r = New-BlackoutReport
      $when = ''
      if ($res.Event) { $when = $res.Event.Time.ToString('yyyy-MM-dd HH:mm:ss') + '　' }
      $ans = [System.Windows.MessageBox]::Show((TF 'blackoutAskFmt' $when), (T 'blackoutTitle'),
        [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
      Set-BlackoutAcked $key
      if ($ans -eq [System.Windows.MessageBoxResult]::Yes) { [void](Open-BlackoutReport $r.Path) }
    }
  } catch {}
}

# ==================== 环境自动切换（显示器 + 网络 → 方案） ====================
# 指纹 = 活动显示器型号集合 + 网络标识（Wi-Fi SSID 优先，其次 IP 网段）
$script:envBindsPath  = Join-Path $baseDir 'env-binds.json'
$script:envState      = $null
$script:envNow        = $null
$script:envLastApplied = ''
$script:applyReadback = ''
$script:envDispCache  = $null
$script:envTimer      = $null
$script:envLogPath    = Join-Path $baseDir 'env-switch.log'

function Write-EnvLog([string]$msg) {
  # 环境切换审计日志：只在「真正切换」或「离开已匹配环境」时写，便于事后排查
  try {
    Add-Content -LiteralPath $script:envLogPath -Value ((Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + '  ' + $msg) -Encoding UTF8
    $f = Get-Item -LiteralPath $script:envLogPath -ErrorAction SilentlyContinue
    if ($f -and $f.Length -gt 200000) {
      $keep = @(Get-Content -LiteralPath $script:envLogPath -Encoding UTF8 | Select-Object -Last 800)
      Set-Content -LiteralPath $script:envLogPath -Value $keep -Encoding UTF8
    }
  } catch {}
}

function Get-EnvDisplays {
  if ($script:envDispCache -and (((Get-Date) - $script:envDispCache.At).TotalSeconds -lt 60)) {
    return $script:envDispCache.Value
  }
  $iL = New-Object System.Collections.ArrayList
  $lL = New-Object System.Collections.ArrayList
  try {
    $mons = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction Stop | Where-Object { $_.Active })
    foreach ($m in $mons) {
      $pd = -join (@($m.ProductCodeID)   | Where-Object { $_ -gt 0 } | ForEach-Object { [char]$_ })
      $mf = -join (@($m.ManufacturerName) | Where-Object { $_ -gt 0 } | ForEach-Object { [char]$_ })
      $nm = -join (@($m.UserFriendlyName) | Where-Object { $_ -gt 0 } | ForEach-Object { [char]$_ })
      $code = ((([string]$mf).Trim()) + (([string]$pd).Trim())).Trim()
      if (-not $code) { continue }
      [void]$iL.Add($code)
      [void]$lL.Add($(if ($nm) { $nm } else { $code }))
    }
  } catch {}
  if ($iL.Count -eq 0) {
    # 退化：用分辨率组合（WMI 不可用时）
    try {
      Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
      foreach ($s in [System.Windows.Forms.Screen]::AllScreens) {
        [void]$iL.Add('SCR' + $s.Bounds.Width + 'x' + $s.Bounds.Height)
        [void]$lL.Add([string]$s.Bounds.Width + '×' + [string]$s.Bounds.Height)
      }
    } catch {}
  }
  $ids = @($iL | Sort-Object -Unique)
  $lbs = @($lL | Sort-Object -Unique)
  $v = [pscustomobject]@{ key = ($ids -join '+'); label = ($lbs -join ' + '); count = @($ids).Count }
  $script:envDispCache = @{ At = (Get-Date); Value = $v }
  return $v
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
  $d = Get-EnvDisplays
  $n = Get-EnvNetwork
  $parts = @()
  if ($d.label) { $parts += $d.label }
  if ($n.label) { $parts += $n.label }
  return [pscustomobject]@{
    display      = [string]$d.key
    displayLabel = [string]$d.label
    wifi         = [string]$n.wifi
    ipseg        = [string]$n.ipseg
    kind         = [string]$n.kind
    netLabel     = [string]$n.label
    label        = ($parts -join ' · ')
  }
}

function Load-EnvBinds {
  $d = @{ enabled = $false; autoApply = $true; binds = @() }
  try {
    if (Test-Path $script:envBindsPath) {
      $j = Get-Content $script:envBindsPath -Raw -Encoding UTF8 | ConvertFrom-Json
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

function Save-EnvBinds($s) {
  try {
    $o = [ordered]@{ enabled = [bool]$s.enabled; autoApply = [bool]$s.autoApply; binds = @($s.binds) }
    ($o | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $script:envBindsPath -Encoding UTF8
  } catch {}
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

function Apply-PresetByName([string]$name, [bool]$writeScreen) {
  if (-not $name -or -not $presets.Contains($name)) { return $false }
  $n = $presets[$name]
  $profiles.ac = @{ brightness = [int]$n.ac.brightness; contrast = [int]$n.ac.contrast; gammaPower = [double]$n.ac.gammaPower; scale = [double]$n.ac.scale }
  $profiles.battery = @{ brightness = [int]$n.battery.brightness; contrast = [int]$n.battery.contrast; gammaPower = [double]$n.battery.gammaPower; scale = [double]$n.battery.scale }
  try { Save-ActiveProfiles $profiles } catch {}
  try {
    if ($RbAc -and $RbAc.IsChecked) { Set-SlidersFromProfile $profiles.ac } else { Set-SlidersFromProfile $profiles.battery }
  } catch {}
  if ($TxtPresetName) { $TxtPresetName.Text = $name }
  $script:applyReadback = '未写屏'
  if ($writeScreen) {
    try {
      $isAc = [bool](Get-IsOnAc)
      $use  = if ($isAc) { $profiles.ac } else { $profiles.battery }
      $subN = if ($isAc) { 'ac' } else { 'battery' }
      # 必须吃掉返回值，否则会顺着管道泄漏出去，让本函数的 $true 变成数组
      $rb = Apply-DisplayValues $use.brightness $use.contrast $use.gammaPower $use.scale
      $script:applyReadback = ('子档位={0} 写回 bright={1}/{2} contrast={3}/{4}' -f $subN, $rb.Brightness, $use.brightness, $rb.Contrast, $use.contrast)
    } catch {
      $script:applyReadback = ('写屏异常：' + $_.Exception.Message)
    }
  }
  return $true
}

function Update-EnvUi {
  try {
    $st = $script:envState
    if (-not $st) { return }
    if ($TxtEnvNow) {
      if ($script:envNow -and $script:envNow.label) { $TxtEnvNow.Text = $script:envNow.label }
      elseif ($script:envNow) { $TxtEnvNow.Text = (T 'envUnknown') }
      else { $TxtEnvNow.Text = (T 'envScanning') }
    }
    if ($ChkEnvAuto)  { $ChkEnvAuto.IsChecked  = [bool]$st.enabled }
    if ($ChkEnvApply) { $ChkEnvApply.IsChecked = [bool]$st.autoApply }
    if ($TxtEnvList) {
      $binds = @($st.binds)
      if ($binds.Count -eq 0) { $TxtEnvList.Text = (T 'envNone') }
      else {
        $rows = @()
        foreach ($b in $binds) { $rows += ('· ' + [string]$b.preset + '  ←  ' + [string]$b.label) }
        $TxtEnvList.Text = ($rows -join "`n")
      }
    }
    if ($CmbEnvPreset) {
      $cur = ''
      if ($null -ne $CmbEnvPreset.SelectedItem) { $cur = [string]$CmbEnvPreset.SelectedItem }
      $have = @($CmbEnvPreset.Items | ForEach-Object { [string]$_ })
      $want = @($presets.Keys | Sort-Object | ForEach-Object { [string]$_ })
      if (($have -join '|') -ne ($want -join '|')) {
        $CmbEnvPreset.Items.Clear()
        foreach ($k in $want) { [void]$CmbEnvPreset.Items.Add($k) }
        if ($cur -and $CmbEnvPreset.Items.Contains($cur)) { $CmbEnvPreset.SelectedItem = $cur }
        elseif ($CmbEnvPreset.Items.Count -gt 0) { $CmbEnvPreset.SelectedIndex = 0 }
      }
    }
  } catch {}
}

function Test-EnvAutoSwitch([switch]$Force) {
  try {
    if (-not $script:envState) { $script:envState = Load-EnvBinds }
    $fp = Get-EnvFingerprint
    $script:envNow = $fp
    Update-EnvUi
    $st = $script:envState
    if (-not $st.enabled -and -not $Force) { return }
    $m = Find-EnvMatch $fp $st.binds
    if (-not $m) {
      if ($script:envLastApplied -ne '') { Write-EnvLog ('离开已匹配环境「' + $script:envLastApplied + '」　当前指纹：' + $fp.label) }
      $script:envLastApplied = ''
      return
    }
    $name = [string]$m.Bind.preset
    if ($name -eq $script:envLastApplied) { return }
    if (-not $presets.Contains($name)) {
      Write-EnvLog ('匹配到「' + $name + '」但该方案不存在，已跳过　指纹：' + $fp.label)
      return
    }
    $script:envLastApplied = $name
    $ok = Apply-PresetByName $name ([bool]$st.autoApply)
    $rbTxt = [string]$script:applyReadback
    Write-EnvLog ('切换方案 → 「' + $name + '」　匹配分 ' + $m.Score + '　写屏=' + [bool]$st.autoApply + '　成功=' + $ok + '　' + $rbTxt + '　指纹：' + $fp.label)
    # 写屏后核对硬件回读：用来区分「方案没生效」和「显示器没响应 DDC/CI」
    if ($st.autoApply -and ($rbTxt -match '写回 bright=(-?\d+)/(-?\d+) contrast=(-?\d+)/(-?\d+)')) {
      $rbB = [int]$Matches[1]; $wantB = [int]$Matches[2]
      $rbC = [int]$Matches[3]; $wantC = [int]$Matches[4]
      if (($rbB -lt 0) -or ($rbC -lt 0)) {
        Write-EnvLog ('　└ 回读失败（显示器未响应 DDC/CI），无法确认是否写入。目标 ' + $wantB + '/' + $wantC + '，可在界面点一次「应用」重试。')
      } elseif (($rbB -ne $wantB) -or ($rbC -ne $wantC)) {
        Write-EnvLog ('　└ 回读不一致：亮度 ' + $rbB + '≠' + $wantB + '　对比度 ' + $rbC + '≠' + $wantC + '　（可在界面点一次「应用」重试）')
      }
    }
    if ($ok) {
      $msg = if ($st.autoApply) { TF 'envAppliedFmt' $name } else { TF 'envSwitchedFmt' $name }
      Flash-Status $msg
    }
  } catch {}
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

# DDC/CI 走 I2C 通道，速率很低：连发命令会把显示器打"哑"（表现为断开/回读-1）。
# 因此：相同数值不重复写（缓存）、失败重试一次、写后等显示器缓过来再回读。
$script:lastBrightApplied = -999
$script:lastContrastApplied = -999
$script:lastBrightRead = -1
$script:lastContrastRead = -1

function Apply-Brightness([int]$v, [switch]$Force) {
  if (-not $Force -and $script:lastBrightApplied -eq $v -and $script:lastBrightRead -ge 0) {
    return $script:lastBrightRead
  }
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
          # 切勿因 $ph 为 0 就 continue！本机实测（单显示器）dxva2 返回的 hPhysicalMonitor
          # 就是 0，用这个 0 句柄读写 DDC 完全正常。加上 Zero 判断的后果是：
          # 主程序「从不写屏、回读永远 -1」，而 ApplyProfile.ps1 没这个判断所以一切正常
          # —— 这正是「界面调了没反应、开机脚本却有效」的根因。
          # 正确做法：照写，用 $ok 与回读值判断成败。
          # DDC/CI 走 I2C，速率极低：写后必须留静默时间，否则显示器会被"打哑"，
          # 症状为回读 -1、且紧随其后的对比度写入丢失（实测复现过）。
          $ok = [ClearyNative]::SetMonitorBrightness($ph,[uint32]$v)
          if (-not $ok) {
            Start-Sleep -Milliseconds 150
            $ok = [ClearyNative]::SetMonitorBrightness($ph,[uint32]$v)
          }
          Start-Sleep -Milliseconds 110
          $got = $false
          $min=0;$cur=0;$max=0
          if ([ClearyNative]::GetMonitorBrightness($ph,[ref]$min,[ref]$cur,[ref]$max)) { $got = $true }
          if (-not $got) {
            # 显示器还没缓过来：再等一会重写一次并复读
            Start-Sleep -Milliseconds 200
            [void][ClearyNative]::SetMonitorBrightness($ph,[uint32]$v)
            Start-Sleep -Milliseconds 150
            $min=0;$cur=0;$max=0
            if ([ClearyNative]::GetMonitorBrightness($ph,[ref]$min,[ref]$cur,[ref]$max)) { $got = $true }
          }
          if ($got) { $last = [int]$cur }
        }
      } finally {
        try { [void][ClearyNative]::DestroyPhysicalMonitors($n,$arr) } catch {}
      }
    }
  } catch {}
  $script:lastBrightApplied = $v
  if ($last -ge 0) { $script:lastBrightRead = $last } else { $script:lastBrightRead = -1 }
  return $last
}

function Apply-Contrast([int]$v, [switch]$Force) {
  if (-not $Force -and $script:lastContrastApplied -eq $v -and $script:lastContrastRead -ge 0) {
    return $script:lastContrastRead
  }
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
          # 同 Apply-Brightness：不要因 $ph 为 0 就跳过（单显示器下 dxva2 就是返回 0，
          # 但读写正常）。Zero 判断会让整个写屏静默失效。
          # I2C 通道慢，写后必须留静默时间 + 失败重试
          $ok = [ClearyNative]::SetMonitorContrast($ph,[uint32]$v)
          if (-not $ok) {
            Start-Sleep -Milliseconds 150
            $ok = [ClearyNative]::SetMonitorContrast($ph,[uint32]$v)
          }
          Start-Sleep -Milliseconds 110
          $got = $false
          $min=0;$cur=0;$max=0
          if ([ClearyNative]::GetMonitorContrast($ph,[ref]$min,[ref]$cur,[ref]$max)) { $got = $true }
          if (-not $got) {
            Start-Sleep -Milliseconds 200
            [void][ClearyNative]::SetMonitorContrast($ph,[uint32]$v)
            Start-Sleep -Milliseconds 150
            $min=0;$cur=0;$max=0
            if ([ClearyNative]::GetMonitorContrast($ph,[ref]$min,[ref]$cur,[ref]$max)) { $got = $true }
          }
          if ($got) { $last = [int]$cur }
        }
      } finally {
        try { [void][ClearyNative]::DestroyPhysicalMonitors($n,$arr) } catch {}
      }
    }
  } catch {}
  $script:lastContrastApplied = $v
  if ($last -ge 0) { $script:lastContrastRead = $last } else { $script:lastContrastRead = -1 }
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
      if (-not [ClearyNative]::EnumDisplayDevicesPtr([IntPtr]::Zero, [uint32]$dev, [ref]$dd, 0)) { break }
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
  # VERIFIED 2026-09-07 (Session4/WinSta0 live): SPI_SETFONTSMOOTHINGGAMMA(0x200F)
  # and SPI_SETFONTSMOOTHINGORIENTATION(0x2011) both CORRUPT the live value to a
  # ~3.2-billion garbage DWORD on this host and CANNOT be reverted via SPI — exactly
  # the Java-Swing crash scenario the old comment warned about (old constants were also
  # wrong: 0x200C/D = CONTRAST, 0x2012/3 = undefined). Only registry persistence is safe:
  # Windows reloads gamma/orientation from HKCU\Control Panel\Desktop at next logon.
  # ClearType on/off + TYPE via SPI above DO take effect live on GDI/legacy text.
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
    if ($null -ne $j.batteryAlertEnabled) { $d.batteryAlertEnabled = [bool]$j.batteryAlertEnabled }
    if ($j.batteryAlertThreshold) {
      $tv = [int]$j.batteryAlertThreshold
      if ($tv -ge 10 -and $tv -le 95) { $d.batteryAlertThreshold = $tv }
    }
    if ($null -ne $j.blackoutReportEnabled) { $d.blackoutReportEnabled = [bool]$j.blackoutReportEnabled }
    if ($null -ne $j.windowTopmost) { $d.windowTopmost = [bool]$j.windowTopmost }
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
    batteryAlertEnabled = if ($null -ne $s.batteryAlertEnabled) { [bool]$s.batteryAlertEnabled } else { $true }
    batteryAlertThreshold = if ($s.batteryAlertThreshold) { [int]$s.batteryAlertThreshold } else { 73 }
    blackoutReportEnabled = if ($null -ne $s.blackoutReportEnabled) { [bool]$s.blackoutReportEnabled } else { $true }
    windowTopmost = if ($null -ne $s.windowTopmost) { [bool]$s.windowTopmost } else { $false }
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
    (Join-Path $script:appDir 'src\ApplyProfile.ps1'),
    (Join-Path $script:appDir 'ApplyProfile.ps1'),
    (Join-Path $baseDir 'ApplyProfile.ps1'),
    'D:\ClearyDisplay\src\ApplyProfile.ps1'
  )
  $srcCmdCandidates = @(
    (Join-Path $script:appDir 'src\ApplyProfile.cmd'),
    (Join-Path $script:appDir 'ApplyProfile.cmd'),
    (Join-Path $baseDir 'ApplyProfile.cmd'),
    'D:\ClearyDisplay\src\ApplyProfile.cmd'
  )
  # 只在「源比部署副本新」或「大小不同」时覆盖：避免把较新的部署副本降级成旧源，
  # 也避免每次启动都无谓重写（曾因此让 ApplyProfile.ps1 卡在几周前的旧版本）。
  foreach ($c in $srcPs1Candidates) {
    if (-not $c -or -not (Test-Path $c) -or ($c -eq $ps1)) { continue }
    try {
      $need = $true
      if (Test-Path $ps1) {
        $sf = Get-Item $c; $tf = Get-Item $ps1
        $need = ($sf.LastWriteTime -gt $tf.LastWriteTime) -or ($sf.Length -ne $tf.Length)
      }
      if ($need) { Copy-Item -Force $c $ps1 }
      break
    } catch {}
  }
  foreach ($c in $srcCmdCandidates) {
    if (-not $c -or -not (Test-Path $c) -or ($c -eq $cmd)) { continue }
    try {
      $need = $true
      if (Test-Path $cmd) {
        $sf = Get-Item $c; $tf = Get-Item $cmd
        $need = ($sf.LastWriteTime -gt $tf.LastWriteTime) -or ($sf.Length -ne $tf.Length)
      }
      if ($need) { Copy-Item -Force $c $cmd }
      break
    } catch {}
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
    appTitle = '天选打工人专用小工具'
    langTip = '切换到 English'
    statusAc = '当前：已接电源（AC）'
    statusBat = '当前：电池供电'
    tabDisplay = '显示'
    tabFont = '字体'
    tabCalc = '汇率'
    tabDraw = '画图'
    tabTheme = '主题'
    powerTitle = '电源配置档'
    powerDesc = '分别为「接电」和「电池」保存独立参数。供电变化时单选与滑条会自动切换；不会自动改屏幕亮度，需点「立即应用」。'
    powerSwitchedAc = '已切换到接电档参数（屏幕未改，点「立即应用」写入）'
    powerSwitchedBat = '已切换到电池档参数（屏幕未改，点「立即应用」写入）'
    rbAc = '接电状态'
    rbBat = '电池状态'
    batAlertTitle = '低电量插电提醒'
    batAlertDesc = '电池供电时，电量降到设定值就弹窗提醒插电，避免掉电黑屏。'
    batAlertEnable = '启用低电量提醒（仅电池供电时）'
    batAlertThreshold = '提醒阈值'
    batAlertHint = '建议 70% 以上。本机电池已老化（实测低于 70% 且外接显示器时有掉电记录），留足余量更稳。'
    batAlertNowFmt = '{0} · 电量 {1}%'
    batAlertNoBattery = '未检测到电池'
    batAlertMsgFmt = '电池电量已降到 {0}%（提醒阈值 {1}%）。外接显示器时低于 70% 可能突然掉电黑屏，请立即插上电源！'
    batAlertTitleBox = '请插上电源'
    blackoutEnable = '如果黑屏，重启后提供黑屏报告'
    blackoutDesc = '系统异常掉电黑屏后，重启时自动比对关机/开机事件，给出黑屏报告。'
    blackoutBtn = '黑屏报告'
    blackoutHintNone = '暂无黑屏记录'
    blackoutHintFoundFmt = '上次黑屏 {0} · 电量 {1}%'
    blackoutTitle = '黑屏报告'
    blackoutAskFmt = '检测到上次是黑屏（异常掉电）后重启。{0}黑屏报告已生成，现在查看？'
    blackoutOpenFail = '报告已生成，但自动打开失败，请手动打开：'
    envTitle = '环境自动切换'
    envDesc = '记住「显示器 + 网络」组合：换到办公室或家庭时，自动载入对应的命名方案。'
    envEnable = '按环境自动切换方案'
    envAutoApply = '切换时自动写入屏幕'
    envNowLabel = '当前环境'
    envPresetLabel = '关联方案'
    btnEnvBind = '绑定当前环境'
    btnEnvUnbind = '解除绑定'
    envNone = '尚未绑定任何环境'
    envScanning = '识别中…'
    envUnknown = '未识别到显示器 / 网络'
    envNeedPreset = '请先选择要关联的方案'
    envBindOkFmt = '已把当前环境绑定到方案「{0}」'
    envUnbindOkFmt = '已解除方案「{0}」的环境绑定'
    envSwitchedFmt = '已按环境切换到方案「{0}」'
    envAppliedFmt = '已按环境切换到方案「{0}」并写入屏幕'
    topmostLabel = '窗口置顶'
    topmostTip = '勾选后本窗口始终显示在其他程序之上（默认关闭）'
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
    presetDesc = '把「接电 + 电池」两套参数另存为方案，方便随时切换。'
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
    clearTypeDesc = 'Windows 系统级 ClearType 文字渲染。开关对传统程序（旧版记事本/资源管理器）即时生效；Chrome/Edge/系统新界面用灰度抗锯齿，不受影响。伽马与子像素方向写入后需注销登录才完全生效。'
    enableClearType = '启用 ClearType'
    fontGamma = '字体平滑伽马'
    fontGammaHint = '通常 1.0～2.2，仅影响 ClearType 渲染的传统程序（旧版记事本/资源管理器等）。Chrome/Edge/系统新界面为灰度抗锯齿，几乎不受影响。本机无法实时修改字体伽马，写入后需「注销并重新登录」才完全生效。'
    subpixel = '子像素排列'
    rgbCommon = 'RGB（常见）'
    btnApplyFont = '应用字体设置'
    btnClearTypeWizard = '打开系统 ClearType 向导'
    previewTitle = '预览'
    previewDesc = '下面文字用于观察边缘是否舒服（宋体/雅黑混排）。'
    previewSample = '天选打工人专用小工具 ClearyDisplay'
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
    numEditTip = '点数字直接输入，回车生效'
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
    fontApplied = '字体设置已写入。ClearType 开关即时生效；伽马/子像素方向需「注销并重新登录」后完全生效。'
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
    appTitle = 'Chosen Worker Toolkit'
    langTip = 'Switch to 中文'
    statusAc = 'Power: AC plugged in'
    statusBat = 'Power: On battery'
    tabDisplay = 'Display'
    tabFont = 'Font'
    tabCalc = 'FX'
    tabDraw = 'Draw'
    tabTheme = 'Theme'
    powerTitle = 'Power profiles'
    powerDesc = 'Separate AC/battery settings. Radios and sliders follow power changes; screen brightness is not auto-written — click Apply.'
    powerSwitchedAc = 'Switched to AC profile (screen unchanged — click Apply)'
    powerSwitchedBat = 'Switched to battery profile (screen unchanged — click Apply)'
    rbAc = 'On AC'
    rbBat = 'On battery'
    batAlertTitle = 'Low battery plug-in alert'
    batAlertDesc = 'On battery, pop up a reminder when charge drops to the set level - avoids sudden power loss with an external monitor.'
    batAlertEnable = 'Enable low battery alert (battery only)'
    batAlertThreshold = 'Alert threshold'
    batAlertHint = 'Recommended above 70%. This battery is worn (power-loss events recorded below 70% with an external monitor), so leave headroom.'
    batAlertNowFmt = '{0} · {1}% charge'
    batAlertNoBattery = 'No battery detected'
    batAlertMsgFmt = 'Battery is at {0}% (alert threshold {1}%). With an external monitor, below 70% the system can lose power without warning - plug in now!'
    batAlertTitleBox = 'Plug in the charger'
    blackoutEnable = 'If the screen blacks out, show a report after reboot'
    blackoutDesc = 'After an unexpected power loss, shutdown/boot events are compared on the next start and a report is produced.'
    blackoutBtn = 'Blackout report'
    blackoutHintNone = 'No blackout recorded yet'
    blackoutHintFoundFmt = 'Last blackout {0} · {1}% charge'
    blackoutTitle = 'Blackout report'
    blackoutAskFmt = 'The last shutdown looks like a blackout (unexpected power loss). {0}A report has been generated. Open it now?'
    blackoutOpenFail = 'Report generated, but it could not be opened automatically: '
    envTitle = 'Environment auto-switch'
    envDesc = 'Remembers a display + network combination and loads the matching named preset when you move between office and home.'
    envEnable = 'Auto-switch presets by environment'
    envAutoApply = 'Write to screen on switch'
    envNowLabel = 'Current environment'
    envPresetLabel = 'Linked preset'
    btnEnvBind = 'Bind current environment'
    btnEnvUnbind = 'Unbind'
    envNone = 'No environment bound yet'
    envScanning = 'Detecting...'
    envUnknown = 'No display / network detected'
    envNeedPreset = 'Pick a preset to link first'
    envBindOkFmt = 'Current environment bound to preset "{0}"'
    envUnbindOkFmt = 'Unbound preset "{0}"'
    envSwitchedFmt = 'Switched to preset "{0}" by environment'
    envAppliedFmt = 'Switched to preset "{0}" and wrote to screen'
    topmostLabel = 'Always on top'
    topmostTip = 'Keep this window above other programs (off by default)'
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
    clearTypeDesc = 'Windows system ClearType text rendering. The on/off toggle takes effect live for legacy apps (classic Notepad, Explorer); Chrome/Edge and modern UI use grayscale AA and are unaffected. Gamma/orientation fully apply after sign-out & back in.'
    enableClearType = 'Enable ClearType'
    fontGamma = 'Font smoothing gamma'
    fontGammaHint = 'Usually 1.0-2.2; affects only ClearType-rendered legacy apps (classic Notepad/Explorer). Chrome/Edge/modern UI use grayscale AA and show little change. Live gamma change is unsupported on this PC - it fully applies after sign-out & back in.'
    subpixel = 'Subpixel layout'
    rgbCommon = 'RGB (common)'
    btnApplyFont = 'Apply font settings'
    btnClearTypeWizard = 'Open ClearType wizard'
    previewTitle = 'Preview'
    previewDesc = 'Sample text to judge edge comfort (serif / sans mix).'
    previewSample = 'Chosen Worker Toolkit ClearyDisplay'
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
    numEditTip = 'Click a number to type; press Enter to apply'
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
    fontApplied = 'Font settings written. ClearType toggle is live; gamma/orientation fully apply after sign-out & back in.'
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
        FxRowHover='#EFF7FF'
        GhostBg='#FFFFFF'; TrackBg='#1A7F37'
        InputBg='#FFFFFF'; InputBorder='#D0D7DE'; ThumbFill='#FFFFFF'
      }
    }
    'apple' {
      return @{
        WinBg='#F5F5F7'; CardBg='#FFFFFF'; CardBorder='#C7C7CC'
        TextPrimary='#1D1D1F'; TextSecondary='#6E6E73'; TextMuted='#86868B'
        Accent='#0071E3'; AccentSoft='#E8F1FB'; BrandAlt='#BF5AF2'
        FxRowHover='#F4F8FD'
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
        FxRowHover='#F2F7FC'
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
        FxRowHover='#EDF4FE'
        GhostBg='#FFFFFF'; TrackBg='#EA4335'
        InputBg='#FFFFFF'; InputBorder='#1A73E8'; ThumbFill='#FFFFFF'
      }
    }
    'dark' {
      return @{
        WinBg='#1C1C1E'; CardBg='#2C2C2E'; CardBorder='#3A3A3C'
        TextPrimary='#F2F2F7'; TextSecondary='#A1A1A6'; TextMuted='#8E8E93'
        Accent='#0A84FF'; AccentSoft='#1A3A5C'; BrandAlt='#FF9F0A'
        FxRowHover='#242A33'
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
        FxRowHover='#F5F8FF'
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
  if ($TabCalc) { $TabCalc.Header = (T 'tabCalc') }
  if ($TabDraw) { $TabDraw.Header = (T 'tabDraw') }
  if ($TabTheme) { $TabTheme.Header = (T 'tabTheme') }

  if ($TxtPowerTitle) { $TxtPowerTitle.Text = (T 'powerTitle') }
  if ($TxtBatAlertTitle) { $TxtBatAlertTitle.Text = (T 'batAlertTitle') }
  if ($TxtBatAlertDesc) { $TxtBatAlertDesc.Text = (T 'batAlertDesc') }
  if ($ChkBatAlert) { $ChkBatAlert.Content = (T 'batAlertEnable') }
  if ($TxtBatAlertThreshold) { $TxtBatAlertThreshold.Text = (T 'batAlertThreshold') }
  if ($TxtBatAlertHint) { $TxtBatAlertHint.Text = (T 'batAlertHint') }
  if ($TxtBlackoutTitle) { $TxtBlackoutTitle.Text = (T 'blackoutTitle') }
  if ($TxtBlackoutDesc) { $TxtBlackoutDesc.Text = (T 'blackoutDesc') }
  if ($ChkBlackout) { $ChkBlackout.Content = (T 'blackoutEnable') }
  if ($BtnBlackoutReport) { $BtnBlackoutReport.Content = (T 'blackoutBtn') }
  if ($TxtBlackoutHint) { Update-BlackoutHint }
  if ($TxtEnvTitle) { $TxtEnvTitle.Text = (T 'envTitle') }
  if ($TxtEnvDesc) { $TxtEnvDesc.Text = (T 'envDesc') }
  if ($ChkEnvAuto) { $ChkEnvAuto.Content = (T 'envEnable') }
  if ($ChkEnvApply) { $ChkEnvApply.Content = (T 'envAutoApply') }
  if ($TxtEnvNowLabel) { $TxtEnvNowLabel.Text = (T 'envNowLabel') }
  if ($TxtEnvPresetLabel) { $TxtEnvPresetLabel.Text = (T 'envPresetLabel') }
  if ($BtnEnvBind) { $BtnEnvBind.Content = (T 'btnEnvBind') }
  if ($BtnEnvUnbind) { $BtnEnvUnbind.Content = (T 'btnEnvUnbind') }
  if ($ChkTopmost) { $ChkTopmost.Content = (T 'topmostLabel'); $ChkTopmost.ToolTip = (T 'topmostTip') }
  if ($TxtEnvList) { Update-EnvUi }
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
  if ($TxtNumEditHint) { $TxtNumEditHint.Text = (T 'numEditTip') }
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

# =====================================================================
# 计算板块 —— 数字转英文大写 / 计算器 / 中国银行汇率
# 画图板块 —— 去背景（C# 内联内核 ClearyBg，零外部依赖）
# 2026-09-20 新增
# =====================================================================

# ---------------- 数字转英文大写 ----------------
# 移植自外贸小宝 core/amount_words.py，英式商业风格（百位与十位间带 AND）。
$script:W_ONES = @('', 'ONE', 'TWO', 'THREE', 'FOUR', 'FIVE', 'SIX', 'SEVEN', 'EIGHT',
  'NINE', 'TEN', 'ELEVEN', 'TWELVE', 'THIRTEEN', 'FOURTEEN', 'FIFTEEN',
  'SIXTEEN', 'SEVENTEEN', 'EIGHTEEN', 'NINETEEN')
$script:W_TENS = @('', '', 'TWENTY', 'THIRTY', 'FORTY', 'FIFTY', 'SIXTY', 'SEVENTY',
  'EIGHTY', 'NINETY')
$script:W_SCALES = @('', 'THOUSAND', 'MILLION', 'BILLION', 'TRILLION', 'QUADRILLION')

function ConvertTo-WordsUnder1000 {
  param([int]$n, [bool]$useAnd)
  $parts = New-Object System.Collections.ArrayList
  $h = [int][Math]::Floor($n / 100)
  $r = $n % 100
  if ($h -gt 0) { [void]$parts.Add($script:W_ONES[$h] + ' HUNDRED') }
  if ($r -gt 0) {
    if ($h -gt 0 -and $useAnd) { [void]$parts.Add('AND') }
    if ($r -lt 20) {
      [void]$parts.Add($script:W_ONES[$r])
    } else {
      $t = [int][Math]::Floor($r / 10)
      $o = $r % 10
      if ($o -gt 0) { [void]$parts.Add($script:W_TENS[$t] + ' ' + $script:W_ONES[$o]) }
      else { [void]$parts.Add($script:W_TENS[$t]) }
    }
  }
  return ($parts -join ' ')
}

function ConvertTo-IntegerWords {
  param([long]$n, [bool]$useAnd = $true)
  if ($n -eq 0) { return 'ZERO' }
  $neg = ($n -lt 0)
  if ($neg) { $n = -$n }
  $groups = New-Object System.Collections.ArrayList
  while ($n -gt 0) {
    [void]$groups.Add([int]($n % 1000))
    $n = [long][Math]::Floor($n / 1000)
  }
  $parts = New-Object System.Collections.ArrayList
  for ($i = $groups.Count - 1; $i -ge 0; $i--) {
    $gg = $groups[$i]
    if ($gg -gt 0) {
      $w = ConvertTo-WordsUnder1000 $gg $useAnd
      if ($i -lt $script:W_SCALES.Count -and $script:W_SCALES[$i]) {
        $w = $w + ' ' + $script:W_SCALES[$i]
      }
      [void]$parts.Add($w)
    }
  }
  $res = ($parts -join ' ')
  if ($neg) { $res = 'MINUS ' + $res }
  return $res
}

# 从剪贴板/单元格原始文本里解析金额。支持 1,234.56 / $1,234.56 / USD 24108 / (500)
function ConvertFrom-AmountText {
  param([string]$Raw)
  if ([string]::IsNullOrWhiteSpace($Raw)) { return $null }
  $s = $Raw.Trim()
  $neg = $false
  if ($s.StartsWith('(') -and $s.EndsWith(')')) { $neg = $true; $s = $s.Substring(1, $s.Length - 2).Trim() }
  $s = [regex]::Replace($s, '[\u00A5\u0024\u20AC\u00A3\u20A9\u20BD]', '')
  $s = [regex]::Replace($s, '\b(USD|EUR|GBP|JPY|HKD|CNY|RMB|AUD|CAD|CHF|SGD|NZD)\b', '',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
  # 注意：',' 和 ' ' 在 PowerShell 里是字符串，会匹配 Replace(string,string)；
  # 而 [char]0x00A0 是字符，重载会偏向 Replace(char,char) 并把 '' 转 char 失败。
  # 必须显式 ToString() 统一成字符串重载，否则整条赋值语句抛异常回滚，
  # 导致所有含逗号/空格的金额（1,234.56 / "USD 24108"）静默返回空。
  $s = $s.Replace(',', '').Replace(' ', '').Replace(([char]0x00A0).ToString(), '')
  $s = $s.TrimEnd('.')
  if ($s.StartsWith('-')) { $neg = $true; $s = $s.Substring(1) }
  elseif ($s.StartsWith('+')) { $s = $s.Substring(1) }
  if (-not [regex]::IsMatch($s, '^\d+(\.\d+)?$')) { return $null }
  $v = 0.0
  if (-not [double]::TryParse($s, [System.Globalization.NumberStyles]::Float,
        [System.Globalization.CultureInfo]::InvariantCulture, [ref]$v)) { return $null }
  if ($neg) { $v = -$v }
  return $v
}

function ConvertTo-AmountEnglish {
  param([string]$Raw, [string]$Currency = 'USD', [string]$Prefix = 'SAY TOTAL ',
        [string]$Suffix = ' ONLY.', [bool]$UseAnd = $true,
        [string]$CentsTemplate = 'AND {cents} CENTS')
  $val = ConvertFrom-AmountText $Raw
  if ($null -eq $val) { return $null }
  $neg = ($val -lt 0)
  $val = [Math]::Abs($val)
  $ip = [long][Math]::Floor($val)
  $cents = [int][Math]::Round(($val - $ip) * 100.0)
  if ($cents -eq 100) { $ip = $ip + 1; $cents = 0 }
  if ($ip -gt 0) { $iw = ConvertTo-IntegerWords $ip $UseAnd } else { $iw = 'ZERO' }
  if ($neg) { $iw = 'MINUS ' + $iw }
  $body = $iw
  if ($cents -gt 0) {
    $cw = ConvertTo-IntegerWords ([long]$cents) $UseAnd
    $body = $body + ' ' + $CentsTemplate.Replace('{cents}', $cw)
  }
  return ($Prefix + $Currency + ' ' + $body + $Suffix)
}

# ---------------- 计算器 ----------------
$script:calcCur = '0'
$script:calcAcc = $null
$script:calcOp = $null
$script:calcFresh = $true
$script:calcExpr = ''
$script:calcErr = $false

function Format-CalcNumber {
  param([double]$v)
  if ([double]::IsNaN($v) -or [double]::IsInfinity($v)) { return '错误' }
  $a = [Math]::Abs($v)
  if ($a -ne 0 -and ($a -ge 1e15 -or $a -lt 1e-9)) { return $v.ToString('0.##########E+0') }
  $s = $v.ToString('0.#############')
  if ($s -eq '-0') { return '0' }
  return $s
}

function Show-CalcDisplay {
  if ($TxtCalcDisp) { $TxtCalcDisp.Text = (Format-CalcDisplayText $script:calcCur) }
  if ($TxtCalcExpr) { $TxtCalcExpr.Text = $script:calcExpr }
  # 读数一变就把金额栏同步过去并重算英文大写：计算器和大写从此是一根链条
  Sync-CaseAmountFromCalc
}

# 显示层千分位：只在「画到屏幕」这一步插逗号。
# $script:calcCur 始终保持裸数字串，Get-CalcCurrent / 连乘连除都读它，
# 所以加逗号不会污染任何计算路径（Format-CalcNumber 本身也不动）。
function Format-CalcDisplayText {
  param([string]$s)
  if ([string]::IsNullOrEmpty($s)) { return '0' }
  if ($s -eq '错误') { return $s }
  # 指数形式（1.23E+20）不加千分位，否则尾数会被逗号拆坏
  if ($s.IndexOf('E') -ge 0 -or $s.IndexOf('e') -ge 0) { return $s }
  $neg = $s.StartsWith('-')
  $body = $s
  if ($neg) { $body = $s.Substring(1) }
  $dot = $body.IndexOf('.')
  if ($dot -ge 0) {
    $ip = $body.Substring(0, $dot)
    $fp = $body.Substring($dot)
  } else {
    $ip = $body
    $fp = ''
  }
  if ($ip.Length -gt 3) {
    $sb = New-Object System.Text.StringBuilder
    $n = $ip.Length
    for ($i = 0; $i -lt $n; $i++) {
      if ($i -gt 0 -and (($n - $i) % 3) -eq 0) { [void]$sb.Append(',') }
      [void]$sb.Append($ip[$i])
    }
    $ip = $sb.ToString()
  }
  $out = $ip + $fp
  if ($neg) { $out = '-' + $out }
  return $out
}

function Get-CalcCurrent {
  $v = 0.0
  [void][double]::TryParse($script:calcCur, [System.Globalization.NumberStyles]::Float,
        [System.Globalization.CultureInfo]::InvariantCulture, [ref]$v)
  return $v
}

function Set-CalcError {
  param([string]$Msg)
  $script:calcErr = $true
  $script:calcCur = $Msg
  $script:calcAcc = $null
  $script:calcOp = $null
  $script:calcExpr = ''
  $script:calcFresh = $true
  Show-CalcDisplay
}

function Invoke-CalcClearAll {
  $script:calcCur = '0'; $script:calcAcc = $null; $script:calcOp = $null
  $script:calcFresh = $true; $script:calcExpr = ''; $script:calcErr = $false
  Show-CalcDisplay
}

function Invoke-CalcClearEntry {
  if ($script:calcErr) { Invoke-CalcClearAll; return }
  $script:calcCur = '0'; $script:calcFresh = $true
  Show-CalcDisplay
}

function Invoke-CalcDigit {
  param([string]$d)
  if ($script:calcErr) { Invoke-CalcClearAll }
  if ($script:calcFresh) { $script:calcCur = $d; $script:calcFresh = $false }
  elseif ($script:calcCur -eq '0') { $script:calcCur = $d }
  elseif ($script:calcCur -eq '-0') { $script:calcCur = '-' + $d }
  else {
    $digits = $script:calcCur.Replace('-', '').Replace('.', '').Length
    if ($digits -lt 15) { $script:calcCur = $script:calcCur + $d }
  }
  Show-CalcDisplay
}

function Invoke-CalcDot {
  if ($script:calcErr) { Invoke-CalcClearAll }
  if ($script:calcFresh) { $script:calcCur = '0.'; $script:calcFresh = $false }
  elseif (-not $script:calcCur.Contains('.')) { $script:calcCur = $script:calcCur + '.' }
  Show-CalcDisplay
}

function Invoke-CalcBack {
  if ($script:calcErr) { Invoke-CalcClearAll; return }
  if ($script:calcFresh) { return }
  if ($script:calcCur.Length -le 1) {
    $script:calcCur = '0'; $script:calcFresh = $true
  } else {
    $script:calcCur = $script:calcCur.Substring(0, $script:calcCur.Length - 1)
    if ($script:calcCur -eq '-' -or $script:calcCur -eq '') {
      $script:calcCur = '0'; $script:calcFresh = $true
    }
  }
  Show-CalcDisplay
}

function Get-CalcOpSymbol {
  param([string]$o)
  switch ($o) {
    '+' { return '+' }
    '-' { return [char]0x2212 }
    '*' { return [char]0x00D7 }
    '/' { return [char]0x00F7 }
  }
  return $o
}

function Invoke-CalcApply {
  param([string]$o, [double]$a, [double]$b)
  switch ($o) {
    '+' { return $a + $b }
    '-' { return $a - $b }
    '*' { return $a * $b }
    '/' { if ($b -eq 0) { return [double]::NaN }; return $a / $b }
  }
  return $b
}

function Invoke-CalcOp {
  param([string]$o)
  if ($script:calcErr) { return }
  $cur = Get-CalcCurrent
  if ($null -ne $script:calcOp -and -not $script:calcFresh) {
    $res = Invoke-CalcApply $script:calcOp ([double]$script:calcAcc) $cur
    if ([double]::IsNaN($res)) { Set-CalcError '除数不能为零'; return }
    $script:calcAcc = $res
    $script:calcCur = Format-CalcNumber $res
  } else {
    $script:calcAcc = $cur
  }
  $script:calcOp = $o
  $script:calcFresh = $true
  $script:calcExpr = (Format-CalcNumber ([double]$script:calcAcc)) + ' ' + (Get-CalcOpSymbol $o)
  Show-CalcDisplay
}

function Invoke-CalcEquals {
  if ($script:calcErr) { return }
  if ($null -eq $script:calcOp) { $script:calcExpr = ''; Show-CalcDisplay; return }
  $cur = Get-CalcCurrent
  $a = [double]$script:calcAcc
  $res = Invoke-CalcApply $script:calcOp $a $cur
  if ([double]::IsNaN($res)) { Set-CalcError '除数不能为零'; return }
  $script:calcExpr = (Format-CalcNumber $a) + ' ' + (Get-CalcOpSymbol $script:calcOp) + ' ' +
                     (Format-CalcNumber $cur) + ' ='
  $script:calcCur = Format-CalcNumber $res
  $script:calcAcc = $res
  $script:calcOp = $null
  $script:calcFresh = $true
  Show-CalcDisplay
}

function Invoke-CalcUnary {
  param([string]$k)
  if ($script:calcErr) { return }
  $cur = Get-CalcCurrent
  switch ($k) {
    'neg' { $cur = -$cur }
    'pct' { $cur = $cur / 100.0 }
    'inv' { if ($cur -eq 0) { Set-CalcError '除数不能为零'; return } else { $cur = 1.0 / $cur } }
    'sqr' { $cur = $cur * $cur }
    'sqrt' {
      if ($cur -lt 0) { Set-CalcError '无效输入'; return }
      $cur = [Math]::Sqrt($cur)
    }
  }
  $script:calcCur = Format-CalcNumber $cur
  $script:calcFresh = $true
  Show-CalcDisplay
}

# ---------------- 中国银行汇率 ----------------
# 只放常用 4 种；要增减币种改这一行即可（名称须与中行牌价表完全一致）。
$script:FX_WANT = @(
  @{ name = '美元'; code = 'USD' },
  @{ name = '欧元'; code = 'EUR' },
  @{ name = '英镑'; code = 'GBP' },
  @{ name = '日元'; code = 'JPY' }
)
$script:fxRows = @()
$script:fxUpdated = ''
$script:fxEls = @()

function Get-FxStatusText {
  if ($script:fxUpdated) { return ('上次更新：' + $script:fxUpdated) }
  return '尚未获取牌价'
}

function Update-FxUi {
  for ($i = 0; $i -lt $script:FX_WANT.Count; $i++) {
    if ($i -ge $script:fxEls.Count) { break }
    $nm = $script:FX_WANT[$i].name
    $row = $null
    foreach ($r in $script:fxRows) { if ($r.name -eq $nm) { $row = $r; break } }
    $e = $script:fxEls[$i]
    if ($e.name) { $e.name.Text = $nm + ' / ' + $script:FX_WANT[$i].code }
    if ($row) {
      if ($e.buy) { $e.buy.Text = (Convert-Rate100To1 $row.buy) }
    } else {
      if ($e.buy) { $e.buy.Text = '--' }
    }
  }
  if ($TxtFxStatus) { $TxtFxStatus.Text = Get-FxStatusText }
}

# 中行的价格是「每 100 外币兑人民币」，换算成 1 外币兑人民币保留 4 位
function Convert-Rate100To1 {
  param([string]$s)
  if ([string]::IsNullOrWhiteSpace($s)) { return '--' }
  $v = 0.0
  if (-not [double]::TryParse($s, [System.Globalization.NumberStyles]::Float,
        [System.Globalization.CultureInfo]::InvariantCulture, [ref]$v)) { return '--' }
  if ($v -le 0) { return '--' }
  return ($v / 100.0).ToString('0.0000')
}

# 抓取 / 释放 逻辑严格对齐 J:\EXCHANGER\fx-helper-v2（core/rate.py + app.py），
# 只是把 requests 换成 .NET 的 HttpWebRequest：
#   · 抓取：单次 GET，带浏览器 UA；只有「超时 / 连不上」这类网络异常才重试，
#           最多 3 次；HTTP 错误或解析不出数据一律立即放弃（等价 rate.py 的
#           except Timeout/ConnectionError → retry，except Exception → 直接 return None）。
#   · 释放：每次请求的 response / stream / reader 都在 finally 里 Dispose，
#           连接不滞留（等价 requests 的会话释放）。
#   · 闸门：$script:fxFetching 等价 self._crawling（threading.Lock），
#           acquire(blocking=False) 抢不到就回「正在抓取中，请稍候」，
#           release 固定放在 finally，任何异常路径都会放锁。
$script:FX_URL = 'https://www.boc.cn/sourcedb/whpj/'
$script:FX_UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
$script:FX_TIMEOUT_MS = 15000
$script:FX_MAX_RETRIES = 3
$script:fxFetching = $false

# 判断异常是否属于「值得重试」的网络类异常（对齐 rate.py 的 Timeout / ConnectionError）
function Test-FxRetryable {
  param($Ex)
  if ($null -eq $Ex) { return $false }
  if ($Ex -is [System.TimeoutException]) { return $true }
  if ($Ex -is [System.Net.WebException]) {
    $st = $Ex.Status
    foreach ($ok in @('Timeout', 'ConnectFailure', 'NameResolutionFailure',
                      'ProxyNameResolutionFailure', 'SendFailure',
                      'ReceiveFailure', 'ConnectionClosed', 'Pending')) {
      if ($st.ToString() -eq $ok) { return $true }
    }
    return $false
  }
  return $false
}

function Get-BocRateTable {
  # 返回 ArrayList（每项一个 hashtable）；彻底失败返回 $null。
  for ($attempt = 0; $attempt -lt $script:FX_MAX_RETRIES; $attempt++) {
    $resp = $null
    $stream = $null
    $reader = $null
    $html = $null
    try {
      $req = [System.Net.HttpWebRequest][System.Net.WebRequest]::Create($script:FX_URL)
      $req.Method = 'GET'
      $req.UserAgent = $script:FX_UA
      $req.Timeout = $script:FX_TIMEOUT_MS
      $req.ReadWriteTimeout = $script:FX_TIMEOUT_MS
      $req.Proxy = [System.Net.WebRequest]::DefaultWebProxy
      $req.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
      $resp = $req.GetResponse()
      $stream = $resp.GetResponseStream()
      $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
      $html = $reader.ReadToEnd()
    } catch {
      $inner = $_.Exception
      while ($inner -and $inner.InnerException) { $inner = $inner.InnerException }
      if ((Test-FxRetryable $inner) -and $attempt -lt ($script:FX_MAX_RETRIES - 1)) {
        continue
      }
      return $null
    } finally {
      # 释放：reader → stream → response，倒序关掉，别把连接挂住
      if ($reader) { try { $reader.Dispose() } catch {} }
      elseif ($stream) { try { $stream.Dispose() } catch {} }
      if ($resp) { try { $resp.Dispose() } catch {} }
    }

    if ([string]::IsNullOrEmpty($html)) { return $null }

    $rows = New-Object System.Collections.ArrayList
    $opt = [System.Text.RegularExpressions.RegexOptions]::Singleline
    foreach ($tr in [regex]::Matches($html, '<tr[^>]*>(.*?)</tr>', $opt)) {
      $tds = [regex]::Matches($tr.Groups[1].Value, '<td[^>]*>(.*?)</td>', $opt)
      if ($tds.Count -lt 7) { continue }
      # tds 顺序与 rate.py 一致：0 货币名称 1 现汇买入 2 现钞买入
      #                      3 现汇卖出 4 现钞卖出 5 中行折算 6 发布时间
      $cells = New-Object System.Collections.ArrayList
      foreach ($td in $tds) {
        # 先剥标签再解实体（等价 BeautifulSoup 的 get_text().strip()）
        $txt = [regex]::Replace($td.Groups[1].Value, '<[^>]+>', '')
        try { $txt = [System.Net.WebUtility]::HtmlDecode($txt) } catch {}
        [void]$cells.Add($txt.Trim())
      }
      $nm = $cells[0]
      $hit = $null
      foreach ($want in $script:FX_WANT) { if ($want.name -eq $nm) { $hit = $want; break } }
      if (-not $hit) { continue }
      [void]$rows.Add(@{
        name = $nm; code = $hit.code
        buy = $cells[1]; buyCash = $cells[2]; sell = $cells[3]
        sellCash = $cells[4]; mid = $cells[5]; time = $cells[6]
      })
    }
    if ($rows.Count -gt 0) { return $rows }
    return $null
  }
  return $null
}

function Save-FxCache {
  try {
    $p = Join-Path $baseDir 'fx-cache.json'
    $o = @{ updated = $script:fxUpdated; rows = $script:fxRows }
    ($o | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $p -Encoding UTF8
  } catch {}
}

function Load-FxCache {
  try {
    $p = Join-Path $baseDir 'fx-cache.json'
    if (-not (Test-Path $p)) { return }
    $o = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($o.rows) { $script:fxRows = @($o.rows) }
    if ($o.updated) { $script:fxUpdated = [string]$o.updated }
  } catch {}
}

function Invoke-FxFetch {
  # 闸门：对应 fx-helper-v2 Api.fetch_rate 里的
  #   if not self._crawling.acquire(blocking=False): return "正在抓取中，请稍候"
  if ($script:fxFetching) {
    if ($TxtFxStatus) { $TxtFxStatus.Text = '正在抓取中，请稍候' }
    return
  }
  $script:fxFetching = $true
  # PS 5.1 默认可能不含 TLS 1.2，补上，否则 boc.cn 的 https 会直接连不上
  try {
    [System.Net.ServicePointManager]::SecurityProtocol =
      [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
  } catch {}
  if ($BtnFxFetch) { $BtnFxFetch.IsEnabled = $false }
  try {
    [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
    try {
      $rows = Get-BocRateTable
      if ($rows -and $rows.Count -gt 0) {
        $script:fxRows = @($rows)
        $script:fxUpdated = [DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss')
        Save-FxCache
        if ($TxtFxStatus) { $TxtFxStatus.Text = '已获取 ' + $rows.Count + ' 种牌价　' + (Get-FxStatusText) }
      } else {
        if ($TxtFxStatus) { $TxtFxStatus.Text = '抓取失败：未获取到牌价，请检查网络（当前显示的是上次缓存）。' }
      }
    } catch {
      if ($TxtFxStatus) { $TxtFxStatus.Text = '抓取异常：' + $_.Exception.Message }
    } finally {
      [System.Windows.Input.Mouse]::OverrideCursor = $null
    }
  } finally {
    # release：放锁与恢复按钮必须走 finally，异常路径也不能把闸门卡死
    if ($BtnFxFetch) { $BtnFxFetch.IsEnabled = $true }
    $script:fxFetching = $false
    Update-FxUi
  }
}

# 当前「复制汇率」要复制的币种（下拉框选中的那个），默认 USD
function Get-FxPickCode {
  $code = 'USD'
  if ($CmbFxPick) {
    # ComboBox 里放的是 ComboBoxItem，必须取 .Content 才是币种字符串
    $si = $CmbFxPick.SelectedItem
    if ($si -and $si.Content) { $code = [string]$si.Content }
    elseif ($CmbFxPick.Text) { $code = [string]$CmbFxPick.Text }
  }
  return $code
}

# 对照 fx-helper-v2 Api.copy_rate()：复制的是「单个汇率的裸数值」，
# 不是带表头的制表符表格 —— 表格粘进单元格会被拆成多列，正是要改掉的行为。
function Copy-FxRate {
  if (-not $script:fxRows -or $script:fxRows.Count -eq 0) {
    if ($TxtFxStatus) { $TxtFxStatus.Text = '暂无汇率数据，请先抓取。' }
    return
  }
  $code = Get-FxPickCode
  $row = $null
  foreach ($r in $script:fxRows) { if ($r.code -eq $code) { $row = $r; break } }
  if (-not $row) {
    if ($TxtFxStatus) { $TxtFxStatus.Text = '未找到 ' + $code + ' 的牌价，请先刷新牌价。' }
    return
  }
  $value = Convert-Rate100To1 $row.buy
  if ($value -eq '--') {
    if ($TxtFxStatus) { $TxtFxStatus.Text = '暂无 ' + $code + ' 的现汇买入价可复制。' }
    return
  }
  try {
    [System.Windows.Clipboard]::SetText($value)
    # 留一份给「粘贴汇率」回放：即使中途剪贴板被别的东西占了也不串味
    $script:fxCopyBuf = $value
    if ($TxtFxStatus) { $TxtFxStatus.Text = '已复制 ' + $code + ' 现汇买入价 ' + $value + '，可直接粘贴到单元格。' }
  } catch {
    if ($TxtFxStatus) { $TxtFxStatus.Text = '复制失败：' + $_.Exception.Message }
  }
}

# ---------------- 画图 / 去背景 ----------------
$script:BG_MAXSIDE = 3000          # 超过此边长先等比缩小再处理，避免内存爆掉
$script:bgSrcPath = ''
$script:bgOut = $null

function Add-BgLog {
  param([string]$m)
  if (-not $TxtBgLog) { return }
  $TxtBgLog.AppendText('[' + [DateTime]::Now.ToString('HH:mm:ss') + '] ' + $m + "`r`n")
  $TxtBgLog.ScrollToEnd()
}

function Test-BgKernel {
  # 确认图像内核已编译（首次调用会现编译，约 300ms），未就绪时写日志并返回 $false。
  # 放在画图功能的入口处调用，避免把编译开销压到启动路径上。
  if (Initialize-BgKernel) { return $true }
  Add-BgLog ('图像内核加载失败：' + $script:BgKernelError)
  Add-BgLog '去背景与矢量导出需要 .NET Framework 的 C# 编译器，Win10/11 系统自带。'
  return $false
}

function Read-ImageRgb {
  param([string]$Path)
  $fs = $null
  try {
    $fs = [System.IO.File]::OpenRead($Path)
    $dec = [System.Windows.Media.Imaging.BitmapDecoder]::Create($fs,
             [System.Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat,
             [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
    $frame = $dec.Frames[0]
    $conv = New-Object System.Windows.Media.Imaging.FormatConvertedBitmap
    $conv.BeginInit()
    $conv.Source = $frame
    # 直接转 Rgb24：内核要的就是 RGB 顺序，省掉一次逐字节交换
    $conv.DestinationFormat = [System.Windows.Media.PixelFormats]::Rgb24
    $conv.EndInit()
    $w = $conv.PixelWidth
    $h = $conv.PixelHeight
    $stride = $w * 3
    $buf = New-Object byte[] ($stride * $h)
    $conv.CopyPixels($buf, $stride, 0)
    return @{ W = $w; H = $h; Buf = $buf }
  } finally {
    if ($fs) { $fs.Close() }
  }
}

function New-PreviewSource {
  param([string]$Path)
  $bi = New-Object System.Windows.Media.Imaging.BitmapImage
  $bi.BeginInit()
  $bi.UriSource = [Uri]::new($Path)
  $bi.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
  $bi.DecodePixelWidth = 900
  $bi.EndInit()
  $bi.Freeze()
  return $bi
}

function New-BitmapFromRgba {
  param([byte[]]$Rgba, [int]$W, [int]$H)
  if (-not $Rgba) { return $null }
  $bgra = [ClearyBg.Bg]::ToBgra($Rgba)
  $bs = [System.Windows.Media.Imaging.BitmapSource]::Create($W, $H, 96, 96,
          [System.Windows.Media.PixelFormats]::Bgra32, $null, $bgra, $W * 4)
  $bs.Freeze()
  return $bs
}

function Save-RgbaPng {
  param([byte[]]$Rgba, [int]$W, [int]$H, [string]$Path)
  $bs = New-BitmapFromRgba $Rgba $W $H
  $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
  $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bs))
  $fs = [System.IO.File]::Create($Path)
  try { $enc.Save($fs) } finally { $fs.Close() }
}

function Get-BgSliderValue {
  param($slider, $box, [double]$def)
  if ($slider) { return [double]$slider.Value }
  if ($box) {
    $v = 0.0
    if ([double]::TryParse(([string]$box.Text).Trim(), [ref]$v)) { return $v }
  }
  return $def
}

function Update-BgParamPanels {
  $isSolid = $false
  if ($CmbBgMode -and $CmbBgMode.SelectedValue) { $isSolid = ([string]$CmbBgMode.SelectedValue -eq 'solid') }
  if ($BgChanPanel) { $BgChanPanel.Visibility = $(if ($isSolid) { 'Collapsed' } else { 'Visible' }) }
  if ($BgSolidPanel) { $BgSolidPanel.Visibility = $(if ($isSolid) { 'Visible' } else { 'Collapsed' }) }
}

function Select-BgImage {
  $dlg = New-Object Microsoft.Win32.OpenFileDialog
  $dlg.Title = '选择图片'
  $dlg.Filter = '图片 (*.png;*.jpg;*.jpeg;*.bmp;*.webp;*.tif;*.tiff)|*.png;*.jpg;*.jpeg;*.bmp;*.webp;*.tif;*.tiff|所有文件 (*.*)|*.*'
  if ($dlg.ShowDialog()) { Open-BgImage $dlg.FileName }
}

function Open-BgImage {
  param([string]$Path)
  if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return }
  if (-not (Test-BgKernel)) { return }
  $script:bgSrcPath = $Path
  $script:bgOut = $null
  try {
    if ($BgImgIn) { $BgImgIn.Source = New-PreviewSource $Path }
    if ($BgImgOut) { $BgImgOut.Source = $null }
    $fi = Get-Item -LiteralPath $Path
    Add-BgLog ('已载入 ' + $fi.Name + '  ' + [Math]::Round($fi.Length / 1024.0, 0) + ' KB')
  } catch {
    Add-BgLog ('载入失败：' + $_.Exception.Message)
    return
  }
  Invoke-BgProcess
}

function Invoke-BgProcess {
  if (-not $script:bgSrcPath) { Add-BgLog '先拖入或选择一张图片。'; return }
  if (-not (Test-BgKernel)) { return }
  try {
    [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $img = Read-ImageRgb $script:bgSrcPath
    if (-not $img) { Add-BgLog '读图失败。'; return }
    $w = $img.W; $h = $img.H; $buf = $img.Buf

    $nw = 0; $nh = 0
    $buf2 = [ClearyBg.Bg]::DownscaleRgb($buf, $w, $h, $script:BG_MAXSIDE, [ref]$nw, [ref]$nh)
    if ($nw -ne $w -or $nh -ne $h) {
      Add-BgLog ('原图 ' + $w + 'x' + $h + ' 超过上限，已缩到 ' + $nw + 'x' + $nh + ' 处理。')
      $w = $nw; $h = $nh; $buf = $buf2
    }

    $mode = 'channel';   if ($CmbBgMode) { $mode = [string]$CmbBgMode.SelectedValue }
    $colorMode = 'main'; if ($CmbBgColor) { $colorMode = [string]$CmbBgColor.SelectedValue }
    $lightMode = 'auto'; if ($CmbBgLight) { $lightMode = [string]$CmbBgLight.SelectedValue }
    $channel = 'auto';   if ($CmbBgChannel) { $channel = [string]$CmbBgChannel.SelectedValue }
    $flatten = $true;    if ($ChkBgFlatten) { $flatten = [bool]$ChkBgFlatten.IsChecked }
    $noHoles = $false;   if ($ChkBgHoles) { $noHoles = -not [bool]$ChkBgHoles.IsChecked }
    $bgCol = '';         if ($TxtBgBgColor) { $bgCol = ([string]$TxtBgBgColor.Text).Trim() }

    $bgPct = Get-BgSliderValue $SlBgBgPct $TxtBgBgPct 90.0
    $fgPct = Get-BgSliderValue $SlBgFgPct $TxtBgFgPct 99.0
    $tol = Get-BgSliderValue $SlBgTol $TxtBgTol 40.0
    $soft = Get-BgSliderValue $SlBgSoft $TxtBgSoft 0.6
    $maxHole = Get-BgSliderValue $SlBgHole $TxtBgHole 0.2

    $r = [ClearyBg.Bg]::Process($buf, $w, $h, $mode, $lightMode, $channel,
          $bgPct, $fgPct, $flatten, $colorMode, $tol, $soft, $maxHole, $noHoles, $bgCol)
    $sw.Stop()
    if (-not $r) { Add-BgLog '处理返回空结果。'; return }

    $script:bgOut = $r
    if ($BgImgOut) { $BgImgOut.Source = New-BitmapFromRgba $r.Rgba $r.Width $r.Height }
    Add-BgLog ('完成 ' + $w + 'x' + $h + '  ' + $sw.ElapsedMilliseconds + 'ms  ' + $r.Info)
    foreach ($ln in ($r.Log -split "`r?`n")) {
      if ($ln -and $ln.Trim()) { Add-BgLog ('   ' + $ln.Trim()) }
    }
  } catch {
    Add-BgLog ('处理出错：' + $_.Exception.Message)
  } finally {
    [System.Windows.Input.Mouse]::OverrideCursor = $null
  }
}

function Save-BgPng {
  if (-not $script:bgOut) { Add-BgLog '还没有结果可保存，先点「重新处理」。'; return }
  $dlg = New-Object Microsoft.Win32.SaveFileDialog
  $dlg.Title = '保存透明背景 PNG'
  $dlg.Filter = 'PNG 图片 (*.png)|*.png'
  $base = 'result'
  if ($script:bgSrcPath) { $base = [System.IO.Path]::GetFileNameWithoutExtension($script:bgSrcPath) }
  $dlg.FileName = $base + '-nobg.png'
  if ($script:bgSrcPath) { $dlg.InitialDirectory = [System.IO.Path]::GetDirectoryName($script:bgSrcPath) }
  if ($dlg.ShowDialog()) {
    try {
      Save-RgbaPng $script:bgOut.Rgba $script:bgOut.Width $script:bgOut.Height $dlg.FileName
      Add-BgLog ('已保存 PNG：' + $dlg.FileName)
    } catch { Add-BgLog ('保存 PNG 失败：' + $_.Exception.Message) }
  }
}

function Save-BgSvg {
  if (-not $script:bgOut) { Add-BgLog '还没有结果可保存，先点「重新处理」。'; return }
  $dlg = New-Object Microsoft.Win32.SaveFileDialog
  $dlg.Title = '保存矢量图'
  $dlg.Filter = 'SVG 矢量图 (*.svg)|*.svg'
  $base = 'result'
  if ($script:bgSrcPath) { $base = [System.IO.Path]::GetFileNameWithoutExtension($script:bgSrcPath) }
  $dlg.FileName = $base + '-nobg.svg'
  if ($script:bgSrcPath) { $dlg.InitialDirectory = [System.IO.Path]::GetDirectoryName($script:bgSrcPath) }
  if (-not $dlg.ShowDialog()) { return }
  try {
    [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
    $eps = Get-BgSliderValue $SlBgVecEps $TxtBgVecEps 0.8
    $smooth = $true
    if ($ChkBgVecSmooth) { $smooth = [bool]$ChkBgVecSmooth.IsChecked }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $svg = [ClearyBg.Bg]::ToSvg($script:bgOut.Rgba, $script:bgOut.Width, $script:bgOut.Height,
             0.5, 6.0, $eps, $smooth)
    $sw.Stop()
    if (-not $svg) { Add-BgLog '矢量化失败。'; return }
    [System.IO.File]::WriteAllText($dlg.FileName, $svg.Svg, (New-Object System.Text.UTF8Encoding $false))
    Add-BgLog ('已保存 SVG：' + $dlg.FileName + '  ' + $sw.ElapsedMilliseconds + 'ms  ' + $svg.Info)
  } catch {
    Add-BgLog ('保存 SVG 失败：' + $_.Exception.Message)
  } finally {
    [System.Windows.Input.Mouse]::OverrideCursor = $null
  }
}

function Invoke-CaseConvert {
  # 金额只有一个来源：上面计算器的大读数框。不再有独立的金额输入框，
  # 所以这里直接读 $script:calcCur（裸数字串），不做二次解析。
  $raw = [string]$script:calcCur
  if ([string]::IsNullOrEmpty($raw) -or $raw -eq '错误') { $raw = '0' }
  # 货币不再单独选：直接跟随「中国银行外汇牌价」卡里选中的那个币种，
  # 上面写 USD，这里算出来的就是 USD 的大写。
  $cur = Get-FxPickCode
  $res = ConvertTo-AmountEnglish -Raw $raw -Currency $cur
  if ($null -eq $res) {
    if ($TxtCaseOut) { $TxtCaseOut.Text = '无法解析金额：' + $raw }
    return
  }
  if ($TxtCaseOut) { $TxtCaseOut.Text = $res }
}

# 金额不在任何地方单独显示：数字只在大读数框里捕获，读数一变就直接重算英文大写。
# 金额框和左侧那个货币下拉都可以拿掉了（货币由牌价卡的币种下拉决定）。
function Sync-CaseAmountFromCalc {
  Invoke-CaseConvert
}

# ---------------- 延迟粘贴：复制 → 2.5 秒后自动粘到鼠标光标处 ----------------
# 动作语义照「外汇小宝」：点按钮后本窗口立刻最小化让开（Windows 会把前台交给
# 下一个窗口，通常就是 Excel / Word），2.5 秒后向前台窗口补一次 Ctrl+V，
# 再把自己收回来，并把焦点还给刚才那个窗口 —— 否则一恢复就把用户的光标抢走了。
$script:PASTE_DELAY_MS = 2500
$script:PASTE_RESTORE_MS = 1200
$script:pasteTimer = $null
$script:pasteRestoreTimer = $null
$script:pastePrev = [IntPtr]::Zero
$script:fxCopyBuf = ''
$script:caseCopyBuf = ''

function Restore-WindowAfterPaste {
  try { if ($window) { $window.WindowState = [System.Windows.WindowState]::Normal } } catch {}
  if ($script:pastePrev -ne [IntPtr]::Zero) {
    try { [void][ClearyNative]::SetForegroundWindow($script:pastePrev) } catch {}
  }
}

function Start-DelayedPaste {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  # 把「这一次」要粘的内容重新写回剪贴板：中途即使被别的东西占了剪贴板，
  # 粘出来的也一定还是刚才那一次的结果，不会串味。
  try { [System.Windows.Clipboard]::SetText($Text) } catch { return $false }
  if ($script:pasteTimer) { try { $script:pasteTimer.Stop() } catch {} }
  if ($script:pasteRestoreTimer) { try { $script:pasteRestoreTimer.Stop() } catch {} }
  # 让开：最小化之后前台交给下一个窗口（Excel / Word / 任何光标能闪的输入位置）
  try { if ($window) { $window.WindowState = [System.Windows.WindowState]::Minimized } } catch {}

  # 定时器一律走 $script: 作用域：tick 是在函数返回之后才跑的，
  # 依赖局部变量做闭包不安全。
  $t = New-Object System.Windows.Threading.DispatcherTimer
  $t.Interval = [TimeSpan]::FromMilliseconds($script:PASTE_DELAY_MS)
  $t.Add_Tick({
    try { $script:pasteTimer.Stop() } catch {}
    # 此刻的前台窗口就是用户自己切过去的那个（Excel / Word），记下来待会儿还焦点
    try { $script:pastePrev = [ClearyNative]::GetForegroundWindow() } catch {}
    try { [System.Windows.Forms.SendKeys]::SendWait('^v') } catch {}
    $r = New-Object System.Windows.Threading.DispatcherTimer
    $r.Interval = [TimeSpan]::FromMilliseconds($script:PASTE_RESTORE_MS)
    $r.Add_Tick({
      try { $script:pasteRestoreTimer.Stop() } catch {}
      Restore-WindowAfterPaste
    })
    $script:pasteRestoreTimer = $r
    $r.Start()
  })
  $script:pasteTimer = $t
  $t.Start()
  return $true
}

# 「复制结果」：内容同时留在 $script:caseCopyBuf 里，供「粘贴结果」回放
function Copy-CaseResult {
  $txt = ''
  if ($TxtCaseOut) { $txt = [string]$TxtCaseOut.Text }
  if ([string]::IsNullOrWhiteSpace($txt)) { return }
  if ($txt -eq ([char]0x2014).ToString()) { return }
  $script:caseCopyBuf = $txt
  try {
    [System.Windows.Clipboard]::SetText($txt)
    if ($BtnCaseCopy) { $BtnCaseCopy.Content = '已复制' }
    if ($TxtCaseStatus) { $TxtCaseStatus.Text = '大写结果已复制到剪贴板。' }
  } catch {
    if ($TxtCaseStatus) { $TxtCaseStatus.Text = '复制失败：' + $_.Exception.Message }
  }
}

function Paste-CaseResult {
  if ([string]::IsNullOrWhiteSpace($script:caseCopyBuf)) { Copy-CaseResult }
  $txt = $script:caseCopyBuf
  if ([string]::IsNullOrWhiteSpace($txt)) {
    if ($TxtCaseStatus) { $TxtCaseStatus.Text = '还没有可粘贴的结果，先点「转换」。' }
    return
  }
  if ($TxtCaseStatus) { $TxtCaseStatus.Text = '已就绪：2.5 秒后把大写结果粘到鼠标光标处（本窗口会先最小化让开，随后自动回来）。' }
  if (-not (Start-DelayedPaste $txt)) {
    if ($TxtCaseStatus) { $TxtCaseStatus.Text = '粘贴失败：剪贴板被别的程序占用，稍后再点一次。' }
  }
}

function Paste-FxRate {
  # 没先点过「复制汇率」也能用：按当前选中的币种现取一次，等价于先复制再粘贴
  if ([string]::IsNullOrWhiteSpace($script:fxCopyBuf)) { Copy-FxRate }
  $v = $script:fxCopyBuf
  if ([string]::IsNullOrWhiteSpace($v)) {
    if ($TxtFxStatus) { $TxtFxStatus.Text = '还没有可粘贴的汇率，先点「刷新牌价」取一次牌价。' }
    return
  }
  if ($TxtFxStatus) { $TxtFxStatus.Text = '已就绪：2.5 秒后把 ' + $v + ' 粘到鼠标光标处（本窗口会先最小化让开，随后自动回来）。' }
  if (-not (Start-DelayedPaste $v)) {
    if ($TxtFxStatus) { $TxtFxStatus.Text = '粘贴失败：剪贴板被别的程序占用，稍后再点一次。' }
  }
}

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="天选打工人专用小工具"
        Height="800" Width="940"
        MinHeight="700" MinWidth="800"
        WindowStartupLocation="CenterScreen"
        ResizeMode="CanResizeWithGrip"
        Topmost="False"
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
    <SolidColorBrush x:Key="FxRowHover" Color="#F5F8FF"/>
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
      <Setter Property="FontWeight" Value="Normal"/>
      <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
    </Style>
    <Style x:Key="SectionTitle" TargetType="TextBlock">
      <Setter Property="FontSize" Value="15"/>
      <Setter Property="FontWeight" Value="Normal"/>
      <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
    </Style>
    <Style x:Key="FieldTitle" TargetType="TextBlock">
      <Setter Property="FontWeight" Value="Normal"/>
      <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
    </Style>
    <Style TargetType="TabItem">
      <Setter Property="Padding" Value="18,10"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="FontWeight" Value="Normal"/>
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
                <Setter Property="FontWeight" Value="Normal"/>
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
            <Border Background="Transparent" Height="2"/>
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
            <Border Background="{DynamicResource Accent}" CornerRadius="5" Height="2"/>
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
      <Setter Property="Height" Value="34"/>
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
              <Border Height="2" Background="{DynamicResource TrackBg}" CornerRadius="5"
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
    <!-- 自定义滚动条样式 - 使竖条变细 -->
    <Style x:Key="ScrollBarThumb" TargetType="Thumb">
      <Setter Property="Background" Value="#C4C4C6"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="IsTabStop" Value="False"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Thumb">
            <Border Background="{TemplateBinding Background}" CornerRadius="3" 
                    BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}"/>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
          <Setter Property="Background" Value="#A8A8AA"/>
        </Trigger>
      </Style.Triggers>
    </Style>
    <Style TargetType="ScrollBar">
      <Setter Property="Width" Value="6"/>
      <Setter Property="MinWidth" Value="6"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Grid Background="Transparent">
              <Track x:Name="PART_Track" IsDirectionReversed="False">
                <Track.DecreaseRepeatButton>
                  <RepeatButton Command="ScrollBar.LineUpCommand" Focusable="False">
                    <RepeatButton.Template>
                      <ControlTemplate>
                        <Border Background="Transparent"/>
                      </ControlTemplate>
                    </RepeatButton.Template>
                  </RepeatButton>
                </Track.DecreaseRepeatButton>
                <Track.Thumb>
                  <Thumb Style="{StaticResource ScrollBarThumb}"/>
                </Track.Thumb>
                <Track.IncreaseRepeatButton>
                  <RepeatButton Command="ScrollBar.LineDownCommand" Focusable="False">
                    <RepeatButton.Template>
                      <ControlTemplate>
                        <Border Background="Transparent"/>
                      </ControlTemplate>
                    </RepeatButton.Template>
                  </RepeatButton>
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
      <Setter Property="FontWeight" Value="Normal"/>
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
      <Setter Property="FontWeight" Value="Normal"/>
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
                                TextElement.Foreground="{TemplateBinding Foreground}"
                                TextElement.FontWeight="{TemplateBinding FontWeight}"/>
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
    <!-- 行内数值框：外观与原来的蓝色数字一致，但可点击直接输入，回车生效 -->
    <Style x:Key="InlineNumBox" TargetType="TextBox">
      <Setter Property="Height" Value="24"/>
      <Setter Property="Padding" Value="4,0"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="FontWeight" Value="Normal"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Foreground" Value="{DynamicResource Accent}"/>
      <Setter Property="CaretBrush" Value="{DynamicResource Accent}"/>
      <Setter Property="SelectionBrush" Value="{DynamicResource Accent}"/>
      <Setter Property="TextAlignment" Value="Right"/>
      <Setter Property="HorizontalAlignment" Value="Right"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
      <Setter Property="MinWidth" Value="46"/>
      <Setter Property="MaxWidth" Value="84"/>
      <Setter Property="Cursor" Value="IBeam"/>
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
          <Setter Property="Background" Value="{DynamicResource AccentSoft}"/>
        </Trigger>
        <Trigger Property="IsFocused" Value="True">
          <Setter Property="Background" Value="{DynamicResource InputBg}"/>
        </Trigger>
      </Style.Triggers>
    </Style>
    <Style TargetType="RadioButton">
      <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
      <Setter Property="FontWeight" Value="Light"/>
    </Style>
    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
      <Setter Property="FontWeight" Value="Light"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
      <!-- 自定义模板：默认模板把方框贴着「首行行框顶部」，中文看着偏上；改为方框与文字同排垂直居中 -->
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <Grid Background="Transparent">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
              </Grid.ColumnDefinitions>
              <Border x:Name="CbBox" Grid.Column="0" Width="14" Height="14" CornerRadius="3"
                      BorderThickness="1" BorderBrush="#B8BCC4" Background="#FFFFFF"
                      VerticalAlignment="Center" SnapsToDevicePixels="True">
                <Path x:Name="CbMark" Data="M 3.1,6.9 L 5.8,9.6 L 10.8,3.9"
                      Stroke="#FFFFFF" StrokeThickness="1.7"
                      StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"
                      Visibility="Collapsed" HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Border>
              <ContentPresenter Grid.Column="1" Margin="8,0,0,0" RecognizesAccessKey="True"
                                VerticalAlignment="Center" HorizontalAlignment="Left"/>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="CbBox" Property="Background" Value="{DynamicResource Accent}"/>
                <Setter TargetName="CbBox" Property="BorderBrush" Value="{DynamicResource Accent}"/>
                <Setter TargetName="CbMark" Property="Visibility" Value="Visible"/>
              </Trigger>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="CbBox" Property="BorderBrush" Value="{DynamicResource Accent}"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.45"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <!-- 计算器按键：Windows 11 布局。所有按键共用同一模板，hover/press 走
         Opacity 而非硬编码颜色，这样「浅灰功能键 / 白底数字键 / 鲜蓝等号键」
         三套配色能共享一份模板；配色一律用主题画刷，深色主题下才不会花。 -->
    <!-- 牌价表的每一行：整行可点，但**完全不要边框**。
         鼠标扫到 = 极淡的浅蓝铺底；选中 = 稍深一点的浅蓝铺底。
         两个触发器都只改 Background，颜色一律取自主题画刷（深色主题下才不会花）。 -->
    <Style x:Key="FxRow" TargetType="RadioButton">
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="Padding" Value="10,3"/>
      <Setter Property="Margin" Value="0,1,0,0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border x:Name="Bg" Background="{TemplateBinding Background}" BorderThickness="0"
                    CornerRadius="6" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Stretch" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bg" Property="Background" Value="{DynamicResource FxRowHover}"/>
              </Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Bg" Property="Background" Value="{DynamicResource AccentSoft}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="CalcBtn" TargetType="Button">
      <Setter Property="FontSize" Value="20"/>
      <Setter Property="FontWeight" Value="Normal"/>
      <Setter Property="Foreground" Value="{DynamicResource TextPrimary}"/>
      <Setter Property="Background" Value="{DynamicResource GhostBg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource InputBorder}"/>
      <Setter Property="Margin" Value="2"/>
      <Setter Property="Height" Value="40"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1"
                    CornerRadius="6" SnapsToDevicePixels="True">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"
                                TextElement.Foreground="{TemplateBinding Foreground}"
                                TextElement.FontSize="{TemplateBinding FontSize}"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.78"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.55"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="CalcNum" TargetType="Button" BasedOn="{StaticResource CalcBtn}">
      <Setter Property="Background" Value="{DynamicResource CardBg}"/>
      <Setter Property="FontSize" Value="23"/>
    </Style>
    <Style x:Key="CalcFn" TargetType="Button" BasedOn="{StaticResource CalcBtn}">
      <Setter Property="FontSize" Value="17"/>
      <Setter Property="Foreground" Value="{DynamicResource TextSecondary}"/>
    </Style>
    <Style x:Key="CalcBtnAccent" TargetType="Button" BasedOn="{StaticResource CalcBtn}">
      <Setter Property="FontSize" Value="24"/>
      <Setter Property="Foreground" Value="#FFFFFF"/>
      <Setter Property="Background" Value="{DynamicResource Accent}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource Accent}"/>
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
          <TextBlock x:Name="TxtPageTitle" Text="天选打工人专用小工具" Style="{StaticResource PageTitle}"/>
          <TextBlock x:Name="TxtStatus" Text="当前：—" Margin="0,6,0,0" Foreground="{DynamicResource TextSecondary}"/>
        </StackPanel>
        <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
          <Border x:Name="BdLang" Background="{DynamicResource AccentSoft}" CornerRadius="20" Padding="12,7" Margin="0,0,12,0"
                  Cursor="Hand" BorderBrush="{DynamicResource CardBorder}" BorderThickness="1"
                  ToolTip="切换到 English">
            <StackPanel Orientation="Horizontal">
              <Grid Width="18" Height="16" Margin="0,0,6,0" VerticalAlignment="Center">
                <TextBlock Text="文" FontSize="10" FontWeight="Normal" Foreground="{DynamicResource Accent}"
                           HorizontalAlignment="Left" VerticalAlignment="Top" Margin="0,-1,0,0"/>
                <TextBlock Text="A" FontSize="10" FontWeight="Normal" Foreground="{DynamicResource Accent}"
                           HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,0,0,-1"/>
              </Grid>
              <TextBlock x:Name="TxtLangCode" Text="中" FontSize="13" FontWeight="Normal"
                         Foreground="{DynamicResource Accent}" VerticalAlignment="Center"/>
            </StackPanel>
          </Border>
          <StackPanel x:Name="BdRecBar" Orientation="Horizontal" VerticalAlignment="Center">
            <Border x:Name="BdRecApple" Background="{DynamicResource GhostBg}" CornerRadius="20" Padding="14,8" Margin="0,0,8,0" Cursor="Hand"
                    ToolTip="显示·苹果">
              <TextBlock x:Name="TxtRecApple" Text="苹果" Foreground="{DynamicResource TextSecondary}" FontWeight="Normal"/>
            </Border>
            <Border x:Name="BdRecLg" Background="{DynamicResource GhostBg}" CornerRadius="20" Padding="14,8" Margin="0,0,8,0" Cursor="Hand"
                    ToolTip="显示·LG">
              <TextBlock x:Name="TxtRecLg" Text="LG" Foreground="{DynamicResource TextSecondary}" FontWeight="Normal"/>
            </Border>
            <Border x:Name="BdRecHuawei" Background="{DynamicResource GhostBg}" CornerRadius="20" Padding="14,8" Margin="0,0,8,0" Cursor="Hand"
                    ToolTip="显示·华为">
              <TextBlock x:Name="TxtRecHuawei" Text="华为" Foreground="{DynamicResource TextSecondary}" FontWeight="Normal"/>
            </Border>
            <Border x:Name="BdRecAsus" Background="{DynamicResource GhostBg}" CornerRadius="20" Padding="14,8" Margin="0,0,8,0" Cursor="Hand"
                    ToolTip="显示·华硕">
              <TextBlock x:Name="TxtRecAsus" Text="华硕" Foreground="{DynamicResource TextSecondary}" FontWeight="Normal"/>
            </Border>
            <Border x:Name="BdRecSamsung" Background="{DynamicResource GhostBg}" CornerRadius="20" Padding="14,8" Margin="0,0,8,0" Cursor="Hand"
                    ToolTip="显示·三星">
              <TextBlock x:Name="TxtRecSamsung" Text="三星" Foreground="{DynamicResource TextSecondary}" FontWeight="Normal"/>
            </Border>
            <Border x:Name="BdRecGeneric" Background="{DynamicResource AccentSoft}" CornerRadius="20" Padding="14,8" Cursor="Hand"
                    ToolTip="显示·通用">
              <TextBlock x:Name="TxtRecGeneric" Text="通用显示" Foreground="{DynamicResource Accent}" FontWeight="Normal"/>
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
            <!-- 左：电源配置（整列拉满） ｜ 右：默认平衡档 + 开机自动应用 + 命名方案（三卡堆叠）
                 右列用三行等分（*）撑满，使左右两列底边严格等高 -->
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
                  <!-- 低电量插电提醒：同属电源配置，并在本卡内 -->
                  <Border Height="1" Background="{DynamicResource CardBorder}" Margin="0,16,0,14"/>
                  <TextBlock x:Name="TxtBatAlertTitle" Text="低电量插电提醒" Style="{StaticResource SectionTitle}"/>
                  <TextBlock x:Name="TxtBatAlertDesc" Text="电池供电时，电量降到设定值就弹窗提醒插电，避免掉电黑屏。" Foreground="{DynamicResource TextSecondary}" TextWrapping="Wrap" Margin="0,4,0,12"/>
                  <CheckBox x:Name="ChkBatAlert" Content="启用低电量提醒（仅电池供电时）" IsChecked="True" Margin="0,0,0,12"/>
                  <Grid>
                    <TextBlock x:Name="TxtBatAlertThreshold" Text="提醒阈值" Style="{StaticResource FieldTitle}"/>
                    <TextBox x:Name="TxtBatAlertVal" Text="73%" Style="{StaticResource InlineNumBox}" MaxWidth="60"/>
                  </Grid>
                  <TextBlock x:Name="TxtBatAlertHint" Text="建议 70% 以上。本机电池已老化，留足余量更稳。" Foreground="{DynamicResource TextSecondary}" FontSize="12"/>
                  <Slider x:Name="SlBatAlert" Minimum="10" Maximum="95" Value="73"
                          SmallChange="1" LargeChange="5" TickFrequency="1" IsSnapToTickEnabled="True" IsMoveToPointEnabled="True"/>
                  <TextBlock x:Name="TxtBatNow" Text="当前：—" Margin="0,10,0,0" Foreground="{DynamicResource TextSecondary}"/>
                  <!-- 黑屏报告：异常掉电（黑屏）关机后，重启时给出诊断报告 -->
                  <Border Height="1" Background="{DynamicResource CardBorder}" Margin="0,16,0,14"/>
                  <TextBlock x:Name="TxtBlackoutTitle" Text="黑屏报告" Style="{StaticResource SectionTitle}"/>
                  <TextBlock x:Name="TxtBlackoutDesc" Text="系统异常掉电黑屏后，重启时自动比对关机/开机事件，给出黑屏报告。" Foreground="{DynamicResource TextSecondary}" TextWrapping="Wrap" Margin="0,4,0,10"/>
                  <CheckBox x:Name="ChkBlackout" Content="如果黑屏，重启后提供黑屏报告" IsChecked="True" Margin="0,0,0,10"/>
                  <StackPanel Orientation="Horizontal">
                    <Button x:Name="BtnBlackoutReport" Style="{StaticResource PrimaryBtn}" Content="黑屏报告" MinWidth="104"/>
                    <TextBlock x:Name="TxtBlackoutHint" Text="—" VerticalAlignment="Center" Margin="12,0,0,0"
                               Foreground="{DynamicResource TextSecondary}" FontSize="12" TextWrapping="Wrap"/>
                  </StackPanel>
                </StackPanel>
              </Border>
              <!-- 右列：三卡堆叠。三行均为 *，整列始终撑满行高，与左卡底边等高 -->
              <Grid Grid.Column="2">
                <Grid.RowDefinitions>
                  <RowDefinition Height="*"/>
                  <RowDefinition Height="*"/>
                  <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                <Border Grid.Row="0" Style="{StaticResource Card}">
                  <StackPanel>
                    <TextBlock x:Name="TxtRecTarget" Text="默认平衡档" Style="{StaticResource SectionTitle}" TextWrapping="Wrap" Margin="0,0,0,10"/>
                    <TextBlock x:Name="TxtRecAcParams" Text="接电：—" Foreground="{DynamicResource TextSecondary}" TextWrapping="Wrap" Margin="0,0,0,4"/>
                    <TextBlock x:Name="TxtRecBatParams" Text="电池：—" Foreground="{DynamicResource Accent}" TextWrapping="Wrap" Margin="0,0,0,4"/>
                    <TextBlock x:Name="TxtRecFontParams" Text="字体档：—" Foreground="{DynamicResource TextMuted}" TextWrapping="Wrap" Margin="0,0,0,10"/>
                    <TextBlock x:Name="TxtRecNote" Text="显示与字体相互独立。" Foreground="{DynamicResource TextMuted}" TextWrapping="Wrap" FontSize="12"/>
                  </StackPanel>
                </Border>
                <Border Grid.Row="1" Style="{StaticResource Card}">
                  <StackPanel>
                    <TextBlock x:Name="TxtAutoStartTitle" Text="开机自动应用" Style="{StaticResource SectionTitle}"/>
                    <TextBlock x:Name="TxtAutoStartDesc" Text="登录 Windows 时自动写回亮度/对比度/软件伽马（系统会重置软件伽马，不是权限问题）。" Foreground="{DynamicResource TextSecondary}" TextWrapping="Wrap" Margin="0,4,0,10"/>
                    <CheckBox x:Name="ChkAutoStart" Content="登录时自动应用当前显示配置" IsChecked="True"/>
                  </StackPanel>
                </Border>
                <Border Grid.Row="2" Style="{StaticResource Card}">
                  <StackPanel>
                    <TextBlock x:Name="TxtPresetTitle" Text="命名方案" Style="{StaticResource SectionTitle}"/>
                    <TextBlock x:Name="TxtPresetDesc" Text="把「接电 + 电池」两套参数另存为方案，方便随时切换。" Foreground="{DynamicResource TextSecondary}" TextWrapping="Wrap" Margin="0,4,0,12"/>
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
              </Grid>
            </Grid>

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
                    <TextBox x:Name="TxtBright" Text="90" Style="{StaticResource InlineNumBox}"/>
                  </Grid>
                  <Slider x:Name="SlBright" Minimum="0" Maximum="100" Value="90"
                          SmallChange="1" LargeChange="5"/>
                </StackPanel>
              </Border>
              <Border Grid.Column="2" Style="{StaticResource Card}">
                <StackPanel>
                  <Grid>
                    <TextBlock x:Name="TxtContrastLabel" Text="对比度" Style="{StaticResource FieldTitle}"/>
                    <TextBox x:Name="TxtContrast" Text="50" Style="{StaticResource InlineNumBox}"/>
                  </Grid>
                  <Slider x:Name="SlContrast" Minimum="0" Maximum="100" Value="50"
                          SmallChange="1" LargeChange="5"/>
                </StackPanel>
              </Border>
            </Grid>

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
                    <TextBox x:Name="TxtGamma" Text="1.00" Style="{StaticResource InlineNumBox}"/>
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
                    <TextBox x:Name="TxtScale" Text="1.00" Style="{StaticResource InlineNumBox}"/>
                  </Grid>
                  <TextBlock x:Name="TxtScaleHint" Text="整体明暗倍率，可细调" Foreground="{DynamicResource TextSecondary}" FontSize="12" Margin="0,2,0,0"/>
                  <Slider x:Name="SlScale" Minimum="0.70" Maximum="1.10" Value="1.0"
                          SmallChange="0.01" LargeChange="0.05"/>
                </StackPanel>
              </Border>
            </Grid>
            <Grid>
              <TextBlock x:Name="TxtReadback" Text="硬件回读：—" Foreground="{DynamicResource TextMuted}" Margin="2,2,0,0" FontSize="12"/>
              <TextBlock x:Name="TxtNumEditHint" Text="点数字可直接输入，回车生效" FontSize="12" Foreground="{DynamicResource TextMuted}" HorizontalAlignment="Right" VerticalAlignment="Center"/>
            </Grid>

            <!-- ===== 颜色校准（老方案：整行大卡 + 放射状图标）===== -->
            <TextBlock x:Name="TxtColorCalibTitle" Text="颜色校准" Style="{StaticResource SectionTitle}" Margin="2,18,0,10"/>
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
                  <TextBlock x:Name="TxtColorCalibName" Text="显示颜色校准" FontSize="14" FontWeight="Normal" Foreground="{DynamicResource TextPrimary}"/>
                  <TextBlock x:Name="TxtColorCalibDesc" Text="校准显示颜色、亮度和对比度" FontSize="12" Foreground="{DynamicResource TextSecondary}" Margin="0,3,0,0" TextWrapping="Wrap"/>
                </StackPanel>
                <Button x:Name="BtnColorCalib" Grid.Column="2" Style="{StaticResource GhostBtn}" Content="校准显示器"
                        MinWidth="108" Margin="12,0,0,0" VerticalAlignment="Center" Padding="16,8"/>
              </Grid>
            </Border>

            <!-- ===== 环境自动切换：显示器 + 网络 → 方案 ===== -->
            <TextBlock x:Name="TxtEnvTitle" Text="环境自动切换" Style="{StaticResource SectionTitle}" Margin="2,18,0,10"/>
            <Border Style="{StaticResource Card}" Padding="16,14">
              <StackPanel>
                <TextBlock x:Name="TxtEnvDesc" Text="记住「显示器 + 网络」组合：换到办公室或家庭时，自动载入对应的命名方案。" Foreground="{DynamicResource TextSecondary}" TextWrapping="Wrap" Margin="0,0,0,10"/>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,12">
                  <CheckBox x:Name="ChkEnvAuto" Content="按环境自动切换方案" Margin="0,0,22,0"/>
                  <CheckBox x:Name="ChkEnvApply" Content="切换时自动写入屏幕" IsChecked="True"/>
                </StackPanel>
                <Grid>
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="14"/>
                    <ColumnDefinition Width="*"/>
                  </Grid.ColumnDefinitions>
                  <StackPanel Grid.Column="0">
                    <TextBlock x:Name="TxtEnvNowLabel" Text="当前环境" FontSize="12" Foreground="{DynamicResource TextMuted}"/>
                    <TextBlock x:Name="TxtEnvNow" Text="识别中…" Margin="0,4,0,0" TextWrapping="Wrap"/>
                  </StackPanel>
                  <StackPanel Grid.Column="2">
                    <TextBlock x:Name="TxtEnvPresetLabel" Text="关联方案" FontSize="12" Foreground="{DynamicResource TextMuted}"/>
                    <ComboBox x:Name="CmbEnvPreset" Margin="0,4,0,0"/>
                  </StackPanel>
                </Grid>
                <StackPanel Orientation="Horizontal" Margin="0,12,0,10">
                  <Button x:Name="BtnEnvBind" Style="{StaticResource PrimaryBtn}" Content="绑定当前环境" MinWidth="120"/>
                  <Button x:Name="BtnEnvUnbind" Style="{StaticResource GhostBtn}" Content="解除绑定" MinWidth="96" Margin="10,0,0,0"/>
                </StackPanel>
                <TextBlock x:Name="TxtEnvList" Text="尚未绑定任何环境" FontSize="12" Foreground="{DynamicResource TextSecondary}" TextWrapping="Wrap"/>
              </StackPanel>
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
                <TextBlock x:Name="TxtFontRecTitle" Text="字体档 · 通用显示" Foreground="{DynamicResource Accent}" FontWeight="Normal" Margin="0,0,0,4"/>
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
                  <TextBox x:Name="TxtFontGamma" Text="1.40" Style="{StaticResource InlineNumBox}"/>
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
                    <TextBlock x:Name="TxtPreviewSample" FontSize="22" FontWeight="Normal" Text="天选打工人专用小工具 ClearyDisplay"/>
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

      <!-- 汇率：牌价 / 计算器 / 数字转英文大写。
           版面是「一左一右」：左列上下放牌价与计算器，右列放数字转英文大写。
           两列都用 Width="*"，窗体拉宽时两边等宽同步变宽；窗体窄到极限时由各列
           自己的 ScrollViewer 兜住（换行也会自然退化成「上下一条通栏」）。 -->
      <TabItem x:Name="TabCalc" Header="汇率">
      <!-- 汇率页版面：
           第一行 = [① 中国银行外汇牌价] | [② 计算器]，左右并行且同高；
           第二行 = [③ 数字转英文大写]，通栏跨两列。
           两列都取 Width="*"，窗体拉宽时两边等宽同步变宽；窗体窄到极限时
           由外层 ScrollViewer 兜住（各卡内部文字换行，自然退化成上下堆叠）。 -->
      <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
        <Grid Margin="0,12,0,0">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="14"/>
            <ColumnDefinition Width="*"/>
          </Grid.ColumnDefinitions>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>

          <!-- ① 中国银行外汇牌价（左上） -->
          <Border Grid.Row="0" Grid.Column="0" Style="{StaticResource Card}">
              <!-- 用 Grid 而不是 StackPanel：最后一行价格区取 Height="*"，
                   把「和右侧计算器卡同高」后多出来的高度均分到 4 行牌价上，
                   这样底部不会留一块空白，两卡看起来才是真正齐平的一条。 -->
              <Grid>
                <Grid.RowDefinitions>
                  <RowDefinition Height="Auto"/>
                  <RowDefinition Height="Auto"/>
                  <RowDefinition Height="Auto"/>
                  <RowDefinition Height="Auto"/>
                  <RowDefinition Height="Auto"/>
                  <RowDefinition Height="Auto"/>
                  <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                <TextBlock Grid.Row="0" Text="中国银行外汇牌价" Style="{StaticResource SectionTitle}"/>
                <TextBlock Grid.Row="1" Text="中行牌价即「每 100 外币兑人民币」，此处换算为 1 外币兑人民币并保留 4 位。" Foreground="{DynamicResource TextSecondary}" TextWrapping="Wrap" Margin="0,4,0,10"/>
                <StackPanel Grid.Row="2" Orientation="Horizontal">
                  <!-- 币种下拉排在最前：后面「复制 / 粘贴」以及下方「数字转英文大写」都跟着它走。
                       字体要加粗 + 主题蓝，所以本控件与每个选项都显式设 FontWeight/Foreground，
                       盖掉全局 ComboBoxItem 样式里的 FontWeight=Light。 -->
                  <ComboBox x:Name="CmbFxPick" Width="92" SelectedIndex="0"
                            FontSize="15" FontWeight="Bold" Foreground="{DynamicResource Accent}"
                            VerticalContentAlignment="Center">
                    <ComboBoxItem Content="USD" FontSize="15" FontWeight="Bold" Foreground="{DynamicResource Accent}"/>
                    <ComboBoxItem Content="EUR" FontSize="15" FontWeight="Bold" Foreground="{DynamicResource Accent}"/>
                    <ComboBoxItem Content="GBP" FontSize="15" FontWeight="Bold" Foreground="{DynamicResource Accent}"/>
                    <ComboBoxItem Content="JPY" FontSize="15" FontWeight="Bold" Foreground="{DynamicResource Accent}"/>
                  </ComboBox>
                  <Button x:Name="BtnFxFetch" Style="{StaticResource PrimaryBtn}" Content="刷新牌价" MinWidth="88" Margin="8,0,0,0"/>
                  <Button x:Name="BtnFxCopy" Style="{StaticResource GhostBtn}" Content="复制汇率" MinWidth="88" Margin="8,0,0,0"/>
                  <Button x:Name="BtnFxPaste" Style="{StaticResource GhostBtn}" Content="粘贴汇率" MinWidth="88" Margin="8,0,0,0"/>
                </StackPanel>
                <TextBlock Grid.Row="3" x:Name="TxtFxStatus" Text="尚未获取牌价" Foreground="{DynamicResource TextSecondary}" FontSize="12" Margin="0,8,0,6" TextWrapping="Wrap"/>

                <Border Grid.Row="4" Height="1" Background="{DynamicResource CardBorder}" Margin="0,0,0,6"/>

                <!-- 牌价表：只留「现汇买入价」；每一行都能点，点哪行就把当前币种切到那一个。
                     行内左右各留一段弹性空白（Width="*"），版面收紧时名字和价格往中间靠。 -->
                <Grid Grid.Row="5" Margin="11,0,11,2">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/><ColumnDefinition Width="*"/>
                  </Grid.ColumnDefinitions>
                  <TextBlock Grid.Column="0" Text="币种" Foreground="{DynamicResource TextSecondary}" FontSize="12" Margin="10,0,0,0"/>
                  <TextBlock Grid.Column="1" Text="现汇买入价" Foreground="{DynamicResource TextSecondary}" FontSize="12" TextAlignment="Right" Margin="0,0,10,0"/>
                </Grid>

                <!-- 4 行价格：每行取 Height="*"，把剩余高度四等分 -->
                <Grid Grid.Row="6">
                  <Grid.RowDefinitions>
                    <RowDefinition Height="*"/><RowDefinition Height="*"/>
                    <RowDefinition Height="*"/><RowDefinition Height="*"/>
                  </Grid.RowDefinitions>
                  <RadioButton x:Name="FxRow0" Grid.Row="0" GroupName="FxPick" IsChecked="True" Style="{StaticResource FxRow}" Tag="0">
                    <Grid>
                      <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*" MinWidth="0"/>
                        <ColumnDefinition Width="32"/>
                        <ColumnDefinition Width="*" MinWidth="0"/>
                        <ColumnDefinition Width="Auto"/>
                      </Grid.ColumnDefinitions>
                      <TextBlock x:Name="FxName0" Grid.Column="0" Text="美元 / USD" FontSize="15" VerticalAlignment="Center"/>
                      <TextBlock x:Name="FxBuy0" Grid.Column="4" Text="--" FontSize="17" FontWeight="Bold" Foreground="{DynamicResource Accent}" TextAlignment="Right" VerticalAlignment="Center"/>
                    </Grid>
                  </RadioButton>

                  <RadioButton x:Name="FxRow1" Grid.Row="1" GroupName="FxPick" Style="{StaticResource FxRow}" Tag="1">
                    <Grid>
                      <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*" MinWidth="0"/>
                        <ColumnDefinition Width="32"/>
                        <ColumnDefinition Width="*" MinWidth="0"/>
                        <ColumnDefinition Width="Auto"/>
                      </Grid.ColumnDefinitions>
                      <TextBlock x:Name="FxName1" Grid.Column="0" Text="欧元 / EUR" FontSize="15" VerticalAlignment="Center"/>
                      <TextBlock x:Name="FxBuy1" Grid.Column="4" Text="--" FontSize="17" FontWeight="Bold" Foreground="{DynamicResource Accent}" TextAlignment="Right" VerticalAlignment="Center"/>
                    </Grid>
                  </RadioButton>

                  <RadioButton x:Name="FxRow2" Grid.Row="2" GroupName="FxPick" Style="{StaticResource FxRow}" Tag="2">
                    <Grid>
                      <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*" MinWidth="0"/>
                        <ColumnDefinition Width="32"/>
                        <ColumnDefinition Width="*" MinWidth="0"/>
                        <ColumnDefinition Width="Auto"/>
                      </Grid.ColumnDefinitions>
                      <TextBlock x:Name="FxName2" Grid.Column="0" Text="英镑 / GBP" FontSize="15" VerticalAlignment="Center"/>
                      <TextBlock x:Name="FxBuy2" Grid.Column="4" Text="--" FontSize="17" FontWeight="Bold" Foreground="{DynamicResource Accent}" TextAlignment="Right" VerticalAlignment="Center"/>
                    </Grid>
                  </RadioButton>

                  <RadioButton x:Name="FxRow3" Grid.Row="3" GroupName="FxPick" Style="{StaticResource FxRow}" Tag="3">
                    <Grid>
                      <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*" MinWidth="0"/>
                        <ColumnDefinition Width="32"/>
                        <ColumnDefinition Width="*" MinWidth="0"/>
                        <ColumnDefinition Width="Auto"/>
                      </Grid.ColumnDefinitions>
                      <TextBlock x:Name="FxName3" Grid.Column="0" Text="日元 / JPY" FontSize="15" VerticalAlignment="Center"/>
                      <TextBlock x:Name="FxBuy3" Grid.Column="4" Text="--" FontSize="17" FontWeight="Bold" Foreground="{DynamicResource Accent}" TextAlignment="Right" VerticalAlignment="Center"/>
                    </Grid>
                  </RadioButton>
                </Grid>
              </Grid>
            </Border>

          <!-- ② 计算器（右上）：与左侧牌价卡并排放在第一行，两卡同高。
               牌价卡的 4 行价格取 Height="*" 均分，所以两卡底边会齐平。 -->
          <Border Grid.Row="0" Grid.Column="2" Style="{StaticResource Card}">
                <StackPanel>
                  <TextBlock Text="计算器" Style="{StaticResource SectionTitle}"/>
                  <TextBlock Text="参照 Windows 11 标准计算器布局；切到本页后可直接用键盘输入算式，回车即等号。读数实时转成下方英文大写。" Foreground="{DynamicResource TextSecondary}" TextWrapping="Wrap" Margin="0,4,0,10"/>
                  <!-- 键区直接撑满本列：不再限宽；窗体拉宽时本列跟着变宽，4 个键格同步放大 -->
                  <Border Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource CardBorder}" BorderThickness="1" CornerRadius="10" Padding="14,6">
                    <StackPanel>
                      <TextBlock x:Name="TxtCalcExpr" Text="" FontSize="13" Foreground="{DynamicResource TextMuted}" TextAlignment="Right" TextTrimming="CharacterEllipsis" MinHeight="16"/>
                      <TextBlock x:Name="TxtCalcDisp" Text="0" FontFamily="Segoe UI, Microsoft YaHei UI" FontSize="34" FontWeight="Bold" Foreground="{DynamicResource Accent}" TextAlignment="Right" Margin="0,2,0,0" TextTrimming="CharacterEllipsis"/>
                    </StackPanel>
                  </Border>
                  <Border Background="{DynamicResource WinBg}" CornerRadius="8" Padding="4" Margin="0,8,0,0">
                    <Grid>
                      <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/><ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="*"/><ColumnDefinition Width="*"/>
                      </Grid.ColumnDefinitions>
                      <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
                      </Grid.RowDefinitions>

                      <Button x:Name="BtnCalcPct" Grid.Row="0" Grid.Column="0" Style="{StaticResource CalcFn}" Content="%"/>
                      <Button x:Name="BtnCalcCE" Grid.Row="0" Grid.Column="1" Style="{StaticResource CalcFn}" Content="CE"/>
                      <Button x:Name="BtnCalcC" Grid.Row="0" Grid.Column="2" Style="{StaticResource CalcFn}" Content="C"/>
                      <Button x:Name="BtnCalcBack" Grid.Row="0" Grid.Column="3" Style="{StaticResource CalcFn}" Content="&#x232B;"/>

                      <Button x:Name="BtnCalcInv" Grid.Row="1" Grid.Column="0" Style="{StaticResource CalcFn}" Content="1/x"/>
                      <Button x:Name="BtnCalcSqr" Grid.Row="1" Grid.Column="1" Style="{StaticResource CalcFn}" Content="x&#x00B2;"/>
                      <Button x:Name="BtnCalcSqrt" Grid.Row="1" Grid.Column="2" Style="{StaticResource CalcFn}" Content="&#x221A;x"/>
                      <Button x:Name="BtnCalcDiv" Grid.Row="1" Grid.Column="3" Style="{StaticResource CalcFn}" Content="&#x00F7;"/>

                      <Button x:Name="BtnCalc7" Grid.Row="2" Grid.Column="0" Style="{StaticResource CalcNum}" Content="7"/>
                      <Button x:Name="BtnCalc8" Grid.Row="2" Grid.Column="1" Style="{StaticResource CalcNum}" Content="8"/>
                      <Button x:Name="BtnCalc9" Grid.Row="2" Grid.Column="2" Style="{StaticResource CalcNum}" Content="9"/>
                      <Button x:Name="BtnCalcMul" Grid.Row="2" Grid.Column="3" Style="{StaticResource CalcFn}" Content="&#x00D7;"/>

                      <Button x:Name="BtnCalc4" Grid.Row="3" Grid.Column="0" Style="{StaticResource CalcNum}" Content="4"/>
                      <Button x:Name="BtnCalc5" Grid.Row="3" Grid.Column="1" Style="{StaticResource CalcNum}" Content="5"/>
                      <Button x:Name="BtnCalc6" Grid.Row="3" Grid.Column="2" Style="{StaticResource CalcNum}" Content="6"/>
                      <Button x:Name="BtnCalcSub" Grid.Row="3" Grid.Column="3" Style="{StaticResource CalcFn}" Content="&#x2212;"/>

                      <Button x:Name="BtnCalc1" Grid.Row="4" Grid.Column="0" Style="{StaticResource CalcNum}" Content="1"/>
                      <Button x:Name="BtnCalc2" Grid.Row="4" Grid.Column="1" Style="{StaticResource CalcNum}" Content="2"/>
                      <Button x:Name="BtnCalc3" Grid.Row="4" Grid.Column="2" Style="{StaticResource CalcNum}" Content="3"/>
                      <Button x:Name="BtnCalcAdd" Grid.Row="4" Grid.Column="3" Style="{StaticResource CalcFn}" Content="+"/>

                      <Button x:Name="BtnCalcNeg" Grid.Row="5" Grid.Column="0" Style="{StaticResource CalcNum}" Content="&#x00B1;"/>
                      <Button x:Name="BtnCalc0" Grid.Row="5" Grid.Column="1" Style="{StaticResource CalcNum}" Content="0"/>
                      <Button x:Name="BtnCalcDot" Grid.Row="5" Grid.Column="2" Style="{StaticResource CalcNum}" Content="."/>
                      <Button x:Name="BtnCalcEq" Grid.Row="5" Grid.Column="3" Style="{StaticResource CalcBtnAccent}" Content="="/>
                    </Grid>
                  </Border>
                </StackPanel>
            </Border>

          <!-- ③ 数字转英文大写：放在第二行，通栏跨两列（含中间 14px 间隔）。
               金额直接读取左上计算器的读数，货币跟随左上牌价选中的那个币种。 -->
          <Border Grid.Row="1" Grid.Column="0" Grid.ColumnSpan="3" Style="{StaticResource Card}">
                <StackPanel>
                  <TextBlock Text="数字转英文大写" Style="{StaticResource SectionTitle}"/>
                  <TextBlock Text="外贸单据风格自动带 AND；金额取自左上计算器读数，货币跟随左上牌价选中的币种。" Foreground="{DynamicResource TextSecondary}" TextWrapping="Wrap" Margin="0,4,0,10"/>
                  <TextBlock Text="英文大写" Foreground="{DynamicResource TextSecondary}" Margin="0,8,0,6"/>
                  <Border Background="{DynamicResource InputBg}" BorderBrush="{DynamicResource CardBorder}" BorderThickness="1" CornerRadius="10" Padding="14,12">
                    <TextBlock x:Name="TxtCaseOut" Text="&#x2014;" FontFamily="Segoe UI, Microsoft YaHei UI"
                               FontSize="17" FontWeight="Bold" Foreground="{DynamicResource Accent}"
                               TextWrapping="Wrap" LineHeight="28" MinHeight="44"/>
                  </Border>
                  <!-- 三个按钮并排一行：通栏之后宽度够，「转换」不必再独占一行，
                       省下来的 ~60px 正好让整张卡进得了视口。 -->
                  <StackPanel Orientation="Horizontal" HorizontalAlignment="Left" Margin="0,10,0,0">
                    <Button x:Name="BtnCaseConv" Style="{StaticResource PrimaryBtn}" Content="转 换" MinWidth="104"/>
                    <Button x:Name="BtnCaseCopy" Style="{StaticResource GhostBtn}" Content="复制结果" MinWidth="104" Margin="10,0,0,0"/>
                    <Button x:Name="BtnCasePaste" Style="{StaticResource GhostBtn}" Content="粘贴结果" MinWidth="104" Margin="10,0,0,0"/>
                  </StackPanel>
                  <TextBlock x:Name="TxtCaseStatus" Text="" Foreground="{DynamicResource TextSecondary}" FontSize="12" Margin="0,8,0,0" TextWrapping="Wrap"/>
                </StackPanel>
              </Border>
        </Grid>
      </ScrollViewer>
    </TabItem>

      <!-- 画图 -->
      <TabItem x:Name="TabDraw" Header="画图">
        <ScrollViewer VerticalScrollBarVisibility="Auto" Margin="0,12,0,0">
          <StackPanel>
            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="14"/>
                <ColumnDefinition Width="312"/>
              </Grid.ColumnDefinitions>

              <StackPanel Grid.Column="0">
                <Border x:Name="BgDropZone" Style="{StaticResource Card}" Padding="16" AllowDrop="True">
                  <StackPanel>
                    <TextBlock Text="预览" Style="{StaticResource SectionTitle}"/>
                    <TextBlock Text="把图片拖进这张卡片，或点下方「选择图片」。结果里的棋盘格代表透明区域。" Foreground="{DynamicResource TextSecondary}" TextWrapping="Wrap" Margin="0,4,0,12"/>
                    <Grid>
                      <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="12"/>
                        <ColumnDefinition Width="*"/>
                      </Grid.ColumnDefinitions>
                      <Border Grid.Column="0" Background="{DynamicResource WinBg}" BorderBrush="{DynamicResource CardBorder}" BorderThickness="1" CornerRadius="10" Padding="8">
                        <StackPanel>
                          <TextBlock Text="原图" Foreground="{DynamicResource TextSecondary}" FontSize="12" Margin="2,0,0,6"/>
                          <Border Height="252" Background="{DynamicResource InputBg}" CornerRadius="6" ClipToBounds="True">
                            <Image x:Name="BgImgIn" Stretch="Uniform" RenderOptions.BitmapScalingMode="HighQuality"/>
                          </Border>
                        </StackPanel>
                      </Border>
                      <Border Grid.Column="2" Background="{DynamicResource WinBg}" BorderBrush="{DynamicResource CardBorder}" BorderThickness="1" CornerRadius="10" Padding="8">
                        <StackPanel>
                          <TextBlock Text="结果（棋盘格 = 透明）" Foreground="{DynamicResource TextSecondary}" FontSize="12" Margin="2,0,0,6"/>
                          <Border Height="252" CornerRadius="6" ClipToBounds="True">
                            <Border.Background>
                              <DrawingBrush TileMode="Tile" Viewport="0,0,16,16" ViewportUnits="Absolute">
                                <DrawingBrush.Drawing>
                                  <DrawingGroup>
                                    <GeometryDrawing Brush="#F4F4F6">
                                      <GeometryDrawing.Geometry>
                                        <RectangleGeometry Rect="0,0,16,16"/>
                                      </GeometryDrawing.Geometry>
                                    </GeometryDrawing>
                                    <GeometryDrawing Brush="#DCDCE2">
                                      <GeometryDrawing.Geometry>
                                        <GeometryGroup>
                                          <RectangleGeometry Rect="0,0,8,8"/>
                                          <RectangleGeometry Rect="8,8,8,8"/>
                                        </GeometryGroup>
                                      </GeometryDrawing.Geometry>
                                    </GeometryDrawing>
                                  </DrawingGroup>
                                </DrawingBrush.Drawing>
                              </DrawingBrush>
                            </Border.Background>
                            <Image x:Name="BgImgOut" Stretch="Uniform" RenderOptions.BitmapScalingMode="HighQuality"/>
                          </Border>
                        </StackPanel>
                      </Border>
                    </Grid>
                    <StackPanel Orientation="Horizontal" Margin="0,14,0,0">
                      <Button x:Name="BtnBgPick" Style="{StaticResource PrimaryBtn}" Content="选择图片" MinWidth="106"/>
                      <Button x:Name="BtnBgRun" Style="{StaticResource GhostBtn}" Content="重新处理" MinWidth="106" Margin="10,0,0,0"/>
                      <Button x:Name="BtnBgSavePng" Style="{StaticResource GhostBtn}" Content="保存透明 PNG" MinWidth="126" Margin="10,0,0,0"/>
                      <Button x:Name="BtnBgSaveSvg" Style="{StaticResource GhostBtn}" Content="保存矢量图" MinWidth="116" Margin="10,0,0,0"/>
                    </StackPanel>
                  </StackPanel>
                </Border>

                <Border Style="{StaticResource Card}" Padding="16">
                  <StackPanel>
                    <TextBlock Text="运行提示" Style="{StaticResource SectionTitle}"/>
                    <TextBox x:Name="TxtBgLog" Height="158" IsReadOnly="True" AcceptsReturn="True" TextWrapping="Wrap"
                             VerticalScrollBarVisibility="Auto" VerticalContentAlignment="Top"
                             FontFamily="Consolas, Microsoft YaHei UI" FontSize="12"
                             Foreground="{DynamicResource TextSecondary}" Background="{DynamicResource WinBg}"
                             BorderThickness="0" Padding="8,6" Margin="0,8,0,0"/>
                  </StackPanel>
                </Border>
              </StackPanel>

              <Border Grid.Column="2" Style="{StaticResource Card}" Padding="16" VerticalAlignment="Top">
                <StackPanel>
                  <TextBlock Text="参数" Style="{StaticResource SectionTitle}"/>

                  <TextBlock Text="算法" Style="{StaticResource FieldTitle}" Margin="0,12,0,6"/>
                  <ComboBox x:Name="CmbBgMode" SelectedValuePath="Tag">
                    <ComboBoxItem Content="印章通道法（印章 / 文字）" Tag="channel" IsSelected="True"/>
                    <ComboBoxItem Content="纯色背景法（平整背景）" Tag="solid"/>
                  </ComboBox>

                  <TextBlock Text="输出颜色" Style="{StaticResource FieldTitle}" Margin="0,12,0,6"/>
                  <ComboBox x:Name="CmbBgColor" SelectedValuePath="Tag">
                    <ComboBoxItem Content="单色主色（最干净）" Tag="main" IsSelected="True"/>
                    <ComboBoxItem Content="保留原图颜色" Tag="keep"/>
                    <ComboBoxItem Content="反解前景色（去白边）" Tag="unmix"/>
                  </ComboBox>

                  <TextBlock Text="背景明暗" Style="{StaticResource FieldTitle}" Margin="0,12,0,6"/>
                  <ComboBox x:Name="CmbBgLight" SelectedValuePath="Tag">
                    <ComboBoxItem Content="自动判断" Tag="auto" IsSelected="True"/>
                    <ComboBoxItem Content="浅色底（白底黑字）" Tag="light"/>
                    <ComboBoxItem Content="深色底（含渐变）" Tag="dark"/>
                  </ComboBox>
                  <TextBlock Text="深色底会先反相再归一化，带渐变的暗背景也能整片抠掉；选错（当浅色底处理）在暗底上几乎抠不出内容。若主体是比归一化窗口更粗的实心色块，关掉下方「光照归一化」更准。" Foreground="{DynamicResource TextMuted}" FontSize="12" TextWrapping="Wrap" Margin="0,5,0,0"/>

                  <StackPanel x:Name="BgChanPanel">
                    <TextBlock Text="通道" Style="{StaticResource FieldTitle}" Margin="0,12,0,6"/>
                    <ComboBox x:Name="CmbBgChannel" SelectedValuePath="Tag">
                      <ComboBoxItem Content="auto（自动挑对比最强的）" Tag="auto" IsSelected="True"/>
                      <ComboBoxItem Content="R" Tag="R"/>
                      <ComboBoxItem Content="G" Tag="G"/>
                      <ComboBoxItem Content="B" Tag="B"/>
                      <ComboBoxItem Content="R-G" Tag="R-G"/>
                      <ComboBoxItem Content="R-B" Tag="R-B"/>
                      <ComboBoxItem Content="G-R" Tag="G-R"/>
                      <ComboBoxItem Content="G-B" Tag="G-B"/>
                      <ComboBoxItem Content="B-G" Tag="B-G"/>
                      <ComboBoxItem Content="B-R" Tag="B-R"/>
                    </ComboBox>

                    <Grid Margin="0,12,0,0">
                      <TextBlock Text="背景上限 %" Style="{StaticResource FieldTitle}"/>
                      <TextBox x:Name="TxtBgBgPct" Text="90.0" Style="{StaticResource InlineNumBox}"/>
                    </Grid>
                    <TextBlock Text="背景有残留 → 调高；主体被吃掉 → 调低" Foreground="{DynamicResource TextMuted}" FontSize="12"/>
                    <Slider x:Name="SlBgBgPct" Minimum="70" Maximum="99" Value="90" SmallChange="0.5" LargeChange="1" IsMoveToPointEnabled="True"/>

                    <Grid Margin="0,12,0,0">
                      <TextBlock Text="前景实心 %" Style="{StaticResource FieldTitle}"/>
                      <TextBox x:Name="TxtBgFgPct" Text="99.0" Style="{StaticResource InlineNumBox}"/>
                    </Grid>
                    <TextBlock Text="印章淡的部分丢失 → 调低；太淡没层次 → 调高" Foreground="{DynamicResource TextMuted}" FontSize="12"/>
                    <Slider x:Name="SlBgFgPct" Minimum="95" Maximum="99.9" Value="99" SmallChange="0.1" LargeChange="0.5" IsMoveToPointEnabled="True"/>

                    <CheckBox x:Name="ChkBgFlatten" Content="先做背景光照归一化（消除阴影与渐变；实心大色块可关掉）" IsChecked="True" Margin="0,12,0,0"/>
                  </StackPanel>

                  <StackPanel x:Name="BgSolidPanel" Visibility="Collapsed">
                    <Grid Margin="0,12,0,0">
                      <TextBlock Text="容差" Style="{StaticResource FieldTitle}"/>
                      <TextBox x:Name="TxtBgTol" Text="40" Style="{StaticResource InlineNumBox}"/>
                    </Grid>
                    <TextBlock Text="背景残留 → 调大；边缘被啃掉 → 调小" Foreground="{DynamicResource TextMuted}" FontSize="12"/>
                    <Slider x:Name="SlBgTol" Minimum="5" Maximum="120" Value="40" SmallChange="1" LargeChange="5" IsMoveToPointEnabled="True"/>

                    <Grid Margin="0,12,0,0">
                      <TextBlock Text="边缘羽化" Style="{StaticResource FieldTitle}"/>
                      <TextBox x:Name="TxtBgSoft" Text="0.60" Style="{StaticResource InlineNumBox}"/>
                    </Grid>
                    <Slider x:Name="SlBgSoft" Minimum="0" Maximum="1" Value="0.6" SmallChange="0.05" LargeChange="0.1" IsMoveToPointEnabled="True"/>

                    <Grid Margin="0,12,0,0">
                      <TextBlock Text="孔洞面积上限" Style="{StaticResource FieldTitle}"/>
                      <TextBox x:Name="TxtBgHole" Text="0.20" Style="{StaticResource InlineNumBox}"/>
                    </Grid>
                    <TextBlock Text="占全图比例；比它小的孔洞会被一起抠掉" Foreground="{DynamicResource TextMuted}" FontSize="12"/>
                    <Slider x:Name="SlBgHole" Minimum="0" Maximum="1" Value="0.2" SmallChange="0.05" LargeChange="0.1" IsMoveToPointEnabled="True"/>

                    <CheckBox x:Name="ChkBgHoles" Content="抠掉孔洞（印章内圈镂空）" IsChecked="True" Margin="0,12,0,0"/>

                    <TextBlock Text="背景色（留空 = 自动取四角）" Style="{StaticResource FieldTitle}" Margin="0,12,0,6"/>
                    <TextBox x:Name="TxtBgBgColor" Text="" Height="34"/>
                  </StackPanel>

                  <Border Height="1" Background="{DynamicResource CardBorder}" Margin="0,14,0,12"/>
                  <TextBlock Text="矢量化（导出 SVG）" Style="{StaticResource SectionTitle}"/>

                  <Grid Margin="0,12,0,0">
                    <TextBlock Text="路径简化 px" Style="{StaticResource FieldTitle}"/>
                    <TextBox x:Name="TxtBgVecEps" Text="0.8" Style="{StaticResource InlineNumBox}"/>
                  </Grid>
                  <TextBlock Text="越小越贴合原图，节点也越多" Foreground="{DynamicResource TextMuted}" FontSize="12"/>
                  <Slider x:Name="SlBgVecEps" Minimum="0" Maximum="3" Value="0.8" SmallChange="0.1" LargeChange="0.5" IsMoveToPointEnabled="True"/>

                  <CheckBox x:Name="ChkBgVecSmooth" Content="曲线平滑（关闭则全用直线段）" IsChecked="True" Margin="0,12,0,0"/>

                  <Border Height="1" Background="{DynamicResource CardBorder}" Margin="0,14,0,12"/>
                  <TextBlock Text="印章淡的部分丢失 → 调低「前景实心」&#x0a;背景有噪点 → 调高「背景上限」&#x0a;纯色模式建议选「保留原图颜色」&#x0a;矢量图适合印章 / 文字 / logo / 剪影，照片不适合&#x0a;超过 3000px 的图会先等比缩小再处理" Foreground="{DynamicResource TextMuted}" FontSize="12" TextWrapping="Wrap" LineHeight="19"/>
                </StackPanel>
              </Border>
            </Grid>
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
                      <TextBlock x:Name="TxtThemeLightShort" Text="浅" FontSize="16" FontWeight="Normal" HorizontalAlignment="Center" VerticalAlignment="Center" Foreground="#0F0F0F"/>
                    </Border>
                    <StackPanel Grid.Column="1" VerticalAlignment="Center">
                      <TextBlock x:Name="TxtThemeLightName" Text="浅色" FontSize="15" FontWeight="Normal"/>
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
                      <TextBlock x:Name="TxtThemeDarkShort" Text="深" FontSize="16" FontWeight="Normal" HorizontalAlignment="Center" VerticalAlignment="Center" Foreground="#F2F2F7"/>
                    </Border>
                    <StackPanel Grid.Column="1" VerticalAlignment="Center">
                      <TextBlock x:Name="TxtThemeDarkName" Text="深色" FontSize="15" FontWeight="Normal"/>
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
                      <TextBlock x:Name="TxtThemeGithubName" Text="GITHUB" FontSize="15" FontWeight="Normal"/>
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
                      <TextBlock x:Name="TxtThemeAppleName" Text="苹果风格" FontSize="15" FontWeight="Normal"/>
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
                      <TextBlock x:Name="TxtThemeDsaName" Text="DSA" FontSize="15" FontWeight="Normal"/>
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
                      <TextBlock x:Name="TxtThemeChromeName" Text="Chrome" FontSize="15" FontWeight="Normal"/>
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
                      <TextBlock x:Name="TxtThemeSysShort" Text="自" FontSize="16" FontWeight="Normal" HorizontalAlignment="Center" VerticalAlignment="Center" Foreground="{DynamicResource Accent}"/>
                    </Border>
                    <StackPanel Grid.Column="1" VerticalAlignment="Center">
                      <TextBlock x:Name="TxtThemeSysName" Text="跟随系统" FontSize="15" FontWeight="Normal"/>
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
        <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center" Margin="0,0,16,0">
          <TextBlock x:Name="TxtFooterHint" VerticalAlignment="Center"
                     Foreground="{DynamicResource TextMuted}" FontSize="12" TextWrapping="NoWrap"
                     TextTrimming="CharacterEllipsis" IsHitTestVisible="False"
                     Text="左右并排调节 · 拖动滑块实时预览 ·「立即应用」写入配置"/>
          <CheckBox x:Name="ChkTopmost" Content="窗口置顶" Margin="14,0,0,0" VerticalAlignment="Center"
                    ToolTip="勾选后本窗口始终显示在其他程序之上（默认关闭）"/>
        </StackPanel>
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
$ChkBatAlert = $window.FindName('ChkBatAlert')
$SlBatAlert = $window.FindName('SlBatAlert')
$TxtBatAlertVal = $window.FindName('TxtBatAlertVal')
$TxtBatNow = $window.FindName('TxtBatNow')
$TxtBlackoutTitle = $window.FindName('TxtBlackoutTitle')
$TxtBlackoutDesc = $window.FindName('TxtBlackoutDesc')
$ChkBlackout = $window.FindName('ChkBlackout')
$BtnBlackoutReport = $window.FindName('BtnBlackoutReport')
$TxtBlackoutHint = $window.FindName('TxtBlackoutHint')
$TxtEnvTitle = $window.FindName('TxtEnvTitle')
$TxtEnvDesc = $window.FindName('TxtEnvDesc')
$ChkEnvAuto = $window.FindName('ChkEnvAuto')
$ChkEnvApply = $window.FindName('ChkEnvApply')
$TxtEnvNowLabel = $window.FindName('TxtEnvNowLabel')
$TxtEnvNow = $window.FindName('TxtEnvNow')
$TxtEnvPresetLabel = $window.FindName('TxtEnvPresetLabel')
$CmbEnvPreset = $window.FindName('CmbEnvPreset')
$BtnEnvBind = $window.FindName('BtnEnvBind')
$BtnEnvUnbind = $window.FindName('BtnEnvUnbind')
$TxtEnvList = $window.FindName('TxtEnvList')
$ChkTopmost = $window.FindName('ChkTopmost')
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
$TxtNumEditHint = $window.FindName('TxtNumEditHint')
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

# ---- 计算板块 ----
$TabCalc = $window.FindName('TabCalc')
$TabDraw = $window.FindName('TabDraw')
$TxtCalcExpr = $window.FindName('TxtCalcExpr')
$TxtCalcDisp = $window.FindName('TxtCalcDisp')
# 24 个按键统一收进哈希表，事件用 $this.Name 反推含义，不必逐按钮写闭包
$script:calcBtns = @{}
foreach ($n in @('Pct', 'CE', 'C', 'Back', 'Inv', 'Sqr', 'Sqrt', 'Div',
                 '7', '8', '9', 'Mul', '4', '5', '6', 'Sub',
                 '1', '2', '3', 'Add', 'Neg', '0', 'Dot', 'Eq')) {
  $el = $window.FindName('BtnCalc' + $n)
  if ($el) { $script:calcBtns[$n] = $el }
}
$BtnFxFetch = $window.FindName('BtnFxFetch')
$BtnFxCopy = $window.FindName('BtnFxCopy')
$BtnFxPaste = $window.FindName('BtnFxPaste')
$CmbFxPick = $window.FindName('CmbFxPick')
$TxtFxStatus = $window.FindName('TxtFxStatus')
$script:fxEls = @()
for ($i = 0; $i -lt 4; $i++) {
  $script:fxEls += @{
    name = $window.FindName('FxName' + $i)
    buy  = $window.FindName('FxBuy' + $i)
  }
}
$TxtCaseOut = $window.FindName('TxtCaseOut')
$TxtCaseStatus = $window.FindName('TxtCaseStatus')
$BtnCasePaste = $window.FindName('BtnCasePaste')
$BtnCaseConv = $window.FindName('BtnCaseConv')
$BtnCaseCopy = $window.FindName('BtnCaseCopy')

# ---- 画图板块 ----
$BgDropZone = $window.FindName('BgDropZone')
$BgImgIn = $window.FindName('BgImgIn')
$BgImgOut = $window.FindName('BgImgOut')
$TxtBgLog = $window.FindName('TxtBgLog')
$BtnBgPick = $window.FindName('BtnBgPick')
$BtnBgRun = $window.FindName('BtnBgRun')
$BtnBgSavePng = $window.FindName('BtnBgSavePng')
$BtnBgSaveSvg = $window.FindName('BtnBgSaveSvg')
$CmbBgMode = $window.FindName('CmbBgMode')
$CmbBgColor = $window.FindName('CmbBgColor')
$CmbBgLight = $window.FindName('CmbBgLight')
$CmbBgChannel = $window.FindName('CmbBgChannel')
$BgChanPanel = $window.FindName('BgChanPanel')
$BgSolidPanel = $window.FindName('BgSolidPanel')
$ChkBgFlatten = $window.FindName('ChkBgFlatten')
$ChkBgHoles = $window.FindName('ChkBgHoles')
$ChkBgVecSmooth = $window.FindName('ChkBgVecSmooth')
$TxtBgBgColor = $window.FindName('TxtBgBgColor')
$TxtBgBgPct = $window.FindName('TxtBgBgPct');  $SlBgBgPct = $window.FindName('SlBgBgPct')
$TxtBgFgPct = $window.FindName('TxtBgFgPct');  $SlBgFgPct = $window.FindName('SlBgFgPct')
$TxtBgTol = $window.FindName('TxtBgTol');      $SlBgTol = $window.FindName('SlBgTol')
$TxtBgSoft = $window.FindName('TxtBgSoft');    $SlBgSoft = $window.FindName('SlBgSoft')
$TxtBgHole = $window.FindName('TxtBgHole');    $SlBgHole = $window.FindName('SlBgHole')
$TxtBgVecEps = $window.FindName('TxtBgVecEps'); $SlBgVecEps = $window.FindName('SlBgVecEps')

$script:timer = New-Object System.Windows.Threading.DispatcherTimer
$script:timer.Interval = [TimeSpan]::FromMilliseconds(400)
$script:themeWatch = New-Object System.Windows.Threading.DispatcherTimer
$script:themeWatch.Interval = [TimeSpan]::FromSeconds(2)
$script:fontTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:fontTimer.Interval = [TimeSpan]::FromMilliseconds(600)
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
  Check-BatteryAlert
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

# ── 蓝色数字直接输入 ──────────────────────────────────────────────
# 把「滑块 + 小数位 + 单位」登记进映射表；事件处理器用 $this（控件本体）回查，
# 不依赖闭包作用域，避免脚本块在函数作用域销毁后取不到变量。
$script:numEditMap = @{}

function Format-NumEdit([double]$v, [int]$decimals, [string]$suffix) {
  $s = switch ($decimals) {
    0 { '{0:N0}' -f $v }
    1 { '{0:N1}' -f $v }
    default { '{0:N2}' -f $v }
  }
  return ($s + $suffix)
}

function Commit-NumEdit($box) {
  if (-not $box) { return }
  $meta = $script:numEditMap["$($box.Name)"]
  if (-not $meta) { return }
  $slider = $meta.slider
  if (-not $slider) { return }
  $decimals = [int]$meta.decimals
  $suffix = [string]$meta.suffix

  $clean = (([string]$box.Text) -replace '[^0-9\.\-]', '')
  $num = 0.0
  $ok = $false
  if ($clean) {
    try {
      $num = [double]::Parse($clean, [System.Globalization.CultureInfo]::InvariantCulture)
      $ok = $true
    } catch { $ok = $false }
  }
  if (-not $ok) {
    # 输入非法：还原为滑块当前值
    $box.Text = (Format-NumEdit ([double]$slider.Value) $decimals $suffix)
    return
  }

  $mn = [double]$slider.Minimum
  $mx = [double]$slider.Maximum
  if ($num -lt $mn) { $num = $mn }
  if ($num -gt $mx) { $num = $mx }
  if ($decimals -le 0) { $num = [Math]::Round($num) } else { $num = [Math]::Round($num, $decimals) }

  if ([Math]::Abs(([double]$slider.Value) - $num) -gt 0.0000001) {
    # 滑块赋值会触发既有的 ValueChanged → 持久化 + 实时应用；滑块也随之滑到新位置
    $slider.Value = $num
  }
  $box.Text = (Format-NumEdit ([double]$slider.Value) $decimals $suffix)
}

function Register-NumEdit($box, $slider, [int]$decimals, [string]$suffix) {
  if (-not $box -or -not $slider) { return }
  if (-not $box.Name) { return }
  $script:numEditMap[$box.Name] = @{ slider = $slider; decimals = $decimals; suffix = $suffix }
  $box.Add_GotFocus({ try { $this.SelectAll() } catch {} })
  $box.Add_KeyDown({
    try {
      $k = $args[1].Key
      if ($k -eq [System.Windows.Input.Key]::Return -or $k -eq [System.Windows.Input.Key]::Enter) {
        Commit-NumEdit $this
        $args[1].Handled = $true
      }
    } catch {}
  })
  $box.Add_LostFocus({ Commit-NumEdit $this })
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
  $rb = Apply-Brightness ([int]$b) -Force
  $rc = Apply-Contrast ([int]$c) -Force
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

# 字体伽马防抖：仅当停留在「字体」页时把当前 UI 状态持久化到注册表。
# 故意不调 SPI 伽马/方向（本机实时写会损坏 live 值，见 Set-FontSmoothingSettings 注释）。
function Persist-FontGammaOnly {
  try {
    $en = if ($ChkClearType) { [bool]$ChkClearType.IsChecked } else { $true }
    $fg = if ($SlFontGamma) { [double]$SlFontGamma.Value } else { 1.4 }
    $ori = if ($RbRgb -and $RbRgb.IsChecked) { 1 } else { 0 }
    $g = [int][Math]::Round($fg * 1000)
    if ($g -lt 1000) { $g = 1000 }
    if ($g -gt 2200) { $g = 2200 }
    Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name FontSmoothing -Value ($(if($en){'2'}else{'0'}))
    Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name FontSmoothingType -Value ($(if($en){2}else{1})) -Type DWord
    Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name FontSmoothingGamma -Value $g -Type DWord
    Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name FontSmoothingOrientation -Value $ori -Type DWord
    if (-not $script:uiSettings) { $script:uiSettings = @{} }
    $script:uiSettings.fontApplied = @{ clearType = $en; gamma = [math]::Round([double]$fg, 2); orientation = [int]$ori }
    try { Save-UiSettings $script:uiSettings } catch {}
  } catch {}
}

$script:fontTimer.Add_Tick({
  $script:fontTimer.Stop()
  if ($script:loading) { return }
  if (-not (Get-IsFontTabActive)) { return }
  Persist-FontGammaOnly
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
# ClearType 复选框与 RGB/BGR 单选改动即持久化注册表（伽马需注销生效；开关点「应用」后经 SPI 即时生效）
if ($ChkClearType) {
  $ChkClearType.Add_Checked({ if (-not $script:loading) { Persist-FontGammaOnly } })
  $ChkClearType.Add_Unchecked({ if (-not $script:loading) { Persist-FontGammaOnly } })
}
if ($RbRgb) {
  $RbRgb.Add_Checked({ if (-not $script:loading) { Persist-FontGammaOnly } })
}
if ($RbBgr) {
  $RbBgr.Add_Checked({ if (-not $script:loading) { Persist-FontGammaOnly } })
}

# 低电量插电提醒：初始化 + 事件（默认开启，阈值 73%，建议高于 70%）
$batAlertOn = Get-BatteryAlertEnabled
$batAlertThr = Get-BatteryAlertThreshold
if ($ChkBatAlert) { $ChkBatAlert.IsChecked = [bool]$batAlertOn }
if ($SlBatAlert) { $SlBatAlert.Value = [double]$batAlertThr }
if ($TxtBatAlertVal) { $TxtBatAlertVal.Text = ([string]$batAlertThr + '%') }
if ($ChkBatAlert) {
  $ChkBatAlert.Add_Checked({
    if ($script:loading) { return }
    $script:uiSettings.batteryAlertEnabled = $true
    Save-BatteryAlertSettings
  })
  $ChkBatAlert.Add_Unchecked({
    if ($script:loading) { return }
    $script:uiSettings.batteryAlertEnabled = $false
    Save-BatteryAlertSettings
  })
}
if ($SlBatAlert) {
  $SlBatAlert.Add_ValueChanged({
    if ($script:loading) { return }
    $v = [int][math]::Round($SlBatAlert.Value)
    if ($TxtBatAlertVal) { $TxtBatAlertVal.Text = ([string]$v + '%') }
    $script:uiSettings.batteryAlertThreshold = $v
    Save-BatteryAlertSettings
  })
}

# 黑屏报告：初始化 + 事件（默认开启）
if ($ChkBlackout) { $ChkBlackout.IsChecked = [bool](Get-BlackoutReportEnabled) }
if ($ChkBlackout) {
  $ChkBlackout.Add_Checked({
    if ($script:loading) { return }
    $script:uiSettings.blackoutReportEnabled = $true
    Save-BlackoutSetting
  })
  $ChkBlackout.Add_Unchecked({
    if ($script:loading) { return }
    $script:uiSettings.blackoutReportEnabled = $false
    Save-BlackoutSetting
  })
}
if ($BtnBlackoutReport) {
  $BtnBlackoutReport.Add_Click({
    try {
      $r = New-BlackoutReport
      $script:blackoutHit = [pscustomobject]@{ Found = $r.Found; Event = $r.Event; Prev = $r.Prev }
      Update-BlackoutHint
      if (-not (Open-BlackoutReport $r.Path)) {
        [System.Windows.MessageBox]::Show(((T 'blackoutOpenFail') + $r.Path), (T 'blackoutTitle'))
      }
    } catch {
      try { [System.Windows.MessageBox]::Show($_.Exception.Message, (T 'blackoutTitle')) } catch {}
    }
  })
}

# 心跳：30 秒一次，异常掉电时留给下次启动作「黑屏前状态」证据
$script:beatTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:beatTimer.Interval = [TimeSpan]::FromSeconds(30)
$script:beatTimer.Add_Tick({ Write-SessionBeat $false })

# ---------- 环境自动切换：控件事件 + 轮询 ----------
$script:envState = Load-EnvBinds
if ($ChkEnvAuto) {
  $ChkEnvAuto.Add_Checked({
    if ($script:loading) { return }
    if (-not $script:envState) { $script:envState = Load-EnvBinds }
    $script:envState.enabled = $true
    Save-EnvBinds $script:envState
    $script:envLastApplied = ''
    Test-EnvAutoSwitch
  })
  $ChkEnvAuto.Add_Unchecked({
    if ($script:loading) { return }
    if (-not $script:envState) { $script:envState = Load-EnvBinds }
    $script:envState.enabled = $false
    Save-EnvBinds $script:envState
  })
}
if ($ChkEnvApply) {
  $ChkEnvApply.Add_Checked({
    if ($script:loading) { return }
    if (-not $script:envState) { $script:envState = Load-EnvBinds }
    $script:envState.autoApply = $true
    Save-EnvBinds $script:envState
  })
  $ChkEnvApply.Add_Unchecked({
    if ($script:loading) { return }
    if (-not $script:envState) { $script:envState = Load-EnvBinds }
    $script:envState.autoApply = $false
    Save-EnvBinds $script:envState
  })
}
if ($BtnEnvBind) {
  $BtnEnvBind.Add_Click({
    try {
      if (-not $script:envState) { $script:envState = Load-EnvBinds }
      $name = ''
      if ($CmbEnvPreset -and $null -ne $CmbEnvPreset.SelectedItem) { $name = [string]$CmbEnvPreset.SelectedItem }
      if (-not $name) { [System.Windows.MessageBox]::Show((T 'envNeedPreset'), (T 'tip')); return }
      $fp = if ($script:envNow) { $script:envNow } else { Get-EnvFingerprint }
      # 同一环境只保留一条绑定（重新绑定即覆盖）
      $keep = New-Object System.Collections.ArrayList
      foreach ($b in @($script:envState.binds)) {
        if (([string]$b.display -eq [string]$fp.display) -and ([string]$b.wifi -eq [string]$fp.wifi) -and ([string]$b.ipseg -eq [string]$fp.ipseg)) { continue }
        [void]$keep.Add($b)
      }
      [void]$keep.Add([ordered]@{ preset = $name; display = [string]$fp.display; wifi = [string]$fp.wifi; ipseg = [string]$fp.ipseg; label = [string]$fp.label })
      $script:envState.binds = @($keep)
      Save-EnvBinds $script:envState
      Update-EnvUi
      [System.Windows.MessageBox]::Show((TF 'envBindOkFmt' $name), (T 'appTitle'))
    } catch {
      try { [System.Windows.MessageBox]::Show($_.Exception.Message, (T 'appTitle')) } catch {}
    }
  })
}
if ($BtnEnvUnbind) {
  $BtnEnvUnbind.Add_Click({
    try {
      if (-not $script:envState) { $script:envState = Load-EnvBinds }
      $name = ''
      if ($CmbEnvPreset -and $null -ne $CmbEnvPreset.SelectedItem) { $name = [string]$CmbEnvPreset.SelectedItem }
      if (-not $name) { [System.Windows.MessageBox]::Show((T 'envNeedPreset'), (T 'tip')); return }
      $keep = New-Object System.Collections.ArrayList
      foreach ($b in @($script:envState.binds)) { if ([string]$b.preset -ne $name) { [void]$keep.Add($b) } }
      $script:envState.binds = @($keep)
      Save-EnvBinds $script:envState
      Update-EnvUi
      [System.Windows.MessageBox]::Show((TF 'envUnbindOkFmt' $name), (T 'appTitle'))
    } catch {}
  })
}

# 环境轮询：45 秒一次（换环境是低频事件，查询开销很小）
$script:envTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:envTimer.Interval = [TimeSpan]::FromSeconds(45)
$script:envTimer.Add_Tick({ Test-EnvAutoSwitch })

# ---------- 窗口置顶开关（默认关闭：避免一直压在其他程序上面） ----------
if ($ChkTopmost) {
  $tw = if ($null -ne $script:uiSettings.windowTopmost) { [bool]$script:uiSettings.windowTopmost } else { $false }
  $script:uiSettings.windowTopmost = $tw
  $ChkTopmost.IsChecked = $tw
  try { $window.Topmost = $tw } catch {}
  $ChkTopmost.Add_Checked({
    if ($script:loading) { return }
    $script:uiSettings.windowTopmost = $true
    try { $window.Topmost = $true } catch {}
    try { Save-UiSettings $script:uiSettings } catch {}
  })
  $ChkTopmost.Add_Unchecked({
    if ($script:loading) { return }
    $script:uiSettings.windowTopmost = $false
    try { $window.Topmost = $false } catch {}
    try { Save-UiSettings $script:uiSettings } catch {}
  })
}

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

# 蓝色数字：登记为「可直接输入 + 回车生效」
Register-NumEdit $TxtBright     $SlBright    0 ''
Register-NumEdit $TxtContrast   $SlContrast  0 ''
Register-NumEdit $TxtGamma      $SlGamma     2 ''
Register-NumEdit $TxtScale      $SlScale     2 ''
Register-NumEdit $TxtFontGamma  $SlFontGamma 2 ''
Register-NumEdit $TxtBatAlertVal $SlBatAlert 0 '%'

# =====================================================================
# 计算板块 / 画图板块 —— 事件装配（2026-09-20 新增）
# =====================================================================
Register-NumEdit $TxtBgBgPct  $SlBgBgPct  1 ''
Register-NumEdit $TxtBgFgPct  $SlBgFgPct  1 ''
Register-NumEdit $TxtBgTol    $SlBgTol    0 ''
Register-NumEdit $TxtBgSoft   $SlBgSoft   2 ''
Register-NumEdit $TxtBgHole   $SlBgHole   2 ''
Register-NumEdit $TxtBgVecEps $SlBgVecEps 1 ''

# 计算器按键派发：$this 就是被按下的那个按钮，用它的名字反推含义，
# 于是 24 个按键只需要一份处理函数。
function Invoke-CalcKey {
  param([string]$k)
  switch ($k) {
    '0' { Invoke-CalcDigit '0' }
    '1' { Invoke-CalcDigit '1' }
    '2' { Invoke-CalcDigit '2' }
    '3' { Invoke-CalcDigit '3' }
    '4' { Invoke-CalcDigit '4' }
    '5' { Invoke-CalcDigit '5' }
    '6' { Invoke-CalcDigit '6' }
    '7' { Invoke-CalcDigit '7' }
    '8' { Invoke-CalcDigit '8' }
    '9' { Invoke-CalcDigit '9' }
    'Dot' { Invoke-CalcDot }
    'Add' { Invoke-CalcOp '+' }
    'Sub' { Invoke-CalcOp '-' }
    'Mul' { Invoke-CalcOp '*' }
    'Div' { Invoke-CalcOp '/' }
    'Eq' { Invoke-CalcEquals }
    'C' { Invoke-CalcClearAll }
    'CE' { Invoke-CalcClearEntry }
    'Back' { Invoke-CalcBack }
    'Neg' { Invoke-CalcUnary 'neg' }
    'Pct' { Invoke-CalcUnary 'pct' }
    'Inv' { Invoke-CalcUnary 'inv' }
    'Sqr' { Invoke-CalcUnary 'sqr' }
    'Sqrt' { Invoke-CalcUnary 'sqrt' }
  }
}

foreach ($kv in $script:calcBtns.GetEnumerator()) {
  $kv.Value.Add_Click({ Invoke-CalcKey (($this.Name) -replace '^BtnCalc', '') })
}

if ($BtnFxFetch) { $BtnFxFetch.Add_Click({ Invoke-FxFetch }) }
if ($BtnFxCopy) { $BtnFxCopy.Add_Click({ Copy-FxRate }) }
if ($BtnFxPaste) { $BtnFxPaste.Add_Click({ Paste-FxRate }) }
# 牌价卡里的币种一换，下面「数字转英文大写」的货币要跟着换
if ($CmbFxPick) {
  $CmbFxPick.Add_SelectionChanged({
    if ($script:loading) { return }
    try { Sync-CaseAmountFromCalc } catch {}
    # 下拉框一变，牌价表里的高亮行也要跟着走（两边是双向同步的）
    try {
      $rb = $window.FindName('FxRow' + $CmbFxPick.SelectedIndex)
      if ($rb) { $rb.IsChecked = $true }
    } catch {}
  })
}
# 牌价表整行可点：点哪一行就等于把币种下拉切到那一个。
# IsChecked 由 GroupName 保证互斥，不用手工去取消别的行。
for ($i = 0; $i -lt 4; $i++) {
  $rbRow = $window.FindName('FxRow' + $i)
  if ($rbRow) {
    $rbRow.Add_Checked({
      try {
        $j = [int]$this.Tag
        if ($CmbFxPick -and $CmbFxPick.SelectedIndex -ne $j) { $CmbFxPick.SelectedIndex = $j }
      } catch {}
    })
  }
}
if ($BtnCaseConv) { $BtnCaseConv.Add_Click({ Invoke-CaseConvert }) }
# 金额已经没有独立输入框了：数字只在大读数框里捕获，转大写全自动。
if ($BtnCaseCopy) {
  $BtnCaseCopy.Add_Click({ Copy-CaseResult })
  $BtnCaseCopy.Add_MouseLeave({ try { $BtnCaseCopy.Content = '复制结果' } catch {} })
}
if ($BtnCasePaste) { $BtnCasePaste.Add_Click({ Paste-CaseResult }) }

# 计算器键盘支持：只在「计算」页选中、且焦点不在输入框/下拉框时才吞按键，
# 否则会干扰其它页的正常输入。
$script:calcKeyMap = @{
  'D0' = '0'; 'D1' = '1'; 'D2' = '2'; 'D3' = '3'; 'D4' = '4'
  'D5' = '5'; 'D6' = '6'; 'D7' = '7'; 'D8' = '8'; 'D9' = '9'
  'NumPad0' = '0'; 'NumPad1' = '1'; 'NumPad2' = '2'; 'NumPad3' = '3'; 'NumPad4' = '4'
  'NumPad5' = '5'; 'NumPad6' = '6'; 'NumPad7' = '7'; 'NumPad8' = '8'; 'NumPad9' = '9'
  'Add' = 'Add'; 'OemPlus' = 'Add'
  'Subtract' = 'Sub'; 'OemMinus' = 'Sub'
  'Multiply' = 'Mul'
  'Divide' = 'Div'; 'Oem2' = 'Div'; 'OemQuestion' = 'Div'
  'Decimal' = 'Dot'; 'OemPeriod' = 'Dot'; 'OemComma' = 'Dot'
  'Return' = 'Eq'; 'Enter' = 'Eq'
  'Back' = 'Back'; 'Delete' = 'CE'; 'Escape' = 'C'
}
$window.Add_PreviewKeyDown({
  try {
    if (-not ($TabCalc -and $TabCalc.IsSelected)) { return }
    $f = [System.Windows.Input.Keyboard]::FocusedElement
    if ($f -is [System.Windows.Controls.Primitives.TextBoxBase]) { return }
    if ($f -is [System.Windows.Controls.ComboBox]) { return }
    $kn = [string]($args[1].Key)
    if ($script:calcKeyMap.ContainsKey($kn)) {
      Invoke-CalcKey $script:calcKeyMap[$kn]
      $args[1].Handled = $true
    }
  } catch {}
})

# ---------------- 画图板块事件 ----------------
if ($BtnBgPick) { $BtnBgPick.Add_Click({ Select-BgImage }) }
if ($BtnBgRun) { $BtnBgRun.Add_Click({ Invoke-BgProcess }) }
if ($BtnBgSavePng) { $BtnBgSavePng.Add_Click({ Save-BgPng }) }
if ($BtnBgSaveSvg) { $BtnBgSaveSvg.Add_Click({ Save-BgSvg }) }
# 参数改动只切换面板显隐，不自动重算（重算要几秒，交给「重新处理」按钮）
if ($CmbBgMode) { $CmbBgMode.Add_SelectionChanged({ if (-not $script:loading) { Update-BgParamPanels } }) }

if ($BgDropZone) {
  $BgDropZone.Add_DragOver({
    try {
      if ($args[1].Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
        $args[1].Effects = [System.Windows.DragDropEffects]::Copy
      } else {
        $args[1].Effects = [System.Windows.DragDropEffects]::None
      }
      $args[1].Handled = $true
    } catch {}
  })
  $BgDropZone.Add_Drop({
    try {
      $files = $args[1].Data.GetData([System.Windows.DataFormats]::FileDrop)
      if ($files -and $files.Count -gt 0) {
        $f = [string]$files[0]
        $ext = [System.IO.Path]::GetExtension($f).ToLower()
        if (@('.png', '.jpg', '.jpeg', '.bmp', '.webp', '.tif', '.tiff') -contains $ext) {
          Open-BgImage $f
        } else {
          Add-BgLog ('不支持的格式：' + $ext)
        }
      }
      $args[1].Handled = $true
    } catch {
      Add-BgLog ('拖入失败：' + $_.Exception.Message)
    }
  })
}

# 新建的两个板块在载入后初始化一次（此时 $script:loading 已由既有 Loaded 复位）
$window.Add_Loaded({
  try { Update-BgParamPanels } catch {}
  try { Load-FxCache; Update-FxUi } catch {}
  try { Show-CalcDisplay } catch {}
  try { Invoke-CaseConvert } catch {}
  try { Add-BgLog '就绪：把图片拖进「预览」卡片，或点「选择图片」。改参数后点「重新处理」生效。' } catch {}
})
if ($SlFontGamma) { $SlFontGamma.Add_ValueChanged({ if (-not $script:loading -and $TxtFontGamma) { $TxtFontGamma.Text = ('{0:N2}' -f $SlFontGamma.Value) }; if (-not $script:loading -and $script:fontTimer) { $script:fontTimer.Stop(); $script:fontTimer.Start() } }) }

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

    # 黑屏报告：心跳启动 + 启动检测（延迟执行，不阻塞首帧）
    try { if ($script:beatTimer) { $script:beatTimer.Start() } } catch {}
    Write-SessionBeat $false
    $script:blackoutTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:blackoutTimer.Interval = [TimeSpan]::FromMilliseconds(1200)
    $script:blackoutTimer.Add_Tick({
      try { $script:blackoutTimer.Stop() } catch {}
      Test-BlackoutOnStartup
      Test-EnvAutoSwitch
    })
    $script:blackoutTimer.Start()
    try { if ($script:envTimer) { $script:envTimer.Start() } } catch {}
  } catch {
    [System.Windows.MessageBox]::Show(((T 'initFail') + $_.Exception.Message), (T 'appTitle'))
  } finally {
    $script:loading = $false
  }
})

$window.Add_Closed({
  try { if ($script:timer) { $script:timer.Stop() } } catch {}
  try { if ($script:beatTimer) { $script:beatTimer.Stop() } } catch {}
  try { if ($script:blackoutTimer) { $script:blackoutTimer.Stop() } } catch {}
  try { if ($script:envTimer) { $script:envTimer.Stop() } } catch {}
  # 正常退出：打上干净标记，避免下次启动误判为黑屏
  Write-SessionBeat $true
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


