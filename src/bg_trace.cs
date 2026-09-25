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
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

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
