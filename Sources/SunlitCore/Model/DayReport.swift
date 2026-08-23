import Foundation

/// Everything true over one local day at one place.
///
/// Built once when the place or the date changes, then read by every view. The
/// time scrubber does NOT rebuild it, because that would recompute several
/// thousand ephemeris evaluations per frame; it builds a `SkyMoment` instead,
/// which costs one.
///
/// The day is swept exactly once, into a `SolarDay`, and that one sweep serves
/// the twilight phases, both light windows and the drawn sun track. Everything
/// the home screen does not show is a method rather than a stored property, so
/// changing the date does not pay for it.
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

    /// The place has a measured skyline. Cheap to know, so it stays a property;
    /// what the skyline does to the day is in `terrain()`.
    public let hasMeasuredHorizon: Bool

    public let dayLength: TimeInterval

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
    /// Ten minutes, which is 145 points across the day. A phone screen is under
    /// 450 points wide, so that is better than one point per three, and the
    /// track is a smooth arc rather than something with detail to lose.
    public static let samplePeriodSeconds: Double = 600

    /// The single sweep of the sun this report was built from, kept so the
    /// figures below can be answered later without sweeping the day again.
    private let solarDay: SolarDay

    /// Computes a day.
    ///
    /// - Parameter date: local midnight of the day wanted, as a Julian day in
    ///   Universal Time. `Place.startOfLocalDay(containing:)` produces it.
    public static func compute(date: JulianDay, place: Place) -> DayReport {
        let geographic = place.geographic
        let end = date.adding(days: 1)

        // The one sweep. Handing it to all three solar solves is the difference
        // between one pass over the day and six.
        let solarDay = SolarDay(start: date, place: geographic)

        let phases = Twilight.phases(date: date, place: geographic, solarDay: solarDay)
        let golden = GoldenHour.golden(date: date, place: geographic, solarDay: solarDay)
        let blue = GoldenHour.blue(date: date, place: geographic, solarDay: solarDay)

        // The moon's rise altitude depends on its parallax, which changes
        // through the day, so the target is a function of time. This is the case
        // the sampling solver exists for.
        //
        // Ten minute steps. The moon moves at most two and a half degrees in
        // that time, its rise target is a single threshold rather than a band,
        // and the crossing is still bisected to one second afterwards, so the
        // coarser sweep changes what is bracketed and not what is reported.
        let moonOutcome = RiseSet.solve(
            start: date, end: end,
            sampleSeconds: 600,
            altitude: { moonAltitude(at: $0, place: geographic) },
            target: { moonRiseAltitude(at: $0) })

        let noon = date.adding(days: 0.5)
        let noonMoment = SkyMoment.at(noon, place: place)

        // The drawing grid is every second sample of the shared sweep, so the
        // sun half of the track is already computed and only the moon costs
        // anything here.
        let stride = max(1, Int((samplePeriodSeconds / solarDay.stepSeconds).rounded()))
        var samples: [Sample] = []
        samples.reserveCapacity(solarDay.samples.count / stride + 1)
        for index in Swift.stride(from: 0, to: solarDay.samples.count, by: stride) {
            let swept = solarDay.samples[index]
            samples.append(Sample(
                instant: swept.instant,
                sun: Coordinates.Horizontal(
                    azimuth: swept.azimuth, altitude: swept.apparentAltitude),
                moon: moonHorizontal(at: swept.instant, place: geographic)))
        }

        func azimuth(at instant: JulianDay?) -> Double? {
            guard let instant else { return nil }
            return SolarPositionSPA.evaluate(julianDay: instant, place: geographic).azimuth
        }

        // The day's greatest altitude is read at the sweep's refined transit,
        // not off the drawing grid: a ten minute grid can miss the peak by five
        // minutes, which at Berlin in June is a sixtieth of a degree.
        let peak = SolarPositionSPA.evaluate(
            julianDay: solarDay.maximum.instant, place: geographic)

        return DayReport(
            date: date,
            place: place,
            phases: phases,
            goldenHour: golden,
            blueHour: blue,
            moonrise: moonOutcome.firstRise,
            moonset: moonOutcome.lastSet,
            moonPhaseAtNoon: noonMoment.moonPhase,
            hasMeasuredHorizon: place.horizonProfile?.isMeasured ?? false,
            dayLength: phases.dayLength,
            maximumSolarAltitude: peak.elevation,
            sunriseAzimuth: azimuth(at: phases.sunrise),
            transitAzimuth: azimuth(at: phases.solarNoon),
            sunsetAzimuth: azimuth(at: phases.sunset),
            samples: samples,
            solarDay: solarDay)
    }

    // MARK: Computed on demand
    //
    // These three used to be stored, which meant every date change paid for
    // them whether or not anything was showing them. Between them they were
    // most of the cost of a report: the Milky Way is its own sweep of the
    // night, the terrain figures are three solves against the skyline, and the
    // change in day length is a second complete day.

    /// The Milky Way window for the night that begins on this day.
    public func milkyWayVisibility() -> MilkyWay.Visibility {
        MilkyWay.visibility(night: date, place: place.geographic)
    }

    /// What a measured skyline does to the day.
    public struct Terrain: Sendable {
        /// Periods when the sun is up but behind the measured skyline. Empty
        /// when the place has no measured profile, which is not the same as
        /// there being no obstruction.
        public let obstructionPeriods: [(start: JulianDay, end: JulianDay)]
        /// Sunrise and sunset against the measured skyline rather than a flat
        /// horizon, when there is a profile.
        public let sunrise: JulianDay?
        public let sunset: JulianDay?
    }

    public func terrain() -> Terrain {
        guard let profile = place.horizonProfile, profile.isMeasured else {
            return Terrain(obstructionPeriods: [], sunrise: nil, sunset: nil)
        }
        let geographic = place.geographic
        return Terrain(
            obstructionPeriods: Shadow.obstructionPeriods(
                date: date, place: geographic, profile: profile),
            sunrise: Shadow.localSunrise(date: date, place: geographic, profile: profile),
            sunset: Shadow.localSunset(date: date, place: geographic, profile: profile))
    }

    /// Change in day length from the previous day, in seconds. Positive while
    /// the days are drawing out.
    ///
    /// Computing the previous day's phases in full costs another day of
    /// samples, and it is one of the few figures in the app that a user checks
    /// daily, so it is computed honestly rather than approximated: it is just
    /// not computed until it is asked for.
    public func dayLengthChange() -> TimeInterval {
        let yesterday = Twilight.phases(date: date.adding(days: -1), place: place.geographic)
        return phases.dayLength - yesterday.dayLength
    }

    // MARK: Moon helpers

    static func moonHorizontal(at instant: JulianDay, place: Coordinates.Geographic) -> Coordinates.Horizontal {
        let jde = instant.adding(seconds: DeltaT.seconds(julianDay: instant))
        let lunar = MoonPosition.evaluate(julianEphemerisDay: jde)
        // The nutation comes back on the lunar result. Evaluating it again here
        // would be the same sixty three term series for the same instant.
        let nutation = lunar.nutation
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
