# Sunlit: Sun & Moon Tracker

Design specification, 23 August 2026.

Status: approved by the owner on 23 August 2026. This document is the contract
for the implementation plan that follows it.

---

## 1. What this is

An iPhone app that answers one question precisely: where is the sun, where is
the moon, and where will they be. It answers it for any date, at any place, on
a device with no network connection, and it shows its working.

The reference product is Sun Seeker: Tracker & Compass (ozPDA / Ajnaware,
id330247123). Sunlit must contain every capability that product ships, and must
beat it on interface quality, on breadth, and on honesty about measurement
error.

### 1.1 The reference product, measured

| Property | Sun Seeker, 10 July 2026 |
|---|---|
| Price | 12.99 EUR up front, no in-app purchases |
| Size | 52.5 MB |
| Languages | English, French, German, Japanese, Spanish |
| Category | Navigation |
| Rating | 4.8 from 1,700+ ratings |
| Version | 8.1.2 |

Its feature set: hourly sun direction intervals, equinox and solstice paths,
sunrise and sunset, civil / nautical / astronomical twilight, shadowed periods,
UV index, solar irradiance, golden and blue hour, eclipses, sun event
notifications, a widget, a watch app, a flat compass view with position and
elevation, a 3D augmented reality camera overlay showing current position and
annual path, a map view with direction arrows and hourly elevations, date and
location selection against 40,000+ offline cities with online map search,
screenshot saving to an album, and export of photos and tabulations.

### 1.2 Where it is weak

Drawn from published review analysis, August 2026:

1. **Compass accuracy is the top complaint theme**, and it lands directly on the
   AR view, which is the product's hero feature.
2. **Scouting distant locations is awkward.** Current location is handled well,
   remote locations are not.
3. **No moon.** Competitors that carry the moon (Sun Surveyor, PhotoPills,
   Ephemeris) take the astrophotography audience outright.
4. **Maintenance posture.** No meaningful feature movement while competitors
   iterate.
5. **12.99 EUR before you have seen anything.** Every install is a blind bet.

### 1.3 How Sunlit answers each

1. Sensor fusion through CoreMotion device attitude in the true-north reference
   frame rather than raw magnetic heading, plus a permanently visible accuracy
   figure and a calibration prompt driven by `CLHeading.headingAccuracy`.
   Stating the uncertainty is the feature.
2. Location and date live in a global header that governs every view. Search
   runs against an embedded city list offline, against MapKit when there is a
   network, and against a dropped map pin always.
3. Full moon support: phase, illuminated fraction, distance, perigee and apogee,
   rise and set with parallax, path in AR and on the map. Plus the Milky Way
   galactic centre with a real visibility window.
4. Not applicable at launch. Recorded here as the standard to hold later.
5. Free to install. Today, at your current location, in all four views, costs
   nothing.

---

## 2. Product decisions, locked

| Decision | Value |
|---|---|
| Name | `Sunlit: Sun & Moon Tracker` (26 of 30 characters) |
| Fallback names, in order | `Helio: Sun Path & Golden Hour`, `Azimuth: Sun, Moon & Sky`, `Solstice: Sun & Moon Compass` |
| Bundle id | `com.levinschwab.sunlit` |
| Scope | Sun, moon, and Milky Way |
| Devices | iPhone only, `TARGETED_DEVICE_FAMILY = 1` |
| Deployment target | iOS 17.0 |
| Monetisation | One non-consumable, `com.levinschwab.sunlit.pro`, 9.99 EUR |
| Free tier | Today, at the current location, in all four views |
| Companions | Widgets in 1.0. Watch app deferred to 1.1 |
| Categories | Primary Navigation, secondary Photo & Video |
| Languages | en, de, fr, it, es, es-MX, nl, pl, ja, pt-BR |
| Visual direction | Adaptive Sky |
| Screenshots | Hybrid: 1 to 3 headline plus frame, 4 to 8 full bleed |
| Icon | Sun arc over a horizon line |
| Site | `sunlit-app.vercel.app` |
| Repository | `github.com/lawoflarge/sunlit`, public |
| Release | Submit autonomously, automatic release after approval |

`TARGETED_DEVICE_FAMILY` is forced on the `xcodebuild` command line as well as
in `project.yml`, because xcodegen has silently dropped it in this portfolio
before and the resulting iPad-capable binary is what four apps were judged on
under guideline 5.6.

---

## 3. Layout

