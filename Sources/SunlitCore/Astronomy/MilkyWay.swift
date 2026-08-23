import Foundation

/// The Milky Way, for the photographer deciding tonight whether the drive to a
/// dark site is worth it.
///
/// Everything here hangs off one catalogued direction, Sagittarius A*, and one
/// great circle, the galactic equator. Both are given at J2000.0 and both have
/// to be brought to the date before they mean anything on the sky: precession
/// moves the galactic centre by about 0.7 degrees per fifty years, which is
/// more than the width of the full moon.
public enum MilkyWay {

    // MARK: The galactic centre

    /// Sagittarius A*, the radio source at the dynamical centre of the Galaxy,
    /// at equinox J2000.0.
    ///
    /// Distance is left at zero, which this module reads as "not applicable".
    /// The galactic centre is twenty six thousand light years away, so it has
    /// no parallax and needs no topocentric correction. For the moon, skipping
    /// that correction moves the body by a degree; here the observer's position
    /// on the Earth changes nothing that any instrument in this app could see.
    public static let galacticCentreJ2000 = Coordinates.Equatorial(
        rightAscension: 266.41681,
        declination: -29.00775)

    /// The galactic centre referred to the mean equinox of the date.
    ///
    /// Mean, not apparent: nutation and aberration are applied later, at the
    /// point where the direction is turned into something the observer sees, so
    /// that this value can be compared directly against a star catalogue at any
    /// equinox.
    public static func galacticCentre(at julianDay: JulianDay) -> Coordinates.Equatorial {
        Coordinates.precessFromJ2000(galacticCentreJ2000, to: julianDay)
    }

    /// Where the galactic centre stands in the observer's sky.
    ///
    /// No refraction is applied. The thresholds this module works with are
    /// photographic rules of thumb well above the horizon, where refraction is
    /// a couple of arcminutes, and a refracted altitude would make the
    /// culmination test below stop being the clean `90 - latitude + declination`
    /// that lets it be checked by hand.
    public static func position(
        at julianDay: JulianDay,
        place: Coordinates.Geographic
    ) -> Coordinates.Horizontal {
        let orientation = Orientation(at: julianDay)
        return horizontal(of: galacticCentre(at: julianDay), orientation: orientation, place: place)
    }

    // MARK: Visibility

    /// Whether the galactic centre can be photographed on a given night, and if
    /// not, what stopped it.
    public struct Visibility: Sendable {
        /// The longest continuous stretch of the night during which every
        /// condition holds. Nil when there is none.
        public let window: (start: JulianDay, end: JulianDay)?
        /// The instant inside the window at which the galactic centre stands
        /// highest. Nil when there is no window.
        public let bestMoment: JulianDay?
        /// The altitude of the galactic centre at `bestMoment`, in degrees.
        /// When there is no window this is instead the highest the centre
        /// reached at any point in the night, so that a caller can tell
        /// "it never cleared three degrees" from "it stood at forty and the
        /// moon was up".
        public let bestAltitude: Double
        public let quality: Quality
        /// Which condition failed. Nil exactly when there is a window.
        public let limitingFactor: LimitingFactor?

        public init(
            window: (start: JulianDay, end: JulianDay)?,
            bestMoment: JulianDay?,
            bestAltitude: Double,
            quality: Quality,
            limitingFactor: LimitingFactor?
        ) {
            self.window = window
            self.bestMoment = bestMoment
            self.bestAltitude = bestAltitude
            self.quality = quality
            self.limitingFactor = limitingFactor
        }
    }

    public enum Quality: String, Sendable {
        case none
        case poor
        case fair
        case good
        case excellent
    }

    /// Why there is no window.
    ///
    /// A planner that says only "not visible" is useless: the answer to
    /// twilight is to wait a month, the answer to moonlight is to wait a week,
    /// and the answer to a centre that never clears the horizon is to drive
    /// south. Naming the condition is the feature.
    public enum LimitingFactor: String, Sendable {
        /// The centre never rose to `minimumAltitude` at all.
        case galacticCentreBelowHorizon
        /// The sun never went below `darkSunAltitude`, so the night never got
        /// dark. This is the northern summer case above about 48 degrees.
        case twilight
        /// A moon that is up and bright covered every dark hour the centre was
        /// high.
        case moonlight
        /// The centre was high, and the night was dark, but never at the same
        /// time. That is the wrong half of the year for this latitude.
        case season
    }

