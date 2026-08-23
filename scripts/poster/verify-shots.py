#!/usr/bin/env python3
"""Prove that ten screenshot sets are actually ten languages.

A previous project in this portfolio uploaded ten localised sets that were
pixel identical, because the app had been launched once and only the poster
overlay text was swapped. The store accepted them and the reviewer did not, so
this compares the shots themselves.

The comparison excludes the top of the frame. The status bar carries a clock
and a battery icon that differ between two runs of the SAME language, so
including it would make every pair look different and prove nothing.
"""
import itertools
import sys
from PIL import Image, ImageChops

STATUS_BAR_HEIGHT = 220     # generous, so no clock digit survives


def below_status_bar(path):
    image = Image.open(path).convert("RGB")
    return image.crop((0, STATUS_BAR_HEIGHT, image.width, image.height))


def main():
    if len(sys.argv) < 4:
        print("usage: verify-shots.py <dir> <lang> <lang> ...", file=sys.stderr)
        return 2
    root, languages = sys.argv[1], sys.argv[2:]
    failures = 0

    for screen in ["sky", "ar", "map", "data"]:
        images = {}
        for lang in languages:
            path = f"{root}/{lang}/{screen}.png"
            try:
                images[lang] = below_status_bar(path)
            except FileNotFoundError:
                print(f"MISSING {path}")
                failures += 1
        identical = []
        for a, b in itertools.combinations(images, 2):
            if images[a].size != images[b].size:
                continue
            diff = ImageChops.difference(images[a], images[b])
            if diff.getbbox() is None:
                identical.append((a, b))
        if identical:
            print(f"FAIL  {screen}: identical below the status bar: {identical}")
            failures += len(identical)
        else:
            print(f"  {screen}: all {len(images)} languages differ")

    if failures:
        print(f"\n{failures} problems: these are not ten languages")
        return 1
    print("\nevery language really is a different capture")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
