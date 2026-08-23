import Foundation

// Eclipse.swift against published figures.
//
// Sources, all fetched rather than remembered:
//
// 1. NASA Five Millennium Catalog of Solar Eclipses, 1901 to 2000 and 2001 to
//    2100, Espenak and Meeus, NASA/TP 2006 214141.
//    https://eclipse.gsfc.nasa.gov/SEcat5/SE1901-2000.html
//    https://eclipse.gsfc.nasa.gov/SEcat5/SE2001-2100.html
//    Columns used: TD of greatest eclipse, gamma, eclipse magnitude, type.
//    The catalogue prints TD, so every comparison here is made in TD and delta
//    T never enters. Greatest eclipse is a purely geocentric instant, so this
//    is a clean comparison of ephemeris against ephemeris.
//
// 2. United States Naval Observatory solar eclipse computer, API version 4.0.1.
//    https://aa.usno.navy.mil/api/eclipses/solar/date?date=...&coords=...&height=...
//    Local circumstances in UT for a given place. Independent of NASA: it runs
//    on the USNO's own ephemeris and its own delta T, quoted in each response.
//
// 3. NASA Five Millennium Catalog of Lunar Eclipses, 2001 to 2100, Espenak and
//    Meeus, NASA/TP 2009 214173.
//    https://eclipse.gsfc.nasa.gov/LEcat5/LE2001-2100.html
//    Columns used: TD of greatest eclipse, type, penumbral magnitude, umbral
//    magnitude, and the durations of the penumbral, partial and total phases.
//    Shadow radii there follow Danjon's enlargement, documented at
//    https://eclipse.gsfc.nasa.gov/LEcat5/shadow.html, which is the convention
//    Eclipse.swift implements.
//
// 4. Geographic visibility strings from the same lunar catalogue and from the
//    NASA decade table https://eclipse.gsfc.nasa.gov/LEdecade/LEdecade2021.html
//
// Nothing below was produced by this implementation and then asserted against
// itself. Where no published number exists the check is an analytic identity
// that any correct implementation must satisfy.

var failures = 0, checks = 0

func check(_ label: String, _ got: Double, _ want: Double, _ tolerance: Double) {
    checks += 1
    if !(abs(got - want) <= tolerance) {
        print(String(format: "FAIL  %@: got %.6f, want %.6f, off by %.6f (tolerance %.6f)",
                     label, got, want, abs(got - want), tolerance))
        failures += 1
    }
}

func checkTrue(_ label: String, _ ok: Bool) {
    checks += 1
    if !ok { print("FAIL  \(label)"); failures += 1 }
}

func universalTime(_ year: Int, _ month: Int, _ day: Int,
                   _ hour: Int, _ minute: Int, _ second: Double) -> JulianDay {
    JulianDay.from(year: year, month: month,
                   day: Double(day) + (Double(hour) + Double(minute) / 60.0 + second / 3600.0) / 24.0)
}

func secondsBetween(_ a: JulianDay?, _ b: JulianDay) -> Double {
    guard let a else { return 1e9 }
    return (a.value - b.value) * 86400.0
}

func clock(_ jd: JulianDay?) -> String {
    guard let jd else { return "     none    " }
    let date = jd.calendarDate
    var fraction = (date.day - date.day.rounded(.down)) * 24.0
    let hour = fraction.rounded(.down)
    fraction = (fraction - hour) * 60.0
    let minute = fraction.rounded(.down)
    return String(format: "%02d:%02d:%05.2f", Int(hour), Int(minute), (fraction - minute) * 60.0)
}

// The tolerance the design document sets for contact times is one minute. The
// task sets two. Both are stated here; the checks use the tighter one, and the
// summary at the end prints the worst error actually seen.
let contactTolerance = 60.0
var worstSolarContact = 0.0
var worstSolarMaximum = 0.0
var worstLunarGreatest = 0.0
var worstLunarDuration = 0.0

// ---------------------------------------------------------------------------
// 1. The overlap area formula, against its analytic value.
// ---------------------------------------------------------------------------
// Two equal discs whose centres are one radius apart. The lens area is
// 2 r^2 acos(1/2) - (r/2) sqrt(3 r^2) = (2 pi / 3 - sqrt(3) / 2) r^2, so the
// covered fraction is that over pi, which is 0.391002. The magnitude of the
// same configuration is 0.5. The two numbers differ by more than a fifth of the
// disc, which is exactly why the module carries both.
check("equal discs, obscuration at magnitude 0.5",
      Eclipse.overlapFraction(separation: 1.0, covered: 1.0, coverer: 1.0),
      (2.0 * Double.pi / 3.0 - 3.0.squareRoot() / 2.0) / Double.pi, 1e-12)
