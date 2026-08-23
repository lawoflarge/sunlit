import Foundation

/// Everything true at one instant at one place.
///
/// The app reads this and never calls the astronomy modules directly. That is
/// not tidiness: the time scrubber recomputes on every frame, and having one
/// entry point is what makes it possible to see, in one file, exactly how much
/// work a frame costs.
public struct SkyMoment: Sendable {

    public let instant: JulianDay
    public let place: Place

    // MARK: Sun

    public let sun: Coordinates.Horizontal
    public let sunEquatorial: Coordinates.Equatorial
    /// The earth to sun distance in astronomical units, at this instant.
    public let earthSunDistanceAU: Double
    /// Apparent sidereal time at Greenwich, kept because the moon's topocentric
    /// correction needs it and recomputing it would double the cost.
    public let apparentSiderealTime: Double

    // MARK: Moon

    public let moon: Coordinates.Horizontal
    public let moonPhase: MoonPosition.Phase
    /// Topocentric distance in kilometres.
    public let moonDistance: Double
    /// Apparent angular radius of the moon's disc in degrees.
    public let moonSemidiameter: Double

    // MARK: Milky Way

    public let galacticCentre: Coordinates.Horizontal

    // MARK: Derived

    public let period: Twilight.Period
    public let isGoldenHour: Bool
    public let isBlueHour: Bool
    public let uv: UVIndex.Estimate
    public let irradiance: Irradiance.Estimate
    /// The shadow a one metre object casts here and now, or nil when the sun is
    /// below the horizon and there is no finite shadow.
    public let unitShadow: Shadow.Cast?

    /// True when the sun is above the astronomical horizon.
    public var sunIsUp: Bool { sun.altitude > Refraction.sunriseAltitude }

    /// True when the sun clears the measured skyline, which is a different and
    /// stricter question than clearing a flat horizon. Equal to `sunIsUp` when
    /// the place has no measured profile.
    public let sunIsAboveTerrain: Bool

    /// Evaluates one instant.
    public static func at(_ instant: JulianDay, place: Place) -> SkyMoment {
        let geographic = place.geographic
        let solar = SolarPositionSPA.evaluate(julianDay: instant, place: geographic)

        let deltaT = DeltaT.seconds(julianDay: instant)
        let jde = instant.adding(seconds: deltaT)
        let lunar = MoonPosition.evaluate(julianEphemerisDay: jde)
        let topocentric = MoonPosition.topocentric(
            lunar, place: geographic, apparentSiderealTime: solar.apparentSiderealTime)
        let moonHourAngle = Coordinates.hourAngle(
            apparentSiderealTime: solar.apparentSiderealTime,
            longitude: geographic.longitude,
            rightAscension: topocentric.rightAscension)
        let moonHorizontal = Coordinates.horizontal(
            equatorial: Coordinates.Equatorial(
                rightAscension: topocentric.rightAscension,
                declination: topocentric.declination),
            hourAngle: moonHourAngle,
            latitude: geographic.latitude)

        let phase = MoonPosition.phase(
            moon: lunar,
            sunRightAscension: solar.geocentricRightAscension,
            sunDeclination: solar.geocentricDeclination,
            sunDistanceAU: solar.radiusVector,
            sunApparentLongitude: solar.apparentLongitude)

        let dayOfYear = Self.dayOfYear(of: instant)
        let uv = UVIndex.estimate(
            solarAltitude: solar.elevation,
            elevationMetres: geographic.elevation,
            earthSunDistanceAU: solar.radiusVector,
            latitude: geographic.latitude,
            dayOfYear: dayOfYear)
        let irradiance = Irradiance.clearSky(
            solarAltitude: solar.elevation,
            elevationMetres: geographic.elevation,
            earthSunDistanceAU: solar.radiusVector)

        let aboveTerrain: Bool
        if let profile = place.horizonProfile, profile.isMeasured {
            aboveTerrain = solar.elevation > profile.altitude(atAzimuth: solar.azimuth)
        } else {
            aboveTerrain = solar.elevation > Refraction.sunriseAltitude
        }

        return SkyMoment(
            instant: instant,
            place: place,
            sun: solar.horizontal,
            sunEquatorial: solar.equatorial,
            earthSunDistanceAU: solar.radiusVector,
            apparentSiderealTime: solar.apparentSiderealTime,
            moon: moonHorizontal,
            moonPhase: phase,
            moonDistance: topocentric.distance,
            moonSemidiameter: topocentric.semidiameter,
            galacticCentre: MilkyWay.position(at: instant, place: geographic),
            period: Twilight.period(solarAltitude: solar.elevation),
            isGoldenHour: GoldenHour.isWithinGolden(solarAltitude: solar.elevation),
            isBlueHour: GoldenHour.isWithinBlue(solarAltitude: solar.elevation),
            uv: uv,
            irradiance: irradiance,
            unitShadow: Shadow.cast(
                objectHeight: 1.0,
                solarAltitude: solar.elevation,
                solarAzimuth: solar.azimuth),
            sunIsAboveTerrain: aboveTerrain)
    }

    /// Day of the year, needed by the ozone climatology.
    static func dayOfYear(of julianDay: JulianDay) -> Int {
        let date = julianDay.calendarDate
        let startOfYear = JulianDay.from(year: date.year, month: 1, day: 1.0)
        return Int((julianDay.value - startOfYear.value).rounded(.down)) + 1
    }
}
