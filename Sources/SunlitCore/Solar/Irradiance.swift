import Foundation

/// A clear-sky MODEL of broadband solar irradiance at the ground.
///
/// Nothing here is a measurement. The model sees no cloud, no aerosol loading,
/// no water vapour, and no snow. It answers what a cloudless sky of average
/// turbidity would deliver at this sun angle and this height, which is an upper
/// bound on almost every real sky. `Estimate.isClearSkyModel` and
/// `modelDisclosure` exist so that no view can present these numbers as
/// something the device measured.
///
/// The three published pieces:
///
/// - Relative optical air mass: Kasten, F. and Young, A. T. (1989), "Revised
///   optical air mass tables and approximation formula", Applied Optics 28(22),
///   4735-4738. `m = 1 / (sin(gamma) + 0.50572 * (gamma + 6.07995)^-1.6364)`
///   with `gamma` the apparent solar elevation in degrees.
/// - Global horizontal: Haurwitz, B. (1945), "Insolation in Relation to
///   Cloudiness and Cloud Density", Journal of Meteorology 2, 154-166, in the
///   form given by Reno, Hansen and Stein (2012), "Global Horizontal Irradiance
///   Clear Sky Models: Implementation and Analysis", Sandia SAND2012-2389:
///   `GHI = 1098 * cos(z) * exp(-0.059 / cos(z))`.
/// - Direct and diffuse split: Erbs, D. G., Klein, S. A. and Duffie, J. A.
///   (1982), "Estimation of the diffuse radiation fraction for hourly, daily and
///   monthly-average global radiation", Solar Energy 28(4), 293-302.
public enum Irradiance {

    /// The caption an interface must show wherever it shows these numbers.
    ///
    /// It is the only string this type publishes, deliberately. Source-language
    /// English; the app layer localises it.
    public static let modelDisclosure = "Clear sky model, not a measurement"

    /// Total solar irradiance at one astronomical unit, in W/m2.
    ///
    /// 1361 is the value adopted after the ACRIM and TIM radiometry was
    /// reconciled (Kopp and Lean 2011), and it is the figure the IAU 2015
    /// nominal solar constant `S_nominal = 1361 W/m2` records. The older 1367
    /// still appears in engineering tables and is about 0.4 percent high.
    public static let solarConstant = 1361.0

    /// One clear-sky model result. Never a measurement: `isClearSkyModel` is
    /// always true and exists so that no view can render these numbers without
    /// having had the chance to see that flag.
    public struct Estimate: Sendable {
        /// Global horizontal irradiance, W/m2 on a horizontal surface.
        public let global: Double
        /// Direct normal irradiance, W/m2 on a surface facing the sun.
        public let direct: Double
        /// Diffuse horizontal irradiance, W/m2 on a horizontal surface.
        public let diffuse: Double
        /// Relative optical air mass, dimensionless.
        public let airMass: Double
        public let isClearSkyModel: Bool
    }

