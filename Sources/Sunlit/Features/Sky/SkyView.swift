import SwiftUI
import SunlitCore

/// The home screen, and the face of the product.
///
/// One shared place and one shared instant, drawn four ways down a single scroll: the
/// day's arc, the scrubber that moves through it, the figures for the instant, and the
/// day's events. The background is not behind any of that. It is part of it: the gradient
/// is interpolated from the solar altitude of the selected instant, so dragging the
/// scrubber repaints the sky the colour the sky actually is.
///
/// Everything scrolls. Not a preference: a `VStack` holding a primary control against a
/// fixed height puts that control below the fold at the largest Dynamic Type size, and
/// App Review tests at the largest Dynamic Type size. Two apps in this portfolio were
/// taken down for exactly that.
///
/// Cost model, which is the reason this file is shaped the way it is. A `DayReport` is
/// several thousand ephemeris evaluations and is rebuilt only when the place or the day
/// changes, off the main thread. A `SkyMoment` is one evaluation and is rebuilt on every
/// frame of a drag. Nothing in this file computes an astronomical quantity; it reads the
/// two of them.
struct SkyView: View {

    @Environment(AppState.self) private var state

    /// The selected day. Nil for the thirty milliseconds it takes to build, during which
    /// the frame, the horizon and the golden band are already drawn.
    @State private var report: DayReport?

    /// The Milky Way window for the night this day opens, computed after the report and
    /// off the main thread. It is a sweep of the whole night in its own right, which is
    /// why the core makes it a method: asking for it from a view body would sweep the
    /// night on every frame of a drag.
    @State private var milkyWay: MilkyWay.Visibility?

    /// The wall clock, sampled once a second while the app is following live time. The
    /// gradient, the arc and the countdowns all hang off it.
    @State private var tick = Date()

    /// Seconds into the local day the reader last chose with the scrubber, kept across a
    /// change of place or date so that the hour is not thrown away. Nil while the app is
    /// following the clock. The Now button is the only thing that clears it.
    @State private var heldHour: Double?

    @State private var showingPlacePicker = false
    @State private var showingDatePicker = false
    @State private var showingPro = false

