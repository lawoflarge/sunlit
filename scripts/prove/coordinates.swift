import Foundation

var failures = 0
func check(_ label: String, _ got: Double, _ want: Double, _ tol: Double) {
    let d = abs(got - want)
    if d > tol {
        print("FAIL  \(label): got \(got), want \(want), off by \(d)")
        failures += 1
    }
}
func checkTrue(_ label: String, _ condition: Bool) {
    if !condition {
        print("FAIL  \(label)")
        failures += 1
    }
}

// Meeus example 12.a. Mean sidereal time at Greenwich for 1987 April 10.0 UT
// is 13h10m46.3668s, which is 197.693195 degrees.
let jd12a = JulianDay.from(year: 1987, month: 4, day: 10.0)
check("JD 1987 Apr 10.0", jd12a.value, 2446895.5, 1e-9)
check("mean sidereal 12.a",
      Coordinates.meanSiderealTime(julianDay: jd12a),
      Angle.fromHours(13, 10, 46.3668), 1e-5)

// Meeus example 12.b. Same date at 19h21m00s UT gives 8h34m57.0896s.
let jd12b = JulianDay.from(year: 1987, month: 4, day: 10.0 + (19.0 + 21.0/60.0) / 24.0)
check("mean sidereal 12.b",
      Coordinates.meanSiderealTime(julianDay: jd12b),
      Angle.fromHours(8, 34, 57.0896), 1e-5)

// Meeus example 13.a. Venus seen from Washington on 1987 April 10 at
// 19h21m00s UT. Meeus reports azimuth measured from SOUTH; this module measures
// from north, so the expected value is his plus 180 degrees.
let venus = Coordinates.Equatorial(
    rightAscension: Angle.fromHours(23, 9, 16.641),
    declination: Angle.fromSexagesimal(-6, 43, 11.61))
let washingtonLatitude = Angle.fromSexagesimal(38, 55, 17.0)
let washingtonLongitude = -Angle.fromSexagesimal(77, 3, 56.0)   // west, so negative here
let theta = Coordinates.meanSiderealTime(julianDay: jd12b)
let h13a = Coordinates.hourAngle(apparentSiderealTime: theta,
                                 longitude: washingtonLongitude,
                                 rightAscension: venus.rightAscension)
check("hour angle 13.a", h13a, 64.352133, 0.002)

let seen = Coordinates.horizontal(equatorial: venus, hourAngle: h13a, latitude: washingtonLatitude)
check("azimuth 13.a (north-based)", seen.azimuth, 68.0337 + 180.0, 0.01)
check("altitude 13.a", seen.altitude, 15.1249, 0.01)

// Analytic cases. These do not depend on any published table, which is exactly
// why they are here: they would catch a sign error that a single worked example
// happens to be insensitive to.

// A body whose declination equals the observer's latitude, on the meridian, is
// at the zenith.
let zenith = Coordinates.horizontal(
    equatorial: Coordinates.Equatorial(rightAscension: 0, declination: 48.0),
    hourAngle: 0, latitude: 48.0)
check("zenith altitude", zenith.altitude, 90.0, 1e-9)

// On the meridian, north of the observer, the azimuth is due north.
let northOfMe = Coordinates.horizontal(
    equatorial: Coordinates.Equatorial(rightAscension: 0, declination: 70.0),
    hourAngle: 0, latitude: 48.0)
check("meridian north azimuth", northOfMe.azimuth, 0.0, 1e-6)
check("meridian north altitude", northOfMe.altitude, 68.0, 1e-9)

// On the meridian, south of the observer, the azimuth is due south.
let southOfMe = Coordinates.horizontal(
    equatorial: Coordinates.Equatorial(rightAscension: 0, declination: 10.0),
    hourAngle: 0, latitude: 48.0)
check("meridian south azimuth", southOfMe.azimuth, 180.0, 1e-6)
check("meridian south altitude", southOfMe.altitude, 52.0, 1e-9)

// A body on the celestial equator crosses the horizon exactly due east and due
// west, at every latitude. Hour angle -90 is six hours before transit, so it is
// rising in the east.
for latitude in [-60.0, -23.5, 0.0, 12.3, 48.0, 66.0] {
    let rising = Coordinates.horizontal(
        equatorial: Coordinates.Equatorial(rightAscension: 0, declination: 0),
        hourAngle: -90, latitude: latitude)
    let setting = Coordinates.horizontal(
        equatorial: Coordinates.Equatorial(rightAscension: 0, declination: 0),
        hourAngle: 90, latitude: latitude)
    check("equator rises east at lat \(latitude)", rising.azimuth, 90.0, 1e-6)
    check("equator sets west at lat \(latitude)", setting.azimuth, 270.0, 1e-6)
    check("equator alt zero rising at lat \(latitude)", rising.altitude, 0.0, 1e-9)
}

// Southern hemisphere. On the meridian the sun is to the NORTH, so an equatorial
// body seen from -35 latitude transits at azimuth 0, not 180. This is the case a
// northern-hemisphere developer gets wrong and never notices.
let southern = Coordinates.horizontal(
    equatorial: Coordinates.Equatorial(rightAscension: 0, declination: 0),
    hourAngle: 0, latitude: -35.0)
