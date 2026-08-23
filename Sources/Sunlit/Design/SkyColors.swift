import SwiftUI

/// The fixed colours of the instrument layer.
///
/// The accents mark bodies and paths: a sun glyph, a moon track, the galactic plane.
/// They are not text colours, and they are weaker than that phrasing suggests.
///
/// Measured against every sky the palette can produce, the worst case for each of the
/// three is 1.00 to 1, not the 2 to 1 this comment used to claim: sun `#FFB020` matches
/// the sky exactly at around 26 degrees of solar altitude, moon `#8FB8FF` at 29, Milky
/// Way `#C9A6FF` at 27. They separate by hue and by chroma, and by nothing else. In
/// greyscale, under Color Filters, or for a reader working from luminance, an unbacked
/// accent mark on a day sky is invisible.
///
/// Two rules follow. Anything a reader has to read is drawn in
/// `SkyPalette.foreground(solarAltitude:)`, which is audited; pair an accent mark with a
/// foreground label rather than colouring the label. And any accent mark that carries
/// meaning on its own is given a foreground edge, the way `ArcTrack` backs its travelled
/// arc and rings its marker, so the shape survives when the colour does not.
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
