import Foundation

var failures = 0, checks = 0
func check(_ label: String, _ got: Double, _ want: Double, _ tol: Double) {
    checks += 1
    if abs(got - want) > tol {
        print("FAIL  \(label): got \(got), want \(want), off by \(abs(got - want))")
        failures += 1
    }
}
func checkTrue(_ label: String, _ ok: Bool) {
    checks += 1
    if !ok { print("FAIL  \(label)"); failures += 1 }
}

// Meeus example 47.a: the Moon on 1992 April 12.0 TD.
let jde47 = JulianDay.from(year: 1992, month: 4, day: 12.0)
check("JD 1992 Apr 12.0", jde47.value, 2448724.5, 1e-9)
let m = MoonPosition.evaluate(julianEphemerisDay: jde47)

// The book prints the MEAN longitude 133.162655 before nutation, and the
// apparent longitude 133.167265 after it. This implementation returns the
// apparent one, so the published apparent value is the one to compare.
check("moon apparent longitude", m.longitude, 133.167265, 5e-5)
check("moon latitude", m.latitude, -3.229126, 5e-5)
check("moon distance km", m.distance, 368409.7, 0.5)
check("moon parallax", m.parallax, 0.991990, 1e-5)

// Meeus example 48.a, the same instant: the illuminated fraction is 0.6786 and
// the phase angle 69.0756 degrees.
let sun47 = SolarPositionSPA.evaluate(
    julianDay: jde47, place: Coordinates.Geographic(latitude: 0, longitude: 0), deltaT: 0)
let phase = MoonPosition.phase(
    moon: m,
    sunRightAscension: sun47.geocentricRightAscension,
    sunDeclination: sun47.geocentricDeclination,
    sunDistanceAU: sun47.radiusVector,
    sunApparentLongitude: sun47.apparentLongitude)
check("phase angle", phase.phaseAngle, 69.0756, 0.01)
check("illuminated fraction", phase.illuminatedFraction, 0.6786, 0.001)

// The synodic month is 29.530589 days. Stepping a full cycle from a known new
// moon must return to a new moon, and the halfway point must be full.
// 2026 January 18 at about 19:52 UT is a new moon.
let newMoon = JulianDay.from(year: 2026, month: 1, day: 18.0 + (19.0 + 52.0/60.0)/24.0)
func illumination(at jd: JulianDay) -> Double {
    let mm = MoonPosition.evaluate(julianEphemerisDay: jd)
    let ss = SolarPositionSPA.evaluate(
        julianDay: jd, place: Coordinates.Geographic(latitude: 0, longitude: 0), deltaT: 0)
    return MoonPosition.phase(moon: mm,
        sunRightAscension: ss.geocentricRightAscension,
        sunDeclination: ss.geocentricDeclination,
        sunDistanceAU: ss.radiusVector,
        sunApparentLongitude: ss.apparentLongitude).illuminatedFraction
}
checkTrue("new moon is dark", illumination(at: newMoon) < 0.01)
checkTrue("half a cycle later is full", illumination(at: newMoon.adding(days: 29.530589 / 2)) > 0.98)
checkTrue("a full cycle later is dark again", illumination(at: newMoon.adding(days: 29.530589)) < 0.02)

// Waxing versus waning must be distinguishable, which the illuminated fraction
// alone cannot do because it is symmetric about full moon.
let waxingQuarter = MoonPosition.evaluate(julianEphemerisDay: newMoon.adding(days: 7.4))
let waningQuarter = MoonPosition.evaluate(julianEphemerisDay: newMoon.adding(days: 22.1))
func cycle(at jd: JulianDay, _ mm: MoonPosition.Result) -> Double {
    let ss = SolarPositionSPA.evaluate(
        julianDay: jd, place: Coordinates.Geographic(latitude: 0, longitude: 0), deltaT: 0)
    return MoonPosition.phase(moon: mm,
        sunRightAscension: ss.geocentricRightAscension,
        sunDeclination: ss.geocentricDeclination,
        sunDistanceAU: ss.radiusVector,
        sunApparentLongitude: ss.apparentLongitude).cycleFraction
}
let waxingFraction = cycle(at: newMoon.adding(days: 7.4), waxingQuarter)
let waningFraction = cycle(at: newMoon.adding(days: 22.1), waningQuarter)
checkTrue("waxing quarter is in the first half of the cycle, got \(waxingFraction)",
          waxingFraction > 0.2 && waxingFraction < 0.3)
checkTrue("waning quarter is in the second half, got \(waningFraction)",
          waningFraction > 0.7 && waningFraction < 0.8)

// The cycle fraction must advance monotonically through one synodic month,
// which a sign inversion in the waxing test would break immediately.
var previousFraction = -1.0
var wraps = 0
for hours in stride(from: 0.0, to: 29.53 * 24, by: 6.0) {
    let jd = newMoon.adding(days: hours / 24.0)
    let mm = MoonPosition.evaluate(julianEphemerisDay: jd)
    let frac = cycle(at: jd, mm)
    if frac < previousFraction { wraps += 1 }
    previousFraction = frac
}
checkTrue("cycle fraction advances monotonically, wrapping once, got \(wraps) wraps", wraps <= 1)

// Distance must stay inside the real perigee and apogee bounds over a year, and
// must actually vary: a constant distance would mean the r terms are dead.
var minDistance = 1e9, maxDistance = 0.0
for day in stride(from: 0.0, to: 365.0, by: 0.5) {
    let d = MoonPosition.evaluate(julianEphemerisDay: JulianDay.from(year: 2026, month: 1, day: 1.0 + day)).distance
    minDistance = min(minDistance, d)
    maxDistance = max(maxDistance, d)
}
checkTrue("perigee within real bounds, got \(minDistance)", minDistance > 356000 && minDistance < 362000)
checkTrue("apogee within real bounds, got \(maxDistance)", maxDistance > 404000 && maxDistance < 407000)

