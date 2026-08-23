#!/usr/bin/env python3
"""
The silhouette test for the Sunlit app icon.

Downscales design/icon-1024.png to every raster size iOS actually draws it at,
writes each one to design/silhouette/ so a human can look, and then measures
whether the two load bearing shapes, the arc and the sun disc, still separate.

Geometry is imported from icon.py rather than restated here, and the PNG is
re-rendered in memory and compared pixel for pixel before anything is measured,
so the test can neither restate a layout nor grade a stale file. The render is
deterministic, so that comparison is an equality.

What is measured, per size
--------------------------
1. ARC against its immediate background.
   The arc centreline is sampled along its length. At each sample two probes are
   taken perpendicular to the stroke, one inside the dome and one outside, each
   placed PROBE_CLEAR downscaled pixels clear of the edge of the stroke. Probes
   that would land on the horizon hairline or off the canvas are dropped,
   because those measure another drawn element rather than background.
   Reported: the worst and the median WCAG contrast ratio, and where the worst
   probe landed.

2. SUN DISC against the arc.
   Reported: the WCAG contrast ratio, the CIE76 colour difference dE, and the
   clear sky gap knocked out of the arc around the disc, measured as a ring at
   half gap width and reported against both the disc and the arc.

   The luminance ratio between the sun and the arc is about 1.5:1 and cannot be
   raised: the design contract fixes the sun accent at #FFB020 and asks for a
   light warm arc, and nothing lighter than that amber reaches 3:1 against it.
   The disc is therefore separated from the arc by hue and by a measured gap,
   and both of those carry a bar. Hue alone would not do: with sun_gap set to
   zero the disc welds itself to the arc and dE stays at 58, so a rule written
   on dE alone passes an icon the design explicitly rejects.

3. A two tone threshold render at 29 pixels, tested for arc rather than blob.

Pass rules
----------
ARC  : worst contrast against background >= 3.0, the WCAG bar for a graphical
       object that carries meaning.
SUN  : two bars, both required.
       Tone, contrast >= 3.0 against the arc OR dE >= 15 against the arc. dE 15
       is well past the dE 10 at which two colours read as different colours
       rather than as shades of one, and the difference here sits mostly on the
       blue to yellow axis, which survives the common forms of colour blindness.
       Gap, the knockout ring >= 1.5 against the disc and >= 1.5 against the
       arc, so the sky really does come between the two.
BLOB : the sky under the apex stays background, the arc stays a stroke rather
       than a filled dome, the highest point of the silhouette sits near the
       middle, the top edge falls away toward both ends, the lit shape spans
       most of the width, and the top of the silhouette belongs to the arc
       rather than to the disc.

Usage:
    python3 design/silhouette-test.py
"""

import math
import os
import sys

try:
    from PIL import Image
except ImportError:  # pragma: no cover - environment fallback
    _FALLBACK = "/usr/bin/python3"
    if sys.executable != _FALLBACK and os.path.exists(_FALLBACK):
        os.execv(_FALLBACK, [_FALLBACK] + sys.argv)
    sys.exit("Pillow is required. Install it with: python3 -m pip install Pillow")

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import icon  # noqa: E402  the renderer is the single source of geometry

SIZES = [180, 120, 87, 80, 60, 40, 29]
SOURCE = os.path.join(HERE, "icon-1024.png")
OUTDIR = os.path.join(HERE, "silhouette")

CONTRAST_MIN = 3.0      # WCAG non text contrast
DELTA_E_MIN = 15.0      # CIE76, comfortably past the dE 10 "different colour" line
# The knockout ring must be measurably darker than both the disc it surrounds and
# the arc it interrupts. The bar is set from measurement, not taste: rendering
# with sun_gap = 0, so the disc touches the arc, puts the ring at 1.05 to 1.24
# against the disc and 1.16 to 1.22 against the arc, because the ring is then ink
# rather than sky. The shipped icon's worst size, 29, reads 1.73 and 2.58. 1.50
# sits between the two with room on both sides.
GAP_MIN = 1.50
PROBE_CLEAR = 1.6       # downscaled pixels of clearance a probe needs
ARC_SAMPLES = 61
RING_SAMPLES = 24


