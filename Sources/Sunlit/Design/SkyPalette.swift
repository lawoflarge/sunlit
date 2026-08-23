import Foundation
import SwiftUI

// MARK: - Linear light colour

/// A colour held in linear light sRGB.
///
/// Everything in this file interpolates here or in Oklab, never in gamma encoded
/// components. Blending gamma encoded violet into amber crosses a dead grey, which
/// is exactly the muddy band the adaptive sky must not have.
public struct LinearRGB: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Builds from an sRGB hex literal such as `0x2E7FD4`, so the constants below
    /// can be read straight against the palette table in the design spec.
    public init(hex: UInt32) {
        self.init(
            red: Self.linearised(Double((hex >> 16) & 0xFF) / 255),
            green: Self.linearised(Double((hex >> 8) & 0xFF) / 255),
            blue: Self.linearised(Double(hex & 0xFF) / 255)
        )
    }

    public static func linearised(_ channel: Double) -> Double {
        let c = min(max(channel, 0), 1)
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    public static func encoded(_ channel: Double) -> Double {
        let c = min(max(channel, 0), 1)
        return c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
    }

    /// Gamma encoded sRGB components, which is what `Color` and the display want.
    public var encodedComponents: (red: Double, green: Double, blue: Double) {
        (Self.encoded(red), Self.encoded(green), Self.encoded(blue))
    }

    public var color: Color {
        let c = encodedComponents
        return Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: 1)
    }

    /// WCAG 2.1 relative luminance. The components are already linear light, which
    /// is the space the formula is defined in.
    public var relativeLuminance: Double {
        0.2126 * min(max(red, 0), 1)
            + 0.7152 * min(max(green, 0), 1)
            + 0.0722 * min(max(blue, 0), 1)
    }

    /// This colour laid over another at a given opacity, composited in gamma encoded
    /// components, which is how the renderer blends standard range content.
    public func composited(over background: LinearRGB, opacity: Double) -> LinearRGB {
        let alpha = min(max(opacity, 0), 1)
        let front = encodedComponents, back = background.encodedComponents
        return LinearRGB(
            red: Self.linearised(front.red * alpha + back.red * (1 - alpha)),
            green: Self.linearised(front.green * alpha + back.green * (1 - alpha)),
            blue: Self.linearised(front.blue * alpha + back.blue * (1 - alpha))
        )
    }

    /// The colour as the panel will actually show it, rounded to 8 bits per channel.
    /// The audit measures this rather than the ideal value, so the guarantee holds
    /// on the glass and not only in the arithmetic.
    public var quantised: LinearRGB {
        let c = encodedComponents
        return LinearRGB(
            red: Self.linearised((c.red * 255).rounded() / 255),
            green: Self.linearised((c.green * 255).rounded() / 255),
            blue: Self.linearised((c.blue * 255).rounded() / 255)
        )
    }
}

// MARK: - Oklab

/// Oklab, from Björn Ottosson's 2020 derivation. Perceptually even, so a mid point
/// between two anchors looks like a mid point.
struct Oklab: Equatable {
    var l: Double
    var a: Double
    var b: Double

    static func mix(_ x: Oklab, _ y: Oklab, _ t: Double) -> Oklab {
        Oklab(l: x.l + (y.l - x.l) * t, a: x.a + (y.a - x.a) * t, b: x.b + (y.b - x.b) * t)
    }
}

extension LinearRGB {
    var oklab: Oklab {
        let l = 0.4122214708 * red + 0.5363325363 * green + 0.0514459929 * blue
        let m = 0.2119034982 * red + 0.6806995451 * green + 0.1073969566 * blue
        let s = 0.0883024619 * red + 0.2817188376 * green + 0.6299787005 * blue
        let lr = cbrt(l), mr = cbrt(m), sr = cbrt(s)
        return Oklab(
            l: 0.2104542553 * lr + 0.7936177850 * mr - 0.0040720468 * sr,
            a: 1.9779984951 * lr - 2.4285922050 * mr + 0.4505937099 * sr,
            b: 0.0259040371 * lr + 0.7827717662 * mr - 0.8086757660 * sr
        )
    }

