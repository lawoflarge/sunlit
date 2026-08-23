import Foundation

/// The Moon's position, after Meeus, *Astronomical Algorithms*, chapter 47.
///
/// This is the ELP-2000/82 theory truncated to the sixty largest terms in
/// longitude and distance and the sixty largest in latitude. Meeus gives the
/// accuracy as about 10 arcseconds in longitude and 4 in latitude, which is
/// roughly a thirtieth of the Moon's apparent diameter. That is far better than
/// anyone can point a phone, and it is good enough that eclipse contact times
/// land inside a minute.
public enum MoonPosition {

    public struct Result: Sendable {
        /// Apparent geocentric ecliptic longitude, degrees.
        public let longitude: Double
        /// Geocentric ecliptic latitude, degrees.
        public let latitude: Double
        /// Distance between the centres of the Earth and the Moon, kilometres.
        public let distance: Double
        /// Equatorial horizontal parallax, degrees.
        public let parallax: Double
        /// Geocentric right ascension, degrees.
        public let rightAscension: Double
        /// Geocentric declination, degrees.
        public let declination: Double
        /// Apparent angular radius of the disc as seen from the Earth's centre,
        /// degrees.
        public let semidiameter: Double
        /// The nutation and obliquity this evaluation already had to compute,
        /// kept rather than thrown away. A caller that needs apparent sidereal
        /// time for the same instant, which is every caller that wants the Moon
        /// in the sky rather than on the ecliptic, would otherwise evaluate the
        /// sixty three term nutation series a second time for the same answer.
        public let nutation: Nutation.Result

        public var equatorial: Coordinates.Equatorial {
            Coordinates.Equatorial(
                rightAscension: rightAscension,
                declination: declination,
                distance: distance)
        }
    }

    /// The Moon's mean radius in kilometres, the IAU value.
    public static let radiusKilometres = 1737.4

    /// Evaluates the Moon's geocentric position.
    ///
    /// - Parameter jde: the instant in Terrestrial Time, which is to say
    ///   Julian day plus delta T. Passing UT here shifts the Moon by about
    ///   half an arcsecond per second of delta T, so the distinction matters.
    public static func evaluate(julianEphemerisDay jde: JulianDay) -> Result {
        let t = jde.julianCentury
        let t2 = t * t
        let t3 = t2 * t
        let t4 = t3 * t

        // Mean longitude, referred to the mean equinox of date, including the
        // constant term of light-time.
        let lPrime = Angle.normalized(218.3164477 + 481267.88123421 * t
            - 0.0015786 * t2 + t3 / 538841.0 - t4 / 65194000.0)
        // Mean elongation of the Moon from the Sun.
        let d = Angle.normalized(297.8501921 + 445267.1114034 * t
            - 0.0018819 * t2 + t3 / 545868.0 - t4 / 113065000.0)
        // Sun's mean anomaly.
        let m = Angle.normalized(357.5291092 + 35999.0502909 * t
            - 0.0001536 * t2 + t3 / 24490000.0)
        // Moon's mean anomaly.
        let mPrime = Angle.normalized(134.9633964 + 477198.8675055 * t
            + 0.0087414 * t2 + t3 / 69699.0 - t4 / 14712000.0)
        // Moon's argument of latitude, its mean distance from the ascending
        // node.
        let f = Angle.normalized(93.2720950 + 483202.0175233 * t
            - 0.0036539 * t2 - t3 / 3526000.0 + t4 / 863310000.0)

        // Three further arguments, standing in for the perturbing action of
        // Venus, of Jupiter, and of the flattening of the Earth.
        let a1 = Angle.normalized(119.75 + 131.849 * t)
        let a2 = Angle.normalized(53.09 + 479264.290 * t)
        let a3 = Angle.normalized(313.45 + 481266.484 * t)

        // The eccentricity of the Earth's orbit around the Sun changes slowly,
        // and terms that depend on the Sun's anomaly have to be scaled by it.
        // Forgetting this is a common error worth about 20 arcseconds.
        let e = 1.0 - 0.002516 * t - 0.0000074 * t2
        let e2 = e * e

        var sumL = 0.0
        var sumR = 0.0
        for term in MoonTables.longitudeAndDistance {
            let argument = Double(term.d) * d + Double(term.m) * m
                + Double(term.mPrime) * mPrime + Double(term.f) * f
            let scale: Double
            switch abs(term.m) {
            case 1: scale = e
            case 2: scale = e2
            default: scale = 1.0
            }
            sumL += term.l * scale * Angle.sin(argument)
            sumR += term.r * scale * Angle.cos(argument)
        }

        var sumB = 0.0
        for term in MoonTables.latitude {
            let argument = Double(term.d) * d + Double(term.m) * m
                + Double(term.mPrime) * mPrime + Double(term.f) * f
            let scale: Double
            switch abs(term.m) {
            case 1: scale = e
            case 2: scale = e2
            default: scale = 1.0
            }
            sumB += term.b * scale * Angle.sin(argument)
        }

        // The additive terms Meeus gives after each table.
        sumL += 3958.0 * Angle.sin(a1)
            + 1962.0 * Angle.sin(lPrime - f)
            + 318.0 * Angle.sin(a2)
        sumB += -2235.0 * Angle.sin(lPrime)
            + 382.0 * Angle.sin(a3)
            + 175.0 * Angle.sin(a1 - f)
            + 175.0 * Angle.sin(a1 + f)
            + 127.0 * Angle.sin(lPrime - mPrime)
            - 115.0 * Angle.sin(lPrime + mPrime)

        // Sigma l and Sigma b are in units of 1e-6 degrees, Sigma r in 1e-3 km.
        let lambdaMean = Angle.normalized(lPrime + sumL / 1000000.0)
        let beta = sumB / 1000000.0
        let distance = 385000.56 + sumR / 1000.0
        let parallax = Angle.asin(6378.14 / distance)

        // Apparent longitude needs the nutation in longitude. The obliquity for
        // the equatorial conversion needs the true obliquity, so both come from
        // the same evaluation.
        let nutation = Nutation.evaluate(julianEphemerisDay: jde)
        let lambda = Angle.normalized(lambdaMean + nutation.inLongitude)

        let equatorial = Coordinates.equatorial(
            ecliptic: Coordinates.Ecliptic(longitude: lambda, latitude: beta, distance: distance),
            obliquity: nutation.trueObliquity)

        return Result(
            longitude: lambda,
            latitude: beta,
            distance: distance,
            parallax: parallax,
            rightAscension: equatorial.rightAscension,
            declination: equatorial.declination,
            semidiameter: Angle.asin(radiusKilometres / distance),
            nutation: nutation)
    }