```
sunlit/
  project.yml                 xcodegen
  Sources/
    SunlitCore/               pure Swift. Foundation only. No UI, no UIKit,
      Astronomy/              no CoreLocation, no MapKit. Fully testable
        JulianDay.swift       calendar to JD, delta T
        SolarPositionSPA.swift  NREL SPA
        SPATables.swift       L, B, R periodic terms; nutation table
        MoonPosition.swift    Meeus 47, truncated ELP-2000/82
        MoonTables.swift      tables 47.A and 47.B
        Nutation.swift        nutation in longitude and obliquity
        Refraction.swift      Bennett, with pressure and temperature
        Coordinates.swift     equatorial, horizontal, galactic, precession
        RiseSet.swift         numerical event solver
        Eclipse.swift         local circumstances from topocentric separation
        MilkyWay.swift        galactic centre and galactic plane
      Solar/
        UVIndex.swift         clear-sky model, ozone climatology
        Irradiance.swift      clear-sky GHI, DNI, DHI
        Twilight.swift        civil, nautical, astronomical
        GoldenHour.swift      golden and blue hour bounds
      Terrain/
        HorizonProfile.swift  measured skyline, 36 sectors, interpolated
        Shadow.swift          shadow length and direction, obstruction periods
      Geo/
        Place.swift           coordinate, elevation, time zone, name
        CityIndex.swift       embedded offline city search
        Declination.swift     magnetic declination, WMM
      Model/
        SkyMoment.swift       everything about one instant at one place
        DayReport.swift       everything about one day at one place
    Sunlit/                   the app, SwiftUI
      Design/                 Adaptive Sky palette, type, components
      Features/
        Sky/                  home
        AR/                   camera overlay
        Map/                  MapKit
        Data/                 tables, calendar, export
        Locations/            search, saved places
        Paywall/              StoreKit 2
        Settings/
      Sensors/                heading fusion, motion, location
      Store/                  ProGate, entitlement
    SunlitWidgets/            WidgetKit, home and lock screen
  Tests/
    SunlitCoreTests/          reference-value suites
  metadata/                   asc canonical metadata, ten storefronts
  scripts/                    build, capture, poster, ship
  web/                        marketing, privacy, support
  design/                     icon, poster templates
  docs/
```

`SunlitCore` importing nothing but Foundation is a hard rule, not a preference.
It is what lets `swiftc Sources/SunlitCore/**/*.swift main.swift` prove a
thousand cases in a second when the simulator is hanging.

---

## 4. The computational core

Every number the app shows is computed on the device. No API is called at
runtime for any astronomical or solar quantity.

### 4.1 Methods and required accuracy

| Quantity | Method | Accuracy target |
|---|---|---|
| Solar position | NREL SPA (Reda and Andreas, NREL/TP-560-34302) | 0.0003 degrees, years -2000 to 6000 |
| Delta T | Espenak and Meeus polynomial series | within 1 second for 1900 to 2100 |
| Nutation | IAU 1980 series, 63 terms | 0.001 arcsecond |
| Refraction | Bennett, corrected for pressure and temperature | 0.1 arcminute at altitudes above 5 degrees |
| Lunar position | Meeus chapter 47, truncated ELP-2000/82 | 10 arcseconds in longitude, 4 arcseconds in latitude |
| Lunar distance | same series | 5 km |
| Rise, set, twilight | numerical solver, see 4.2 | 1 second |
| Eclipse local circumstances | topocentric separation, see 4.4 | 1 minute on contact times |
| Milky Way | Sgr A* precessed to date | 0.01 degrees |

### 4.2 The event solver

Meeus's interpolation method for rise and set degrades near the poles and around
grazing events. Sunlit uses a numerical solver instead:

1. Sample the altitude function over the local day at 60 second steps.
2. Detect sign changes against the target altitude `h0`.
3. Bisect each bracket to 1 second.
4. Report polar day and polar night explicitly when no crossing exists, rather
   than emitting a bogus time.

Target altitudes:

| Event | `h0` |
|---|---|
| Sunrise, sunset | -0.8333 degrees (refraction plus semidiameter) |
| Civil twilight | -6 degrees |
| Nautical twilight | -12 degrees |
| Astronomical twilight | -18 degrees |
| Golden hour bounds | +6 degrees and -4 degrees |
| Blue hour bounds | -4 degrees and -6 degrees |
| Moonrise, moonset | `0.7275 * parallax - 34 arcminutes`, computed per instant |
| Local sunrise over measured terrain | `horizonProfile(azimuth)` |

Roughly 1,440 SPA evaluations per day per place. SPA is cheap; this is measured
in the performance suite and must stay under 30 ms for a full day report on an
iPhone 12.

### 4.3 Derived solar quantities

