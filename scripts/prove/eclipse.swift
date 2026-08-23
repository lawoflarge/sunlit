import Foundation

// Eclipse.swift against published figures.
//
// Sources, all fetched from the publisher rather than remembered, and every
// row below copied column by column out of the response:
//
// 1. NASA Five Millennium Catalog of Solar Eclipses, Espenak and Meeus,
//    NASA/TP 2006 214141.
//    https://eclipse.gsfc.nasa.gov/SEcat5/SE1901-2000.html
//    https://eclipse.gsfc.nasa.gov/SEcat5/SE2001-2100.html
//    Columns used: TD of greatest eclipse, eclipse type, gamma, eclipse
//    magnitude. The key at
//    https://eclipse.gsfc.nasa.gov/SEcat5/SEcatkey.html states that for
//    annular, total and hybrid eclipses the magnitude column "is actually the
//    diameter ratio of Moon/Sun", which is why it is compared against
//    SolarGlobal.diameterRatio and not against any magnitude.
//    The catalogue prints TD, so every comparison here is made in TD and delta
//    T never enters: the module derives its own TD from the same DeltaT series
//    it is handed back, so the term cancels exactly. Greatest eclipse is a
//    purely geocentric instant, so this is ephemeris against ephemeris.
//
// 2. United States Naval Observatory solar eclipse computer, API version 4.0.1.
//    https://aa.usno.navy.mil/api/eclipses/solar/date?date=...&coords=...&height=...
//    Local circumstances in UT for a given place, on the USNO's own ephemeris
//    and its own delta T, both quoted in each response.
//
//    Two conventions in that response had to be established before its numbers
//    could be compared with anything, and both were established from the
//    response itself rather than assumed:
//
//    a. The altitude column is the GEOMETRIC altitude, refraction excluded.
//       Toronto on 2021 Jun 10 proves it: the response gives sunrise at 09:36,
//       maximum eclipse at 09:39:58.0 with altitude -0.2, and eclipse ends at
//       10:37:55.3 with altitude 9.0. The last two points fix a rate of
//       0.1587 degrees a minute, and extrapolating the ramp back to -0.8333,
//       the true altitude at which the upper limb sits on the horizon, lands
//       on 09:36.0, the quoted sunrise. An apparent altitude would have read
//       about +0.31 at maximum and would have crossed zero minutes earlier.
//       Every altitude fixture below is therefore converted with
//       Refraction.apparentFromTrue before being compared with the module,
//       which reports the apparent altitude. That conversion is a stated
//       change of convention and not a recomputation of the quantity under
//       test: it enters both sides as very nearly the same additive term, so
//       what the check really compares is the module's unrefracted altitude
//       against the USNO's.
//
//    b. The top level "magnitude" and "obscuration" fields are the values at
//       the geometric maximum, whether or not the Sun was above the horizon
//       then. Where the maximum happened below the horizon they are therefore
//       not the same quantity the module returns, which is the greatest phase
//       actually seen. Those places are tested in their own section and their
//       magnitude is deliberately not asserted against the USNO field.
//
// 3. NASA Five Millennium Catalog of Lunar Eclipses, Espenak and Meeus,
//    NASA/TP 2009 214173.
//    https://eclipse.gsfc.nasa.gov/LEcat5/LE1901-2000.html
//    https://eclipse.gsfc.nasa.gov/LEcat5/LE2001-2100.html
//    Columns used: TD of greatest eclipse, type, penumbral magnitude, umbral
//    magnitude, and the durations of the penumbral, partial and total phases.
//    Shadow radii there follow Danjon's enlargement, documented at
//    https://eclipse.gsfc.nasa.gov/LEcat5/shadow.html, which is the convention
//    Eclipse.swift implements.
//
// 4. Geographic visibility strings from the same lunar catalogue.
//
// Nothing below was produced by this implementation and then asserted against
// itself. Where no published number exists the check is an identity that any
// correct implementation must satisfy.

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
    guard let jd else { return "    none    " }
    let date = jd.calendarDate
    var fraction = (date.day - date.day.rounded(.down)) * 24.0
    let hour = fraction.rounded(.down)
    fraction = (fraction - hour) * 60.0
    let minute = fraction.rounded(.down)
    return String(format: "%02d %02d:%02d:%05.2f",
                  Int(date.day), Int(hour), Int(minute), (fraction - minute) * 60.0)
}

/// The USNO altitude column is geometric. The module reports the apparent
/// altitude. See note 2a in the header.
func apparent(_ geometric: Double, elevation: Double) -> Double {
    geometric + Refraction.apparentFromTrue(
        trueAltitude: geometric, pressure: Refraction.pressure(atElevation: elevation))
}

// The tolerance the design document sets for contact times is one minute. The
// checks use it and the summary at the end prints the worst error actually
// seen, so a regression that stays inside the tolerance is still visible.
let contactTolerance = 60.0
var worstGlobalTime = 0.0
var worstSolarContact = 0.0
var worstSolarMaximum = 0.0
var worstSolarMagnitude = 0.0
var worstSolarObscuration = 0.0
var worstSolarAltitude = 0.0
var worstGamma = 0.0
var worstRatio = 0.0
var worstLunarGreatest = 0.0
var worstLunarDuration = 0.0
var worstLunarMagnitude = 0.0

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
    let catalogueType: String                    // the catalogue's own letter
    let kind: Eclipse.SolarKind                  // what this module must report
    let gamma: Double
    let ratio: Double?                           // nil where the axis misses
}