    var body: some View {
        let zone = TimeZone(identifier: state.place.timeZoneIdentifier) ?? .current
        let dayStart = dayStartDate
        let instant = displayInstant
        let moment = SkyMoment.at(JulianDay(date: instant), place: state.place)
        let altitude = moment.sun.altitude
        let fraction = min(max(instant.timeIntervalSince(dayStart) / 86400, 0), 1)

        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                GlobalHeader(
                    showingPlacePicker: $showingPlacePicker,
                    showingDatePicker: $showingDatePicker,
                    solarAltitude: altitude)

                VStack(alignment: .leading, spacing: 22) {
                    if !state.selectionIsFree {
                        SkyLockNote(reason: SkyStrings.lockSelection, action: { showingPro = true })
                    }

                    // The arc says the moon is locked with the lock beside its own legend
                    // entry. The written reason and the route to the paywall belong to the
                    // moon's row in the rail below, once, rather than twice down one
                    // scroll: two identical notes on one screen read as a defect.
                    DayArc(
                        report: report,
                        moment: moment,
                        fraction: fraction,
                        showsMoon: state.pro.allows(.moon))

                    TimeScrubber(
                        fraction: Binding(
                            get: { fraction },
                            set: { scrub(to: $0, dayStart: dayStart) }),
                        dayStart: dayStart,
                        timeZone: zone,
                        marks: marks,
                        isLive: state.scrubSeconds == nil && state.isToday,
                        onReturnToNow: returnToNow)

                    HairlineDivider()

                    MetricBlock(moment: moment)

                    HairlineDivider()

                    EventRail(
                        report: report,
                        milkyWay: milkyWay,
                        instant: instant,
                        timeZone: zone,
                        allowsMoon: state.pro.allows(.moon),
                        allowsMilkyWay: state.pro.allows(.milkyWay),
                        onUnlock: { showingPro = true })
                }
                .padding(.horizontal, 20)
            }
            .padding(.vertical, 16)
        }
        .adaptiveSky(solarAltitude: altitude, moonIllumination: moonlight(moment))
        .task(id: dayKey) {
            await loadReport()
        }
        .task {
            await followTheClock()
        }
        .onChange(of: dayKey, initial: true) { _, _ in
            alignInstantToSelection()
        }
        // The three shared screens, not local imitations of them. The altitude is handed
        // over explicitly because `adaptiveSky` publishes it into the environment of the
        // content it wraps, and a sheet is presented from outside that wrapper, so without
        // this line all three would open painted for a sun on the horizon.
        .sheet(isPresented: $showingPlacePicker) {
            PlacePickerView()
                .environment(\.solarAltitude, altitude)
        }
        .sheet(isPresented: $showingDatePicker) {
            DatePickerSheet()
                .environment(\.solarAltitude, altitude)
        }
        .sheet(isPresented: $showingPro) {
            PaywallView()
                .environment(\.solarAltitude, altitude)
        }
    }

    // MARK: The selected instant

    /// Local midnight of the selected day, in the selected place's own zone. This is the
    /// window the arc is drawn over and the window the scrubber runs across.
    private var dayStartDate: Date {
        state.place.startOfLocalDay(containing: state.day).date
    }

    /// What the whole screen is showing.
    ///
    /// Following the clock is only meaningful on the day being lived through, so a
    /// selected day that is not today shows local noon until it is scrubbed. Without that
    /// the app would answer a question about the fourteenth with the position of the sun
    /// right now.
    private var displayInstant: Date {
        if state.scrubSeconds != nil { return state.instant }
        if state.isToday { return tick }
        return dayStartDate.addingTimeInterval(43_200)
    }

    /// Writes the scrubber's position back as an offset from `AppState.day`, which is what
    /// every other view resolves the shared instant through.
    ///
    /// Assigned rather than passed through `AppState.scrub(toSecondsSinceMidnight:)`,
    /// because that helper clamps to a single day measured from the device's midnight. The
    /// offset between the device's midnight and the selected place's midnight can be up to
    /// fourteen hours in either direction, and clamping it would pin the scrubber to one
    /// end of the track for anyone scouting a distant location.
    private func scrub(to fraction: Double, dayStart: Date) {
        let clamped = min(max(fraction, 0), 1)
        let target = dayStart.addingTimeInterval(clamped * 86400)
        state.scrubSeconds = target.timeIntervalSince(state.day)
        heldHour = clamped * 86400
    }

    /// Back to today, live. The one control that always means the same thing.
    ///
    /// Today is resolved in the selected place's own clock, not the device's. Those two
    /// disagree by up to a day whenever the reader is scouting a distant location, which
    /// is the workflow this app is built around: taking the device's midnight and asking
    /// `AppState.isToday` about it in Tokyo's calendar answers no, which would put a lock
    /// note on the free tier's one free day and pin the screen to noon.
    private func returnToNow() {
        // Cleared before the day moves, so that the alignment this triggers cannot read a
        // held hour that this button exists to discard.
        heldHour = nil
        state.day = state.place.startOfLocalDay(containing: Date()).date
        state.resumeLiveTime()
        tick = Date()
    }

    /// Keeps the shared instant inside the selected day whenever the place or the day
    /// changes, so the four views never disagree about what they are showing.
    ///
    /// A chosen hour survives the change. Setting six in the morning and then moving the
    /// place from Berlin to Reykjavik used to snap the screen back to live time and throw
    /// the hour away, which is the opposite of what the one shared place and instant are
    /// for. Only the Now button clears it.
    private func alignInstantToSelection() {
        // A capture has already chosen its instant, and the branch below would
        // throw it away the moment the chosen day happens to be today. The first
        // capture came out at the wall clock time for exactly this reason.
        guard !state.isCaptureMode else { return }
        let dayStart = dayStartDate
        if let heldHour {
            state.scrubSeconds = dayStart
                .addingTimeInterval(heldHour)
                .timeIntervalSince(state.day)
        } else if state.isToday {
            state.resumeLiveTime()
        } else {
            state.scrubSeconds = dayStart
                .addingTimeInterval(43_200)
                .timeIntervalSince(state.day)
        }
    }

    /// A gentle lift on a clear night, and only from a moon that is actually up. The
    /// gradient is a readout of the sky, and a moon below the horizon lights nothing.
    private func moonlight(_ moment: SkyMoment) -> Double {
        moment.moon.altitude > 0 ? moment.moonPhase.illuminatedFraction : 0
    }

    // MARK: The day

    /// What a rebuild of the day depends on, and nothing else. The scrubber moves inside
    /// this key without changing it, which is the whole point.
    private struct DayKey: Hashable {
        let place: UUID
        let start: Double
    }

    private var dayKey: DayKey {
        DayKey(place: state.place.id, start: state.place.startOfLocalDay(containing: state.day).value)
    }

    private func loadReport() async {
        let start = state.place.startOfLocalDay(containing: state.day)
        let place = state.place
        // Cleared rather than left standing: yesterday's arc under today's gradient is a
        // wrong answer, and the frame, the horizon and the golden band are drawn anyway.
        report = nil
        milkyWay = nil
        let computed = await Task.detached(priority: .userInitiated) {
            DayReport.compute(date: start, place: place)
        }.value
        guard !Task.isCancelled else { return }
        report = computed
        // Second, and at a lower priority: the arc and the figures are on screen by now,
        // and one row of the rail is waiting for this.
        let window = await Task.detached(priority: .utility) {
            computed.milkyWayVisibility()
        }.value
        guard !Task.isCancelled else { return }
        milkyWay = window
    }

    /// One second is finer than any figure on this screen changes and coarse enough to
    /// cost nothing. It stops when the view goes away, and it does not run while the
    /// scrubber is holding the instant.
    ///
    /// The `isToday` half matters as much as the scrubber half: `displayInstant` does not
    /// read `tick` at all on any other day, so publishing it there would rebuild a
    /// `SkyMoment` every second to draw exactly the same screen.
    private func followTheClock() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if state.scrubSeconds == nil, state.isToday {
                tick = Date()
            }
        }
    }

    private var marks: [TimeScrubber.Mark] {
        guard let report else { return [] }
        let origin = report.date.value
        return [
            ("sunrise", report.phases.sunrise),
            ("noon", report.phases.solarNoon),
            ("sunset", report.phases.sunset)
        ].compactMap { name, moment in
            guard let moment else { return nil }
            let fraction = moment.value - origin
            guard fraction >= 0, fraction <= 1 else { return nil }
            return TimeScrubber.Mark(id: name, fraction: fraction)
        }
    }
}

