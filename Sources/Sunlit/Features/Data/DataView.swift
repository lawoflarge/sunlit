import SwiftUI
import SunlitCore

// MARK: - The tabulation

/// The Data tab: every figure the selected day holds, in one scrolling column.
///
/// Nothing in this file or its siblings computes an astronomical quantity.
/// `DayReport` and `SkyMoment` are built once, on a background task, whenever
/// the place or the date changes, and every section below renders what they
/// already contain.
///
/// The screen scrolls end to end and carries no control pinned outside the
/// scroll view. Two apps in this portfolio were taken down for a primary button
/// that the largest Dynamic Type size pushed under the fold, and a tabulation is
/// the screen most likely to grow past a canvas. The one thing above the scroll
/// view is the shared header, which is pinned to the top and so is the one
/// position from which nothing can be pushed under the fold.
struct DataView: View {

    @Environment(AppState.self) private var state

    @State private var day: DataDay?

    @State private var showingPlacePicker = false
    @State private var showingDatePicker = false

    var body: some View {
        let altitude = skyAltitude
        return VStack(spacing: 0) {
            // The same header the Sky and Map tabs carry. Without it this tab
            // shows the figures for a place and a date that it offers no way to
            // change, which is the exact complaint about the competing product
            // that one shared header exists to answer.
            GlobalHeader(
                showingPlacePicker: $showingPlacePicker,
                showingDatePicker: $showingDatePicker,
                solarAltitude: altitude)

            ScrollView {
                // Lazy on purpose: the eclipse search and the annual sweep are
                // started by the `task` of their own section, so a section that
                // has never been scrolled to has never cost anything.
                LazyVStack(alignment: .leading, spacing: 28) {
                    DataContextRow(place: state.place, selected: state.day)

                    if let day {
                        SunSection(day: day, lock: selectionLock)
                        TwilightSection(day: day, lock: selectionLock)
                        GoldenBlueSection(day: day, lock: selectionLock)
                        MoonSection(day: day, lock: lock(for: .moon))
                        MilkyWaySection(day: day, lock: lock(for: .milkyWay))
                        EclipseSection(
                            place: state.place,
                            after: day.report.date,
                            timeZoneIdentifier: state.place.timeZoneIdentifier,
                            lock: lock(for: .eclipses))
                        ObstructionSection(day: day, lock: lock(for: .terrain))
                        AnnualSection(
                            place: state.place,
                            selected: state.day,
                            // The peak the core already refined for this day.
                            // Scanning for it a second time inside the annual
                            // sweep cost another twenty five ephemeris
                            // evaluations and could disagree with the figure the
                            // sun section prints two screens above.
                            selectedMaximum: day.report.maximumSolarAltitude,
                            lock: lock(for: .annualPaths))
                        ExportSection(day: day, place: state.place, lock: lock(for: .export))
                    } else {
                        DataLoadingRow()
                    }

                    DataFooter()
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 44)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .adaptiveSky(
            solarAltitude: altitude,
            moonIllumination: day?.noon.moonPhase.illuminatedFraction ?? 0)
        .task(id: key) { await reload() }
        // The shared screens, not local imitations. The altitude is handed over
        // explicitly because `adaptiveSky` publishes it into the environment of
        // the content it wraps and a sheet is presented from outside that.
        .sheet(isPresented: $showingPlacePicker) {
            PlacePickerView()
                .environment(\.solarAltitude, altitude)
        }
        .sheet(isPresented: $showingDatePicker) {
            DatePickerSheet()
                .environment(\.solarAltitude, altitude)
        }
    }

    // MARK: Loading

    /// Everything the day depends on. `Place` hashes on identity alone, so a
    /// coordinate that moved under the same identifier would not retrigger the
    /// task; the fields are listed out for that reason.
    private struct Key: Equatable {
        let latitude: Double
        let longitude: Double
        let elevation: Double
        let zone: String
        let profile: HorizonProfile?
        let day: Date
    }

    private var key: Key {
        Key(
            latitude: state.place.latitude,
            longitude: state.place.longitude,
            elevation: state.place.elevation,
            zone: state.place.timeZoneIdentifier,
            profile: state.place.horizonProfile,
            day: state.day)
    }

    @MainActor
    private func reload() async {
        // Dropped before the new one is built. `DataContextRow` and the header
        // above it read the live place and date, so a result kept across the
        // change prints one place's sunrise under another place's name for as
        // long as the sweep takes.
        day = nil
        let place = state.place
        let selected = state.day
        let computed = await Task.detached(priority: .userInitiated) {
            DataDay.compute(day: selected, place: place)
        }.value
        guard !Task.isCancelled else { return }
        day = computed
    }

    // MARK: Sky

    /// The instant the sky is painted for.
    ///
    /// Following the wall clock is only meaningful on the day being lived
    /// through. `AppState.instant` answers `Date()` whenever the scrubber is
    /// idle, so on any other date the nearest sample in the selected day is one
    /// of its two endpoints and the whole screen would be painted for midnight
    /// whatever date was chosen. Sky and Map resolve it exactly this way.
    private var displayInstant: Date {
        if state.scrubSeconds != nil { return state.instant }
        if state.isToday { return Date() }
        return state.place
            .startOfLocalDay(containing: state.day)
            .date
            .addingTimeInterval(43_200)
    }

    /// The altitude the background is painted for. Taken from the day's own
    /// samples rather than computed here, so the Data tab agrees with every
    /// other view about what the sky looks like at this instant.
    private var skyAltitude: Double {
        guard let day else { return 0 }
        let wanted = JulianDay(date: displayInstant).value
        var best = day.report.samples.first
        var distance = Double.infinity
        for sample in day.report.samples {
            let gap = abs(sample.instant.value - wanted)
            if gap < distance {
                distance = gap
                best = sample
            }
        }
        return best?.sun.altitude ?? 0
    }

    // MARK: Gates

    /// Today at the current location is free, in full. Anything else is the
    /// purchase, and the whole screen says so rather than emptying out.
    private var selectionLock: DataLock? {
        if state.selectionIsFree { return nil }
        return state.isToday ? .selectionPlace : .selectionDate
    }

    private func lock(for capability: ProCapability) -> DataLock? {
        if let selectionLock { return selectionLock }
        return state.pro.allows(capability) ? nil : .capability(capability)
    }
}

// MARK: - The day, computed once

/// One day at one place, plus the two instants the tables read from and the
/// extremes the absence explanations are built out of.
struct DataDay: Sendable {

    let report: DayReport
    /// Local noon. `DayReport.moonPhaseAtNoon` uses the same instant, so the
    /// moon figures on this screen are all referred to one moment.
    let noon: SkyMoment
    /// Solar transit, where the day's clear sky model figures peak. Falls back
    /// to local noon in polar night, where there is no transit above the
    /// horizon to speak of.
    let peak: SkyMoment
    let minimumSolarAltitude: Double
    let minimumMoonAltitude: Double
    let maximumMoonAltitude: Double
    let timeZoneIdentifier: String

    // The three figures `DayReport` no longer stores, because each one costs a
    // second sweep and the home screen does not show any of them. The Data tab
    // is exactly the screen that does, so it pays for them here, once, off the
    // main actor, rather than in a view body.

    /// A second complete day, solved so the change from yesterday is honest.
    let dayLengthChange: TimeInterval
    /// Its own sweep of the night.
    let milkyWay: MilkyWay.Visibility
    /// Three solves against the measured skyline.
    let terrain: DayReport.Terrain

    var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .gmt }
    var format: DataFormat { DataFormat(timeZone: timeZone) }
    var maximumSolarAltitude: Double { report.maximumSolarAltitude }

    static func compute(day: Date, place: Place) -> DataDay {
        let start = place.startOfLocalDay(containing: day)
        let report = DayReport.compute(date: start, place: place)
        let localNoon = start.adding(days: 0.5)

        var minimumSun = Double.infinity
        var minimumMoon = Double.infinity
        var maximumMoon = -Double.infinity
        for sample in report.samples {
            minimumSun = min(minimumSun, sample.sun.altitude)
            minimumMoon = min(minimumMoon, sample.moon.altitude)
            maximumMoon = max(maximumMoon, sample.moon.altitude)
        }

        return DataDay(
            report: report,
            noon: SkyMoment.at(localNoon, place: place),
            peak: SkyMoment.at(report.phases.solarNoon ?? localNoon, place: place),
            minimumSolarAltitude: minimumSun.isFinite ? minimumSun : -90,
            minimumMoonAltitude: minimumMoon.isFinite ? minimumMoon : -90,
            maximumMoonAltitude: maximumMoon.isFinite ? maximumMoon : -90,
            timeZoneIdentifier: place.timeZoneIdentifier,
            dayLengthChange: report.dayLengthChange(),
            milkyWay: report.milkyWayVisibility(),
            terrain: report.terrain())
    }
}

// MARK: - Formatting

/// Every figure on this screen goes through here, so that one place decides how
/// a time, a duration and an angle look, and so that all of them are expressed
/// in the selected place's own clock rather than the device's.
struct DataFormat: Sendable {