check("disc fully covered", Eclipse.overlapFraction(separation: 0.1, covered: 1.0, coverer: 2.0), 1.0, 0)
check("discs apart", Eclipse.overlapFraction(separation: 3.1, covered: 1.0, coverer: 2.0), 0.0, 0)
// A small disc entirely inside a large one covers the ratio of the areas, which
// is the annular case.
check("annular ring", Eclipse.overlapFraction(separation: 0.1, covered: 1.0, coverer: 0.5), 0.25, 1e-12)
// Halving the separation must increase the covered area, monotonically.
var previousOverlap = -1.0
for step in stride(from: 2.0, through: 0.0, by: -0.05) {
    let value = Eclipse.overlapFraction(separation: step, covered: 1.0, coverer: 1.0)
    checkTrue("overlap grows as the discs close, at separation \(step)", value >= previousOverlap)
    previousOverlap = value
}

// ---------------------------------------------------------------------------
// 2. Solar eclipses, global circumstances, against the NASA catalogue.
// ---------------------------------------------------------------------------
struct GlobalFixture {
    let year: Int, month: Int, day: Int
    let hour: Int, minute: Int, second: Double   // TD of greatest eclipse
    let kind: Eclipse.SolarKind
    let gamma: Double
    let magnitude: Double                        // ratio of apparent diameters
}

// Catalogue rows, copied column by column:
//   09506  1999 Aug 11  11:04:09   64   -5  145  T  p-  0.5062  1.0286  45N  24E
//   09546  2017 Aug 21  18:26:40   70  218  145  T  p-  0.4367  1.0306  37N  88W
//   09561  2024 Apr 08  18:18:29   74  300  139  T  n-  0.3431  1.0566  25N 104W
//   09566  2026 Aug 12  17:47:06   75  329  126  T  -p  0.8977  1.0386  65N  25W
let globalFixtures = [
    GlobalFixture(year: 1999, month: 8, day: 11, hour: 11, minute: 4, second: 9,
                  kind: .total, gamma: 0.5062, magnitude: 1.0286),
    GlobalFixture(year: 2017, month: 8, day: 21, hour: 18, minute: 26, second: 40,
                  kind: .total, gamma: 0.4367, magnitude: 1.0306),
    GlobalFixture(year: 2024, month: 4, day: 8, hour: 18, minute: 18, second: 29,
                  kind: .total, gamma: 0.3431, magnitude: 1.0566),
    GlobalFixture(year: 2026, month: 8, day: 12, hour: 17, minute: 47, second: 6,
                  kind: .total, gamma: 0.8977, magnitude: 1.0386),
]

print("solar, global circumstances against the NASA five millennium catalogue")
print("  date          type    greatest TD    error s      gamma  error    ratio  error")
var worstGlobalTime = 0.0
for fixture in globalFixtures {
    let midnight = JulianDay.from(year: fixture.year, month: fixture.month, day: Double(fixture.day))
    let events = Eclipse.solarGlobalEvents(from: midnight.adding(days: -1),
                                           to: midnight.adding(days: 2))
    checkTrue("exactly one solar eclipse near \(fixture.year)-\(fixture.month)-\(fixture.day), got \(events.count)",
              events.count == 1)
    guard let event = events.first else { continue }

    // Compare in TD. The catalogue prints TD and greatest eclipse is geocentric,
    // so delta T cancels out of the comparison entirely.
    let computedTD = event.greatestEclipse.adding(seconds: DeltaT.seconds(julianDay: event.greatestEclipse))
    let publishedTD = universalTime(fixture.year, fixture.month, fixture.day,
                                    fixture.hour, fixture.minute, fixture.second)
    let error = secondsBetween(computedTD, publishedTD)
    worstGlobalTime = max(worstGlobalTime, abs(error))

    print(String(format: "  %04d-%02d-%02d   %-7@ %@  %+8.1f  %+8.4f %+7.4f  %6.4f %+6.4f",
                 fixture.year, fixture.month, fixture.day, event.kind.rawValue as NSString,
                 clock(computedTD), error,
                 event.gamma, event.gamma - fixture.gamma,
                 event.diameterRatio ?? -1, (event.diameterRatio ?? -1) - fixture.magnitude))

    checkTrue("\(fixture.year) eclipse type, got \(event.kind.rawValue)", event.kind == fixture.kind)
    check("\(fixture.year) greatest eclipse TD seconds", error, 0, contactTolerance)
    check("\(fixture.year) gamma", event.gamma, fixture.gamma, 0.001)
    check("\(fixture.year) ratio of apparent diameters", event.diameterRatio ?? -1, fixture.magnitude, 0.002)
}

