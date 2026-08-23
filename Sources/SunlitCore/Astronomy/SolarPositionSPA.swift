import Foundation

/// The NREL Solar Position Algorithm.
///
/// Reda and Andreas, *Solar Position Algorithm for Solar Radiation
/// Applications*, NREL/TP-560-34302. Accurate to 0.0003 degrees for the years
/// -2000 to 6000, which is a hundred times better than the app needs and is why
/// the accuracy claim on the store listing is safe to make.
///
/// The structure follows the report section by section so that anyone checking
/// a number against the paper can find the corresponding line here.
public enum SolarPositionSPA {

    /// Everything the algorithm produces for one instant at one place.
    ///
    /// The intermediate values are kept rather than discarded because the
    /// report publishes them for its worked example, which makes them the only
    /// way to locate a transcription error in a coefficient table: if the final
    /// azimuth is wrong, the first intermediate value that disagrees says which
    /// table to look in.
    public struct Result: Sendable {
        public let julianDay: Double
        public let julianEphemerisDay: Double
        /// Earth heliocentric longitude, degrees.
        public let heliocentricLongitude: Double
        /// Earth heliocentric latitude, degrees.
        public let heliocentricLatitude: Double
        /// Earth radius vector, astronomical units.
        public let radiusVector: Double
        /// Geocentric longitude of the sun, degrees.
        public let geocentricLongitude: Double
        /// Geocentric latitude of the sun, degrees.
        public let geocentricLatitude: Double
        public let nutationInLongitude: Double
        public let nutationInObliquity: Double
        public let trueObliquity: Double
        public let aberrationCorrection: Double
        /// Apparent longitude of the sun, degrees.
        public let apparentLongitude: Double
        /// Apparent sidereal time at Greenwich, degrees.
        public let apparentSiderealTime: Double
        public let geocentricRightAscension: Double
        public let geocentricDeclination: Double
        /// Observer local hour angle, degrees.
        public let hourAngle: Double
        public let topocentricRightAscension: Double
        public let topocentricDeclination: Double
        public let topocentricHourAngle: Double
        /// Topocentric elevation before refraction, degrees.
        public let elevationWithoutRefraction: Double
        public let refractionCorrection: Double
        /// Topocentric elevation after refraction, degrees. This is what the
        /// interface calls altitude.
        public let elevation: Double
        /// Topocentric zenith angle, degrees.
        public let zenith: Double
        /// Azimuth measured from north, increasing toward east. This is the
        /// navigator's azimuth and what a compass reads.
        public let azimuth: Double
        /// Azimuth measured from south, increasing toward west. The report
        /// calls this the astronomers' azimuth and publishes it for its
        /// worked example.
        public let azimuthFromSouth: Double
        /// The sun's equatorial horizontal parallax, degrees.
        public let equatorialHorizontalParallax: Double

        public var horizontal: Coordinates.Horizontal {
            Coordinates.Horizontal(azimuth: azimuth, altitude: elevation)
        }

        public var equatorial: Coordinates.Equatorial {
            Coordinates.Equatorial(
                rightAscension: topocentricRightAscension,
                declination: topocentricDeclination,
                distance: radiusVector)
        }
    }

    /// Atmospheric conditions at the observer. Defaults are the standard
    /// atmosphere the report itself uses.
    public struct Atmosphere: Sendable {
        public let pressureMillibars: Double
        public let temperatureCelsius: Double

        public init(pressureMillibars: Double = 1010, temperatureCelsius: Double = 10) {
            self.pressureMillibars = pressureMillibars
            self.temperatureCelsius = temperatureCelsius
        }

        /// Derives a plausible pressure from an elevation, for the common case
        /// where the caller knows where the observer is but not what the
        /// barometer says.
        public static func standard(atElevation metres: Double) -> Atmosphere {
            Atmosphere(pressureMillibars: Refraction.pressure(atElevation: metres))
        }
    }

