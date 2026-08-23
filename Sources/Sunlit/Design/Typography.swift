import SwiftUI

/// The type scale.
///
/// Every style is built from a `Font.TextStyle`, never from a fixed point size, so all
/// of it tracks Dynamic Type from extra small through the accessibility sizes. A fixed
/// size here would silently opt the whole app out of the largest sizes App Review tests
/// at, which is the failure this portfolio has already paid for twice.
///
/// SF Pro Display and SF Pro Text are the same system family: the system picks Display
/// above roughly 20 points and Text below it, so asking for the right text style is
/// what selects the right optical size.
public enum SunlitType {

    /// Screen level figure, for the one number a view exists to show.
    public static let display = Font.system(.largeTitle, design: .default).weight(.semibold)

    /// Section headings.
    public static let title = Font.system(.title3, design: .default).weight(.semibold)

    /// Running text.
    public static let body = Font.system(.body, design: .default)

    /// Labels, units, captions, and anything set alongside a figure.
    public static let caption = Font.system(.caption, design: .default).weight(.medium)

    // MARK: Metrics
    //
    // Every number that changes is set with monospaced digits. Without it a ticking
    // countdown or a scrubbing azimuth reflows on each frame and the whole instrument
    // layer twitches.

    public static let metric = Font.system(.title2, design: .default).weight(.medium).monospacedDigit()
    public static let metricLarge = Font.system(.largeTitle, design: .default).weight(.medium).monospacedDigit()
    public static let metricSmall = Font.system(.footnote, design: .default).weight(.medium).monospacedDigit()
}

public extension View {
    /// A small tracked label.
    ///
    /// Hierarchy here comes from size, weight, and tracking, never from opacity. The
    /// contrast floor has no headroom at the ink crossover, so a label at even 0.9
    /// opacity drops to 4.27 to 1 and breaks the guarantee. No text in this system
    /// carries a fade. `SkyContrast.worstContrast(inkOpacity:solarAltitude:)` will say so.
    ///
    /// Uppercasing is visual only: every component that uses this also carries an
    /// explicit accessibility label built from the original string, so VoiceOver never
    /// has to guess at a run of capitals.
    func sunlitLabel() -> some View {
        self
            .font(SunlitType.caption)
            .textCase(.uppercase)
            .tracking(0.5)
    }
}
