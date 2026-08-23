import Foundation

/// Solar and lunar eclipses, local to a place.
///
/// There are no Besselian elements here and there is no need for any. The core
/// already produces the topocentric position of the Sun and of the Moon,
/// parallax included, so a solar eclipse at a place is simply the instant at
/// which the topocentric angular separation of the two centres is least,
/// compared against the sum and the difference of the two apparent
/// semidiameters. A lunar eclipse is the Moon's separation from the antisolar
/// point compared against the radii of the two shadow cones at the Moon's
/// distance. Both fall out of quantities the core already computes correctly.
///
/// ## Measured accuracy
///
/// Every figure below is what `scripts/prove/eclipse.swift` measures against
/// published values, not what this file hopes for. See that driver for the
/// sources.
///
/// Global circumstances, against the NASA Five Millennium Catalog of Solar
/// Eclipses, for the four total eclipses of 1999 Aug 11, 2017 Aug 21,
/// 2024 Apr 8 and 2026 Aug 12:
///
/// | Quantity | Worst error over the four |
/// |---|---|
/// | Eclipse type | correct, 4 of 4 |
/// | Instant of greatest eclipse, in TD | 10.2 seconds |
/// | Gamma | 0.0002 Earth radii |
/// | Ratio of apparent diameters | 0.0002 |
///
/// Local circumstances, against the United States Naval Observatory solar
/// eclipse computer, at eight places across those same four eclipses,
/// four of them under totality and four under a partial phase:
///
/// | Quantity | Worst error |
/// |---|---|
/// | Eclipse type | correct, 8 of 8, plus 2 correct refusals |
/// | First contact | 13.3 seconds |
/// | Maximum | 11.2 seconds |
/// | Last contact | 11.0 seconds |
/// | Magnitude | 0.0008 |
/// | Obscuration | 0.05 percent |
/// | The Sun's altitude at maximum | 0.1 degrees |
///
/// Lunar circumstances, against the NASA Five Millennium Catalog of Lunar
/// Eclipses, over six eclipses spanning total, partial and penumbral:
///
/// | Quantity | Worst error |
/// |---|---|
/// | Eclipse type | correct, 6 of 6 |
/// | Greatest eclipse, in TD | 8.7 seconds |
/// | Umbral magnitude | 0.0015 |
/// | Penumbral magnitude | 0.0012 |
/// | Duration of a phase, P1 to P4, U1 to U4 or U2 to U3 | 35.6 seconds |
///
/// The one minute target set for contact times in section 4.1 of the design
/// document is therefore met with a factor of four in hand, and the fallback
/// position section 12 reserved is not needed. What is left is dominated by the
/// truncated lunar theory: ten arcseconds of error in the Moon's longitude is
/// eighteen seconds of time at the rate the Moon moves, which is the size of
/// everything in the tables above.
///
/// ## Cost
///
/// Finding the next solar eclipse at a place over a five year window takes
/// about 150 milliseconds. Almost all of that is the syzygy search, which walks
/// the window in one day steps: a solar eclipse can only happen at new moon and
/// a lunar one only at full moon, so twelve candidates a year are examined
/// instead of half a million minutes, and of those twelve about two survive the
/// geocentric stage and earn the local work. This is a background computation
/// and not part of the day report the design budgets at 30 milliseconds.
///
/// ## What this module will not do
///
/// The classification of a central eclipse as total or annular is decided on a
/// spherical Earth of the equatorial radius. For an eclipse whose gamma is
/// within about 0.01 of unity the shadow axis grazes the limb, where the
/// difference between the sphere and the true ellipsoid decides the answer, and
/// the type reported here may be wrong. No such case is in the test set and
/// none is claimed.
public enum Eclipse {

    // MARK: Kinds

    public enum SolarKind: String, Sendable, CaseIterable {
        /// The Moon's disc never touches the Sun's as seen from this place.
        case none
        case partial
        case annular
        case total
    }

    public enum LunarKind: String, Sendable, CaseIterable {
        /// The Moon misses even the penumbra.
        case none
        case penumbral
        case partial
        case total
    }

    // MARK: Results