    /// Clear-sky global, direct and diffuse irradiance.
    ///
    /// - Parameters:
    ///   - solarAltitude: apparent (refracted) solar elevation in degrees.
    ///     Kasten and Young state explicitly that their table and formula take
    ///     the apparent elevation, and that using the unrefracted value instead
    ///     introduces substantial error near the horizon. `SolarPositionSPA`
    ///     returns exactly this as `elevation`.
    ///   - elevationMetres: observer height above sea level.
    ///   - earthSunDistanceAU: the sun's radius vector for the instant.
    public static func clearSky(
        solarAltitude: Double,
        elevationMetres: Double,
        earthSunDistanceAU: Double
    ) -> Estimate {
        let mass = airMass(solarAltitude: solarAltitude)
        let cosZenith = Angle.cos(90.0 - solarAltitude)
        guard cosZenith > 0, earthSunDistanceAU > 0 else {
            return Estimate(global: 0, direct: 0, diffuse: 0, airMass: mass, isClearSkyModel: true)
        }

        // Haurwitz fitted a whole year of pyranometer records with one curve, so
        // its 1098 already carries the MEAN earth-sun distance and the published
        // form responds to the orbit not at all. The inverse square factor puts
        // the 3.4 percent annual swing back. Leaving it out is not neutral: the
        // clearness index below would then be the only thing that saw the
        // distance, and the Erbs split would move the direct beam the wrong way,
        // making it strongest in July when the earth is furthest from the sun.
        let distanceFactor = 1.0 / (earthSunDistanceAU * earthSunDistanceAU)
        let global = 1098.0 * cosZenith * exp(-0.059 / cosZenith)
            * altitudeFactor(elevationMetres)
            * distanceFactor

        // Erbs correlates the diffuse fraction against the clearness index, the
        // ratio of what reached the ground to what arrived at the top of the
        // atmosphere on the same horizontal surface. The clamp matters: a
        // clear-sky GHI slightly above the extraterrestrial value at very low
        // sun would otherwise drive the polynomial outside its fitted range.
        let extraterrestrialNormal = solarConstant / (earthSunDistanceAU * earthSunDistanceAU)
        let extraterrestrialHorizontal = extraterrestrialNormal * cosZenith
        let clearnessIndex = min(1.0, global / extraterrestrialHorizontal)

        let diffuse = global * diffuseFraction(clearnessIndex: clearnessIndex)
        let direct = (global - diffuse) / cosZenith

        return Estimate(
            global: global,
            direct: direct,
            diffuse: diffuse,
            airMass: mass,
            isClearSkyModel: true)
    }

    /// Relative optical air mass by Kasten and Young (1989).
    ///
    /// The naive `1 / cos(z)` diverges at the horizon; this stays finite and
    /// reaches about 37.9 there, against the 38.10 to 38.16 that the three
    /// independent tables quoted in the paper give for a standard atmosphere.
    /// The paper's own fit error against its recomputed ISO Standard Atmosphere
    /// table is below 0.5 percent everywhere.
    ///
    /// Air mass is RELATIVE, so it is 1.0 at the zenith at any site height. The
    /// height dependence of the atmosphere belongs in the extinction, not here.
    public static func airMass(solarAltitude: Double) -> Double {
        // Below the horizon there is no meaningful path length. Returning the
        // horizon value rather than a negative or infinite one keeps callers
        // that plot air mass across a whole day from producing a spike.
        let elevation = max(0.0, solarAltitude)
        return 1.0 / (Angle.sin(elevation) + 0.50572 * pow(elevation + 6.07995, -1.6364))
    }

    /// The Erbs et al. (1982) hourly diffuse fraction, diffuse horizontal over
    /// global horizontal, as a function of the hourly clearness index.
    ///
    /// The published coefficients are continuous at both breakpoints, which is
    /// the cheapest check that they have been transcribed correctly.
    public static func diffuseFraction(clearnessIndex: Double) -> Double {
        let kt = min(1.0, max(0.0, clearnessIndex))
        if kt <= 0.22 { return 1.0 - 0.09 * kt }
        if kt <= 0.80 {
            return 0.9511
                - 0.1604 * kt
                + 4.388 * kt * kt
                - 16.638 * kt * kt * kt
                + 12.336 * kt * kt * kt * kt
        }
        return 0.165
    }

    /// Height enhancement of clear-sky global irradiance.
    ///
    /// Haurwitz fitted sea-level pyranometer records and carries no height term
    /// at all, so at 3 km it would be about 15 percent low. The factor here is
    /// the ratio of the altitude coefficient published by Ineichen, P. and
    /// Perez, R. (2002), "A new airmass independent formulation for the Linke
    /// turbidity coefficient", Solar Energy 73(3), 151-157, whose clear-sky
    /// global model carries `a1 = 5.09e-5 * altitude + 0.868`. Normalising that
    /// to sea level gives 5.86 percent per kilometre.
    ///
    /// The height is capped at 5 km, a little above the highest permanently
    /// inhabited place on earth. A linear enhancement extrapolated further would
    /// eventually put more energy on the ground than arrives at the top of the
    /// atmosphere, and no clamp downstream would make that number honest.
    private static func altitudeFactor(_ elevationMetres: Double) -> Double {
        1.0 + (5.09e-5 / 0.868) * min(5000.0, max(0.0, elevationMetres))
    }
}
