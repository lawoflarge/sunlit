#!/usr/bin/env python3
"""Assemble Localizable.xcstrings from the English keys and the nine translations.

The catalogue is generated rather than hand edited because it is a machine
format: one wrong nesting level and Xcode silently ships the English default in
every language while the build stays green, which is exactly the failure this
project cannot afford after selling the app in ten storefronts.

Every entry is written with state "translated". A "needs_review" entry is
treated by Xcode as untranslated and falls back, so leaving one in would ship an
English string to a market that paid for its own.
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
I18N = ROOT / "scripts" / "i18n"
OUT = ROOT / "Sources" / "Sunlit" / "Resources" / "Localizable.xcstrings"

LANGUAGES = ["de", "fr", "it", "es", "es-MX", "nl", "pl", "ja", "pt-BR"]
PLACEHOLDER = re.compile(r"\\\(([a-zA-Z0-9_.]+)\)")


def main():
    english = json.loads((I18N / "keys.json").read_text(encoding="utf-8"))
    problems = []
    translations = {}

    for code in LANGUAGES:
        path = I18N / f"{code}.json"
        if not path.exists():
            problems.append(f"{code}: file missing")
            continue
        data = json.loads(path.read_text(encoding="utf-8"))
        translations[code] = data

        missing = set(english) - set(data)
        extra = set(data) - set(english)
        if missing:
            problems.append(f"{code}: {len(missing)} keys missing, first {sorted(missing)[:3]}")
        if extra:
            problems.append(f"{code}: {len(extra)} keys not in the source, first {sorted(extra)[:3]}")

        for key, value in data.items():
            if key not in english:
                continue
            # An interpolation that is dropped or renamed shows the reader a
            # literal backslash-paren in a shipped build, or crashes the format.
            if PLACEHOLDER.findall(english[key]) != PLACEHOLDER.findall(value):
                problems.append(
                    f"{code}: placeholders differ on {key!r}: "
                    f"{PLACEHOLDER.findall(english[key])} vs {PLACEHOLDER.findall(value)}")
            if re.search(r"[–—]", value):
                problems.append(f"{code}: dash punctuation in {key!r}")

    if problems:
        print(f"{len(problems)} problems, catalogue NOT written:\n")
        for p in problems[:40]:
            print("  " + p)
        if len(problems) > 40:
            print(f"  ... and {len(problems) - 40} more")
        return 1

    strings = {}
    for key, source in sorted(english.items()):
        localisations = {
            "en": {"stringUnit": {"state": "translated", "value": source}}
        }
        for code in LANGUAGES:
            localisations[code] = {
                "stringUnit": {"state": "translated", "value": translations[code][key]}
            }
        strings[key] = {"extractionState": "manual", "localizations": localisations}

    catalogue = {"sourceLanguage": "en", "strings": strings, "version": "1.0"}
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(catalogue, ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"{len(strings)} keys x {len(LANGUAGES) + 1} languages -> "
          f"{OUT.relative_to(ROOT)} ({OUT.stat().st_size // 1024} KB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
