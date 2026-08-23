#!/usr/bin/env python3
"""Build the embedded offline city database for Sunlit.

Data source
===========
GeoNames cities15000, every populated place above 15000 inhabitants.
    https://download.geonames.org/export/dump/cities15000.zip

This work is licensed under a Creative Commons Attribution 4.0 License,
see https://creativecommons.org/licenses/by/4.0/
The Data is provided "as is" without warranty or any representation of
accuracy, timeliness or completeness.

    Data source: GeoNames, https://www.geonames.org, CC BY 4.0

That attribution is a licence obligation and is owed in three places: in
Settings inside the app, in the repository README, and on the website. As of
this writing the website carries it and the other two do not exist yet: this
repository has no README and Sources/Sunlit/Features/Settings is still empty.
Neither may ship without it.

Usage
=====
    python3 build.py                    download the dump, write cities.bin
    python3 build.py --input DUMP.txt   use a dump already on disk
    python3 build.py --output PATH      write somewhere else
    python3 build.py --verify           rebuild into a temporary file and
                                        compare it against the committed one

The generated file is committed to the repository because the app has to
build with no network access.

Output format, version 1
========================
All integers are little endian and unaligned. Byte offsets are absolute.
The identical layout is documented at the top of
Sources/SunlitCore/Geo/CityIndex.swift, which reads it.

  header, 48 bytes
    0   magic, the 8 ASCII bytes "SUNCITY1"
    8   u32   format version, currently 1
    12  u32   city count
    16  u32   time zone count
    20  u32   offset of the time zone table
    24  u32   offset of the record table
    28  u32   offset of the name blob
    32  u32   length of the name blob
    36  u32   offset of the key blob
    40  u32   length of the key blob
    44  u32   reserved, zero

  time zone table
    One entry per zone, ordered alphabetically:
      u8    length in bytes
      ...   IANA identifier, ASCII

  record table
    City count records of exactly 24 bytes, sorted by population descending
    and by GeoNames id ascending within equal populations. Search ranking
    therefore falls out of the storage order and costs nothing at runtime.
      0   i32   latitude in units of 1e-5 degrees
      4   i32   longitude in units of 1e-5 degrees
      8   u32   population
      12  i16   elevation in metres
      14  u16   index into the time zone table
      16  2     ISO 3166-1 alpha-2 country code, ASCII
      18  u32   offset of the display name inside the name blob
      22  u8    length of the display name in bytes
      23  u8    reserved, zero

  name blob
    Display names, UTF-8, not terminated. GeoNames field `name`, which keeps
    its diacritics.

  key blob
    The folded search keys, in the same order as the record table, so the
    city a key belongs to is implied by counting. Each key is
      u8    length, with bit 7 set when this is the last key of a city
      ...   the key, ASCII, at most 127 bytes
    A city carries one key when its GeoNames `name` and `asciiname` fold to
    the same thing, and two when they differ. Köln stores "koln", folded from
    the name, and "koeln", folded from the ASCII name "Koeln", so both
    spellings find it. 390 of the 34,106 cities carry two keys.

Search key folding
==================
Both sides of the wire run the same algorithm. `foldedSearchKey` in
CityIndex.swift is the Swift half and must stay identical to `fold` below,
because a query is folded on the device and compared against keys folded
here.

  1. Unicode normalisation form KD.
  2. Lowercase.
  3. Drop every combining mark.
  4. Transliterate the Latin letters that KD does not decompose.
  5. Delete apostrophes and full stops, so "St. John's" and "st johns" fold
     alike. Map anything else that is not an ASCII letter, digit or space to
     a space, so "Baden-Baden" and "baden baden" fold alike.
  6. Collapse runs of whitespace and strip.

What is deliberately not indexed
================================
The `alternatenames` column. It is where GeoNames keeps every other spelling
of a place, but it keeps them without language tags and mixed with
transliteration noise, and folding every entry in it takes the resource to
3,245,149 bytes, past the 3 MB budget. Searching runs against the `name` and
`asciiname` columns only.

The consequence is not the one the phrase "no alternate names" suggests.
GeoNames `name` is frequently the English exonym rather than the local
endonym, so it is the *local* spelling that goes missing: "munich" finds
Munich and "muenchen" does not, "gothenburg" finds Gothenburg and "goteborg"
does not. Measured over a sample of 36 European endonyms, 21 reach nothing
or the wrong place, among them München, Praha, Warszawa, Firenze, Venezia,
Bruxelles, København, Moskva and Athina. The app sells in ten languages, so
this is an open product gap, not a footnote about a file format. Closing it
means indexing part of `alternatenames` and re-arguing the 3 MB budget.
"""