**UV index** is a clear-sky model, not a measurement, and is labelled as such in
the interface and in the store listing.

```
UVI = 12.50 * mu0^2.42 * (omega / 300)^-1.23 * f_altitude * f_distance
mu0        = cos(solar zenith angle), clamped at 0
omega      = total column ozone in Dobson units, from a latitude and
             season climatology table embedded in the app
f_altitude = 1 + 0.06 * elevation_km
f_distance = (1 AU / earth-sun distance)^2
```

**Irradiance** is a clear-sky model, labelled as such.

```
air mass  Kasten and Young
GHI       Haurwitz clear-sky, 1098 * cos(z) * exp(-0.059 / cos(z))
DNI, DHI  split from GHI by the Erbs correlation
```

Both carry a visible "clear sky model" caption everywhere they appear. This
matters: promising a measurement the app does not take is the failure mode that
has cost this portfolio rejections before.

### 4.4 Eclipses

Sunlit does not implement Besselian elements. It does not need to, because it
already computes topocentric positions of both bodies with parallax.

**Solar eclipses.** For each new moon in the window, minimise the topocentric
angular separation of the two centres as seen from the observer. Compare the
separation against the sum and difference of the apparent semidiameters:

```
sun semidiameter    959.63 arcseconds / distance in AU
moon semidiameter   arcsin(1737.4 km / topocentric distance in km)

separation > sun_sd + moon_sd            no eclipse at this place
separation < sun_sd - moon_sd            annular
separation < moon_sd - sun_sd            total
otherwise                                partial
```

First contact, maximum, and last contact come from bisecting the separation
function against the relevant threshold. Obscuration follows from the standard
circular-overlap area formula. Accuracy is bounded by the lunar ephemeris at
roughly 10 arcseconds, which puts contact times inside a minute.

**Lunar eclipses.** Umbral and penumbral radii at the lunar distance, compared
against the moon's separation from the antisolar point. Local visibility is
exactly "is the moon above the horizon at that instant", which the core already
answers.

**Validation.** Both are tested against the NASA Five Millennium Canon of Solar
Eclipses and the corresponding lunar catalogue, as frozen fixtures in the
repository. A minimum of 12 solar and 8 lunar events spanning 1990 to 2050,
across several observer locations including at least one grazing case.

### 4.5 Milky Way

Galactic centre, Sgr A*, J2000: right ascension 266.41681 degrees, declination
-29.00775 degrees, precessed to date. The galactic plane is drawn as a curve by
transforming galactic longitude at galactic latitude zero into equatorial and
then horizontal coordinates.

Visibility window at a place on a night:

```
galactic centre altitude > 10 degrees
sun altitude < -18 degrees
moon below horizon, or illuminated fraction below 0.3
```

The window is reported as an interval with a quality grade, and the limiting
factor is named when there is no window.

### 4.6 Terrain and obstruction

The measured horizon profile is 36 azimuth sectors of 10 degrees, linearly
interpolated, each holding an apparent altitude in degrees. It can be filled in
three ways: swept with the camera in the AR view by aiming at the skyline,
entered by hand as a table, or left flat at 0 degrees.

With a profile present:

- true local sunrise and sunset use `horizonProfile(azimuth)` as `h0`
- obstruction periods are the intervals where sun altitude is below the profile
  while above the astronomical horizon
- the difference between flat-horizon and measured times is shown, because that
  difference is the whole point

Shadow length for an object of height `h` at solar altitude `alpha > 0` is
`h / tan(alpha)`, cast toward `azimuth + 180 degrees`.

### 4.7 Places, time zones, and offline behaviour

- Current location: CoreLocation, and the device time zone, which is correct.
- Embedded city list: GeoNames `cities15000`, roughly 25,000 entries, each with
  coordinate, elevation, and IANA time zone. **GeoNames is CC BY 4.0. The
  attribution is mandatory** and appears in Settings, in the repository README,
  and in `web/`. This obligation is not optional and is not to be dropped for
  convenience.
- Text search: the embedded list always, MapKit local search additionally when a
  network exists.
- Dropped map pin: coordinate is exact offline. Time zone resolves through
  CLGeocoder when there is a network; without one the app falls back to the
  device time zone and says so on screen rather than silently guessing.

Magnetic declination for the compass comes from an embedded World Magnetic Model
coefficient set, so true north is available with no network.

---

## 5. Interface

### 5.1 Adaptive Sky

The background is not decoration. It is a readout. A vertical gradient whose
stops are interpolated continuously from the actual solar altitude at the
selected instant and place.