// MARK: - The lock

/// One line saying what is locked, and the way to unlock it.
///
/// Never a substitute for the thing it locks: everywhere this appears, the feature above
/// it is still drawn, greyed, in its own place. A feature that vanishes when it is not
/// bought makes a free app look broken rather than free.
///
/// With no route supplied it is a statement rather than a button, because a control that
/// does nothing is worse than no control.
struct SkyLockNote: View {

    @Environment(\.solarAltitude) private var solarAltitude
    @Environment(\.displayScale) private var displayScale

    let reason: String
    let action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                Button(action: action) { content }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(spoken))
            } else {
                content
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(reason))
            }
        }
    }

    private var content: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                lock
                Text(reason).font(SunlitType.caption)
                Spacer(minLength: 8)
                if action != nil { unlock }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    lock
                    Text(reason)
                        .font(SunlitType.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if action != nil { unlock }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    SkyPalette.componentBorder(solarAltitude: solarAltitude),
                    lineWidth: 1 / displayScale)
        }
        .frame(minHeight: SunlitLayout.minimumTouchTarget)
        .contentShape(Rectangle())
    }

    private var lock: some View {
        Image(systemName: "lock.fill")
            .imageScale(.small)
            .accessibilityHidden(true)
    }

    private var unlock: some View {
        Text(SkyStrings.unlock)
            .font(SunlitType.caption)
            .fontWeight(.semibold)
    }

    private var spoken: String {
        reason + ". " + SkyStrings.unlockSpoken
    }
}

