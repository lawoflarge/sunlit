import Foundation
import SwiftUI

// MARK: - Shared rules

public enum SunlitLayout {
    /// The HIG minimum. Deliberately not a `ScaledMetric`: 44 points is 44 points at
    /// every text size, because it describes a fingertip and not a glyph.
    public static let minimumTouchTarget: CGFloat = 44
}

public extension View {
    /// Guarantees a 44 by 44 point hit area.
    ///
    /// Apply it outermost, after any `scaleEffect`, because the rule is about the area a
    /// finger can actually land on and a scale applied afterwards shrinks it again.
    func sunlitTouchTarget(minimum: CGFloat = SunlitLayout.minimumTouchTarget) -> some View {
        frame(minWidth: minimum, minHeight: minimum)
            .contentShape(Rectangle())
    }
}

public extension HorizontalAlignment {
    /// Aligns a column of readouts on the left edge of their values, so the figures form
    /// a single line down the screen and the labels range right against them.
    /// `MetricGroup` sets it up.
    static let metricValue = HorizontalAlignment(MetricValueAlignment.self)

    private enum MetricValueAlignment: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat { context[.leading] }
    }
}

// MARK: - Metric readout

/// A label, a value, and a unit. Stacked inside a `MetricGroup` the values line up.
///
/// At the accessibility text sizes the horizontal form stops fitting and it folds to two
/// lines rather than truncating the figure, which is the number the reader came for.
public struct MetricReadout: View {
    @Environment(\.solarAltitude) private var solarAltitude
    @ScaledMetric(relativeTo: .body) private var gap: CGFloat = 8

    private let label: String
    private let value: String
    private let unit: String?
    private let valueFont: Font

    public init(label: String, value: String, unit: String? = nil, valueFont: Font = SunlitType.metric) {
        self.label = label
        self.value = value
        self.unit = unit
        self.valueFont = valueFont
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: gap) {
                Text(label).sunlitLabel()
                figure
            }
            VStack(alignment: .metricValue, spacing: 2) {
                Text(label).sunlitLabel()
                figure
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(spokenValue))
    }

    private var figure: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(valueFont)
                .alignmentGuide(.metricValue) { $0[.leading] }
            if let unit {
                Text(unit).font(SunlitType.caption)
            }
        }
    }

    private var spokenValue: String {
        guard let unit else { return value }
        return value + " " + unit
    }
}

/// The container that makes `MetricReadout` alignment do anything.
public struct MetricGroup<Content: View>: View {
    @ScaledMetric(relativeTo: .body) private var rowSpacing: CGFloat = 10
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .metricValue, spacing: rowSpacing) {
            content
        }
    }
}

// MARK: - Hairline

/// One physical pixel, at the instrument line weight. Not one point: on a 3x screen a
/// one point rule is three pixels and reads as a bar.
public struct HairlineDivider: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.solarAltitude) private var solarAltitude

    public init() {}

    public var body: some View {
        Rectangle()
            .fill(SkyPalette.instrumentLine(solarAltitude: solarAltitude))
            .frame(height: 1 / displayScale)
            .accessibilityHidden(true)
    }
}

// MARK: - Event chip

/// An icon, the time of an event, and how far away it is.
///
/// The countdown is a live system relative style, so it keeps itself current and reads
/// correctly in every locale without any date arithmetic here.
public struct EventChip: View {
    @Environment(\.solarAltitude) private var solarAltitude
    @Environment(\.displayScale) private var displayScale
    @ScaledMetric(relativeTo: .footnote) private var horizontalPadding: CGFloat = 12
    @ScaledMetric(relativeTo: .footnote) private var verticalPadding: CGFloat = 7
    @ScaledMetric(relativeTo: .footnote) private var gap: CGFloat = 8

    private let systemImage: String
    private let label: String
    private let date: Date
    private let tint: Color