    /// The illuminated fraction of the disc and the phase, Meeus chapter 48.
    public struct Phase: Sendable {
        /// Phase angle: the Sun-Moon-Earth angle, degrees. Zero at full moon,
        /// 180 at new moon.
        public let phaseAngle: Double
        /// Fraction of the disc that is lit, 0 to 1.
        public let illuminatedFraction: Double
        /// Position angle of the bright limb's midpoint, measured eastward from
        /// the north point of the disc, degrees.
        public let brightLimbAngle: Double
        /// Elongation from the Sun, degrees. Grows from 0 at new moon through
        /// 180 at full moon and back.
        public let elongation: Double
        /// Age of the moon in the synodic cycle, 0 to 1, where 0 and 1 are new
        /// moon and 0.5 is full moon. This is what the interface calls phase
        /// and what decides which crescent to draw.
        public let cycleFraction: Double

        /// The named phase, for labelling.
        public var name: Name {
            switch cycleFraction {
            case ..<0.0335: return .newMoon
            case ..<0.2165: return .waxingCrescent
            case ..<0.2835: return .firstQuarter
            case ..<0.4665: return .waxingGibbous
            case ..<0.5335: return .fullMoon
            case ..<0.7165: return .waningGibbous
            case ..<0.7835: return .lastQuarter
            case ..<0.9665: return .waningCrescent
            default: return .newMoon
            }
        }

        public enum Name: String, Sendable, CaseIterable {
            case newMoon, waxingCrescent, firstQuarter, waxingGibbous
            case fullMoon, waningGibbous, lastQuarter, waningCrescent
        }
    }

