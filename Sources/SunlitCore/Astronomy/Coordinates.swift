import Foundation

/// Coordinate systems and the transformations between them.
///
/// **Longitude is positive east throughout this module.** Meeus writes his
/// formulae with longitude positive *west*, so every expression transcribed
/// from the book has had its sign flipped here. That single convention is the
/// most common source of an app that is right in one hemisphere and mirrored in
/// the other, so it is stated once, loudly, and never varied.
///
/// **Azimuth is measured from north, increasing toward east.** That is what a
/// compass reads and what the interface shows. Meeus measures from south; the
/// NREL algorithm publishes both and calls the north-based one the navigator's
/// azimuth.
public enum Coordinates {

    // MARK: Geographic position

    /// A place on the Earth.
    public struct Geographic: Hashable, Sendable {
        /// Degrees, positive north.
        public let latitude: Double
        /// Degrees, positive east.
        public let longitude: Double
        /// Metres above mean sea level.
        public let elevation: Double

        public init(latitude: Double, longitude: Double, elevation: Double = 0) {
            self.latitude = latitude
            self.longitude = longitude
            self.elevation = elevation
        }
    }

    // MARK: Equatorial

    /// Right ascension and declination.
    public struct Equatorial: Hashable, Sendable {
        /// Degrees, 0 to 360. Not hours.
        public let rightAscension: Double
        /// Degrees, positive north.
        public let declination: Double
        /// Distance to the body. Kilometres for the moon, astronomical units
        /// for the sun. Zero means "not applicable", as for a fixed star.
        public let distance: Double

        public init(rightAscension: Double, declination: Double, distance: Double = 0) {
            self.rightAscension = rightAscension
            self.declination = declination
            self.distance = distance
        }
    }

    // MARK: Horizontal

    /// What an observer sees.
    public struct Horizontal: Hashable, Sendable {
        /// Degrees from north, increasing toward east, 0 to 360.
        public let azimuth: Double
        /// Degrees above the horizon. Negative below it.
        public let altitude: Double

        public init(azimuth: Double, altitude: Double) {
            self.azimuth = azimuth
            self.altitude = altitude
        }
    }

    // MARK: Ecliptic

    public struct Ecliptic: Hashable, Sendable {
        /// Degrees, 0 to 360.
        public let longitude: Double
        /// Degrees.
        public let latitude: Double
        public let distance: Double

        public init(longitude: Double, latitude: Double, distance: Double = 0) {
            self.longitude = longitude
            self.latitude = latitude
            self.distance = distance
        }
    }

    // MARK: Sidereal time

    /// Mean sidereal time at Greenwich, in degrees, for a Julian day expressed
    /// in Universal Time. Meeus formula 12.4.
    public static func meanSiderealTime(julianDay jd: JulianDay) -> Double {
        let t = jd.julianCentury
        let theta = 280.46061837
            + 360.98564736629 * (jd.value - 2451545.0)
            + 0.000387933 * t * t
            - t * t * t / 38710000.0
        return Angle.normalized(theta)
    }

    /// Apparent sidereal time at Greenwich, in degrees. The nutation in
    /// longitude and the true obliquity are what turn mean into apparent.
    public static func apparentSiderealTime(
        julianDay jd: JulianDay,
        nutationInLongitude deltaPsi: Double,
        trueObliquity epsilon: Double
    ) -> Double {
        Angle.normalized(meanSiderealTime(julianDay: jd) + deltaPsi * Angle.cos(epsilon))
    }

    /// The local hour angle of a body, in degrees.
    ///
    /// Positive west of the meridian, which is to say the body has already
    /// transited. Longitude is positive east, hence the plus sign.
    public static func hourAngle(
        apparentSiderealTime theta: Double,
        longitude: Double,
        rightAscension alpha: Double
    ) -> Double {
        Angle.normalized(theta + longitude - alpha)
    }

    // MARK: Equatorial to horizontal

    /// Converts equatorial coordinates to what the observer sees, before
    /// refraction.
    ///
    /// The azimuth is built with `atan2` on the two components rather than from
    /// a single arctangent, because the single-argument form loses the quadrant
    /// and puts the sun in the wrong half of the sky for half of every day.
    public static func horizontal(
        equatorial: Equatorial,
        hourAngle h: Double,
        latitude phi: Double
    ) -> Horizontal {
        let delta = equatorial.declination
        let sinAltitude = Angle.sin(phi) * Angle.sin(delta)
            + Angle.cos(phi) * Angle.cos(delta) * Angle.cos(h)
        let altitude = Angle.asin(sinAltitude)

        let y = -Angle.cos(delta) * Angle.sin(h)
        let x = Angle.sin(delta) * Angle.cos(phi) - Angle.cos(delta) * Angle.sin(phi) * Angle.cos(h)
        let azimuth = Angle.normalized(Angle.atan2(y, x))

        return Horizontal(azimuth: azimuth, altitude: altitude)
    }