    init(_ oklab: Oklab) {
        let lr = oklab.l + 0.3963377774 * oklab.a + 0.2158037573 * oklab.b
        let mr = oklab.l - 0.1055613458 * oklab.a - 0.0638541728 * oklab.b
        let sr = oklab.l - 0.0894841775 * oklab.a - 1.2914855480 * oklab.b
        let l = lr * lr * lr, m = mr * mr * mr, s = sr * sr * sr
        self.init(
            red: min(max(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s, 0), 1),
            green: min(max(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s, 0), 1),
            blue: min(max(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s, 0), 1)
        )
    }

    static func mix(_ x: LinearRGB, _ y: LinearRGB, _ t: Double) -> LinearRGB {
        LinearRGB(Oklab.mix(x.oklab, y.oklab, min(max(t, 0), 1)))
    }
}

// MARK: - The adaptive sky

/// The background gradient is a readout, not decoration. Its stops are interpolated
/// continuously from the solar altitude at the selected instant and place.
///
/// The one non obvious constraint is legibility. A light foreground reaches only
/// 1.60 to 1 against the brightest band of the full day palette, so the ink has to flip
/// from light to dark somewhere. Because the gradient is continuous, at the altitude
/// where it flips both inks must clear 4.5 to 1 at once, which is only possible where
/// the gradient is close to isoluminant. Solving that balance gives an ideal ceiling of
/// 4.5826 to 1 for any continuous sky carrying a single ink, reached with pure white,
/// pure black, and a sky luminance of 0.1791 at the flip. The `dusk` anchor below is
/// placed exactly there, at the boundary between blue hour and golden hour, and it is
/// isoluminant on purpose: its two stops differ in hue, not in brightness.
///
/// The ideal ceiling is not what the panel shows. Once the stops are quantised to 8 bits
/// and the renderer interpolates between them, the measured worst case is 4.5500 to 1,
/// at solar altitude -4.01 with the light ink. That is the real number, and it leaves
/// 0.05 of headroom over the 4.5 floor. `SkyContrast.audit()` measures it over the whole
/// domain and `SkyPaletteContrastTests` fails the build if it ever drops. Move these
/// constants and that proof moves with them, so run the audit after any change.
public struct SkyPalette {
    private struct Anchor {
        let altitude: Double
        let top: LinearRGB
        let bottom: LinearRGB
    }

    /// Solar altitude in degrees mapped to the vertical pair for that sky.
    /// Below the first anchor and above the last the palette holds steady.
    private static let anchors: [Anchor] = [
        // Deep night. Fixed by the design spec.
        Anchor(altitude: -18, top: LinearRGB(hex: 0x070B18), bottom: LinearRGB(hex: 0x0D1430)),
        // Astronomical into civil: the navy lifts into violet.
        Anchor(altitude: -6, top: LinearRGB(hex: 0x2F2047), bottom: LinearRGB(hex: 0x6F386B)),
        // Dusk. Isoluminant at 0.1791, and the altitude at which the ink flips.
        Anchor(altitude: -4, top: LinearRGB(hex: 0x93678F), bottom: LinearRGB(hex: 0xAF5F51)),
        // Civil twilight resolving into rose at the horizon.
        Anchor(altitude: 0, top: LinearRGB(hex: 0xAC6E91), bottom: LinearRGB(hex: 0xE9956F)),
        // Golden.
        Anchor(altitude: 6, top: LinearRGB(hex: 0xCD7B5F), bottom: LinearRGB(hex: 0xF6BC4F)),
        // Haze. This anchor routes the hue path from golden to day. Amber and sky blue
        // sit almost opposite each other in Oklab, so a run between them passes close to
        // the neutral axis and, on the green side, turns the horizon band a pale sage.
        //
        // The anchor that used to sit here, #868498 to #BEC9D4, was itself near neutral.
        // Along its own two columns the least chromatic point fell to 0.0036, worse than
        // the 0.0188 a direct amber to blue run with no anchor reaches: it swapped a
        // slightly green grey for a deader one. These values sit off the neutral axis on
        // the blue side and lift that figure to 0.0349, while holding the Oklab lightness
        // of the pair they replaced so the contrast proof does not move. Worst case over
        // 6 to 30 degrees is 5.1021 to 1, against 5.0972 before.
        //
        // What this does NOT fix, and no choice of anchor colour can: between about 10
        // and 19 degrees the top of the sky is still cool while the horizon is still
        // warm, so the vertical mix between the two columns crosses the neutral axis and
        // one of the nine emitted stops goes grey. Measured over every stop, the least
        // chromatic point is 0.0017 here, against 0.0009 for the old anchor and 0.0037
        // with no anchor at all. Removing the anchor scores better on that one number and
        // worse on the horizon, which is why it stays. Killing the crossing outright
        // needs both columns held on the same side of the hue circle through the
        // handover, which is a palette redesign and an owner decision, not a repair.
        // `SkyPaletteContrastTests.testTheDaytimeRunDoesNotGetGreyerThanItIs` pins it.
        Anchor(altitude: 14, top: LinearRGB(hex: 0x7684B7), bottom: LinearRGB(hex: 0x8BD4EC)),
        // Full day. Fixed by the design spec.
        Anchor(altitude: 30, top: LinearRGB(hex: 0x2E7FD4), bottom: LinearRGB(hex: 0x9FD3F5))
    ]