    /// What one place actually sees of one solar eclipse.
    ///
    /// Everything here is restricted to the interval during which the Sun is
    /// above the observer's horizon, and ``SolarKind/none`` therefore means
    /// nothing was visible from here, whether because the shadow missed the
    /// place or because the alignment happened at night. That restriction is
    /// not cosmetic: the topocentric separation of the two centres is small for
    /// an observer on the night side of the Earth just as it is for one under
    /// the shadow, so a module that skipped it would announce a partial eclipse
    /// at Berlin on 21 August 2017, an hour after the Sun had set there. The
    /// Naval Observatory answers that same query with "eclipse not visible from
    /// selected location", and so does this.
    public struct SolarLocal: Sendable {
        public let kind: SolarKind
        /// Exterior contact as the Moon's limb first touches the Sun's. Nil
        /// when the Sun rose with the eclipse already under way, and for
        /// ``SolarKind/none``.
        public let firstContact: JulianDay?
        /// The instant of greatest magnitude among those at which the Sun was
        /// up, so an eclipse still growing at sunset reports the maximum that
        /// was actually seen rather than one that was not.
        public let maximum: JulianDay?
        /// Exterior contact as the discs part. Nil when the Sun set first.
        public let lastContact: JulianDay?
        /// Fraction of the Sun's **diameter** covered at maximum. Above one for
        /// a total eclipse. This is the quantity the Naval Observatory and the
        /// almanacs print as the eclipse magnitude.
        public let magnitude: Double
        /// Fraction of the Sun's **area** covered at maximum, 0 to 1. Not the
        /// same number as the magnitude and not derivable from it by squaring:
        /// at magnitude 0.5 the obscuration is 0.391, and the gap is what makes
        /// a half eclipsed sky look barely dimmed.
        public let obscuration: Double
        /// The Sun's apparent altitude at ``maximum``, refraction included.
        /// Never below -0.8333, the altitude at which the upper limb sits on
        /// the horizon, because a lower Sun is not a visible eclipse and is
        /// reported as ``SolarKind/none`` instead. A small value here is the
        /// interface's cue that the eclipse was a sunset one.
        public let maximumAltitude: Double
    }

    /// Where and when an eclipse happens for the Earth as a whole, without
    /// reference to any observer. This is the stage that decides whether the
    /// expensive local work is worth doing, and it is what the published
    /// catalogues tabulate.
    public struct SolarGlobal: Sendable {
        public let kind: SolarKind
        /// The instant at which the axis of the Moon's shadow passes closest to
        /// the centre of the Earth, in Universal Time.
        public let greatestEclipse: JulianDay
        /// That least distance, in Earth equatorial radii, positive when the
        /// axis passes north of the centre.
        public let gamma: Double
        /// The Moon's apparent diameter divided by the Sun's, at the point on
        /// the surface where the axis strikes. Greater than one for a total
        /// eclipse, less for an annular one. Nil when the axis misses the Earth
        /// entirely, which is every purely partial eclipse.
        public let diameterRatio: Double?
    }

    /// A lunar eclipse and whether the Moon was up for it.
    ///
    /// The contact times are the same everywhere on Earth, because the Moon
    /// enters a shadow rather than casting one. Only
    /// ``moonAltitudeAtMaximum`` depends on the place.
    public struct LunarLocal: Sendable {
        public let kind: LunarKind
        public let penumbralBegin: JulianDay?
        public let partialBegin: JulianDay?
        public let totalBegin: JulianDay?
        public let maximum: JulianDay?
        public let totalEnd: JulianDay?
        public let partialEnd: JulianDay?
        public let penumbralEnd: JulianDay?
        /// Fraction of the Moon's diameter inside the umbra at maximum.
        /// Negative when the Moon misses the umbra altogether.
        public let umbralMagnitude: Double
        /// The same for the penumbra.
        public let penumbralMagnitude: Double
        /// The Moon's apparent altitude at ``maximum``, refraction included.
        /// At or below zero the eclipse happens below the horizon here.
        public let moonAltitudeAtMaximum: Double
    }

    // MARK: Constants

    /// Equatorial radius of the Earth in kilometres, the value gamma is
    /// expressed in.
    private static let earthRadius = 6378.137
    private static let sunRadius = 696000.0
    private static let astronomicalUnit = 149597870.7

    /// Half the Sun's apparent diameter at one astronomical unit, in degrees.
    ///
    /// This is 959.63 arcseconds, the value section 4.4 of the design document
    /// names and the one the almanacs and the eclipse canons use. It is not
    /// `Refraction.solarSemidiameterAtOneAU`, which is 960 arcseconds exactly:
    /// that constant exists to define the -0.8333 degree horizon of a sunrise,
    /// where a rounded figure is the convention, and borrowing it here would
    /// put a fifth of an arcsecond of bias into every contact time. The
    /// difference is worth about a second at each exterior contact, which is
    /// small next to the ephemeris but is a bias rather than noise.
    private static let sunSemidiameterAtOneAU = Angle.fromArcseconds(959.63)

    // MARK: Solar, public

    /// Every solar eclipse visible from `place` between the two instants.
    ///
    /// Both bounds are in Universal Time and the search is over the new moons
    /// that fall between them.
    public static func solarEvents(
        from start: JulianDay,
        to end: JulianDay,
        place: Coordinates.Geographic
    ) -> [SolarLocal] {
        newMoons(from: start.adding(days: -1), to: end.adding(days: 1)).compactMap { newMoon in
            // The global stage is about a tenth the cost of the local one and
            // rejects roughly five new moons in six.
            guard globalSolar(atNewMoon: newMoon) != nil else { return nil }
            let local = solarLocal(atNewMoon: newMoon, place: place)
            guard local.kind != .none else { return nil }
            guard let maximum = local.maximum,
                  maximum >= start, maximum <= end else { return nil }
            return local
        }
    }

