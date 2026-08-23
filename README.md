# Sunlit: Sun & Moon Tracker

An iPhone app that answers one question precisely: where is the sun, where is
the moon, and where will they be. For any date, at any place, on a device with
no network connection.

- **App Store:** id `6804486604`, submitted 23 August 2026, `WAITING_FOR_REVIEW`
- **Bundle:** `com.levinschwab.sunlit` · iPhone only · iOS 17+
- **Site:** <https://sunlit-app.vercel.app>
- **Price:** free, with one non consumable at 9.99 EUR
- **Languages:** ten storefronts, 584 keys, written per market rather than
  machine translated

## What it does

Four views over one shared place and date.

**Sky** is the home screen and the identity of the product: the background
gradient is not decoration but a readout, interpolated continuously from the
real solar altitude, so dragging the time scrubber repaints the sky the colour
the sky actually is. The day's arc carries the sun and the moon at their true
positions, with the golden hour band drawn along it.

**AR** puts the sun and moon paths over the camera image, with hour marks and
the solstice and equinox reference curves, and lets you sweep your own skyline
so the app knows when the sun really clears the ridge rather than a flat
horizon. It shows the heading uncertainty as a number, because the loudest
complaint about the product this one competes with is compass accuracy, and a
figure with a stated error is an instrument while a figure without one is a
guess in uniform.

**Map** draws the sunrise and sunset azimuths from the pin, the moon's own rays,
and the shadow an object of any height casts, to scale.

**Data** is the tabulation: three twilights, solar noon, day length and its
change, the moon phase calendar, eclipses with local circumstances, the annual
curve, and export.

## Accuracy, and how it is known

| Quantity | Method | Verified against |
|---|---|---|
| Solar position | NREL SPA (Reda and Andreas) | the report's worked example, to 1e-9 |
| Lunar position | truncated ELP-2000/82, Meeus 47 | examples 47.a and 48.a |
| Eclipses | topocentric separation, no Besselian elements | NASA canon, contact times to **13 s** |
| Rise, set, twilight | numerical solver, not interpolation | NOAA and USNO, including polar cases |

`scripts/prove.sh` compiles `SunlitCore` with `swiftc` and runs **1,976 checks**
in seconds. That exists because a simulator run of the same work has hung for a
day in this portfolio, and because a core that imports nothing but Foundation
can be proven without one.

UV index and irradiance are **clear sky models**, not measurements, and the app
says so wherever they appear.

## Layout

```
Sources/SunlitCore/     pure Swift, Foundation only, no UI. A build gate enforces it
  Astronomy/            SPA, moon, nutation, refraction, eclipses, Milky Way
  Solar/                twilight, golden hour, UV, irradiance
  Terrain/              measured skyline, obstruction, shadows
  Geo/                  34,106 offline cities
  Model/                SkyMoment (one instant), DayReport (one day)
Sources/Sunlit/         the app: Design, Features, Sensors, Store
Sources/SunlitWidgets/  WidgetKit, reads CoreLocation and StoreKit directly
scripts/prove/          eleven proof drivers, 1,976 checks
scripts/i18n/           extraction from compiler output, catalogue assembly
scripts/poster/         poster composition and the gates that guard it
web/                    the site, deployed to Vercel
```

## Attribution

Offline city data from [GeoNames](https://www.geonames.org), licensed
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
