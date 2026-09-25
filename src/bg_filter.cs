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
using System;
using System.Collections.Generic;

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
