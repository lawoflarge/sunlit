import SwiftUI
import SunlitCore

/// The control that moves the whole screen through the day.
///
/// It shares its horizontal axis with `DayArc` above it, so the handle sits under the sun
/// at all times, and dragging it drags the sun along its own path. The gradient follows
/// too, because the gradient is a readout of solar altitude and not a backdrop.
///
/// Dragging recomputes one `SkyMoment` per frame, never a `DayReport`. A day report is
/// several thousand ephemeris evaluations and would turn a drag into a slideshow; a
/// moment is one, and the whole screen is built from it.
struct TimeScrubber: View {

    @Environment(\.solarAltitude) private var solarAltitude
    @Environment(\.displayScale) private var displayScale

    @ScaledMetric(relativeTo: .body) private var handleDiameter: CGFloat = 26

    /// Where the selected instant sits in the plotted day, 0 to 1.
    @Binding var fraction: Double
    /// Local midnight of the plotted day.
    let dayStart: Date
    /// The place's own zone, so a user in Berlin reading Tokyo sees Tokyo's clock.
    let timeZone: TimeZone
    /// Ticks along the track. Sunrise, solar noon and sunset.
    let marks: [Mark]
    /// True while the app is following the real clock.
    let isLive: Bool
    let onReturnToNow: () -> Void

    struct Mark: Identifiable {
        let id: String
        let fraction: Double
    }

    /// One step of the VoiceOver adjustable action. Fifteen minutes is coarse enough to
    /// cross a day in a reasonable number of gestures and fine enough to land inside any
    /// golden hour.
    private static let stepSeconds: Double = 15 * 60

    private var instant: Date {
        dayStart.addingTimeInterval(min(max(fraction, 0), 1) * 86400)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            track
        }
    }

    // MARK: The figure and the live control

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                timeFigure
                Spacer(minLength: 12)
                liveControl
            }
            VStack(alignment: .leading, spacing: 8) {
                timeFigure
                liveControl
            }
        }
    }

    private var timeFigure: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(SkyStrings.scrubberLabel).sunlitLabel()
            Text(SkyFormat.time(instant, in: timeZone))
                .font(SunlitType.metricLarge)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(SkyStrings.scrubberLabel))
        .accessibilityValue(Text(SkyFormat.time(instant, in: timeZone)))
    }

    @ViewBuilder
    private var liveControl: some View {
        if isLive {
            // Nothing to return to. Saying "live" where the button would be keeps the row
            // from reflowing the moment a drag begins.
            HStack(spacing: 6) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .imageScale(.small)
                    .accessibilityHidden(true)
                Text(SkyStrings.live).sunlitLabel()
            }
            .frame(minHeight: SunlitLayout.minimumTouchTarget)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(SkyStrings.liveSpoken))
        } else {
            Button(action: onReturnToNow) {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .imageScale(.small)
                    Text(SkyStrings.now).sunlitLabel()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            SkyPalette.componentBorder(solarAltitude: solarAltitude),
                            lineWidth: 1 / displayScale)
                }
                .sunlitTouchTarget()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(SkyStrings.nowSpoken))
        }
    }

    // MARK: The track

    private var track: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let midY = proxy.size.height / 2
            let hairline = 1 / displayScale
            let line = SkyPalette.instrumentLine(solarAltitude: solarAltitude)
            let ink = SkyPalette.foreground(solarAltitude: solarAltitude)
            let position = width * CGFloat(min(max(fraction, 0), 1))

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(line)
                    .frame(height: hairline)
                    .position(x: width / 2, y: midY)

                ForEach(marks) { mark in
                    Rectangle()
                        .fill(line)
                        .frame(width: hairline, height: 12)
                        .position(x: width * CGFloat(min(max(mark.fraction, 0), 1)), y: midY - 8)
                }

                // Travelled portion, under an ink underlay for the same reason the arc
                // carries one: the accent alone is a hue and can match the sky exactly.
                Rectangle()
                    .fill(ink)
                    .frame(width: max(position, hairline), height: hairline * 3)
                    .position(x: max(position, hairline) / 2, y: midY)

                Circle()
                    .fill(SkyColors.sun)
                    .overlay {
                        Circle().strokeBorder(ink, lineWidth: hairline * 2)
                    }
                    .frame(width: handleDiameter, height: handleDiameter)
                    .position(x: position, y: midY)
            }
            .contentShape(Rectangle())
            .gesture(
                // Zero minimum distance so a tap seeks as well as a drag. A slider inside
                // a scroll view claims the gesture it starts, which is what a finger on a
                // slider expects.
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        fraction = min(max(Double(value.location.x / width), 0), 1)
                    }
            )
        }
        .frame(height: max(SunlitLayout.minimumTouchTarget, handleDiameter + 8))
        .accessibilityElement()
        .accessibilityLabel(Text(SkyStrings.scrubberLabel))
        .accessibilityValue(Text(SkyFormat.time(instant, in: timeZone)))
        .accessibilityHint(Text(SkyStrings.scrubberHint))
        .accessibilityAdjustableAction { direction in
            let step = Self.stepSeconds / 86400
            switch direction {
            case .increment: fraction = min(fraction + step, 1)
            case .decrement: fraction = max(fraction - step, 0)
            @unknown default: break
            }
        }
    }
}
