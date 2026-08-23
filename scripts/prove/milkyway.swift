import Foundation

var failures = 0, checks = 0
func check(_ label: String, _ got: Double, _ want: Double, _ tol: Double) {
    checks += 1
    if abs(got - want) > tol || got.isNaN {
        print("FAIL  \(label): got \(got), want \(want), off by \(abs(got - want))")
        failures += 1
    }
}
func checkTrue(_ label: String, _ ok: Bool) {
    checks += 1
    if !ok { print("FAIL  \(label)"); failures += 1 }
}

// Longitude zero throughout the timing tests, so local mean solar time is
// Universal Time and every printed hour can be read straight off a clock.
func hoursFromMidnight(_ jd: JulianDay, longitude: Double) -> Double {
    let local = jd.value + longitude / 360.0 + 0.5
    let fraction = local - local.rounded(.down)
    let hours = fraction * 24.0
    return hours
}
func hoursBeforeOrAfterMidnight(_ jd: JulianDay, longitude: Double) -> Double {
    let h = hoursFromMidnight(jd, longitude: longitude)
    return h > 12 ? h - 24 : h
}
func utAt(year: Int, month: Int, day: Int, localHour: Double, longitude: Double) -> JulianDay {
    JulianDay.from(year: year, month: month, day: Double(day) + localHour / 24.0)
        .adding(days: -longitude / 360.0)
}
func separation(_ a: Coordinates.Horizontal, _ b: Coordinates.Horizontal) -> Double {
    Angle.acos(Angle.sin(a.altitude) * Angle.sin(b.altitude)
        + Angle.cos(a.altitude) * Angle.cos(b.altitude) * Angle.cos(a.azimuth - b.azimuth))
}
/// The instant of greatest galactic centre altitude in the day that starts at
/// `startUT`, refined by the shared event solver.
func transit(startUT: JulianDay, place: Coordinates.Geographic) -> (julianDay: JulianDay, altitude: Double) {
    let outcome = RiseSet.solve(
        start: startUT, end: startUT.adding(days: 1),
        altitude: { MilkyWay.position(at: $0, place: place).altitude },
        target: { _ in MilkyWay.minimumAltitude })
    guard let transit = outcome.transit else {
        checkTrue("the solver found a culmination", false)
        return (startUT, -90)
    }
    return transit
}
func sunAltitude(_ jd: JulianDay, _ p: Coordinates.Geographic) -> Double {
    SolarPositionSPA.evaluate(julianDay: jd, place: p).elevationWithoutRefraction
}

print("MilkyWay proof. Reference values are published, not computed here.")

// ---------------------------------------------------------------------------
// 1. The catalogue position and the pole constants.
//
// SIMBAD, object Sgr A*: galactic coordinates l 359.94423568, b -00.04616002.
// Converting the J2000 equatorial position this module ships must land on that
// pair, which is what pins the three galactic pole constants. Any error in them
// tilts the whole galactic plane.
// ---------------------------------------------------------------------------
let simbadGalacticLongitude = 359.94423568
let simbadGalacticLatitude = -0.04616002
let galactic = Coordinates.galacticFromEquatorial(MilkyWay.galacticCentreJ2000)
print(String(format: "  Sgr A* galactic: l %.5f, b %.5f", galactic.longitude, galactic.latitude))
check("Sgr A* galactic longitude is the origin", Angle.normalizedSigned(galactic.longitude), 0.0, 0.1)
check("Sgr A* galactic latitude is the origin", galactic.latitude, 0.0, 0.1)
check("Sgr A* galactic longitude matches SIMBAD", galactic.longitude, simbadGalacticLongitude, 0.001)
check("Sgr A* galactic latitude matches SIMBAD", galactic.latitude, simbadGalacticLatitude, 0.001)

// The inverse transform must return the catalogue position it came from.
let backToEquatorial = Coordinates.equatorialFromGalactic(
    longitude: galactic.longitude, latitude: galactic.latitude)
check("galactic to equatorial round trip, right ascension",
      backToEquatorial.rightAscension, MilkyWay.galacticCentreJ2000.rightAscension, 1e-9)
check("galactic to equatorial round trip, declination",
      backToEquatorial.declination, MilkyWay.galacticCentreJ2000.declination, 1e-9)

// ---------------------------------------------------------------------------
// 2. Precession, checked against a second published epoch.
//
// SIMBAD lists the same object in FK4 at equinox and epoch B1950.0 as
// 17 42 29.30683, -28 59 18.5584. Precessing the J2000 position back to
// B1950.0, JD 2433282.4235, must reproduce it. FK4 carries E terms of
// aberration that FK5 does not, which is a few tenths of an arcsecond, so the
// tolerance is the 0.01 degree accuracy target of the design, not the
// milliarcsecond of the catalogue.
// ---------------------------------------------------------------------------
let simbadB1950RightAscension = (17.0 + 42.0 / 60.0 + 29.30683 / 3600.0) * 15.0
let simbadB1950Declination = -(28.0 + 59.0 / 60.0 + 18.5584 / 3600.0)
let b1950 = MilkyWay.galacticCentre(at: JulianDay(2433282.4235))
print(String(format: "  precessed to B1950: ra %.5f dec %.5f, published %.5f %.5f",
             b1950.rightAscension, b1950.declination,
             simbadB1950RightAscension, simbadB1950Declination))
