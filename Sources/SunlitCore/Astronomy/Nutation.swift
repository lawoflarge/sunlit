import Foundation

/// Nutation and the obliquity of the ecliptic.
///
/// The Earth's axis wobbles with a period of about 18.6 years, driven mostly by
/// the regression of the lunar nodes. The effect is small, under 20 arcseconds,
/// but it is larger than the accuracy this core claims, so it cannot be skipped.
public enum Nutation {

    /// The result of one nutation evaluation. All values in degrees.
    public struct Result: Sendable {
        /// Nutation in longitude, usually written delta psi.
        public let inLongitude: Double
        /// Nutation in obliquity, usually written delta epsilon.
        public let inObliquity: Double
        /// Mean obliquity of the ecliptic, epsilon zero.
        public let meanObliquity: Double
        /// True obliquity, epsilon, which is the mean plus the nutation.
        public let trueObliquity: Double
    }

    /// The five fundamental arguments, in degrees, at a Julian ephemeris
    /// century. NREL appendix A.4.3, expressions 3.4.1 through 3.4.5.
    public static func fundamentalArguments(julianEphemerisCentury jce: Double) -> [Double] {
        let t = jce
        let t2 = t * t
        let t3 = t2 * t
        return [
            // Mean elongation of the moon from the sun.
            297.85036 + 445267.111480 * t - 0.0019142 * t2 + t3 / 189474.0,
            // Mean anomaly of the sun.
            357.52772 + 35999.050340 * t - 0.0001603 * t2 - t3 / 300000.0,
            // Mean anomaly of the moon.
            134.96298 + 477198.867398 * t + 0.0086972 * t2 + t3 / 56250.0,
            // Moon's argument of latitude.
            93.27191 + 483202.017538 * t - 0.0036825 * t2 + t3 / 327270.0,
            // Longitude of the ascending node of the moon's mean orbit.
            125.04452 - 1934.136261 * t + 0.0020708 * t2 + t3 / 450000.0,
        ]
    }

    /// Evaluates nutation and obliquity for a Julian ephemeris day.
    public static func evaluate(julianEphemerisDay jde: JulianDay) -> Result {
        let jce = jde.julianCentury
        let jme = jde.julianMillennium
        let x = fundamentalArguments(julianEphemerisCentury: jce)

        var sumPsi = 0.0
        var sumEpsilon = 0.0
        for i in 0..<SPATables.nutationArguments.count {
            let y = SPATables.nutationArguments[i]
            var argument = 0.0
            for j in 0..<5 {
                argument += x[j] * Double(y[j])
            }
            let pe = SPATables.nutationCoefficients[i]
            sumPsi += (pe[0] + pe[1] * jce) * Angle.sin(argument)
            sumEpsilon += (pe[2] + pe[3] * jce) * Angle.cos(argument)
        }

        // The published coefficients are in units of 0.0001 arcseconds, so the
        // divisor is 36000000 to reach degrees: 10000 to undo the scaling and
        // 3600 to convert arcseconds.
        let deltaPsi = sumPsi / 36000000.0
        let deltaEpsilon = sumEpsilon / 36000000.0

        // Mean obliquity, NREL expression 3.5.1, a tenth-order polynomial in
        // U = JME / 10. It is written in arcseconds.
        let u = jme / 10.0
        var e0 = 84381.448
        e0 += u * (-4680.93
            + u * (-1.55
            + u * (1999.25
            + u * (-51.38
            + u * (-249.67
            + u * (-39.05
            + u * (7.12
            + u * (27.87
            + u * (5.79
            + u * 2.45)))))))))
        let meanObliquity = e0 / 3600.0
        let trueObliquity = meanObliquity + deltaEpsilon

        return Result(
            inLongitude: deltaPsi,
            inObliquity: deltaEpsilon,
            meanObliquity: meanObliquity,
            trueObliquity: trueObliquity)
    }
}