// ---------------------------------------------------------------------------
// 3. Solar eclipses, local circumstances, against the USNO computer.
// ---------------------------------------------------------------------------
struct LocalFixture {
    let name: String
    let year: Int, month: Int, day: Int
    let latitude: Double, longitude: Double, elevation: Double
    let firstContact: (Int, Int, Double)
    let maximum: (Int, Int, Double)
    let lastContact: (Int, Int, Double)
    let kind: Eclipse.SolarKind
    let magnitude: Double
    let obscuration: Double
    let altitude: Double
}

// Every row is one USNO API response, verbatim. Times are UT.
let localFixtures = [
    LocalFixture(name: "Munich 1999", year: 1999, month: 8, day: 11,
                 latitude: 48.1372, longitude: 11.5756, elevation: 519,
                 firstContact: (9, 16, 23.5), maximum: (10, 38, 17.2), lastContact: (12, 1, 26.6),
                 kind: .total, magnitude: 1.009, obscuration: 1.0, altitude: 56.1),
    LocalFixture(name: "Madras OR 2017", year: 2017, month: 8, day: 21,
                 latitude: 44.6335, longitude: -121.1298, elevation: 683,
                 firstContact: (16, 6, 42.5), maximum: (17, 20, 34.1), lastContact: (18, 41, 3.1),
                 kind: .total, magnitude: 1.012, obscuration: 1.0, altitude: 41.6),
    LocalFixture(name: "New York 2017", year: 2017, month: 8, day: 21,
                 latitude: 40.7128, longitude: -74.0060, elevation: 10,
                 firstContact: (17, 23, 14.3), maximum: (18, 44, 57.4), lastContact: (20, 0, 42.8),
                 kind: .partial, magnitude: 0.770, obscuration: 0.716, altitude: 52.9),
    LocalFixture(name: "Los Angeles 2017", year: 2017, month: 8, day: 21,
                 latitude: 34.0522, longitude: -118.2437, elevation: 87,
                 firstContact: (16, 5, 43.9), maximum: (17, 21, 9.7), lastContact: (18, 44, 47.6),
                 kind: .partial, magnitude: 0.694, obscuration: 0.622, altitude: 48.4),
    LocalFixture(name: "Dallas TX 2024", year: 2024, month: 4, day: 8,
                 latitude: 32.77912, longitude: -96.80028, elevation: 131,
                 firstContact: (17, 23, 14.6), maximum: (18, 42, 32.9), lastContact: (20, 2, 35.5),
                 kind: .total, magnitude: 1.015, obscuration: 1.0, altitude: 64.6),
    LocalFixture(name: "New York 2024", year: 2024, month: 4, day: 8,
                 latitude: 40.7128, longitude: -74.0060, elevation: 10,
                 firstContact: (18, 10, 32.3), maximum: (19, 25, 30.1), lastContact: (20, 36, 19.3),
                 kind: .partial, magnitude: 0.911, obscuration: 0.899, altitude: 43.4),
    LocalFixture(name: "Reykjavik 2026", year: 2026, month: 8, day: 12,
                 latitude: 64.1466, longitude: -21.9426, elevation: 61,
                 firstContact: (16, 47, 9.8), maximum: (17, 48, 42.3), lastContact: (18, 47, 34.4),
                 kind: .total, magnitude: 1.002, obscuration: 1.0, altitude: 24.5),
]