check("B1950 right ascension matches the FK4 catalogue",
      b1950.rightAscension, simbadB1950RightAscension, 0.01)
check("B1950 declination matches the FK4 catalogue",
      b1950.declination, simbadB1950Declination, 0.01)

// Size and direction over fifty years. General precession is 50.29 arcseconds
// per year along the ecliptic, which for this object works out at about 0.7
// degrees per fifty years. The sign matters more than the size: right ascension
// must increase and declination must decrease for a body at 17h45m, -29
// degrees, and an implementation with the sign of the precession angles flipped
// would move it exactly the other way while passing a size only test.
let epoch2000 = MilkyWay.galacticCentre(at: JulianDay.j2000)
let epoch2050 = MilkyWay.galacticCentre(at: JulianDay.j2000.adding(days: 50 * 365.25))
let moved = Angle.acos(
    Angle.sin(epoch2000.declination) * Angle.sin(epoch2050.declination)
    + Angle.cos(epoch2000.declination) * Angle.cos(epoch2050.declination)
      * Angle.cos(epoch2000.rightAscension - epoch2050.rightAscension))
print(String(format: "  fifty years of precession: %.4f degrees, dRA %+.4f, dDec %+.4f",
             moved, epoch2050.rightAscension - epoch2000.rightAscension,
             epoch2050.declination - epoch2000.declination))
check("fifty years of precession moves the centre about 0.7 degrees", moved, 0.695, 0.03)
checkTrue("precession increases the right ascension of the galactic centre",
          epoch2050.rightAscension > epoch2000.rightAscension)
checkTrue("precession decreases the declination of the galactic centre",
          epoch2050.declination < epoch2000.declination)
checkTrue("the declination change is the small one, an order of magnitude under the RA change",
          abs(epoch2050.declination - epoch2000.declination)
            < 0.1 * abs(epoch2050.rightAscension - epoch2000.rightAscension))

// ---------------------------------------------------------------------------
// 3. Season and culmination.
//
// The galactic centre sits at right ascension 17h45m, so it stands opposite the
// sun when the sun is near 5h45m, which is mid June. Published, EarthSky: on
// July 1 the Teapot and the galactic centre climb to their highest point for
// the night "around midnight", and "in August the Teapot and the Milky Way's
// centre reach their highest points for the night during the evening hours".
// ---------------------------------------------------------------------------
let north = Coordinates.Geographic(latitude: 40.0, longitude: 0.0)
let juneNight = utAt(year: 2026, month: 6, day: 18, localHour: 12, longitude: 0)
let juneTransit = transit(startUT: juneNight, place: north)
let juneOffset = hoursBeforeOrAfterMidnight(juneTransit.julianDay, longitude: 0)
print(String(format: "  40N, 18 June 2026: culmination %+.2f h from local midnight, altitude %.2f",
             juneOffset, juneTransit.altitude))
check("in June the galactic centre culminates at local midnight", juneOffset, 0.0, 0.34)
check("culmination altitude at 40N is 90 minus latitude plus declination",
      juneTransit.altitude, 90.0 - 40.0 + MilkyWay.galacticCentre(at: juneTransit.julianDay).declination, 0.05)

// Southern hemisphere, same night. June is southern winter, and the centre
// passes almost overhead: the same date that makes it a summer object in the
// north makes it a winter object in the south.
let south = Coordinates.Geographic(latitude: -33.0, longitude: 0.0)
let southTransit = transit(startUT: juneNight, place: south)
let southOffset = hoursBeforeOrAfterMidnight(southTransit.julianDay, longitude: 0)
print(String(format: "  33S, 18 June 2026: culmination %+.2f h from local midnight, altitude %.2f",
             southOffset, southTransit.altitude))
check("in June the centre also culminates at local midnight from the south", southOffset, 0.0, 0.34)
check("from 33S the centre passes nearly overhead", southTransit.altitude,
      90.0 - abs(-33.0 - MilkyWay.galacticCentre(at: southTransit.julianDay).declination), 0.05)
checkTrue("the southern winter view beats the northern summer view by more than fifty degrees",
          southTransit.altitude - juneTransit.altitude > 50)

// Northern winter: the centre is a daytime object, culminating near local noon.
let decemberDay = utAt(year: 2026, month: 12, day: 18, localHour: 0, longitude: 0)
let decemberTransit = transit(startUT: decemberDay, place: north)
let decemberHour = hoursFromMidnight(decemberTransit.julianDay, longitude: 0)
print(String(format: "  40N, 18 December 2026: culmination at local %.2f h", decemberHour))
check("in December the centre culminates near local noon", decemberHour, 12.0, 0.34)