    /// Computes the phase from the geocentric positions of both bodies.
    ///
    /// - Parameters:
    ///   - moon: the Moon's geocentric position.
    ///   - sunRightAscension: the Sun's apparent right ascension, degrees.
    ///   - sunDeclination: the Sun's apparent declination, degrees.
    ///   - sunDistanceAU: the Earth to Sun distance in astronomical units.
    ///   - sunApparentLongitude: the Sun's apparent ecliptic longitude,
    ///     degrees. This is what decides waxing from waning, and nothing else
    ///     can: the illuminated fraction is symmetric about full moon, and the
    ///     elongation is an unsigned separation. The phase of the moon is by
    ///     definition the difference of the two ecliptic longitudes, so that is
    ///     what is used.
    public static func phase(
        moon: Result,
        sunRightAscension: Double,
        sunDeclination: Double,
        sunDistanceAU: Double,
        sunApparentLongitude: Double
    ) -> Phase {
        let astronomicalUnitKm = 149597870.7
        let sunDistance = sunDistanceAU * astronomicalUnitKm

        // Geocentric elongation of the Moon from the Sun.
        let psi = Angle.acos(
            Angle.sin(sunDeclination) * Angle.sin(moon.declination)
            + Angle.cos(sunDeclination) * Angle.cos(moon.declination)
              * Angle.cos(sunRightAscension - moon.rightAscension))

        // Phase angle, Meeus 48.3. Written with atan2 rather than atan so the
        // quadrant survives.
        let i = Angle.atan2(
            sunDistance * Angle.sin(psi),
            moon.distance - sunDistance * Angle.cos(psi))
        let phaseAngle = Angle.normalized(i)

        let illuminated = (1.0 + Angle.cos(phaseAngle)) / 2.0

        // Position angle of the bright limb, Meeus 48.5.
        let y = Angle.cos(sunDeclination) * Angle.sin(sunRightAscension - moon.rightAscension)
        let x = Angle.sin(sunDeclination) * Angle.cos(moon.declination)
            - Angle.cos(sunDeclination) * Angle.sin(moon.declination)
              * Angle.cos(sunRightAscension - moon.rightAscension)
        let chi = Angle.normalized(Angle.atan2(y, x))

        // The position in the synodic cycle, straight from the definition: the
        // difference in ecliptic longitude between the moon and the sun, as a
        // fraction of a full turn. Zero is new moon, a quarter is first
        // quarter, a half is full moon.
        //
        // An earlier draft derived this from the position angle of the bright
        // limb instead and had waxing and waning exactly backwards. The limb
        // angle does carry the information, but reading it correctly depends on
        // a convention that is easy to invert, whereas the longitude difference
        // is the definition and cannot be.
        let cycleFraction = Angle.normalized(moon.longitude - sunApparentLongitude) / 360.0

        return Phase(
            phaseAngle: phaseAngle,
            illuminatedFraction: illuminated,
            brightLimbAngle: chi,
            elongation: psi,
            cycleFraction: cycleFraction)
    }

    /// Topocentric position: what the observer on the surface sees, rather than
    /// what a hypothetical observer at the centre of the Earth would.
    ///
    /// For the Sun this correction is nine arcseconds and pedantic. For the
    /// Moon it reaches a full degree, which is twice the Moon's own diameter,
    /// so skipping it would put the Moon visibly in the wrong place and would
    /// make every eclipse prediction wrong.
    public static func topocentric(
        _ moon: Result,
        place: Coordinates.Geographic,
        apparentSiderealTime: Double
    ) -> (rightAscension: Double, declination: Double, distance: Double, semidiameter: Double) {
        let h = Angle.normalized(apparentSiderealTime + place.longitude - moon.rightAscension)
        let phi = place.latitude

        // The Earth is an ellipsoid, so the observer's distance from the centre
        // depends on latitude. Meeus chapter 11.
        let u = Foundation.atan(0.99664719 * Angle.tan(phi))
        let rhoSinPhi = 0.99664719 * Foundation.sin(u) + place.elevation / 6378140.0 * Angle.sin(phi)
        let rhoCosPhi = Foundation.cos(u) + place.elevation / 6378140.0 * Angle.cos(phi)

        let sinPi = Angle.sin(moon.parallax)
        let deltaAlpha = Angle.atan2(
            -rhoCosPhi * sinPi * Angle.sin(h),
            Angle.cos(moon.declination) - rhoCosPhi * sinPi * Angle.cos(h))
        let alphaPrime = Angle.normalized(moon.rightAscension + deltaAlpha)
        let deltaPrime = Angle.atan2(
            (Angle.sin(moon.declination) - rhoSinPhi * sinPi) * Angle.cos(deltaAlpha),
            Angle.cos(moon.declination) - rhoCosPhi * sinPi * Angle.cos(h))

        // Topocentric distance, from the triangle formed by the geocentre, the
        // observer and the Moon.
        let earthRadius = 6378.14
        let cosZ = Angle.sin(phi) * Angle.sin(moon.declination)
            + Angle.cos(phi) * Angle.cos(moon.declination) * Angle.cos(h)
        let observerOffset = earthRadius * sqrt(rhoSinPhi * rhoSinPhi + rhoCosPhi * rhoCosPhi)
        let topocentricDistance = sqrt(
            moon.distance * moon.distance
            + observerOffset * observerOffset
            - 2.0 * moon.distance * observerOffset * cosZ)

        return (alphaPrime, deltaPrime, topocentricDistance,
                Angle.asin(radiusKilometres / topocentricDistance))
    }
}
