import Foundation

/// Everything true over one local day at one place.
///
/// Built once when the place or the date changes, then read by every view. The
/// time scrubber does NOT rebuild it, because that would recompute several
/// thousand ephemeris evaluations per frame; it builds a `SkyMoment` instead,
/// which costs one.
public struct DayReport: Sendable {

    public let date: JulianDay
    public let place: Place

    public let phases: Twilight.Phases
    public let goldenHour: (morning: GoldenHour.Window?, evening: GoldenHour.Window?)
    public let blueHour: (morning: GoldenHour.Window?, evening: GoldenHour.Window?)

    /// Moonrise and moonset within the local day. Either can be absent: the moon
    /// rises about fifty minutes later each day, so roughly once a month there
    /// is a calendar day with no moonrise in it at all. That is a fact about the
    /// moon, not a gap in the data, and the interface must say so rather than
    /// showing a dash.
    public let moonrise: JulianDay?
    public let moonset: JulianDay?
    public let moonPhaseAtNoon: MoonPosition.Phase

    /// The Milky Way window for the night that begins on this day.
    public let milkyWay: MilkyWay.Visibility

    /// Periods when the sun is up but behind the measured skyline. Empty when
    /// the place has no measured profile, which is not the same as there being
    /// no obstruction.
    public let obstructionPeriods: [(start: JulianDay, end: JulianDay)]
    public let hasMeasuredHorizon: Bool
    /// Sunrise and sunset against the measured skyline rather than a flat
    /// horizon, when there is a profile.
    public let terrainSunrise: JulianDay?
    public let terrainSunset: JulianDay?

    public let dayLength: TimeInterval
    /// Change in day length from the previous day, in seconds. Positive while
    /// the days are drawing out.
    public let dayLengthChange: TimeInterval

    public let maximumSolarAltitude: Double
    public let sunriseAzimuth: Double?
    public let transitAzimuth: Double?
    public let sunsetAzimuth: Double?

    /// A sampled track of both bodies through the day, for drawing. One entry
    /// every `samplePeriodSeconds`.
    public struct Sample: Sendable {
        public let instant: JulianDay
        public let sun: Coordinates.Horizontal
        public let moon: Coordinates.Horizontal
    }
    public let samples: [Sample]
    public static let samplePeriodSeconds: Double = 300

