import SwiftUI
import WidgetKit
import SunlitCore

// MARK: - The widget

/// `systemMedium`: the day's arc, with the sun where it actually is on it.
struct DayArcWidget: Widget {

    static let kind = "com.levinschwab.sunlit.widget.dayArc"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SunlitTimelineProvider()) { entry in
            DayArcWidgetView(entry: entry)
        }
        .configurationDisplayName(Text(Self.title))
        .description(Text(Self.blurb))
        .supportedFamilies([.systemMedium])
    }

    static var title: String {
        String(localized: "widget.dayArc.title", defaultValue: "Day Arc",
               comment: "Name of the medium widget in the widget gallery")
    }

    static var blurb: String {
        String(localized: "widget.dayArc.description",
               defaultValue: "The day's arc with the sun in its real position.",
               comment: "Description of the medium widget in the widget gallery")
    }
}

// MARK: - The view

struct DayArcWidgetView: View {
    let entry: SunlitEntry

    var body: some View {
        content
            .containerBackground(for: .widget) {
                if entry.needsSetup {
                    WidgetSky.setupBackground
                } else {
                    WidgetSky.gradient(
                        solarAltitude: entry.solarAltitude,
                        moonIllumination: entry.skyMoonIllumination
                    )
                }
            }
            .widgetURL(SunlitWidgetLink.destination(for: entry))
    }

    @ViewBuilder
    private var content: some View {
        if entry.needsSetup {
            SetupPromptView()
        } else if entry.isUnlocked {
            unlocked
        } else {
            LockedSystemWidget(solarAltitude: entry.solarAltitude) {
                unlocked
            }
        }
    }

    /// A tile cannot scroll, so at the largest text sizes something has to give rather
    /// than be pushed off the canvas. The two angle readouts go first, then the arc.
    ///
    /// The place caption never goes. It used to: the smallest fit was the bottom row
    /// alone, which left a medium tile printing a sunrise and a sunset with nothing on
    /// it to say whose. A time without its place is not a smaller readout, it is a
    /// different and unanswerable one.
    private var unlocked: some View {
        ViewThatFits(in: .vertical) {
            stack(showsAngles: true, showsArc: true)
            stack(showsAngles: false, showsArc: true)
            stack(showsAngles: false, showsArc: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .foregroundStyle(WidgetSky.foreground(solarAltitude: entry.solarAltitude))
    }

    private func stack(showsAngles: Bool, showsArc: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            topRow(showsAngles: showsAngles)
            if showsArc {
                DayArcTrack(entry: entry)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            bottomRow
        }
    }

    // MARK: Rows

    private func topRow(showsAngles: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(entry.placeName)
                .widgetLabelStyle()
                .lineLimit(1)
                .truncationMode(.tail)
                .accessibilityLabel(Text(placeLabel))
                .accessibilityValue(Text(entry.placeName))

            Spacer(minLength: 4)

            if showsAngles {
                readout(
                    label: altitudeLabel,
                    value: entry.altitudeText + "\u{00B0}",
                    spoken: String(
                        localized: "widget.dayArc.accessibility.altitude",
                        defaultValue: "Sun altitude \(entry.altitudeText) degrees",
                        comment: "VoiceOver value for the sun altitude readout in the medium widget"
                    )
                )

                readout(
                    label: azimuthLabel,
                    value: entry.azimuthText + "\u{00B0}",
                    spoken: String(
                        localized: "widget.dayArc.accessibility.azimuth",
                        defaultValue: "Sun azimuth \(entry.azimuthText) degrees",
                        comment: "VoiceOver value for the sun azimuth readout in the medium widget"
                    )
                )
            }
        }
    }

    /// The two ends of the arc, or, when the sun crosses the horizon at neither end,
    /// one sentence saying so.
    ///
    /// One sentence, not two. Both ends used to print `polarExplanation`, so a polar
    /// day read "The sun stays up all day" twice across the bottom of the tile.
    @ViewBuilder
    private var bottomRow: some View {
        if entry.sunrise == nil && entry.sunset == nil {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.dayAbsenceText)
                    .font(.system(.caption, design: .default))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 4)

                nextEventInline
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                endpoint(
                    symbol: "sunrise.fill",
                    instant: entry.sunrise,
                    label: sunriseLabel,
                    absence: entry.sunriseAbsenceText,
                    accent: WidgetSky.sunAccent
                )

                Spacer(minLength: 4)

                nextEventInline

                Spacer(minLength: 4)

                endpoint(
                    symbol: "sunset.fill",
                    instant: entry.sunset,
                    label: sunsetLabel,
                    absence: entry.sunsetAbsenceText,
                    accent: WidgetSky.sunAccent
                )
            }
        }
    }

    // MARK: Pieces

    private func readout(label: String, value: String, spoken: String) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(label).widgetLabelStyle()
            Text(value).widgetFigureStyle(.callout)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(spoken))
    }

    /// One end of the arc. When that end does not happen there is no time to print, so
    /// the fact about that end is printed instead.
    ///
    /// `absence` is per end. It used to fall back to `label`, which put the bare word
    /// "Sunset" where a clock time belongs on the day a polar day begins, where the sun
    /// rises and then does not set.
    @ViewBuilder
    private func endpoint(
        symbol: String,
        instant: Date?,
        label: String,
        absence: String,
        accent: Color
    ) -> some View {
        if let instant {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .imageScale(.small)
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)
                Text(entry.timeText(instant))
                    .widgetFigureStyle(.footnote)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(label))
            .accessibilityValue(Text(entry.timeText(instant)))
        } else {
            Text(absence)
                .font(.system(.caption2, design: .default))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(label))
                .accessibilityValue(Text(absence))
        }
    }

    @ViewBuilder
    private var nextEventInline: some View {
        if let event = entry.nextEvent {
            VStack(spacing: 0) {
                Text(event.kind.localisedName)
                    .widgetLabelStyle()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(timerInterval: entry.date...event.date, countsDown: true)
                    .widgetFigureStyle(.footnote)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(event.kind.localisedName))
            .accessibilityValue(Text(
                String(
                    localized: "widget.dayArc.accessibility.next",
                    defaultValue: "at \(entry.timeText(event.date)), in \(entry.aheadText(event.date))",
                    comment: "VoiceOver value for the next event readout in the medium widget"
                )
            ))
        }
    }

    // MARK: Strings

    private var placeLabel: String {
        String(localized: "widget.label.place", defaultValue: "Place",
               comment: "Label for the place name in a widget")
    }

    private var altitudeLabel: String {
        String(localized: "widget.label.altitude", defaultValue: "Alt",
               comment: "Short label for the sun's altitude above the horizon in a widget")
    }

    private var azimuthLabel: String {
        String(localized: "widget.label.azimuth", defaultValue: "Az",
               comment: "Short label for the sun's compass bearing in a widget")
    }

    private var sunriseLabel: String {
        String(localized: "widget.label.sunrise", defaultValue: "Sunrise",
               comment: "Label for the sunrise time in a widget")
    }

    private var sunsetLabel: String {
        String(localized: "widget.label.sunset", defaultValue: "Sunset",
               comment: "Label for the sunset time in a widget")
    }
}