    let timeZone: TimeZone

    func time(_ julianDay: JulianDay?) -> String? {
        guard let julianDay else { return nil }
        return julianDay.date.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone))
    }

    func preciseTime(_ julianDay: JulianDay?) -> String? {
        guard let julianDay else { return nil }
        return julianDay.date.formatted(
            Date.FormatStyle(date: .omitted, time: .standard, timeZone: timeZone))
    }

    func dateAndTime(_ julianDay: JulianDay?) -> String? {
        guard let julianDay else { return nil }
        return julianDay.date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .standard, timeZone: timeZone))
    }

    func day(_ julianDay: JulianDay?) -> String? {
        guard let julianDay else { return nil }
        return julianDay.date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: timeZone))
    }

    func day(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: timeZone))
    }

    /// Hours and minutes, for a day length or a window.
    func span(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    /// Minutes and seconds, for the change from yesterday, signed.
    func shortSpan(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated))
    }

    func signedShortSpan(_ seconds: TimeInterval) -> String {
        let magnitude = shortSpan(abs(seconds))
        if seconds > 0 {
            return String(
                localized: "data.format.longer",
                defaultValue: "\(magnitude) longer",
                comment: "Day length change from yesterday when the days are drawing out")
        }
        if seconds < 0 {
            return String(
                localized: "data.format.shorter",
                defaultValue: "\(magnitude) shorter",
                comment: "Day length change from yesterday when the days are closing in")
        }
        return String(
            localized: "data.format.unchanged",
            defaultValue: "Unchanged",
            comment: "Day length is the same as yesterday to the second")
    }

    func degrees(_ value: Double?, fraction: Int = 1) -> String? {
        guard let value else { return nil }
        return value.formatted(.number.precision(.fractionLength(fraction))) + "\u{00B0}"
    }

    func spokenDegrees(_ value: Double?, fraction: Int = 1) -> String? {
        guard let value else { return nil }
        let figure = value.formatted(.number.precision(.fractionLength(fraction)))
        return String(
            localized: "data.format.degrees",
            defaultValue: "\(figure) degrees",
            comment: "Spoken form of an angle in degrees")
    }

    func percent(_ fraction: Double, digits: Int = 0) -> String {
        fraction.formatted(.percent.precision(.fractionLength(digits)))
    }

    func number(_ value: Double, fraction: Int = 0) -> String {
        value.formatted(.number.precision(.fractionLength(fraction)))
    }
}