// The two published EarthSky statements.
let julyFirstNight = utAt(year: 2026, month: 7, day: 1, localHour: 12, longitude: 0)
let julyTransit = transit(startUT: julyFirstNight, place: north)
let julyOffset = hoursBeforeOrAfterMidnight(julyTransit.julianDay, longitude: 0)
print(String(format: "  40N, 1 July 2026: culmination %+.2f h from local midnight", julyOffset))
check("EarthSky: on 1 July the centre culminates around midnight", julyOffset, 0.0, 1.0)

let augustNight = utAt(year: 2026, month: 8, day: 15, localHour: 12, longitude: 0)
let augustTransit = transit(startUT: augustNight, place: north)
let augustHour = hoursFromMidnight(augustTransit.julianDay, longitude: 0)
let augustSunset = RiseSet.solve(
    start: augustNight, end: augustNight.adding(days: 1),
    altitude: { sunAltitude($0, north) },
    target: { _ in Refraction.sunriseAltitude }).lastSet
let augustSunsetHour = hoursFromMidnight(augustSunset ?? augustNight, longitude: 0)
print(String(format: "  40N, 15 August 2026: culmination at local %.2f h, sunset at %.2f h",
             augustHour, augustSunsetHour))
checkTrue("EarthSky: in August the centre culminates in the evening hours, got \(augustHour)",
          augustHour > 18.0 && augustHour < 24.0)
checkTrue("and it culminates after sunset, so the evening culmination is a dark one",
          augustHour > augustSunsetHour)
checkTrue("August culminates earlier in the evening than July did",
          augustHour < 24.0 + julyOffset)

// ---------------------------------------------------------------------------
// 4. The latitude at which the centre stops clearing ten degrees.
//
// Culmination altitude for a northern observer is 90 - latitude + declination,
// so the centre reaches exactly ten degrees at latitude 80 + declination. That
// boundary is computed here from the declination the module itself returns for
// the date, and checked on both sides.
// ---------------------------------------------------------------------------
let boundaryNight = utAt(year: 2026, month: 6, day: 18, localHour: 12, longitude: 0)
let declinationOfDate = MilkyWay.galacticCentre(at: boundaryNight).declination
let boundaryLatitude = 80.0 + declinationOfDate
print(String(format: "  declination of date %.4f gives boundary latitude %.4f",
             declinationOfDate, boundaryLatitude))
check("the boundary latitude is just under 51 degrees north", boundaryLatitude, 50.98, 0.05)

let atBoundary = MilkyWay.visibility(
    night: boundaryNight, place: Coordinates.Geographic(latitude: boundaryLatitude, longitude: 0))
check("at the boundary latitude the centre peaks at exactly the ten degree threshold",
      atBoundary.bestAltitude, MilkyWay.minimumAltitude, 0.05)

let justNorth = MilkyWay.visibility(
    night: boundaryNight,
    place: Coordinates.Geographic(latitude: boundaryLatitude + 0.5, longitude: 0))
print("  half a degree north of the boundary: \(justNorth.limitingFactor?.rawValue ?? "a window"), "
    + String(format: "peak %.3f", justNorth.bestAltitude))
checkTrue("half a degree north of the boundary there is no window", justNorth.window == nil)
checkTrue("and the reason given is that the centre never got high enough",
          justNorth.limitingFactor == .galacticCentreBelowHorizon)
checkTrue("and the peak altitude is below the threshold, got \(justNorth.bestAltitude)",
          justNorth.bestAltitude < MilkyWay.minimumAltitude)

let justSouth = MilkyWay.visibility(
    night: boundaryNight,
    place: Coordinates.Geographic(latitude: boundaryLatitude - 0.5, longitude: 0))
print("  half a degree south of the boundary: \(justSouth.limitingFactor?.rawValue ?? "a window"), "
    + String(format: "peak %.3f", justSouth.bestAltitude))
checkTrue("half a degree south of the boundary the centre does clear the threshold, got \(justSouth.bestAltitude)",
          justSouth.bestAltitude > MilkyWay.minimumAltitude)
checkTrue("so the limiting factor there is no longer the horizon",
          justSouth.limitingFactor != .galacticCentreBelowHorizon)

// The latitude named in the brief, well north of the computed boundary.
let farNorth = MilkyWay.visibility(
    night: boundaryNight, place: Coordinates.Geographic(latitude: 59.0, longitude: 0))
checkTrue("at 59N the centre never clears ten degrees",
          farNorth.limitingFactor == .galacticCentreBelowHorizon && farNorth.window == nil)
checkTrue("at 59N the quality is none", farNorth.quality == .none)