// MARK: - The arc

/// Half a sine across the width, which is what a solar path projects to on a flat
/// panel, with the horizon as its baseline.
///
/// Hidden from VoiceOver on purpose: it restates the figures printed beside it, and a
/// spoken fraction of an arc tells a reader nothing the readouts have not already
/// said precisely.
private struct DayArcTrack: View {
    @Environment(\.displayScale) private var displayScale

    let entry: SunlitEntry

    private var markerDiameter: CGFloat { 11 }

    var body: some View {
        GeometryReader { proxy in
            let inset = markerDiameter / 2 + 1
            let rect = CGRect(
                x: inset,
                y: inset,
                width: max(proxy.size.width - inset * 2, 1),
                height: max(proxy.size.height - inset * 2, 1)
            )
            let hairline = 1 / displayScale
            let line = WidgetSky.instrumentLine(solarAltitude: entry.solarAltitude)
            let ink = WidgetSky.foreground(solarAltitude: entry.solarAltitude)
            let progress = entry.arcProgress

            ZStack(alignment: .topLeading) {
                Path { path in
                    path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
                    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                }
                .stroke(line, lineWidth: hairline)

                // No arc where there is no sunrise and sunset to draw one between. A
                // half sine from horizon to horizon asserts a crossing at each end, and
                // inside the polar circles there is none, so drawing it would be the
                // picture making a claim the figures do not.
                if let progress {
                    WidgetArc.path(in: rect, from: 0, to: 1)
                        .stroke(line, lineWidth: hairline)

                    if entry.sunIsUp {
                        // The accent is a hue signal, not a luminance one: measured
                        // against the sky it crosses, the sun accent bottoms out at
                        // 1.00 to 1, so in greyscale the stroke simply is not there.
                        // The ink underlay is what makes it a mark rather than a hue.
                        WidgetArc.path(in: rect, from: 0, to: progress)
                            .stroke(ink, style: StrokeStyle(lineWidth: hairline * 4, lineCap: .round))

                        WidgetArc.path(in: rect, from: 0, to: progress)
                            .stroke(
                                WidgetSky.sunAccent,
                                style: StrokeStyle(lineWidth: hairline * 2, lineCap: .round)
                            )

                        Circle()
                            .fill(WidgetSky.sunAccent)
                            .overlay {
                                Circle().strokeBorder(ink, lineWidth: hairline)
                            }
                            .frame(width: markerDiameter, height: markerDiameter)
                            .position(WidgetArc.point(at: progress, in: rect))
                    }
                }
            }
        }
        // Low enough that the arc is what `ViewThatFits` can squeeze rather than what
        // forces a row off the tile, and still tall enough to read as an arc.
        .frame(minHeight: 24)
        .accessibilityHidden(true)
    }
}
