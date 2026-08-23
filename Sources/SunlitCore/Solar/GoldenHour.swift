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
    public static func golden(
        date: JulianDay,
        place: Coordinates.Geographic
    ) -> (morning: Window?, evening: Window?) {
        windows(date: date, place: place,
                lower: goldenLowerAltitude, upper: goldenUpperAltitude)
    }

    /// Blue hour on one local day, same convention as `golden`.
    public static func blue(
        date: JulianDay,
        place: Coordinates.Geographic
    ) -> (morning: Window?, evening: Window?) {
        windows(date: date, place: place,
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
        lower: Double,
        upper: Double
    ) -> (morning: Window?, evening: Window?) {
        let dayStart = date
        let dayEnd = date.adding(days: 1)

        var cache: [Double: Double] = [:]
        func trueAltitude(_ jd: JulianDay) -> Double {
            if let hit = cache[jd.value] { return hit }
            // The band edges are geometric altitudes, so the unrefracted value
            // is the one to compare, as everywhere else in this layer.
            let value = SolarPositionSPA.evaluate(julianDay: jd, place: place)
                .elevationWithoutRefraction
            cache[jd.value] = value
            return value
        }

        // Distance into the band, positive inside it and negative outside on
        // either side. Turning "between two altitudes" into a single signed
        // function lets the existing crossing solver find both edges, including
        // the case where the sun leaves the band downward at the top rather
        // than upward, which a pair of independent threshold solves would then
        // have to reassemble.
        func depth(_ jd: JulianDay) -> Double {
            let altitude = trueAltitude(jd)
            return min(altitude - lower, upper - altitude)
        }

        let band = RiseSet.solve(
            start: dayStart, end: dayEnd,
            altitude: depth, target: { _ in 0 })

        var intervals: [(start: JulianDay, end: JulianDay)] = []
        var open: JulianDay? = depth(dayStart) > 0 ? dayStart : nil
        for crossing in band.crossings {
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

        // Solar noon divides morning from evening. This solve reads entirely
        // from the cache the band solve just filled.
        let sun = RiseSet.solve(
            start: dayStart, end: dayEnd,
            altitude: trueAltitude, target: { _ in Refraction.sunriseAltitude })
        let noon = sun.transit?.julianDay ?? dayStart.adding(days: 0.5)

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
