#!/usr/bin/env python3
"""
Sunlit app icon: a sun arc over a horizon line, on the Adaptive Sky gradient.

Renders design/icon-1024.png and mirrors it into design/AppIcon.appiconset/.

That appiconset is not yet reachable from the build. project.yml sets
ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon, but the repo contains no .xcassets
catalog, so actool never sees this directory and the app compiles with no icon,
which fails App Store validation. Installing it, by making the app target carry
an Assets.xcassets that holds a copy of this AppIcon.appiconset, belongs to the
target that owns Sources/Sunlit and project.yml, not to this script.

Composition, in one sentence: a bold light warm arc springs from the horizon on
the left, crests above centre, and lands on the horizon on the right, with the
sun as a filled amber disc riding the arc at 45 degrees of elevation on the
ascending side, so the icon reads as a path with the sun still climbing it.

Three decisions worth keeping:

  The arc is an exact semicircle centred on the horizon. arc_left_x, arc_right_x
  and arc_apex_y are chosen so half chord equals sagitta, which is what makes
  the shape read as a sun path rather than as a generic arch.

  The sun sits low on the ascending branch, at sun_t 0.25, which is 45 degrees
  of elevation. Higher up the arc the disc would poke above the apex and the
  silhouette would lose its dome, which is the thing that survives 29 points.

  A clear sky gap is knocked out of the arc around the disc. Amber on a light
  warm tone is only about 1.5:1 in luminance and nothing lighter than #FFB020
  reaches 3:1 against it, so the disc is separated from the arc by hue and by
  that gap rather than by brightness. silhouette-test.py has a pass rule for
  each of the three, gap included, so shrinking sun_gap to nothing fails the
  test rather than passing it quietly.

Every dimension in PARAMS is a fraction of the canvas side, so the icon renders
identically at any size. The render is deterministic: two runs produce the same
bytes.

Pillow is required. macOS ships Pillow with the Command Line Tools interpreter
at /usr/bin/python3, and this script re-executes itself there if the interpreter
it was started with has no Pillow.

Usage:
    python3 design/icon.py [--size 1024]
"""

import argparse
import json
import math
import os
import shutil
import sys

try:
    from PIL import Image, ImageDraw
except ImportError:  # pragma: no cover - environment fallback
    _FALLBACK = "/usr/bin/python3"
    if sys.executable != _FALLBACK and os.path.exists(_FALLBACK):
        os.execv(_FALLBACK, [_FALLBACK] + sys.argv)
    sys.exit("Pillow is required. Install it with: python3 -m pip install Pillow")

HERE = os.path.dirname(os.path.abspath(__file__))

# ---------------------------------------------------------------------------
# Parameters. All positions and lengths are fractions of the canvas side.
# ---------------------------------------------------------------------------

PARAMS = {
    "size": 1024,
    "supersample": 4,

    # Adaptive Sky at golden hour: deep navy overhead, violet through the
    # middle, amber at the horizon and below it.
    "sky_stops": [
        (0.00, "#1B2340"),
        (0.30, "#35304F"),
        (0.62, "#6B4A6E"),
        (0.82, "#B06A4E"),
        (1.00, "#FFB020"),
    ],

    # Horizon: one crisp hairline, full bleed, in the lower third.
    "horizon_y": 0.665,
    "horizon_w": 0.0117,

    # The arc.
    "arc_left_x": 0.100,
    "arc_right_x": 0.900,
    "arc_apex_y": 0.265,
    "arc_w": 0.0566,

    # Ink colour shared by the arc and the horizon hairline.
    "line_color": "#FFE7BE",

    # The sun. sun_t runs 0 at the left end of the arc to 1 at the right end.
    "sun_t": 0.25,
    "sun_r": 0.0980,
    "sun_color": "#FFB020",
    "sun_gap": 0.0260,

    # Subtle warm halo. Drawn under the arc so it never closes the gap.
    "halo_color": "#FFCE6A",
    "halo_alpha": 0.16,
    "halo_sigma": 1.5,      # in units of sun_r
    "halo_res": 512,        # sampling grid for the smooth radial falloff
}


