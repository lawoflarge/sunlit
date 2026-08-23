import SwiftUI
import SunlitCore

/// The day, as a list of the moments people actually plan around, in the order they
/// happen. The next one to come carries a countdown from the selected instant.
///
/// An event that does not occur says so. Optional here means "did not happen on this day
/// at this place", never "unknown": above the Arctic Circle most of these are absent for
/// weeks at a time, the moon skips a rise roughly once a month, and printing a plausible
/// looking time for either is worse than printing nothing.
struct EventRail: View {

    @Environment(\.solarAltitude) private var solarAltitude

    let report: DayReport?
    /// The Milky Way window for the night this day opens. Held separately from the
    /// report because it is its own sweep of the night: `DayReport.milkyWayVisibility()`
    /// is a method rather than a stored property precisely so that a date change does not
    /// pay for it, and calling it from a view body would pay for it on every frame.
    let milkyWay: MilkyWay.Visibility?
    /// The instant the rest of the screen is showing. Countdowns are measured from here
    /// and not from the wall clock, so a scrubbed screen stays internally consistent.
    let instant: Date
    let timeZone: TimeZone
    let allowsMoon: Bool
    let allowsMilkyWay: Bool
    /// The route to the paywall. Nil while no route has been supplied, in which case the
    /// locked rows explain themselves and offer nothing that does not work.
    let onUnlock: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(SkyStrings.eventsTitle).sunlitLabel()
                .padding(.bottom, 10)