// ---------------------------------------------------------------------------
// 5. Fifty degrees north in June: the centre rises, and it is still hopeless,
// because the sky never gets astronomically dark. This is the case a naive
// implementation reports as visible.
//
// The check on the reason is analytic: the sun's lowest altitude on the
// solstice is latitude + obliquity - 90, which at 50N is -16.56 degrees, above
// the -18 that astronomical night requires.
// ---------------------------------------------------------------------------
let fiftyNorth = Coordinates.Geographic(latitude: 50.0, longitude: 0.0)
let solsticeNight = utAt(year: 2026, month: 6, day: 21, localHour: 12, longitude: 0)
let juneAtFifty = MilkyWay.visibility(night: solsticeNight, place: fiftyNorth)
var lowestSun = 90.0
for step in 0...288 {
    lowestSun = min(lowestSun, sunAltitude(solsticeNight.adding(days: Double(step) / 288.0), fiftyNorth))
}
print(String(format: "  50N solstice: centre peaks at %.2f, sun bottoms out at %.2f, factor %@",
             juneAtFifty.bestAltitude, lowestSun, juneAtFifty.limitingFactor?.rawValue ?? "a window"))
checkTrue("at 50N in June the centre does clear ten degrees, got \(juneAtFifty.bestAltitude)",
          juneAtFifty.bestAltitude > MilkyWay.minimumAltitude)
check("the sun's lowest altitude at 50N on the solstice is latitude plus obliquity minus 90",
      lowestSun, 50.0 + 23.44 - 90.0, 0.2)
checkTrue("there is no astronomical night at 50N in June", lowestSun > MilkyWay.darkSunAltitude)
checkTrue("so the limiting factor is twilight, not the horizon and not the moon",
          juneAtFifty.limitingFactor == .twilight)
checkTrue("and there is no window", juneAtFifty.window == nil && juneAtFifty.quality == .none)

// ---------------------------------------------------------------------------
// 6. Moonlight. Published: the full moon of July 2026 falls on 29 July at
// 14:35 UTC (timeanddate, Farmers' Almanac). A full moon is up from sunset to
// sunrise by definition, so the night that follows it has no window anywhere.
// ---------------------------------------------------------------------------
let thirtyNorth = Coordinates.Geographic(latitude: 30.0, longitude: 0.0)
let fullMoonNight = utAt(year: 2026, month: 7, day: 29, localHour: 18, longitude: 0)
let moonlit = MilkyWay.visibility(night: fullMoonNight, place: thirtyNorth)

// Independent confirmation that the setup is what the published date says it
// is: at local midnight the moon must be all but fully lit and above the
// horizon. Without this the moonlight verdict could come from a bug rather
// than from the moon.
let midnight = utAt(year: 2026, month: 7, day: 30, localHour: 0, longitude: 0)
let sunAtMidnight = SolarPositionSPA.evaluate(julianDay: midnight, place: thirtyNorth)
let moonAtMidnight = MoonPosition.evaluate(julianEphemerisDay: JulianDay(sunAtMidnight.julianEphemerisDay))
let moonPhase = MoonPosition.phase(
    moon: moonAtMidnight,
    sunRightAscension: sunAtMidnight.geocentricRightAscension,
    sunDeclination: sunAtMidnight.geocentricDeclination,
    sunDistanceAU: sunAtMidnight.radiusVector,
    sunApparentLongitude: sunAtMidnight.apparentLongitude)
let moonTopocentric = MoonPosition.topocentric(
    moonAtMidnight, place: thirtyNorth, apparentSiderealTime: sunAtMidnight.apparentSiderealTime)
let moonAltitude = Coordinates.horizontal(
    equatorial: Coordinates.Equatorial(rightAscension: moonTopocentric.rightAscension,
                                       declination: moonTopocentric.declination),
    hourAngle: Coordinates.hourAngle(apparentSiderealTime: sunAtMidnight.apparentSiderealTime,
                                     longitude: 0, rightAscension: moonTopocentric.rightAscension),
    latitude: 30.0).altitude
print(String(format: "  30N, night of 29 July 2026: moon %.3f lit at altitude %.1f, centre peaks %.1f, factor %@",
             moonPhase.illuminatedFraction, moonAltitude, moonlit.bestAltitude,
             moonlit.limitingFactor?.rawValue ?? "a window"))
checkTrue("the published full moon really is full, got \(moonPhase.illuminatedFraction)",
          moonPhase.illuminatedFraction > 0.98)
checkTrue("and it is above the horizon at local midnight", moonAltitude > 0)
checkTrue("the centre is well up on that night, got \(moonlit.bestAltitude)",
          moonlit.bestAltitude > 25)
checkTrue("with a full moon up there is no window", moonlit.window == nil)
checkTrue("and the limiting factor is moonlight", moonlit.limitingFactor == .moonlight)

// The same place two weeks earlier. Half a synodic month before a full moon,
// 29.530589 / 2 days, is a new moon, and the window must appear.
let newMoonNight = fullMoonNight.adding(days: -29.530589 / 2)
let dark = MilkyWay.visibility(night: newMoonNight, place: thirtyNorth)
checkTrue("the same place on a new moon night has a window", dark.window != nil)
guard let darkWindow = dark.window, let darkBest = dark.bestMoment else {
    print("milkyway: \(failures + 1) FAILURES of \(checks), no window on the new moon night")
    exit(1)
}
let windowHours = (darkWindow.end.value - darkWindow.start.value) * 24
print(String(format: "  30N, new moon night: window %.2f h from local %.2f h, best altitude %.1f, quality %@",
             windowHours, hoursFromMidnight(darkWindow.start, longitude: 0),
             dark.bestAltitude, dark.quality.rawValue))