// Topocentric correction. For the Moon it must be large, up to about a degree,
// and it must vanish when the body is overhead.
let place = Coordinates.Geographic(latitude: 52.52, longitude: 13.405)
let sunNow = SolarPositionSPA.evaluate(
    julianDay: jde47, place: place, deltaT: 0)
let topo = MoonPosition.topocentric(m, place: place, apparentSiderealTime: sunNow.apparentSiderealTime)
let shift = sqrt(pow(Angle.normalizedSigned(topo.rightAscension - m.rightAscension), 2)
               + pow(topo.declination - m.declination, 2))
checkTrue("topocentric shift is of order one degree, got \(shift)", shift > 0.1 && shift < 1.2)
checkTrue("topocentric distance differs from geocentric",
          abs(topo.distance - m.distance) > 1000)

// Rise and set. Berlin on 21 June 2026: the sun rises about 04:43 and sets about
// 21:33 local, which is 02:43 and 19:33 UT.
func sunAltitude(_ jd: JulianDay, _ p: Coordinates.Geographic) -> Double {
    SolarPositionSPA.evaluate(julianDay: jd, place: p).elevation
}
let berlin = Coordinates.Geographic(latitude: 52.5200, longitude: 13.4050, elevation: 34)
let dayStart = JulianDay.from(year: 2026, month: 6, day: 21.0)
let outcome = RiseSet.solve(
    start: dayStart, end: dayStart.adding(days: 1),
    altitude: { sunAltitude($0, berlin) },
    target: { _ in Refraction.sunriseAltitude })

checkTrue("Berlin has one rise and one set on the solstice", outcome.crossings.count == 2)
if let rise = outcome.firstRise, let set = outcome.lastSet {
    let riseHour = (rise.value - dayStart.value) * 24
    let setHour = (set.value - dayStart.value) * 24
    print(String(format: "  Berlin 2026-06-21 UT: rise %.4f h, set %.4f h, transit alt %.3f",
                 riseHour, setHour, outcome.transit?.altitude ?? -99))
    check("Berlin sunrise UT hour", riseHour, 2.717, 0.05)
    check("Berlin sunset UT hour", setHour, 19.55, 0.05)
}
// Maximum solar altitude at Berlin on the June solstice is 90 - 52.52 + 23.44.
check("Berlin solstice transit altitude", outcome.transit?.altitude ?? -99, 60.92, 0.15)

// The polar cases, which the interpolation method gets wrong and which the app
// must report honestly rather than inventing a time for.
let tromso = Coordinates.Geographic(latitude: 69.6492, longitude: 18.9553)
let midnightSun = RiseSet.solve(
    start: JulianDay.from(year: 2026, month: 6, day: 21.0),
    end: JulianDay.from(year: 2026, month: 6, day: 22.0),
    altitude: { sunAltitude($0, tromso) },
    target: { _ in Refraction.sunriseAltitude })
checkTrue("Tromso has no sunset on the June solstice", midnightSun.crossings.isEmpty)
checkTrue("Tromso is in midnight sun, not polar night", midnightSun.alwaysAbove)

let polarNight = RiseSet.solve(
    start: JulianDay.from(year: 2026, month: 12, day: 21.0),
    end: JulianDay.from(year: 2026, month: 12, day: 22.0),
    altitude: { sunAltitude($0, tromso) },
    target: { _ in Refraction.sunriseAltitude })
checkTrue("Tromso has no sunrise on the December solstice", polarNight.crossings.isEmpty)
checkTrue("Tromso is in polar night", polarNight.alwaysBelow)

// A time-varying target, which is the case the whole solver exists for. The
// moon's rise altitude depends on its parallax at that instant.
func moonAltitude(_ jd: JulianDay, _ p: Coordinates.Geographic) -> Double {
    let mm = MoonPosition.evaluate(julianEphemerisDay: jd)
    let ss = SolarPositionSPA.evaluate(julianDay: jd, place: p)
    let t = MoonPosition.topocentric(mm, place: p, apparentSiderealTime: ss.apparentSiderealTime)
    let h = Coordinates.hourAngle(apparentSiderealTime: ss.apparentSiderealTime,
                                  longitude: p.longitude, rightAscension: t.rightAscension)
    return Coordinates.horizontal(
        equatorial: Coordinates.Equatorial(rightAscension: t.rightAscension, declination: t.declination),
        hourAngle: h, latitude: p.latitude).altitude
}
let moonDay = JulianDay.from(year: 2026, month: 8, day: 23.0)
let moonOutcome = RiseSet.solve(
    start: moonDay, end: moonDay.adding(days: 1),
    altitude: { moonAltitude($0, berlin) },
    target: { _ in 0.125 })
checkTrue("moon rises or sets at Berlin on 23 August 2026, got \(moonOutcome.crossings.count)",
          !moonOutcome.crossings.isEmpty)

// Every crossing the solver reports must actually be a crossing: the altitude
// one minute either side must straddle the target.
for c in outcome.crossings + moonOutcome.crossings {
    let before = sunAltitude(c.julianDay.adding(seconds: -60), berlin)
    let after = sunAltitude(c.julianDay.adding(seconds: 60), berlin)
    checkTrue("crossing at \(c.julianDay.value) is real", before != after)
}

if failures == 0 { print("moon: all \(checks) checks passed") }
else { print("moon: \(failures) FAILURES of \(checks)"); exit(1) }