| Solar altitude | Palette |
|---|---|
| below -18 | deep night, `#070B18` to `#0D1430` |
| -18 to -6 | astronomical to civil, navy into violet |
| -6 to 0 | civil twilight, violet into rose |
| 0 to 6 | golden, rose into amber |
| 6 to 30 | morning to day, amber into sky blue |
| above 30 | full day, `#2E7FD4` to `#9FD3F5` |

Above it sits one instrument layer and nothing else: hairlines at 1 physical
pixel, tabular figures, no drop shadows, no glass, no gradients on controls.

- Sun accent `#FFB020`
- Moon accent `#8FB8FF`
- Milky Way accent `#C9A6FF`
- Instrument line, foreground at 55 percent opacity
- Type: SF Pro Display for headings, SF Pro Text with
  `monospacedDigit` for every number that changes

Every foreground colour is checked for at least 4.5:1 contrast against the
darkest and the lightest sky the gradient can produce. A palette that reads at
noon and fails at midnight is a bug, and this portfolio has shipped that bug
before at 1.86:1.

### 5.2 The four views

A global header carries place and date and governs all four.

**Sky.** The home screen. The day's arc drawn across the adaptive gradient, with
sun and moon at their true positions on it. Beneath it a time scrubber; dragging
it moves the entire screen through the day, gradient included. Key figures in a
tabular block: azimuth, altitude, UV, irradiance, and the next event with a
countdown. Below that the day's event rail: first light, sunrise, golden hour,
solar noon, golden hour, sunset, last light.

**AR.** Live camera with the sun and moon paths overlaid, hour marks along each,
and the summer solstice, winter solstice, and equinox paths as reference curves.
The Milky Way galactic plane appears when the selected instant is dark enough.
The horizon sweep lives here. A persistent accuracy chip shows the current
heading uncertainty in degrees and turns amber when calibration is needed.

**Map.** MapKit. Sunrise and sunset direction rays from the pin, the moon's rays
in its own accent, the day's path over the terrain, and a shadow projection for
an object of adjustable height. Tap anywhere to move the pin; the whole app
follows.

**Data.** The tabulation. All three twilights, solar noon, day length and its
change from yesterday, the moon phase calendar, upcoming eclipses with local
circumstances, the annual altitude curve, and export to CSV and image.

### 5.3 Non-negotiable interface rules

These come from rejections this portfolio has already absorbed.

1. Every screen scrolls. No `VStack` with `maxHeight: .infinity` holding a
   primary control that can be pushed off the canvas. App Review tests with
   large text, and the single button below the fold is exactly what took down
   two apps in one batch.
2. Verified at the largest Dynamic Type size on the smallest supported device,
   by driving the simulator, not by reading the code.
3. Every interactive target is at least 44 by 44 points, measured after any
   scaling transform, not before.
4. Localised strings are declared with literal keys. `Text("key \(value)")`
   looks up `key %@` and quietly ships the raw key at green build. Interpolated
   strings go through explicit `String(localized:)` with a named key.
5. Accessibility labels on every control and every value readout.

---

## 6. Monetisation

One non-consumable, `com.levinschwab.sunlit.pro`, 9.99 EUR, StoreKit 2.

**Free, permanently:** the current location and today's date, in all four views.
Sun position, compass, AR sun path, sunrise, sunset, all three twilights, golden
and blue hour, solar noon, day length, shadow length, and UV and irradiance for
today.

**Pro:**

| Capability | Gate identifier |
|---|---|
| Any date, past or future | `anyDate` |
| Saved places beyond the current location | `savedPlaces` |
| Moon: phase, path, rise, set, calendar | `moon` |
| Milky Way: galactic centre, plane, windows | `milkyWay` |
| Annual path overlay, solstice and equinox curves | `annualPaths` |
| Measured horizon profile and obstruction periods | `terrain` |
| Eclipses with local circumstances | `eclipses` |
| Widgets | `widgets` |
| Event notifications | `notifications` |
| CSV and image export | `export` |

`ProGate` exposes these as named capabilities. **Every one of them has a test
that proves a caller exists.** Three apps in one batch of this portfolio shipped
a paid promise with no caller; a search for the capability name alone is not
sufficient evidence, because indirection through a gate helper hides callers
from a naive grep. The test asserts on behaviour, not on the presence of a
symbol.

The paywall names what stays free, in full, before it names what costs money.

---

## 7. Widgets

WidgetKit, all values computed locally by `SunlitCore` in the extension.

| Family | Content |
|---|---|
| `systemSmall` | Next event and its countdown |
| `systemMedium` | The day's arc with the sun's live position |
| `accessoryCircular` | Golden hour countdown ring |
| `accessoryRectangular` | Sunrise, sunset, moon phase |