checkTrue("with no limiting factor", dark.limitingFactor == nil)
checkTrue("the window is hours long, got \(windowHours)", windowHours > 2 && windowHours < 10)
checkTrue("and the grade is excellent, got \(dark.quality.rawValue)", dark.quality == .excellent)
checkTrue("the best moment lies inside the window",
          darkBest.value >= darkWindow.start.value && darkBest.value <= darkWindow.end.value)

// Every condition the window claims must actually hold at its midpoint, and at
// least one must fail a quarter of an hour outside each end.
let middle = JulianDay((darkWindow.start.value + darkWindow.end.value) / 2)
func conditions(_ jd: JulianDay, _ place: Coordinates.Geographic) -> (centre: Double, sun: Double, moonUp: Bool, lit: Double) {
    let sun = SolarPositionSPA.evaluate(julianDay: jd, place: place)
    let centre = MilkyWay.position(at: jd, place: place).altitude
    let moon = MoonPosition.evaluate(julianEphemerisDay: JulianDay(sun.julianEphemerisDay))
    let topo = MoonPosition.topocentric(moon, place: place, apparentSiderealTime: sun.apparentSiderealTime)
    let altitude = Coordinates.horizontal(
        equatorial: Coordinates.Equatorial(rightAscension: topo.rightAscension, declination: topo.declination),
        hourAngle: Coordinates.hourAngle(apparentSiderealTime: sun.apparentSiderealTime,
                                         longitude: place.longitude, rightAscension: topo.rightAscension),
        latitude: place.latitude).altitude
    let phase = MoonPosition.phase(moon: moon,
        sunRightAscension: sun.geocentricRightAscension,
        sunDeclination: sun.geocentricDeclination,
        sunDistanceAU: sun.radiusVector,
        sunApparentLongitude: sun.apparentLongitude)
    return (centre, sun.elevationWithoutRefraction, altitude > 0, phase.illuminatedFraction)
}
let inside = conditions(middle, thirtyNorth)
checkTrue("inside the window the centre is above ten degrees, got \(inside.centre)",
          inside.centre > MilkyWay.minimumAltitude)
checkTrue("inside the window the sun is below minus eighteen, got \(inside.sun)",
          inside.sun < MilkyWay.darkSunAltitude)
checkTrue("inside the window the moon is down or faint",
          !inside.moonUp || inside.lit < MilkyWay.tolerableMoonIllumination)
for edge in [darkWindow.start.adding(seconds: -900), darkWindow.end.adding(seconds: 900)] {
    let outside = conditions(edge, thirtyNorth)
    let holds = outside.centre > MilkyWay.minimumAltitude
        && outside.sun < MilkyWay.darkSunAltitude
        && (!outside.moonUp || outside.lit < MilkyWay.tolerableMoonIllumination)
    checkTrue("a quarter hour outside the window at least one condition fails", !holds)
}

// ---------------------------------------------------------------------------
// 6a. A moon that is up but dim costs a grade.
//
// On 17 August 2026 at the same place the centre reaches the same 31 degrees as
// on the new moon night above, and the moon inside the window is under three
// tenths lit, so the window is allowed to stand. The sky is still not properly
// dark, and the grade has to say so. Same site, same peak altitude, one step
// apart: the only difference is the moon.
// ---------------------------------------------------------------------------
let dimMoonNight = utAt(year: 2026, month: 8, day: 17, localHour: 18, longitude: 0)
let dimMoon = MilkyWay.visibility(night: dimMoonNight, place: thirtyNorth)
if let best = dimMoon.bestMoment {
    let atBest = conditions(best, thirtyNorth)
    print(String(format: "  30N, 17 August 2026: peak %.2f, moon up %@, %.3f lit, grade %@",
                 dimMoon.bestAltitude, atBest.moonUp ? "yes" : "no", atBest.lit,
                 dimMoon.quality.rawValue))
    checkTrue("the centre reaches the same height as on the new moon night, got \(dimMoon.bestAltitude)",
              dimMoon.bestAltitude > 30)
    checkTrue("the moon is above the horizon at the best moment", atBest.moonUp)
    checkTrue("and it is dim enough to be tolerated, got \(atBest.lit)",
              atBest.lit > 0.05 && atBest.lit < MilkyWay.tolerableMoonIllumination)
    checkTrue("so the same peak altitude grades one step lower than under a moonless sky, got "
              + dimMoon.quality.rawValue, dimMoon.quality == .good)
} else {
    checkTrue("17 August 2026 at 30N has a window", false)
}