print("")
print("solar, local circumstances against the USNO eclipse computer")
print("  place                type     C1 error  max error  C4 error   magnitude   obscuration   altitude")
for fixture in localFixtures {
    let place = Coordinates.Geographic(latitude: fixture.latitude,
                                       longitude: fixture.longitude,
                                       elevation: fixture.elevation)
    let noon = JulianDay.from(year: fixture.year, month: fixture.month, day: Double(fixture.day) + 0.5)
    let local = Eclipse.solarCircumstances(near: noon, place: place)

    checkTrue("\(fixture.name) type, got \(local.kind.rawValue)", local.kind == fixture.kind)
    guard local.kind != .none else { continue }

    let c1 = secondsBetween(local.firstContact,
                            universalTime(fixture.year, fixture.month, fixture.day,
                                          fixture.firstContact.0, fixture.firstContact.1,
                                          fixture.firstContact.2))
    let mx = secondsBetween(local.maximum,
                            universalTime(fixture.year, fixture.month, fixture.day,
                                          fixture.maximum.0, fixture.maximum.1, fixture.maximum.2))
    let c4 = secondsBetween(local.lastContact,
                            universalTime(fixture.year, fixture.month, fixture.day,
                                          fixture.lastContact.0, fixture.lastContact.1,
                                          fixture.lastContact.2))
    worstSolarContact = max(worstSolarContact, max(abs(c1), abs(c4)))
    worstSolarMaximum = max(worstSolarMaximum, abs(mx))

    print(String(format: "  %-20@ %-7@ %+8.1f  %+9.1f  %+8.1f   %6.4f%+7.4f   %6.4f%+7.4f  %5.1f%+5.1f",
                 fixture.name as NSString, local.kind.rawValue as NSString, c1, mx, c4,
                 local.magnitude, local.magnitude - fixture.magnitude,
                 local.obscuration, local.obscuration - fixture.obscuration,
                 local.maximumAltitude, local.maximumAltitude - fixture.altitude))

    check("\(fixture.name) first contact", c1, 0, contactTolerance)
    check("\(fixture.name) maximum", mx, 0, contactTolerance)
    check("\(fixture.name) last contact", c4, 0, contactTolerance)
    // USNO prints the magnitude to three places, so half a unit in the last
    // place is rounding and not error.
    check("\(fixture.name) magnitude", local.magnitude, fixture.magnitude, 0.006)
    check("\(fixture.name) obscuration", local.obscuration, fixture.obscuration, 0.02)
    check("\(fixture.name) sun altitude at maximum", local.maximumAltitude, fixture.altitude, 0.15)

    // The obscuration and the magnitude are different numbers, and for a
    // partial phase the obscuration is always the smaller of the two. If the
    // module ever returned one where the other was meant this would catch it.
    if local.kind == .partial {
        checkTrue("\(fixture.name) obscuration is below the magnitude",
                  local.obscuration < local.magnitude - 0.01)
    }
}

// ---------------------------------------------------------------------------
// 3b. An eclipse the Sun sets during.
// ---------------------------------------------------------------------------
// The USNO response for Madrid on 2026 Aug 12 lists three phenomena and not
// five: eclipse begins 17:36:42.4, maximum eclipse 18:32:18.5, and then
// "Sunset" at 19:16 where a fourth contact would otherwise stand. Magnitude
// 0.999, so Madrid misses totality by a hair. A module that clipped nothing
// would print a fourth contact nobody in Madrid could have seen; one that
// clipped too eagerly would drop the eclipse entirely.
print("")
print("an eclipse the sun sets during")
let madrid = Coordinates.Geographic(latitude: 40.4168, longitude: -3.7038, elevation: 667)
let august12 = JulianDay.from(year: 2026, month: 8, day: 12.0)
let madridEclipse = Eclipse.solarCircumstances(near: august12.adding(days: 0.5), place: madrid)
print("  Madrid: \(madridEclipse.kind.rawValue), C1 \(clock(madridEclipse.firstContact)), max \(clock(madridEclipse.maximum)), C4 \(clock(madridEclipse.lastContact))")
print(String(format: "          magnitude %.4f, obscuration %.4f, sun altitude at maximum %.1f",
             madridEclipse.magnitude, madridEclipse.obscuration, madridEclipse.maximumAltitude))
checkTrue("Madrid 2026 is partial, got \(madridEclipse.kind.rawValue)", madridEclipse.kind == .partial)
check("Madrid 2026 first contact",
      secondsBetween(madridEclipse.firstContact, universalTime(2026, 8, 12, 17, 36, 42.4)),
      0, contactTolerance)
check("Madrid 2026 maximum",
      secondsBetween(madridEclipse.maximum, universalTime(2026, 8, 12, 18, 32, 18.5)),
      0, contactTolerance)
check("Madrid 2026 magnitude", madridEclipse.magnitude, 0.999, 0.006)
check("Madrid 2026 sun altitude at maximum", madridEclipse.maximumAltitude, 7.2, 0.15)
checkTrue("Madrid 2026 reports no fourth contact, because the sun sets first",
          madridEclipse.lastContact == nil)
