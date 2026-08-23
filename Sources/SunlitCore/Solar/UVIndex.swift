import Foundation

/// A clear-sky MODEL of the erythemal ultraviolet index.
///
/// Nothing here is a measurement and nothing here is a forecast. The model sees
/// no cloud, no aerosol, no haze, no snow, and no ozone value measured over the
/// observer today. It answers one question only: what would the UV index be at
/// this sun angle, at this height, under a cloudless sky carrying the
/// climatological mean ozone column for this latitude and season. Real skies are
/// almost always below it, which is why `Estimate.isClearSkyModel` exists and
/// why `modelDisclosure` is the only human-readable string this type offers.
///
/// Formula: Madronich, S. (2007), "Analytic Formula for the Clear-sky UV Index",
/// Photochemistry and Photobiology 83(6), 1537-1538.
///
///     UVI = 12.50 * mu0^2.42 * (omega / 300)^-1.23 * fAltitude * fDistance
///
/// The paper states the formula reproduces a full radiative transfer
/// calculation to 10 percent or better for solar zenith angles of 0 to 60
/// degrees and ozone columns of 200 to 400 Dobson units. Outside that range,
/// and in particular below about 20 degrees solar altitude, the power law in
/// `mu0` decays faster than the real atmosphere does, because it carries no
/// scattered-light term. The index there is small enough that the WHO category
/// is `low` either way, which is the number the interface actually acts on.
public enum UVIndex {

    /// The caption an interface must show wherever it shows this number.
    ///
    /// It is the only string this type publishes, deliberately. Source-language
    /// English; the app layer localises it.
    public static let modelDisclosure = "Clear sky model, not a measurement"

    /// The World Health Organization exposure categories.
    ///
    /// Boundaries from the WHO / WMO / UNEP / ICNIRP "Global Solar UV Index: A
    /// Practical Guide" (2002), table 1: below 3 low, 3 to below 6 moderate,
    /// 6 to below 8 high, 8 to below 11 very high, 11 and above extreme.
    public enum Category: String, Sendable, CaseIterable {
        case low, moderate, high, veryHigh, extreme

        public init(index: Double) {
            switch index {
            case ..<3: self = .low
            case ..<6: self = .moderate
            case ..<8: self = .high
            case ..<11: self = .veryHigh
            default: self = .extreme
            }
        }
    }

    /// One clear-sky model result. Never a measurement: `isClearSkyModel` is
    /// always true and exists so that no view can render `index` without having
    /// had the chance to see that flag.
    public struct Estimate: Sendable {
        public let index: Double
        public let category: Category
        /// The total column ozone the model used, in Dobson units.
        public let ozoneDobson: Double
        public let isClearSkyModel: Bool
    }

    /// Clear-sky UV index using the embedded ozone climatology.
    ///
    /// - Parameters:
    ///   - solarAltitude: true (geometric, unrefracted) solar altitude in
    ///     degrees. `mu0` in the published formula is the cosine of the true
    ///     solar zenith angle. Refraction changes it by far less than the
    ///     model's own error except within a degree of the horizon, where the
    ///     index is essentially zero anyway.
    ///   - elevationMetres: observer height above sea level.
    ///   - earthSunDistanceAU: the sun's radius vector for the instant.
    ///   - latitude: degrees, positive north. Selects the climatology band.
    ///   - dayOfYear: 1 to 366. Selects the season.
    public static func estimate(
        solarAltitude: Double,
        elevationMetres: Double,
        earthSunDistanceAU: Double,
        latitude: Double,
        dayOfYear: Int
    ) -> Estimate {
        estimate(
            solarAltitude: solarAltitude,
            elevationMetres: elevationMetres,
            earthSunDistanceAU: earthSunDistanceAU,
            ozoneDobson: climatologicalOzone(latitude: latitude, dayOfYear: dayOfYear))
    }

    /// Clear-sky UV index for a known ozone column.
    ///
    /// The two error sources in this model, the formula and the climatology, are
    /// independent and are validated separately. This entry point is the one
    /// that carries only the formula.
    public static func estimate(
        solarAltitude: Double,
        elevationMetres: Double,
        earthSunDistanceAU: Double,
        ozoneDobson: Double
    ) -> Estimate {
        let mu0 = max(0.0, Angle.cos(90.0 - solarAltitude))
        guard mu0 > 0, ozoneDobson > 0, earthSunDistanceAU > 0 else {
            return Estimate(index: 0, category: .low, ozoneDobson: ozoneDobson, isClearSkyModel: true)
        }
        let fAltitude = 1.0 + 0.06 * elevationMetres / 1000.0
        let fDistance = 1.0 / (earthSunDistanceAU * earthSunDistanceAU)
        let index = 12.50
            * pow(mu0, 2.42)
            * pow(ozoneDobson / 300.0, -1.23)
            * fAltitude
            * fDistance
        return Estimate(
            index: index,
            category: Category(index: index),
            ozoneDobson: ozoneDobson,
            isClearSkyModel: true)
    }

