# Sunlit Implementation Master Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement each milestone plan
> task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `Sunlit: Sun & Moon Tracker` to App Store review: a free iPhone app that
computes sun, moon, and Milky Way positions entirely on device, with one 9.99 EUR
non-consumable unlocking any date, saved places, moon, Milky Way, terrain, eclipses,
widgets, notifications, and export.

**Architecture:** A pure-Foundation Swift core (`SunlitCore`) holds every calculation and
is provable without a simulator. A SwiftUI app layers four views over it, each reading
the same `DayReport` and `SkyMoment` values. A WidgetKit extension reuses the core
verbatim. Nothing calls the network at runtime.

**Tech Stack:** Swift 5, SwiftUI, XcodeGen, StoreKit 2, WidgetKit, ARKit-free AR through
AVFoundation plus CoreMotion, MapKit, CoreLocation, XCTest.

---

## Why this is split into milestone plans

The spec covers subsystems that are independently testable and independently valuable:
the computational core, the interface, the sensor layer, monetisation, localisation, and
the store pipeline. A single plan would be unreviewable. Each milestone below has its
own plan document, written immediately before that milestone is executed, and each ends
with software that runs and is tested.

## Milestones

| # | Milestone | Plan document | Ends when |
|---|---|---|---|
| M1 | `SunlitCore` astronomy | `2026-08-23-sunlit-m1-core-astronomy.md` | Every reference fixture in spec 4.1 passes |
| M2 | `SunlitCore` solar, terrain, geo | `...-m2-core-derived.md` | UV, irradiance, twilight, horizon, cities tested |
| M3 | App shell, design system, Sky view | `...-m3-shell-sky.md` | App runs, Sky view renders across all sky states |
| M4 | Sensors, AR view, Map view | `...-m4-ar-map.md` | Heading fusion measured, AR overlay aligned, map rays correct |
| M5 | Data view, places, export | `...-m5-data-places.md` | Tables, calendar, eclipses, CSV and image export |
| M6 | StoreKit, paywall, ProGate, widgets | `...-m6-store-widgets.md` | Every gate has a proven caller, widgets render |
| M7 | Ten languages | `...-m7-localisation.md` | Ten languages verified inside the built bundle |
| M8 | Icon, posters, screenshots | `...-m8-assets.md` | 8 shots per language, silhouette test passed |
| M9 | Website | `...-m9-web.md` | Live on Vercel, verified anonymously |
| M10 | App Store Connect submission | `...-m10-submission.md` | Review submission reports `WAITING_FOR_REVIEW` |

## Dependency order

M1 gates everything. M2 depends on M1. M3 depends on M2. M4 and M5 can run in parallel
after M3. M6 depends on M5. M7 depends on all interface text existing, so after M6. M8
depends on M7, because every screenshot is captured in its own language. M9 is
independent and can run any time, but must be live before M10. M10 depends on all.

## Standing rules for every milestone

These are not suggestions. Each one is a rejection or a wasted day already paid for in
this portfolio.

1. **`SunlitCore` imports Foundation and nothing else.** Verified by a grep gate in CI.
2. **Prove logic with `swiftc`, not the simulator.** A thousand cases in a second beats a
   simulator that hangs for a day. The driver file must be named `main.swift`.
3. **Measure the before state.** A green test after a fix proves nothing unless the same
   test was red before it. No fix lands without its failing test having been observed.
4. **Every paid promise gets a test proving a caller exists**, asserting on behaviour, not
   on the presence of a symbol.
5. **Read `meta.associatedErrors` on every App Store Connect 409.** The top-level message
   is generic and has misdirected this portfolio repeatedly.
6. **Never claim a UI state without having seen it.** Screenshot or it did not happen.
7. **Commit at every green test.** Small commits, real messages.
8. **`TARGETED_DEVICE_FAMILY = 1` is forced on the xcodebuild command line** as well as in
   `project.yml`.
9. **No dash punctuation in any user-facing copy**, in any language, anywhere.
10. **Localised strings use literal keys.** Interpolation goes through
    `String(localized:)` with a named key, never `Text("key \(value)")`.

## Acceptance for the whole programme

The ten criteria in section 13 of the spec. Each is evidence-backed, and the evidence
lands in `docs/verification/`.
