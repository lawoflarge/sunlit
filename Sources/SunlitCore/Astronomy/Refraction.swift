import Foundation

/// Atmospheric refraction.
///
/// Light bends as it enters the atmosphere, so a body appears higher than it
/// geometrically is. At the horizon the effect is about 34 arcminutes, which is
/// slightly more than the sun's own diameter: the whole sun is already
/// geometrically below the horizon at the moment it appears to touch it. That
/// is why sunrise is defined at a true altitude of about -0.833 degrees rather
/// than at zero, and it is the single largest correction in this module.
public enum Refraction {

    /// Standard sea-level pressure in millibars.
    public static let standardPressure = 1010.0
    /// Standard temperature in degrees Celsius.
    public static let standardTemperature = 10.0

    /// The apparent angular radius of the sun's disc, in degrees, at one
    /// astronomical unit. Used to define the horizon depression at sunrise.
    public static let solarSemidiameterAtOneAU = 0.26667

    /// The refraction at the horizon, in degrees, used to define the standard
    /// altitude for rise and set. Together with the solar semidiameter this
    /// gives the familiar -0.8333 degrees.
    public static let horizontalRefraction = 0.5667

    /// The true altitude at which the upper limb of the sun appears to touch a
    /// flat horizon. This is the target the rise and set solver uses.
    public static let sunriseAltitude = -(solarSemidiameterAtOneAU + horizontalRefraction)

    /// The pressure and temperature scaling both formulae below share. Colder,
    /// denser air bends light more.
    private static func densityFactor(pressure: Double, temperature: Double) -> Double {
        (pressure / standardPressure) * (283.0 / (273.0 + temperature))
    }

    /// Refraction correction to add to a *true* altitude to get the apparent
    /// one, in degrees. Saemundsson's formula, Meeus 16.4, with the pressure
    /// and temperature scaling the NREL algorithm applies.
    ///
    /// This is the direction the app needs: the ephemeris produces a geometric
    /// altitude, and the interface shows where the body appears.
    public static func apparentFromTrue(
        trueAltitude h0: Double,
        pressure: Double = standardPressure,
        temperature: Double = standardTemperature
    ) -> Double {
        // Below the point where the whole disc plus the horizon refraction is
        // gone, the formula stops meaning anything and would grow without
        // bound. NREL guards it at the same threshold.
        guard h0 >= -(solarSemidiameterAtOneAU + horizontalRefraction) else { return 0 }
        let arcminutes = 1.02 / Angle.tan(h0 + 10.3 / (h0 + 5.11))
        // Within a tenth of a degree of the zenith the bracket exceeds ninety
        // degrees, the tangent turns negative, and the formula would hand back a
        // refraction that bends light the wrong way. The real value there is a
        // rounding error away from zero.
        return max(0, densityFactor(pressure: pressure, temperature: temperature) * arcminutes / 60.0)
    }

    /// Refraction correction to subtract from an *apparent* altitude to get the
    /// true one, in degrees. Bennett's formula, Meeus 16.3, with the optional
    /// second-order correction Meeus gives for higher accuracy.
    public static func trueFromApparent(
        apparentAltitude h: Double,
        pressure: Double = standardPressure,
        temperature: Double = standardTemperature,
        refined: Bool = true
    ) -> Double {
        guard h >= -1.0 else { return 0 }
        var arcminutes = 1.0 / Angle.tan(h + 7.31 / (h + 4.4))
        if refined {
            // Meeus notes Bennett's formula is accurate to about 0.07
            // arcminutes and gives this term to bring it closer.
            arcminutes -= 0.06 * Angle.sin(14.7 * arcminutes + 13.0)
        }
        return max(0, densityFactor(pressure: pressure, temperature: temperature) * arcminutes / 60.0)
    }

    /// Air pressure in millibars at a given elevation, from the barometric
    /// formula with a standard atmosphere. Used when the caller knows the
    /// elevation but not the pressure, which is every case in this app.
    public static func pressure(atElevation metres: Double) -> Double {
        standardPressure * pow(1.0 - 0.0065 * metres / 288.15, 5.2559)
    }
}
