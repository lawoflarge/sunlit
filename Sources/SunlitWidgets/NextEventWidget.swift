import SwiftUI
import WidgetKit
import SunlitCore

// MARK: - The widget

/// `systemSmall`: the next sun event and its countdown.
///
/// The one number this widget exists for is a duration, so the duration is set in the
/// display size and everything else ranges around it.
struct NextEventWidget: Widget {

    static let kind = "com.levinschwab.sunlit.widget.nextEvent"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SunlitTimelineProvider()) { entry in
            NextEventWidgetView(entry: entry)
        }
        .configurationDisplayName(Text(Self.title))
        .description(Text(Self.blurb))
        .supportedFamilies([.systemSmall])
    }

    static var title: String {
        String(localized: "widget.nextEvent.title", defaultValue: "Next Event",
               comment: "Name of the small widget in the widget gallery")
    }

    static var blurb: String {
        String(localized: "widget.nextEvent.description",
               defaultValue: "The next sun event at your place, counting down.",
               comment: "Description of the small widget in the widget gallery")
    }
}

// MARK: - The view

struct NextEventWidgetView: View {
    let entry: SunlitEntry

    var body: some View {
        content
            .containerBackground(for: .widget) {
                if entry.needsSetup {
                    // No place, so no sky to report. A flat panel instead.
                    WidgetSky.setupBackground
                } else {
                    // The background is the readout. This is the colour the sky over
                    // that place actually is at this instant, interpolated from the
                    // solar altitude the core computed, so a glance at the tile already
                    // says whether it is night, twilight, golden, or full day.
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

    /// A tile cannot scroll, so the rule that no primary content may be pushed off the
    /// canvas at the largest text size has to be met by giving way instead. The place
    /// name goes first, then the breathing room. The event name, its time and its
    /// countdown are what the widget is for and they never give way.
    private var unlocked: some View {
        ViewThatFits(in: .vertical) {
            stack(spacing: 4, showsFooter: true)
            stack(spacing: 4, showsFooter: false)
            stack(spacing: 1, showsFooter: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .foregroundStyle(WidgetSky.foreground(solarAltitude: entry.solarAltitude))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spokenLabel))
        .accessibilityValue(Text(spokenValue))
    }

    private func stack(spacing: CGFloat, showsFooter: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: spacing)
            figures
            if showsFooter {
                Spacer(minLength: spacing)
                footer
            }
        }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 5) {
            // The glyph carries the accent, the name carries the meaning. The accents
            // separate by hue and by nothing else, so a reader who works from
            // luminance still has the word beside it.
            Image(systemName: entry.nextEvent?.kind.symbolName ?? "sun.horizon")
                .imageScale(.small)
                .foregroundStyle(entry.nextEvent?.kind.accent ?? WidgetSky.sunAccent)
                .accessibilityHidden(true)
            Text(entry.nextEvent?.kind.localisedName ?? nextEventFallbackLabel)
                .widgetLabelStyle()
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
    }

    @ViewBuilder
    private var figures: some View {
        if let event = entry.nextEvent {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.timeText(event.date))
                    .widgetFigureStyle(.title)
                // A live timer rather than a rendered string. It ticks between
                // entries, and the entry that replaces it lands exactly on the event
                // rather than at the next convenient quarter hour.
                Text(timerInterval: entry.date...event.date, countsDown: true)
                    .widgetFigureStyle(.subheadline)
            }
        } else {
            // Inside the polar circles there is no next event to name. Saying so is
            // the honest readout; a dash would look like missing data.
            Text(entry.polarExplanation ?? nextEventFallbackLabel)
                .font(.system(.footnote, design: .default))
                .lineLimit(3)
                .minimumScaleFactor(0.7)
        }
    }

    private var footer: some View {
        Text(entry.placeName)
            .font(.system(.caption2, design: .default))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    // MARK: Strings

    private var nextEventFallbackLabel: String {
        String(localized: "widget.nextEvent.none", defaultValue: "No event ahead",
               comment: "Shown in the small widget when the sun neither rises nor sets on this day")
    }

    private var spokenLabel: String {
        String(
            localized: "widget.nextEvent.accessibility.label",
            defaultValue: "Next sun event at \(entry.placeName)",
            comment: "VoiceOver label for the small next event widget"
        )
    }

    private var spokenValue: String {
        guard let event = entry.nextEvent else {
            return entry.polarExplanation ?? nextEventFallbackLabel
        }
        // Formatted first, into named placeholders, so the catalogue carries
        // readable values rather than Swift calls.
        let name = event.kind.localisedName
        let clock = entry.timeText(event.date)
        let ahead = entry.aheadText(event.date)
        return String(
            localized: "widget.nextEvent.accessibility.value",
            defaultValue: "\(name) at \(clock), in \(ahead)",
            comment: "VoiceOver value for the small next event widget: event name, clock time, and how long until it"
        )
    }
}
