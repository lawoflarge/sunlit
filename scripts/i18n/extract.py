#!/usr/bin/env python3
"""Extract every localisable key from the Swift sources.

Xcode can generate a string catalogue at build time, but it only sees what the
compiler sees, which means a key introduced by a helper it cannot constant fold
never appears and ships as a raw key. Extracting explicitly, and failing loudly
on the patterns that are known to break, is what stops that.

Two patterns are ERRORS rather than keys, and both have shipped raw keys in this
portfolio before:

    Text("greeting \\(name)")     looks up the literal key "greeting %@" and
                                  will not find it
    Text(someVariable)            has no literal key at all

Interpolation must go through String(localized:) with an explicit named key.
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCES = [ROOT / "Sources" / "Sunlit", ROOT / "Sources" / "SunlitWidgets"]

# String(localized: "key", defaultValue: "English text")
LOCALIZED = re.compile(
    r'String\(\s*localized:\s*"([^"\\]+)"\s*,\s*defaultValue:\s*"((?:[^"\\]|\\.)*)"')
# Text("key") and Label("key", systemImage:)
TEXT = re.compile(r'\b(?:Text|Label)\(\s*"([^"\\]+)"')
# The one shape that is provably broken. Text("key \(value)") asks the catalogue
# for a key that has already had the value substituted into it, finds nothing,
# and renders the raw key. It compiles, it looks right in English if the key
# happens to be English, and it is a bug in every other language.
INTERPOLATED = re.compile(r'\b(?:Text|Label)\(\s*"[^"]*\\\(')

# Text(variable) is NOT checked, and that is deliberate rather than an omission.
# A reusable component that takes a label and renders Text(label) is correct when
# its caller passes a localised string, and there is no way to tell those apart
# by reading one line. What IS checkable is the caller, so the gate below looks
# for English copy sitting in a literal instead.


def main():
    keys = {}
    problems = []

    for root in SOURCES:
        if not root.exists():
            continue
        for path in sorted(root.rglob("*.swift")):
            # Developer tooling, not shipped copy. DesignPreview renders the
            # palette at nine solar altitudes for a human to judge; its labels
            # are never seen by a user and would pad the catalogue with two
            # English sentences that no translator should be asked to handle.
            if "/Debug/" in str(path) or path.name == "DesignPreview.swift":
                continue
            text = path.read_text(encoding="utf-8")
            for line_number, line in enumerate(text.splitlines(), start=1):
                # Comments describe the rule as often as code breaks it, and a
                # gate that fires on its own documentation gets switched off.
                stripped = line.lstrip()
                if stripped.startswith("//") or stripped.startswith("///") or stripped.startswith("*"):
                    continue
                if INTERPOLATED.search(line):
                    problems.append(
                        f"{path.relative_to(ROOT)}:{line_number}: interpolation inside "
                        f"Text or Label ships a raw key. Use String(localized:) with a "
                        f"named key.\n      {line.strip()}")

            for key, default in LOCALIZED.findall(text):
                keys.setdefault(key, default)
            for key in TEXT.findall(text):
                # A key with a space in it is almost always English copy passed
                # straight to Text, which works in English and nowhere else.
                keys.setdefault(key, key)

    if problems:
        print("LOCALISATION PROBLEMS:\n")
        for problem in problems:
            print("  " + problem)
        print(f"\n{len(problems)} problems")
        return 1

    out = ROOT / "scripts" / "i18n" / "keys.json"
    out.write_text(json.dumps(keys, ensure_ascii=False, indent=2, sort_keys=True),
                   encoding="utf-8")
    print(f"{len(keys)} keys extracted to {out.relative_to(ROOT)}")

    literal_english = [k for k in keys if " " in k]
    if literal_english:
        print(f"\n{len(literal_english)} keys look like English copy rather than "
              f"identifiers, which works in English and nowhere else:")
        for k in sorted(literal_english)[:20]:
            print(f"  {k!r}")
        if len(literal_english) > 20:
            print(f"  ... and {len(literal_english) - 20} more")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