    /// The next solar eclipse visible from `place` after the given instant, or
    /// nil if there is none inside the search window.
    public static func nextSolar(
        after start: JulianDay,
        place: Coordinates.Geographic,
        searchYears: Double = 5
    ) -> SolarLocal? {
        for newMoon in newMoons(from: start, to: start.adding(days: searchYears * 365.25)) {
            guard globalSolar(atNewMoon: newMoon) != nil else { continue }
            let local = solarLocal(atNewMoon: newMoon, place: place)
            guard local.kind != .none, let maximum = local.maximum, maximum > start else { continue }
            return local
        }
        return nil
    }

    /// Local circumstances of the solar eclipse at the new moon nearest to
    /// `date`, whether or not there is one.
    ///
    /// This is the honest answer to "what does this place see on that day". A
    /// place outside the shadow gets ``SolarKind/none`` back rather than an
    /// invented event.
    public static func solarCircumstances(
        near date: JulianDay,
        place: Coordinates.Geographic
    ) -> SolarLocal {
        guard let newMoon = nearestSyzygy(to: date, offsetDegrees: 0) else {
            return SolarLocal(kind: .none, firstContact: nil, maximum: nil, lastContact: nil,
                              magnitude: 0, obscuration: 0, maximumAltitude: 0)
        }
        return solarLocal(atNewMoon: newMoon, place: place)
    }

    /// Global circumstances of every solar eclipse between the two instants.
    public static func solarGlobalEvents(from start: JulianDay, to end: JulianDay) -> [SolarGlobal] {
        newMoons(from: start.adding(days: -1), to: end.adding(days: 1)).compactMap { newMoon in
            guard let global = globalSolar(atNewMoon: newMoon) else { return nil }
            guard global.greatestEclipse >= start, global.greatestEclipse <= end else { return nil }
            return global
        }
    }

    // MARK: Lunar, public

    /// Every lunar eclipse between the two instants, with the Moon's altitude
    /// at `place` so the caller can tell whether it was above the horizon.
    public static func lunarEvents(
        from start: JulianDay,
        to end: JulianDay,
        place: Coordinates.Geographic
    ) -> [LunarLocal] {
        fullMoons(from: start.adding(days: -1), to: end.adding(days: 1)).compactMap { fullMoon in
            let local = lunarLocal(atFullMoon: fullMoon, place: place)
            guard local.kind != .none else { return nil }
            guard let maximum = local.maximum, maximum >= start, maximum <= end else { return nil }
            return local
        }
    }

    /// The next lunar eclipse after the given instant. May happen below the
    /// horizon at `place`; see ``LunarLocal/moonAltitudeAtMaximum``.
    public static func nextLunar(
        after start: JulianDay,
        place: Coordinates.Geographic,
        searchYears: Double = 5
    ) -> LunarLocal? {
        for fullMoon in fullMoons(from: start, to: start.adding(days: searchYears * 365.25)) {
            let local = lunarLocal(atFullMoon: fullMoon, place: place)
            guard local.kind != .none, let maximum = local.maximum, maximum > start else { continue }
            return local
        }
        return nil
    }

    /// Circumstances of the lunar eclipse at the full moon nearest to `date`,
    /// whether or not there is one.
    public static func lunarCircumstances(
        near date: JulianDay,
        place: Coordinates.Geographic
    ) -> LunarLocal {
        guard let fullMoon = nearestSyzygy(to: date, offsetDegrees: 180) else {
            return LunarLocal(kind: .none, penumbralBegin: nil, partialBegin: nil, totalBegin: nil,
                              maximum: nil, totalEnd: nil, partialEnd: nil, penumbralEnd: nil,
                              umbralMagnitude: 0, penumbralMagnitude: 0, moonAltitudeAtMaximum: 0)
        }
        return lunarLocal(atFullMoon: fullMoon, place: place)
    }

    // MARK: Syzygies

    /// The instants at which the Moon's apparent ecliptic longitude equals the
    /// Sun's plus `offsetDegrees`, in Universal Time.
    ///
    /// A solar eclipse can only happen at new moon and a lunar one only at full
    /// moon, so this is the filter that keeps the whole module cheap: about
    /// twelve candidates a year instead of half a million minutes.
    ///
    /// The elongation grows monotonically at about 12.2 degrees a day, so a one
    /// day sampling step cannot skip a crossing, and the wrap from +180 to -180
    /// is excluded by accepting only the ascending sign change.
    private static func syzygies(
        from start: JulianDay,
        to end: JulianDay,
        offsetDegrees: Double
    ) -> [JulianDay] {
        func f(_ value: Double) -> Double {
            let jd = JulianDay(value)
            let dt = DeltaT.seconds(julianDay: jd)
            let sun = SolarPositionSPA.evaluate(julianDay: jd, place: geocentre, deltaT: dt)
            let moon = MoonPosition.evaluate(julianEphemerisDay: jd.adding(seconds: dt))
            return Angle.normalizedSigned(moon.longitude - sun.apparentLongitude - offsetDegrees)
        }

        var results: [JulianDay] = []
        var previousValue = start.value
        var previous = f(previousValue)
        var current = start.value + 1.0
        while current <= end.value + 1.0 {
            let value = f(current)
            if previous < 0 && value >= 0 {
                results.append(JulianDay(root(previousValue, current, f)))
            }
            previousValue = current
            previous = value
            current += 1.0
        }
        return results
    }