# ---------------------------------------------------------------------------
# Colour
# ---------------------------------------------------------------------------

def _linear(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def luminance(rgb):
    r, g, b = (_linear(v) for v in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(rgb_a, rgb_b):
    la, lb = luminance(rgb_a), luminance(rgb_b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def _lab(rgb):
    r, g, b = (_linear(v) for v in rgb)
    x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
    y = (0.2126 * r + 0.7152 * g + 0.0722 * b)
    z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883

    def f(t):
        return t ** (1.0 / 3.0) if t > 216.0 / 24389.0 else (841.0 / 108.0) * t + 4.0 / 29.0

    fx, fy, fz = f(x), f(y), f(z)
    return (116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))


def delta_e(rgb_a, rgb_b):
    la, aa, ba = _lab(rgb_a)
    lb, ab, bb = _lab(rgb_b)
    return math.sqrt((la - lb) ** 2 + (aa - ab) ** 2 + (ba - bb) ** 2)


# ---------------------------------------------------------------------------
# Sampling
# ---------------------------------------------------------------------------

class Sampler:
    """Bilinear sampling of a downscaled icon, addressed in 1024 unit coords."""

    def __init__(self, img, side_units):
        self.n = img.size[0]
        self.px = img.convert("RGB").load()
        self.units = side_units
        self.pitch = side_units / float(self.n)   # icon units per image pixel

    def inside(self, x, y, margin_px=0.5):
        m = margin_px * self.pitch
        return m <= x <= self.units - m and m <= y <= self.units - m

    def __call__(self, x, y):
        u = x / self.pitch - 0.5
        v = y / self.pitch - 0.5
        u = min(max(u, 0.0), self.n - 1.0)
        v = min(max(v, 0.0), self.n - 1.0)
        i0, j0 = int(math.floor(u)), int(math.floor(v))
        i1, j1 = min(i0 + 1, self.n - 1), min(j0 + 1, self.n - 1)
        fu, fv = u - i0, v - j0
        out = []
        for c in range(3):
            top = self.px[i0, j0][c] * (1 - fu) + self.px[i1, j0][c] * fu
            bot = self.px[i0, j1][c] * (1 - fu) + self.px[i1, j1][c] * fu
            out.append(top * (1 - fv) + bot * fv)
        return tuple(out)


def median(values):
    s = sorted(values)
    k = len(s)
    return s[k // 2] if k % 2 else 0.5 * (s[k // 2 - 1] + s[k // 2])


# ---------------------------------------------------------------------------
# Test 1: the arc against its background
# ---------------------------------------------------------------------------

def test_arc(smp, g):
    off = g["arc_w"] / 2.0 + PROBE_CLEAR * smp.pitch
    horizon_guard = g["horizon_w"] / 2.0 + PROBE_CLEAR * smp.pitch
    sun_x, sun_y = g["sun"]
    hole_guard = g["r_hole"] + g["arc_w"] / 2.0

    worst = None
    ratios = []
    for k in range(ARC_SAMPLES):
        t = 0.05 + 0.90 * k / (ARC_SAMPLES - 1)
        x, y = icon.arc_point(g, t)
        if math.hypot(x - sun_x, y - sun_y) < hole_guard:
            continue                      # the arc is knocked out here
        nx, ny = icon.arc_normal(g, t)
        ink = smp(x, y)
        for sign, side in ((1.0, "outside"), (-1.0, "inside")):
            px_, py_ = x + sign * nx * off, y + sign * ny * off
            if not smp.inside(px_, py_):
                continue
            if abs(py_ - g["horizon_y"]) < horizon_guard:
                continue
            c = contrast(ink, smp(px_, py_))
            ratios.append(c)
            if worst is None or c < worst[0]:
                worst = (c, t, side)

    return {
        "n": len(ratios),
        "worst": worst[0] if worst else 0.0,
        "worst_at": ("t=%.2f %s" % (worst[1], worst[2])) if worst else "none",
        "median": median(ratios) if ratios else 0.0,
        "pass": bool(ratios) and len(ratios) >= 20 and worst[0] >= CONTRAST_MIN,
    }


# ---------------------------------------------------------------------------
# Test 2: the sun disc against the arc
# ---------------------------------------------------------------------------

def _mean_rgb(samples):
    return tuple(sum(s[c] for s in samples) / len(samples) for c in range(3))


def test_sun(smp, g):
    sx, sy = g["sun"]
    rs = g["r_sun"]

    core = [smp(sx, sy)]
    for k in range(8):
        a = 2 * math.pi * k / 8
        core.append(smp(sx + 0.40 * rs * math.cos(a), sy + 0.40 * rs * math.sin(a)))
    sun_rgb = _mean_rgb(core)

    # Arc reference: the centreline just clear of the knockout, on both sides.
    ds = (g["r_hole"] + PROBE_CLEAR * smp.pitch) / g["arc_len"]
    arc_rgbs = []
    for dt in (-ds, +ds):
        t = g["sun_t"] + dt
        if 0.02 <= t <= 0.98:
            arc_rgbs.append(smp(*icon.arc_point(g, t)))
    arc_rgb = min(arc_rgbs, key=lambda c: contrast(sun_rgb, c))

    ring_r = rs + g["gap"] / 2.0
    ring = [smp(sx + ring_r * math.cos(2 * math.pi * k / RING_SAMPLES),
                sy + ring_r * math.sin(2 * math.pi * k / RING_SAMPLES))
            for k in range(RING_SAMPLES)]

    c_sun_arc = contrast(sun_rgb, arc_rgb)
    de_sun_arc = delta_e(sun_rgb, arc_rgb)
    gap_vs_sun = min(contrast(sun_rgb, r) for r in ring)
    gap_vs_arc = min(contrast(r, arc_rgb) for r in ring)

    # Both halves of the contract are gated. The hue difference alone is not
    # enough: it stays at dE 58 even when sun_gap is zero and the disc is welded
    # to the arc, so a rule written on dE alone would pass an icon the design
    # explicitly rejects. The gap has to carry its own bar.
    tone_ok = c_sun_arc >= CONTRAST_MIN or de_sun_arc >= DELTA_E_MIN
    gap_ok = gap_vs_sun >= GAP_MIN and gap_vs_arc >= GAP_MIN

    return {
        "sun_rgb": tuple(int(round(v)) for v in sun_rgb),
        "arc_rgb": tuple(int(round(v)) for v in arc_rgb),
        "contrast": c_sun_arc,
        "delta_e": de_sun_arc,
        "gap_vs_sun": gap_vs_sun,
        "gap_vs_arc": gap_vs_arc,
        "tone_pass": tone_ok,
        "gap_pass": gap_ok,
        "pass": tone_ok and gap_ok,
    }


# ---------------------------------------------------------------------------
# Test 3: two tone threshold at 29, arc or blob
# ---------------------------------------------------------------------------

def otsu(values):
    hist = [0] * 256
    for v in values:
        hist[min(255, max(0, int(round(v * 255.0))))] += 1
    total = len(values)
    sum_all = sum(i * hist[i] for i in range(256))
    sum_b = 0.0
    w_b = 0
    best, thr = -1.0, 128
    for i in range(256):
        w_b += hist[i]
        if w_b == 0:
            continue
        w_f = total - w_b
        if w_f == 0:
            break
        sum_b += i * hist[i]
        var = w_b * w_f * (sum_b / w_b - (sum_all - sum_b) / w_f) ** 2
        if var > best:
            best, thr = var, i
    return thr / 255.0


def test_threshold(img29, g, units):
    n = img29.size[0]
    px = img29.convert("RGB").load()
    lum = [[luminance(px[i, j]) for i in range(n)] for j in range(n)]
    thr = otsu([v for row in lum for v in row])
    fg = [[lum[j][i] > thr for i in range(n)] for j in range(n)]

    two = Image.new("L", (n, n))
    two.putdata([255 if fg[j][i] else 0 for j in range(n) for i in range(n)])
    two.save(os.path.join(OUTDIR, "threshold-29.png"))
    two.resize((n * 10, n * 10), Image.NEAREST).save(
        os.path.join(OUTDIR, "threshold-29-x10.png"))

    pitch = units / float(n)

    def col_of(x):
        return int(min(n - 1, max(0, math.floor(x / pitch))))

    def row_of(y):
        return int(min(n - 1, max(0, math.floor(y / pitch))))

    # (a) the sky under the apex must stay background
    hx = col_of(units * 0.5)
    hy = row_of((g["apex"][1] + g["horizon_y"]) / 2.0)
    hollow_fg = sum(1 for j in range(max(0, hy - 1), min(n, hy + 2))
                    for i in range(max(0, hx - 1), min(n, hx + 2)) if fg[j][i])

    # (b) a stroke, not a filled dome
    hz = row_of(g["horizon_y"])
    counts = [sum(1 for j in range(hz) if fg[j][i])
              for i in range(col_of(units * 0.16), col_of(units * 0.84) + 1)]
    fill_median = median(counts) if counts else 0.0
    fill_max = max(counts) if counts else 0

    # (c) the top edge peaks near the middle and descends toward both extremes.
    # Measured against the leftmost and rightmost lit columns, which are the
    # arc's two landings, and not against a percentile of the lit columns: the
    # sun deliberately occupies the left flank, so a percentile would measure
    # the disc and report a flat silhouette for a shape that plainly domes.
    tops = {}
    for i in range(n):
        for j in range(hz):
            if fg[j][i]:
                tops[i] = j
                break
    peak_x = None
    drop_left = drop_right = span = 0.0
    if tops:
        cols = sorted(tops)
        peak_col = min(tops, key=lambda i: tops[i])
        peak_x = (peak_col + 0.5) * pitch / units
        drop_left = tops[cols[0]] - tops[peak_col]
        drop_right = tops[cols[-1]] - tops[peak_col]
        span = (cols[-1] - cols[0] + 1) / float(n)
    drop_needed = 0.45 * (g["horizon_y"] - g["apex"][1]) / pitch

    # (d) the arc, not the disc, must own the top of the silhouette. Everything
    # above only looks at the outline, and an outline whose highest point is the
    # sun still domes and still descends toward both ends: moving sun_t to 0.50
    # puts the disc on the apex, breaks the arc into two disconnected hooks, and
    # passes every rule above. So compare the two directly. The columns the disc
    # covers are known from the geometry, and the arc has to reach higher.
    sun_x = g["sun"][0]
    disc_cols = set(range(col_of(sun_x - g["r_sun"]), col_of(sun_x + g["r_sun"]) + 1))
    arc_top = min([tops[i] for i in tops if i not in disc_cols], default=None)
    disc_top = min([tops[i] for i in tops if i in disc_cols], default=None)
    apex_is_arc = arc_top is not None and (disc_top is None or arc_top < disc_top)

    ok = (hollow_fg == 0
          and fill_median <= 4.0
          and peak_x is not None and 0.30 <= peak_x <= 0.70
          and drop_left >= drop_needed and drop_right >= drop_needed
          and span >= 0.70
          and apex_is_arc)

    return {
        "threshold": thr, "hollow_fg": hollow_fg,
        "fill_median": fill_median, "fill_max": fill_max,
        "peak_x": peak_x, "drop_left": drop_left, "drop_right": drop_right,
        "drop_needed": drop_needed, "span": span,
        "arc_top": arc_top, "disc_top": disc_top, "apex_is_arc": apex_is_arc,
        "pass": ok,
    }


# ---------------------------------------------------------------------------

def main():
    if not os.path.exists(SOURCE):
        sys.exit("missing %s, run: python3 design/icon.py" % SOURCE)
    os.makedirs(OUTDIR, exist_ok=True)

    src = Image.open(SOURCE).convert("RGB")
    if src.size != (1024, 1024):
        sys.exit("source is %dx%d, expected 1024x1024" % src.size)

    # Importing the geometry from icon.py stops the test restating a layout, but
    # it does not stop the test measuring a PNG that predates the parameters it
    # just imported. Re-render and compare pixels. The render is deterministic,
    # so this is an equality, not a tolerance, and it costs about four seconds.
    if src.tobytes() != icon.render(icon.PARAMS).convert("RGB").tobytes():
        sys.exit("design/icon-1024.png is not what icon.py renders today.\n"
                 "The parameters moved and the PNG did not. Run: python3 design/icon.py")

    units = 1024
    g = icon.geometry(icon.PARAMS, units)

    print("Sunlit icon silhouette test")
    print("source   %s  %dx%d" % (SOURCE, src.size[0], src.size[1]))
    print("filter   Lanczos")
    print("bars     arc contrast >= %.1f   sun (contrast >= %.1f or dE >= %.1f) "
          "AND gap >= %.2f on both sides"
          % (CONTRAST_MIN, CONTRAST_MIN, DELTA_E_MIN, GAP_MIN))
    print()
    header = "size  | arc vs background        | sun vs arc                              | verdict"
    print(header)
    print("-" * len(header))

    failures = []
    probes = []
    img29 = None
    for n in SIZES:
        small = src.resize((n, n), Image.LANCZOS)
        small.save(os.path.join(OUTDIR, "icon-%d.png" % n))
        if n == 29:
            img29 = small

        smp = Sampler(small, units)
        arc = test_arc(smp, g)
        sun = test_sun(smp, g)
        ok = arc["pass"] and sun["pass"]
        if not ok:
            failures.append("%d px" % n)
        probes.append((n, arc["worst_at"], arc["n"]))

        print("%-5d | worst %5.2f med %5.2f %s | ratio %4.2f  dE %5.1f  gap %4.2f/%4.2f %s | %s"
              % (n, arc["worst"], arc["median"], "OK " if arc["pass"] else "BAD",
                 sun["contrast"], sun["delta_e"], sun["gap_vs_sun"], sun["gap_vs_arc"],
                 "OK " if sun["pass"] else "BAD",
                 "PASS" if ok else "FAIL"))

    print()
    print("gap a/b is the clear sky knockout around the disc, measured against the")
    print("sun and against the arc. Where the worst arc probe landed, per size:")
    for n, at, cnt in probes:
        print("  %-4d %-16s from %d valid probes" % (n, at, cnt))
    print()

    thr = test_threshold(img29, g, units)
    print("Two tone threshold at 29 px (Otsu at luminance %.3f)" % thr["threshold"])
    print("  sky under the apex stays background : %d of 9 px lit   %s"
          % (thr["hollow_fg"], "OK" if thr["hollow_fg"] == 0 else "BAD"))
    print("  stroke not fill, lit px per column  : median %.1f, max %d (bar <= 4.0)   %s"
          % (thr["fill_median"], thr["fill_max"], "OK" if thr["fill_median"] <= 4.0 else "BAD"))
    peak_ok = thr["peak_x"] is not None and 0.30 <= thr["peak_x"] <= 0.70
    print("  silhouette peak sits at x           : %s of width (bar 0.30 to 0.70)   %s"
          % ("%.3f" % thr["peak_x"] if thr["peak_x"] is not None else "nothing lit",
             "OK" if peak_ok else "BAD"))
    print("  top edge drops toward the left end  : %.1f px (bar >= %.1f)   %s"
          % (thr["drop_left"], thr["drop_needed"],
             "OK" if thr["drop_left"] >= thr["drop_needed"] else "BAD"))
    print("  top edge drops toward the right end : %.1f px (bar >= %.1f)   %s"
          % (thr["drop_right"], thr["drop_needed"],
             "OK" if thr["drop_right"] >= thr["drop_needed"] else "BAD"))
    print("  lit shape spans                     : %.2f of the width (bar >= 0.70)   %s"
          % (thr["span"], "OK" if thr["span"] >= 0.70 else "BAD"))
    print("  the arc owns the top, not the disc  : arc row %s vs disc row %s   %s"
          % (thr["arc_top"], thr["disc_top"], "OK" if thr["apex_is_arc"] else "BAD"))
    print("  reads as an arc, not a blob         : %s" % ("PASS" if thr["pass"] else "FAIL"))
    if not thr["pass"]:
        failures.append("threshold 29")

    print()
    print("wrote %d files to %s" % (len(SIZES) + 2, OUTDIR))
    print()
    if failures:
        print("VERDICT: FAIL at %s" % ", ".join(failures))
        return 1
    print("VERDICT: PASS at every size, 180 down to 29, and the 29 px threshold")
    print("render still reads as an arc.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
