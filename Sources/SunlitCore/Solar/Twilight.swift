import Foundation

/// The named moments of one solar day at one place.
///
/// Every quantity here is a crossing of the sun's true geometric altitude
/// through a fixed threshold. The thresholds are geometric, not apparent: the
/// familiar -0.8333 degrees for sunrise already contains the horizontal
/// refraction and the solar semidiameter, and -6, -12 and -18 are defined on
/// the centre of the disc without refraction. So the solver is fed
/// `elevationWithoutRefraction` and never the refracted value, otherwise the
/// correction would be applied twice and every time would be about two minutes
/// wrong.
public enum Twilight {

    /// Sun centre at -6 degrees. Bright enough to read outdoors, the horizon is
    /// still distinct.
    public static let civilAltitude = -6.0
    /// Sun centre at -12 degrees. The sea horizon is no longer usable for a
    /// sextant sight, which is where the name comes from.
    public static let nauticalAltitude = -12.0
    /// Sun centre at -18 degrees. Scattered sunlight no longer contributes to
    /// sky brightness.
    public static let astronomicalAltitude = -18.0

    /// Every named instant of one local day.
    ///
    /// Optional means "did not happen on this day at this place", never
    /// "unknown". Above the Arctic Circle most of these are absent for weeks at
    /// a time and the interface has to say so rather than print a plausible
    /// looking time.
    public struct Phases: Sendable {
        public let astronomicalDawn: JulianDay?
        public let nauticalDawn: JulianDay?
        public let civilDawn: JulianDay?
        public let sunrise: JulianDay?
        public let solarNoon: JulianDay?
        public let sunset: JulianDay?
        public let civilDusk: JulianDay?
        public let nauticalDusk: JulianDay?
        public let astronomicalDusk: JulianDay?
        /// Solar midnight, the instant of least altitude in the local day.
        public let nadir: JulianDay?
        /// Seconds of the local day during which the sun was above the sunrise
        /// altitude. Equal to sunset minus sunrise whenever both exist.
        public let dayLength: TimeInterval
        /// The sun stayed above the sunrise altitude for the whole local day.
        public let polarDay: Bool
        /// The sun stayed below it for the whole local day.
        public let polarNight: Bool
    }