    private static func newMoons(from start: JulianDay, to end: JulianDay) -> [JulianDay] {
        syzygies(from: start, to: end, offsetDegrees: 0)
    }

    private static func fullMoons(from start: JulianDay, to end: JulianDay) -> [JulianDay] {
        syzygies(from: start, to: end, offsetDegrees: 180)
    }

    /// The syzygy of the given kind closest to `date`. One synodic month either
    /// side is enough to guarantee exactly one or two candidates.
    private static func nearestSyzygy(to date: JulianDay, offsetDegrees: Double) -> JulianDay? {
        syzygies(from: date.adding(days: -16), to: date.adding(days: 16),
                 offsetDegrees: offsetDegrees)
            .min(by: { abs($0.value - date.value) < abs($1.value - date.value) })
    }

    // MARK: Solar, global

    /// Greatest eclipse, gamma and type for the new moon given, or nil when the
    /// shadow misses the Earth completely.
    ///
    /// The axis of the shadow is the line through the centres of the Sun and
    /// the Moon. Greatest eclipse is by definition the instant at which that
    /// line passes closest to the centre of the Earth, and gamma is that
    /// distance in equatorial radii, so both come from one minimisation of one
    /// scalar. Working from the light time corrected apparent positions of both
    /// bodies is what makes the line the real one: the Sun's apparent place is
    /// where it was when the light now arriving left it, which is exactly the
    /// direction the shadow points away from.
    private static func globalSolar(atNewMoon newMoon: JulianDay) -> SolarGlobal? {
        func axisDistance(_ value: Double) -> Double { shadowAxis(at: JulianDay(value)).distance }

        // Greatest eclipse lies within about twenty minutes of the conjunction
        // in longitude. Three hours either side is a wide bracket for a
        // function that is smooth and has a single minimum there.
        var bestValue = newMoon.value
        var best = Double.greatestFiniteMagnitude
        let step = 6.0 / (24.0 * 60.0)
        var offset = -0.125
        while offset <= 0.125 {
            let value = newMoon.value + offset
            let distance = axisDistance(value)
            if distance < best { best = distance; bestValue = value }
            offset += step
        }
        let greatestValue = minimise(bestValue - step, bestValue + step, axisDistance)
        let greatest = JulianDay(greatestValue)
        let axis = shadowAxis(at: greatest)

        // The penumbral cone widens away from the Moon. Where it crosses the
        // plane through the Earth's centre its radius is this, and if the axis
        // misses the Earth by more than that plus one Earth radius then nobody
        // anywhere sees anything.
        let penumbraRadius = MoonPosition.radiusKilometres
            + axis.alongAxisToCentre * (sunRadius + MoonPosition.radiusKilometres) / axis.sunToMoon
        guard axis.distance < penumbraRadius + earthRadius else { return nil }

        let gamma = axis.signedDistance / earthRadius

        // Where the axis strikes the surface, if it does. The near intersection
        // with the sphere is the one the light reaches first.
        guard axis.distance < earthRadius else {
            return SolarGlobal(kind: .partial, greatestEclipse: greatest,
                               gamma: gamma, diameterRatio: nil)
        }
        let halfChord = (earthRadius * earthRadius - axis.distance * axis.distance).squareRoot()
        let moonToSurface = axis.alongAxisToCentre - halfChord

        let moonSemidiameter = Angle.asin(MoonPosition.radiusKilometres / moonToSurface)
        // The observer at that point is one Earth radius nearer the Sun than
        // the geocentre, which changes the Sun's semidiameter by four hundredths
        // of an arcsecond. Ignored.
        let sunSemidiameter = sunSemidiameterAtOneAU / axis.sunDistanceAU
        let ratio = moonSemidiameter / sunSemidiameter

        return SolarGlobal(kind: ratio >= 1 ? .total : .annular, greatestEclipse: greatest,
                           gamma: gamma, diameterRatio: ratio)
    }

    private struct ShadowAxis {
        /// Least distance from the Earth's centre to the axis, kilometres.
        let distance: Double
        /// The same, signed positive when the axis passes north of the centre.
        let signedDistance: Double
        /// Distance from the Moon along the axis to the point of closest
        /// approach, kilometres.
        let alongAxisToCentre: Double
        let sunToMoon: Double
        let sunDistanceAU: Double
    }