// Twenty four events spanning 1990 to 2035, taken as whole catalogue rows.
// The set is chosen so that no single sign, branch or magnitude regime is
// carried by one case alone:
//
//   eight rows have gamma below zero, which is the only thing that can catch a
//     module returning the unsigned miss distance;
//   nine are annular, so the annular branch of the classification and of the
//     ratio is exercised by published values rather than by hope;
//   three are purely partial, where the axis misses the Earth and the ratio is
//     undefined, which exercises the guard that returns nil;
//   two are hybrid, which this module cannot name, see the note below;
//   1991 Jul 11 has gamma -0.0041, an axis through the centre of the Earth to
//     four parts in ten thousand, and 1990 Jan 26 has gamma -0.9457, an axis
//     that grazes the limb.
//
// Catalogue rows, copied column by column. Columns are
//   number  date  TD  deltaT  luna  saros  type  qse  gamma  magnitude ...
//   09486  1990 Jan 26  19:31:24  57  -123  121  A   -t  -0.9457  0.9670
//   09489  1991 Jul 11  19:07:01  58  -105  136  Tm  nn  -0.0041  1.0800
//   09493  1993 May 21  14:20:15  59   -82  118  P   -t   1.1372  0.7352
//   09495  1994 May 10  17:12:26  60   -70  128  A   -p   0.4077  0.9431
//   09503  1998 Feb 26  17:29:27  63   -23  130  T   -n   0.2391  1.0441
//   09506  1999 Aug 11  11:04:09  64    -5  145  T   p-   0.5062  1.0286
//   09511  2001 Jun 21  12:04:46  64    18  127  T   -p  -0.5701  1.0495
//   09519  2005 Apr 08  20:36:51  65    65  129  H   -n  -0.3473  1.0074
//   09520  2005 Oct 03  10:32:47  65    71  134  A   -p   0.3306  0.9576
//   09535  2012 May 20  23:53:54  68   153  128  A   -p   0.4828  0.9439
//   09544  2016 Sep 01  09:08:02  70   206  135  A   -n  -0.3330  0.9736
//   09545  2017 Feb 26  14:54:33  70   212  140  A   n-  -0.4578  0.9922
//   09546  2017 Aug 21  18:26:40  70   218  145  T   p-   0.4367  1.0306
//   09549  2018 Aug 11  09:47:28  71   230  155  P   t-   1.1476  0.7368
//   09553  2020 Jun 21  06:41:15  72   253  137  Am  nn   0.1209  0.9940
//   09558  2022 Oct 25  11:01:20  73   282  124  P   -t   1.0701  0.8619
//   09559  2023 Apr 20  04:17:56  73   288  129  H   -n  -0.3952  1.0132
//   09560  2023 Oct 14  18:00:41  74   294  134  A   -p   0.3753  0.9520
//   09561  2024 Apr 08  18:18:29  74   300  139  T   n-   0.3431  1.0566
//   09566  2026 Aug 12  17:47:06  75   329  126  T   -p   0.8977  1.0386
//   09568  2027 Aug 02  10:07:50  76   341  136  T   nn   0.1421  1.0790
//   09570  2028 Jul 22  02:56:40  77   353  146  T   p-  -0.6056  1.0560
//   09576  2030 Nov 25  06:51:37  78   382  133  T   -n  -0.3867  1.0468
//   09586  2035 Sep 02  01:56:46  81   441  145  T   p-   0.3727  1.0320
//
// The two hybrid rows are expected back as total, and that is the module's
// documented behaviour rather than a tolerated error: SolarGlobal.kind
// describes the character at greatest eclipse, and a hybrid eclipse is total
// there by construction, since the catalogue's magnitude column exceeds one at
// exactly that instant. The annular ends of its path are a fact about the path
// and not about the instant this structure describes.
let globalFixtures = [
    GlobalFixture(year: 1990, month: 1, day: 26, hour: 19, minute: 31, second: 24,
                  catalogueType: "A", kind: .annular, gamma: -0.9457, ratio: 0.9670),
    GlobalFixture(year: 1991, month: 7, day: 11, hour: 19, minute: 7, second: 1,
                  catalogueType: "Tm", kind: .total, gamma: -0.0041, ratio: 1.0800),
    GlobalFixture(year: 1993, month: 5, day: 21, hour: 14, minute: 20, second: 15,
                  catalogueType: "P", kind: .partial, gamma: 1.1372, ratio: nil),
    GlobalFixture(year: 1994, month: 5, day: 10, hour: 17, minute: 12, second: 26,
                  catalogueType: "A", kind: .annular, gamma: 0.4077, ratio: 0.9431),
    GlobalFixture(year: 1998, month: 2, day: 26, hour: 17, minute: 29, second: 27,
                  catalogueType: "T", kind: .total, gamma: 0.2391, ratio: 1.0441),
    GlobalFixture(year: 1999, month: 8, day: 11, hour: 11, minute: 4, second: 9,
                  catalogueType: "T", kind: .total, gamma: 0.5062, ratio: 1.0286),
    GlobalFixture(year: 2001, month: 6, day: 21, hour: 12, minute: 4, second: 46,
                  catalogueType: "T", kind: .total, gamma: -0.5701, ratio: 1.0495),
    GlobalFixture(year: 2005, month: 4, day: 8, hour: 20, minute: 36, second: 51,
                  catalogueType: "H", kind: .total, gamma: -0.3473, ratio: 1.0074),
    GlobalFixture(year: 2005, month: 10, day: 3, hour: 10, minute: 32, second: 47,
                  catalogueType: "A", kind: .annular, gamma: 0.3306, ratio: 0.9576),
    GlobalFixture(year: 2012, month: 5, day: 20, hour: 23, minute: 53, second: 54,
                  catalogueType: "A", kind: .annular, gamma: 0.4828, ratio: 0.9439),
    GlobalFixture(year: 2016, month: 9, day: 1, hour: 9, minute: 8, second: 2,
                  catalogueType: "A", kind: .annular, gamma: -0.3330, ratio: 0.9736),
    GlobalFixture(year: 2017, month: 2, day: 26, hour: 14, minute: 54, second: 33,
                  catalogueType: "A", kind: .annular, gamma: -0.4578, ratio: 0.9922),
    GlobalFixture(year: 2017, month: 8, day: 21, hour: 18, minute: 26, second: 40,
                  catalogueType: "T", kind: .total, gamma: 0.4367, ratio: 1.0306),
    GlobalFixture(year: 2018, month: 8, day: 11, hour: 9, minute: 47, second: 28,
                  catalogueType: "P", kind: .partial, gamma: 1.1476, ratio: nil),
    GlobalFixture(year: 2020, month: 6, day: 21, hour: 6, minute: 41, second: 15,
                  catalogueType: "Am", kind: .annular, gamma: 0.1209, ratio: 0.9940),
    GlobalFixture(year: 2022, month: 10, day: 25, hour: 11, minute: 1, second: 20,
                  catalogueType: "P", kind: .partial, gamma: 1.0701, ratio: nil),
    GlobalFixture(year: 2023, month: 4, day: 20, hour: 4, minute: 17, second: 56,
                  catalogueType: "H", kind: .total, gamma: -0.3952, ratio: 1.0132),
    GlobalFixture(year: 2023, month: 10, day: 14, hour: 18, minute: 0, second: 41,
                  catalogueType: "A", kind: .annular, gamma: 0.3753, ratio: 0.9520),
    GlobalFixture(year: 2024, month: 4, day: 8, hour: 18, minute: 18, second: 29,
                  catalogueType: "T", kind: .total, gamma: 0.3431, ratio: 1.0566),
    GlobalFixture(year: 2026, month: 8, day: 12, hour: 17, minute: 47, second: 6,
                  catalogueType: "T", kind: .total, gamma: 0.8977, ratio: 1.0386),
    GlobalFixture(year: 2027, month: 8, day: 2, hour: 10, minute: 7, second: 50,
                  catalogueType: "T", kind: .total, gamma: 0.1421, ratio: 1.0790),
    GlobalFixture(year: 2028, month: 7, day: 22, hour: 2, minute: 56, second: 40,
                  catalogueType: "T", kind: .total, gamma: -0.6056, ratio: 1.0560),
    GlobalFixture(year: 2030, month: 11, day: 25, hour: 6, minute: 51, second: 37,
                  catalogueType: "T", kind: .total, gamma: -0.3867, ratio: 1.0468),
    GlobalFixture(year: 2035, month: 9, day: 2, hour: 1, minute: 56, second: 46,
                  catalogueType: "T", kind: .total, gamma: 0.3727, ratio: 1.0320),
]

