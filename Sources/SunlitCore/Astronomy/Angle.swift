import Foundation

/// Angle helpers.
///
/// Every angle in this module is a `Double` in degrees unless the symbol says
/// `Radians`. That convention is not a preference: the astronomical literature
/// this core implements is written in degrees, and translating each published
/// formula into a wrapper type at the point of transcription is where sign and
/// unit errors get introduced. The functions below are the only place the
/// conversion happens.
public enum Angle {

    public static let degreesPerRadian = 180.0 / Double.pi
    public static let radiansPerDegree = Double.pi / 180.0

    @inlinable
    public static func radians(_ degrees: Double) -> Double {
        degrees * radiansPerDegree
    }

    @inlinable
    public static func degrees(_ radians: Double) -> Double {
        radians * degreesPerRadian
    }

    /// Reduces an angle to `[0, 360)`.
    ///
    /// `truncatingRemainder` alone returns a negative value for negative input,
    /// which silently flips an azimuth to the opposite side of the sky.
    @inlinable
    public static func normalized(_ degrees: Double) -> Double {
        let r = degrees.truncatingRemainder(dividingBy: 360.0)
        return r < 0 ? r + 360.0 : r
    }

    /// Reduces an angle to `(-180, 180]`.
    @inlinable
    public static func normalizedSigned(_ degrees: Double) -> Double {
        let r = normalized(degrees)
        return r > 180.0 ? r - 360.0 : r
    }

    /// The shortest angular distance from `a` to `b`, signed, in `(-180, 180]`.
    @inlinable
    public static func difference(from a: Double, to b: Double) -> Double {
        normalizedSigned(b - a)
    }

    @inlinable public static func sin(_ degrees: Double) -> Double { Foundation.sin(radians(degrees)) }
    @inlinable public static func cos(_ degrees: Double) -> Double { Foundation.cos(radians(degrees)) }
    @inlinable public static func tan(_ degrees: Double) -> Double { Foundation.tan(radians(degrees)) }

    @inlinable public static func asin(_ x: Double) -> Double { degrees(Foundation.asin(min(1, max(-1, x)))) }
    @inlinable public static func acos(_ x: Double) -> Double { degrees(Foundation.acos(min(1, max(-1, x)))) }
    @inlinable public static func atan2(_ y: Double, _ x: Double) -> Double { degrees(Foundation.atan2(y, x)) }

    /// Arcseconds to degrees.
    @inlinable public static func fromArcseconds(_ arcseconds: Double) -> Double { arcseconds / 3600.0 }

    /// Degrees to arcseconds.
    @inlinable public static func toArcseconds(_ degrees: Double) -> Double { degrees * 3600.0 }

    /// Degrees to arcminutes.
    @inlinable public static func toArcminutes(_ degrees: Double) -> Double { degrees * 60.0 }

    /// Builds a degree value from sexagesimal parts. The sign of `degrees`
    /// governs the whole value, so `-9, 47, 1.7` is `-9.783806`, not
    /// `-9 + 47/60 + 1.7/3600`.
    public static func fromSexagesimal(_ degrees: Int, _ arcminutes: Int, _ arcseconds: Double) -> Double {
        let magnitude = Double(abs(degrees)) + Double(arcminutes) / 60.0 + arcseconds / 3600.0
        return degrees < 0 ? -magnitude : magnitude
    }

    /// Builds a degree value from an hour angle expressed in hours, minutes and
    /// seconds of time. One hour of right ascension is fifteen degrees.
    public static func fromHours(_ hours: Int, _ minutes: Int, _ seconds: Double) -> Double {
        (Double(hours) + Double(minutes) / 60.0 + seconds / 3600.0) * 15.0
    }
}