// MARK: - Formatting

/// Times and countdowns, in the selected place's own zone and the reader's own locale.
///
/// Formatters are cached because the scrubber redraws the rail on every frame of a drag
/// and building a `DateFormatter` is not free. The key carries the locale as well as the
/// zone, so a reader who changes either does not keep the old one.
@MainActor
enum SkyFormat {

    private static var timeFormatters: [String: DateFormatter] = [:]

    static func time(_ date: Date, in zone: TimeZone) -> String {
        let key = zone.identifier + "|" + Locale.current.identifier
        if let cached = timeFormatters[key] {
            return cached.string(from: date)
        }
        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        timeFormatters[key] = formatter
        return formatter.string(from: date)
    }

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    /// Measured from the instant on screen rather than from the wall clock, so a scrubbed
    /// screen does not tell the reader that sunset is in four hours while showing them
    /// midnight.
    static func countdown(from origin: Date, to target: Date) -> String {
        relative.localizedString(for: target, relativeTo: origin)
    }
}

// MARK: - Copy

/// Every user visible string on this screen, in one place.
///
/// All of them go through `String(localized:defaultValue:comment:)` with a literal key.
/// `Text("key \(value)")` looks up the key `key %@`, finds nothing, and ships the raw key
/// on a green build, which is a failure that reaches the store rather than the compiler.
///
/// No dash punctuation anywhere in this file, in any language.
enum SkyStrings {

    // MARK: Locks

    static var lockSelection: String {
        String(
            localized: "sky.lock.selection",
            defaultValue: "This place and date are part of Sunlit Pro",
            comment: "Shown when the selected place or date is outside the free tier")
    }

    static var lockMoon: String {
        String(
            localized: "sky.lock.moon",
            defaultValue: "The moon path and phase are part of Sunlit Pro",
            comment: "One line reason on the greyed out moon layer")
    }

    static var lockMilkyWay: String {
        String(
            localized: "sky.lock.milkyWay",
            defaultValue: "Milky Way windows are part of Sunlit Pro",
            comment: "One line reason on the greyed out Milky Way row")
    }

    static var unlock: String {
        String(localized: "sky.lock.unlock", defaultValue: "Unlock", comment: "Button on a lock note")
    }

    static var unlockSpoken: String {
        String(
            localized: "sky.lock.unlockSpoken",
            defaultValue: "Double tap to see what Sunlit Pro includes",
            comment: "Spoken form of the unlock button")
    }

    // MARK: The arc

    static var noon: String {
        String(localized: "sky.arc.noon", defaultValue: "Noon", comment: "Marks solar noon on the day arc")
    }

    static var legendSun: String {
        String(localized: "sky.legend.sun", defaultValue: "Sun", comment: "Legend under the day arc")
    }

    static var legendMoon: String {
        String(localized: "sky.legend.moon", defaultValue: "Moon", comment: "Legend under the day arc")
    }

    static var legendGolden: String {
        String(localized: "sky.legend.golden", defaultValue: "Golden hour", comment: "Legend under the day arc")
    }

    // MARK: The scrubber

    static var scrubberLabel: String {
        String(localized: "sky.scrubber.label", defaultValue: "Time", comment: "Label above the time scrubber")
    }

    static var scrubberHint: String {
        String(
            localized: "sky.scrubber.hint",
            defaultValue: "Swipe up or down to move through the day",
            comment: "VoiceOver hint for the adjustable time scrubber")
    }

    static var live: String {
        String(localized: "sky.scrubber.live", defaultValue: "Live", comment: "Shown while the app follows the clock")
    }

    static var liveSpoken: String {
        String(
            localized: "sky.scrubber.liveSpoken",
            defaultValue: "Showing the current time",
            comment: "Spoken form of the live indicator")
    }