import argparse
import hashlib
import io
import os
import struct
import sys
import tempfile
import unicodedata
import urllib.request
import zipfile

DUMP_URL = "https://download.geonames.org/export/dump/cities15000.zip"
MAGIC = b"SUNCITY1"
FORMAT_VERSION = 1
HEADER_SIZE = 48
RECORD_SIZE = 24
MAX_KEY_BYTES = 127

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_OUTPUT = os.path.join(HERE, "cities.bin")

# Latin letters with no compatibility decomposition. Without this table a
# Danish or Icelandic name folds to a hole rather than to a letter.
TRANSLITERATIONS = {
    "ø": "o",   # o with stroke
    "æ": "ae",  # ae
    "œ": "oe",  # oe
    "ß": "ss",  # sharp s
    "đ": "d",   # d with stroke
    "ð": "d",   # eth
    "þ": "th",  # thorn
    "ł": "l",   # l with stroke
    "ı": "i",   # dotless i
    "ħ": "h",   # h with stroke
    "ŋ": "n",   # eng
    "ŧ": "t",   # t with stroke
    "ĸ": "k",   # kra
    "ſ": "s",   # long s
}

# Deleted rather than turned into a space, so that a name written with an
# apostrophe and the same name typed without one fold to the same key.
DELETED = "'‘’ʼʻ´`."


def fold(text):
    """Fold a name into its ASCII search key. See the module docstring."""
    out = []
    for ch in unicodedata.normalize("NFKD", text).lower():
        if unicodedata.category(ch).startswith("M"):
            continue
        if ch in DELETED:
            continue
        mapped = TRANSLITERATIONS.get(ch)
        if mapped is not None:
            out.append(mapped)
            continue
        if ch.isascii() and (ch.isalpha() or ch.isdigit()):
            out.append(ch)
        else:
            out.append(" ")
    return " ".join("".join(out).split())


def load_dump(path):
    """Return the raw tab separated lines, downloading the dump if needed."""
    if path:
        with open(path, encoding="utf-8") as handle:
            return handle.read().splitlines()
    sys.stderr.write("downloading %s\n" % DUMP_URL)
    with urllib.request.urlopen(DUMP_URL) as response:
        payload = response.read()
    with zipfile.ZipFile(io.BytesIO(payload)) as archive:
        raw = archive.read("cities15000.txt")
    return raw.decode("utf-8").splitlines()


def parse(lines):
    """Turn dump lines into the tuples the writer needs, sorted for ranking."""
    cities = []
    for line in lines:
        if not line:
            continue
        column = line.split("\t")
        geoname_id = int(column[0])
        name = column[1]
        ascii_name = column[2]
        latitude = float(column[4])
        longitude = float(column[5])
        country = column[8]
        population = int(column[14]) if column[14] else 0
        # The elevation column is blank for most entries. GeoNames fills the
        # dem column from a digital elevation model in that case, and uses
        # -9999 there to mean it has no value at all.
        raw_elevation = column[15] if column[15] else column[16]
        try:
            elevation = int(raw_elevation)
        except ValueError:
            elevation = 0
        if elevation <= -9999:
            elevation = 0
        elevation = max(-32768, min(32767, elevation))
        timezone = column[17]

        keys = []
        for candidate in (name, ascii_name):
            key = fold(candidate)
            if key and key not in keys:
                keys.append(key)
        if not keys:
            # Nothing typeable to search for. Every row in the August 2026
            # dump yields a key, so this is a guard, not a live path.
            continue

        cities.append(
            (
                -population,
                geoname_id,
                name,
                country,
                latitude,
                longitude,
                elevation,
                population,
                timezone,
                keys,
            )
        )

    cities.sort(key=lambda item: (item[0], item[1]))
    return cities