// ---------------------------------------------------------------------------
// 6b. A night whose window is split in two.
//
// The moon condition can switch off and back on inside one night: a waning moon
// just over three tenths lit rises during the dark hours, and its illuminated
// fraction then falls through the threshold while it is still up. A search over
// twenty years of nights finds this every few lunations, so it is a case the
// product will meet, not a curiosity. What the module must report is the longest
// continuous stretch. Reporting the span from the first qualifying minute to the
// last one would promise the moonlit gap as shooting time.
//
// The qualifying set here is recomputed minute by minute from the three
// published conditions rather than taken from the module.
// ---------------------------------------------------------------------------
let splitNight = utAt(year: 2027, month: 7, day: 8, localHour: 12, longitude: 0)
func qualifies(_ jd: JulianDay, _ place: Coordinates.Geographic) -> Bool {
    let c = conditions(jd, place)
    return c.centre > MilkyWay.minimumAltitude
        && c.sun < MilkyWay.darkSunAltitude
        && (!c.moonUp || c.lit < MilkyWay.tolerableMoonIllumination)
}
var independentRuns: [(start: Double, end: Double)] = []
var openRun: Double? = nil
var lastQualifying = 0.0
for minute in 0...1440 {
    let fraction = Double(minute) / 1440.0
    if qualifies(splitNight.adding(days: fraction), south) {
        if openRun == nil { openRun = fraction }
        lastQualifying = fraction
    } else if let o = openRun {
        independentRuns.append((o, lastQualifying))
        openRun = nil
    }
}
if let o = openRun { independentRuns.append((o, lastQualifying)) }
let longest = independentRuns.max(by: { ($0.end - $0.start) < ($1.end - $1.start) })
let split = MilkyWay.visibility(night: splitNight, place: south)
print(String(format: "  33S, 8 July 2027: %d qualifying stretches, longest %.2f h, module returns %.2f h",
             independentRuns.count, ((longest?.end ?? 0) - (longest?.start ?? 0)) * 24,
             split.window.map { ($0.end.value - $0.start.value) * 24 } ?? 0))
checkTrue("the night really is split into two stretches, got \(independentRuns.count)",
          independentRuns.count == 2)
if let window = split.window, let longest = longest {
    check("the reported window starts at the longest stretch",
          (window.start.value - splitNight.value) * 24, longest.start * 24, 0.02)
    check("the reported window ends at the longest stretch",
          (window.end.value - splitNight.value) * 24, longest.end * 24, 0.02)
    // The shorter stretch lies outside the window, which is the whole point:
    // an implementation that spanned from the first qualifying minute to the
    // last would have swallowed it and the moonlit gap with it.
    let discarded = independentRuns.first(where: { $0.start != longest.start })
    checkTrue("the shorter stretch is left out of the window",
              discarded.map { $0.end < longest.start || $0.start > longest.end } ?? false)
    checkTrue("every minute of the reported window qualifies", {
        var allQualify = true
        var t = window.start
        while t.value <= window.end.value {
            if !qualifies(t, south) { allQualify = false; break }
            t = t.adding(seconds: 60)
        }
        return allQualify
    }())
} else {
    checkTrue("the split night has a window", false)
}

// ---------------------------------------------------------------------------
// 6c. The night boundary follows the place, not Greenwich.
//
// At longitude 175 east, local noon falls at 00:21 Universal Time. A night cut
// at Universal noon instead would slice this observer's night down the middle
// and hand back half of it. The window is checked against a qualifying set
// computed here from local noon to local noon, minute by minute.
// ---------------------------------------------------------------------------
let wellington = Coordinates.Geographic(latitude: -41.29, longitude: 174.78)
let newMoonJuly = JulianDay.from(year: 2026, month: 7, day: 29.0 + (14.0 + 35.0 / 60.0) / 24.0)
    .adding(days: -29.530589 / 2)
let wellingtonNoon: JulianDay = {
    let offset = wellington.longitude / 360.0
    return JulianDay((newMoonJuly.value + offset).rounded(.down) - offset)
}()
var wellingtonRuns: [(start: Double, end: Double)] = []
var wellingtonOpen: Double? = nil
var wellingtonLast = 0.0
for minute in 0...1440 {
    let fraction = Double(minute) / 1440.0
    if qualifies(wellingtonNoon.adding(days: fraction), wellington) {
        if wellingtonOpen == nil { wellingtonOpen = fraction }
        wellingtonLast = fraction
    } else if let o = wellingtonOpen {
        wellingtonRuns.append((o, wellingtonLast))
        wellingtonOpen = nil
    }
}
if let o = wellingtonOpen { wellingtonRuns.append((o, wellingtonLast)) }
let wellingtonLongest = wellingtonRuns.max(by: { ($0.end - $0.start) < ($1.end - $1.start) })
let wellingtonVisibility = MilkyWay.visibility(night: newMoonJuly, place: wellington)
let wellingtonHours = wellingtonVisibility.window.map { ($0.end.value - $0.start.value) * 24 } ?? 0
print(String(format: "  Wellington, new moon of July 2026: module %.2f h, independent %.2f h",
             wellingtonHours, ((wellingtonLongest?.end ?? 0) - (wellingtonLongest?.start ?? 0)) * 24))