    /// Solves one local day.
    ///
    /// - Parameters:
    ///   - date: the start of the local day, expressed in Universal Time. A
    ///     place two hours ahead of Greenwich passes 22:00 UT of the previous
    ///     calendar date.
    ///   - place: the observer.
    public static func phases(date: JulianDay, place: Coordinates.Geographic) -> Phases {
        let dayStart = date
        let dayEnd = date.adding(days: 1)

        // The solve runs an hour past each end of the day. An event a few
        // seconds after local midnight sits in the very first sampling bracket,
        // where a solver given exactly one day has no earlier sample to bracket
        // it against; the same at the far end. The events are filtered back to
        // the day afterwards, so the padding costs samples and changes nothing
        // else.
        let pad = 1.0 / 24.0

        // One shared cache. The four thresholds are solved over an identical
        // grid, so the sun is evaluated once per instant rather than four times.
        var cache: [Double: Double] = [:]
        func trueAltitude(_ jd: JulianDay) -> Double {
            if let hit = cache[jd.value] { return hit }
            let value = SolarPositionSPA.evaluate(julianDay: jd, place: place)
                .elevationWithoutRefraction
            cache[jd.value] = value
            return value
        }

        func crossingsInDay(at h0: Double) -> [RiseSet.Crossing] {
            RiseSet.solve(
                start: dayStart.adding(days: -pad),
                end: dayEnd.adding(days: pad),
                altitude: trueAltitude,
                target: { _ in h0 }
            ).crossings.filter { $0.julianDay >= dayStart && $0.julianDay < dayEnd }
        }

        let sunCrossings = crossingsInDay(at: Refraction.sunriseAltitude)
        let civil = crossingsInDay(at: civilAltitude)
        let nautical = crossingsInDay(at: nauticalAltitude)
        let astronomical = crossingsInDay(at: astronomicalAltitude)

        // Transit, antitransit and the polar flags are taken over exactly the
        // local day, so solar noon and solar midnight are guaranteed to be
        // instants the day actually contains.
        let day = RiseSet.solve(
            start: dayStart,
            end: dayEnd,
            altitude: trueAltitude,
            target: { _ in Refraction.sunriseAltitude })

        // Twilight ends at the horizon, so the first upward crossing of a
        // threshold is that threshold's dawn and the last downward crossing is
        // its dusk. Taking first and last rather than the only one matters near
        // the Arctic Circle, where the previous evening's dusk can fall after
        // local midnight and would otherwise be mistaken for this day's.
        func dawn(_ crossings: [RiseSet.Crossing]) -> JulianDay? {
            crossings.first(where: { $0.kind == .rise })?.julianDay
        }
        func dusk(_ crossings: [RiseSet.Crossing]) -> JulianDay? {
            crossings.last(where: { $0.kind == .set })?.julianDay
        }

        return Phases(
            astronomicalDawn: dawn(astronomical),
            nauticalDawn: dawn(nautical),
            civilDawn: dawn(civil),
            sunrise: dawn(sunCrossings),
            solarNoon: day.transit?.julianDay,
            sunset: dusk(sunCrossings),
            civilDusk: dusk(civil),
            nauticalDusk: dusk(nautical),
            astronomicalDusk: dusk(astronomical),
            nadir: day.antitransit?.julianDay,
            dayLength: daylight(
                crossings: sunCrossings,
                startsAboveHorizon: trueAltitude(dayStart) > Refraction.sunriseAltitude,
                dayStart: dayStart,
                dayEnd: dayEnd),
            polarDay: day.alwaysAbove,
            polarNight: day.alwaysBelow)
    }

    /// Total time the sun spent above the sunrise altitude inside the day.
    ///
    /// Measured rather than taken as sunset minus sunrise, because on the day
    /// the midnight sun begins the sun rises and never sets, and on the day it
    /// ends it sets without having risen. The difference of two times is
    /// meaningless in both cases; the occupied duration is not.
    private static func daylight(
        crossings: [RiseSet.Crossing],
        startsAboveHorizon: Bool,
        dayStart: JulianDay,
        dayEnd: JulianDay
    ) -> TimeInterval {
        var seconds = 0.0
        var aboveSince: JulianDay? = startsAboveHorizon ? dayStart : nil
        for crossing in crossings {
            switch crossing.kind {
            case .rise:
                if aboveSince == nil { aboveSince = crossing.julianDay }
            case .set:
                if let since = aboveSince {
                    seconds += (crossing.julianDay.value - since.value) * 86400.0
                    aboveSince = nil
                }
            }
        }
        if let since = aboveSince {
            seconds += (dayEnd.value - since.value) * 86400.0
        }
        return seconds
    }

    /// Which named part of the day an altitude falls in.
    public enum Period: String, Sendable {
        case night
        case astronomicalTwilight
        case nauticalTwilight
        case civilTwilight
        case goldenHour
        case day
    }

    /// The period containing a given solar altitude, in degrees.
    ///
    /// This is a partition, so the bands cannot be the textbook ones: civil
    /// twilight officially runs all the way from -6 degrees to the horizon and
    /// would then overlap the golden band, which starts at -4. Golden wins the
    /// overlap, because that is the band the interface is colouring for, and
    /// what is left of civil twilight is exactly the blue hour.
    public static func period(solarAltitude: Double) -> Period {
        if solarAltitude >= GoldenHour.goldenUpperAltitude { return .day }
        if solarAltitude >= GoldenHour.goldenLowerAltitude { return .goldenHour }
        if solarAltitude >= civilAltitude { return .civilTwilight }
        if solarAltitude >= nauticalAltitude { return .nauticalTwilight }
        if solarAltitude >= astronomicalAltitude { return .astronomicalTwilight }
        return .night
    }
}
