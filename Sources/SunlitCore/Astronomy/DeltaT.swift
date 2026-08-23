import Foundation

// The coefficients in this file were transcribed from "Polynomial Expressions
// for Delta T" by Fred Espenak, NASA/GSFC, adapted from Espenak and Meeus,
// "Five Millennium Canon of Solar Eclipses: -1999 to +3000", at
// https://eclipse.gsfc.nasa.gov/SEhelp/deltatpoly2004.html
//
// One wrong digit here yields a sky that looks right and is not, so the
// transcription was checked three further ways: against NASA's second copy of
// the same page at https://eclipse.gsfc.nasa.gov/SEcat5/deltatpoly.html, whose
// expressions are character for character identical to the first, and against
// two independent reproductions, the Astronomy Engine
// (github.com/cosinekitty/astronomy, source/python/astronomy/astronomy.py) and
// astronomia (github.com/commenthol/astronomia, src/deltat.js). All four agree
// on every coefficient of every branch.
//
// The two NASA copies differ in exactly one respect. For the two parabolic
// branches the 2004 copy writes the substitution as u = (year-1820)/100 while
// the later copy writes u = (y-1820)/100, meaning the decimal year. This file
// follows the later reading, which is also what both reproductions use. The
// choice is not cosmetic: at the -1999 end of the range the two readings differ
// by up to eleven seconds, because there the parabola changes by roughly
// twenty-four seconds for every year of argument.

/// Delta T, the difference TT minus UT1, in seconds.
///
/// The ephemerides in this module are evaluated in Terrestrial Time, which
/// ticks uniformly. Civil clocks and the sky over a given meridian follow UT1,
/// which is defined by the rotation of the Earth and therefore drifts, because
/// the planet is not a good clock. Delta T is the bridge between the two, so
/// every rise, set and transit time this app produces inherits whatever error
/// delta T carries.
///
/// ## Values after roughly 2025 are extrapolations, not observations
///
/// Espenak and Meeus fitted the 2005 to 2050 branch in 2007 from two estimated
/// values, one for 2010 and one for 2050, each obtained by continuing the
/// recent trend in a straight line. The rotation of the Earth does not continue
/// trends. It has run slightly fast since the late 2010s, so the measured delta
/// T has stayed near 69 seconds while this polynomial climbs past 74 seconds by
/// 2025, and the gap widens from there.
///
/// The app must therefore not present rise and set times far in the future as
/// accurate to better than a second, and should not display a seconds field at
/// all for dates many years out. No better formula fixes this, because what is
/// missing is a future measurement of the Earth's rotation, not a better fit.
/// Only shipping observed delta T values, or fetching them, would improve it.
public enum DeltaT {

    /// Delta T in seconds for a decimal year, using the Espenak and Meeus
    /// polynomial expressions published with the NASA eclipse canon.
    ///
    /// The published set covers the years -1999 to +3000. Arguments outside
    /// that span still return a value, since the branches at either end are
    /// the unbounded Morrison and Stephenson parabola, but nothing supports
    /// those values.
    ///
    /// The result includes the lunar acceleration correction described under
    /// ``lunarAccelerationCorrection(decimalYear:)``.
    public static func seconds(decimalYear y: Double) -> Double {
        polynomialSeconds(decimalYear: y) + lunarAccelerationCorrection(decimalYear: y)
    }

    /// Convenience: delta T in seconds for a Julian day.
    public static func seconds(julianDay: JulianDay) -> Double {
        seconds(decimalYear: decimalYear(julianDay: julianDay))
    }

    /// The decimal year the polynomials take as their argument, y = year +
    /// (month - 0.5) / 12, which places y at the middle of the calendar month.
    ///
    /// The step from one month to the next makes delta T jump by a few
    /// milliseconds at each month boundary. That is the published definition
    /// and it is deliberate on Espenak and Meeus's part: delta T itself is not
    /// known to anything like that resolution, so a smoother argument would
    /// only dress up precision the quantity does not have.
    public static func decimalYear(julianDay: JulianDay) -> Double {
        let date = julianDay.calendarDate
        return Double(date.year) + (Double(date.month) - 0.5) / 12.0
    }

    /// The correction Espenak and Meeus add outside the directly observed
    /// interval, c = -0.000012932 * (y - 1955)^2 seconds.
    ///
    /// The tabulated delta T values that the polynomials fit come from Morrison
    /// and Stephenson (2004), who assumed a lunar secular acceleration of -26
    /// arcseconds per century squared. The lunar theory used by the canon, and
    /// by this module, is ELP-2000/82, which uses -25.858. Delta T deduced from
    /// ancient eclipse records depends on that assumed acceleration, so the
    /// values have to be shifted before they can be used with a different
    /// ephemeris.
    ///
    /// Between 1955 and 2005 delta T was measured directly rather than deduced
    /// from eclipses, so no shift applies there and the correction is skipped.
    /// This leaves a step of about 0.03 seconds at 2005, which is far below the
    /// uncertainty in delta T and far below what the app displays. There is no
    /// step at 1955, where the correction is zero by construction.
    public static func lunarAccelerationCorrection(decimalYear y: Double) -> Double {
        guard y < 1955.0 || y > 2005.0 else { return 0.0 }
        let t = y - 1955.0
        return -0.000012932 * t * t
    }