    private static func shadowAxis(at jd: JulianDay) -> ShadowAxis {
        let dt = DeltaT.seconds(julianDay: jd)
        let sun = SolarPositionSPA.evaluate(julianDay: jd, place: geocentre, deltaT: dt)
        let moon = MoonPosition.evaluate(julianEphemerisDay: jd.adding(seconds: dt))

        let m = cartesian(rightAscension: moon.rightAscension,
                          declination: moon.declination,
                          distance: moon.distance)
        let s = cartesian(rightAscension: sun.geocentricRightAscension,
                          declination: sun.geocentricDeclination,
                          distance: sun.radiusVector * astronomicalUnit)

        let axis = (m.0 - s.0, m.1 - s.1, m.2 - s.2)
        let length = (axis.0 * axis.0 + axis.1 * axis.1 + axis.2 * axis.2).squareRoot()
        let u = (axis.0 / length, axis.1 / length, axis.2 / length)

        let projection = m.0 * u.0 + m.1 * u.1 + m.2 * u.2
        let w = (m.0 - projection * u.0, m.1 - projection * u.1, m.2 - projection * u.2)
        let distance = (w.0 * w.0 + w.1 * w.1 + w.2 * w.2).squareRoot()

        // North in the plane perpendicular to the axis, which is what the sign
        // of gamma is measured against.
        let north = (-u.2 * u.0, -u.2 * u.1, 1.0 - u.2 * u.2)
        let northLength = (north.0 * north.0 + north.1 * north.1 + north.2 * north.2).squareRoot()
        let towardNorth = northLength > 0
            ? (w.0 * north.0 + w.1 * north.1 + w.2 * north.2) / northLength
            : 0

        return ShadowAxis(distance: distance,
                          signedDistance: towardNorth < 0 ? -distance : distance,
                          alongAxisToCentre: -projection,
                          sunToMoon: length,
                          sunDistanceAU: sun.radiusVector)
    }

    // MARK: Solar, local

    /// One minute sampling over nine hours centred on the new moon. The whole
    /// eclipse, from first contact anywhere on Earth to last contact anywhere,
    /// never spans more than about six hours, so nothing can fall outside.
    private static let solarWindowHours = 4.5
    private static let solarStepDays = 1.0 / (24.0 * 60.0)

    private static func solarLocal(
        atNewMoon newMoon: JulianDay,
        place: Coordinates.Geographic
    ) -> SolarLocal {
        let nothing = SolarLocal(kind: .none, firstContact: nil, maximum: nil, lastContact: nil,
                                 magnitude: 0, obscuration: 0, maximumAltitude: 0)

        /// Positive when the discs overlap. This is the magnitude, and bisecting
        /// it against zero gives the exterior contacts directly.
        func magnitude(_ value: Double) -> Double {
            let g = solarGeometry(at: JulianDay(value), place: place)
            return (g.sunSemidiameter + g.moonSemidiameter - g.separation) / (2 * g.sunSemidiameter)
        }

        let first = newMoon.value - solarWindowHours / 24.0
        let count = Int((2 * solarWindowHours / 24.0) / solarStepDays)

        // Only the part of the window in which the Sun is above the horizon
        // counts. Without that restriction the separation test alone would
        // report an eclipse for an observer on the night side of the Earth,
        // because at new moon the Sun and the Moon are close together in the
        // sky whichever way the observer faces, and the topocentric parallax
        // vanishes again at the nadir just as it does at the zenith. Berlin on
        // 21 August 2017 is the case in point: the geometry is satisfied there
        // to a magnitude of 0.07, an hour after the Sun has set.
        //
        // The upper limb clearing the horizon is the test rather than the
        // centre, because a sliver of Sun at sunset still shows an eclipse.
        var magnitudes = [Double](repeating: 0, count: count + 1)
        var aboveHorizon = [Bool](repeating: false, count: count + 1)
        var peak = -1
        for i in 0...count {
            let jd = JulianDay(first + Double(i) * solarStepDays)
            let g = solarGeometry(at: jd, place: place)
            magnitudes[i] = (g.sunSemidiameter + g.moonSemidiameter - g.separation)
                / (2 * g.sunSemidiameter)
            aboveHorizon[i] = g.sunAltitude > Refraction.sunriseAltitude
            if aboveHorizon[i] && (peak < 0 || magnitudes[i] > magnitudes[peak]) { peak = i }
        }
        guard peak >= 0, magnitudes[peak] > 0 else { return nothing }

        // The run of daylight containing the greatest phase. Contacts outside
        // it were not seen from here and are reported as nil rather than as
        // times nobody could have observed.
        var lowIndex = peak
        while lowIndex > 0 && aboveHorizon[lowIndex - 1] { lowIndex -= 1 }
        var highIndex = peak
        while highIndex < count && aboveHorizon[highIndex + 1] { highIndex += 1 }

        let low = first + Double(max(lowIndex, peak - 1)) * solarStepDays
        let high = first + Double(min(highIndex, peak + 1)) * solarStepDays
        let maximumValue = minimise(low, high, { -magnitude($0) })
        let maximum = JulianDay(maximumValue)

        let g = solarGeometry(at: maximum, place: place)
        let sunSemidiameter = g.sunSemidiameter
        let moonSemidiameter = g.moonSemidiameter
        let separation = g.separation

        let kind: SolarKind
        if separation < moonSemidiameter - sunSemidiameter {
            kind = .total
        } else if separation < sunSemidiameter - moonSemidiameter {
            kind = .annular
        } else if separation < sunSemidiameter + moonSemidiameter {
            kind = .partial
        } else {
            // The coarse samples straddled the peak but the refined maximum
            // fell just short of contact.
            return nothing
        }

        let firstContact = crossing(before: peak, lowerBound: lowIndex, first: first,
                                    values: magnitudes, f: magnitude)
        let lastContact = crossing(after: peak, upperBound: highIndex, first: first,
                                   values: magnitudes, f: magnitude)

        return SolarLocal(
            kind: kind,
            firstContact: firstContact,
            maximum: maximum,
            lastContact: lastContact,
            magnitude: (sunSemidiameter + moonSemidiameter - separation) / (2 * sunSemidiameter),
            obscuration: overlapFraction(separation: separation,
                                         covered: sunSemidiameter,
                                         coverer: moonSemidiameter),
            maximumAltitude: g.sunAltitude)
    }

