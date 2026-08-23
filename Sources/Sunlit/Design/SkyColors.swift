import SwiftUI

/// The fixed colours of the instrument layer.
///
/// The accents mark bodies and paths: a sun glyph, a moon track, the galactic plane.
/// They are not text colours. Their luminance sits in the middle of the range, so on a
/// bright sky they land near 2 to 1, well under the readable floor. Anything a reader
/// has to read is drawn in `SkyPalette.foreground(solarAltitude:)`, which is audited.
/// Pair an accent mark with a foreground label rather than colouring the label.
public enum SkyColors {

    // MARK: Bodies

    public static let sun = LinearRGB(hex: 0xFFB020).color
    public static let moon = LinearRGB(hex: 0x8FB8FF).color
    public static let milkyWay = LinearRGB(hex: 0xC9A6FF).color

    // MARK: Semantic

    /// Filled behind `onWarning`, never used as text on the sky. As a filled capsule it
    /// reads at 8.9 to 1 against its own ink on every sky, and it is the one element
    /// allowed to ignore the background entirely, because a warning that the sky can
    /// wash out is not a warning.
    public static let warning = LinearRGB(hex: 0xE8A33D).color

    /// The ink to place on `warning`.
    public static let onWarning = LinearRGB(hex: 0x0A0F1A).color

    /// Disabled controls are exempt from the contrast floor under WCAG 1.4.3, and this
    /// is below it on purpose so that off reads as off.
    public static let disabledOpacity: Double = 0.38

    public static func disabled(solarAltitude: Double) -> Color {
        SkyPalette.foreground(solarAltitude: solarAltitude).opacity(disabledOpacity)
    }
}