    static var now: String {
        String(localized: "sky.scrubber.now", defaultValue: "Now", comment: "Button that returns to the current time")
    }

    static var nowSpoken: String {
        String(
            localized: "sky.scrubber.nowSpoken",
            defaultValue: "Return to today at the current time",
            comment: "Spoken form of the now button")
    }

    // MARK: The figures

    static var azimuth: String {
        String(localized: "sky.metric.azimuth", defaultValue: "Azimuth", comment: "The sun's bearing")
    }

    static var altitude: String {
        String(localized: "sky.metric.altitude", defaultValue: "Altitude", comment: "The sun's height above the horizon")
    }

    static var shadow: String {
        String(localized: "sky.metric.shadow", defaultValue: "Shadow length", comment: "The same quantity as map.shadow.length, expressed here as a multiple of the object's height rather than as a distance")
    }

    static var shadowUnit: String {
        String(
            localized: "sky.metric.shadowUnit",
            defaultValue: "times the height",
            comment: "Unit of the shadow ratio, as in 2.4 times the height. A multiple of the object's own height, not a distance, so it takes no metric or imperial unit")
    }

    static var shadowNone: String {
        String(
            localized: "sky.metric.shadowNone",
            defaultValue: "None",
            comment: "Shown for the shadow when the sun is below the horizon")
    }

    static var uvIndex: String {
        String(localized: "sky.metric.uv", defaultValue: "UV index", comment: "Modelled ultraviolet index")
    }

    static var irradiance: String {
        String(localized: "sky.metric.irradiance", defaultValue: "Irradiance", comment: "Modelled global horizontal irradiance")
    }

    static var clearSkyModel: String {
        String(
            localized: "sky.model.clearSky",
            defaultValue: "UV index and irradiance are a clear sky model, not a measurement",
            comment: "Mandatory caption wherever the two modelled figures appear")
    }

    static var clearSkyModelSpoken: String { clearSkyModel }

    // MARK: The day's events

    /// Not "today's light": the rail is drawn for whatever day the header is showing, and
    /// on any date but today the word today is simply false.
    static var eventsTitle: String {
        String(
            localized: "sky.events.title",
            defaultValue: "The day's light",
            comment: "Heading of the event rail, which is drawn for the selected day and not only for today")
    }

    static var working: String {
        String(localized: "sky.events.working", defaultValue: "Computing the day", comment: "Spoken while the day is being computed")
    }

    static var polarDay: String {
        String(
            localized: "sky.events.polarDay",
            defaultValue: "The sun does not set on this day",
            comment: "Shown above the event rail during the midnight sun")
    }

    static var polarNight: String {
        String(
            localized: "sky.events.polarNight",
            defaultValue: "The sun does not rise on this day",
            comment: "Shown above the event rail during the polar night")
    }

    static var firstLight: String {
        String(localized: "sky.event.firstLight", defaultValue: "First light", comment: "Astronomical dawn")
    }

    static var sunrise: String {
        String(localized: "sky.event.sunrise", defaultValue: "Sunrise", comment: "Event name")
    }

    static var goldenHour: String {
        String(localized: "sky.event.goldenHour", defaultValue: "Golden hour", comment: "Event name")
    }

    static var solarNoon: String {
        String(localized: "sky.event.solarNoon", defaultValue: "Solar noon", comment: "Event name")
    }

    static var sunset: String {
        String(localized: "sky.event.sunset", defaultValue: "Sunset", comment: "Event name")
    }

    static var lastLight: String {
        String(localized: "sky.event.lastLight", defaultValue: "Last light", comment: "Astronomical dusk")
    }

    static var absent: String {
        String(
            localized: "sky.event.absent",
            defaultValue: "Does not occur on this day",
            comment: "Shown for an event that does not happen on this day at this place. This screen can show any date, so it does not say today")
    }

    static func range(_ start: String, _ end: String) -> String {
        String(
            localized: "sky.event.range",
            defaultValue: "\(start) to \(end)",
            comment: "A start time and an end time")
    }

    // MARK: The moon and the Milky Way