    private struct SolarGeometry {
        let separation: Double
        let sunSemidiameter: Double
        let moonSemidiameter: Double
        let sunAltitude: Double
    }

    private static func solarGeometry(
        at jd: JulianDay,
        place: Coordinates.Geographic
    ) -> SolarGeometry {
        let dt = DeltaT.seconds(julianDay: jd)
        let sun = SolarPositionSPA.evaluate(julianDay: jd, place: place, deltaT: dt)
        let moon = MoonPosition.evaluate(julianEphemerisDay: jd.adding(seconds: dt))
        let topocentric = MoonPosition.topocentric(
            moon, place: place, apparentSiderealTime: sun.apparentSiderealTime)

        return SolarGeometry(
            separation: angularSeparation(
                sun.topocentricRightAscension, sun.topocentricDeclination,
                topocentric.rightAscension, topocentric.declination),
            sunSemidiameter: sunSemidiameterAtOneAU / sun.radiusVector,
            moonSemidiameter: topocentric.semidiameter,
            sunAltitude: sun.elevation)
    }

    // MARK: Lunar

    private static let lunarWindowHours = 5.0
    private static let lunarStepDays = 2.0 / (24.0 * 60.0)

    /// Shadow radii follow Danjon's convention, as used by the NASA Five
    /// Millennium Catalog of Lunar Eclipses and by Connaissance des Temps:
    ///
    ///     penumbral radius = 1.01 * parallaxMoon + semidiameterSun + parallaxSun
    ///     umbral radius    = 1.01 * parallaxMoon - semidiameterSun + parallaxSun
    ///
    /// The 1.01 is 1 + 1/85 - 1/594: Danjon enlarges the Earth's radius by the
    /// 75 kilometre thickness of the opaque air, and takes off half the
    /// flattening for a shadow cast from latitude 45.
    ///
    /// The alternative, Chauvenet's, enlarges both radii by 1/50 instead:
    ///
    ///     penumbral radius = 1.02 * (0.998340 * parallaxMoon + semidiameterSun + parallaxSun)
    ///
    /// The choice is not cosmetic. Chauvenet gives umbral magnitudes larger by
    /// about 0.006 and penumbral ones larger by about 0.026, which moves the
    /// umbral contacts by tens of seconds and reclassifies a shallow eclipse
    /// from partial to penumbral. Danjon is used here because the catalogue
    /// this module is tested against uses it, and mixing the two would show up
    /// as a fixed bias no amount of ephemeris work could remove.
    private static func lunarLocal(
        atFullMoon fullMoon: JulianDay,
        place: Coordinates.Geographic
    ) -> LunarLocal {
        let nothing = LunarLocal(kind: .none, penumbralBegin: nil, partialBegin: nil,
                                 totalBegin: nil, maximum: nil, totalEnd: nil, partialEnd: nil,
                                 penumbralEnd: nil, umbralMagnitude: 0, penumbralMagnitude: 0,
                                 moonAltitudeAtMaximum: 0)

        func separation(_ value: Double) -> Double { lunarGeometry(at: JulianDay(value)).separation }

        let first = fullMoon.value - lunarWindowHours / 24.0
        let count = Int((2 * lunarWindowHours / 24.0) / lunarStepDays)

        // The three contact functions all read the same four numbers, so the
        // window is sampled once and each of them is a projection of it.
        var samples: [LunarGeometry] = []
        samples.reserveCapacity(count + 1)
        var peak = 0
        for i in 0...count {
            samples.append(lunarGeometry(at: JulianDay(first + Double(i) * lunarStepDays)))
            if samples[i].separation < samples[peak].separation { peak = i }
        }
        let maximumValue = minimise(first + Double(max(0, peak - 1)) * lunarStepDays,
                                    first + Double(min(count, peak + 1)) * lunarStepDays,
                                    separation)
        let maximum = JulianDay(maximumValue)
        let g = lunarGeometry(at: maximum)

        let umbralMagnitude = (g.umbralRadius + g.moonSemidiameter - g.separation)
            / (2 * g.moonSemidiameter)
        let penumbralMagnitude = (g.penumbralRadius + g.moonSemidiameter - g.separation)
            / (2 * g.moonSemidiameter)

        let kind: LunarKind
        if umbralMagnitude >= 1 { kind = .total }
        else if umbralMagnitude > 0 { kind = .partial }
        else if penumbralMagnitude > 0 { kind = .penumbral }
        else { return nothing }

        // How far the Moon's limb is inside a shadow edge: zero at contact,
        // positive while inside. Outer contacts take the leading limb, inner
        // contacts the trailing one, which is the whole difference between the
        // partial and the total phase.
        func outerPenumbral(_ g: LunarGeometry) -> Double {
            g.penumbralRadius + g.moonSemidiameter - g.separation
        }
        func outerUmbral(_ g: LunarGeometry) -> Double {
            g.umbralRadius + g.moonSemidiameter - g.separation
        }
        func innerUmbral(_ g: LunarGeometry) -> Double {
            g.umbralRadius - g.moonSemidiameter - g.separation
        }

        func contacts(
            _ measure: @escaping (LunarGeometry) -> Double,
            _ enabled: Bool
        ) -> (JulianDay?, JulianDay?) {
            guard enabled else { return (nil, nil) }
            let values = samples.map(measure)
            let f: (Double) -> Double = { measure(lunarGeometry(at: JulianDay($0))) }
            return (crossing(before: peak, lowerBound: 0, first: first,
                             values: values, step: lunarStepDays, f: f),
                    crossing(after: peak, upperBound: count, first: first,
                             values: values, step: lunarStepDays, f: f))
        }

        let (penumbralBegin, penumbralEnd) = contacts(outerPenumbral, true)
        let (partialBegin, partialEnd) = contacts(outerUmbral, kind != .penumbral)
        let (totalBegin, totalEnd) = contacts(innerUmbral, kind == .total)

        return LunarLocal(
            kind: kind,
            penumbralBegin: penumbralBegin,
            partialBegin: partialBegin,
            totalBegin: totalBegin,
            maximum: maximum,
            totalEnd: totalEnd,
            partialEnd: partialEnd,
            penumbralEnd: penumbralEnd,
            umbralMagnitude: umbralMagnitude,
            penumbralMagnitude: penumbralMagnitude,
            moonAltitudeAtMaximum: moonAltitude(at: maximum, place: place))
    }