// And it is still listed as an event of that day, which is the half of the
// horizon rule that the negative cases below cannot check.
checkTrue("Madrid 2026 is listed among that day's events",
          Eclipse.solarEvents(from: august12, to: august12.adding(days: 1), place: madrid).count == 1)

// ---------------------------------------------------------------------------
// 4. The negative cases.
// ---------------------------------------------------------------------------
// The USNO computer answers both of these with
//   {"error": "Eclipse not visible from selected location. ..."}
// so a module that returns an eclipse here has invented it.
print("")
print("negative cases")
struct Absent { let name: String; let year: Int, month: Int, day: Int
                let latitude: Double, longitude: Double, elevation: Double }
let absent = [
    Absent(name: "Berlin, 2017 Aug 21", year: 2017, month: 8, day: 21,
           latitude: 52.5200, longitude: 13.4050, elevation: 34),
    Absent(name: "Sydney, 2024 Apr 08", year: 2024, month: 4, day: 8,
           latitude: -33.8688, longitude: 151.2093, elevation: 58),
]
for case_ in absent {
    let place = Coordinates.Geographic(latitude: case_.latitude,
                                       longitude: case_.longitude,
                                       elevation: case_.elevation)
    let noon = JulianDay.from(year: case_.year, month: case_.month, day: Double(case_.day) + 0.5)
    let local = Eclipse.solarCircumstances(near: noon, place: place)
    print("  \(case_.name): kind \(local.kind.rawValue), magnitude \(String(format: "%.4f", local.magnitude))")
    checkTrue("\(case_.name) reports no eclipse, got \(local.kind.rawValue)", local.kind == .none)
    checkTrue("\(case_.name) reports no contact times",
              local.firstContact == nil && local.lastContact == nil)

    let dayStart = JulianDay.from(year: case_.year, month: case_.month, day: Double(case_.day))
    let listed = Eclipse.solarEvents(from: dayStart, to: dayStart.adding(days: 1), place: place)
    checkTrue("\(case_.name) is not listed among that day's events, got \(listed.count)",
              listed.isEmpty)
}

// The same day at a place that did see it must still be listed, otherwise the
// negative test above would pass for a module that never returns anything.
let madras = Coordinates.Geographic(latitude: 44.6335, longitude: -121.1298, elevation: 683)
let august21 = JulianDay.from(year: 2017, month: 8, day: 21.0)
checkTrue("Madras does see the 2017 eclipse on the same query",
          Eclipse.solarEvents(from: august21, to: august21.adding(days: 1), place: madras).count == 1)

// ---------------------------------------------------------------------------
// 5. Lunar eclipses, against the NASA catalogue.
// ---------------------------------------------------------------------------
struct LunarFixture {
    let name: String
    let year: Int, month: Int, day: Int
    let hour: Int, minute: Int, second: Double   // TD of greatest eclipse
    let kind: Eclipse.LunarKind
    let penumbralMagnitude: Double
    let umbralMagnitude: Double
    let penumbralMinutes: Double
    let partialMinutes: Double?
    let totalMinutes: Double?
}