    /// Moonlight lifts a clear night a little. Blended toward, never past.
    private static let moonlitTop = LinearRGB(hex: 0x1C203B)
    private static let moonlitBottom = LinearRGB(hex: 0x2F3B62)

    /// Number of emitted stops. Enough that whatever space the renderer blends in
    /// between them cannot move the luminance far, which the audit relies on.
    public static let stopCount = 9

    /// Pushes the bright band down toward the horizon rather than spreading it evenly.
    private static let horizonBias = 1.4

    /// The altitude at which the ink flips, which is the blue hour and golden hour
    /// boundary the event solver already uses.
    public static let inkCrossoverAltitude: Double = -4

    /// Pure, because nothing less pure clears 4.5 to 1 on both sides of the flip.
    private static let nightInk = LinearRGB(hex: 0xFFFFFF)
    private static let dayInk = LinearRGB(hex: 0x000000)

    // MARK: Public surface

    /// The vertical gradient for a solar altitude, top of screen to horizon.
    public static func gradient(solarAltitude: Double, moonIllumination: Double = 0) -> LinearGradient {
        LinearGradient(
            gradient: Gradient(stops: stops(solarAltitude: solarAltitude, moonIllumination: moonIllumination)),
            startPoint: .top,
            endPoint: .bottom
        )
    }

    public static func stops(solarAltitude: Double, moonIllumination: Double = 0) -> [Gradient.Stop] {
        skyColours(solarAltitude: solarAltitude, moonIllumination: moonIllumination)
            .enumerated()
            .map { Gradient.Stop(color: $0.element.color, location: CGFloat($0.offset) / CGFloat(stopCount - 1)) }
    }

    /// The ink for every figure, rule, and glyph laid over that sky.
    ///
    /// Text is drawn in this colour at full strength. The floor has no headroom at the
    /// crossover, so a fade of even one tenth breaks it. Hierarchy comes from size,
    /// weight, and tracking instead.
    public static func foreground(solarAltitude: Double) -> Color {
        ink(solarAltitude: solarAltitude).color
    }

    static func ink(solarAltitude: Double) -> LinearRGB {
        solarAltitude < inkCrossoverAltitude ? nightInk : dayInk
    }

    /// The instrument line: the same ink at 55 percent, for rules and inactive tracks.
    ///
    /// Separators and guides only, and that restriction is not stylistic. Measured against
    /// the sky it sits on this reaches only 2.48 to 1 at its worst, at the ink crossover.
    /// WCAG 1.4.11 exempts a purely decorative rule, so a `HairlineDivider` may use it,
    /// but the visible boundary of a control may not: use `componentBorder` there.
    public static let instrumentLineOpacity: Double = 0.55

    public static func instrumentLine(solarAltitude: Double) -> Color {
        foreground(solarAltitude: solarAltitude).opacity(instrumentLineOpacity)
    }