            if let report {
                content(report)
            } else {
                ProgressView()
                    .padding(.vertical, 12)
                    .accessibilityLabel(Text(SkyStrings.working))
            }
        }
    }

    @ViewBuilder
    private func content(_ report: DayReport) -> some View {
        let rows = chronological(sunRows(report))
        let nextIdentifier = rows.first(where: { ($0.time ?? .distantPast) > instant })?.id

        VStack(alignment: .leading, spacing: 0) {
            if report.phases.polarDay || report.phases.polarNight {
                Text(report.phases.polarDay ? SkyStrings.polarDay : SkyStrings.polarNight)
                    .font(SunlitType.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 10)
                HairlineDivider()
            }

            ForEach(rows) { row in
                EventRow(
                    symbol: row.symbol,
                    tint: SkyColors.sun,
                    title: row.title,
                    value: row.value,
                    countdown: row.id == nextIdentifier ? countdown(to: row.time) : nil,
                    spokenValue: row.value)
                HairlineDivider()
            }

            moonRow(report)
            HairlineDivider()
            milkyWayRow()
        }
    }

    private func countdown(to date: Date?) -> String? {
        guard let date else { return nil }
        return SkyFormat.countdown(from: instant, to: date)
    }

    // MARK: The sun's day

    private struct Row: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let value: String
        /// The instant the countdown is measured to. Nil when the event does not occur.
        let time: Date?
    }

    private func sunRows(_ report: DayReport) -> [Row] {
        let phases = report.phases
        let golden = report.goldenHour
        return [
            row(id: "firstLight", symbol: "sun.horizon", title: SkyStrings.firstLight, at: phases.astronomicalDawn),
            row(id: "sunrise", symbol: "sunrise.fill", title: SkyStrings.sunrise, at: phases.sunrise),
            window(id: "goldenMorning", symbol: "sun.min.fill", title: SkyStrings.goldenHour, window: golden.morning),
            row(id: "solarNoon", symbol: "sun.max.fill", title: SkyStrings.solarNoon, at: phases.solarNoon),
            window(id: "goldenEvening", symbol: "sun.min.fill", title: SkyStrings.goldenHour, window: golden.evening),
            row(id: "sunset", symbol: "sunset.fill", title: SkyStrings.sunset, at: phases.sunset),
            row(id: "lastLight", symbol: "sun.horizon", title: SkyStrings.lastLight, at: phases.astronomicalDusk)
        ]
    }

    /// The rows in the order they actually happen, which the declared order is not.
    ///
    /// The golden band runs from minus four degrees to plus six, and sunrise is at minus
    /// five sixths of a degree, so the morning window opens before the sun is up: at
    /// Berlin in March it opens about eighteen minutes before sunrise. Listing sunrise
    /// above it contradicted the heading of this file, and it also put the countdown on
    /// the wrong event, because the countdown goes to the first row in the array whose
    /// time is still ahead. A reader at six in the morning was told sunrise was in
    /// twenty eight minutes while the golden hour they were waiting for started in ten.
    ///
    /// Rows with no time keep the slot the day's structure gives them, so an absent
    /// sunrise in the polar night still reads between first light and golden hour rather
    /// than being swept to one end of the list.
    private func chronological(_ rows: [Row]) -> [Row] {
        var timed = rows.filter { $0.time != nil }
        guard timed.count > 1 else { return rows }
        timed.sort { ($0.time ?? .distantPast) < ($1.time ?? .distantPast) }
        var next = timed.makeIterator()
        return rows.map { $0.time == nil ? $0 : (next.next() ?? $0) }
    }

    private func row(id: String, symbol: String, title: String, at moment: JulianDay?) -> Row {
        guard let moment else {
            return Row(id: id, symbol: symbol, title: title, value: SkyStrings.absent, time: nil)
        }
        let date = moment.date
        return Row(
            id: id,
            symbol: symbol,
            title: title,
            value: SkyFormat.time(date, in: timeZone),
            time: date)
    }

    private func window(id: String, symbol: String, title: String, window: GoldenHour.Window?) -> Row {
        guard let window else {
            return Row(id: id, symbol: symbol, title: title, value: SkyStrings.absent, time: nil)
        }
        let start = window.start.date
        return Row(
            id: id,
            symbol: symbol,
            title: title,
            value: SkyStrings.range(
                SkyFormat.time(start, in: timeZone),
                SkyFormat.time(window.end.date, in: timeZone)),
            time: start)
    }

    // MARK: The moon

    private func moonRow(_ report: DayReport) -> some View {
        let phase = report.moonPhaseAtNoon
        let value = SkyStrings.moonSummary(
            phase: SkyStrings.phaseName(phase.name),
            illumination: phase.illuminatedFraction.formatted(.percent.precision(.fractionLength(0))),
            rise: report.moonrise.map { SkyFormat.time($0.date, in: timeZone) },
            set: report.moonset.map { SkyFormat.time($0.date, in: timeZone) })

        return GatedRow(
            title: SkyStrings.moon,
            value: value,
            reason: SkyStrings.lockMoon,
            isUnlocked: allowsMoon,
            onUnlock: onUnlock,
            leading: {
                SkyMoonDisc(
                    illuminatedFraction: phase.illuminatedFraction,
                    brightLimbAngle: phase.brightLimbAngle,
                    lit: allowsMoon ? SkyColors.moon : SkyColors.disabled(solarAltitude: solarAltitude),
                    outline: allowsMoon
                        ? SkyPalette.foreground(solarAltitude: solarAltitude)
                        : SkyColors.disabled(solarAltitude: solarAltitude))
                    .frame(width: 22, height: 22)
            })
    }

    // MARK: The Milky Way

    private func milkyWayRow() -> some View {
        GatedRow(
            title: SkyStrings.milkyWay,
            value: milkyWayValue(milkyWay),
            reason: SkyStrings.lockMilkyWay,
            isUnlocked: allowsMilkyWay,
            onUnlock: onUnlock,
            leading: {
                Image(systemName: "sparkles")
                    .imageScale(.medium)
                    .foregroundStyle(
                        allowsMilkyWay
                            ? SkyColors.milkyWay
                            : SkyColors.disabled(solarAltitude: solarAltitude))
                    .frame(width: 22)
                    .accessibilityHidden(true)
            })
    }

    /// The window when there is one, and otherwise the condition that closed it. Naming
    /// the limiting factor is the feature: the answer to twilight is to wait a month, the
    /// answer to moonlight is to wait a week, and the answer to a centre that never rises
    /// is to drive south.
    private func milkyWayValue(_ visibility: MilkyWay.Visibility?) -> String {
        guard let visibility else { return SkyStrings.working }
        if let window = visibility.window {
            return SkyStrings.range(
                SkyFormat.time(window.start.date, in: timeZone),
                SkyFormat.time(window.end.date, in: timeZone))
        }
        guard let factor = visibility.limitingFactor else { return SkyStrings.absent }
        return SkyStrings.limitingFactor(factor)
    }
}