    /// The altitude the galactic centre has to clear before it is worth
    /// photographing. Lower than this and it sits in the thickest, dirtiest
    /// part of the atmosphere.
    public static let minimumAltitude = 10.0

    /// The end of astronomical twilight. Above this the sky is not
    /// astronomically dark.
    public static let darkSunAltitude = -18.0

    /// The illuminated fraction above which a moon that is up ruins the frame.
    public static let tolerableMoonIllumination = 0.3

    /// Solves one night at one place.
    ///
    /// The night runs from the local noon at or before `night` to the following
    /// local noon, so that a single call covers one uninterrupted period of
    /// darkness rather than being cut in half at midnight. Local is derived
    /// from longitude at fifteen degrees per hour, because `SunlitCore` has no
    /// time zone database and mean solar time is what the sky actually follows.
    ///
    /// - Parameter sampleSeconds: the resolution of the window edges. Sixty
    ///   seconds is a minute of accuracy on a boundary that a photographer
    ///   reads to the nearest ten.
    public static func visibility(
        night: JulianDay,
        place: Coordinates.Geographic,
        sampleSeconds: Double = 60
    ) -> Visibility {
        let start = localNoon(atOrBefore: night, longitude: place.longitude)
        let steps = max(2, Int((86400.0 / sampleSeconds).rounded()))

        var centreEverHigh = false
        var darkEver = false
        var centreHighAndDarkEver = false
        var highestOverNight = -90.0

        // The longest run of consecutive samples that satisfy every condition.
        // The first and last such samples of the night would be wrong: a moon
        // rising in the middle of the night splits the window, and reporting
        // the hull would promise hours that are not there.
        var runStart: JulianDay?
        var runEnd: JulianDay?
        var runBest: Sample?
        var bestRun: (start: JulianDay, end: JulianDay, best: Sample)?

        func closeRun() {
            guard let s = runStart, let e = runEnd, let b = runBest else { return }
            let length = e.value - s.value
            if bestRun == nil || length > (bestRun!.end.value - bestRun!.start.value) {
                bestRun = (s, e, b)
            }
            runStart = nil
            runEnd = nil
            runBest = nil
        }

        for i in 0...steps {
            let jd = start.adding(days: Double(i) / Double(steps))
            let sun = SolarPositionSPA.evaluate(julianDay: jd, place: place)
            let orientation = Orientation(sun)
            let centre = horizontal(of: galacticCentre(at: jd), orientation: orientation, place: place)
            highestOverNight = max(highestOverNight, centre.altitude)

            let centreHigh = centre.altitude > minimumAltitude
            // The geometric altitude of the sun's centre, not the refracted
            // one. Twilight is defined on the geometric altitude, and the
            // refraction model returns zero this far down anyway.
            let dark = sun.elevationWithoutRefraction < darkSunAltitude
            if centreHigh { centreEverHigh = true }
            if dark { darkEver = true }

            guard centreHigh, dark else { closeRun(); continue }
            centreHighAndDarkEver = true

            let moon = moonState(at: jd, sun: sun, orientation: orientation, place: place)
            guard !moon.ruinsTheSky else { closeRun(); continue }

            let sample = Sample(julianDay: jd, altitude: centre.altitude, moon: moon)
            if runStart == nil { runStart = jd; runBest = sample }
            runEnd = jd
            if sample.altitude > (runBest?.altitude ?? -90) { runBest = sample }
        }
        closeRun()

        guard let run = bestRun else {
            let factor: LimitingFactor
            if !centreEverHigh {
                factor = .galacticCentreBelowHorizon
            } else if !darkEver {
                factor = .twilight
            } else if !centreHighAndDarkEver {
                factor = .season
            } else {
                factor = .moonlight
            }
            return Visibility(
                window: nil, bestMoment: nil, bestAltitude: highestOverNight,
                quality: .none, limitingFactor: factor)
        }

        return Visibility(
            window: (run.start, run.end),
            bestMoment: run.best.julianDay,
            bestAltitude: run.best.altitude,
            quality: grade(run.best),
            limitingFactor: nil)
    }