check("southern transit azimuth", southern.azimuth, 0.0, 1e-6)
check("southern transit altitude", southern.altitude, 55.0, 1e-9)

// Meeus example 21.b, the precession half. Theta Persei, already corrected for
// proper motion to the epoch, precessed from J2000 to 2028 November 13.19 TD.
let thetaPersei = Coordinates.Equatorial(
    rightAscension: Angle.fromHours(2, 44, 12.975),
    declination: Angle.fromSexagesimal(49, 13, 39.90))
let precessed = Coordinates.precessFromJ2000(thetaPersei, to: JulianDay(2462088.69))
check("precession 21.b right ascension", precessed.rightAscension, Angle.fromHours(2, 46, 11.331), 3e-4)
check("precession 21.b declination", precessed.declination, Angle.fromSexagesimal(49, 20, 54.54), 3e-4)

// Precessing to J2000 itself must be the identity.
let unmoved = Coordinates.precessFromJ2000(thetaPersei, to: JulianDay.j2000)
check("precession identity ra", unmoved.rightAscension, thetaPersei.rightAscension, 1e-12)
check("precession identity dec", unmoved.declination, thetaPersei.declination, 1e-12)

// Galactic coordinates. Sagittarius A* sits within a twentieth of a degree of
// the galactic origin by construction, so this checks the pole constants and the
// direction of the transformation at once.
let sgrA = Coordinates.Equatorial(rightAscension: 266.41681, declination: -29.00775)
let galactic = Coordinates.galacticFromEquatorial(sgrA)
checkTrue("Sgr A* galactic longitude near zero",
          abs(Angle.normalizedSigned(galactic.longitude)) < 0.1)
checkTrue("Sgr A* galactic latitude near zero", abs(galactic.latitude) < 0.1)

// Round trip in both directions.
for (l, b) in [(0.0, 0.0), (90.0, 30.0), (210.0, -45.0), (359.0, 5.0)] {
    let eq = Coordinates.equatorialFromGalactic(longitude: l, latitude: b)
    let back = Coordinates.galacticFromEquatorial(eq)
    check("galactic round trip l=\(l)", Angle.normalizedSigned(back.longitude - l), 0.0, 1e-9)
    check("galactic round trip b=\(b)", back.latitude, b, 1e-9)
}

// The north galactic pole must map to declination +27.12825 by definition.
let ngp = Coordinates.equatorialFromGalactic(longitude: 0, latitude: 90)
check("north galactic pole declination", ngp.declination, 27.12825, 1e-9)
check("north galactic pole right ascension", ngp.rightAscension, 192.85948, 1e-6)

// Refraction. The familiar "about 34 arcminutes at the horizon" figure is the
// correction at APPARENT altitude zero, which is Bennett's formula. At TRUE
// altitude zero the correction is smaller, near 29 arcminutes, because the body
// is already being lifted. Conflating the two is the classic error here, so both
// directions are pinned separately.
check("Bennett at apparent altitude zero",
      Angle.toArcminutes(Refraction.trueFromApparent(apparentAltitude: 0)), 34.5, 0.5)
check("Saemundsson at true altitude zero",
      Angle.toArcminutes(Refraction.apparentFromTrue(trueAltitude: 0)), 29.0, 0.5)
// The two must agree at the point that defines sunrise: a body at true altitude
// -0.5667 degrees appears exactly on the horizon.
check("horizon refraction is self consistent",
      -Refraction.horizontalRefraction
        + Refraction.apparentFromTrue(trueAltitude: -Refraction.horizontalRefraction),
      0.0, 0.02)
check("standard sunrise altitude", Refraction.sunriseAltitude, -0.8333, 1e-3)
checkTrue("refraction shrinks with altitude",
          Refraction.apparentFromTrue(trueAltitude: 45) < Refraction.apparentFromTrue(trueAltitude: 5))
check("refraction near zenith",
      Angle.toArcminutes(Refraction.apparentFromTrue(trueAltitude: 89.9)), 0.0, 0.02)

// The two formulae are inverses of each other to within their stated accuracy.
for trueAltitude in [0.5, 2.0, 10.0, 30.0, 60.0, 85.0] {
    let apparent = trueAltitude + Refraction.apparentFromTrue(trueAltitude: trueAltitude)
    let back = apparent - Refraction.trueFromApparent(apparentAltitude: apparent)
    check("refraction inverse at \(trueAltitude)", back, trueAltitude, 0.02)
}

// Pressure falls with elevation. Denver at 1609 m should read near 833 mbar.
check("pressure at 1609 m", Refraction.pressure(atElevation: 1609), 833.0, 5.0)
check("pressure at sea level", Refraction.pressure(atElevation: 0), 1010.0, 1e-9)

if failures == 0 {
    print("coordinates: all checks passed")
} else {
    print("coordinates: \(failures) FAILURES")
    exit(1)
}