    // MARK: Ecliptic to equatorial

    /// Meeus formulae 13.3 and 13.4.
    public static func equatorial(ecliptic: Ecliptic, obliquity epsilon: Double) -> Equatorial {
        let lambda = ecliptic.longitude
        let beta = ecliptic.latitude

        let y = Angle.sin(lambda) * Angle.cos(epsilon) - Angle.tan(beta) * Angle.sin(epsilon)
        let x = Angle.cos(lambda)
        let alpha = Angle.normalized(Angle.atan2(y, x))

        let sinDelta = Angle.sin(beta) * Angle.cos(epsilon)
            + Angle.cos(beta) * Angle.sin(epsilon) * Angle.sin(lambda)
        let delta = Angle.asin(sinDelta)

        return Equatorial(rightAscension: alpha, declination: delta, distance: ecliptic.distance)
    }

    // MARK: Precession

    /// Reduces J2000.0 equatorial coordinates to the mean equinox of date.
    /// Meeus chapter 21, rigorous method, formulae 21.2 and 21.4.
    ///
    /// Needed for anything catalogued at a fixed epoch, which in this app means
    /// the galactic centre and the galactic plane.
    public static func precessFromJ2000(_ position: Equatorial, to jd: JulianDay) -> Equatorial {
        let t = jd.julianCentury

        // Arcseconds, converted to degrees once at the end of each expression.
        let zeta = Angle.fromArcseconds(2306.2181 * t + 0.30188 * t * t + 0.017998 * t * t * t)
        let z = Angle.fromArcseconds(2306.2181 * t + 1.09468 * t * t + 0.018203 * t * t * t)
        let theta = Angle.fromArcseconds(2004.3109 * t - 0.42665 * t * t - 0.041833 * t * t * t)

        let alpha0 = position.rightAscension
        let delta0 = position.declination

        let a = Angle.cos(delta0) * Angle.sin(alpha0 + zeta)
        let b = Angle.cos(theta) * Angle.cos(delta0) * Angle.cos(alpha0 + zeta)
            - Angle.sin(theta) * Angle.sin(delta0)
        let c = Angle.sin(theta) * Angle.cos(delta0) * Angle.cos(alpha0 + zeta)
            + Angle.cos(theta) * Angle.sin(delta0)

        let alpha = Angle.normalized(Angle.atan2(a, b) + z)
        let delta = Angle.asin(c)

        return Equatorial(rightAscension: alpha, declination: delta, distance: position.distance)
    }

    // MARK: Galactic

    /// The J2000.0 equatorial coordinates of the north galactic pole, and the
    /// galactic longitude of the north celestial pole. These three numbers
    /// define the galactic coordinate system.
    public enum Galactic {
        public static let northPoleRightAscension = 192.85948
        public static let northPoleDeclination = 27.12825
        public static let northCelestialPoleLongitude = 122.93192
    }

    /// Galactic longitude and latitude, both in degrees, to J2000.0 equatorial.
    public static func equatorialFromGalactic(longitude l: Double, latitude b: Double) -> Equatorial {
        let alphaGP = Galactic.northPoleRightAscension
        let deltaGP = Galactic.northPoleDeclination
        let lNCP = Galactic.northCelestialPoleLongitude

        let sinDelta = Angle.sin(b) * Angle.sin(deltaGP)
            + Angle.cos(b) * Angle.cos(deltaGP) * Angle.cos(lNCP - l)
        let delta = Angle.asin(sinDelta)

        let y = Angle.cos(b) * Angle.sin(lNCP - l)
        let x = Angle.sin(b) * Angle.cos(deltaGP)
            - Angle.cos(b) * Angle.sin(deltaGP) * Angle.cos(lNCP - l)
        let alpha = Angle.normalized(alphaGP + Angle.atan2(y, x))

        return Equatorial(rightAscension: alpha, declination: delta)
    }

    /// J2000.0 equatorial to galactic longitude and latitude.
    public static func galacticFromEquatorial(_ position: Equatorial) -> (longitude: Double, latitude: Double) {
        let alphaGP = Galactic.northPoleRightAscension
        let deltaGP = Galactic.northPoleDeclination
        let lNCP = Galactic.northCelestialPoleLongitude

        let alpha = position.rightAscension
        let delta = position.declination

        let sinB = Angle.sin(delta) * Angle.sin(deltaGP)
            + Angle.cos(delta) * Angle.cos(deltaGP) * Angle.cos(alpha - alphaGP)
        let b = Angle.asin(sinB)

        let y = Angle.cos(delta) * Angle.sin(alpha - alphaGP)
        let x = Angle.sin(delta) * Angle.cos(deltaGP)
            - Angle.cos(delta) * Angle.sin(deltaGP) * Angle.cos(alpha - alphaGP)
        let l = Angle.normalized(lNCP - Angle.atan2(y, x))

        return (l, b)
    }
}
