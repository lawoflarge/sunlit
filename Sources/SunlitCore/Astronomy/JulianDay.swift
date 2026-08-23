import Foundation

/// Julian day conversions, after Meeus, *Astronomical Algorithms*, chapter 7.
///
/// The Julian day is the continuous count of days since noon on 1 January 4713
/// BC in the Julian proleptic calendar. Every ephemeris in this module takes it
/// as input, which is why the conversion lives on its own and is tested against
/// Meeus's published table 7.A before anything else is written.
public struct JulianDay: Hashable, Comparable, Sendable {

    /// The Julian day number, including the fractional part of the day.
    public let value: Double

    public init(_ value: Double) {
        self.value = value
    }

    public static func < (lhs: JulianDay, rhs: JulianDay) -> Bool { lhs.value < rhs.value }

    /// Julian day for 2000 January 1.5 TT, the J2000.0 epoch.
    public static let j2000 = JulianDay(2451545.0)

    /// Julian centuries from J2000.0.
    public var julianCentury: Double { (value - 2451545.0) / 36525.0 }

    /// Julian millennia from J2000.0. The NREL algorithm's heliocentric series
    /// are expressed in these.
    public var julianMillennium: Double { (value - 2451545.0) / 365250.0 }

    /// Builds a Julian day from a calendar date.
    ///
    /// - Parameters:
    ///   - year: astronomical year numbering. There is a year zero: 1 BC is
    ///     year 0, 2 BC is year -1. Meeus uses this and so does every table
    ///     this core is tested against.
    ///   - month: 1 to 12.
    ///   - day: day of month including the fraction of a day, so 4.81 is the
    ///     fourth at 19:26:24.
    ///   - calendar: which calendar the date is expressed in. The default
    ///     follows history: Gregorian from 1582 October 15 onward, Julian
    ///     before it.
    public static func from(
        year: Int,
        month: Int,
        day: Double,
        calendar: CalendarSystem = .historical
    ) -> JulianDay {
        var y = year
        var m = month
        if m <= 2 {
            y -= 1
            m += 12
        }

        let isGregorian: Bool
        switch calendar {
        case .gregorian:
            isGregorian = true
        case .julian:
            isGregorian = false
        case .historical:
            // 1582 October 15 is the first Gregorian day. Compare on the
            // original, unshifted month and day, not on the shifted ones above.
            if year > 1582 { isGregorian = true }
            else if year < 1582 { isGregorian = false }
            else if month > 10 { isGregorian = true }
            else if month < 10 { isGregorian = false }
            else { isGregorian = day >= 15.0 }
        }

        var b = 0.0
        if isGregorian {
            let a = (Double(y) / 100.0).rounded(.down)
            b = 2.0 - a + (a / 4.0).rounded(.down)
        }

        let jd = (365.25 * Double(y + 4716)).rounded(.down)
            + (30.6001 * Double(m + 1)).rounded(.down)
            + day + b - 1524.5
        return JulianDay(jd)
    }

    /// Which calendar a date is expressed in.
    public enum CalendarSystem: Sendable {
        /// Gregorian from 1582 October 15, Julian before it.
        case historical
        case gregorian
        case julian
    }

    /// The calendar date this Julian day falls on, in the historical calendar.
    public var calendarDate: (year: Int, month: Int, day: Double) {
        let jdPlusHalf = value + 0.5
        let z = jdPlusHalf.rounded(.down)
        let f = jdPlusHalf - z

        var a = z
        if z >= 2299161 {
            let alpha = ((z - 1867216.25) / 36524.25).rounded(.down)
            a = z + 1 + alpha - (alpha / 4.0).rounded(.down)
        }

        let b = a + 1524
        let c = ((b - 122.1) / 365.25).rounded(.down)
        let d = (365.25 * c).rounded(.down)
        let e = ((b - d) / 30.6001).rounded(.down)

        let day = b - d - (30.6001 * e).rounded(.down) + f
        let month = e < 14 ? Int(e) - 1 : Int(e) - 13
        let year = month > 2 ? Int(c) - 4716 : Int(c) - 4715
        return (year, month, day)
    }

    /// Day of the week. 0 is Sunday.
    public var dayOfWeek: Int {
        Int((value + 1.5).rounded(.down).truncatingRemainder(dividingBy: 7.0))
    }

    /// Builds a Julian day from a `Date`, which is always UTC.
    public init(date: Date) {
        // The Unix epoch, 1970 January 1 00:00:00 UTC, is JD 2440587.5.
        self.value = date.timeIntervalSince1970 / 86400.0 + 2440587.5
    }

    /// The instant this Julian day denotes, read as UTC.
    public var date: Date {
        Date(timeIntervalSince1970: (value - 2440587.5) * 86400.0)
    }

    public func adding(days: Double) -> JulianDay { JulianDay(value + days) }
    public func adding(seconds: Double) -> JulianDay { JulianDay(value + seconds / 86400.0) }
}