    public init(systemImage: String, label: String, date: Date, tint: Color = SkyColors.sun) {
        self.systemImage = systemImage
        self.label = label
        self.date = date
        self.tint = tint
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: gap) {
                icon
                stacked
                countdown
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: gap) {
                    icon
                    stacked
                }
                countdown
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(
                    SkyPalette.componentBorder(solarAltitude: solarAltitude),
                    lineWidth: 1 / displayScale
                )
        }
        .sunlitTouchTarget()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(spokenValue))
    }

    private var icon: some View {
        Image(systemName: systemImage)
            .imageScale(.medium)
            .foregroundStyle(tint)
            .accessibilityHidden(true)
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).sunlitLabel()
            Text(date, style: .time).font(SunlitType.metricSmall).fontWeight(.semibold)
        }
    }

    private var countdown: some View {
        Text(date, style: .relative)
            .font(SunlitType.metricSmall)
    }

    private var spokenValue: String {
        date.formatted(date: .omitted, time: .shortened)
            + ", "
            + date.formatted(.relative(presentation: .named))
    }
}

// MARK: - Accuracy chip

/// The heading uncertainty, always on screen in the AR view.
///
/// Stating the uncertainty is the feature, so this never hides. In the poor state it
/// fills with amber and carries its own dark ink, which is the one element in the system
/// that ignores the sky: at 8.9 to 1 against its own fill it survives every altitude,
/// and a warning the sky can wash out is not a warning.
public struct AccuracyChip: View {
    @Environment(\.solarAltitude) private var solarAltitude
    @Environment(\.displayScale) private var displayScale
    @ScaledMetric(relativeTo: .footnote) private var horizontalPadding: CGFloat = 12
    @ScaledMetric(relativeTo: .footnote) private var verticalPadding: CGFloat = 7

    private let degrees: Double
    private let poorAbove: Double

    public init(degrees: Double, poorAbove: Double = 5) {
        self.degrees = degrees
        self.poorAbove = poorAbove
    }

    private var isPoor: Bool { degrees > poorAbove }

    private var figure: String {
        degrees.formatted(.number.precision(.fractionLength(0)))
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isPoor ? "exclamationmark.triangle.fill" : "location.north.line.fill")
                .imageScale(.small)
                .accessibilityHidden(true)
            // Symbols and a locale formatted number, so there is nothing here to translate.
            Text(verbatim: "±\(figure)°")
                .font(SunlitType.metricSmall)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background {
            if isPoor {
                Capsule(style: .continuous).fill(SkyColors.warning)
            }
        }
        .overlay {
            if !isPoor {
                Capsule(style: .continuous)
                    .strokeBorder(
                        SkyPalette.componentBorder(solarAltitude: solarAltitude),
                        lineWidth: 1 / displayScale
                    )
            }
        }
        .foregroundStyle(isPoor ? SkyColors.onWarning : SkyPalette.foreground(solarAltitude: solarAltitude))
        .sunlitTouchTarget()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spokenLabel))
    }

    private var spokenLabel: String {
        // The number and its unit are formatted together by Foundation, which is
        // what makes "1 degree" come out singular and "12 degrees" plural, here
        // and in every other language. Written into the sentence as the bare
        // word degrees it read "plus or minus 1 degrees".
        let amount = Measurement(value: degrees, unit: UnitAngle.degrees)
            .formatted(.measurement(
                width: .wide,
                numberFormatStyle: .number.precision(.fractionLength(0))))
        let uncertainty = String(
            localized: "accuracy.uncertainty",
            defaultValue: "Heading accuracy, plus or minus \(amount)",
            comment: "Spoken form of the heading accuracy chip in the AR view. The placeholder is an angle with its unit already in it, such as 3 degrees"
        )
        guard isPoor else { return uncertainty }
        let calibrate = String(
            localized: "accuracy.calibrate",
            defaultValue: "Calibration needed",
            comment: "Spoken when the heading uncertainty is too large to trust"
        )
        return uncertainty + ". " + calibrate
    }
}

