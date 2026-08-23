import SwiftUI
import SunlitCore

/// The day's arc: the sun's altitude through the whole selected day, with both bodies
/// drawn at their true positions for the selected instant.
///
/// The horizontal axis is time, from local midnight to local midnight, which is the same
/// axis `TimeScrubber` sits on directly beneath it, so the handle is always under the sun.
/// The vertical axis is altitude in degrees, which makes three of the four marks free:
/// the horizon is the zero rule, the golden band is the altitude band between -4 and +6,
/// and a body below the plotted floor is simply below the frame. An azimuth axis would
/// read as a compass but wraps at high latitude and would put the moon on a different
/// scale from the sun.
///
/// Nothing here computes anything astronomical. The arc is `DayReport.samples`, the two
/// glyph positions are `SkyMoment.sun` and `SkyMoment.moon`, and the band edges are the
/// constants the event solver itself uses.
///
/// The drawing is hidden from VoiceOver, for the reason `ArcTrack` gives: it restates
/// `MetricBlock` and `EventRail`, which carry every figure on it precisely, and a spoken
/// description of a curve tells a reader nothing those two have not already said.
struct DayArc: View {

    @Environment(\.solarAltitude) private var solarAltitude
    @Environment(\.displayScale) private var displayScale

    /// The drawing grows with the type size, but only so far: past this it is a picture
    /// pushing the readouts off the first screen rather than a bigger picture.
    @ScaledMetric(relativeTo: .body) private var preferredHeight: CGFloat = 216
    @ScaledMetric(relativeTo: .body) private var sunDiameter: CGFloat = 18
    @ScaledMetric(relativeTo: .body) private var moonDiameter: CGFloat = 20

    /// Nil until the day has been computed, which takes about thirty milliseconds and
    /// happens off the main thread. The frame, the horizon and the golden band are drawn
    /// meanwhile, so the screen has its shape from the first frame.
    let report: DayReport?
    let moment: SkyMoment
    /// Where the selected instant sits in the plotted day, 0 to 1.
    let fraction: Double
    /// True when the moon layer is unlocked. When false the same geometry is still
    /// drawn, in the disabled ink, because a feature that vanishes makes the free app
    /// look broken rather than free.
    let showsMoon: Bool

