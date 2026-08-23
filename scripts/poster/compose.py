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


# Fonts in preference order. The first one that can draw every character of the
# string is used, which is decided per string rather than per language: a
# Japanese poster may still contain "Sunlit" and "AR", and a Polish one contains
# characters Helvetica happens to have while Japanese ones it does not.
FONT_CANDIDATES = [
    "/System/Library/Fonts/Helvetica.ttc",
    "/System/Library/Fonts/Hiragino Sans GB.ttc",
    "/System/Library/Fonts/AppleSDGothicNeo.ttc",
    "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
]

_TOFU_CACHE = {}


def _renders(font, character):
    """Whether a font has a real glyph for a character.

    U+FFFF is a permanent noncharacter, so whatever a font draws for it is that
    font's missing-glyph box. A character that renders identically to it has no
    glyph. This is done by rendering rather than by parsing the font, because it
    needs no extra library and it measures the thing that actually reaches the
    poster.
    """
    key = (font.path, font.size)
    if key not in _TOFU_CACHE:
        image = Image.new("L", (96, 96), 0)
        ImageDraw.Draw(image).text((8, 8), "\uFFFF", font=font, fill=255)
        _TOFU_CACHE[key] = image.tobytes()
    image = Image.new("L", (96, 96), 0)
    ImageDraw.Draw(image).text((8, 8), character, font=font, fill=255)
    return image.tobytes() != _TOFU_CACHE[key]


def font(size, text=""):
    """A font that can actually draw `text` at `size`.

    This exists because the first version of this file picked Helvetica and the
    Japanese posters came out as eight screens of empty rectangles. Helvetica
    has none of the fourteen Japanese characters in the copy, and nothing in the
    pipeline noticed: the images were the right size, the layout was right, and
    the text was tofu. Nothing but looking at it, or this check, catches that.
    """
    needed = {c for c in text if not c.isspace()}
    for path in FONT_CANDIDATES:
        if not os.path.exists(path):
            continue
        try:
            candidate = ImageFont.truetype(path, size)
        except OSError:
            continue
        if all(_renders(candidate, c) for c in needed):
            return candidate

    missing_report = []
    for path in FONT_CANDIDATES:
        if not os.path.exists(path):
            continue
        try:
            candidate = ImageFont.truetype(path, size)
        except OSError:
            continue
        missing = [c for c in needed if not _renders(candidate, c)]
        missing_report.append(f"{os.path.basename(path)} cannot draw {''.join(sorted(missing))}")
    raise RuntimeError(
        "no font on this machine can draw every character of "
        f"{text!r}. Tried: " + "; ".join(missing_report))


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
    """Break a string into lines that fit.

    Two strategies, because Japanese has no spaces. Breaking on whitespace turns
    a Japanese headline into one unbreakable word that runs off the canvas,
    which is exactly what the first version did: the text rendered, the image
    was the right size, and half the sentence was outside the frame.

    Japanese is broken between characters instead, which is what Japanese
    typesetting does anyway. The only refinement is that a line may not START
    with a character that is forbidden at the head of a line, the small kana and
    the closing punctuation, which is the kinsoku rule a reader would notice
    being broken.
    """
    if " " not in text.strip():
        return _wrap_by_character(draw, text, typeface, max_width)

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


# Characters that may not begin a line in Japanese typesetting.
NO_LINE_START = "\u3001\u3002\uff0c\uff0e\uff09\u300d\u300f\u3041\u3043\u3045\u3047\u3049\u3063\u3083\u3085\u3087\u3093\u30a1\u30a3\u30a5\u30a7\u30a9\u30c3\u30e3\u30e5\u30e7\u30fc\u30f3"


def _wrap_by_character(draw, text, typeface, max_width):
    lines, current = [], ""
    for character in text:
        trial = current + character
        if draw.textlength(trial, font=typeface) <= max_width or not current:
            current = trial
            continue
        # Do not start the next line with a character that cannot begin one.
        if character in NO_LINE_START:
            current = trial
            continue
        lines.append(current)
        current = character
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
    available = WIDTH - 2 * MARGIN
    while size > 40:
        typeface = font(size, headline)
        lines = wrap(draw, headline, typeface, available)
        widest = max((draw.textlength(line, font=typeface) for line in lines), default=0)
        if len(lines) <= 3 and widest <= available:
            break
        size -= 4
    typeface = font(size, headline)
    lines = wrap(draw, headline, typeface, WIDTH - 2 * MARGIN)

    y = HEADLINE_TOP
    for line in lines:
        draw.text((MARGIN, y), line, font=typeface, fill=CREAM)
        y += int(size * 1.18)

    if subhead:
        sub_face = font(46, subhead)
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
        typeface = font(50, caption)
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


def _text_overflows_margin(path, probe=8):
    """Report rows where bright pixels sit inside the margin.

    A last line of defence over the whole composition rather than over one
    string: it catches a headline that ran off the canvas, a caption that was
    measured with a different font from the one it was drawn with, and anything
    else that puts ink where the margin should be. Only the top third is
    examined, because the device frame legitimately fills the margin lower down.
    """
    image = Image.open(path).convert("L")
    rows = []
    for y in range(0, int(HEIGHT * 0.33), probe):
        for x in list(range(0, 6)) + list(range(WIDTH - 6, WIDTH)):
            if image.getpixel((x, y)) > 170:
                rows.append(y)
                break
    return rows[:5]


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
        overflow = _text_overflows_margin(out)
        if overflow:
            print(f"  {index:02d}  {os.path.basename(out)}  TEXT REACHES THE EDGE at rows {overflow}",
                  file=sys.stderr)
            return 1
        print(f"  {index:02d}  {os.path.basename(out)}  {size[0]}x{size[1]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