// MARK: - Arc track

/// The day's arc. Half a sine across the width, which is what a solar path projects to
/// on a flat panel, with the horizon as its baseline.
public struct ArcTrackShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        Self.path(in: rect, from: 0, to: 1)
    }

    /// The arc is sampled by parameter rather than trimmed by arc length, so the end of a
    /// partial stroke lands exactly where `point(at:in:)` puts the marker. Trimming would
    /// drift, because equal steps along the curve are not equal steps in time.
    public static func path(in rect: CGRect, from start: Double, to end: Double) -> Path {
        var path = Path()
        let lower = min(max(start, 0), 1)
        let upper = min(max(end, 0), 1)
        guard upper > lower else { return path }
        let steps = 96
        for step in 0...steps {
            let t = lower + (upper - lower) * Double(step) / Double(steps)
            let point = self.point(at: t, in: rect)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }

    public static func point(at fraction: Double, in rect: CGRect) -> CGPoint {
        let t = min(max(fraction, 0), 1)
        return CGPoint(
            x: rect.minX + rect.width * t,
            y: rect.maxY - rect.height * sin(.pi * t)
        )
    }
}

/// The day's arc with a marker at a fraction of the day.
///
/// Hidden from VoiceOver on purpose: it restates the figures and the event rail beside
/// it, and a spoken percentage of an arc tells a reader nothing the readouts have not
/// already said precisely.
public struct ArcTrack: View {
    @Environment(\.solarAltitude) private var solarAltitude
    @Environment(\.displayScale) private var displayScale
    @ScaledMetric(relativeTo: .body) private var markerDiameter: CGFloat = 12

    private let progress: Double
    private let tint: Color

    public init(progress: Double, tint: Color = SkyColors.sun) {
        self.progress = progress
        self.tint = tint
    }

    public var body: some View {
        GeometryReader { proxy in
            let inset = markerDiameter / 2 + 1
            let rect = CGRect(
                x: inset,
                y: inset,
                width: max(proxy.size.width - inset * 2, 1),
                height: max(proxy.size.height - inset * 2, 1)
            )
            let hairline = 1 / displayScale
            let line = SkyPalette.instrumentLine(solarAltitude: solarAltitude)
            let fraction = min(max(progress, 0), 1)

            ZStack(alignment: .topLeading) {
                Path { path in
                    path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
                    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                }
                .stroke(line, lineWidth: hairline)

                ArcTrackShape().path(in: rect)
                    .stroke(line, lineWidth: hairline)

                // The accent is a hue signal, not a luminance one. Measured against the
                // sky it crosses, #FFB020 bottoms out at 1.00 to 1: from about four
                // degrees of solar altitude upward the travelled arc and the sky behind
                // it are the same brightness, so in greyscale, under Color Filters, or
                // to a reader who works from luminance, the stroke is simply not there.
                // The ink underlay is what makes it a mark rather than a hue. It is
                // drawn first and wider, so the accent keeps its colour and gains an
                // edge that the audited foreground guarantees at 4.55 to 1.
                ArcTrackShape.path(in: rect, from: 0, to: fraction)
                    .stroke(
                        SkyPalette.foreground(solarAltitude: solarAltitude),
                        style: StrokeStyle(lineWidth: hairline * 4, lineCap: .round)
                    )

                ArcTrackShape.path(in: rect, from: 0, to: fraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: hairline * 2, lineCap: .round))

                Circle()
                    .fill(tint)
                    .overlay {
                        Circle().strokeBorder(
                            SkyPalette.foreground(solarAltitude: solarAltitude),
                            lineWidth: hairline
                        )
                    }
                    .frame(width: markerDiameter, height: markerDiameter)
                    .position(ArcTrackShape.point(at: fraction, in: rect))
            }
        }
        .frame(minHeight: 44)
        .accessibilityHidden(true)
    }
}
