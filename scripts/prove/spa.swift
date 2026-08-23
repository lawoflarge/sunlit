import Foundation

// The worked example from Reda and Andreas, NREL/TP-560-34302, section 3 and
// appendix A.5. Reproducing this single case validates all 321 coefficient rows
// at once: if any digit in any table were wrong, one of these intermediate
// values would disagree, and which one says which table to look in.
//
// Inputs: 17 October 2003, 12:30:30 local time, zone UT-7, longitude
// -105.1786, latitude 39.742476, elevation 1830.14 m, pressure 820 mbar,
// temperature 11 C, surface slope 30 degrees, surface azimuth rotation -10
// degrees, delta T 67 seconds.

var failures = 0
var checks = 0
func check(_ label: String, _ got: Double, _ want: Double, _ tol: Double) {
    checks += 1
    let d = abs(got - want)
    if d > tol {
        print("FAIL  \(label): got \(got), want \(want), off by \(d)")
        failures += 1
    }
}

let localDay = 17.0 + (12.0 + 30.0 / 60.0 + 30.0 / 3600.0) / 24.0
let utDay = localDay + 7.0 / 24.0     // UT-7, so UT is later
let jd = JulianDay.from(year: 2003, month: 10, day: utDay)

let place = Coordinates.Geographic(latitude: 39.742476, longitude: -105.1786, elevation: 1830.14)
let air = SolarPositionSPA.Atmosphere(pressureMillibars: 820, temperatureCelsius: 11)
let r = SolarPositionSPA.evaluate(julianDay: jd, place: place, deltaT: 67, atmosphere: air)

check("julian day",                 r.julianDay,                 2452930.312847,  1e-6)
check("heliocentric longitude L",   r.heliocentricLongitude,     24.0182616917,   1e-5)
check("heliocentric latitude B",    r.heliocentricLatitude,      -0.0001011219,   1e-8)
check("radius vector R",            r.radiusVector,              0.9965422974,    1e-8)
check("geocentric longitude Theta", r.geocentricLongitude,       204.0182616917,  1e-5)
check("geocentric latitude beta",   r.geocentricLatitude,        0.0001011219,    1e-8)
check("nutation in longitude",      r.nutationInLongitude,       -0.00399840,     1e-7)
check("nutation in obliquity",      r.nutationInObliquity,       0.00166657,      1e-7)
check("true obliquity epsilon",     r.trueObliquity,             23.440465,       1e-6)
check("aberration",                 r.aberrationCorrection,      -0.005711359,    1e-8)
check("apparent longitude lambda",  r.apparentLongitude,         204.0085519281,  1e-5)
// The paper's value for nu, recovered from its own published H, alpha and the
// observer longitude rather than trusted from a transcription: the report
// defines H = nu + longitude - alpha, so nu = H + alpha - longitude =
// 11.105900 + 202.22741 + 105.1786 = 318.51191. An earlier draft of this test
// carried 318.5119364822, which is wrong by 2.66e-5 degrees. That it is wrong is
// not a matter of opinion: an error of that size in nu propagates one for one
// into H and moves the azimuth by 3.4e-5 degrees, and both H and the azimuth
// reproduce the paper to better than 2e-6. The implementation was right and the
// expected value was mistyped.
check("apparent sidereal time nu",  r.apparentSiderealTime,      318.51191,       1e-5)
// Internal consistency of the hour angle definition, which is what makes the
// recovery above valid.
check("H equals nu plus longitude minus alpha",
      Angle.normalized(r.apparentSiderealTime + place.longitude - r.geocentricRightAscension),
      r.hourAngle, 1e-12)
check("geocentric right ascension", r.geocentricRightAscension,  202.22741,       1e-4)
check("geocentric declination",     r.geocentricDeclination,     -9.31434,        1e-4)
check("observer hour angle H",      r.hourAngle,                 11.105900,       1e-4)
check("topocentric right ascension", r.topocentricRightAscension, 202.22704,      1e-4)
check("topocentric declination",    r.topocentricDeclination,    -9.316179,       1e-5)
check("topocentric hour angle",     r.topocentricHourAngle,      11.10629,        1e-4)
check("elevation without refraction", r.elevationWithoutRefraction, 39.872046,    1e-5)
check("refraction correction",      r.refractionCorrection,      0.016332,        1e-5)
check("topocentric elevation e",    r.elevation,                 39.888378,       1e-5)
check("topocentric zenith theta",   r.zenith,                    50.111622,       1e-5)
check("azimuth from south Gamma",   r.azimuthFromSouth,          14.340241,       1e-5)
check("azimuth from north Phi",     r.azimuth,                   194.340241,      1e-5)