// Catalogue rows, copied column by column. Columns are
//   number date TD deltaT luna saros type qse gamma penMag umbMag penDur parDur totDur lat long
//   09691  2018 Jul 27  20:22:54  71  229  129  T+ pp  0.1168 2.6792 1.6087 373.8 234.5 103.0
//   09692  2019 Jan 21  05:13:27  71  235  134  T  p-  0.3684 2.1684 1.1953 311.5 196.8  62.0
//   09700  2022 May 16  04:12:42  73  276  131  T- p- -0.2532 2.3726 1.4137 318.7 207.2  84.9
//   09702  2023 May 05  17:24:05  73  288  141  N  h- -1.0349 0.9636 -0.0457 257.5  -     -
//   09705  2024 Sep 18  02:45:25  74  305  118  P  -a -0.9792 1.0372  0.0848 246.3 62.8  -
//   09706  2025 Mar 14  06:59:56  75  311  123  T  -p  0.3484 2.2595 1.1784 362.6 218.3  65.4
let lunarFixtures = [
    LunarFixture(name: "2018 Jul 27 total", year: 2018, month: 7, day: 27,
                 hour: 20, minute: 22, second: 54, kind: .total,
                 penumbralMagnitude: 2.6792, umbralMagnitude: 1.6087,
                 penumbralMinutes: 373.8, partialMinutes: 234.5, totalMinutes: 103.0),
    LunarFixture(name: "2019 Jan 21 total", year: 2019, month: 1, day: 21,
                 hour: 5, minute: 13, second: 27, kind: .total,
                 penumbralMagnitude: 2.1684, umbralMagnitude: 1.1953,
                 penumbralMinutes: 311.5, partialMinutes: 196.8, totalMinutes: 62.0),
    LunarFixture(name: "2022 May 16 total", year: 2022, month: 5, day: 16,
                 hour: 4, minute: 12, second: 42, kind: .total,
                 penumbralMagnitude: 2.3726, umbralMagnitude: 1.4137,
                 penumbralMinutes: 318.7, partialMinutes: 207.2, totalMinutes: 84.9),
    LunarFixture(name: "2023 May 05 penumbral", year: 2023, month: 5, day: 5,
                 hour: 17, minute: 24, second: 5, kind: .penumbral,
                 penumbralMagnitude: 0.9636, umbralMagnitude: -0.0457,
                 penumbralMinutes: 257.5, partialMinutes: nil, totalMinutes: nil),
    LunarFixture(name: "2024 Sep 18 partial", year: 2024, month: 9, day: 18,
                 hour: 2, minute: 45, second: 25, kind: .partial,
                 penumbralMagnitude: 1.0372, umbralMagnitude: 0.0848,
                 penumbralMinutes: 246.3, partialMinutes: 62.8, totalMinutes: nil),
    LunarFixture(name: "2025 Mar 14 total", year: 2025, month: 3, day: 14,
                 hour: 6, minute: 59, second: 56, kind: .total,
                 penumbralMagnitude: 2.2595, umbralMagnitude: 1.1784,
                 penumbralMinutes: 362.6, partialMinutes: 218.3, totalMinutes: 65.4),
]

print("")
print("lunar circumstances against the NASA five millennium catalogue")
print("  eclipse                 type       greatest TD  error s   umbral mag      penumbral mag    P duration   U duration   T duration")
for fixture in lunarFixtures {
    // The place only decides the altitude, not the contact times, so a
    // geocentric stand in is used for the shadow geometry checks.
    let place = Coordinates.Geographic(latitude: 0, longitude: 0)
    let noon = JulianDay.from(year: fixture.year, month: fixture.month, day: Double(fixture.day) + 0.5)
    let local = Eclipse.lunarCircumstances(near: noon, place: place)

    checkTrue("\(fixture.name) type, got \(local.kind.rawValue)", local.kind == fixture.kind)
    guard let maximum = local.maximum else {
        checkTrue("\(fixture.name) has a maximum", false)
        continue
    }

    let computedTD = maximum.adding(seconds: DeltaT.seconds(julianDay: maximum))
    let publishedTD = universalTime(fixture.year, fixture.month, fixture.day,
                                    fixture.hour, fixture.minute, fixture.second)
    let error = secondsBetween(computedTD, publishedTD)
    worstLunarGreatest = max(worstLunarGreatest, abs(error))

    func minutes(_ begin: JulianDay?, _ end: JulianDay?) -> Double? {
        guard let begin, let end else { return nil }
        return (end.value - begin.value) * 1440.0
    }
    let penumbral = minutes(local.penumbralBegin, local.penumbralEnd)
    let partial = minutes(local.partialBegin, local.partialEnd)
    let total = minutes(local.totalBegin, local.totalEnd)

    print(String(format: "  %-22@  %-9@  %@  %+7.1f  %+7.4f%+8.4f  %+7.4f%+8.4f   %6.1f%+6.1f  %6.1f%+6.1f  %6.1f%+6.1f",
                 fixture.name as NSString, local.kind.rawValue as NSString, clock(computedTD), error,
                 local.umbralMagnitude, local.umbralMagnitude - fixture.umbralMagnitude,
                 local.penumbralMagnitude, local.penumbralMagnitude - fixture.penumbralMagnitude,
                 penumbral ?? -1, (penumbral ?? 0) - fixture.penumbralMinutes,
                 partial ?? -1, (partial ?? 0) - (fixture.partialMinutes ?? 0),
                 total ?? -1, (total ?? 0) - (fixture.totalMinutes ?? 0)))

    check("\(fixture.name) greatest eclipse TD seconds", error, 0, contactTolerance)
    check("\(fixture.name) umbral magnitude", local.umbralMagnitude, fixture.umbralMagnitude, 0.005)
    check("\(fixture.name) penumbral magnitude", local.penumbralMagnitude, fixture.penumbralMagnitude, 0.005)

    // The catalogue prints durations to a tenth of a minute, so a tolerance of
    // one minute on a phase lasting hours is one part in two hundred.
    check("\(fixture.name) penumbral duration", penumbral ?? -1, fixture.penumbralMinutes, 1.0)
    worstLunarDuration = max(worstLunarDuration, abs((penumbral ?? 0) - fixture.penumbralMinutes) * 60)
    if let published = fixture.partialMinutes {
        check("\(fixture.name) partial duration", partial ?? -1, published, 1.0)
        worstLunarDuration = max(worstLunarDuration, abs((partial ?? 0) - published) * 60)
    } else {
        checkTrue("\(fixture.name) has no partial phase", local.partialBegin == nil)
    }
    if let published = fixture.totalMinutes {
        check("\(fixture.name) total duration", total ?? -1, published, 1.0)
        worstLunarDuration = max(worstLunarDuration, abs((total ?? 0) - published) * 60)
    } else {
        checkTrue("\(fixture.name) has no total phase", local.totalBegin == nil)
    }

    // Ordering. Nothing published pins this down, but a set of contact times
    // out of order is a bug whatever the ephemeris says.
    let ordered = [local.penumbralBegin, local.partialBegin, local.totalBegin, local.maximum,
                   local.totalEnd, local.partialEnd, local.penumbralEnd].compactMap { $0 }
    checkTrue("\(fixture.name) contacts are in order",
              zip(ordered, ordered.dropFirst()).allSatisfy { $0.value <= $1.value })
}