checkTrue("the local night at longitude 175 east is hours long, got \(wellingtonHours)",
          wellingtonHours > 5)
if let window = wellingtonVisibility.window, let longest = wellingtonLongest {
    check("the window matches the local night computed independently, start",
          (window.start.value - wellingtonNoon.value) * 24, longest.start * 24, 0.02)
    check("the window matches the local night computed independently, end",
          (window.end.value - wellingtonNoon.value) * 24, longest.end * 24, 0.02)
} else {
    checkTrue("Wellington has a window on a new moon night", false)
}

// ---------------------------------------------------------------------------
// 7. Season. At 35N in late December the centre climbs to 26 degrees and the
// night is properly dark, but the centre is up in the daytime and gone by dusk.
// Neither the horizon, nor twilight, nor the moon is the reason.
// ---------------------------------------------------------------------------
let thirtyFive = Coordinates.Geographic(latitude: 35.0, longitude: 0.0)
let winterNight = utAt(year: 2026, month: 12, day: 21, localHour: 12, longitude: 0)
let winter = MilkyWay.visibility(night: winterNight, place: thirtyFive)
var winterLowestSun = 90.0
for step in 0...288 {
    winterLowestSun = min(winterLowestSun, sunAltitude(winterNight.adding(days: Double(step) / 288.0), thirtyFive))
}
print(String(format: "  35N, 21 December 2026: centre peaks %.1f, sun bottoms out %.1f, factor %@",
             winter.bestAltitude, winterLowestSun, winter.limitingFactor?.rawValue ?? "a window"))
checkTrue("at 35N in December the centre does get high, got \(winter.bestAltitude)",
          winter.bestAltitude > 20)
checkTrue("and the night is genuinely dark", winterLowestSun < MilkyWay.darkSunAltitude)
checkTrue("but the two never coincide, so the factor is the season",
          winter.limitingFactor == .season)

// ---------------------------------------------------------------------------
// 8. The galactic plane as a curve.
//
// Both precession and the equatorial to horizontal transform are rotations of
// the celestial sphere, and a rotation preserves angles. So evenly spaced
// galactic longitudes must come out evenly spaced on the observer's sky: with
// 360 samples every neighbouring pair is exactly one degree apart, including
// the pair that closes the loop. Measuring that as a spherical separation
// rather than as an azimuth difference is the point of the test, because an
// azimuth difference is what a wrap bug hides in.
// ---------------------------------------------------------------------------
let planeInstant = utAt(year: 2026, month: 8, day: 23, localHour: 22, longitude: 0)
let planePlace = Coordinates.Geographic(latitude: 28.3, longitude: -16.5, elevation: 2390)
let plane = MilkyWay.galacticPlane(at: planeInstant, place: planePlace, samples: 360)
checkTrue("the plane comes back with the requested number of samples", plane.count == 360)

var worstGap = 0.0
var largestAzimuthJump = 0.0
for i in plane.indices {
    let next = plane[(i + 1) % plane.count]
    worstGap = max(worstGap, abs(separation(plane[i], next) - 1.0))
    largestAzimuthJump = max(largestAzimuthJump, abs(plane[i].azimuth - next.azimuth))
}
print(String(format: "  galactic plane: worst deviation from one degree spacing %.2e, largest raw azimuth step %.1f",
             worstGap, largestAzimuthJump))
checkTrue("consecutive plane samples are one degree apart on the sky, worst error \(worstGap)",
          worstGap < 1e-3)

// The curve is a great circle, so every point on it stands ninety degrees from
// the north galactic pole. That catches a plane built at the wrong galactic
// latitude as well as one built around the wrong pole. The pole is placed here
// independently of the module, straight from the catalogue constants.
let poleDirection: Coordinates.Horizontal = {
    let equatorial = Coordinates.precessFromJ2000(
        Coordinates.equatorialFromGalactic(longitude: 0, latitude: 90), to: planeInstant)
    let sun = SolarPositionSPA.evaluate(julianDay: planeInstant, place: planePlace)
    let hourAngle = Coordinates.hourAngle(apparentSiderealTime: sun.apparentSiderealTime,
                                          longitude: planePlace.longitude,
                                          rightAscension: equatorial.rightAscension)
    return Coordinates.horizontal(equatorial: equatorial, hourAngle: hourAngle, latitude: planePlace.latitude)
}()
var worstPoleSeparation = 0.0
for point in plane {
    worstPoleSeparation = max(worstPoleSeparation, abs(separation(point, poleDirection) - 90.0))
}
checkTrue("every plane sample stands ninety degrees from the galactic pole, worst error \(worstPoleSeparation)",
          worstPoleSeparation < 0.01)