    // MARK: The galactic plane

    /// The galactic equator drawn across the observer's sky, which is what the
    /// augmented reality view traces.
    ///
    /// Galactic longitude is sampled evenly from 0 to 360 at galactic latitude
    /// zero, each point converted to J2000.0 equatorial, precessed to the date,
    /// and then turned into azimuth and altitude. Points below the horizon are
    /// kept: the caller draws the part it wants, and dropping them here would
    /// hand back a curve with a hole in it that no longer closes.
    public static func galacticPlane(
        at julianDay: JulianDay,
        place: Coordinates.Geographic,
        samples: Int = 360
    ) -> [Coordinates.Horizontal] {
        guard samples > 1 else { return [] }
        let orientation = Orientation(at: julianDay)
        return (0..<samples).map { index in
            let galacticLongitude = 360.0 * Double(index) / Double(samples)
            let catalogued = Coordinates.equatorialFromGalactic(
                longitude: galacticLongitude, latitude: 0)
            let ofDate = Coordinates.precessFromJ2000(catalogued, to: julianDay)
            return horizontal(of: ofDate, orientation: orientation, place: place)
        }
    }

    // MARK: Internals

    private struct Sample {
        let julianDay: JulianDay
        let altitude: Double
        let moon: MoonState
    }

    private struct MoonState {
        let altitude: Double
        let illuminatedFraction: Double

        /// A moon that is below the horizon does not matter however bright it
        /// is, and a thin crescent does not matter however high it is. Only the
        /// two together spoil the sky.
        var ruinsTheSky: Bool {
            altitude > 0 && illuminatedFraction >= tolerableMoonIllumination
        }
    }

    /// How the celestial sphere is turned and tilted at one instant. Sidereal
    /// time and nutation are needed by every conversion here and are expensive
    /// enough to be worth carrying rather than recomputing per point of the
    /// galactic plane.
    private struct Orientation {
        let apparentSiderealTime: Double
        let nutationInLongitude: Double
        let nutationInObliquity: Double
        let trueObliquity: Double

        init(at julianDay: JulianDay) {
            let jde = julianDay.adding(seconds: DeltaT.seconds(julianDay: julianDay))
            let nutation = Nutation.evaluate(julianEphemerisDay: jde)
            self.nutationInLongitude = nutation.inLongitude
            self.nutationInObliquity = nutation.inObliquity
            self.trueObliquity = nutation.trueObliquity
            self.apparentSiderealTime = Coordinates.apparentSiderealTime(
                julianDay: julianDay,
                nutationInLongitude: nutation.inLongitude,
                trueObliquity: nutation.trueObliquity)
        }

        /// Reuses what the solar algorithm has already computed for the same
        /// instant, which halves the work in the visibility loop.
        init(_ sun: SolarPositionSPA.Result) {
            self.apparentSiderealTime = sun.apparentSiderealTime
            self.nutationInLongitude = sun.nutationInLongitude
            self.nutationInObliquity = sun.nutationInObliquity
            self.trueObliquity = sun.trueObliquity
        }
    }