def encode(cities):
    """Serialise the parsed cities into the version 1 binary format."""
    zones = sorted({city[8] for city in cities})
    zone_index = {zone: number for number, zone in enumerate(zones)}
    if len(zones) > 0xFFFF:
        raise ValueError("more time zones than the u16 index can address")

    zone_table = bytearray()
    for zone in zones:
        encoded = zone.encode("utf-8")
        if len(encoded) > 255:
            raise ValueError("time zone identifier too long: %s" % zone)
        zone_table.append(len(encoded))
        zone_table += encoded

    name_blob = bytearray()
    key_blob = bytearray()
    records = bytearray()

    for city in cities:
        (
            _,
            _,
            name,
            country,
            latitude,
            longitude,
            elevation,
            population,
            timezone,
            keys,
        ) = city

        encoded_name = name.encode("utf-8")
        if len(encoded_name) > 255:
            encoded_name = encoded_name[:255]
            # Cut on a character boundary rather than mid sequence.
            while encoded_name and (encoded_name[-1] & 0xC0) == 0x80:
                encoded_name = encoded_name[:-1]
        name_offset = len(name_blob)
        name_blob += encoded_name

        for position, key in enumerate(keys):
            encoded_key = key.encode("ascii")
            if len(encoded_key) > MAX_KEY_BYTES:
                encoded_key = encoded_key[:MAX_KEY_BYTES]
            marker = 0x80 if position == len(keys) - 1 else 0x00
            key_blob.append(len(encoded_key) | marker)
            key_blob += encoded_key

        country_bytes = country.encode("ascii")[:2].ljust(2, b" ")
        records += struct.pack(
            "<iiIhH2sIBB",
            int(round(latitude * 1e5)),
            int(round(longitude * 1e5)),
            population,
            elevation,
            zone_index[timezone],
            country_bytes,
            name_offset,
            len(encoded_name),
            0,
        )

    assert len(records) == RECORD_SIZE * len(cities), "record stride drifted"

    zone_offset = HEADER_SIZE
    record_offset = zone_offset + len(zone_table)
    name_offset_base = record_offset + len(records)
    key_offset_base = name_offset_base + len(name_blob)

    header = struct.pack(
        "<8sIIIIIIIIII",
        MAGIC,
        FORMAT_VERSION,
        len(cities),
        len(zones),
        zone_offset,
        record_offset,
        name_offset_base,
        len(name_blob),
        key_offset_base,
        len(key_blob),
        0,
    )
    assert len(header) == HEADER_SIZE, "header size drifted"

    return bytes(header + zone_table + records + name_blob + key_blob)


def report(blob, cities):
    zones = len({city[8] for city in cities})
    keys = sum(len(city[9]) for city in cities)
    sys.stderr.write(
        "cities %d, time zones %d, search keys %d\n" % (len(cities), zones, keys)
    )
    sys.stderr.write(
        "bytes %d (%.2f MB), sha256 %s\n"
        % (len(blob), len(blob) / 1048576.0, hashlib.sha256(blob).hexdigest())
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--input", help="a cities15000.txt already on disk")
    parser.add_argument("--output", default=DEFAULT_OUTPUT)
    parser.add_argument(
        "--verify",
        action="store_true",
        help="rebuild and compare against the committed file instead of writing",
    )
    arguments = parser.parse_args()

    cities = parse(load_dump(arguments.input))
    blob = encode(cities)
    report(blob, cities)

    if arguments.verify:
        with open(arguments.output, "rb") as handle:
            committed = handle.read()
        if committed == blob:
            sys.stderr.write("verify: the committed file matches a fresh build\n")
            return 0
        sys.stderr.write(
            "verify: MISMATCH, committed %d bytes, fresh %d bytes\n"
            % (len(committed), len(blob))
        )
        return 1

    directory = os.path.dirname(os.path.abspath(arguments.output))
    handle, temporary = tempfile.mkstemp(dir=directory)
    with os.fdopen(handle, "wb") as sink:
        sink.write(blob)
    os.replace(temporary, arguments.output)
    # mkstemp creates the file 0600. The resource is checked in and read by
    # every build, so give it the mode the rest of the tree has.
    os.chmod(arguments.output, 0o644)
    sys.stderr.write("wrote %s\n" % arguments.output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
