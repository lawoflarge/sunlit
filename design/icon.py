#!/usr/bin/env python3
"""Render the Sunlit app icon: a sun with rays riding an arc over a horizon.

Renders design/icon-1024.png and mirrors it into design/AppIcon.appiconset/ and
into the app's asset catalogue.

The icon has to survive being 29 points wide, so it carries one idea and no
more: a sun on a path that meets the horizon at both ends.

Three decisions are load bearing.

  The sun sits ON the arc. Its centre is computed from the same parametric
  ellipse the arc is drawn from, so the two cannot drift apart. An earlier
  version had the disc floating beside a broken curve, which reads as a
  rendering fault rather than as a design.

  The arc meets the horizon at both ends, symmetrically. An arc that runs off
  one side and stops in a stub on the other reads as clipped.

  The rays are short, blunt and few. At 29 points the whole disc is nine pixels
  across, so a long thin ray becomes a smear that closes the gap between the sun
  and the arc and turns three shapes into one blob. The silhouette test measures
  this rather than taking it on trust.

Everything is drawn at four times the final size and resampled down, because
PIL's arc has no antialiasing of its own.
"""
import math
import os
import shutil
from PIL import Image, ImageDraw

SIZE = 1024
SUPERSAMPLE = 4
S = SIZE * SUPERSAMPLE

# The Adaptive Sky palette at golden hour, which is the moment the app is for.
SKY_TOP = (16, 23, 54)        # deep twilight navy
SKY_MID = (74, 51, 92)        # the violet the gradient passes through
SKY_HORIZON = (242, 160, 60)  # the glow sitting on the horizon
GROUND_TOP = (24, 28, 52)
GROUND = (10, 13, 30)
ARC = (253, 243, 224)         # warm cream, the instrument line
SUN = (255, 176, 32)          # the accent, #FFB020

# The apex lands at HORIZON_Y minus ARC_B and the feet at HORIZON_Y, so the
# motif spans that band. Keeping the midpoint of the band near the middle of the
# canvas is what stops the icon reading as bottom heavy, which is why these
# three are chosen together rather than tuned one at a time.
HORIZON_Y = 0.735
ARC_A = 0.355
ARC_B = 0.400
ARC_WIDTH = 0.050
HORIZON_WIDTH = 0.011

SUN_THETA = 52.0              # where on the arc the sun sits, degrees from east
SUN_RADIUS = 0.070
HALO_RADIUS = 0.215

RAY_COUNT = 8
RAY_INNER = 0.096             # gap between the disc edge and where a ray starts
RAY_OUTER = 0.145
RAY_WIDTH = 0.021
RAY_PHASE = 22.5              # degrees, so no ray lies flat along the arc


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def sky_gradient(draw, horizon_px):
    """Night at the top, the glow at the horizon, a base below it.

    Two segments rather than one: a single linear ramp from navy to amber passes
    through a muddy brown, and routing it through the violet keeps the hue
    moving the way a real sky does.
    """
    for y in range(horizon_px):
        t = y / max(1, horizon_px - 1)
        if t < 0.55:
            colour = lerp(SKY_TOP, SKY_MID, t / 0.55)
        else:
            colour = lerp(SKY_MID, SKY_HORIZON, (t - 0.55) / 0.45)
        draw.line([(0, y), (S, y)], fill=colour)

    # A base, not a void. A flat black band under a lit sky reads as a missing
    # layer; a slight falloff reads as ground in shadow.
    depth = S - horizon_px
    for y in range(horizon_px, S):
        t = (y - horizon_px) / max(1, depth - 1)
        draw.line([(0, y), (S, y)], fill=lerp(GROUND_TOP, GROUND, t))


def arc_point(theta_degrees, cx, cy, a, b):
    """A point on the arc. The sun and the curve both read from this, which is
    what guarantees they stay together."""
    t = math.radians(theta_degrees)
    return cx + a * math.cos(t), cy - b * math.sin(t)


def render(path):
    image = Image.new("RGB", (S, S), SKY_TOP)
    draw = ImageDraw.Draw(image)

    horizon_px = int(S * HORIZON_Y)
    sky_gradient(draw, horizon_px)

    cx, cy = S / 2.0, float(horizon_px)
    a, b = S * ARC_A, S * ARC_B
    stroke = int(S * ARC_WIDTH)

    # The horizon first, so the arc's feet sit on top of it.
    hw = int(S * HORIZON_WIDTH)
    draw.rectangle([0, horizon_px - hw // 2, S, horizon_px + hw // 2], fill=ARC)

    # PIL measures angles clockwise from three o'clock, so the upper half of the
    # ellipse runs from 180 to 360.
    draw.arc([cx - a, cy - b, cx + a, cy + b], 180, 360, fill=ARC, width=stroke)

    sx, sy = arc_point(SUN_THETA, cx, cy, a, b)
    sun_r = S * SUN_RADIUS
    halo_r = S * HALO_RADIUS

    # The halo is composited rather than drawn, so it fades into whatever the
    # gradient happens to be behind it instead of banding against a guess.
    halo = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    halo_draw = ImageDraw.Draw(halo)
    steps = 48
    for i in range(steps, 0, -1):
        r = halo_r * i / steps
        alpha = int(120 * (1.0 - i / steps) ** 2)
        halo_draw.ellipse([sx - r, sy - r, sx + r, sy + r], fill=SUN + (alpha,))
    image = Image.alpha_composite(image.convert("RGBA"), halo).convert("RGB")
    draw = ImageDraw.Draw(image)

    # Rays before the disc, so the disc covers their inner ends and they read as
    # coming from behind it rather than as spokes stuck onto its edge.
    inner = S * RAY_INNER
    outer = S * RAY_OUTER
    ray_w = int(S * RAY_WIDTH)
    for i in range(RAY_COUNT):
        angle = math.radians(RAY_PHASE + i * 360.0 / RAY_COUNT)
        dx, dy = math.cos(angle), -math.sin(angle)
        draw.line([(sx + dx * inner, sy + dy * inner),
                   (sx + dx * outer, sy + dy * outer)], fill=SUN, width=ray_w)
        # PIL draws square ends, which at this scale read as pixel artefacts.
        for t in (inner, outer):
            ex, ey = sx + dx * t, sy + dy * t
            r2 = ray_w / 2.0
            draw.ellipse([ex - r2, ey - r2, ex + r2, ey + r2], fill=SUN)

    draw.ellipse([sx - sun_r, sy - sun_r, sx + sun_r, sy + sun_r], fill=SUN)

    image = image.resize((SIZE, SIZE), Image.LANCZOS)
    image.save(path, "PNG")
    return image


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.join(here, "icon-1024.png")
    img = render(out)

    # An icon with an alpha channel is rejected at upload, so this is checked
    # here rather than discovered by App Store Connect.
    assert img.mode == "RGB", "icon must be opaque"
    assert img.size == (SIZE, SIZE)
    print("wrote", out, img.size, "mode", img.mode)

    for target in [
        os.path.join(here, "AppIcon.appiconset", "icon-1024.png"),
        os.path.join(here, "..", "Sources", "Sunlit", "Resources",
                     "Assets.xcassets", "AppIcon.appiconset", "icon-1024.png"),
    ]:
        os.makedirs(os.path.dirname(target), exist_ok=True)
        shutil.copyfile(out, target)
        print("copied to", os.path.normpath(target))