// MARK: - Gates

/// Why a section is greyed. Each case carries its own sentence, because
/// "unavailable" tells a reader nothing and a section that simply vanishes
/// makes the free app look broken rather than free.
enum DataLock: Equatable {
    case capability(ProCapability)
    case selectionDate
    case selectionPlace

    var explanation: String {
        switch self {
        case .selectionDate:
            return String(
                localized: "data.lock.date",
                defaultValue: "Today at your current location is free, in full. Another date is part of Sunlit Pro.",
                comment: "Shown under a greyed section when a past or future date is selected")
        case .selectionPlace:
            return String(
                localized: "data.lock.place",
                defaultValue: "Today at your current location is free, in full. Another place is part of Sunlit Pro.",
                comment: "Shown under a greyed section when a place other than the device location is selected")
        case .capability(let capability):
            switch capability {
            case .moon:
                return String(
                    localized: "data.lock.moon",
                    defaultValue: "Moonrise, phase, illumination and distance are part of Sunlit Pro.",
                    comment: "Why the moon section is greyed")
            case .milkyWay:
                return String(
                    localized: "data.lock.milkyWay",
                    defaultValue: "The Milky Way window and its quality are part of Sunlit Pro.",
                    comment: "Why the Milky Way section is greyed")
            case .eclipses:
                return String(
                    localized: "data.lock.eclipses",
                    defaultValue: "Eclipses with local contact times are part of Sunlit Pro.",
                    comment: "Why the eclipse section is greyed")
            case .terrain:
                return String(
                    localized: "data.lock.terrain",
                    defaultValue: "The measured skyline and the periods it blocks the sun are part of Sunlit Pro.",
                    comment: "Why the obstruction section is greyed")
            case .annualPaths:
                return String(
                    localized: "data.lock.annualPaths",
                    defaultValue: "The sun's path across the whole year is part of Sunlit Pro.",
                    comment: "Why the annual curve is greyed")
            case .export:
                return String(
                    localized: "data.lock.export",
                    defaultValue: "Export to a spreadsheet or an image is part of Sunlit Pro.",
                    comment: "Why export is greyed")
            default:
                return String(
                    localized: "data.lock.generic",
                    defaultValue: "This is part of Sunlit Pro.",
                    comment: "Fallback reason a section is greyed")
            }
        }
    }
}