print("solar, global circumstances against the NASA five millennium catalogue")
print("  date          cat  got        greatest TD    error s      gamma  error    ratio  error")
for fixture in globalFixtures {
    let midnight = JulianDay.from(year: fixture.year, month: fixture.month, day: Double(fixture.day))
    let events = Eclipse.solarGlobalEvents(from: midnight.adding(days: -1),
                                           to: midnight.adding(days: 2))
    checkTrue("exactly one solar eclipse near \(fixture.year)-\(fixture.month)-\(fixture.day), got \(events.count)",
              events.count == 1)
    guard let event = events.first else { continue }

    let computedTD = event.greatestEclipse.adding(seconds: DeltaT.seconds(julianDay: event.greatestEclipse))
    let publishedTD = universalTime(fixture.year, fixture.month, fixture.day,
                                    fixture.hour, fixture.minute, fixture.second)
    let error = secondsBetween(computedTD, publishedTD)
    worstGlobalTime = max(worstGlobalTime, abs(error))
    worstGamma = max(worstGamma, abs(event.gamma - fixture.gamma))
    if let published = fixture.ratio, let got = event.diameterRatio {
        worstRatio = max(worstRatio, abs(got - published))
    }

    print(String(format: "  %04d-%02d-%02d   %-3@  %-9@  %@  %+8.1f  %+8.4f %+7.4f  %6.4f %+6.4f",
                 fixture.year, fixture.month, fixture.day,
                 fixture.catalogueType as NSString, event.kind.rawValue as NSString,
                 clock(computedTD), error,
                 event.gamma, event.gamma - fixture.gamma,
                 event.diameterRatio ?? -1, (event.diameterRatio ?? -1) - (fixture.ratio ?? -1)))

    checkTrue("\(fixture.year)-\(fixture.month) eclipse type, got \(event.kind.rawValue)",
              event.kind == fixture.kind)
    check("\(fixture.year)-\(fixture.month) greatest eclipse TD seconds", error, 0, contactTolerance)
    // Signed, so an implementation returning the unsigned miss distance fails
    // on the eight rows whose gamma is negative.
    check("\(fixture.year)-\(fixture.month) gamma", event.gamma, fixture.gamma, 0.001)
    if let published = fixture.ratio {
        checkTrue("\(fixture.year)-\(fixture.month) has a diameter ratio", event.diameterRatio != nil)
        check("\(fixture.year)-\(fixture.month) ratio of apparent diameters",
              event.diameterRatio ?? -1, published, 0.001)
        // The classification and the ratio have to agree with each other, not
        // only with the catalogue.
        checkTrue("\(fixture.year)-\(fixture.month) ratio above one exactly when total",
                  (event.diameterRatio! >= 1) == (event.kind == .total))
    } else {
        // The axis misses the Earth, so there is no point on the surface at
        // which to take a ratio and the module must say so rather than invent
        // one.
        checkTrue("\(fixture.year)-\(fixture.month) has no diameter ratio", event.diameterRatio == nil)
        checkTrue("\(fixture.year)-\(fixture.month) with the axis outside the Earth is partial",
                  event.kind == .partial)
        checkTrue("\(fixture.year)-\(fixture.month) gamma exceeds one when the axis misses",
                  abs(event.gamma) > 1)
    }
}

// ---------------------------------------------------------------------------
// 2b. A census of two whole decades against the catalogue.
// ---------------------------------------------------------------------------
// Counting is what tests the syzygy search and the rejection threshold rather
// than the geometry. Miss a new moon and the count drops; accept a shadow that
// never touches the Earth and it rises. The counts are the number of rows the
// catalogues carry in each interval, taken from the same pages.
print("")
print("census against the catalogues")
for (start, end, published, label) in [(2000, 2010, 22, "solar"), (2030, 2040, 22, "solar")] {
    let got = Eclipse.solarGlobalEvents(from: JulianDay.from(year: start, month: 1, day: 1.0),
                                        to: JulianDay.from(year: end, month: 1, day: 1.0)).count
    print("  \(label) eclipses \(start) to \(end): got \(got), catalogue \(published)")
    checkTrue("\(label) eclipse count \(start) to \(end), got \(got) want \(published)", got == published)
}
let census = Coordinates.Geographic(latitude: 0, longitude: 0)
for (start, end, published) in [(2000, 2010, 24), (2030, 2040, 23)] {
    let got = Eclipse.lunarEvents(from: JulianDay.from(year: start, month: 1, day: 1.0),
                                  to: JulianDay.from(year: end, month: 1, day: 1.0),
                                  place: census).count
    print("  lunar eclipses \(start) to \(end): got \(got), catalogue \(published)")
    checkTrue("lunar eclipse count \(start) to \(end), got \(got) want \(published)", got == published)
}

// ---------------------------------------------------------------------------
// 3. Solar eclipses, local circumstances, against the USNO computer.
// ---------------------------------------------------------------------------
struct LocalFixture {
    let name: String
    let year: Int, month: Int, day: Int      // the UT date the response carries
    let latitude: Double, longitude: Double, elevation: Double
    /// Nil where the response shows "Sunrise" in place of a first contact.
    let firstContact: (Int, Int, Double)?
    let maximum: (Int, Int, Double)
    /// Nil where the response shows "Sunset" in place of a last contact.
    let lastContact: (Int, Int, Double)?
    let kind: Eclipse.SolarKind
    let magnitude: Double
    let obscuration: Double
    /// The response's altitude column, which is geometric. See note 2a.
    let geometricAltitude: Double
}