// The plane and the galactic centre have to live in the same frame. Sgr A* is
// not exactly at galactic longitude zero: SIMBAD puts it 0.0725 degrees away
// from the origin, and that offset is what the two must differ by.
let centreNow = MilkyWay.position(at: planeInstant, place: planePlace)
let originOffset = separation(plane[0], centreNow)
let catalogueOffset = Angle.acos(
    Angle.cos(simbadGalacticLatitude) * Angle.cos(simbadGalacticLongitude))
print(String(format: "  plane origin to galactic centre: %.4f degrees, catalogue says %.4f",
             originOffset, catalogueOffset))
check("the plane origin sits the catalogued offset away from Sgr A*",
      originOffset, catalogueOffset, 0.002)

// Altitudes on the curve have to span the sky rather than sit on one value,
// which a transform that dropped the hour angle would produce.
let altitudes = plane.map { $0.altitude }
checkTrue("the plane crosses the horizon on this night",
          altitudes.min()! < -20 && altitudes.max()! > 20)

// ---------------------------------------------------------------------------
// 9. The position function has to agree with the plane machinery and with the
// hand computable culmination altitude, at a place in the southern hemisphere
// so that a hemisphere sign error cannot hide.
// ---------------------------------------------------------------------------
let atacama = Coordinates.Geographic(latitude: -24.63, longitude: -70.40, elevation: 2635)
let atacamaNight = utAt(year: 2026, month: 8, day: 23, localHour: 12, longitude: -70.40)
let atacamaTransit = transit(startUT: atacamaNight, place: atacama)
let expectedAltitude = 90.0 - abs(-24.63 - MilkyWay.galacticCentre(at: atacamaTransit.julianDay).declination)
check("culmination altitude in the Atacama", atacamaTransit.altitude, expectedAltitude, 0.05)
// Which side of the zenith a body transits on is decided by its declination
// against the observer's latitude, not by the hemisphere. The galactic centre
// at -29 degrees passes south of the zenith for everyone north of -29, which
// includes the Atacama at -24.6, and north of the zenith for anyone further
// south. Getting this wrong is what a mirrored azimuth looks like.
let atacamaAzimuth = MilkyWay.position(at: atacamaTransit.julianDay, place: atacama).azimuth
let northAzimuth = MilkyWay.position(at: juneTransit.julianDay, place: north).azimuth
let deepSouthAzimuth = MilkyWay.position(at: southTransit.julianDay, place: south).azimuth
print(String(format: "  culmination azimuths: 40N %.1f, 24.6S %.1f, 33S %.1f",
             northAzimuth, atacamaAzimuth, deepSouthAzimuth))
checkTrue("from 40N the centre transits due south, got \(northAzimuth)",
          abs(northAzimuth - 180) < 1)
checkTrue("from 24.6S, still north of the centre's declination, it also transits due south, got \(atacamaAzimuth)",
          abs(atacamaAzimuth - 180) < 1)
checkTrue("from 33S, south of the centre's declination, it transits due north, got \(deepSouthAzimuth)",
          abs(Angle.normalizedSigned(deepSouthAzimuth)) < 1)

// The published full moon of 28 August 2026 at 04:18 UTC, less half a synodic
// month, is the new moon of 13 August. On that night the best dark site in the
// world has the centre almost overhead with no moon at all, which is the case
// the whole feature exists to find.
let atacamaNewMoon = utAt(year: 2026, month: 8, day: 28, localHour: 4.3, longitude: -70.40)
    .adding(days: -29.530589 / 2)
let atacamaVisibility = MilkyWay.visibility(night: atacamaNewMoon, place: atacama)
let atacamaHours = atacamaVisibility.window.map { ($0.end.value - $0.start.value) * 24 } ?? 0
print(String(format: "  Atacama, new moon of August 2026: peak %.1f, quality %@, window %.2f h, factor %@",
             atacamaVisibility.bestAltitude, atacamaVisibility.quality.rawValue, atacamaHours,
             atacamaVisibility.limitingFactor?.rawValue ?? "none"))
checkTrue("the Atacama on a new moon night in August is excellent, got \(atacamaVisibility.quality.rawValue)",
          atacamaVisibility.quality == .excellent)
checkTrue("with the centre nearly overhead, got \(atacamaVisibility.bestAltitude)",
          atacamaVisibility.bestAltitude > 80)
checkTrue("and a window of several hours, got \(atacamaHours)", atacamaHours > 4)

// A gibbous moon a week later must cost the same place its window, or at least
// its grade. This is the same site and the same season, so only the moon can
// account for a difference.
let atacamaMoonlit = MilkyWay.visibility(night: atacamaNewMoon.adding(days: 10), place: atacama)
print("  Atacama ten nights later: quality \(atacamaMoonlit.quality.rawValue), "
    + "factor \(atacamaMoonlit.limitingFactor?.rawValue ?? "none")")
checkTrue("a bright moon downgrades the same site ten nights later",
          atacamaMoonlit.quality != .excellent)

if failures == 0 { print("milkyway: all \(checks) checks passed") }
else { print("milkyway: \(failures) FAILURES of \(checks)"); exit(1) }
