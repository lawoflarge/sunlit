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

# The English now comes from the compiler, so it carries real format specifiers
# such as %@. The translations were written against the earlier Swift-shaped
# source, so they carry \(name) instead. Converting them here, positionally
# against the English, is what keeps a translator's reordering intact: the first
# placeholder in the English becomes %1$@ wherever it lands in the translation.
SWIFT_PLACEHOLDER = re.compile(r"\\\(([A-Za-z0-9_.]+)\)")
FORMAT_PLACEHOLDER = re.compile(r"%(?:\d+\$)?[@a-zA-Z]")


def swift_placeholder_order(text):
    return SWIFT_PLACEHOLDER.findall(text)


def to_format_string(translated, english_names):
    """Rewrite \(name) into %N$@ using the English order as the numbering."""
    if not english_names:
        return translated

    def replace(match):
        name = match.group(1)
        if name not in english_names:
            return match.group(0)
        return "%%%d$@" % (english_names.index(name) + 1)

    return SWIFT_PLACEHOLDER.sub(replace, translated)


def main():
    english = json.loads((I18N / "keys.json").read_text(encoding="utf-8"))
    # The Swift-shaped source the translators worked from, kept so the
    # placeholder NAMES are known and can be numbered in the English order.
    swift_path = I18N / "keys_swift_form.json"
    source_swift = json.loads(swift_path.read_text(encoding="utf-8")) if swift_path.exists() else {}
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

        converted = {}
        for key, value in data.items():
            if key not in english:
                continue
            names = swift_placeholder_order(source_swift.get(key, ""))
            rewritten = to_format_string(value, names)
            converted[key] = rewritten
            # A dropped or added placeholder either shows the reader a literal
            # percent sign or crashes the format at runtime.
            wanted = len(FORMAT_PLACEHOLDER.findall(english[key]))
            got = len(FORMAT_PLACEHOLDER.findall(rewritten))
            if wanted != got:
                problems.append(
                    f"{code}: {key!r} needs {wanted} placeholders, has {got}: {rewritten!r}")
            if SWIFT_PLACEHOLDER.search(rewritten):
                problems.append(
                    f"{code}: {key!r} still carries a Swift interpolation: {rewritten!r}")
            if re.search(r"[–—]", value):
                problems.append(f"{code}: dash punctuation in {key!r}")
        translations[code] = converted

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
