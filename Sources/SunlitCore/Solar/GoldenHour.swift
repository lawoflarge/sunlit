import Foundation

/// The two light windows photographers plan around.
///
/// Golden hour is the sun between -4 and +6 degrees; blue hour is the sun
/// between -6 and -4. Neither is an hour. The band is an altitude band, and how
/// long the sun takes to cross it depends entirely on how steeply it moves,
/// which is a function of latitude and season. At the equator the golden band
/// is crossed in about forty minutes; at 70 degrees north in high summer the
/// sun can sit inside it from evening until morning without ever leaving.
public enum GoldenHour {

    public static let goldenLowerAltitude = -4.0
    public static let goldenUpperAltitude = 6.0
    public static let blueLowerAltitude = -6.0
    public static let blueUpperAltitude = -4.0

    /// A stretch of time with a start and an end.
    public struct Window: Sendable {
        public let start: JulianDay
        public let end: JulianDay

        public init(start: JulianDay, end: JulianDay) {
            self.start = start
            self.end = end
        }
    }

    /// Golden hour on one local day, as a morning window and an evening window.
    ///
    /// `date` is the start of the local day expressed in Universal Time, the
    /// same convention `Twilight.phases` takes. Either window is nil when the
    /// sun did not occupy the band on that side of solar noon.
    ///
    /// `solarDay` is a sweep of the same day that has already been made. Pass
    /// nil and one is made here; `DayReport` passes the one it also gives to
    /// `Twilight.phases` and to `blue`, so the day is swept once rather than
    /// three times.
    public static func golden(
        date: JulianDay,
        place: Coordinates.Geographic,
        solarDay: SolarDay? = nil
    ) -> (morning: Window?, evening: Window?) {
        windows(date: date, place: place, solarDay: solarDay,
                lower: goldenLowerAltitude, upper: goldenUpperAltitude)
    }

    /// Blue hour on one local day, same convention as `golden`.
    public static func blue(
        date: JulianDay,
        place: Coordinates.Geographic,
        solarDay: SolarDay? = nil
    ) -> (morning: Window?, evening: Window?) {
        windows(date: date, place: place, solarDay: solarDay,
                lower: blueLowerAltitude, upper: blueUpperAltitude)
    }

    /// Whether an altitude in degrees is inside the golden band.
    public static func isWithinGolden(solarAltitude: Double) -> Bool {
        solarAltitude >= goldenLowerAltitude && solarAltitude <= goldenUpperAltitude
    }

    /// Whether an altitude in degrees is inside the blue band.
    ///
    /// Half open at the top so that -4 degrees belongs to exactly one of the two
    /// bands. The shared boundary is the instant blue hour hands over to golden.
    public static func isWithinBlue(solarAltitude: Double) -> Bool {
        solarAltitude >= blueLowerAltitude && solarAltitude < blueUpperAltitude
    }

    private static func windows(
        date: JulianDay,
        place: Coordinates.Geographic,
        solarDay: SolarDay?,
        lower: Double,
        upper: Double
    ) -> (morning: Window?, evening: Window?) {
        let dayStart = date
        let dayEnd = date.adding(days: 1)

        // The band edges are geometric altitudes, so the sweep's unrefracted
        // value is the one to compare, as everywhere else in this layer.
        let day = solarDay ?? SolarDay(start: date, place: place)

        // Distance into the band, positive inside it and negative outside on
        // either side. Turning "between two altitudes" into a single signed
        // function lets the existing crossing solver find both edges, including
        // the case where the sun leaves the band downward at the top rather
        // than upward, which a pair of independent threshold solves would then
        // have to reassemble.
        func depth(_ altitude: Double) -> Double {
            min(altitude - lower, upper - altitude)
        }

        let bandCrossings = day.crossings(of: depth)

        var intervals: [(start: JulianDay, end: JulianDay)] = []
        var open: JulianDay? = depth(day.samples[0].altitude) > 0 ? dayStart : nil
        for crossing in bandCrossings {
            switch crossing.kind {
            case .rise:
                if open == nil { open = crossing.julianDay }
            case .set:
                if let from = open {
                    intervals.append((from, crossing.julianDay))
                    open = nil
                }
            }
        }
        // Still inside the band when the day ran out. Near the pole this is the
        // normal case and clipping to midnight is the honest answer: the window
        // really does continue into the next local day.
        if let from = open { intervals.append((from, dayEnd)) }

        // Solar noon divides morning from evening. It is the sweep's own
        // refined maximum, which is the same instant `Twilight.phases` reports
        // as solar noon when both are given the same sweep.
        let noon = day.maximum.instant

        func clipped(_ interval: (start: JulianDay, end: JulianDay),
                     from low: JulianDay, to high: JulianDay) -> Window? {
            let start = max(interval.start.value, low.value)
            let end = min(interval.end.value, high.value)
            guard end > start else { return nil }
            return Window(start: JulianDay(start), end: JulianDay(end))
        }

        // Where a single band interval spans solar noon, which happens through
        // the polar winter when the sun peaks inside the band and never leaves
        // it, splitting at the sun's own maximum is the only division that is
        // not invented.
        let morning = intervals.compactMap { clipped($0, from: dayStart, to: noon) }.last
        let evening = intervals.compactMap { clipped($0, from: noon, to: dayEnd) }.first
        return (morning, evening)
    }
}