Timelines refresh at event boundaries rather than on a fixed cadence.

---

## 8. Localisation

Ten storefronts: en, de, fr, it, es, es-MX, nl, pl, ja, pt-BR.

String catalogue, `LOCALIZATION_PREFERS_STRING_CATALOGS = YES`, `knownRegions`
listing all ten, and a source-language entry in the InfoPlist catalogue, without
which the app is named `CFBundleDisplayName` on the home screen.

Translations are written, not machine-produced, and are audited by reading the
original back. Numbers, dates, and units are formatted through `Foundation`
formatters so that decimal separators and 12 versus 24 hour clocks follow the
locale.

Store metadata, keywords, in-app purchase display names and descriptions, and
screenshots all exist per storefront.

---

## 9. Store listing

| Field | Value |
|---|---|
| Name | `Sunlit: Sun & Moon Tracker` |
| Subtitle | `Golden Hour & AR Sun Path` |
| Categories | Navigation, Photo & Video |
| Age rating | 4+ |
| Price | Free with one in-app purchase |

Keywords are written per storefront, not translated from English, because the
words people actually type differ per market.

Eight screenshots at 1290 by 2796, per language, captured in that language.
Screenshots 1 to 3 carry a benefit headline over a device frame on a branded
background; 4 to 8 are full bleed. Screenshots 1 and 2 must carry the story
alone, because those are the two the search results show.

Review notes state the free tier explicitly, name the one purchase, give the
clear-sky model caveat, and describe how to reach the AR view.

---

## 10. Site

`web/`, static, deployed to Vercel at `sunlit-app.vercel.app`. Three pages:
marketing, privacy, support. The privacy page describes an app that collects
nothing, because it collects nothing. The support page describes only features
that exist.

**The site is live and verified anonymously before anything is submitted.** Dead
legal links under a purchase button cost this portfolio a rejection, and a
support page advertising fields that did not exist cost another.

---

## 11. Non-goals

Cut deliberately, and not to be added back without being asked:

- Apple Watch app. Deferred to 1.1.
- Weather, cloud cover, or any forecast. It needs a network and it breaks the
  on-device promise.
- Accounts, sync, analytics, advertising, telemetry of any kind.
- iPad.
- Android.
- Star charts, planets, deep-sky objects. The Milky Way galactic centre is in
  scope; a planetarium is not.
- Drone flight planning, exposure calculators, depth of field tables.

---

## 12. Risks, stated before the work starts

**Eclipse local circumstances** are the most expensive single item. The
topocentric-separation approach removes the need for Besselian elements, but its
accuracy rides entirely on the lunar ephemeris. If the NASA fixture suite cannot
be met inside one minute on contact times, the app ships global circumstances
plus local visibility and obscuration, and the store copy describes exactly
that. It does not describe more.

**The name may be taken.** App Store Connect is the only authority. If
`Sunlit: Sun & Moon Tracker` is refused, the fallbacks are taken in order and
the substitution is reported.

**UV index and irradiance are models.** They are labelled as models in the
interface, in the store description, and in the review notes.

**Camera permission** is required for the AR view. `NSCameraUsageDescription`
must explain the purpose in the user's language, the app must degrade to a
non-AR view if permission is refused, and the App Privacy questionnaire must be
answered as "data not collected", which is true.

**GeoNames attribution** is a licence obligation, not a nicety.

---

## 13. Acceptance criteria

The work is done when all of the following are demonstrated with evidence, not
asserted:

1. `SunlitCore` reproduces every reference fixture inside the accuracy targets
   in section 4.1. Sources: NOAA Solar Calculator, USNO, JPL Horizons, NASA
   eclipse canon.
2. A full day report for one place computes in under 30 ms on device.
3. Every `ProGate` capability has a passing test that proves a caller.
4. The app has been driven on the smallest supported device at the largest
   Dynamic Type size, and every primary control was reached. Evidence is
   screenshots, not a code reading.
5. All four views render correctly at solar altitudes spanning night, twilight,
   golden, and full day, with contrast at or above 4.5:1 in each.
6. Ten languages present in the built bundle, verified by inspecting the binary,
   not the source.
7. The site is live and returns the correct content to an anonymous request.
8. Store metadata validates with zero errors.
9. Screenshots exist for all ten languages, captured in each language, and are
   verified to differ below the header.
10. The version and the in-app purchase are submitted together in one review
    submission, and the submission reports `WAITING_FOR_REVIEW`.