    /// The stroke for the visible boundary of a control, such as a chip capsule.
    ///
    /// WCAG 1.4.11 asks for 3 to 1 between a user interface component's boundary and
    /// what is adjacent to it. The instrument line at 55 percent does not reach that:
    /// it bottoms out at 2.48 to 1 at the ink crossover and 2.86 to 1 in full day. The
    /// lowest opacity that clears 3 to 1 on every sky is 0.65; this sits at 0.70, which
    /// measures 3.40 to 1 at its worst. `SkyContrast.worstComponentBorderContrast()`
    /// is the sweep that says so.
    public static let componentBorderOpacity: Double = 0.70

    public static func componentBorder(solarAltitude: Double) -> Color {
        foreground(solarAltitude: solarAltitude).opacity(componentBorderOpacity)
    }

    // MARK: Internals

    static func skyColours(solarAltitude: Double, moonIllumination: Double) -> [LinearRGB] {
        var (top, bottom) = pair(solarAltitude: solarAltitude)
        let lift = nightWeight(solarAltitude) * min(max(moonIllumination, 0), 1) * 0.9
        if lift > 0 {
            top = LinearRGB.mix(top, moonlitTop, lift)
            bottom = LinearRGB.mix(bottom, moonlitBottom, lift)
        }
        return (0..<stopCount).map { index in
            let t = Double(index) / Double(stopCount - 1)
            return LinearRGB.mix(top, bottom, pow(t, horizonBias))
        }
    }

    private static func pair(solarAltitude: Double) -> (top: LinearRGB, bottom: LinearRGB) {
        guard let first = anchors.first, let last = anchors.last else {
            return (dayInk, dayInk)
        }
        if solarAltitude <= first.altitude { return (first.top, first.bottom) }
        if solarAltitude >= last.altitude { return (last.top, last.bottom) }
        for index in 0..<(anchors.count - 1) {
            let lower = anchors[index], upper = anchors[index + 1]
            guard solarAltitude <= upper.altitude else { continue }
            let t = smoothstep((solarAltitude - lower.altitude) / (upper.altitude - lower.altitude))
            return (LinearRGB.mix(lower.top, upper.top, t), LinearRGB.mix(lower.bottom, upper.bottom, t))
        }
        return (last.top, last.bottom)
    }

    /// Full moonlight below 12 degrees, none once civil twilight has taken over.
    private static func nightWeight(_ solarAltitude: Double) -> Double {
        if solarAltitude <= -12 { return 1 }
        if solarAltitude >= -6 { return 0 }
        return smoothstep((-6 - solarAltitude) / 6)
    }

    private static func smoothstep(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        return x * x * (3 - 2 * x)
    }
}

// MARK: - Contrast

/// WCAG 2.1 relative luminance and contrast, plus the sweep that proves the palette
/// stays legible at every solar altitude the app can be asked for.
public enum SkyContrast {

    /// WCAG relative luminance from gamma encoded sRGB components in 0 to 1.
    public static func relativeLuminance(red: Double, green: Double, blue: Double) -> Double {
        LinearRGB(
            red: LinearRGB.linearised(red),
            green: LinearRGB.linearised(green),
            blue: LinearRGB.linearised(blue)
        ).relativeLuminance
    }

    /// WCAG contrast ratio between two relative luminances.
    public static func ratio(_ first: Double, _ second: Double) -> Double {
        let lighter = max(first, second), darker = min(first, second)
        return (lighter + 0.05) / (darker + 0.05)
    }

    public static func ratio(_ first: LinearRGB, _ second: LinearRGB) -> Double {
        ratio(first.relativeLuminance, second.relativeLuminance)
    }

    /// Every luminance the sky actually paints at this instant: the emitted stops, and
    /// the values the renderer produces between them. Blending is sampled in both
    /// linear and gamma encoded space because the two differ slightly and the guarantee
    /// has to hold whichever the renderer picks. Each sample is quantised to 8 bits
    /// first, so this measures the panel and not the ideal.
    public static func paintedLuminances(solarAltitude: Double, moonIllumination: Double) -> [Double] {
        paintedColours(solarAltitude: solarAltitude, moonIllumination: moonIllumination)
            .map { $0.relativeLuminance }
    }