    /// The piecewise polynomial set itself, before the lunar correction.
    ///
    /// Each expression is written in the published term order rather than in
    /// Horner form, so that a reader can compare it line by line against the
    /// source page. The cost is a handful of multiplications per call.
    private static func polynomialSeconds(decimalYear y: Double) -> Double {

        // Before the year -500.
        if y < -500.0 {
            let u = (y - 1820.0) / 100.0
            return -20.0 + 32.0 * u * u
        }

        // Years -500 to +500.
        if y < 500.0 {
            let u = y / 100.0
            let u2 = u * u, u3 = u2 * u, u4 = u3 * u, u5 = u4 * u, u6 = u5 * u
            return 10583.6 - 1014.41 * u + 33.78311 * u2 - 5.952053 * u3
                - 0.1798452 * u4 + 0.022174192 * u5 + 0.0090316521 * u6
        }

        // Years +500 to +1600.
        if y < 1600.0 {
            let u = (y - 1000.0) / 100.0
            let u2 = u * u, u3 = u2 * u, u4 = u3 * u, u5 = u4 * u, u6 = u5 * u
            return 1574.2 - 556.01 * u + 71.23472 * u2 + 0.319781 * u3
                - 0.8503463 * u4 - 0.005050998 * u5 + 0.0083572073 * u6
        }

        // Years +1600 to +1700.
        if y < 1700.0 {
            let t = y - 1600.0
            let t2 = t * t, t3 = t2 * t
            return 120.0 - 0.9808 * t - 0.01532 * t2 + t3 / 7129.0
        }

        // Years +1700 to +1800.
        if y < 1800.0 {
            let t = y - 1700.0
            let t2 = t * t, t3 = t2 * t, t4 = t3 * t
            return 8.83 + 0.1603 * t - 0.0059285 * t2 + 0.00013336 * t3 - t4 / 1174000.0
        }

        // Years +1800 to +1860.
        if y < 1860.0 {
            let t = y - 1800.0
            let t2 = t * t, t3 = t2 * t, t4 = t3 * t, t5 = t4 * t, t6 = t5 * t, t7 = t6 * t
            return 13.72 - 0.332447 * t + 0.0068612 * t2 + 0.0041116 * t3 - 0.00037436 * t4
                + 0.0000121272 * t5 - 0.0000001699 * t6 + 0.000000000875 * t7
        }

        // Years 1860 to 1900.
        if y < 1900.0 {
            let t = y - 1860.0
            let t2 = t * t, t3 = t2 * t, t4 = t3 * t, t5 = t4 * t
            return 7.62 + 0.5737 * t - 0.251754 * t2 + 0.01680668 * t3
                - 0.0004473624 * t4 + t5 / 233174.0
        }

        // Years 1900 to 1920.
        if y < 1920.0 {
            let t = y - 1900.0
            let t2 = t * t, t3 = t2 * t, t4 = t3 * t
            return -2.79 + 1.494119 * t - 0.0598939 * t2 + 0.0061966 * t3 - 0.000197 * t4
        }

        // Years 1920 to 1941.
        if y < 1941.0 {
            let t = y - 1920.0
            let t2 = t * t, t3 = t2 * t
            return 21.20 + 0.84493 * t - 0.076100 * t2 + 0.0020936 * t3
        }

        // Years 1941 to 1961. The origin is 1950, not the start of the
        // interval. Espenak and Meeus centre several of these fits, and reading
        // the origin off the interval instead of off the published formula is
        // the easiest way to get a wrong answer here.
        if y < 1961.0 {
            let t = y - 1950.0
            let t2 = t * t, t3 = t2 * t
            return 29.07 + 0.407 * t - t2 / 233.0 + t3 / 2547.0
        }

        // Years 1961 to 1986. The origin is 1975.
        if y < 1986.0 {
            let t = y - 1975.0
            let t2 = t * t, t3 = t2 * t
            return 45.45 + 1.067 * t - t2 / 260.0 - t3 / 718.0
        }

        // Years 1986 to 2005. The origin is 2000.
        if y < 2005.0 {
            let t = y - 2000.0
            let t2 = t * t, t3 = t2 * t, t4 = t3 * t, t5 = t4 * t
            return 63.86 + 0.3345 * t - 0.060374 * t2 + 0.0017275 * t3
                + 0.000651814 * t4 + 0.00002373599 * t5
        }

        // Years 2005 to 2050. This is the extrapolated branch the type comment
        // warns about, and it is the one the app spends nearly all its time in.
        if y < 2050.0 {
            let t = y - 2000.0
            return 62.92 + 0.32217 * t + 0.005589 * t * t
        }

        // Years 2050 to 2150. The final term is not part of the parabola. It is
        // there to close the gap the parabola would otherwise leave at 2050,
        // where it takes over from the fitted branch above, and it decays to
        // zero by 2150.
        if y < 2150.0 {
            let u = (y - 1820.0) / 100.0
            return -20.0 + 32.0 * u * u - 0.5628 * (2150.0 - y)
        }

        // After 2150.
        let u = (y - 1820.0) / 100.0
        return -20.0 + 32.0 * u * u
    }
}