    /// Mean place of date to apparent place, Meeus formula 23.1.
    ///
    /// This is not decoration. The hour angle is formed against *apparent*
    /// sidereal time, so pairing it with a mean right ascension would leave a
    /// systematic error of about fifteen arcseconds. Applying nutation to the
    /// star makes the pair consistent and brings the residual down to annual
    /// aberration alone, which is at most twenty arcseconds and below the
    /// accuracy this layer promises.
    private static func apparentPlace(
        _ mean: Coordinates.Equatorial,
        orientation: Orientation
    ) -> Coordinates.Equatorial {
        let alpha = mean.rightAscension
        let delta = mean.declination
        let epsilon = orientation.trueObliquity
        let deltaPsi = orientation.nutationInLongitude
        let deltaEpsilon = orientation.nutationInObliquity

        // The tangent blows up at the celestial poles. Nothing on the galactic
        // equator gets closer to one than 27 degrees, and the galactic centre
        // sits at -29, so the guard is a formality rather than a live case.
        let tanDelta = abs(delta) > 89.9 ? Angle.tan(89.9 * (delta < 0 ? -1 : 1)) : Angle.tan(delta)

        let deltaAlpha = (Angle.cos(epsilon) + Angle.sin(epsilon) * Angle.sin(alpha) * tanDelta) * deltaPsi
            - Angle.cos(alpha) * tanDelta * deltaEpsilon
        let deltaDelta = Angle.sin(epsilon) * Angle.cos(alpha) * deltaPsi
            + Angle.sin(alpha) * deltaEpsilon

        return Coordinates.Equatorial(
            rightAscension: Angle.normalized(alpha + deltaAlpha),
            declination: delta + deltaDelta,
            distance: mean.distance)
    }

    private static func horizontal(
        of mean: Coordinates.Equatorial,
        orientation: Orientation,
        place: Coordinates.Geographic
    ) -> Coordinates.Horizontal {
        let apparent = apparentPlace(mean, orientation: orientation)
        let hourAngle = Coordinates.hourAngle(
            apparentSiderealTime: orientation.apparentSiderealTime,
            longitude: place.longitude,
            rightAscension: apparent.rightAscension)
        return Coordinates.horizontal(
            equatorial: apparent, hourAngle: hourAngle, latitude: place.latitude)
    }

    private static func moonState(
        at julianDay: JulianDay,
        sun: SolarPositionSPA.Result,
        orientation: Orientation,
        place: Coordinates.Geographic
    ) -> MoonState {
        let moon = MoonPosition.evaluate(julianEphemerisDay: JulianDay(sun.julianEphemerisDay))
        let topocentric = MoonPosition.topocentric(
            moon, place: place, apparentSiderealTime: orientation.apparentSiderealTime)
        let hourAngle = Coordinates.hourAngle(
            apparentSiderealTime: orientation.apparentSiderealTime,
            longitude: place.longitude,
            rightAscension: topocentric.rightAscension)
        let horizontal = Coordinates.horizontal(
            equatorial: Coordinates.Equatorial(
                rightAscension: topocentric.rightAscension,
                declination: topocentric.declination),
            hourAngle: hourAngle,
            latitude: place.latitude)
        let phase = MoonPosition.phase(
            moon: moon,
            sunRightAscension: sun.geocentricRightAscension,
            sunDeclination: sun.geocentricDeclination,
            sunDistanceAU: sun.radiusVector,
            sunApparentLongitude: sun.apparentLongitude)
        return MoonState(altitude: horizontal.altitude, illuminatedFraction: phase.illuminatedFraction)
    }

    /// Grades the best moment of a window that exists.
    ///
    /// Altitude carries the grade because it is what decides how much
    /// atmosphere and how much horizon glow the core is seen through. A moon
    /// that is up costs one grade even when it is inside the tolerated
    /// fraction, because a quarter moon still lifts the sky background.
    private static func grade(_ best: Sample) -> Quality {
        let base: Quality
        switch best.altitude {
        case 30...: base = .excellent
        case 20..<30: base = .good
        case 15..<20: base = .fair
        default: base = .poor
        }
        guard best.moon.altitude > 0 else { return base }
        switch base {
        case .excellent: return .good
        case .good: return .fair
        default: return .poor
        }
    }

    /// The local noon at or before an instant.
    ///
    /// Integer Julian day values fall at noon, so flooring the instant shifted
    /// into local mean time picks the noon that opens the night containing it.
    private static func localNoon(atOrBefore julianDay: JulianDay, longitude: Double) -> JulianDay {
        let offsetDays = longitude / 360.0
        let noon = (julianDay.value + offsetDays).rounded(.down)
        return JulianDay(noon - offsetDays)
    }
}
