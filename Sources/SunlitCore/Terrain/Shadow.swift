import Foundation

/// Shadows, and the times a measured skyline puts the observer in shade while a
/// flat horizon calculation still says the sun is up.
///
/// The difference between the two is the whole reason the terrain layer exists:
/// a published sunrise time is the time the sun clears the ocean, and almost
/// nobody stands on an ocean.
public enum Shadow {

    /// The shadow an upright object casts on level ground.
    public struct Cast: Equatable, Sendable {
        /// Length in whatever unit the object's height was given in.
        public let length: Double
        /// The bearing the shadow points along, degrees from north toward east.
        public let azimuth: Double
        /// Length divided by height, which is the cotangent of the solar
        /// altitude and therefore the same for every object at that instant.
        public let ratio: Double
    }

    /// The shadow of an upright object of `objectHeight`.
    ///
    /// Returns nil when the sun is at or below the horizon. The shadow there is
    /// not long, it is unbounded, and an app that prints a number for it prints
    /// a lie.
    public static func cast(
        objectHeight: Double,
        solarAltitude: Double,
        solarAzimuth: Double
    ) -> Cast? {
        guard solarAltitude > 0 else { return nil }
        // Cotangent first, then the length. Deriving the ratio back out of the
        // length would divide by a height that is allowed to be zero.
        let ratio = 1.0 / Angle.tan(solarAltitude)
        return Cast(
            length: objectHeight * ratio,
            azimuth: Angle.normalized(solarAzimuth + 180.0),
            ratio: ratio)
    }

    // MARK: Terrain

    /// How tightly the terrain events are bracketed. Finer than the one second
    /// the solver defaults to, so that the flat profile case reproduces the flat
    /// horizon time to well inside a second rather than to just inside one.
    private static let precisionSeconds = 0.25

    /// The altitude the sun's centre must reach for its upper limb to clear the
    /// skyline along a bearing.
    ///
    /// The profile is an offset applied to the standard target, not a
    /// replacement for it. Two reasons. The -0.8333 degrees already accounts for
    /// the sun's semidiameter and for refraction, and both still apply behind a
    /// ridge. And the app shows the difference between the flat time and the
    /// measured time, so a flat profile has to reproduce the flat time exactly
    /// rather than nearly, which only an offset does. Carrying the horizontal
    /// refraction up to a raised skyline overstates it by about half a degree at
    /// twenty degrees of elevation, which is well inside the error of a hand
    /// swept profile.
    private static func skylineTarget(
        _ profile: HorizonProfile,
        azimuth: Double
    ) -> Double {
        Refraction.sunriseAltitude + profile.altitude(atAzimuth: azimuth)
    }

    /// A one entry memo for the ephemeris.
    ///
    /// `RiseSet.solve` asks for the altitude at an instant and then immediately
    /// for the target at the same instant. Both need the same solar position, so
    /// without this every sample evaluates the SPA twice for one moment.
    private final class SolarMemo {
        private let place: Coordinates.Geographic
        private var cachedValue = Double.nan
        private var cached: SolarPositionSPA.Result?

        init(place: Coordinates.Geographic) { self.place = place }

        func at(_ julianDay: JulianDay) -> SolarPositionSPA.Result {
            if let cached, cachedValue == julianDay.value { return cached }
            let fresh = SolarPositionSPA.evaluate(julianDay: julianDay, place: place)
            cachedValue = julianDay.value
            cached = fresh
            return fresh
        }
    }

    /// Solves the sun against the measured skyline over the twenty four hours
    /// that begin at `date`.
    private static func skylineOutcome(
        date: JulianDay,
        place: Coordinates.Geographic,
        profile: HorizonProfile
    ) -> RiseSet.Outcome {
        let memo = SolarMemo(place: place)
        return RiseSet.solve(
            start: date,
            end: date.adding(days: 1),
            precisionSeconds: precisionSeconds,
            // The true altitude, not the refracted one. `sunriseAltitude` is
            // defined as a true altitude, and the refraction correction is
            // deliberately clamped to zero below it, which puts a step in the
            // refracted altitude at exactly the value being solved for.
            altitude: { memo.at($0).elevationWithoutRefraction },
            target: { skylineTarget(profile, azimuth: memo.at($0).azimuth) })
    }

