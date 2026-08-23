#!/usr/bin/env python3
"""Extract every localisable key from what the COMPILER produced.

The first version of this script parsed the Swift source text and took each
`defaultValue:` literally. That looked right and shipped a catalogue in which
`ar.aim.value` was the string `\\(azimuth)° az, \\(altitude)° alt`, so the AR
screen displayed those characters to the reader instead of two numbers. Fifty
two of the 584 keys carried an interpolation and every one of them would have
done the same.

The compiler already writes the exact key and the exact format string it will
look up at runtime, into a .stringsdata file per source file. Reading those
cannot disagree with the binary, which is the whole point.

Requires a build first:
  xcodegen generate
  xcodebuild build -project Sunlit.xcodeproj -scheme Sunlit \\
    -destination "generic/platform=iOS" -derivedDataPath build/dd \\
    CODE_SIGNING_ALLOWED=NO
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
DERIVED = ROOT / "build" / "dd"
OUT = ROOT / "scripts" / "i18n" / "keys.json"

# Text("key \(value)") looks up a key that already has the value substituted
# into it, finds nothing, and renders the raw key. It compiles and it is a bug
# in every language.
INTERPOLATED = re.compile(r'\b(?:Text|Label)\(\s*"[^"]*\\\(')


def source_problems():
    problems = []
    for root in [ROOT / "Sources" / "Sunlit", ROOT / "Sources" / "SunlitWidgets"]:
        if not root.exists():
            continue
        for path in sorted(root.rglob("*.swift")):
            if "/Debug/" in str(path) or path.name == "DesignPreview.swift":
                continue
            for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                stripped = line.lstrip()
                if stripped.startswith("//") or stripped.startswith("*"):
                    continue
                if INTERPOLATED.search(line):
                    problems.append(
                        f"{path.relative_to(ROOT)}:{number}: interpolation inside Text or "
                        f"Label ships a raw key\n      {stripped}")
    return problems


def main():
    if not DERIVED.exists():
        print(f"no build at {DERIVED.relative_to(ROOT)}; build first", file=sys.stderr)
        return 2

    keys = {}
    files = 0
    for f in DERIVED.rglob("*.stringsdata"):
        try:
            data = json.loads(f.read_text(encoding="utf-8"))
        except Exception:
            continue
        for table, entries in (data.get("tables") or {}).items():
            if table != "Localizable":
                continue
            files += 1
            for entry in entries:
                key, value = entry.get("key"), entry.get("value")
                if key is not None and value is not None:
                    keys[key] = value

    if not keys:
        print("no keys found; is the build current?", file=sys.stderr)
        return 1

    problems = source_problems()
    bare = sorted(k for k, v in keys.items() if k == v)
    if bare:
        problems.append(
            f"{len(bare)} keys have no English text, so the app shows the key itself: "
            + ", ".join(bare))

    if problems:
        print("LOCALISATION PROBLEMS:\n")
        for p in problems:
            print("  " + p)
        print(f"\n{len(problems)} problems")
        return 1

    OUT.write_text(json.dumps(keys, ensure_ascii=False, indent=2, sort_keys=True),
                   encoding="utf-8")
    interpolated = sum(1 for v in keys.values() if "%" in v)
    print(f"{len(keys)} keys from {files} tables -> {OUT.relative_to(ROOT)}")
    print(f"  {interpolated} carry a format placeholder, taken from the compiler "
          f"rather than reconstructed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
