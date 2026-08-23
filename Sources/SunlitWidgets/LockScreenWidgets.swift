import SwiftUI
import WidgetKit
import SunlitCore

// MARK: - Golden hour ring

/// `accessoryCircular`: a ring that drains toward the golden hour, and then through it.
///
/// The ring is a `ProgressView(timerInterval:)`, so it advances by itself between
/// timeline entries. The entries still matter: the one that flips the ring from
/// counting toward the golden hour to counting through it lands exactly on the
/// window's start, not at the next convenient quarter hour.
struct GoldenHourRingWidget: Widget {

    static let kind = "com.levinschwab.sunlit.widget.goldenHourRing"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SunlitTimelineProvider()) { entry in
            GoldenHourRingView(entry: entry)
        }
        .configurationDisplayName(Text(Self.title))
        .description(Text(Self.blurb))
        .supportedFamilies([.accessoryCircular])
    }

    static var title: String {
        String(localized: "widget.goldenRing.title", defaultValue: "Golden Hour",
               comment: "Name of the circular lock screen widget in the widget gallery")
    }

    static var blurb: String {
        String(localized: "widget.goldenRing.description",
               defaultValue: "A ring counting down to the golden hour, then through it.",
               comment: "Description of the circular lock screen widget in the widget gallery")
    }
}

struct GoldenHourRingView: View {
    let entry: SunlitEntry

    var body: some View {
        content
            .containerBackground(.clear, for: .widget)
            .widgetURL(SunlitWidgetLink.destination(for: entry))
    }

    @ViewBuilder
    private var content: some View {
        if entry.needsSetup {
            // This family has no room for a caption, so before a place has been shared
            // a ring here would count down to a golden hour somewhere the reader has
            // never been, with nothing on the tile to say so.
            SetupPromptView(compact: true)
        } else if !entry.isUnlocked {
            lockedRing
        } else if let range = timerRange {
            ProgressView(timerInterval: range, countsDown: true)
                .progressViewStyle(.circular)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(GoldenHourRingWidget.title))
                .accessibilityValue(Text(spokenValue))
        } else {
            // No golden hour in the window ahead, which happens inside the polar
            // circles. Saying so beats an empty ring that looks like a failure.
            VStack(spacing: 1) {
                Image(systemName: "camera.filters")
                    .imageScale(.small)
                    .accessibilityHidden(true)
                Text(noWindowLabel)
                    .font(.system(.caption2, design: .default))
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(GoldenHourRingWidget.title))
            .accessibilityValue(Text(entry.polarExplanation ?? noWindowLabel))
        }
    }

    private var lockedRing: some View {
        VStack(spacing: 1) {
            Image(systemName: "lock.fill")
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(lockedShort)
                .font(.system(.caption2, design: .default))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(lockedTitle))
    }

    /// The interval the ring runs over: the wait for the golden hour, or the golden
    /// hour itself once it has started.
    private var timerRange: ClosedRange<Date>? {
        guard let window = entry.goldenWindow else { return nil }
        if window.isUnderway(at: entry.date) {
            guard window.end > window.start else { return nil }
            return window.start...window.end
        }
        guard window.start > entry.date else { return nil }
        return entry.date...window.start
    }

    private var spokenValue: String {
        guard let window = entry.goldenWindow else { return noWindowLabel }
        if window.isUnderway(at: entry.date) {
            return String(
                localized: "widget.goldenRing.accessibility.underway",
                defaultValue: "Golden hour now, until \(entry.timeText(window.end))",
                comment: "VoiceOver value for the golden hour ring while the golden hour is running"
            )
        }
        return String(
            localized: "widget.goldenRing.accessibility.waiting",
            defaultValue: "Golden hour begins at \(entry.timeText(window.start))",
            comment: "VoiceOver value for the golden hour ring before the golden hour starts"
        )
    }

    private var noWindowLabel: String {
        String(localized: "widget.goldenRing.none", defaultValue: "None today",
               comment: "Shown on the circular widget when the sun never reaches the golden hour band")
    }

    private var lockedTitle: String {
        String(localized: "widget.locked.title", defaultValue: "Unlock in Sunlit",
               comment: "Headline of the locked state of a widget, shown when the purchase is absent")
    }

    private var lockedShort: String {
        String(localized: "widget.locked.short", defaultValue: "Sunlit",
               comment: "The app name, shown on the tiny circular widget when the purchase is absent")
    }
}

// MARK: - Sun and moon digest

/// `accessoryRectangular`: sunrise, sunset, and the moon phase.
struct SkyDigestWidget: Widget {

    static let kind = "com.levinschwab.sunlit.widget.skyDigest"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SunlitTimelineProvider()) { entry in
            SkyDigestView(entry: entry)
        }
        .configurationDisplayName(Text(Self.title))
        .description(Text(Self.blurb))
        .supportedFamilies([.accessoryRectangular])
    }

    static var title: String {
        String(localized: "widget.digest.title", defaultValue: "Sun and Moon",
               comment: "Name of the rectangular lock screen widget in the widget gallery")
    }

    static var blurb: String {
        String(localized: "widget.digest.description",
               defaultValue: "Sunrise, sunset, and tonight's moon phase.",
               comment: "Description of the rectangular lock screen widget in the widget gallery")
    }
}

struct SkyDigestView: View {
    let entry: SunlitEntry