// ---------------------------------------------------------------------------
// 6. Lunar local visibility, against the published geographic regions.
// ---------------------------------------------------------------------------
// The catalogue's visibility column for 2022 May 16 reads
//   "Americas, Europe, Africa"
// and for 2023 May 05
//   "Africa, Asia, Australia".
// The Moon must therefore be up at greatest eclipse in the named regions and
// down on the far side of the world.
print("")
print("lunar visibility against the published geographic regions")
struct Visibility { let name: String; let latitude: Double; let longitude: Double; let up: Bool }
let visibilityCases: [(fixtureName: String, year: Int, month: Int, day: Int, places: [Visibility])] = [
    ("2022 May 16, Americas Europe Africa", 2022, 5, 16, [
        Visibility(name: "Santiago", latitude: -33.4489, longitude: -70.6693, up: true),
        Visibility(name: "New York", latitude: 40.7128, longitude: -74.0060, up: true),
        Visibility(name: "Tokyo", latitude: 35.6762, longitude: 139.6503, up: false),
    ]),
    ("2023 May 05, Africa Asia Australia", 2023, 5, 5, [
        Visibility(name: "Nairobi", latitude: -1.2921, longitude: 36.8219, up: true),
        Visibility(name: "Sydney", latitude: -33.8688, longitude: 151.2093, up: true),
        Visibility(name: "New York", latitude: 40.7128, longitude: -74.0060, up: false),
    ]),
]
for testCase in visibilityCases {
    let noon = JulianDay.from(year: testCase.year, month: testCase.month,
                              day: Double(testCase.day) + 0.5)
    for place in testCase.places {
        let local = Eclipse.lunarCircumstances(
            near: noon,
            place: Coordinates.Geographic(latitude: place.latitude, longitude: place.longitude))
        let altitude = local.moonAltitudeAtMaximum
        print(String(format: "  %-38@ %-10@ moon altitude %+6.1f, expected %@",
                     testCase.fixtureName as NSString, place.name as NSString, altitude,
                     (place.up ? "up" : "down") as NSString))
        checkTrue("\(testCase.fixtureName): moon is \(place.up ? "up" : "down") at \(place.name), got \(altitude)",
                  (altitude > 0) == place.up)
    }
}

// At greatest eclipse the Moon sits within about one and a half degrees of the
// antisolar point, so its altitude has to mirror the Sun's. Parallax, the
// Moon's ecliptic latitude and refraction together account for at most a few
// degrees. Nothing published states this; it is an identity that has to hold.
let berlin = Coordinates.Geographic(latitude: 52.52, longitude: 13.405, elevation: 34)
for fixture in lunarFixtures {
    let noon = JulianDay.from(year: fixture.year, month: fixture.month, day: Double(fixture.day) + 0.5)
    let local = Eclipse.lunarCircumstances(near: noon, place: berlin)
    guard let maximum = local.maximum else { continue }
    let sun = SolarPositionSPA.evaluate(julianDay: maximum, place: berlin)
    let mirrored = local.moonAltitudeAtMaximum + sun.elevation
    checkTrue("\(fixture.name): eclipsed moon is opposite the sun at Berlin, mismatch \(mirrored)",
              abs(mirrored) < 4.0)
}

