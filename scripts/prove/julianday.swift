import Foundation

// Meeus, Astronomical Algorithms, 2nd edition, table 7.A plus the worked
// examples of chapter 7. These are the published values; nothing here is
// computed by this program and then asserted against itself.
let table: [(year: Int, month: Int, day: Double, jd: Double, label: String)] = [
    (2000,  1,  1.5,   2451545.0,  "J2000.0"),
    (1999,  1,  1.0,   2451179.5,  "1999 Jan 1.0"),
    (1987,  1, 27.0,   2446822.5,  "1987 Jan 27.0"),
    (1987,  6, 19.5,   2446966.0,  "1987 Jun 19.5"),
    (1988,  1, 27.0,   2447187.5,  "1988 Jan 27.0"),
    (1988,  6, 19.5,   2447332.0,  "1988 Jun 19.5"),
    (1900,  1,  1.0,   2415020.5,  "1900 Jan 1.0"),
    (1600,  1,  1.0,   2305447.5,  "1600 Jan 1.0"),
    (1600, 12, 31.0,   2305812.5,  "1600 Dec 31.0"),
    (1957, 10,  4.81,  2436116.31, "Sputnik 1"),
]

// Dates before the Gregorian reform, which must be read in the Julian calendar.
let julianTable: [(year: Int, month: Int, day: Double, jd: Double, label: String)] = [
    ( 837,  4, 10.3,   2026871.8,  "837 Apr 10.3"),
    ( 333,  1, 27.5,   1842713.0,  "333 Jan 27.5"),
    (-123, 12, 31.0,   1676496.5,  "-123 Dec 31.0"),
    (-122,  1,  1.0,   1676497.5,  "-122 Jan 1.0"),
    (-1000, 7, 12.5,   1356001.0,  "-1000 Jul 12.5"),
    (-1000, 2, 29.0,   1355866.5,  "-1000 Feb 29.0"),
    (-1001, 8, 17.9,   1355671.4,  "-1001 Aug 17.9"),
    (-4712, 1,  1.5,         0.0,  "epoch"),
]

var failures = 0
func check(_ label: String, _ got: Double, _ want: Double, _ tol: Double) {
    let d = abs(got - want)
    if d > tol {
        print("FAIL  \(label): got \(got), want \(want), off by \(d)")
        failures += 1
    }
}

for row in table {
    let jd = JulianDay.from(year: row.year, month: row.month, day: row.day).value
    check("JD \(row.label)", jd, row.jd, 1e-6)
}
for row in julianTable {
    let jd = JulianDay.from(year: row.year, month: row.month, day: row.day, calendar: .julian).value
    check("JD \(row.label)", jd, row.jd, 1e-6)
}

// The reform boundary itself. 1582 October 4 Julian is followed immediately by
// 1582 October 15 Gregorian; the ten days between never existed.
check("1582 Oct 4 Julian",
      JulianDay.from(year: 1582, month: 10, day: 4.0, calendar: .julian).value, 2299159.5, 1e-9)
check("1582 Oct 15 Gregorian",
      JulianDay.from(year: 1582, month: 10, day: 15.0, calendar: .gregorian).value, 2299160.5, 1e-9)
check("historical picks Julian on Oct 4",
      JulianDay.from(year: 1582, month: 10, day: 4.0).value, 2299159.5, 1e-9)
check("historical picks Gregorian on Oct 15",
      JulianDay.from(year: 1582, month: 10, day: 15.0).value, 2299160.5, 1e-9)

// Round trip. Every date in the table must survive conversion in both
// directions, because an asymmetric bug here would not show up in the forward
// test alone.
for row in table {
    let d = JulianDay(row.jd).calendarDate
    if d.year != row.year || d.month != row.month || abs(d.day - row.day) > 1e-6 {
        print("FAIL  round trip \(row.label): got \(d), want (\(row.year), \(row.month), \(row.day))")
        failures += 1
    }
}

// Meeus chapter 7 example: 1954 June 30.0 falls on a Wednesday, day 3.
check("day of week 1954 Jun 30", Double(JulianDay(2434923.5).dayOfWeek), 3.0, 0)

// Date bridge. The Unix epoch is JD 2440587.5 by definition.
check("Unix epoch", JulianDay(date: Date(timeIntervalSince1970: 0)).value, 2440587.5, 1e-9)
check("Date round trip",
      JulianDay(date: JulianDay(2451545.0).date).value, 2451545.0, 1e-9)

// Angle helpers. Normalisation of a negative angle is the one that silently
// flips an azimuth to the far side of the sky when it is wrong.
check("normalized(-10)", Angle.normalized(-10), 350, 1e-12)
check("normalized(370)", Angle.normalized(370), 10, 1e-12)
check("normalizedSigned(350)", Angle.normalizedSigned(350), -10, 1e-12)
check("normalizedSigned(180)", Angle.normalizedSigned(180), 180, 1e-12)
check("difference 350 to 10", Angle.difference(from: 350, to: 10), 20, 1e-12)
check("difference 10 to 350", Angle.difference(from: 10, to: 350), -20, 1e-12)
check("sexagesimal -9 47 1.7", Angle.fromSexagesimal(-9, 47, 1.7), -9.7838055555, 1e-9)
check("hours 13 13 30.75", Angle.fromHours(13, 13, 30.75), 198.3781250, 1e-7)

if failures == 0 {
    print("julianday: all \(table.count + julianTable.count + 12) checks passed")
} else {
    print("julianday: \(failures) FAILURES")
    exit(1)
}
