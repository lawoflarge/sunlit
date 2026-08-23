#!/bin/bash
# Prove SunlitCore logic without a simulator.
#
# `xcrun simctl` has hung for a full day in this portfolio while a swiftc run
# proved 1500 cases in one second. Every numerical claim about the core is
# settled here first, and only then in XCTest.
#
# The driver file must be named main.swift. Swift only allows top-level
# statements in a file with that exact name; any other name fails with
# "expressions are not allowed at the top level".
#
# Usage: scripts/prove.sh <driver.swift>
set -euo pipefail
cd "$(dirname "$0")/.."

DRIVER="${1:?usage: scripts/prove.sh <driver.swift>}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cp "$DRIVER" "$WORK/main.swift"

# SunlitCore imports Foundation and nothing else, which is what makes this
# possible. Guard that invariant here rather than discovering it when the
# compile fails.
BAD=$(grep -rhoE '^import [A-Za-z]+' Sources/SunlitCore --include='*.swift' | sort -u | grep -v '^import Foundation$' || true)
if [ -n "$BAD" ]; then
  echo "SunlitCore must import Foundation only. Found:" >&2
  echo "$BAD" >&2
  exit 1
fi

# Concatenate rather than link: no module, no framework, just the sources.
find Sources/SunlitCore -name '*.swift' -print0 | xargs -0 -I{} cp {} "$WORK/"

swiftc -O -o "$WORK/prove" "$WORK"/*.swift 2>&1 | grep -vE 'warning:|^ *\^|^ *~|note:' || true
if [ ! -x "$WORK/prove" ]; then
  echo "compile failed" >&2
  swiftc -O -o "$WORK/prove" "$WORK"/*.swift
  exit 1
fi
"$WORK/prove"