    static var moon: String {
        String(localized: "sky.moon.title", defaultValue: "Moon", comment: "Row name")
    }

    static var milkyWay: String {
        String(localized: "sky.milkyWay.title", defaultValue: "Milky Way", comment: "Row name")
    }

    static func moonSummary(phase: String, illumination: String, rise: String?, set: String?) -> String {
        let lit = String(
            localized: "sky.moon.illuminated",
            defaultValue: "\(phase), \(illumination) lit",
            comment: "The moon's phase name and its illuminated fraction")
        switch (rise, set) {
        case let (rise?, set?):
            return lit + "\n" + String(
                localized: "sky.moon.riseAndSet",
                defaultValue: "Rises \(rise), sets \(set)",
                comment: "Moonrise and moonset times")
        case let (rise?, nil):
            return lit + "\n" + String(
                localized: "sky.moon.riseOnly",
                defaultValue: "Rises \(rise), no moonset on this day",
                comment: "The moon rises but does not set on this calendar day. This screen can show any date, so it does not say today")
        case let (nil, set?):
            return lit + "\n" + String(
                localized: "sky.moon.setOnly",
                defaultValue: "Sets \(set), no moonrise on this day",
                comment: "The moon sets but does not rise on this calendar day. This screen can show any date, so it does not say today")
        default:
            return lit + "\n" + String(
                localized: "sky.moon.neither",
                defaultValue: "No moonrise or moonset on this day",
                comment: "Neither event falls on this calendar day. This screen can show any date, so it does not say today")
        }
    }

    /// The eight named phases. The moon is drawn from its real illuminated fraction and
    /// bright limb angle; this only names what has been drawn.
    static func phaseName(_ name: MoonPosition.Phase.Name) -> String {
        switch name {
        case .newMoon:
            return String(localized: "sky.moon.phase.new", defaultValue: "New moon", comment: "Moon phase")
        case .waxingCrescent:
            return String(localized: "sky.moon.phase.waxingCrescent", defaultValue: "Waxing crescent", comment: "Moon phase")
        case .firstQuarter:
            return String(localized: "sky.moon.phase.firstQuarter", defaultValue: "First quarter", comment: "Moon phase")
        case .waxingGibbous:
            return String(localized: "sky.moon.phase.waxingGibbous", defaultValue: "Waxing gibbous", comment: "Moon phase")
        case .fullMoon:
            return String(localized: "sky.moon.phase.full", defaultValue: "Full moon", comment: "Moon phase")
        case .waningGibbous:
            return String(localized: "sky.moon.phase.waningGibbous", defaultValue: "Waning gibbous", comment: "Moon phase")
        case .lastQuarter:
            return String(localized: "sky.moon.phase.lastQuarter", defaultValue: "Last quarter", comment: "Moon phase")
        case .waningCrescent:
            return String(localized: "sky.moon.phase.waningCrescent", defaultValue: "Waning crescent", comment: "Moon phase")
        }
    }

    /// Why there is no Milky Way window. Naming the condition is the feature: the answer
    /// to each of these four is a different plan.
    static func limitingFactor(_ factor: MilkyWay.LimitingFactor) -> String {
        switch factor {
        case .galacticCentreBelowHorizon:
            return String(
                localized: "sky.milkyWay.limit.belowHorizon",
                defaultValue: "The galactic centre stays too low here on this night",
                comment: "Why there is no Milky Way window")
        case .twilight:
            return String(
                localized: "sky.milkyWay.limit.twilight",
                defaultValue: "The night never gets fully dark here at this time of year",
                comment: "Why there is no Milky Way window")
        case .moonlight:
            return String(
                localized: "sky.milkyWay.limit.moonlight",
                defaultValue: "Moonlight covers every dark hour of this night",
                comment: "Why there is no Milky Way window")
        case .season:
            return String(
                localized: "sky.milkyWay.limit.season",
                defaultValue: "A dark sky and a high centre never coincide on this night",
                comment: "Why there is no Milky Way window")
        }
    }
}
