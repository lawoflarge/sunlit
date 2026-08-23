#!/usr/bin/env python3
"""Compose App Store posters from raw simulator screenshots.

The layout is the one the owner chose: shots one to three carry a benefit
headline over a device frame on a branded background, shots four onward are full
bleed. The reason is that the App Store search result shows only the first two,
so those two have to tell the story alone, while anyone who scrolls past three
is already interested and is better served by seeing the real product large.

Output is 1290 x 2796, the iPhone 6.9 inch size, which is the only size Apple
still requires for a new iPhone-only submission.

Every string is passed in per locale. Nothing here is written in English and
translated later, because a headline that has to fit a fixed box is a design
constraint and not a translation job.
"""
import json
import os
import sys
from PIL import Image, ImageDraw, ImageFont

WIDTH, HEIGHT = 1290, 2796

# The Adaptive Sky identity, matched to the app and the icon.
SKY_TOP = (16, 23, 54)
SKY_MID = (74, 51, 92)
SKY_LOW = (176, 106, 66)
SUN = (255, 176, 32)
CREAM = (253, 243, 224)

MARGIN = 88
HEADLINE_TOP = 150
DEVICE_TOP = 620
DEVICE_CORNER = 68
DEVICE_BORDER = 10


def font(size, weight="Bold"):
    """A system font at a real weight.

    SF Pro is not readable by Pillow from its .ttc on every machine, so this
    walks a short list and reports which one it used rather than silently
    falling back to the bitmap default, which would make every poster look
    broken in a way that is easy to miss at thumbnail size.
    """
    candidates = [
        f"/System/Library/Fonts/SFNS{'Display' if weight == 'Bold' else 'Text'}.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/Library/Fonts/Arial Unicode.ttf",
        "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
    ]
    for path in candidates:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                continue
    raise RuntimeError("no usable font found; posters would render in the "
                       "bitmap default and look broken at thumbnail size")


def gradient(height_fraction_top=0.0):
    """The background, the same ramp the app paints at golden hour."""
    image = Image.new("RGB", (WIDTH, HEIGHT))
    draw = ImageDraw.Draw(image)
    for y in range(HEIGHT):
        t = y / (HEIGHT - 1)
        if t < 0.6:
            u = t / 0.6
            colour = tuple(round(SKY_TOP[i] + (SKY_MID[i] - SKY_TOP[i]) * u) for i in range(3))
        else:
            u = (t - 0.6) / 0.4
            colour = tuple(round(SKY_MID[i] + (SKY_LOW[i] - SKY_MID[i]) * u) for i in range(3))
        draw.line([(0, y), (WIDTH, y)], fill=colour)
    return image


def wrap(draw, text, typeface, max_width):
    words = text.split()
    lines, current = [], ""
    for word in words:
        trial = (current + " " + word).strip()
        if draw.textlength(trial, font=typeface) <= max_width or not current:
            current = trial
        else:
            lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def headline_poster(shot_path, headline, subhead, out_path):
    """Shots one to three: headline above, device below."""
    image = gradient()
    draw = ImageDraw.Draw(image)

    # The headline shrinks until it fits three lines. A fixed size that works in
    # English overflows in German and Polish, which is the failure this loop
    # exists to prevent, and it is checked rather than hoped for.
    size = 104
    while size > 54:
        typeface = font(size)
        lines = wrap(draw, headline, typeface, WIDTH - 2 * MARGIN)
        if len(lines) <= 3:
            break
        size -= 4
    typeface = font(size)
    lines = wrap(draw, headline, typeface, WIDTH - 2 * MARGIN)

    y = HEADLINE_TOP
    for line in lines:
        draw.text((MARGIN, y), line, font=typeface, fill=CREAM)
        y += int(size * 1.18)

    if subhead:
        sub_face = font(46, "Regular")
        for line in wrap(draw, subhead, sub_face, WIDTH - 2 * MARGIN)[:2]:
            draw.text((MARGIN, y + 18), line, font=sub_face, fill=SUN)
            y += 58

    shot = Image.open(shot_path).convert("RGB")
    device_width = WIDTH - 2 * MARGIN - 2 * DEVICE_BORDER
    scale = device_width / shot.width
    device_height = int(shot.height * scale)
    shot = shot.resize((device_width, device_height), Image.LANCZOS)

    top = max(DEVICE_TOP, y + 70)
    # The device may run off the bottom, which is fine and intentional: a screen
    # that continues past the edge reads as a real phone rather than as a sticker.
    frame = Image.new("RGB", (device_width + 2 * DEVICE_BORDER,
                              min(device_height, HEIGHT - top) + 2 * DEVICE_BORDER), CREAM)
    frame.paste(shot.crop((0, 0, device_width, min(device_height, HEIGHT - top))),
                (DEVICE_BORDER, DEVICE_BORDER))

    rounded = Image.new("L", frame.size, 0)
    ImageDraw.Draw(rounded).rounded_rectangle([0, 0, frame.size[0] - 1, frame.size[1] - 1],
                                              radius=DEVICE_CORNER, fill=255)
    image.paste(frame, (MARGIN, top), rounded)

    image.save(out_path, "PNG")
    return image.size


def full_bleed_poster(shot_path, caption, out_path):
    """Shots four onward: the product, edge to edge, with one small caption."""
    shot = Image.open(shot_path).convert("RGB")
    scale = max(WIDTH / shot.width, HEIGHT / shot.height)
    resized = shot.resize((round(shot.width * scale), round(shot.height * scale)), Image.LANCZOS)
    left = (resized.width - WIDTH) // 2
    top = (resized.height - HEIGHT) // 2
    image = resized.crop((left, top, left + WIDTH, top + HEIGHT))

    if caption:
        draw = ImageDraw.Draw(image, "RGBA")
        typeface = font(50)
        lines = wrap(draw, caption, typeface, WIDTH - 2 * MARGIN)[:2]
        block = len(lines) * 64 + 56
        # A scrim rather than a solid bar: the screenshot underneath is the point,
        # and a solid bar would hide the part of it the caption is about.
        draw.rectangle([0, HEIGHT - block - 40, WIDTH, HEIGHT], fill=(7, 11, 24, 190))
        y = HEIGHT - block - 4
        for line in lines:
            draw.text((MARGIN, y), line, font=typeface, fill=CREAM)
            y += 64

    image.save(out_path, "PNG")
    return image.size


def main():
    if len(sys.argv) != 4:
        print("usage: compose.py <plan.json> <shots-dir> <out-dir>", file=sys.stderr)
        return 2
    plan_path, shots_dir, out_dir = sys.argv[1:4]
    plan = json.loads(open(plan_path, encoding="utf-8").read())
    os.makedirs(out_dir, exist_ok=True)

    for index, entry in enumerate(plan["posters"], start=1):
        shot = os.path.join(shots_dir, entry["shot"])
        if not os.path.exists(shot):
            print(f"MISSING {shot}", file=sys.stderr)
            return 1
        out = os.path.join(out_dir, f"{index:02d}.png")
        if index <= 3:
            size = headline_poster(shot, entry["headline"], entry.get("subhead", ""), out)
        else:
            size = full_bleed_poster(shot, entry.get("caption", ""), out)
        assert size == (WIDTH, HEIGHT), f"{out} is {size}, expected {(WIDTH, HEIGHT)}"
        print(f"  {index:02d}  {os.path.basename(out)}  {size[0]}x{size[1]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