// MARK: - Section shell

/// A titled block of rows, greyed and explained when it is behind the purchase.
///
/// The explanation and the route out sit **below** the greyed rows rather than
/// floating over them. Text laid over a blurred readout cannot be held to the
/// contrast floor the palette guarantees, and the floor has no headroom.
struct DataSection<Content: View>: View {

    @Environment(\.solarAltitude) private var solarAltitude
    @Environment(\.displayScale) private var displayScale

    private let title: String
    private let caption: String?
    private let lock: DataLock?
    private let content: Content

    @State private var showingUnlock = false

    init(
        title: String,
        caption: String? = nil,
        lock: DataLock? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.caption = caption
        self.lock = lock
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(SunlitType.title)
                if let caption {
                    Text(caption)
                        .font(SunlitType.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            HairlineDivider()

            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .redacted(reason: lock == nil ? [] : .placeholder)
            .blur(radius: lock == nil ? 0 : 2)
            // A greyed readout must not be spoken. Without this VoiceOver reads
            // out the very figures the bars are hiding.
            .accessibilityHidden(lock != nil)
            .allowsHitTesting(lock == nil)

            if let lock {
                unlockBlock(lock)
            }
        }
        // The one shared purchase screen, not a copy of it. A second StoreKit
        // flow in this file wrote the entitlement to `ProGate` alone, which left
        // the app group the widget extension reads untouched and the widget
        // timelines unreloaded, so a purchase made from this tab unlocked the
        // app and not the widgets it had just been sold. It also carried no
        // terms or privacy link under its purchase button, which is the exact
        // omission that had a submission in this portfolio rejected.
        .sheet(isPresented: $showingUnlock) {
            PaywallView()
                .environment(\.solarAltitude, solarAltitude)
        }
    }

    private func unlockBlock(_ lock: DataLock) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "lock.fill")
                    .imageScale(.small)
                    .accessibilityHidden(true)
                Text(lock.explanation)
                    .font(SunlitType.body)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                showingUnlock = true
            } label: {
                Text(DataStrings.unlockButton)
                    .font(SunlitType.body)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(
                                SkyPalette.componentBorder(solarAltitude: solarAltitude),
                                lineWidth: 1 / displayScale)
                    }
                    // Inside the label, not outside the button. A minimum frame
                    // applied to a `Button` lays the button out inside a larger
                    // box without moving its hit region, which stays the label's
                    // own bounds: eleven points of padding either side of a body
                    // line is 42 points, and 42 is not 44.
                    .sunlitTouchTarget()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(DataStrings.unlockButton))
            .accessibilityHint(Text(lock.explanation))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Rows

/// A label, a figure, and the caption the figure may not travel without.
struct DataRow: View {

    @Environment(\.solarAltitude) private var solarAltitude

    let label: String
    let value: String
    var unit: String?
    /// Overrides what VoiceOver says for the figure. A time reads well as it is
    /// written; an angle does not, because the degree sign is a symbol.
    var spoken: String?
    /// Marks the row with the body it belongs to. Never the only carrier of
    /// meaning: the accents measure 1.00 to 1 against a day sky, so the label
    /// beside them is what a reader actually reads.
    var accent: Color?
    /// Sits under the row in full contrast. This is where a clear sky model
    /// says so, and it is also spoken, because a caption a screen reader skips
    /// is a caption that did not happen.
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(label).sunlitLabel()
                    Spacer(minLength: 8)
                    figure
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).sunlitLabel()
                    figure
                }
            }
            if let caption {
                Text(caption)
                    .font(SunlitType.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(spokenValue))
    }

    private var figure: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if let accent {
                Circle()
                    .fill(accent)
                    .overlay {
                        // An accent mark bottoms out at 1.00 to 1 against the
                        // sky it sits on, so it never carries meaning alone.
                        Circle().strokeBorder(
                            SkyPalette.foreground(solarAltitude: solarAltitude), lineWidth: 0.5)
                    }
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            }
            Text(value)
                .font(DataType.value)
            if let unit {
                Text(unit)
                    .font(SunlitType.caption)
            }
        }
    }

    private var spokenValue: String {
        var parts: [String] = []
        if let spoken {
            parts.append(spoken)
        } else if let unit {
            parts.append(value + " " + unit)
        } else {
            parts.append(value)
        }
        if let caption { parts.append(caption) }
        return parts.joined(separator: ". ")
    }
}