    /// Computes a day.
    ///
    /// - Parameter date: local midnight of the day wanted, as a Julian day in
    ///   Universal Time. `Place.startOfLocalDay(containing:)` produces it.
    public static func compute(date: JulianDay, place: Place) -> DayReport {
        let geographic = place.geographic
        let end = date.adding(days: 1)

        let phases = Twilight.phases(date: date, place: geographic)
        let golden = GoldenHour.golden(date: date, place: geographic)
        let blue = GoldenHour.blue(date: date, place: geographic)

        // The moon's rise altitude depends on its parallax, which changes
        // through the day, so the target is a function of time. This is the case
        // the sampling solver exists for.
        let moonOutcome = RiseSet.solve(
            start: date, end: end,
            altitude: { moonAltitude(at: $0, place: geographic) },
            target: { moonRiseAltitude(at: $0) })

        let noon = date.adding(days: 0.5)
        let noonMoment = SkyMoment.at(noon, place: place)

        let profile = place.horizonProfile
        let measured = profile?.isMeasured ?? false
        let obstruction: [(start: JulianDay, end: JulianDay)]
        let terrainRise: JulianDay?
        let terrainSet: JulianDay?
        if let profile, measured {
            obstruction = Shadow.obstructionPeriods(date: date, place: geographic, profile: profile)
            terrainRise = Shadow.localSunrise(date: date, place: geographic, profile: profile)
            terrainSet = Shadow.localSunset(date: date, place: geographic, profile: profile)
        } else {
            obstruction = []
            terrainRise = nil
            terrainSet = nil
        }

        // Day length change. Computing the previous day's phases in full costs
        // another day of samples, which is the single most expensive thing this
        // function does, so it is worth knowing that it is deliberate: the
        // number is one of the few figures in the app that a user checks daily.
        let yesterday = Twilight.phases(date: date.adding(days: -1), place: geographic)
        let change = phases.dayLength - yesterday.dayLength

        var samples: [Sample] = []
        let sampleCount = Int(86400.0 / samplePeriodSeconds)
        samples.reserveCapacity(sampleCount + 1)
        var maximumAltitude = -90.0
        for i in 0...sampleCount {
            let instant = date.adding(seconds: Double(i) * samplePeriodSeconds)
            let solar = SolarPositionSPA.evaluate(julianDay: instant, place: geographic)
            maximumAltitude = max(maximumAltitude, solar.elevation)
            samples.append(Sample(
                instant: instant,
                sun: solar.horizontal,
                moon: moonHorizontal(at: instant, place: geographic)))
        }

        func azimuth(at instant: JulianDay?) -> Double? {
            guard let instant else { return nil }
            return SolarPositionSPA.evaluate(julianDay: instant, place: geographic).azimuth
        }

        return DayReport(
            date: date,
            place: place,
            phases: phases,
            goldenHour: golden,
            blueHour: blue,
            moonrise: moonOutcome.firstRise,
            moonset: moonOutcome.lastSet,
            moonPhaseAtNoon: noonMoment.moonPhase,
            milkyWay: MilkyWay.visibility(night: date, place: geographic),
            obstructionPeriods: obstruction,
            hasMeasuredHorizon: measured,
            terrainSunrise: terrainRise,
            terrainSunset: terrainSet,
            dayLength: phases.dayLength,
            dayLengthChange: change,
            maximumSolarAltitude: maximumAltitude,
            sunriseAzimuth: azimuth(at: phases.sunrise),
            transitAzimuth: azimuth(at: phases.solarNoon),
            sunsetAzimuth: azimuth(at: phases.sunset),
            samples: samples)
    }

    // MARK: Moon helpers

    static func moonHorizontal(at instant: JulianDay, place: Coordinates.Geographic) -> Coordinates.Horizontal {
        let jde = instant.adding(seconds: DeltaT.seconds(julianDay: instant))
        let lunar = MoonPosition.evaluate(julianEphemerisDay: jde)
        let nutation = Nutation.evaluate(julianEphemerisDay: jde)
        let sidereal = Coordinates.apparentSiderealTime(
            julianDay: instant,
            nutationInLongitude: nutation.inLongitude,
            trueObliquity: nutation.trueObliquity)
        let topocentric = MoonPosition.topocentric(
            lunar, place: place, apparentSiderealTime: sidereal)
        let hourAngle = Coordinates.hourAngle(
            apparentSiderealTime: sidereal,
            longitude: place.longitude,
            rightAscension: topocentric.rightAscension)
        return Coordinates.horizontal(
            equatorial: Coordinates.Equatorial(
                rightAscension: topocentric.rightAscension,
                declination: topocentric.declination),
            hourAngle: hourAngle,
            latitude: place.latitude)
    }

    static func moonAltitude(at instant: JulianDay, place: Coordinates.Geographic) -> Double {
        moonHorizontal(at: instant, place: place).altitude
    }

    /// The altitude at which the moon's upper limb appears to touch the horizon.
    ///
    /// Unlike the sun's fixed -0.8333 degrees this moves through the month,
    /// because the moon's parallax lifts it by nearly a degree and that parallax
    /// changes by a tenth of a degree between perigee and apogee.
    static func moonRiseAltitude(at instant: JulianDay) -> Double {
        let jde = instant.adding(seconds: DeltaT.seconds(julianDay: instant))
        let lunar = MoonPosition.evaluate(julianEphemerisDay: jde)
        return 0.7275 * lunar.parallax - Refraction.horizontalRefraction
    }
}