// Twenty four responses across ten eclipses. Nine are total, six annular and
// nine partial; six lose a contact to the horizon; and the lowest Sun among
// them stands at -0.2 degrees, where the difference between a geometric and an
// apparent altitude is larger than the whole tolerance.
let localFixtures = [
    LocalFixture(name: "Munich 1999 T", year: 1999, month: 8, day: 11,
                 latitude: 48.1372, longitude: 11.5756, elevation: 519,
                 firstContact: (9, 16, 23.5), maximum: (10, 38, 17.2), lastContact: (12, 1, 26.6),
                 kind: .total, magnitude: 1.009, obscuration: 1.0, geometricAltitude: 56.1),
    LocalFixture(name: "Madras OR 2017 T", year: 2017, month: 8, day: 21,
                 latitude: 44.6335, longitude: -121.1298, elevation: 683,
                 firstContact: (16, 6, 42.5), maximum: (17, 20, 34.1), lastContact: (18, 41, 3.1),
                 kind: .total, magnitude: 1.012, obscuration: 1.0, geometricAltitude: 41.6),
    LocalFixture(name: "New York 2017 P", year: 2017, month: 8, day: 21,
                 latitude: 40.7128, longitude: -74.0060, elevation: 10,
                 firstContact: (17, 23, 14.3), maximum: (18, 44, 57.4), lastContact: (20, 0, 42.8),
                 kind: .partial, magnitude: 0.770, obscuration: 0.716, geometricAltitude: 52.9),
    LocalFixture(name: "Los Angeles 2017 P", year: 2017, month: 8, day: 21,
                 latitude: 34.0522, longitude: -118.2437, elevation: 87,
                 firstContact: (16, 5, 43.9), maximum: (17, 21, 9.7), lastContact: (18, 44, 47.6),
                 kind: .partial, magnitude: 0.694, obscuration: 0.622, geometricAltitude: 48.4),
    LocalFixture(name: "Anchorage 2017 P", year: 2017, month: 8, day: 21,
                 latitude: 61.2181, longitude: -149.9003, elevation: 31,
                 firstContact: (16, 21, 37.2), maximum: (17, 16, 13.1), lastContact: (18, 13, 47.9),
                 kind: .partial, magnitude: 0.556, obscuration: 0.456, geometricAltitude: 19.2),
    LocalFixture(name: "Nome 2017 P", year: 2017, month: 8, day: 21,
                 latitude: 64.5011, longitude: -165.4064, elevation: 5,
                 firstContact: (16, 29, 58.3), maximum: (17, 18, 8.9), lastContact: (18, 8, 24.6),
                 kind: .partial, magnitude: 0.449, obscuration: 0.338, geometricAltitude: 12.2),
    LocalFixture(name: "Honolulu 2017 P", year: 2017, month: 8, day: 21,
                 latitude: 21.3069, longitude: -157.8583, elevation: 5,
                 firstContact: nil, maximum: (16, 35, 51.7), lastContact: (17, 25, 19.8),
                 kind: .partial, magnitude: 0.387, obscuration: 0.273, geometricAltitude: 4.6),
    LocalFixture(name: "Adak AK 2017 P", year: 2017, month: 8, day: 21,
                 latitude: 51.8800, longitude: -176.6581, elevation: 10,
                 firstContact: nil, maximum: (17, 2, 20.7), lastContact: (17, 56, 32.8),
                 kind: .partial, magnitude: 0.679, obscuration: 0.602, geometricAltitude: 2.2),
    LocalFixture(name: "Dallas TX 2024 T", year: 2024, month: 4, day: 8,
                 latitude: 32.77912, longitude: -96.80028, elevation: 131,
                 firstContact: (17, 23, 14.6), maximum: (18, 42, 32.9), lastContact: (20, 2, 35.5),
                 kind: .total, magnitude: 1.015, obscuration: 1.0, geometricAltitude: 64.6),
    LocalFixture(name: "New York 2024 P", year: 2024, month: 4, day: 8,
                 latitude: 40.7128, longitude: -74.0060, elevation: 10,
                 firstContact: (18, 10, 32.3), maximum: (19, 25, 30.1), lastContact: (20, 36, 19.3),
                 kind: .partial, magnitude: 0.911, obscuration: 0.899, geometricAltitude: 43.4),
    // The point of greatest eclipse itself, 25.3N 104.1W, where the catalogue
    // puts the diameter ratio at 1.0566 and the USNO puts the magnitude at
    // 1.028. Those are not the same quantity and this row is the fixture that
    // holds the module to the second of them.
    LocalFixture(name: "Greatest point 2024 T", year: 2024, month: 4, day: 8,
                 latitude: 25.3, longitude: -104.1, elevation: 0,
                 firstContact: (16, 58, 29.4), maximum: (18, 17, 20.1), lastContact: (19, 39, 45.9),
                 kind: .total, magnitude: 1.028, obscuration: 1.0, geometricAltitude: 69.8),
    LocalFixture(name: "Hilo HI 2024 P", year: 2024, month: 4, day: 8,
                 latitude: 19.7297, longitude: -155.0900, elevation: 12,
                 firstContact: (16, 28, 49.4), maximum: (17, 11, 20.4), lastContact: (17, 57, 6.2),
                 kind: .partial, magnitude: 0.335, obscuration: 0.223, geometricAltitude: 14.1),
    LocalFixture(name: "Kiritimati 2024 P", year: 2024, month: 4, day: 8,
                 latitude: 1.8721, longitude: -157.4278, elevation: 3,
                 firstContact: nil, maximum: (16, 48, 3.9), lastContact: (17, 44, 26.0),
                 kind: .partial, magnitude: 0.747, obscuration: 0.689, geometricAltitude: 4.4),
    LocalFixture(name: "Papeete 2024 P", year: 2024, month: 4, day: 8,
                 latitude: -17.5516, longitude: -149.5585, elevation: 2,
                 firstContact: nil, maximum: (16, 34, 0.5), lastContact: (17, 29, 29.6),
                 kind: .partial, magnitude: 0.675, obscuration: 0.601, geometricAltitude: 5.8),
    LocalFixture(name: "Ponta Delgada 2024 P", year: 2024, month: 4, day: 8,
                 latitude: 37.7412, longitude: -25.6756, elevation: 40,
                 firstContact: (19, 5, 21.9), maximum: (20, 0, 11.9), lastContact: nil,
                 kind: .partial, magnitude: 0.690, obscuration: 0.619, geometricAltitude: 1.5),
    LocalFixture(name: "Reykjavik 2026 T", year: 2026, month: 8, day: 12,
                 latitude: 64.1466, longitude: -21.9426, elevation: 61,
                 firstContact: (16, 47, 9.8), maximum: (17, 48, 42.3), lastContact: (18, 47, 34.4),
                 kind: .total, magnitude: 1.002, obscuration: 1.0, geometricAltitude: 24.5),
    // Madrid misses totality by a hair and then loses the fourth contact to the
    // horizon: the response lists "Sunset" at 19:16 where C4 would stand.
    LocalFixture(name: "Madrid 2026 P", year: 2026, month: 8, day: 12,
                 latitude: 40.4168, longitude: -3.7038, elevation: 667,
                 firstContact: (17, 36, 42.4), maximum: (18, 32, 18.5), lastContact: nil,
                 kind: .partial, magnitude: 0.999, obscuration: 1.0, geometricAltitude: 7.2),
    LocalFixture(name: "Albuquerque 2023 A", year: 2023, month: 10, day: 14,
                 latitude: 35.0844, longitude: -106.6504, elevation: 1619,
                 firstContact: (15, 13, 11.5), maximum: (16, 36, 52.4), lastContact: (18, 9, 21.8),
                 kind: .annular, magnitude: 0.970, obscuration: 0.897, geometricAltitude: 36.1),
    LocalFixture(name: "San Antonio 2023 A", year: 2023, month: 10, day: 14,
                 latitude: 29.4241, longitude: -98.4936, elevation: 198,
                 firstContact: (15, 23, 47.6), maximum: (16, 54, 13.1), lastContact: (18, 32, 56.3),
                 kind: .annular, magnitude: 0.962, obscuration: 0.901, geometricAltitude: 47.1),
    // The eclipse of 2012 May 20 falls on 21 May in Universal Time at
    // Albuquerque, which the response says in its own "day" field. A fixture
    // that used the calendar date of the eclipse would be a day out.
    LocalFixture(name: "Albuquerque 2012 A", year: 2012, month: 5, day: 21,
                 latitude: 35.0844, longitude: -106.6504, elevation: 1619,
                 firstContact: (0, 28, 25.1), maximum: (1, 35, 51.0), lastContact: nil,
                 kind: .annular, magnitude: 0.965, obscuration: 0.870, geometricAltitude: 5.1),
    LocalFixture(name: "Dehradun 2020 A", year: 2020, month: 6, day: 21,
                 latitude: 30.3165, longitude: 78.0322, elevation: 640,
                 firstContact: (4, 54, 0.4), maximum: (6, 35, 14.6), lastContact: (8, 20, 31.1),
                 kind: .annular, magnitude: 0.995, obscuration: 0.989, geometricAltitude: 82.4),
    LocalFixture(name: "Madrid 2005 A", year: 2005, month: 10, day: 3,
                 latitude: 40.4168, longitude: -3.7038, elevation: 667,
                 firstContact: (7, 40, 12.3), maximum: (8, 57, 57.0), lastContact: (10, 23, 35.3),
                 kind: .annular, magnitude: 0.973, obscuration: 0.903, geometricAltitude: 28.5),
    LocalFixture(name: "Coyhaique 2017 A", year: 2017, month: 2, day: 26,
                 latitude: -45.5752, longitude: -72.0662, elevation: 302,
                 firstContact: (12, 23, 24.6), maximum: (13, 36, 16.1), lastContact: (14, 56, 28.1),
                 kind: .annular, magnitude: 0.990, obscuration: 0.973, geometricAltitude: 32.6),
    LocalFixture(name: "New York 2021 P", year: 2021, month: 6, day: 10,
                 latitude: 40.7128, longitude: -74.0060, elevation: 10,
                 firstContact: nil, maximum: (9, 32, 44.4), lastContact: (10, 30, 49.4),
                 kind: .partial, magnitude: 0.797, obscuration: 0.725, geometricAltitude: 0.5),
    LocalFixture(name: "Boston 2021 P", year: 2021, month: 6, day: 10,
                 latitude: 42.3601, longitude: -71.0589, elevation: 43,
                 firstContact: nil, maximum: (9, 33, 18.0), lastContact: (10, 32, 36.0),
                 kind: .partial, magnitude: 0.800, obscuration: 0.729, geometricAltitude: 3.3),
    // The lowest Sun in the set. Its geometric altitude at maximum is below
    // zero and its apparent altitude is above it, so a fixture compared in the
    // wrong convention is out by more than half a degree here and by two
    // hundredths at Dallas.
    LocalFixture(name: "Toronto 2021 P", year: 2021, month: 6, day: 10,
                 latitude: 43.6532, longitude: -79.3832, elevation: 76,
                 firstContact: nil, maximum: (9, 39, 58.0), lastContact: (10, 37, 55.3),
                 kind: .partial, magnitude: 0.861, obscuration: 0.801, geometricAltitude: -0.2),
]