/// A sentence where figures would otherwise be.
///
/// Absent values are absent for a reason, and the reason is the information. A
/// polar day is not a blank and it is not a dash; it is a fact about the place
/// and the date, and it is written out.
struct DataNote: View {

    let text: String
    var label: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let label {
                Text(label).sunlitLabel()
            }
            Text(text)
                .font(SunlitType.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The row a table falls back to while its figures are still being computed.
struct DataLoadingRow: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(DataStrings.computing)
                .font(SunlitType.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Header and footer

/// Place, date and clock, written out in full. Not a control: the control is
/// the shared `GlobalHeader` at the top of this screen. This row exists because
/// the header abbreviates, and every figure below it is expressed in a clock
/// the header does not name.
struct DataContextRow: View {

    let place: Place
    let selected: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(place.name)
                .font(SunlitType.title)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(SunlitType.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let zone = TimeZone(identifier: place.timeZoneIdentifier) ?? .gmt
        let day = selected.formatted(
            Date.FormatStyle(date: .complete, time: .omitted, timeZone: zone))
        let zoneName = zone.localizedName(for: .generic, locale: .current) ?? place.timeZoneIdentifier
        return String(
            localized: "data.context.subtitle",
            defaultValue: "\(day). All times in \(zoneName).",
            comment: "Date and the clock every figure on the Data screen is expressed in")
    }
}

/// What the whole screen is, and what it is not.
struct DataFooter: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HairlineDivider()
            Text(DataStrings.footerOffline)
                .font(SunlitType.caption)
                .fixedSize(horizontal: false, vertical: true)
            Text(DataStrings.clearSkyModel)
                .font(SunlitType.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Type

/// The figure face for a tabulation. Body sized rather than the display face
/// the Sky view uses, because these numbers are read across a column and not
/// one at a time, and monospaced throughout so that the column lines up.
enum DataType {
    static let value = Font.system(.body, design: .default).weight(.medium).monospacedDigit()
}

// MARK: - Strings

/// Strings used in more than one place in this territory.
///
/// Held as computed properties rather than constants so each one is resolved in
/// the reader's current locale at the moment it is drawn, and written out with
/// literal keys so the compiler can extract them for the ten storefronts.
enum DataStrings {

    static var unlockButton: String {
        String(
            localized: "data.unlock.button",
            defaultValue: "See Sunlit Pro",
            comment: "Button under a greyed section that opens the purchase")
    }

    static var computing: String {
        String(
            localized: "data.loading",
            defaultValue: "Computing the day",
            comment: "Shown while the day report is being built")
    }

    static var clearSkyModel: String {
        String(
            localized: "data.model.clearSky",
            defaultValue: "UV index and irradiance are clear sky models, not measurements. They assume a cloudless atmosphere.",
            comment: "The caption that must accompany every modelled solar figure")
    }

    static var clearSkyShort: String {
        String(
            localized: "data.model.clearSkyShort",
            defaultValue: "Clear sky model, not a measurement",
            comment: "Short caption printed beside a modelled figure")
    }

    static var footerOffline: String {
        String(
            localized: "data.footer.offline",
            defaultValue: "Every figure here is computed on this device from the selected place and date. Nothing on this screen needs a network.",
            comment: "Footer of the Data screen")
    }

    static var done: String {
        String(localized: "data.done", defaultValue: "Done", comment: "Dismisses a sheet")
    }

    /// Stands in for a figure that has not been computed because the section is
    /// behind the purchase. Never visible: the section that shows it is
    /// redacted, so this is drawn as a grey bar of the right shape.
    static let placeholderTime = "00:00"
    static let placeholderFigure = "0.0"
}