    /// How finely the span between two emitted stops is sampled.
    ///
    /// This was 6, and 6 is not enough. Along a straight line in gamma encoded
    /// components, relative luminance is a sum of convex functions of an affine
    /// parameter, so it is convex: the interior of a span can sit *below* both of its
    /// endpoints. That interior dip is exactly the case a coarse sample steps over.
    /// Measured at the binding altitude of -4.01, six subdivisions reported 4.5586 to 1
    /// where the true value is 4.5500 to 1, an overstatement of 0.0086 against total
    /// headroom of 0.05. Eight subdivisions already converge to the exact value there;
    /// 32 is the margin, and costs nothing a sweep notices.
    public static let blendSubdivisions = 32

    /// Every colour the sky actually paints at this instant, already quantised to 8 bits.
    public static func paintedColours(solarAltitude: Double, moonIllumination: Double) -> [LinearRGB] {
        let stops = SkyPalette.skyColours(solarAltitude: solarAltitude, moonIllumination: moonIllumination)
        var result = stops.map { $0.quantised }
        let subdivisions = blendSubdivisions
        for index in 0..<(stops.count - 1) {
            let a = stops[index], b = stops[index + 1]
            let ea = a.encodedComponents, eb = b.encodedComponents
            for step in 1..<subdivisions {
                let t = Double(step) / Double(subdivisions)
                let linear = LinearRGB(
                    red: a.red + (b.red - a.red) * t,
                    green: a.green + (b.green - a.green) * t,
                    blue: a.blue + (b.blue - a.blue) * t
                )
                let gamma = LinearRGB(
                    red: LinearRGB.linearised(ea.red + (eb.red - ea.red) * t),
                    green: LinearRGB.linearised(ea.green + (eb.green - ea.green) * t),
                    blue: LinearRGB.linearised(ea.blue + (eb.blue - ea.blue) * t)
                )
                result.append(linear.quantised)
                result.append(gamma.quantised)
            }
        }
        return result
    }

    /// The worst contrast the foreground reaches anywhere on this sky.
    ///
    /// The ink comes from `SkyPalette.ink` rather than from a second copy of the
    /// crossover comparison, so the audit cannot drift away from what the app draws.
    public static func worstContrast(solarAltitude: Double, moonIllumination: Double = 0) -> Double {
        let ink = SkyPalette.ink(solarAltitude: solarAltitude).relativeLuminance
        return paintedLuminances(solarAltitude: solarAltitude, moonIllumination: moonIllumination)
            .reduce(Double.infinity) { min($0, ratio(ink, $1)) }
    }

    /// The worst contrast a `SkyPalette.componentBorder` stroke reaches against the sky
    /// on either side of it, swept over the whole domain. WCAG 1.4.11 wants 3 to 1.
    public static func worstComponentBorderContrast(
        step: Double = 1,
        illuminationSteps: Int = 3
    ) -> (ratio: Double, solarAltitude: Double) {
        worstOverlayContrast(
            opacity: SkyPalette.componentBorderOpacity,
            step: step,
            illuminationSteps: illuminationSteps
        )
    }

    /// The worst contrast any ink at `opacity` reaches against the sky under it.
    public static func worstOverlayContrast(
        opacity: Double,
        step: Double = 1,
        illuminationSteps: Int = 3
    ) -> (ratio: Double, solarAltitude: Double) {
        var worst = (ratio: Double.infinity, solarAltitude: 0.0)
        for altitude in sweptAltitudes(step: step, fineAroundCrossover: false) {
            for index in 0..<max(illuminationSteps, 1) {
                let illumination = illuminationSteps <= 1 ? 0 : Double(index) / Double(illuminationSteps - 1)
                let value = worstContrast(
                    inkOpacity: opacity,
                    solarAltitude: altitude,
                    moonIllumination: illumination
                )
                if value < worst.ratio { worst = (value, altitude) }
            }
        }
        return worst
    }