print("")
print("solar, local circumstances against the USNO eclipse computer")
print("  place                  type     C1 error  max error  C4 error   magnitude     obscuration    altitude")
for fixture in localFixtures {
    let place = Coordinates.Geographic(latitude: fixture.latitude,
                                       longitude: fixture.longitude,
                                       elevation: fixture.elevation)
    let noon = JulianDay.from(year: fixture.year, month: fixture.month, day: Double(fixture.day) + 0.5)
    let local = Eclipse.solarCircumstances(near: noon, place: place)

    checkTrue("\(fixture.name) type, got \(local.kind.rawValue)", local.kind == fixture.kind)
    guard local.kind != .none else { continue }

    let c1: Double
    if let published = fixture.firstContact {
        c1 = secondsBetween(local.firstContact,
                            universalTime(fixture.year, fixture.month, fixture.day,
                                          published.0, published.1, published.2))
        worstSolarContact = max(worstSolarContact, abs(c1))
        check("\(fixture.name) first contact", c1, 0, contactTolerance)
    } else {
        // The response put a sunrise where a first contact would be, so the
        // module has to withhold one too rather than name a time nobody there
        // could have observed.
        c1 = local.firstContact == nil ? 0 : 1e9
        checkTrue("\(fixture.name) withholds a first contact the sun rose through",
                  local.firstContact == nil)
    }

    let mx = secondsBetween(local.maximum,
                            universalTime(fixture.year, fixture.month, fixture.day,
                                          fixture.maximum.0, fixture.maximum.1, fixture.maximum.2))
    worstSolarMaximum = max(worstSolarMaximum, abs(mx))

    let c4: Double
    if let published = fixture.lastContact {
        c4 = secondsBetween(local.lastContact,
                            universalTime(fixture.year, fixture.month, fixture.day,
                                          published.0, published.1, published.2))
        worstSolarContact = max(worstSolarContact, abs(c4))
        check("\(fixture.name) last contact", c4, 0, contactTolerance)
    } else {
        c4 = local.lastContact == nil ? 0 : 1e9
        checkTrue("\(fixture.name) withholds a last contact the sun set before",
                  local.lastContact == nil)
    }

    let wantAltitude = apparent(fixture.geometricAltitude, elevation: fixture.elevation)
    worstSolarMagnitude = max(worstSolarMagnitude, abs(local.magnitude - fixture.magnitude))
    worstSolarObscuration = max(worstSolarObscuration, abs(local.obscuration - fixture.obscuration))
    worstSolarAltitude = max(worstSolarAltitude, abs(local.maximumAltitude - wantAltitude))

    print(String(format: "  %-22@ %-7@ %+8.1f  %+9.1f  %+8.1f   %6.4f%+8.4f   %6.4f%+8.4f  %6.2f%+6.2f",
                 fixture.name as NSString, local.kind.rawValue as NSString, c1, mx, c4,
                 local.magnitude, local.magnitude - fixture.magnitude,
                 local.obscuration, local.obscuration - fixture.obscuration,
                 local.maximumAltitude, local.maximumAltitude - wantAltitude))

    check("\(fixture.name) maximum", mx, 0, contactTolerance)
    // The USNO prints the magnitude to three places and the obscuration to a
    // tenth of a percent, so half a unit in the last place of each is rounding
    // and not error.
    check("\(fixture.name) magnitude", local.magnitude, fixture.magnitude, 0.003)
    check("\(fixture.name) obscuration", local.obscuration, fixture.obscuration, 0.003)
    check("\(fixture.name) sun altitude at maximum", local.maximumAltitude, wantAltitude, 0.12)

    // Identities the three returned numbers owe each other, whatever the
    // ephemeris says. Magnitude counts diameter and obscuration counts area,
    // so at a partial phase the second is always the smaller; a disc entirely
    // behind the Moon is entirely obscured; and an annulus leaves a ring.
    switch local.kind {
    case .partial:
        checkTrue("\(fixture.name) partial magnitude is below one", local.magnitude < 1)
        checkTrue("\(fixture.name) partial obscuration is below one", local.obscuration < 1)
        // Below a deep phase the area covered always trails the diameter
        // covered, and by a wide margin: half the Sun's diameter is 39 percent
        // of its area. The rule reverses only when the Moon's disc is the
        // larger of the two and the pair is within a whisker of totality, as
        // Madrid is on 2026 Aug 12 with an obscuration of 0.9995 against a
        // magnitude of 0.9986, so the check is stated for the range where it
        // holds rather than as a law that it is not.
        if local.magnitude < 0.95 {
            checkTrue("\(fixture.name) obscuration is below the magnitude",
                      local.obscuration < local.magnitude - 0.005)
        }
    case .total:
        checkTrue("\(fixture.name) total eclipse obscures the whole disc",
                  local.obscuration == 1.0)
        checkTrue("\(fixture.name) total eclipse magnitude reaches one", local.magnitude >= 1)
    case .annular:
        checkTrue("\(fixture.name) annular eclipse leaves a ring", local.obscuration < 1)
        checkTrue("\(fixture.name) annular magnitude is below one", local.magnitude < 1)
    case .none:
        break
    }
    // Nothing is reported for a Sun whose upper limb is under the horizon.
    checkTrue("\(fixture.name) reports a sun above the horizon at maximum",
              local.maximumAltitude >= Refraction.sunriseAltitude)
    let ordered = [local.firstContact, local.maximum, local.lastContact].compactMap { $0 }
    checkTrue("\(fixture.name) contacts are in order",
              zip(ordered, ordered.dropFirst()).allSatisfy { $0.value <= $1.value })
}