    /// Sunrise over the measured skyline rather than over a flat horizon.
    ///
    /// Nil when the sun never clears the skyline that day, which is the honest
    /// answer for a courtyard in winter as much as for a polar night.
    public static func localSunrise(
        date: JulianDay,
        place: Coordinates.Geographic,
        profile: HorizonProfile
    ) -> JulianDay? {
        skylineOutcome(date: date, place: place, profile: profile).firstRise
    }

    /// Sunset behind the measured skyline rather than behind a flat horizon.
    public static func localSunset(
        date: JulianDay,
        place: Coordinates.Geographic,
        profile: HorizonProfile
    ) -> JulianDay? {
        skylineOutcome(date: date, place: place, profile: profile).lastSet
    }

    /// The stretches of the day in which the sun is above the flat horizon and
    /// still behind the measured skyline: the shade a flat horizon calculation
    /// misses entirely.
    ///
    /// - Parameters:
    ///   - date: the start of the twenty four hour window to examine, normally
    ///     local midnight expressed in Universal Time.
    ///   - place: the observer.
    ///   - profile: the measured skyline.
    public static func obstructionPeriods(
        date: JulianDay,
        place: Coordinates.Geographic,
        profile: HorizonProfile
    ) -> [(start: JulianDay, end: JulianDay)] {
        // Nothing can hide behind a horizon that is nowhere raised, and saying
        // so here saves several thousand ephemeris evaluations on the case that
        // every user starts in.
        guard !profile.isFlat else { return [] }

        let end = date.adding(days: 1)
        let memo = SolarMemo(place: place)

        let flat = RiseSet.solve(
            start: date, end: end,
            precisionSeconds: precisionSeconds,
            altitude: { memo.at($0).elevationWithoutRefraction },
            target: { _ in Refraction.sunriseAltitude })
        let skyline = skylineOutcome(date: date, place: place, profile: profile)

        // Every boundary of an obstructed stretch is a crossing of one of the
        // two horizons, so the union of both crossing sets, plus the ends of the
        // window, brackets every stretch there can be. Which brackets are
        // obstructed then costs one evaluation each, at the midpoint. Deciding
        // by sampling rather than by pairing rises with sets is what keeps this
        // right when the sun crosses the skyline twice in a notch, or crosses
        // the flat horizon while already behind a ridge.
        var boundaries = [date.value, end.value]
        boundaries.append(contentsOf: flat.crossings.map { $0.julianDay.value })
        boundaries.append(contentsOf: skyline.crossings.map { $0.julianDay.value })
        boundaries.sort()

        var periods: [(start: JulianDay, end: JulianDay)] = []
        for index in 1..<boundaries.count {
            let low = boundaries[index - 1]
            let high = boundaries[index]
            guard high > low else { continue }
            guard isObstructed(JulianDay((low + high) / 2), place: place, profile: profile) else { continue }
            if let last = periods.last, last.end.value == low {
                // The boundary between these two brackets was a crossing of one
                // horizon that did not end the shade, because the other horizon
                // was already hiding the sun.
                periods[periods.count - 1] = (last.start, JulianDay(high))
            } else {
                periods.append((JulianDay(low), JulianDay(high)))
            }
        }
        return periods
    }

    /// True when the sun is up on a flat horizon and behind the skyline.
    public static func isObstructed(
        _ julianDay: JulianDay,
        place: Coordinates.Geographic,
        profile: HorizonProfile
    ) -> Bool {
        let sun = SolarPositionSPA.evaluate(julianDay: julianDay, place: place)
        let altitude = sun.elevationWithoutRefraction
        return altitude > Refraction.sunriseAltitude
            && altitude < skylineTarget(profile, azimuth: sun.azimuth)
    }
}