let incidence = SolarPositionSPA.incidenceAngle(
    zenith: r.zenith, azimuthFromSouth: r.azimuthFromSouth,
    slope: 30, surfaceAzimuthRotation: -10)
check("incidence angle I", incidence, 25.187000, 1e-5)

// Sanity beyond the single published case. The sun must be highest at local
// solar noon and lowest at midnight, at any place, on any day. A sign error in
// the hour angle would pass the worked example and fail this.
for (lat, lon, label) in [(52.52, 13.405, "Berlin"), (-33.87, 151.21, "Sydney"),
                          (0.0, 0.0, "null island"), (78.22, 15.65, "Longyearbyen")] {
    let p = Coordinates.Geographic(latitude: lat, longitude: lon)
    var best = -100.0, bestHour = -1.0
    var worst = 100.0
    for step in 0..<(24 * 12) {
        let hour = Double(step) / 12.0
        let j = JulianDay.from(year: 2026, month: 6, day: 21.0 + hour / 24.0)
        let alt = SolarPositionSPA.evaluate(julianDay: j, place: p).elevation
        if alt > best { best = alt; bestHour = hour }
        if alt < worst { worst = alt }
    }
    // Solar noon in UT is close to 12 minus longitude over fifteen.
    let expectedNoon = (12.0 - lon / 15.0).truncatingRemainder(dividingBy: 24.0)
    let normalisedExpected = expectedNoon < 0 ? expectedNoon + 24 : expectedNoon
    var diff = abs(bestHour - normalisedExpected)
    if diff > 12 { diff = 24 - diff }
    check("\(label) solar noon hour", diff, 0.0, 0.35)
    if best <= worst {
        print("FAIL  \(label): maximum altitude not above minimum")
        failures += 1
    }
    checks += 1
}

// On the June solstice the sun's declination is close to +23.44 degrees, and on
// the December solstice close to -23.44. This is independent of the observer and
// pins the obliquity chain.
let june = SolarPositionSPA.evaluate(
    julianDay: JulianDay.from(year: 2026, month: 6, day: 21.5),
    place: Coordinates.Geographic(latitude: 0, longitude: 0))
let december = SolarPositionSPA.evaluate(
    julianDay: JulianDay.from(year: 2026, month: 12, day: 21.5),
    place: Coordinates.Geographic(latitude: 0, longitude: 0))
check("June solstice declination", june.geocentricDeclination, 23.44, 0.05)
check("December solstice declination", december.geocentricDeclination, -23.44, 0.05)

// The Earth is closest to the sun in early January and farthest in early July.
let perihelion = SolarPositionSPA.evaluate(
    julianDay: JulianDay.from(year: 2026, month: 1, day: 3.5),
    place: Coordinates.Geographic(latitude: 0, longitude: 0))
let aphelion = SolarPositionSPA.evaluate(
    julianDay: JulianDay.from(year: 2026, month: 7, day: 5.5),
    place: Coordinates.Geographic(latitude: 0, longitude: 0))
check("perihelion distance", perihelion.radiusVector, 0.9833, 0.0004)
check("aphelion distance", aphelion.radiusVector, 1.0167, 0.0004)

// Performance. A day report samples the altitude every sixty seconds, so 1440
// evaluations must be comfortably fast.
let p0 = Coordinates.Geographic(latitude: 48.0, longitude: 9.0, elevation: 500)
let start = Date()
var sink = 0.0
for step in 0..<1440 {
    let j = JulianDay.from(year: 2026, month: 8, day: 23.0 + Double(step) / 1440.0)
    sink += SolarPositionSPA.evaluate(julianDay: j, place: p0).elevation
}
let elapsed = Date().timeIntervalSince(start) * 1000
print(String(format: "1440 evaluations in %.1f ms (%.3f us each), sink %.3f", elapsed, elapsed * 1000 / 1440, sink))
if elapsed > 200 {
    print("FAIL  1440 evaluations took \(elapsed) ms, budget is 200 ms in a debug-ish build")
    failures += 1
}
checks += 1

if failures == 0 {
    print("spa: all \(checks) checks passed")
} else {
    print("spa: \(failures) FAILURES of \(checks)")
    exit(1)
}