// ---------------------------------------------------------------------------
// 3b. Places where the greatest phase was never above the horizon.
// ---------------------------------------------------------------------------
// The response for these lists a sunrise or a sunset and no maximum eclipse at
// all, because the geometric maximum happened with the Sun down. Its top level
// magnitude field is still the geometric one. The module promises something
// different and narrower: the greatest phase actually seen. These two rows are
// the only ones that hold it to that promise, and they are the reason the
// magnitude of a clipped eclipse is not compared against the USNO field
// anywhere above.
print("")
print("places where the greatest phase happened below the horizon")
struct ClippedFixture {
    let name: String
    let year: Int, month: Int, day: Int
    let latitude: Double, longitude: Double, elevation: Double
    /// The horizon crossing the response names, to the minute.
    let horizon: (Int, Int)
    /// The one exterior contact the response does give.
    let contact: (Int, Int, Double)
    let contactIsLast: Bool
    /// The response's magnitude field, which is the geometric maximum and so an
    /// upper bound on what could be seen from here.
    let geometricMagnitude: Double
}
let clippedFixtures = [
    // Praia, Cape Verde: eclipse begins 19:00:34.4 at altitude 11.7, sunset
    // 19:53, magnitude 0.882, and no maximum eclipse row.
    ClippedFixture(name: "Praia 2017", year: 2017, month: 8, day: 21,
                   latitude: 14.9330, longitude: -23.5133, elevation: 32,
                   horizon: (19, 53), contact: (19, 0, 34.4), contactIsLast: false,
                   geometricMagnitude: 0.882),
    // Tiksi, Siberia: sunrise 17:38, eclipse ends 17:43:22.5 at altitude -0.6,
    // magnitude 0.944, and no maximum eclipse row. The Sun climbs a quarter of
    // a degree in the five minutes between the two, which is why an eclipse
    // that reached 0.944 here left less than a tenth of it to be seen.
    ClippedFixture(name: "Tiksi 2026", year: 2026, month: 8, day: 12,
                   latitude: 71.6872, longitude: 128.8694, elevation: 12,
                   horizon: (17, 38), contact: (17, 43, 22.5), contactIsLast: true,
                   geometricMagnitude: 0.944),
]
for fixture in clippedFixtures {
    let place = Coordinates.Geographic(latitude: fixture.latitude,
                                       longitude: fixture.longitude,
                                       elevation: fixture.elevation)
    let noon = JulianDay.from(year: fixture.year, month: fixture.month, day: Double(fixture.day) + 0.5)
    let local = Eclipse.solarCircumstances(near: noon, place: place)
    let contact = universalTime(fixture.year, fixture.month, fixture.day,
                                fixture.contact.0, fixture.contact.1, fixture.contact.2)
    let horizon = universalTime(fixture.year, fixture.month, fixture.day,
                                fixture.horizon.0, fixture.horizon.1, 0)
    let contactError = secondsBetween(fixture.contactIsLast ? local.lastContact : local.firstContact,
                                      contact)
    let maximumError = secondsBetween(local.maximum, horizon)
    worstSolarContact = max(worstSolarContact, abs(contactError))
    print(String(format: "  %-12@ %-8@ C1 %@ max %@ C4 %@  contact error %+6.1f s, max is %+5.1f s from the horizon crossing, magnitude %.4f of a possible %.3f",
                 fixture.name as NSString, local.kind.rawValue as NSString,
                 clock(local.firstContact), clock(local.maximum), clock(local.lastContact),
                 contactError, maximumError, local.magnitude, fixture.geometricMagnitude))
    checkTrue("\(fixture.name) is partial, got \(local.kind.rawValue)", local.kind == .partial)
    check("\(fixture.name) the one contact the response gives", contactError, 0, contactTolerance)
    checkTrue("\(fixture.name) withholds the contact on the horizon side",
              (fixture.contactIsLast ? local.firstContact : local.lastContact) == nil)
    // The response gives the horizon crossing only to the minute, so a minute
    // is the whole precision available on this one.
    check("\(fixture.name) greatest phase seen is at the horizon crossing", maximumError, 0, 60.0)
    checkTrue("\(fixture.name) reports less than the eclipse reached below the horizon, got \(local.magnitude)",
              local.magnitude < fixture.geometricMagnitude - 0.01)
    checkTrue("\(fixture.name) still reports a sun above the horizon",
              local.maximumAltitude >= Refraction.sunriseAltitude)
}

// ---------------------------------------------------------------------------
// 4. The negative cases.
// ---------------------------------------------------------------------------
// The USNO computer answers all three of these with
//   {"error": "Eclipse not visible from selected location. ..."}
// so a module that returns an eclipse here has invented it. Berlin is the case
// the horizon rule exists for: the separation of the two centres there on 21
// August 2017 satisfies the geometry to a magnitude of about 0.07, an hour
// after the Sun has set.
print("")
print("negative cases")
struct Absent { let name: String; let year: Int, month: Int, day: Int
                let latitude: Double, longitude: Double, elevation: Double }