# ---------------------------------------------------------------------------
# Geometry
# ---------------------------------------------------------------------------

def geometry(p, side):
    """Arc, sun and horizon geometry in pixels for a canvas of the given side."""
    x0 = p["arc_left_x"] * side
    x1 = p["arc_right_x"] * side
    yh = p["horizon_y"] * side
    ya = p["arc_apex_y"] * side

    half_chord = (x1 - x0) / 2.0
    sagitta = yh - ya
    if sagitta <= 0:
        raise ValueError("arc_apex_y must sit above horizon_y")
    radius = (half_chord ** 2 + sagitta ** 2) / (2.0 * sagitta)
    cx = (x0 + x1) / 2.0
    cy = ya + radius

    # Screen convention: angles in degrees, 0 at 3 o'clock, growing clockwise
    # because y points down. 270 is the top of the circle.
    a_start = math.degrees(math.atan2(yh - cy, x0 - cx)) % 360.0
    a_end = math.degrees(math.atan2(yh - cy, x1 - cx)) % 360.0
    if a_end <= a_start:
        a_end += 360.0

    g = {
        "side": side,
        "cx": cx, "cy": cy, "radius": radius,
        "a_start": a_start, "a_end": a_end,
        "arc_len": radius * math.radians(a_end - a_start),
        "arc_w": p["arc_w"] * side,
        "horizon_y": yh,
        "horizon_w": p["horizon_w"] * side,
        "r_sun": p["sun_r"] * side,
        "gap": p["sun_gap"] * side,
        "sun_t": p["sun_t"],
    }
    g["r_hole"] = g["r_sun"] + g["gap"]
    g["sun"] = arc_point(g, p["sun_t"])
    g["apex"] = (cx, cy - radius)
    return g


def arc_point(g, t):
    """Point on the arc centreline. t = 0 at the left end, 1 at the right end."""
    ang = math.radians(g["a_start"] + t * (g["a_end"] - g["a_start"]))
    return (g["cx"] + g["radius"] * math.cos(ang),
            g["cy"] + g["radius"] * math.sin(ang))


def arc_normal(g, t):
    """Unit normal at t, pointing outward, away from the circle centre."""
    x, y = arc_point(g, t)
    return ((x - g["cx"]) / g["radius"], (y - g["cy"]) / g["radius"])


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

def rgb(hex_str):
    h = hex_str.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


def _lerp(a, b, f):
    return tuple(int(round(a[i] + (b[i] - a[i]) * f)) for i in range(3))


def sky_layer(side, stops):
    """Vertical gradient, built one row at a time and stretched sideways."""
    cooked = [(pos, rgb(col)) for pos, col in stops]
    column = Image.new("RGB", (1, side))
    px = column.load()
    for y in range(side):
        f = (y + 0.5) / side
        for i in range(len(cooked) - 1):
            p0, c0 = cooked[i]
            p1, c1 = cooked[i + 1]
            if f <= p1 or i == len(cooked) - 2:
                span = max(p1 - p0, 1e-9)
                px[0, y] = _lerp(c0, c1, min(max((f - p0) / span, 0.0), 1.0))
                break
    return column.resize((side, side), Image.NEAREST).convert("RGBA")


def halo_layer(side, g, p):
    """Radially symmetric warm glow, sampled coarsely then smoothed up."""
    n = p["halo_res"]
    sx, sy = g["sun"]
    r = g["r_sun"]
    a0 = p["halo_alpha"]
    sigma = p["halo_sigma"] * r

    mask = Image.new("L", (n, n))
    mpx = mask.load()
    for j in range(n):
        y = (j + 0.5) * side / n
        dy2 = (y - sy) ** 2
        for i in range(n):
            x = (i + 0.5) * side / n
            d = math.sqrt((x - sx) ** 2 + dy2)
            a = a0 if d <= r else a0 * math.exp(-((d - r) / sigma) ** 2)
            mpx[i, j] = int(round(a * 255.0))

    layer = Image.new("RGBA", (side, side), rgb(p["halo_color"]) + (0,))
    layer.putalpha(mask.resize((side, side), Image.BICUBIC))
    return layer