    /// Evaluates the sun's position.
    ///
    /// - Parameters:
    ///   - julianDay: the instant, in Universal Time.
    ///   - place: the observer.
    ///   - deltaT: TT minus UT1 in seconds. Pass nil to have it estimated.
    ///   - atmosphere: pressure and temperature, which affect refraction only.
    public static func evaluate(
        julianDay jd: JulianDay,
        place: Coordinates.Geographic,
        deltaT: Double? = nil,
        atmosphere: Atmosphere? = nil
    ) -> Result {
        let dt = deltaT ?? DeltaT.seconds(julianDay: jd)
        let jde = jd.adding(seconds: dt)
        let jme = jde.julianMillennium

        // 3.2 Earth heliocentric longitude, latitude and radius vector.
        // The published terms are scaled by 1e8 and produce radians.
        let l = Angle.normalized(Angle.degrees(summation(SPATables.l, jme) / 1e8))
        let b = Angle.degrees(summation(SPATables.b, jme) / 1e8)
        let r = summation(SPATables.r, jme) / 1e8

        // 3.3 Geocentric longitude and latitude: the sun seen from the Earth is
        // the Earth seen from the sun, turned around.
        let theta = Angle.normalized(l + 180.0)
        let beta = -b

        // 3.4 and 3.5 Nutation and obliquity.
        let nutation = Nutation.evaluate(julianEphemerisDay: jde)

        // 3.6 Aberration. Light takes about 8.3 minutes to arrive, during which
        // the Earth has moved, so the sun appears slightly behind where it is.
        let deltaTau = -20.4898 / (3600.0 * r)

        // 3.7 Apparent sun longitude.
        let lambda = theta + nutation.inLongitude + deltaTau

        // 3.8 Apparent sidereal time at Greenwich.
        let nu = Coordinates.apparentSiderealTime(
            julianDay: jd,
            nutationInLongitude: nutation.inLongitude,
            trueObliquity: nutation.trueObliquity)

        // 3.9 and 3.10 Geocentric right ascension and declination.
        let epsilon = nutation.trueObliquity
        let alpha = Angle.normalized(Angle.atan2(
            Angle.sin(lambda) * Angle.cos(epsilon) - Angle.tan(beta) * Angle.sin(epsilon),
            Angle.cos(lambda)))
        let delta = Angle.asin(
            Angle.sin(beta) * Angle.cos(epsilon)
            + Angle.cos(beta) * Angle.sin(epsilon) * Angle.sin(lambda))

        // 3.11 Observer local hour angle. Longitude is positive east here.
        let h = Angle.normalized(nu + place.longitude - alpha)

        // 3.12 Topocentric position. The observer is on the surface, not at the
        // centre, and for the sun that shifts the apparent position by about
        // nine arcseconds. Small, but the claimed accuracy is smaller.
        let xi = 8.794 / (3600.0 * r)
        let phi = place.latitude
        let u = Foundation.atan(0.99664719 * Angle.tan(phi))
        let x = Foundation.cos(u) + place.elevation / 6378140.0 * Angle.cos(phi)
        let y = 0.99664719 * Foundation.sin(u) + place.elevation / 6378140.0 * Angle.sin(phi)

        let deltaAlpha = Angle.atan2(
            -x * Angle.sin(xi) * Angle.sin(h),
            Angle.cos(delta) - x * Angle.sin(xi) * Angle.cos(h))
        let alphaPrime = alpha + deltaAlpha
        let deltaPrime = Angle.atan2(
            (Angle.sin(delta) - y * Angle.sin(xi)) * Angle.cos(deltaAlpha),
            Angle.cos(delta) - x * Angle.sin(xi) * Angle.cos(h))
        let hPrime = h - deltaAlpha

        // 3.14 Topocentric elevation, before and after refraction.
        let e0 = Angle.asin(
            Angle.sin(phi) * Angle.sin(deltaPrime)
            + Angle.cos(phi) * Angle.cos(deltaPrime) * Angle.cos(hPrime))
        let air = atmosphere ?? Atmosphere.standard(atElevation: place.elevation)
        let deltaE = Refraction.apparentFromTrue(
            trueAltitude: e0,
            pressure: air.pressureMillibars,
            temperature: air.temperatureCelsius)
        let e = e0 + deltaE

        // 3.15 Azimuth. The report gives the astronomers' convention first,
        // measured from south toward west, then adds 180 for the navigators'
        // convention, measured from north toward east.
        let gamma = Angle.normalized(Angle.atan2(
            Angle.sin(hPrime),
            Angle.cos(hPrime) * Angle.sin(phi) - Angle.tan(deltaPrime) * Angle.cos(phi)))
        let phiAzimuth = Angle.normalized(gamma + 180.0)

        return Result(
            julianDay: jd.value,
            julianEphemerisDay: jde.value,
            heliocentricLongitude: l,
            heliocentricLatitude: b,
            radiusVector: r,
            geocentricLongitude: theta,
            geocentricLatitude: beta,
            nutationInLongitude: nutation.inLongitude,
            nutationInObliquity: nutation.inObliquity,
            trueObliquity: nutation.trueObliquity,
            aberrationCorrection: deltaTau,
            apparentLongitude: lambda,
            apparentSiderealTime: nu,
            geocentricRightAscension: alpha,
            geocentricDeclination: delta,
            hourAngle: h,
            topocentricRightAscension: alphaPrime,
            topocentricDeclination: deltaPrime,
            topocentricHourAngle: hPrime,
            elevationWithoutRefraction: e0,
            refractionCorrection: deltaE,
            elevation: e,
            zenith: 90.0 - e,
            azimuth: phiAzimuth,
            azimuthFromSouth: gamma,
            equatorialHorizontalParallax: xi)
    }

    /// Evaluates the summation of a set of periodic term groups.
    ///
    /// Each group is a polynomial coefficient in the Julian millennium: group
    /// zero is the constant term, group one multiplies jme, group two jme
    /// squared, and so on. Within a group each term contributes
    /// `a * cos(b + c * jme)`.
    private static func summation(
        _ groups: [[(a: Double, b: Double, c: Double)]],
        _ jme: Double
    ) -> Double {
        var total = 0.0
        var power = 1.0
        for group in groups {
            var sum = 0.0
            for term in group {
                sum += term.a * Foundation.cos(term.b + term.c * jme)
            }
            total += sum * power
            power *= jme
        }
        return total
    }

    /// The angle of incidence on a tilted surface, in degrees. The report
    /// publishes this for its worked example, so it is implemented to make the
    /// example fully reproducible, and it is genuinely useful for the solar
    /// panel audience.
    ///
    /// - Parameters:
    ///   - zenith: topocentric zenith angle in degrees.
    ///   - azimuthFromSouth: the astronomers' azimuth in degrees.
    ///   - slope: surface tilt from horizontal in degrees.
    ///   - surfaceAzimuthRotation: surface azimuth measured from south,
    ///     positive toward west, in degrees.
    public static func incidenceAngle(
        zenith: Double,
        azimuthFromSouth: Double,
        slope: Double,
        surfaceAzimuthRotation: Double
    ) -> Double {
        Angle.acos(
            Angle.cos(zenith) * Angle.cos(slope)
            + Angle.sin(slope) * Angle.sin(zenith)
              * Angle.cos(azimuthFromSouth - surfaceAzimuthRotation))
    }
}