    var body: some View {
        content
            .containerBackground(.clear, for: .widget)
            .widgetURL(SunlitWidgetLink.destination(for: entry))
    }

    @ViewBuilder
    private var content: some View {
        if entry.needsSetup {
            // Room here for the whole sentence, unlike the circular family.
            SetupPromptView()
        } else if entry.isUnlocked {
            unlocked
        } else {
            locked
        }
    }

    private var unlocked: some View {
        // The place line is the first thing to go when the text size grows, because
        // the times and the phase are what the reader came for. Nothing truncates and
        // nothing is pushed off the tile.
        ViewThatFits(in: .vertical) {
            VStack(alignment: .leading, spacing: 1) {
                placeLine
                sunLine
                moonLine
            }
            VStack(alignment: .leading, spacing: 1) {
                sunLine
                moonLine
            }
            VStack(alignment: .leading, spacing: 1) {
                sunLine
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(SkyDigestWidget.title))
        .accessibilityValue(Text(spokenValue))
    }

    /// The locked state shows what it would show, obscured, rather than replacing it.
    ///
    /// It used to replace it: the sun and moon lines vanished entirely and only the
    /// lock text remained, which is the treatment the two system families already
    /// avoid. A gated feature that shows nothing of itself reads as a broken one.
    private var locked: some View {
        ZStack {
            unlocked
                .blur(radius: 2.5)
                .opacity(0.45)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .imageScale(.small)
                        .accessibilityHidden(true)
                    Text(lockedTitle)
                        .font(.system(.footnote, design: .default).weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Text(lockedBody)
                    .font(.system(.caption2, design: .default))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(lockedTitle))
        .accessibilityHint(Text(lockedBody))
    }

    // MARK: Lines

    private var placeLine: some View {
        Text(entry.placeName)
            .font(.system(.caption2, design: .default).weight(.medium))
            .textCase(.uppercase)
            .tracking(0.4)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    /// Sunrise and sunset, each printed when it happens.
    ///
    /// The two are separate facts. This used to demand both and otherwise print "No
    /// sunrise or sunset today", which on the day a polar day begins, where the sun
    /// rises and then never sets, is a false sentence printed over a real sunrise.
    @ViewBuilder
    private var sunLine: some View {
        if let sunrise = entry.sunrise, let sunset = entry.sunset {
            HStack(spacing: 10) {
                timeCell(symbol: "sunrise.fill", text: entry.timeText(sunrise))
                timeCell(symbol: "sunset.fill", text: entry.timeText(sunset))
            }
        } else if let sunrise = entry.sunrise {
            HStack(spacing: 8) {
                timeCell(symbol: "sunrise.fill", text: entry.timeText(sunrise))
                absenceNote(entry.sunsetAbsenceText)
            }
        } else if let sunset = entry.sunset {
            HStack(spacing: 8) {
                absenceNote(entry.sunriseAbsenceText)
                timeCell(symbol: "sunset.fill", text: entry.timeText(sunset))
            }
        } else {
            absenceNote(entry.dayAbsenceText)
        }
    }

    private func absenceNote(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .default))
            .lineLimit(2)
            .minimumScaleFactor(0.7)
    }

    private var moonLine: some View {
        HStack(spacing: 4) {
            Image(systemName: entry.moonSymbolName)
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(moonText)
                .font(.system(.caption, design: .default).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    private func timeCell(symbol: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(.callout, design: .default).weight(.medium).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    // MARK: Strings

    private var moonText: String {
        String(
            localized: "widget.digest.moon",
            defaultValue: "\(entry.moonPhaseText) \(entry.moonIlluminationText)",
            comment: "The moon line on the rectangular widget: phase name then the lit fraction as a percentage"
        )
    }

    private var spokenValue: String {
        let moon = String(
            localized: "widget.digest.accessibility.moon",
            defaultValue: "Moon \(entry.moonPhaseText), \(entry.moonIlluminationText) lit",
            comment: "VoiceOver value for the moon part of the rectangular widget"
        )
        let sun: String
        switch (entry.sunrise, entry.sunset) {
        case let (sunrise?, sunset?):
            sun = String(
                localized: "widget.digest.accessibility.sun",
                defaultValue: "Sunrise \(entry.timeText(sunrise)), sunset \(entry.timeText(sunset))",
                comment: "VoiceOver value for the sunrise and sunset part of the rectangular widget"
            )
        case let (sunrise?, nil):
            sun = String(
                localized: "widget.digest.accessibility.sunriseOnly",
                defaultValue: "Sunrise \(entry.timeText(sunrise)). \(entry.sunsetAbsenceText)",
                comment: "VoiceOver value on a day with a sunrise and no sunset"
            )
        case let (nil, sunset?):
            sun = String(
                localized: "widget.digest.accessibility.sunsetOnly",
                defaultValue: "\(entry.sunriseAbsenceText). Sunset \(entry.timeText(sunset))",
                comment: "VoiceOver value on a day with no sunrise and a sunset"
            )
        case (nil, nil):
            sun = entry.dayAbsenceText
        }
        return sun + ". " + moon
    }

    private var lockedTitle: String {
        String(localized: "widget.locked.title", defaultValue: "Unlock in Sunlit",
               comment: "Headline of the locked state of a widget, shown when the purchase is absent")
    }

    private var lockedBody: String {
        String(localized: "widget.locked.body", defaultValue: "Widgets are part of the one purchase.",
               comment: "Explanation in the locked state of a widget")
    }
}