def ink_layer(side, g, p):
    """Horizon hairline and arc, with the clear sky gap punched out."""
    layer = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    ink = rgb(p["line_color"]) + (255,)

    half = g["horizon_w"] / 2.0
    d.rectangle([0, g["horizon_y"] - half, side, g["horizon_y"] + half], fill=ink)

    # The arc is stamped as overlapping discs, which gives an exact round cap at
    # both ends and leaves no doubt about which side of the path the width falls.
    brush = g["arc_w"] / 2.0
    steps = max(2, int(math.ceil(g["arc_len"] / (brush / 4.0))))
    for k in range(steps + 1):
        x, y = arc_point(g, k / steps)
        d.ellipse([x - brush, y - brush, x + brush, y + brush], fill=ink)

    sx, sy = g["sun"]
    rh = g["r_hole"]
    d.ellipse([sx - rh, sy - rh, sx + rh, sy + rh], fill=(0, 0, 0, 0))
    return layer


def render(p):
    """Render the icon and return an opaque RGB image of side p['size']."""
    side = p["size"] * p["supersample"]
    g = geometry(p, side)

    img = sky_layer(side, p["sky_stops"])
    img = Image.alpha_composite(img, halo_layer(side, g, p))
    img = Image.alpha_composite(img, ink_layer(side, g, p))

    sx, sy = g["sun"]
    rs = g["r_sun"]
    ImageDraw.Draw(img).ellipse([sx - rs, sy - rs, sx + rs, sy + rs],
                                fill=rgb(p["sun_color"]) + (255,))

    return img.resize((p["size"], p["size"]), Image.LANCZOS).convert("RGB")


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

CONTENTS_JSON = {
    "images": [
        {
            "filename": "icon-1024.png",
            "idiom": "universal",
            "platform": "ios",
            "size": "1024x1024",
        }
    ],
    "info": {"author": "xcode", "version": 1},
}


def write_appiconset(png_path):
    out = os.path.join(HERE, "AppIcon.appiconset")
    os.makedirs(out, exist_ok=True)
    shutil.copyfile(png_path, os.path.join(out, "icon-1024.png"))
    with open(os.path.join(out, "Contents.json"), "w") as fh:
        json.dump(CONTENTS_JSON, fh, indent=2)
        fh.write("\n")
    return out


def main():
    ap = argparse.ArgumentParser(description="Render the Sunlit app icon.")
    ap.add_argument("--size", type=int, default=PARAMS["size"])
    ap.add_argument("--out", default=None,
                    help="write somewhere other than design/icon-<size>.png. "
                         "A run with --out never touches the shipped appiconset.")
    args = ap.parse_args()

    p = dict(PARAMS, size=args.size)
    out_path = args.out or os.path.join(HERE, "icon-%d.png" % args.size)

    render(p).save(out_path, optimize=True)

    with Image.open(out_path) as check:
        w, h = check.size
        mode = check.mode
    if (w, h) != (args.size, args.size):
        sys.exit("render produced %dx%d, expected %dx%d" % (w, h, args.size, args.size))
    if mode != "RGB":
        sys.exit("render produced mode %s, expected RGB with no alpha" % mode)

    print("wrote %s  %dx%d  %s  %d bytes"
          % (out_path, w, h, mode, os.path.getsize(out_path)))

    # Only the canonical 1024 render is mirrored into the appiconset. A run with
    # --out is a preview or an experiment, and mirroring it would silently
    # replace the shipped asset with whatever was being tried out.
    if args.size == 1024 and args.out is None:
        print("wrote %s" % write_appiconset(out_path))


if __name__ == "__main__":
    main()
