#!/usr/bin/env python3
"""The silhouette test.

An icon is judged at 29 points in Settings and at 60 on the home screen, not at
1024 in a design tool. This portfolio has shipped an icon that looked fine at
full size and turned into an unreadable blob in the list, so the test is
mandatory and it measures rather than asserts.

Three questions, each answered with a number:

  1. Is the arc still distinguishable from the sky behind it?
  2. Is the sun still distinguishable from the arc it sits on?
  3. At the smallest size, reduced to two tones, is the shape still an ARC,
     which is to say does a horizontal cut below the apex find two separate
     limbs, or has it filled in into a blob?
"""
import os
import sys
from PIL import Image

SIZES = [180, 120, 87, 80, 60, 40, 29]
MIN_CONTRAST = 1.6   # WCAG-style ratio; below this two shapes stop reading apart


def luminance(pixel):
    """WCAG relative luminance."""
    def channel(c):
        c = c / 255.0
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = pixel[:3]
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)


def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    lighter, darker = max(la, lb), min(la, lb)
    return (lighter + 0.05) / (darker + 0.05)


def classify(image):
    """Split the pixels into sky, arc and sun by hue and brightness.

    The three tones are far enough apart that a simple rule separates them, and
    a simple rule is what should be used: a clustering step would hide the very
    failure this test exists to find, because it would happily find three
    clusters in mush.
    """
    w, h = image.size
    sky, arc, sun = [], [], []
    for y in range(h):
        for x in range(w):
            r, g, b = image.getpixel((x, y))[:3]
            if r > 200 and g > 190 and b > 170:
                arc.append((x, y, (r, g, b)))
            elif r > 190 and 120 < g < 210 and b < 120:
                sun.append((x, y, (r, g, b)))
            else:
                sky.append((x, y, (r, g, b)))
    return sky, arc, sun


def mean(pixels):
    if not pixels:
        return None
    n = len(pixels)
    return (sum(p[2][0] for p in pixels) / n,
            sum(p[2][1] for p in pixels) / n,
            sum(p[2][2] for p in pixels) / n)


def arc_is_still_an_arc(image):
    """Reduce to two tones and look for two separate limbs on a horizontal cut.

    A real arc, cut anywhere below its apex and above its feet, crosses the line
    twice. A blob crosses it once. That difference is the whole question.
    """
    w, h = image.size
    grey = image.convert("L")
    values = list(grey.getdata())
    threshold = (max(values) + min(values)) / 2
    bitmap = [[1 if grey.getpixel((x, y)) > threshold else 0 for x in range(w)]
              for y in range(h)]

    # Cut across the lower third of the motif, where the two limbs are furthest
    # apart and the sun is not in the way.
    best = 0
    for y in range(int(h * 0.55), int(h * 0.72)):
        runs, previous = 0, 0
        for x in range(w):
            if bitmap[y][x] == 1 and previous == 0:
                runs += 1
            previous = bitmap[y][x]
        best = max(best, runs)
    return best, bitmap


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    source = Image.open(os.path.join(here, "icon-1024.png")).convert("RGB")
    outdir = os.path.join(here, "silhouette")
    os.makedirs(outdir, exist_ok=True)

    failures = 0
    print(f"{'size':>5}  {'arc vs sky':>11}  {'sun vs arc':>11}  verdict")
    print("-" * 48)
    for size in SIZES:
        small = source.resize((size, size), Image.LANCZOS)
        small.save(os.path.join(outdir, f"icon-{size}.png"))

        sky, arc, sun = classify(small)
        sky_mean, arc_mean, sun_mean = mean(sky), mean(arc), mean(sun)

        if arc_mean is None or sun_mean is None:
            print(f"{size:>5}  {'GONE':>11}  {'GONE':>11}  FAIL: a shape disappeared entirely")
            failures += 1
            continue

        arc_vs_sky = contrast(arc_mean, sky_mean)
        sun_vs_arc = contrast(sun_mean, arc_mean)
        ok = arc_vs_sky >= MIN_CONTRAST and sun_vs_arc >= MIN_CONTRAST
        if not ok:
            failures += 1
        print(f"{size:>5}  {arc_vs_sky:>11.2f}  {sun_vs_arc:>11.2f}  {'pass' if ok else 'FAIL'}"
              f"   (arc {len(arc)} px, sun {len(sun)} px)")

    smallest = source.resize((29, 29), Image.LANCZOS)
    runs, bitmap = arc_is_still_an_arc(smallest)
    print()
    print(f"two-tone shape test at 29 px: best horizontal cut crosses {runs} separate limbs")
    for row in bitmap:
        print("   " + "".join("#" if v else "." for v in row))
    if runs >= 2:
        print("verdict: still reads as an arc, not a blob")
    else:
        print("verdict: FAIL, the shape has filled in and reads as a blob")
        failures += 1

    print()
    if failures:
        print(f"SILHOUETTE TEST FAILED: {failures} problems")
        sys.exit(1)
    print("SILHOUETTE TEST PASSED at every size")


if __name__ == "__main__":
    main()