// MARK: - Rows

/// One line of the rail: a mark, a name, a figure, and a countdown on the next one.
///
/// The mark is decorative and hidden; the accent colours are hue signals that can match
/// the sky they lie on exactly, so the name beside each of them in foreground ink is what
/// carries the meaning.
private struct EventRow<Leading: View>: View {

    @Environment(\.solarAltitude) private var solarAltitude

    let title: String
    let value: String
    let countdown: String?
    let spokenValue: String
    /// Greys the row and softens the figures on it, without moving anything. The name and
    /// the mark stay legible: the reader is meant to see exactly which row is locked.
    let isLocked: Bool
    @ViewBuilder let leading: Leading

    init(
        symbol: String,
        tint: Color,
        title: String,
        value: String,
        countdown: String?,
        spokenValue: String
    ) where Leading == AnyView {
        self.title = title
        self.value = value
        self.countdown = countdown
        self.spokenValue = spokenValue
        self.isLocked = false
        self.leading = AnyView(
            Image(systemName: symbol)
                .imageScale(.medium)
                .foregroundStyle(tint)
                .frame(width: 22)
                .accessibilityHidden(true))
    }

    init(
        title: String,
        value: String,
        countdown: String?,
        spokenValue: String,
        isLocked: Bool,
        @ViewBuilder leading: () -> Leading
    ) {
        self.title = title
        self.value = value
        self.countdown = countdown
        self.spokenValue = spokenValue
        self.isLocked = isLocked
        self.leading = leading()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                leading
                Text(title).font(SunlitType.body)
                Spacer(minLength: 12)
                figures(alignment: .trailing)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    leading
                    Text(title).font(SunlitType.body)
                }
                figures(alignment: .leading)
            }
        }
        .frame(minHeight: 44)
        .foregroundStyle(
            isLocked
                ? SkyColors.disabled(solarAltitude: solarAltitude)
                : SkyPalette.foreground(solarAltitude: solarAltitude))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(spokenAll))
    }

    private func figures(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(value)
                .font(SunlitType.metricSmall)
                .fixedSize(horizontal: false, vertical: true)
            if let countdown {
                Text(countdown).font(SunlitType.caption)
            }
        }
        // Only the figures are softened. Blurring the name of the row would hide which
        // row is locked, which is the one thing the reader has to be able to see.
        .blur(radius: isLocked ? 2.5 : 0)
    }

    private var spokenAll: String {
        guard let countdown else { return spokenValue }
        return spokenValue + ", " + countdown
    }
}

/// A row for something the purchase unlocks.
///
/// Unlocked it is an ordinary row. Locked it keeps its place, its name and its mark, and
/// blurs only the figures, so the reader can see exactly what the feature would tell them
/// and what it costs to read it. A gated feature that disappears makes the free app look
/// broken instead of free, which is why nothing here is ever hidden.
private struct GatedRow<Leading: View>: View {

    let title: String
    let value: String
    let reason: String
    let isUnlocked: Bool
    let onUnlock: (() -> Void)?
    @ViewBuilder let leading: Leading

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            EventRow(
                title: title,
                value: value,
                countdown: nil,
                spokenValue: isUnlocked ? value : reason,
                isLocked: !isUnlocked,
                leading: { leading })

            if !isUnlocked {
                SkyLockNote(reason: reason, action: onUnlock)
            }
        }
        .padding(.vertical, 2)
    }
}