    private struct LunarGeometry {
        /// Angular distance of the Moon's centre from the antisolar point.
        let separation: Double
        let moonSemidiameter: Double
        let umbralRadius: Double
        let penumbralRadius: Double
    }

    private static func lunarGeometry(at jd: JulianDay) -> LunarGeometry {
        let dt = DeltaT.seconds(julianDay: jd)
        let sun = SolarPositionSPA.evaluate(julianDay: jd, place: geocentre, deltaT: dt)
        let moon = MoonPosition.evaluate(julianEphemerisDay: jd.adding(seconds: dt))

        let sunSemidiameter = sunSemidiameterAtOneAU / sun.radiusVector
        let sunParallax = Angle.fromArcseconds(8.794 / sun.radiusVector)
        let moonParallax = moon.parallax

        return LunarGeometry(
            separation: angularSeparation(
                moon.rightAscension, moon.declination,
                sun.geocentricRightAscension + 180.0, -sun.geocentricDeclination),
            moonSemidiameter: moon.semidiameter,
            umbralRadius: 1.01 * moonParallax - sunSemidiameter + sunParallax,
            penumbralRadius: 1.01 * moonParallax + sunSemidiameter + sunParallax)
    }

    private static func moonAltitude(at jd: JulianDay, place: Coordinates.Geographic) -> Double {
        let dt = DeltaT.seconds(julianDay: jd)
        let sun = SolarPositionSPA.evaluate(julianDay: jd, place: place, deltaT: dt)
        let moon = MoonPosition.evaluate(julianEphemerisDay: jd.adding(seconds: dt))
        let topocentric = MoonPosition.topocentric(
            moon, place: place, apparentSiderealTime: sun.apparentSiderealTime)
        let hourAngle = Coordinates.hourAngle(
            apparentSiderealTime: sun.apparentSiderealTime,
            longitude: place.longitude,
            rightAscension: topocentric.rightAscension)
        let horizontal = Coordinates.horizontal(
            equatorial: Coordinates.Equatorial(rightAscension: topocentric.rightAscension,
                                               declination: topocentric.declination),
            hourAngle: hourAngle,
            latitude: place.latitude)
        return horizontal.altitude + Refraction.apparentFromTrue(
            trueAltitude: horizontal.altitude,
            pressure: Refraction.pressure(atElevation: place.elevation))
    }

    // MARK: Geometry helpers