// ---------------------------------------------------------------------------
// 7. The search entry points.
// ---------------------------------------------------------------------------
print("")
print("search entry points")
// The next solar eclipse visible from Madras after new year 2017 is the one on
// 21 August, per the NASA catalogue: no other solar eclipse of 2017 has a track
// anywhere near North America.
if let next = Eclipse.nextSolar(after: JulianDay.from(year: 2017, month: 1, day: 1.0),
                                place: madras, searchYears: 1) {
    let date = next.maximum!.calendarDate
    print("  nextSolar at Madras from 2017 Jan 1: \(date.year)-\(date.month)-\(Int(date.day)) \(next.kind.rawValue)")
    checkTrue("nextSolar finds 2017 Aug 21 at Madras",
              date.year == 2017 && date.month == 8 && Int(date.day) == 21)
    checkTrue("nextSolar reports totality at Madras", next.kind == .total)
} else {
    checkTrue("nextSolar finds an eclipse at Madras", false)
}

// The next lunar eclipse after new year 2022 is 2022 May 16, from the same
// catalogue. There is no lunar eclipse between January and May of that year.
if let next = Eclipse.nextLunar(after: JulianDay.from(year: 2022, month: 1, day: 1.0),
                                place: berlin, searchYears: 1) {
    let date = next.maximum!.calendarDate
    print("  nextLunar from 2022 Jan 1: \(date.year)-\(date.month)-\(Int(date.day)) \(next.kind.rawValue)")
    checkTrue("nextLunar finds 2022 May 16",
              date.year == 2022 && date.month == 5 && Int(date.day) == 16)
    checkTrue("nextLunar reports a total eclipse", next.kind == .total)
} else {
    checkTrue("nextLunar finds an eclipse", false)
}

// The catalogue lists four lunar eclipses in 2022 and 2023 taken together:
// 2022 May 16, 2022 Nov 08, 2023 May 05 and 2023 Oct 28. Counting them is a
// check on the syzygy search rather than on the geometry: miss a full moon and
// this drops.
let lunar2022 = Eclipse.lunarEvents(from: JulianDay.from(year: 2022, month: 1, day: 1.0),
                                    to: JulianDay.from(year: 2024, month: 1, day: 1.0),
                                    place: berlin)
print("  lunar eclipses in 2022 and 2023: \(lunar2022.count)")
checkTrue("four lunar eclipses in 2022 and 2023, got \(lunar2022.count)", lunar2022.count == 4)

// And two solar eclipses in 2017, at 26 February and 21 August, of which
// exactly one reaches Madras.
let solar2017 = Eclipse.solarGlobalEvents(from: JulianDay.from(year: 2017, month: 1, day: 1.0),
                                          to: JulianDay.from(year: 2018, month: 1, day: 1.0))
print("  solar eclipses worldwide in 2017: \(solar2017.count) of kinds \(solar2017.map(\.kind.rawValue))")
checkTrue("two solar eclipses in 2017, got \(solar2017.count)", solar2017.count == 2)
checkTrue("the February 2017 eclipse is annular",
          solar2017.first(where: { $0.greatestEclipse.calendarDate.month == 2 })?.kind == .annular)

// Cost. Nothing in the design document budgets eclipse search, but a five year
// hunt is the worst thing the interface will ask for and the number belongs on
// the record rather than in someone's head.
let started = Date()
_ = Eclipse.nextSolar(after: JulianDay.from(year: 2026, month: 1, day: 1.0),
                      place: berlin, searchYears: 5)
let elapsed = Date().timeIntervalSince(started)

print("")
print(String(format: "nextSolar over five years at one place: %.0f ms", elapsed * 1000))
print(String(format: "worst greatest eclipse error, solar: %.1f s", worstGlobalTime))
print(String(format: "worst contact error, solar local:   %.1f s", worstSolarContact))
print(String(format: "worst maximum error, solar local:   %.1f s", worstSolarMaximum))
print(String(format: "worst greatest eclipse error, lunar: %.1f s", worstLunarGreatest))
print(String(format: "worst phase duration error, lunar:  %.1f s", worstLunarDuration))

if failures == 0 { print("eclipse: all \(checks) checks passed") }
else { print("eclipse: \(failures) FAILURES of \(checks)"); exit(1) }