    /// Climatological total column ozone in Dobson units.
    ///
    /// Source: NASA GSFC SBUV/OMPS Merged Ozone Data, monthly zonal means of
    /// layer ozone amounts, OMPS NP v2.8, 5 degree latitude zones, file
    /// `MZM_OMPS_NP_lyr.txt` from
    /// `acd-ext.gsfc.nasa.gov/anonftp/toms/sbuv/zonal_means/`, 107 months
    /// covering February 2012 to December 2020. The published total column row
    /// of each monthly block was averaged over years, then interpolated from the
    /// 5 degree measurement zones onto the 10 degree bands below.
    ///
    /// Two limitations that matter and are not bugs. It is a ZONAL mean, so it
    /// carries no longitude: over Europe in December the real column runs about
    /// 10 percent below this table while over western Canada it runs above it,
    /// because the winter polar vortex is not centred on the pole. And SBUV
    /// measures backscattered sunlight, so it has no polar-night data; those
    /// cells are filled by interpolating each band around the year. That fill
    /// is invisible in practice: with the sun below the horizon the index is
    /// zero whatever the ozone.
    public static func climatologicalOzone(latitude: Double, dayOfYear: Int) -> Double {
        let lat = min(90.0, max(-90.0, latitude))
        let position = (lat + 90.0) / 10.0
        let band = min(17, max(0, Int(position.rounded(.down))))
        let bandFraction = position - Double(band)

        func monthlyMean(_ month: Int) -> Double {
            let row = ozoneByMonthAndBand[month]
            return row[band] * (1.0 - bandFraction) + row[band + 1] * bandFraction
        }

        // Each monthly mean is anchored at the middle of its month and the year
        // is interpolated as a closed loop, so 31 December and 1 January agree.
        let day = Double(((dayOfYear - 1) % 365 + 365) % 365 + 1)
        var earlier = 11, later = 0
        var earlierAnchor = midMonthDayOfYear[11] - 365.0
        var laterAnchor = midMonthDayOfYear[0]
        if day >= midMonthDayOfYear[11] {
            earlier = 11; later = 0
            earlierAnchor = midMonthDayOfYear[11]; laterAnchor = midMonthDayOfYear[0] + 365.0
        } else if day >= midMonthDayOfYear[0] {
            for month in 0..<11 where day >= midMonthDayOfYear[month] && day <= midMonthDayOfYear[month + 1] {
                earlier = month; later = month + 1
                earlierAnchor = midMonthDayOfYear[month]; laterAnchor = midMonthDayOfYear[month + 1]
            }
        }
        let weight = (day - earlierAnchor) / (laterAnchor - earlierAnchor)
        return monthlyMean(earlier) * (1.0 - weight) + monthlyMean(later) * weight
    }

    /// Day of year of the middle of each month in a common year.
    private static let midMonthDayOfYear: [Double] = [
        15.5, 45.0, 74.5, 105.0, 135.5, 166.0, 196.5, 227.5, 258.0, 288.5, 319.0, 349.5
    ]

    /// Total column ozone in Dobson units, by calendar month and by 10 degree
    /// latitude band from -90 to +90. See `climatologicalOzone` for the source.
    private static let ozoneByMonthAndBand: [[Double]] = [
        //   -90    -80    -70    -60    -50    -40    -30    -20    -10      0     10     20     30     40     50     60     70     80     90
        [287.3, 287.3, 295.7, 306.5, 296.8, 278.5, 266.7, 257.6, 249.5, 244.1, 241.9, 248.8, 274.9, 331.4, 377.5, 383.0, 363.4, 364.3, 364.3],
        [278.7, 278.7, 289.0, 296.8, 285.1, 272.7, 263.1, 255.5, 250.6, 247.2, 245.6, 255.8, 283.8, 342.2, 392.9, 408.1, 395.7, 389.3, 389.3],
        [275.9, 275.9, 288.6, 292.0, 278.8, 269.4, 262.7, 254.5, 251.3, 251.5, 254.0, 268.1, 296.8, 347.9, 391.7, 412.5, 418.5, 414.3, 414.3],
        [264.0, 264.0, 283.5, 299.0, 284.7, 270.3, 262.0, 254.2, 250.0, 251.6, 259.8, 279.1, 307.9, 348.6, 382.5, 404.2, 417.9, 421.7, 421.7],
        [252.2, 252.2, 274.2, 305.4, 304.0, 284.3, 263.0, 253.8, 249.0, 251.3, 263.6, 284.0, 308.3, 340.0, 367.9, 381.8, 388.1, 390.3, 390.3],
        [240.3, 240.3, 264.8, 307.0, 320.8, 302.4, 271.0, 254.8, 249.1, 254.9, 267.0, 283.3, 297.6, 324.1, 348.1, 352.9, 346.7, 347.0, 347.0],
        [228.4, 228.4, 255.5, 313.4, 333.5, 317.2, 281.4, 258.8, 252.3, 259.8, 269.8, 282.0, 292.2, 306.0, 326.3, 329.6, 317.7, 312.4, 312.4],
        [216.4, 216.4, 246.0, 317.7, 344.5, 329.2, 291.2, 265.0, 257.6, 264.4, 270.6, 278.3, 286.5, 297.4, 311.3, 312.4, 301.6, 293.0, 293.0],
        [204.5, 204.5, 229.6, 317.0, 351.2, 337.0, 302.7, 274.6, 261.7, 264.5, 267.4, 272.5, 279.0, 290.0, 300.8, 305.1, 297.7, 289.2, 289.2],
        [192.6, 192.6, 246.9, 325.8, 349.6, 333.2, 304.7, 279.0, 261.9, 259.2, 260.6, 264.5, 270.5, 282.0, 300.9, 312.7, 306.5, 286.3, 286.3],
        [264.0, 264.0, 289.4, 325.2, 329.7, 313.6, 294.3, 275.1, 258.7, 251.8, 251.6, 256.4, 267.1, 289.4, 318.2, 327.9, 320.9, 312.1, 312.1],
        [290.1, 290.1, 302.4, 317.9, 310.7, 291.1, 278.2, 264.9, 253.1, 246.1, 244.5, 249.1, 267.7, 310.8, 349.4, 349.3, 342.0, 338.0, 338.0]
    ]
}