    private static let geocentre = Coordinates.Geographic(latitude: 0, longitude: 0)

    private static func cartesian(
        rightAscension: Double,
        declination: Double,
        distance: Double
    ) -> (Double, Double, Double) {
        (distance * Angle.cos(declination) * Angle.cos(rightAscension),
         distance * Angle.cos(declination) * Angle.sin(rightAscension),
         distance * Angle.sin(declination))
    }

    private static func angularSeparation(
        _ rightAscension1: Double, _ declination1: Double,
        _ rightAscension2: Double, _ declination2: Double
    ) -> Double {
        Angle.acos(
            Angle.sin(declination1) * Angle.sin(declination2)
            + Angle.cos(declination1) * Angle.cos(declination2)
              * Angle.cos(rightAscension1 - rightAscension2))
    }

    /// Fraction of the covered disc that the covering disc hides, for two
    /// circles whose centres are `separation` apart.
    ///
    /// This is the area of the circular lens divided by the area of the covered
    /// disc, and it is emphatically not the magnitude. Magnitude counts
    /// diameter, this counts area, and confusing them overstates how dark the
    /// sky gets by a wide margin at every partial phase. Two equal discs half
    /// overlapping give magnitude 0.5 and obscuration 0.391.
    ///
    /// Left internal rather than private so that the proof driver can put the
    /// area formula against its analytic value without going through an
    /// ephemeris.
    static func overlapFraction(
        separation d: Double,
        covered r1: Double,
        coverer r2: Double
    ) -> Double {
        guard r1 > 0 else { return 0 }
        if d >= r1 + r2 { return 0 }
        if d <= r2 - r1 { return 1 }
        if d <= r1 - r2 { return (r2 * r2) / (r1 * r1) }

        // Working in degrees throughout is safe: the expression is homogeneous
        // in the three lengths, so the unit cancels.
        let c1 = min(1, max(-1, (d * d + r1 * r1 - r2 * r2) / (2 * d * r1)))
        let c2 = min(1, max(-1, (d * d + r2 * r2 - r1 * r1) / (2 * d * r2)))
        let lens = r1 * r1 * Foundation.acos(c1)
            + r2 * r2 * Foundation.acos(c2)
            - 0.5 * max(0, (-d + r1 + r2) * (d + r1 - r2) * (d - r1 + r2) * (d + r1 + r2))
                .squareRoot()
        return lens / (Double.pi * r1 * r1)
    }

    // MARK: Numerics

    /// Golden section search for the minimum of a unimodal function.
    ///
    /// Forty iterations take a twelve minute bracket down below a millisecond,
    /// which is far finer than the ephemeris behind it deserves, and costs
    /// forty evaluations.
    private static func minimise(_ a0: Double, _ b0: Double, _ f: (Double) -> Double) -> Double {
        let ratio = (5.0.squareRoot() - 1.0) / 2.0
        var a = a0
        var b = b0
        var c = b - ratio * (b - a)
        var d = a + ratio * (b - a)
        var fc = f(c)
        var fd = f(d)
        for _ in 0..<40 {
            if fc < fd {
                b = d
                d = c
                fd = fc
                c = b - ratio * (b - a)
                fc = f(c)
            } else {
                a = c
                c = d
                fc = fd
                d = a + ratio * (b - a)
                fd = f(d)
            }
        }
        return (a + b) / 2
    }

    /// Bisection for the root of a function known to change sign on the bracket.
    private static func root(_ a0: Double, _ b0: Double, _ f: (Double) -> Double) -> Double {
        var a = a0
        var b = b0
        var fa = f(a)
        for _ in 0..<60 {
            if b - a < 1e-9 { break }
            let mid = (a + b) / 2
            let fm = f(mid)
            if fm == 0 { return mid }
            if (fa < 0) == (fm < 0) { a = mid; fa = fm } else { b = mid }
        }
        return (a + b) / 2
    }

    /// The last instant before the peak at which `f` was not yet positive, and
    /// the first after it at which it is not positive again. Nil when the
    /// searched range never contained one, which means the phase was already
    /// under way at the edge of it.
    private static func crossing(
        before peak: Int,
        lowerBound: Int,
        first: Double,
        values: [Double],
        step: Double = solarStepDays,
        f: (Double) -> Double
    ) -> JulianDay? {
        var i = peak
        while i > lowerBound {
            if values[i - 1] <= 0 && values[i] > 0 {
                return JulianDay(root(first + Double(i - 1) * step, first + Double(i) * step, f))
            }
            i -= 1
        }
        return nil
    }

    private static func crossing(
        after peak: Int,
        upperBound: Int,
        first: Double,
        values: [Double],
        step: Double = solarStepDays,
        f: (Double) -> Double
    ) -> JulianDay? {
        var i = peak
        while i < upperBound {
            if values[i] > 0 && values[i + 1] <= 0 {
                return JulianDay(root(first + Double(i) * step, first + Double(i + 1) * step, f))
            }
            i += 1
        }
        return nil
    }
}