    private var height: CGFloat { min(max(preferredHeight, 180), 340) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { proxy in
                let plot = Plot(
                    size: proxy.size,
                    inset: max(sunDiameter, moonDiameter) / 2 + 2,
                    floor: Self.plottedFloor,
                    ceiling: ceiling)

                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in
                        draw(in: &context, plot: plot)
                    }

                    noonLabel(plot: plot)
                    moonGlyph(plot: plot)
                    sunGlyph(plot: plot)
                }
            }
            .frame(height: height)
            .accessibilityHidden(true)

            legend
        }
    }

    // MARK: The plotted domain

    /// The bottom of the frame. The end of astronomical twilight, which is where night
    /// begins and below which the exact depth of the sun stops carrying information.
    private static let plottedFloor = -18.0

    /// The top of the frame. High enough for the sun's own maximum and for the moon,
    /// which in winter stands far higher than the sun does.
    private var ceiling: Double {
        guard let report else { return 20 }
        var highest = report.maximumSolarAltitude
        for sample in report.samples {
            highest = max(highest, sample.moon.altitude)
        }
        return min(90, max(highest + 6, 20))
    }

    // MARK: Drawing

    private func draw(in context: inout GraphicsContext, plot: Plot) {
        let hairline = 1 / displayScale
        let line = SkyPalette.instrumentLine(solarAltitude: solarAltitude)
        let ink = SkyPalette.foreground(solarAltitude: solarAltitude)

        context.clip(to: Path(plot.rect))

        drawGoldenBand(in: &context, plot: plot, hairline: hairline, line: line)
        drawHorizon(in: &context, plot: plot, hairline: hairline, ink: ink)
        drawNoonTick(in: &context, plot: plot, hairline: hairline, line: line)

        guard let report else { return }
        drawMoonPath(report, in: &context, plot: plot, hairline: hairline, ink: ink)
        drawSunPath(report, in: &context, plot: plot, hairline: hairline, line: line, ink: ink)
    }

    private func drawGoldenBand(
        in context: inout GraphicsContext,
        plot: Plot,
        hairline: CGFloat,
        line: Color
    ) {
        let top = plot.clampedY(GoldenHour.goldenUpperAltitude)
        let bottom = plot.clampedY(GoldenHour.goldenLowerAltitude)
        guard bottom > top else { return }
        let band = CGRect(x: plot.rect.minX, y: top, width: plot.rect.width, height: bottom - top)
        // A gradient rather than a flat wash. Eighteen percent of #FFB020 laid over the
        // twilight violet the gradient shows at this hour mixes to a flat brown, which
        // reads as a bar drawn across the picture rather than as light lying in it. Fading
        // to almost nothing at both edges makes it a band of light again, and it costs no
        // legibility: the two hairlines still carry the shape, so it is still a band in
        // greyscale, where the accent can match the sky it lies on exactly.
        context.fill(
            Path(band),
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: SkyColors.sun.opacity(0.04), location: 0),
                    .init(color: SkyColors.sun.opacity(0.24), location: 0.5),
                    .init(color: SkyColors.sun.opacity(0.04), location: 1),
                ]),
                startPoint: CGPoint(x: band.midX, y: band.minY),
                endPoint: CGPoint(x: band.midX, y: band.maxY)))
        context.stroke(Self.rule(y: top, in: plot), with: .color(line), lineWidth: hairline)
        context.stroke(Self.rule(y: bottom, in: plot), with: .color(line), lineWidth: hairline)
    }

    private func drawHorizon(
        in context: inout GraphicsContext,
        plot: Plot,
        hairline: CGFloat,
        ink: Color
    ) {
        // Full ink rather than the instrument line: this is the datum the whole drawing
        // is read against, and it stays one physical pixel to earn that without weight.
        context.stroke(Self.rule(y: plot.clampedY(0), in: plot), with: .color(ink), lineWidth: hairline)
    }

    private func drawNoonTick(
        in context: inout GraphicsContext,
        plot: Plot,
        hairline: CGFloat,
        line: Color
    ) {
        guard let noon = noonFraction else { return }
        var tick = Path()
        tick.move(to: CGPoint(x: plot.x(noon), y: plot.rect.minY))
        tick.addLine(to: CGPoint(x: plot.x(noon), y: plot.clampedY(0)))
        context.stroke(tick, with: .color(line), style: StrokeStyle(lineWidth: hairline, dash: [3, 3]))
    }

    private func drawMoonPath(
        _ report: DayReport,
        in context: inout GraphicsContext,
        plot: Plot,
        hairline: CGFloat,
        ink: Color
    ) {
        let path = Self.path(report, plot: plot, upTo: 1) { $0.moon.altitude }
        guard !path.isEmpty else { return }
        let dashed = StrokeStyle(lineWidth: hairline * 1.5, dash: [7, 5])
        if showsMoon {
            context.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: hairline * 3.5, dash: [7, 5]))
            context.stroke(path, with: .color(SkyColors.moon), style: dashed)
        } else {
            context.stroke(
                path,
                with: .color(SkyColors.disabled(solarAltitude: solarAltitude)),
                style: dashed)
        }
    }

    private func drawSunPath(
        _ report: DayReport,
        in context: inout GraphicsContext,
        plot: Plot,
        hairline: CGFloat,
        line: Color,
        ink: Color
    ) {
        let whole = Self.path(report, plot: plot, upTo: 1) { $0.sun.altitude }
        guard !whole.isEmpty else { return }
        context.stroke(whole, with: .color(line), lineWidth: hairline)

        var travelled = Self.path(report, plot: plot, upTo: fraction) { $0.sun.altitude }
        let head = plot.point(fraction, moment.sun.altitude)
        if travelled.isEmpty {
            travelled.move(to: head)
            travelled.addLine(to: head)
        } else {
            travelled.addLine(to: head)
        }
        // The ink underlay is what makes the travelled arc a mark rather than a hue:
        // measured against the sky it crosses, the sun accent bottoms out at 1.00 to 1.
        context.stroke(travelled, with: .color(ink), style: StrokeStyle(lineWidth: hairline * 4, lineCap: .round))
        context.stroke(travelled, with: .color(SkyColors.sun), style: StrokeStyle(lineWidth: hairline * 2, lineCap: .round))
    }

    private static func rule(y: CGFloat, in plot: Plot) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: plot.rect.minX, y: y))
        path.addLine(to: CGPoint(x: plot.rect.maxX, y: y))
        return path
    }

    /// The sampled track as a polyline. Sampled by time, exactly as `DayReport` stored it,
    /// so the head of a partial stroke lands where the glyph is put rather than drifting
    /// the way a trimmed curve does.
    private static func path(
        _ report: DayReport,
        plot: Plot,
        upTo limit: Double,
        altitude: (DayReport.Sample) -> Double
    ) -> Path {
        var path = Path()
        var started = false
        for sample in report.samples {
            let fraction = sample.instant.value - report.date.value
            guard fraction <= limit + 1e-9 else { break }
            let point = plot.point(fraction, altitude(sample))
            if started {
                path.addLine(to: point)
            } else {
                path.move(to: point)
                started = true
            }
        }
        return path
    }

    private var noonFraction: Double? {
        guard let report, let noon = report.phases.solarNoon else { return nil }
        let fraction = noon.value - report.date.value
        guard fraction >= 0, fraction <= 1 else { return nil }
        return fraction
    }

    // MARK: Glyphs and labels

    private func sunGlyph(plot: Plot) -> some View {
        let below = moment.sun.altitude < plot.floor
        return Group {
            if below {
                Circle()
                    .strokeBorder(
                        SkyPalette.foreground(solarAltitude: solarAltitude),
                        lineWidth: 1 / displayScale)
                    .frame(width: sunDiameter * 0.7, height: sunDiameter * 0.7)
            } else {
                Circle()
                    .fill(SkyColors.sun)
                    .overlay {
                        Circle().strokeBorder(
                            SkyPalette.foreground(solarAltitude: solarAltitude),
                            lineWidth: 1 / displayScale)
                    }
                    .frame(width: sunDiameter, height: sunDiameter)
            }
        }
        .position(x: plot.x(fraction), y: plot.clampedY(moment.sun.altitude))
    }

    private func moonGlyph(plot: Plot) -> some View {
        let below = moment.moon.altitude < plot.floor
        let ink = SkyPalette.foreground(solarAltitude: solarAltitude)
        let disabled = SkyColors.disabled(solarAltitude: solarAltitude)
        return SkyMoonDisc(
            illuminatedFraction: moment.moonPhase.illuminatedFraction,
            brightLimbAngle: moment.moonPhase.brightLimbAngle,
            lit: showsMoon ? SkyColors.moon : disabled,
            outline: showsMoon ? ink : disabled)
            .frame(
                width: below ? moonDiameter * 0.7 : moonDiameter,
                height: below ? moonDiameter * 0.7 : moonDiameter)
            .opacity(below ? 0.6 : 1)
            .position(x: plot.x(fraction), y: plot.clampedY(moment.moon.altitude))
    }

    private func noonLabel(plot: Plot) -> some View {
        Group {
            if let noon = noonFraction {
                // Held clear of both edges. The dashed tick marks the instant exactly;
                // the word only has to be readable, and at a longitude far from the
                // centre of its own time zone solar noon can fall near midnight local.
                Text(SkyStrings.noon)
                    .sunlitLabel()
                    .fixedSize()
                    .position(
                        x: min(max(plot.x(noon), plot.rect.minX + 24), plot.rect.maxX - 24),
                        y: plot.rect.minY - 2)
            }
        }
    }

    // MARK: Legend
    //
    // The three accents are hue signals and nothing else: each of them matches the sky it
    // lies on exactly somewhere in the palette's range. Naming them in foreground ink is
    // what makes the drawing readable in greyscale, under Color Filters, and to anyone
    // reading it by brightness.

    private var legend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                legendItems
            }
            VStack(alignment: .leading, spacing: 6) {
                legendItems
            }
        }
        .font(SunlitType.caption)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var legendItems: some View {
        legendItem(colour: SkyColors.sun, title: SkyStrings.legendSun, locked: false)
        legendItem(
            colour: showsMoon ? SkyColors.moon : SkyColors.disabled(solarAltitude: solarAltitude),
            title: SkyStrings.legendMoon,
            locked: !showsMoon)
        legendItem(colour: SkyColors.sun.opacity(0.18), title: SkyStrings.legendGolden, locked: false)
    }

    private func legendItem(colour: Color, title: String, locked: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(colour)
                .overlay {
                    Circle().strokeBorder(
                        SkyPalette.instrumentLine(solarAltitude: solarAltitude),
                        lineWidth: 1 / displayScale)
                }
                .frame(width: 10, height: 10)
            if locked {
                Image(systemName: "lock.fill").imageScale(.small)
            }
            Text(title).sunlitLabel()
        }
    }

    // MARK: Geometry

    /// Time to x, altitude in degrees to y. The only arithmetic in this file.
    fileprivate struct Plot {
        let rect: CGRect
        let floor: Double
        let ceiling: Double

        init(size: CGSize, inset: CGFloat, floor: Double, ceiling: Double) {
            self.rect = CGRect(
                x: inset,
                y: inset,
                width: max(size.width - inset * 2, 1),
                height: max(size.height - inset * 2, 1))
            self.floor = floor
            self.ceiling = max(ceiling, floor + 1)
        }

        func x(_ fraction: Double) -> CGFloat {
            rect.minX + rect.width * CGFloat(min(max(fraction, 0), 1))
        }

        func y(_ altitude: Double) -> CGFloat {
            let t = (altitude - floor) / (ceiling - floor)
            return rect.maxY - rect.height * CGFloat(t)
        }

        /// The same, held inside the frame, for a glyph whose body has left the plotted
        /// range. The glyph changes shape there rather than being drawn at a false height.
        func clampedY(_ altitude: Double) -> CGFloat {
            min(max(y(altitude), rect.minY), rect.maxY)
        }

        func point(_ fraction: Double, _ altitude: Double) -> CGPoint {
            CGPoint(x: x(fraction), y: y(altitude))
        }
    }
}