    /// The worst contrast a foreground at this opacity would reach on this sky.
    ///
    /// Provided as a guard rail. The floor leaves nothing spare at the ink crossover, so
    /// anything under full opacity fails there. Measured: 0.95 gives 4.40 to 1, 0.90
    /// gives 4.26, 0.75 gives 3.63, and the instrument line at 0.55 gives 2.67. Fade
    /// nothing that has to be read. Rules and other marks that carry no reading may use
    /// `SkyPalette.instrumentLine`; the boundary of a control uses
    /// `SkyPalette.componentBorder`, which is the lightest stroke that still clears the
    /// 3 to 1 that WCAG 1.4.11 asks of it.
    public static func worstContrast(
        inkOpacity: Double,
        solarAltitude: Double,
        moonIllumination: Double = 0
    ) -> Double {
        let ink = SkyPalette.ink(solarAltitude: solarAltitude)
        return paintedColours(solarAltitude: solarAltitude, moonIllumination: moonIllumination)
            .reduce(Double.infinity) { worst, sky in
                min(worst, ratio(ink.composited(over: sky, opacity: inkOpacity), sky))
            }
    }

    public struct Audit: Equatable {
        public let worstRatio: Double
        public let solarAltitude: Double
        public let moonIllumination: Double
        public let required: Double
        public var passes: Bool { worstRatio >= required }
    }

    /// The altitudes a sweep visits: the whole domain at `step`, and, for the contrast
    /// audit, a dense band either side of the ink crossover, because that is where the
    /// minimum lives and a coarse step walks straight over it.
    ///
    /// A non positive `step` would spin forever, so it is clamped rather than trusted.
    static func sweptAltitudes(step: Double, fineAroundCrossover: Bool) -> [Double] {
        let stride = step > 0 ? step : 1
        var altitudes: [Double] = []
        var altitude = -90.0
        while altitude <= 90 {
            altitudes.append(altitude)
            altitude += stride
        }
        guard fineAroundCrossover else { return altitudes }
        let crossover = SkyPalette.inkCrossoverAltitude
        var fine = crossover - 1
        while fine <= crossover + 1 {
            altitudes.append(fine)
            fine += 0.005
        }
        return altitudes
    }

    /// Sweeps solar altitude and moon illumination and returns the worst case found.
    public static func audit(required: Double = 4.5, step: Double = 0.25, illuminationSteps: Int = 5) -> Audit {
        let altitudes = sweptAltitudes(step: step, fineAroundCrossover: true)
        var worst = Audit(worstRatio: .infinity, solarAltitude: 0, moonIllumination: 0, required: required)
        for altitude in altitudes {
            for index in 0..<max(illuminationSteps, 1) {
                let illumination = illuminationSteps <= 1 ? 0 : Double(index) / Double(illuminationSteps - 1)
                let ratio = worstContrast(solarAltitude: altitude, moonIllumination: illumination)
                if ratio < worst.worstRatio {
                    worst = Audit(
                        worstRatio: ratio,
                        solarAltitude: altitude,
                        moonIllumination: illumination,
                        required: required
                    )
                }
            }
        }
        return worst
    }

    #if DEBUG
    /// Trips in debug builds if the palette ever stops clearing the floor.
    @discardableResult
    public static func assertLegible(required: Double = 4.5) -> Audit {
        let result = audit(required: required)
        assert(
            result.passes,
            "Adaptive Sky contrast floor breached: \(result.worstRatio) to 1 at solar altitude "
                + "\(result.solarAltitude) with moon illumination \(result.moonIllumination)"
        )
        return result
    }
    #endif
}

// MARK: - Applying the sky

private struct SolarAltitudeKey: EnvironmentKey {
    static let defaultValue: Double = 0
}

public extension EnvironmentValues {
    /// The solar altitude the surrounding sky was drawn for. Instrument components read
    /// it to pick their ink, so they stay legible wherever they are placed.
    var solarAltitude: Double {
        get { self[SolarAltitudeKey.self] }
        set { self[SolarAltitudeKey.self] = newValue }
    }
}

public extension View {
    /// Lays the adaptive sky behind this view, sets the matching ink, and publishes the
    /// altitude so nested instrument components agree with it.
    func adaptiveSky(solarAltitude: Double, moonIllumination: Double = 0) -> some View {
        self
            .foregroundStyle(SkyPalette.foreground(solarAltitude: solarAltitude))
            .environment(\.solarAltitude, solarAltitude)
            .background {
                SkyPalette.gradient(solarAltitude: solarAltitude, moonIllumination: moonIllumination)
                    .ignoresSafeArea()
            }
    }
}