let absent = [
    Absent(name: "Berlin, 2017 Aug 21", year: 2017, month: 8, day: 21,
           latitude: 52.5200, longitude: 13.4050, elevation: 34),
    Absent(name: "Sydney, 2024 Apr 08", year: 2024, month: 4, day: 8,
           latitude: -33.8688, longitude: 151.2093, elevation: 58),
    Absent(name: "Apia, 2017 Aug 21", year: 2017, month: 8, day: 21,
           latitude: -13.8333, longitude: -171.7667, elevation: 2),
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
// And Madrid, whose fourth contact is withheld, is still an event of its day.
let madrid = Coordinates.Geographic(latitude: 40.4168, longitude: -3.7038, elevation: 667)
let august12 = JulianDay.from(year: 2026, month: 8, day: 12.0)
checkTrue("Madrid 2026 is listed among that day's events",
          Eclipse.solarEvents(from: august12, to: august12.adding(days: 1), place: madrid).count == 1)

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

// Nineteen events spanning 1993 to 2047. Catalogue rows, copied column by
// column. Columns are
//   number date TD deltaT luna saros type qse gamma penMag umbMag penDur parDur totDur lat long
//   09635  1993 Nov 29  06:27:06  60   -76  135  T   p-  -0.3994  2.1633  1.0876  354.4  210.8   46.7
//   09641  1996 Sep 27  02:55:24  62   -41  127  T   -p   0.3426  2.2188  1.2395  320.9  203.3   69.2
//   09642  1997 Mar 24  04:40:28  62   -35  132  P   t-   0.4899  1.9994  0.9195  353.9  203.1    -
//   09658  2003 Nov 09  01:19:38  64    47  126  T   -t  -0.4319  2.1139  1.0178  363.2  211.4   22.0
//   09660  2004 Oct 28  03:05:11  65    59  136  T   p-   0.2846  2.3637  1.3081  353.8  218.7   80.5
//   09675  2011 Jun 15  20:13:43  67   141  130  T+  pp   0.0897  2.6868  1.6999  336.1  219.3  100.2
//   09679  2013 Apr 25  20:08:38  68   164  112  P   -a  -1.0121  0.9866  0.0148  247.7   27.0    -
//   09684  2015 Apr 04  12:01:24  69   188  132  T   t-   0.4460  2.0792  1.0008  357.5  209.0    4.7
//   09691  2018 Jul 27  20:22:54  71   229  129  T+  pp   0.1168  2.6792  1.6087  373.8  234.5  103.0
//   09692  2019 Jan 21  05:13:27  71   235  134  T   p-   0.3684  2.1684  1.1953  311.5  196.8   62.0
//   09698  2021 May 26  11:19:53  72   264  121  T   -a   0.4774  1.9540  1.0095  302.0  187.4   14.5
//   09700  2022 May 16  04:12:42  73   276  131  T-  p-  -0.2532  2.3726  1.4137  318.7  207.2   84.9
//   09702  2023 May 05  17:24:05  73   288  141  N   h-  -1.0349  0.9636 -0.0457  257.5    -      -
//   09705  2024 Sep 18  02:45:25  74   305  118  P   -a  -0.9792  1.0372  0.0848  246.3   62.8    -
//   09706  2025 Mar 14  06:59:56  75   311  123  T   -p   0.3484  2.2595  1.1784  362.6  218.3   65.4
//   09707  2025 Sep 07  18:12:58  75   317  128  T   -p  -0.2752  2.3440  1.3619  326.7  209.4   82.1
//   09715  2028 Dec 31  16:53:15  77   358  125  T   -p   0.3258  2.2742  1.2463  336.2  208.8   71.3
//   09716  2029 Jun 26  03:23:22  77   364  130  T+  pp   0.0124  2.8266  1.8436  335.1  219.5  101.9
//   09756  2047 Jul 07  10:35:45  91   587  130  T-  pp  -0.0636  2.7310  1.7513  333.4  218.5  100.8
//
// 2015 Apr 04 is the shortest total phase in the catalogue between 1990 and
// 2050 at 4.7 minutes, and 2013 Apr 25 the shortest partial phase at 27.0
// minutes. Both are in the set on purpose: they are what a sampling step too
// coarse to bracket a short phase would lose, and they are also where the
// error in a duration is largest, because near a grazing contact the Moon's
// limb runs almost along the shadow's edge and the crossing is slow.
let lunarFixtures = [
    LunarFixture(name: "1993 Nov 29 T", year: 1993, month: 11, day: 29,
                 hour: 6, minute: 27, second: 6, kind: .total,
                 penumbralMagnitude: 2.1633, umbralMagnitude: 1.0876,
                 penumbralMinutes: 354.4, partialMinutes: 210.8, totalMinutes: 46.7),
    LunarFixture(name: "1996 Sep 27 T", year: 1996, month: 9, day: 27,
                 hour: 2, minute: 55, second: 24, kind: .total,
                 penumbralMagnitude: 2.2188, umbralMagnitude: 1.2395,
                 penumbralMinutes: 320.9, partialMinutes: 203.3, totalMinutes: 69.2),
    LunarFixture(name: "1997 Mar 24 P", year: 1997, month: 3, day: 24,
                 hour: 4, minute: 40, second: 28, kind: .partial,
                 penumbralMagnitude: 1.9994, umbralMagnitude: 0.9195,
                 penumbralMinutes: 353.9, partialMinutes: 203.1, totalMinutes: nil),
    LunarFixture(name: "2003 Nov 09 T", year: 2003, month: 11, day: 9,
                 hour: 1, minute: 19, second: 38, kind: .total,
                 penumbralMagnitude: 2.1139, umbralMagnitude: 1.0178,
                 penumbralMinutes: 363.2, partialMinutes: 211.4, totalMinutes: 22.0),
    LunarFixture(name: "2004 Oct 28 T", year: 2004, month: 10, day: 28,
                 hour: 3, minute: 5, second: 11, kind: .total,
                 penumbralMagnitude: 2.3637, umbralMagnitude: 1.3081,
                 penumbralMinutes: 353.8, partialMinutes: 218.7, totalMinutes: 80.5),
    LunarFixture(name: "2011 Jun 15 T", year: 2011, month: 6, day: 15,
                 hour: 20, minute: 13, second: 43, kind: .total,
                 penumbralMagnitude: 2.6868, umbralMagnitude: 1.6999,
                 penumbralMinutes: 336.1, partialMinutes: 219.3, totalMinutes: 100.2),
    LunarFixture(name: "2013 Apr 25 P", year: 2013, month: 4, day: 25,
                 hour: 20, minute: 8, second: 38, kind: .partial,
                 penumbralMagnitude: 0.9866, umbralMagnitude: 0.0148,
                 penumbralMinutes: 247.7, partialMinutes: 27.0, totalMinutes: nil),
    LunarFixture(name: "2015 Apr 04 T", year: 2015, month: 4, day: 4,
                 hour: 12, minute: 1, second: 24, kind: .total,
                 penumbralMagnitude: 2.0792, umbralMagnitude: 1.0008,
                 penumbralMinutes: 357.5, partialMinutes: 209.0, totalMinutes: 4.7),
    LunarFixture(name: "2018 Jul 27 T", year: 2018, month: 7, day: 27,
                 hour: 20, minute: 22, second: 54, kind: .total,
                 penumbralMagnitude: 2.6792, umbralMagnitude: 1.6087,
                 penumbralMinutes: 373.8, partialMinutes: 234.5, totalMinutes: 103.0),
    LunarFixture(name: "2019 Jan 21 T", year: 2019, month: 1, day: 21,
                 hour: 5, minute: 13, second: 27, kind: .total,
                 penumbralMagnitude: 2.1684, umbralMagnitude: 1.1953,
                 penumbralMinutes: 311.5, partialMinutes: 196.8, totalMinutes: 62.0),
    LunarFixture(name: "2021 May 26 T", year: 2021, month: 5, day: 26,
                 hour: 11, minute: 19, second: 53, kind: .total,
                 penumbralMagnitude: 1.9540, umbralMagnitude: 1.0095,
                 penumbralMinutes: 302.0, partialMinutes: 187.4, totalMinutes: 14.5),
    LunarFixture(name: "2022 May 16 T", year: 2022, month: 5, day: 16,
                 hour: 4, minute: 12, second: 42, kind: .total,
                 penumbralMagnitude: 2.3726, umbralMagnitude: 1.4137,
                 penumbralMinutes: 318.7, partialMinutes: 207.2, totalMinutes: 84.9),
    LunarFixture(name: "2023 May 05 N", year: 2023, month: 5, day: 5,
                 hour: 17, minute: 24, second: 5, kind: .penumbral,
                 penumbralMagnitude: 0.9636, umbralMagnitude: -0.0457,
                 penumbralMinutes: 257.5, partialMinutes: nil, totalMinutes: nil),
    LunarFixture(name: "2024 Sep 18 P", year: 2024, month: 9, day: 18,
                 hour: 2, minute: 45, second: 25, kind: .partial,
                 penumbralMagnitude: 1.0372, umbralMagnitude: 0.0848,
                 penumbralMinutes: 246.3, partialMinutes: 62.8, totalMinutes: nil),
    LunarFixture(name: "2025 Mar 14 T", year: 2025, month: 3, day: 14,
                 hour: 6, minute: 59, second: 56, kind: .total,
                 penumbralMagnitude: 2.2595, umbralMagnitude: 1.1784,
                 penumbralMinutes: 362.6, partialMinutes: 218.3, totalMinutes: 65.4),
    LunarFixture(name: "2025 Sep 07 T", year: 2025, month: 9, day: 7,
                 hour: 18, minute: 12, second: 58, kind: .total,
                 penumbralMagnitude: 2.3440, umbralMagnitude: 1.3619,
                 penumbralMinutes: 326.7, partialMinutes: 209.4, totalMinutes: 82.1),
    LunarFixture(name: "2028 Dec 31 T", year: 2028, month: 12, day: 31,
                 hour: 16, minute: 53, second: 15, kind: .total,
                 penumbralMagnitude: 2.2742, umbralMagnitude: 1.2463,
                 penumbralMinutes: 336.2, partialMinutes: 208.8, totalMinutes: 71.3),
    LunarFixture(name: "2029 Jun 26 T", year: 2029, month: 6, day: 26,
                 hour: 3, minute: 23, second: 22, kind: .total,
                 penumbralMagnitude: 2.8266, umbralMagnitude: 1.8436,
                 penumbralMinutes: 335.1, partialMinutes: 219.5, totalMinutes: 101.9),
    LunarFixture(name: "2047 Jul 07 T", year: 2047, month: 7, day: 7,
                 hour: 10, minute: 35, second: 45, kind: .total,
                 penumbralMagnitude: 2.7310, umbralMagnitude: 1.7513,
                 penumbralMinutes: 333.4, partialMinutes: 218.5, totalMinutes: 100.8),
]

print("")
print("lunar circumstances against the NASA five millennium catalogue")
print("  eclipse         type        greatest TD    error s   umbral mag       penumbral mag     P duration    U duration    T duration")
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
    worstLunarMagnitude = max(worstLunarMagnitude,
                              max(abs(local.umbralMagnitude - fixture.umbralMagnitude),
                                  abs(local.penumbralMagnitude - fixture.penumbralMagnitude)))

    func minutes(_ begin: JulianDay?, _ end: JulianDay?) -> Double? {
        guard let begin, let end else { return nil }
        return (end.value - begin.value) * 1440.0
    }
    let penumbral = minutes(local.penumbralBegin, local.penumbralEnd)
    let partial = minutes(local.partialBegin, local.partialEnd)
    let total = minutes(local.totalBegin, local.totalEnd)

    print(String(format: "  %-15@ %-9@  %@  %+7.1f  %+7.4f%+8.4f  %+7.4f%+8.4f   %6.1f%+6.2f  %6.1f%+6.2f  %6.1f%+6.2f",
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
    // one minute on a phase lasting hours is one part in two hundred. It is
    // one part in six on the total phase of 2015 Apr 04, which is what a
    // grazing contact costs and is why that row is here.
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

    // A kind and a set of contacts that disagree is a bug whatever the
    // ephemeris says: a module whose sampling step is too coarse to bracket a
    // short phase will still classify the eclipse from the refined maximum and
    // then hand back an eclipse it says is total with no total phase in it.
    switch local.kind {
    case .total:
        checkTrue("\(fixture.name) total eclipse has both interior contacts",
                  local.totalBegin != nil && local.totalEnd != nil)
        checkTrue("\(fixture.name) total eclipse has both umbral contacts",
                  local.partialBegin != nil && local.partialEnd != nil)
        checkTrue("\(fixture.name) total eclipse reaches umbral magnitude one",
                  local.umbralMagnitude >= 1)
    case .partial:
        checkTrue("\(fixture.name) partial eclipse has both umbral contacts",
                  local.partialBegin != nil && local.partialEnd != nil)
        checkTrue("\(fixture.name) partial eclipse has no interior contacts",
                  local.totalBegin == nil && local.totalEnd == nil)
        checkTrue("\(fixture.name) partial umbral magnitude lies between zero and one",
                  local.umbralMagnitude > 0 && local.umbralMagnitude < 1)
    case .penumbral:
        checkTrue("\(fixture.name) penumbral eclipse has only penumbral contacts",
                  local.partialBegin == nil && local.totalBegin == nil)
        checkTrue("\(fixture.name) penumbral eclipse misses the umbra",
                  local.umbralMagnitude <= 0 && local.penumbralMagnitude > 0)
    case .none:
        break
    }
    // The Moon reaches the penumbra before the umbra and leaves it after, so
    // the penumbral magnitude always exceeds the umbral one.
    checkTrue("\(fixture.name) penumbral magnitude exceeds the umbral one",
              local.penumbralMagnitude > local.umbralMagnitude)
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
// 21 August, per the NASA catalogue: the only other solar eclipse of 2017 is
// the annular of 26 February, whose track is in the southern hemisphere.
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

// And at Coyhaique the answer for the same year is the other one, which is the
// half of the test that a module returning the first eclipse of any year would
// pass by accident.
let coyhaique = Coordinates.Geographic(latitude: -45.5752, longitude: -72.0662, elevation: 302)
if let next = Eclipse.nextSolar(after: JulianDay.from(year: 2017, month: 1, day: 1.0),
                                place: coyhaique, searchYears: 1) {
    let date = next.maximum!.calendarDate
    print("  nextSolar at Coyhaique from 2017 Jan 1: \(date.year)-\(date.month)-\(Int(date.day)) \(next.kind.rawValue)")
    checkTrue("nextSolar finds 2017 Feb 26 at Coyhaique",
              date.year == 2017 && date.month == 2 && Int(date.day) == 26)
    checkTrue("nextSolar reports annularity at Coyhaique", next.kind == .annular)
} else {
    checkTrue("nextSolar finds an eclipse at Coyhaique", false)
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
// 2022 May 16, 2022 Nov 08, 2023 May 05 and 2023 Oct 28.
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
// the record rather than in someone's head. It is machine dependent, so it is
// printed and not asserted.
var started = Date()
_ = Eclipse.nextSolar(after: JulianDay.from(year: 2026, month: 1, day: 1.0),
                      place: berlin, searchYears: 5)
let solarSearch = Date().timeIntervalSince(started)
started = Date()
_ = Eclipse.lunarEvents(from: JulianDay.from(year: 2026, month: 1, day: 1.0),
                        to: JulianDay.from(year: 2031, month: 1, day: 1.0), place: berlin)
let lunarSearch = Date().timeIntervalSince(started)
started = Date()
_ = Eclipse.solarCircumstances(near: JulianDay.from(year: 2024, month: 4, day: 8.5), place: berlin)
let oneDay = Date().timeIntervalSince(started)

print("")
print(String(format: "nextSolar over five years at one place:      %5.0f ms", solarSearch * 1000))
print(String(format: "lunarEvents over five years at one place:    %5.0f ms", lunarSearch * 1000))
print(String(format: "solarCircumstances, one place one day:       %5.0f ms", oneDay * 1000))
print(String(format: "worst greatest eclipse error, solar: %6.1f s", worstGlobalTime))
print(String(format: "worst gamma error:                  %8.4f", worstGamma))
print(String(format: "worst diameter ratio error:         %8.4f", worstRatio))
print(String(format: "worst contact error, solar local:   %6.1f s", worstSolarContact))
print(String(format: "worst maximum error, solar local:   %6.1f s", worstSolarMaximum))
print(String(format: "worst magnitude error, solar local: %8.4f", worstSolarMagnitude))
print(String(format: "worst obscuration error:            %8.4f", worstSolarObscuration))
print(String(format: "worst altitude error:               %8.4f degrees", worstSolarAltitude))
print(String(format: "worst greatest eclipse error, lunar: %5.1f s", worstLunarGreatest))
print(String(format: "worst magnitude error, lunar:       %8.4f", worstLunarMagnitude))
print(String(format: "worst phase duration error, lunar:  %6.1f s", worstLunarDuration))

if failures == 0 { print("eclipse: all \(checks) checks passed") }
else { print("eclipse: \(failures) FAILURES of \(checks)"); exit(1) }