// MARK: - The moon, drawn

/// The moon at its real phase: a disc, and a terminator that is the half ellipse the
/// terminator actually projects to, turned to the bright limb angle the ephemeris gives.
///
/// Not a glyph and not an emoji. A waxing crescent lying the wrong way round is the
/// detail this audience checks first, and the orientation is data, not decoration:
/// `brightLimbAngle` is the position angle of the bright limb's midpoint, measured from
/// the disc's north point through east. North is up here and east is to the left, which
/// is the sky's own orientation seen from inside it.
///
/// The construction: with the bright limb at local +x, the lit region is bounded by the
/// +x semicircle and by a half ellipse of semi axes `radius * (1 - 2k)` and `radius`,
/// where k is the illuminated fraction. At k = 0.5 that ellipse collapses to the straight
/// terminator of a quarter moon, at k = 1 it bulges out to the full disc, and at k = 0 it
/// falls back onto the semicircle and nothing is lit.
struct SkyMoonDisc: View {

    @Environment(\.displayScale) private var displayScale

    let illuminatedFraction: Double
    /// Degrees, from the disc's north point through east.
    let brightLimbAngle: Double
    let lit: Color
    let outline: Color

    var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2 - 1
            guard radius > 0 else { return }
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            context.fill(litPath(centre: centre, radius: radius), with: .color(lit))
            // The full disc is always outlined, so a new moon is still a moon and not a
            // hole in the drawing.
            let disc = Path(ellipseIn: CGRect(
                x: centre.x - radius,
                y: centre.y - radius,
                width: radius * 2,
                height: radius * 2))
            context.stroke(disc, with: .color(outline), lineWidth: max(1 / displayScale, 0.5))
        }
        .accessibilityHidden(true)
    }

    private func litPath(centre: CGPoint, radius: CGFloat) -> Path {
        let k = min(max(illuminatedFraction, 0), 1)
        let terminator = radius * CGFloat(1 - 2 * k)
        let chi = brightLimbAngle * .pi / 180
        // Up is north; a position angle measured through east turns anticlockwise on
        // screen, because east lies to the left when north is up on the sky.
        let ux = CGFloat(-sin(chi))
        let uy = CGFloat(-cos(chi))

        func place(_ localX: CGFloat, _ localY: CGFloat) -> CGPoint {
            CGPoint(
                x: centre.x + localX * ux - localY * uy,
                y: centre.y + localX * uy + localY * ux)
        }

        let steps = 48
        var path = Path()
        for step in 0...steps {
            let theta = -Double.pi / 2 + Double.pi * Double(step) / Double(steps)
            let point = place(radius * CGFloat(cos(theta)), radius * CGFloat(sin(theta)))
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        for step in stride(from: steps, through: 0, by: -1) {
            let theta = -Double.pi / 2 + Double.pi * Double(step) / Double(steps)
            path.addLine(to: place(terminator * CGFloat(cos(theta)), radius * CGFloat(sin(theta))))
        }
        path.closeSubpath()
        return path
    }
}
