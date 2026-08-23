import Foundation
import SwiftUI
import WidgetKit
import SunlitCore

// MARK: - Where the widget gets its two facts

import CoreLocation
import StoreKit

/// The only two things the widget needs that it cannot compute: where the reader
/// is, and whether the purchase is present.
///
/// Neither crosses a process boundary, and that is deliberate. An app group would
/// work, but it cannot be provisioned from the App Store Connect API at all: there
/// is no /v1/appGroups endpoint, so the group can only be created by hand in the
/// developer portal, and until it exists every archive fails with "provisioning
/// profile doesn't support the group". Both facts are available to an extension
/// directly, so the group buys nothing and costs a manual step.
///
/// Every number the widgets show is computed here, in the extension, by
/// `SunlitCore`. Nothing is passed across from the app, because a widget that
/// renders a value the app wrote an hour ago is a widget that is wrong an hour
/// later.
///
/// The extension can afford this, but not carelessly. Measured with an optimised
/// build, one `DayReport` costs 52 ms at Berlin, 55 ms at Singapore and 74 ms at
/// Tromso, where the polar solver bisects harder, while one `SkyMoment` costs
/// 0.019 ms. So a timeline pays for at most two day reports and then thirty odd
/// instants for nothing, and `singleEntry` skips the second day when the figures on
/// screen all belong to today.
enum SunlitSharedStore {

    /// The reader's own location.
    ///
    /// A widget extension may read this when its Info.plist sets
    /// `NSWidgetWantsLocation` and the containing app holds when-in-use
    /// authorisation. The system hands over the last known fix rather than
    /// starting the hardware, which is exactly right here: a tenth of a degree of
    /// latitude moves sunrise by well under a minute, so a stale fix from across
    /// town is not a stale answer.
    ///
    /// Returns nil when authorisation has never been granted. Nil rather than a
    /// stand-in: the families with no room for a caption, `accessoryCircular` above
    /// all, would otherwise count down to a golden hour somewhere the reader has
    /// never been, with nothing on the tile to say so. That is a fabricated
    /// measurement wearing a real one's clothes.
    static func place() -> Place? {
        let manager = CLLocationManager()
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways,
              let fix = manager.location else {
            return nil
        }
        return Place(
            name: "",
            geographic: Coordinates.Geographic(
                latitude: fix.coordinate.latitude,
                longitude: fix.coordinate.longitude,
                // A negative altitude is CoreLocation saying it does not know,
                // not a place below sea level.
                elevation: fix.verticalAccuracy > 0 ? max(0, fix.altitude) : 0),
            // The device's own zone is the right one for the device's own
            // position, and it needs no network to resolve.
            timeZoneIdentifier: TimeZone.current.identifier,
            isCurrentLocation: true)
    }

    /// Whether `ProCapability.widgets` is unlocked.
    ///
    /// Read from StoreKit directly. `Transaction.currentEntitlements` is served by
    /// the system to any process in the app's group of targets, so the extension
    /// gets the same answer the app does without either of them writing it down,
    /// and there is no key for the two sides to disagree about. An earlier version
    /// passed it through shared defaults under two different key names and the
    /// purchase could never unlock a single tile.
    static func allowsWidgets() async -> Bool {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == "com.levinschwab.sunlit.pro",
               transaction.revocationDate == nil {
                return true
            }
        }
        return false
    }

    /// The Royal Observatory. Longitude zero by definition, which makes it the one
    /// coordinate on earth that is a statement rather than a guess.
    ///
    /// A stand-in for the gallery previews and for `placeholder(in:)`, which
    /// WidgetKit renders redacted. Never a substitute for the reader's own place on
    /// a live tile.
    static let fallbackPlace = Place(
        name: "Greenwich",
        geographic: Coordinates.Geographic(latitude: 51.4779, longitude: -0.0015, elevation: 47),
        timeZoneIdentifier: "Europe/London"
    )
}

// MARK: - Events

/// The sun events a widget can count down to.
///
/// First light and last light are the civil twilight bounds. That is the sense
/// photographers use the words in, and it is the bound at which a hand held frame
/// stops being possible, which is the question the widget is being asked.
enum SunEventKind {
    case firstLight
    case goldenHourStart
    case sunrise
    case goldenHourEnd
    case solarNoon
    case sunset
    case lastLight

    var symbolName: String {
        switch self {
        case .firstLight: return "sun.horizon"
        case .goldenHourStart: return "camera.filters"
        case .sunrise: return "sunrise.fill"
        case .goldenHourEnd: return "camera.filters"
        case .solarNoon: return "sun.max.fill"
        case .sunset: return "sunset.fill"
        case .lastLight: return "moon.stars.fill"
        }
    }

    /// The accent the glyph carries. Never the colour of a figure: the accents are
    /// hue signals and bottom out at 1.00 to 1 against a day sky, so anything a
    /// reader has to read stays in the audited foreground ink.
    var accent: Color {
        switch self {
        case .lastLight: return WidgetSky.moonAccent
        default: return WidgetSky.sunAccent
        }
    }

    var localisedName: String {
        switch self {
        case .firstLight:
            return String(localized: "widget.event.firstLight", defaultValue: "First light",
                          comment: "Name of the civil dawn event in a widget")
        case .goldenHourStart:
            return String(localized: "widget.event.goldenHourStart", defaultValue: "Golden hour",
                          comment: "Name of the moment golden hour begins, in a widget")
        case .sunrise:
            return String(localized: "widget.event.sunrise", defaultValue: "Sunrise",
                          comment: "Name of the sunrise event in a widget")
        case .goldenHourEnd:
            return String(localized: "widget.event.goldenHourEnd", defaultValue: "Golden hour ends",
                          comment: "Name of the moment golden hour finishes, in a widget")
        case .solarNoon:
            return String(localized: "widget.event.solarNoon", defaultValue: "Solar noon",
                          comment: "Name of the solar transit event in a widget")
        case .sunset:
            return String(localized: "widget.event.sunset", defaultValue: "Sunset",
                          comment: "Name of the sunset event in a widget")
        case .lastLight:
            return String(localized: "widget.event.lastLight", defaultValue: "Last light",
                          comment: "Name of the civil dusk event in a widget")
        }
    }
}

struct SunEvent {
    let kind: SunEventKind
    let date: Date
}

/// A golden hour, as an interval rather than a point, because the ring shows a
/// position inside it as well as a wait for it.
struct GoldenWindow {
    let start: Date
    let end: Date

    func isUnderway(at instant: Date) -> Bool {
        instant >= start && instant < end
    }
}

// MARK: - The entry

/// Everything one rendered frame of any of the four widgets needs.
///
/// Flat on purpose. WidgetKit archives the entry with the view, so anything held here
/// is paid for once per entry and never recomputed at draw time.
struct SunlitEntry: TimelineEntry {
    let date: Date

    let placeName: String
    let timeZone: TimeZone
    /// Southern hemisphere places see the moon's terminator on the other side, and
    /// SF Symbols carries an `.inverse` variant for exactly that.
    let latitude: Double

    /// `ProCapability.widgets`.
    let isUnlocked: Bool

    /// True when the app has never shared a place, so there is nothing to compute
    /// and nothing below this line means anything. Every view branches on it before
    /// it reads a figure.
    let needsSetup: Bool

    // The sky at `date`.
    let solarAltitude: Double
    let solarAzimuth: Double
    let sunIsUp: Bool
    let moonAltitude: Double
    let moonIlluminatedFraction: Double
    let moonPhaseName: MoonPosition.Phase.Name

    // The day that contains `date`, in the place's own time zone.
    let sunrise: Date?
    let sunset: Date?
    let isPolarDay: Bool
    let isPolarNight: Bool

    let nextEvent: SunEvent?
    /// The golden hour that is running now, or the next one.
    let goldenWindow: GoldenWindow?

    // MARK: Formatting

    /// Times are printed in the place's own zone, not the device's. A user in Berlin
    /// looking at Tokyo wants Tokyo's sunrise on Tokyo's clock, and the header in the
    /// app already works that way.
    func timeText(_ instant: Date) -> String {
        instant.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone))
    }

    /// Fraction of the way from sunrise to sunset, or nil when the day has no such
    /// span to be a fraction of.
    ///
    /// Optional rather than a number with a fallback, and that is the whole point.
    /// This returned 0.5 on a polar day, which put the sun marker at the apex of an
    /// arc that does not exist: a position nothing measured, drawn as though something
    /// had. It returned 0 on the day a polar day begins, where there is a sunrise and
    /// no sunset, which pinned the marker to the left end for twenty four hours. Where
    /// there is no sunrise and sunset pair there is no arc, and the widget says so in
    /// words instead of drawing one.
    var arcProgress: Double? {
        guard let sunrise, let sunset, sunset > sunrise else { return nil }
        let span = sunset.timeIntervalSince(sunrise)
        let travelled = date.timeIntervalSince(sunrise)
        return min(max(travelled / span, 0), 1)
    }

    /// The moonlight the sky gradient is lifted by.
    ///
    /// Gated on the moon actually being above the horizon, which is what
    /// `SkyView.moonlight` in the app does. The background is a readout, so a widget
    /// that paints a moonlit night while the moon is down is reporting something that
    /// is not happening, and it disagrees with the app for the same instant.
    var skyMoonIllumination: Double {
        moonAltitude > 0 ? moonIlluminatedFraction : 0
    }

    /// How far ahead an instant is, measured from this entry rather than from the
    /// clock at render time.
    ///
    /// WidgetKit renders a timeline ahead of showing it, so a phrase built against
    /// `Date.now` inside a view body can be hours stale by the time VoiceOver reads
    /// it. Anchoring to the entry's own instant bounds the error by the gap to the
    /// next entry, which is at most `SunlitEntryBuilder.cadence`.
    func aheadText(_ instant: Date) -> String {
        let seconds = max(instant.timeIntervalSince(date), 0)
        return Duration.seconds(seconds).formatted(
            .units(allowed: [.hours, .minutes], width: .wide))
    }

    var moonIlluminationText: String {
        moonIlluminatedFraction.formatted(.percent.precision(.fractionLength(0)))
    }

    var altitudeText: String {
        solarAltitude.formatted(.number.precision(.fractionLength(1)))
    }

    var azimuthText: String {
        solarAzimuth.formatted(.number.precision(.fractionLength(0)))
    }

    /// What to say when there is no next event at all, which happens inside the polar
    /// circles and is a fact about the sun rather than a gap in the data. Showing a
    /// dash here would be a lie by omission.
    var polarExplanation: String? {
        if isPolarDay {
            return String(localized: "widget.polar.day", defaultValue: "The sun stays up all day",
                          comment: "Shown in a widget on a polar day, when there is no sunrise or sunset")
        }
        if isPolarNight {
            return String(localized: "widget.polar.night", defaultValue: "The sun stays down all day",
                          comment: "Shown in a widget during polar night, when there is no sunrise or sunset")
        }
        return nil
    }

    /// What to print where a sunrise time would go when the sun does not rise.
    ///
    /// Separate from the sunset case because they are separate facts, and on the day a
    /// polar day begins exactly one of them is true. Printing "no sunrise or sunset
    /// today" on a day that had a sunrise is a false statement, and printing the word
    /// "Sunrise" where a time belongs is a label wearing a readout's clothes. Both of
    /// those were being printed.
    var sunriseAbsenceText: String {
        polarExplanation ?? String(
            localized: "widget.sun.noSunrise", defaultValue: "The sun does not rise today",
            comment: "Shown in a widget on a day with no sunrise but a sunset, at the Arctic Circle")
    }

    var sunsetAbsenceText: String {
        polarExplanation ?? String(
            localized: "widget.sun.noSunset", defaultValue: "The sun does not set today",
            comment: "Shown in a widget on a day with a sunrise but no sunset, at the Arctic Circle")
    }

    /// What to print when the day has neither bound.
    var dayAbsenceText: String {
        polarExplanation ?? String(
            localized: "widget.sun.neither", defaultValue: "No sunrise or sunset today",
            comment: "Shown in a widget when the sun crosses the horizon at neither end of the day")
    }

    var moonPhaseText: String {
        switch moonPhaseName {
        case .newMoon:
            return String(localized: "widget.moon.newMoon", defaultValue: "New moon",
                          comment: "Moon phase name in a widget")
        case .waxingCrescent:
            return String(localized: "widget.moon.waxingCrescent", defaultValue: "Waxing crescent",
                          comment: "Moon phase name in a widget")
        case .firstQuarter:
            return String(localized: "widget.moon.firstQuarter", defaultValue: "First quarter",
                          comment: "Moon phase name in a widget")
        case .waxingGibbous:
            return String(localized: "widget.moon.waxingGibbous", defaultValue: "Waxing gibbous",
                          comment: "Moon phase name in a widget")
        case .fullMoon:
            return String(localized: "widget.moon.fullMoon", defaultValue: "Full moon",
                          comment: "Moon phase name in a widget")
        case .waningGibbous:
            return String(localized: "widget.moon.waningGibbous", defaultValue: "Waning gibbous",
                          comment: "Moon phase name in a widget")
        case .lastQuarter:
            return String(localized: "widget.moon.lastQuarter", defaultValue: "Last quarter",
                          comment: "Moon phase name in a widget")
        case .waningCrescent:
            return String(localized: "widget.moon.waningCrescent", defaultValue: "Waning crescent",
                          comment: "Moon phase name in a widget")
        }
    }

    var moonSymbolName: String {
        let base: String
        switch moonPhaseName {
        case .newMoon: base = "moonphase.new.moon"
        case .waxingCrescent: base = "moonphase.waxing.crescent"
        case .firstQuarter: base = "moonphase.first.quarter"
        case .waxingGibbous: base = "moonphase.waxing.gibbous"
        case .fullMoon: base = "moonphase.full.moon"
        case .waningGibbous: base = "moonphase.waning.gibbous"
        case .lastQuarter: base = "moonphase.last.quarter"
        case .waningCrescent: base = "moonphase.waning.crescent"
        }
        return latitude < 0 ? base + ".inverse" : base
    }
}

// MARK: - Building entries

/// The arithmetic behind every entry, kept out of the provider so that the four
/// widgets and the gallery previews all go through one path.
enum SunlitEntryBuilder {

    /// How far ahead one timeline reaches. Sixteen hours means the extension is asked
    /// for a new timeline between one and two times a day, which sits far inside the
    /// refresh budget while still covering a full waking day from any starting point.
    static let horizon: TimeInterval = 16 * 3600

    /// The background cadence between events.
    ///
    /// The events themselves are the point of the timeline, and they land exactly:
    /// a sunrise widget that ticks over at 06:07 for an 06:04 sunrise reads as broken.
    /// But the medium family draws the sun's position on the arc, and a marker that
    /// only moves at events would sit still for hours in the middle of the day. So a
    /// slow cadence fills the gaps, and any cadence point that lands near an event is
    /// discarded in the event's favour, so the exact instant is never displaced by an
    /// approximate one. Thirty minutes moves the marker by about two percent of the
    /// arc's width, which is below what the eye reads as stale.
    static let cadence: TimeInterval = 30 * 60

    /// How close a cadence point has to be to an event before it is dropped.
    static let eventGuard: TimeInterval = 6 * 60

    /// Upper bound on entries in one timeline, so a pathological horizon cannot
    /// balloon the archive WidgetKit has to hold.
    static let entryLimit = 64

    // MARK: Day reports

    /// The day that contains `instant`, and the one after it.
    ///
    /// Two days rather than one because the widget must always be able to name a next
    /// event: at 22:00 every event of today is behind us, and because a sixteen hour
    /// timeline crosses midnight from any evening starting point.
    static func reports(covering instant: Date, place: Place) -> [DayReport] {
        let start = place.startOfLocalDay(containing: instant)
        return [
            report(date: start, place: place),
            report(date: start.adding(days: 1), place: place)
        ]
    }

    // MARK: The report memo

    /// One process local cache of day reports, keyed by place and local day.
    ///
    /// WidgetKit asks all four widgets for a placeholder, a snapshot and a timeline in
    /// the same extension process, and each of those asks for the same one or two days
    /// at the same place. Without this, opening the gallery paid for up to eight day
    /// reports on the calling thread at 52 to 81 ms each. With it, it pays for two.
    ///
    /// Bounded and short lived: a widget process lives for seconds, so a cached report
    /// cannot outlive the day it belongs to. The lock is here because nothing
    /// documents which queue WidgetKit calls a `TimelineProvider` on, and being wrong
    /// about that is a data race rather than a slow path.
    private final class ReportCache {
        private struct Key: Hashable {
            let place: UUID
            let latitude: Double
            let longitude: Double
            let day: Double
        }

        private let lock = NSLock()
        private var stored: [Key: DayReport] = [:]
        private var order: [Key] = []
        private let limit = 4

        func report(date: JulianDay, place: Place) -> DayReport {
            let key = Key(
                place: place.id,
                latitude: place.latitude,
                longitude: place.longitude,
                day: date.value)

            lock.lock()
            let hit = stored[key]
            lock.unlock()
            if let hit { return hit }

            // Computed outside the lock. Holding a mutex across eighty milliseconds of
            // arithmetic to save a duplicated computation in a race that costs one
            // duplicated computation is a bad trade.
            let computed = DayReport.compute(date: date, place: place)

            lock.lock()
            if stored[key] == nil {
                stored[key] = computed
                order.append(key)
                while order.count > limit {
                    stored.removeValue(forKey: order.removeFirst())
                }
            }
            lock.unlock()
            return computed
        }
    }

    private static let cache = ReportCache()

    /// One day report, taken from the process cache when it is already there.
    static func report(date: JulianDay, place: Place) -> DayReport {
        cache.report(date: date, place: place)
    }

    /// The report whose local day contains `instant`.
    static func report(containing instant: Date, in reports: [DayReport]) -> DayReport? {
        reports.last { $0.date.date <= instant } ?? reports.first
    }

    static func events(in report: DayReport) -> [SunEvent] {
        var found: [SunEvent] = []
        if let value = report.phases.civilDawn {
            found.append(SunEvent(kind: .firstLight, date: value.date))
        }
        if let window = report.goldenHour.morning {
            found.append(SunEvent(kind: .goldenHourStart, date: window.start.date))
            found.append(SunEvent(kind: .goldenHourEnd, date: window.end.date))
        }
        if let value = report.phases.sunrise {
            found.append(SunEvent(kind: .sunrise, date: value.date))
        }
        if let value = report.phases.solarNoon {
            found.append(SunEvent(kind: .solarNoon, date: value.date))
        }
        if let value = report.phases.sunset {
            found.append(SunEvent(kind: .sunset, date: value.date))
        }
        if let window = report.goldenHour.evening {
            found.append(SunEvent(kind: .goldenHourStart, date: window.start.date))
            found.append(SunEvent(kind: .goldenHourEnd, date: window.end.date))
        }
        if let value = report.phases.civilDusk {
            found.append(SunEvent(kind: .lastLight, date: value.date))
        }
        return found.sorted { $0.date < $1.date }
    }

    static func events(in reports: [DayReport]) -> [SunEvent] {
        reports.flatMap { events(in: $0) }.sorted { $0.date < $1.date }
    }

    static func goldenWindows(in reports: [DayReport]) -> [GoldenWindow] {
        reports
            .flatMap { report -> [GoldenHour.Window] in
                [report.goldenHour.morning, report.goldenHour.evening].compactMap { $0 }
            }
            .map { GoldenWindow(start: $0.start.date, end: $0.end.date) }
            .sorted { $0.start < $1.start }
    }

    // MARK: One entry

    static func entry(
        at instant: Date,
        place: Place,
        isUnlocked: Bool,
        reports: [DayReport],
        events: [SunEvent],
        goldenWindows: [GoldenWindow]
    ) -> SunlitEntry {
        let moment = SkyMoment.at(JulianDay(date: instant), place: place)
        let day = report(containing: instant, in: reports)

        return SunlitEntry(
            date: instant,
            placeName: place.name,
            timeZone: TimeZone(identifier: place.timeZoneIdentifier) ?? .gmt,
            latitude: place.latitude,
            isUnlocked: isUnlocked,
            needsSetup: false,
            solarAltitude: moment.sun.altitude,
            solarAzimuth: moment.sun.azimuth,
            sunIsUp: moment.sunIsUp,
            moonAltitude: moment.moon.altitude,
            moonIlluminatedFraction: moment.moonPhase.illuminatedFraction,
            moonPhaseName: moment.moonPhase.name,
            sunrise: day?.phases.sunrise?.date,
            sunset: day?.phases.sunset?.date,
            isPolarDay: day?.phases.polarDay ?? false,
            isPolarNight: day?.phases.polarNight ?? false,
            nextEvent: events.first { $0.date > instant },
            goldenWindow: goldenWindows.first { $0.end > instant }
        )
    }

    /// One entry for right now, for the placeholder and the snapshot.
    ///
    /// Unlike the timeline this computes the second day only when it has to. A day
    /// report is the expensive thing in the extension by three orders of magnitude:
    /// measured on this machine it is 52 to 81 ms against 0.019 ms for one
    /// `SkyMoment`. `placeholder(in:)` is called while the gallery is being scrolled,
    /// so paying for tomorrow at ten in the morning, when every figure on screen
    /// belongs to today, is a cost with nothing behind it.
    static func singleEntry(at instant: Date, place: Place, isUnlocked: Bool) -> SunlitEntry {
        let start = place.startOfLocalDay(containing: instant)
        var days = [report(date: start, place: place)]
        var found = events(in: days)
        var windows = goldenWindows(in: days)

        // In the evening both the next event and the next golden hour are tomorrow's,
        // and only then is the second day worth its cost.
        let needsTomorrow = !found.contains { $0.date > instant }
            || !windows.contains { $0.end > instant }
        if needsTomorrow {
            days.append(report(date: start.adding(days: 1), place: place))
            found = events(in: days)
            windows = goldenWindows(in: days)
        }

        return entry(
            at: instant,
            place: place,
            isUnlocked: isUnlocked,
            reports: days,
            events: found,
            goldenWindows: windows
        )
    }

    /// The entry for "the app has never shared a place".
    ///
    /// Every figure in it is zero and no view may read one: each of the four branches
    /// on `needsSetup` before it touches a number. The zeros are not a measurement and
    /// are never drawn as one.
    static func setupEntry(at instant: Date, isUnlocked: Bool = false) -> SunlitEntry {
        SunlitEntry(
            date: instant,
            placeName: "",
            timeZone: .current,
            latitude: 0,
            isUnlocked: isUnlocked,
            needsSetup: true,
            solarAltitude: 0,
            solarAzimuth: 0,
            sunIsUp: false,
            moonAltitude: 0,
            moonIlluminatedFraction: 0,
            moonPhaseName: .newMoon,
            sunrise: nil,
            sunset: nil,
            isPolarDay: false,
            isPolarNight: false,
            nextEvent: nil,
            goldenWindow: nil)
    }

    // MARK: Instants

    /// The instants the timeline holds entries for: now, every event ahead of us
    /// inside the horizon, and a slow cadence between them.
    static func instants(from now: Date, events: [SunEvent]) -> [Date] {
        let end = now.addingTimeInterval(horizon)
        let eventDates = events.map(\.date).filter { $0 > now && $0 <= end }

        var candidates: [Date] = [now]
        candidates.append(contentsOf: eventDates)

        var tick = now.addingTimeInterval(cadence)
        while tick <= end {
            let clashesWithEvent = eventDates.contains { abs($0.timeIntervalSince(tick)) < eventGuard }
            if !clashesWithEvent {
                candidates.append(tick)
            }
            tick = tick.addingTimeInterval(cadence)
        }

        candidates.sort()

        // Collapse anything the sort left within a second of its neighbour, which is
        // what two twilight bounds meeting at the same instant look like at a solstice.
        var deduplicated: [Date] = []
        for candidate in candidates {
            if let previous = deduplicated.last, candidate.timeIntervalSince(previous) < 1 {
                continue
            }
            deduplicated.append(candidate)
        }

        return Array(deduplicated.prefix(entryLimit))
    }
}

// MARK: - The provider

struct SunlitTimelineProvider: TimelineProvider {

    /// A stand in, which WidgetKit renders redacted.
    ///
    /// It uses the reader's own place when there is one, so the gallery shows the
    /// right shape, and Greenwich when there is not, because a redacted placeholder
    /// carries no figure a reader can act on. Both go through the report memo, so the
    /// four widgets in the gallery share one computation rather than paying for eight.
    func placeholder(in context: Context) -> SunlitEntry {
        // Synchronous by protocol, and rendered redacted by WidgetKit, so the
        // entitlement it carries is never read by anything a person sees.
        // Asking StoreKit here would mean blocking on an async sequence inside a
        // synchronous callback, which is how a provider deadlocks.
        SunlitEntryBuilder.singleEntry(
            at: Date(),
            place: SunlitSharedStore.place() ?? SunlitSharedStore.fallbackPlace,
            isUnlocked: false
        )
    }

    /// The gallery.
    ///
    /// This is where the install decision is made, so it shows the real place, the
    /// real sky, and the real figures rather than a stub. It also honours the
    /// entitlement: a gallery that shows the unlocked widget to someone who has not
    /// bought it promises something they will not get when they place it, and this
    /// portfolio has already paid for promising a feature the delivered app did not
    /// show. The locked appearance is designed to survive that: the real gradient,
    /// the real structure, one honest line.
    func getSnapshot(in context: Context, completion: @escaping (SunlitEntry) -> Void) {
        let now = Date()
        Task {
            let isUnlocked = await SunlitSharedStore.allowsWidgets()
            guard let place = SunlitSharedStore.place() else {
                completion(SunlitEntryBuilder.setupEntry(at: now, isUnlocked: isUnlocked))
                return
            }
            completion(
                SunlitEntryBuilder.singleEntry(at: now, place: place, isUnlocked: isUnlocked))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SunlitEntry>) -> Void) {
        let now = Date()
        Task {
            let isUnlocked = await SunlitSharedStore.allowsWidgets()
            buildTimeline(at: now, isUnlocked: isUnlocked, completion: completion)
        }
    }

    private func buildTimeline(
        at now: Date,
        isUnlocked: Bool,
        completion: @escaping (Timeline<SunlitEntry>) -> Void
    ) {
        // Location has never been authorised, so there is nothing truthful to
        // compute and nothing to count down to. One entry, and an hourly backstop:
        // the app calls WidgetCenter.shared.reloadAllTimelines() the moment
        // authorisation changes, and this is only what happens if it does not.
        guard let place = SunlitSharedStore.place() else {
            completion(Timeline(
                entries: [SunlitEntryBuilder.setupEntry(at: now, isUnlocked: isUnlocked)],
                policy: .after(now.addingTimeInterval(3600))))
            return
        }

        let reports = SunlitEntryBuilder.reports(covering: now, place: place)
        let events = SunlitEntryBuilder.events(in: reports)
        let windows = SunlitEntryBuilder.goldenWindows(in: reports)

        let entries = SunlitEntryBuilder.instants(from: now, events: events).map {
            SunlitEntryBuilder.entry(
                at: $0,
                place: place,
                isUnlocked: isUnlocked,
                reports: reports,
                events: events,
                goldenWindows: windows
            )
        }

        guard let last = entries.last else {
            let single = SunlitEntryBuilder.singleEntry(at: now, place: place, isUnlocked: isUnlocked)
            completion(Timeline(entries: [single], policy: .after(now.addingTimeInterval(3600))))
            return
        }

        completion(Timeline(entries: entries, policy: .after(last.date)))
    }
}

// MARK: - The sky, in the extension

/// The adaptive sky, ported for the widget target.
///
/// This is a deliberate mirror of `Sources/Sunlit/Design/SkyPalette.swift`, not a
/// second design. The widget extension links `SunlitCore` and nothing from the app
/// target, so the palette cannot be shared without moving it into the core, and the
/// core is Foundation only by a hard rule. The anchors, the horizon bias, the stop
/// count and the ink crossover are copied exactly; change one there and change it
/// here, because the contrast audit that proves 4.55 to 1 at the worst altitude lives
/// with the original and measures these same numbers.
enum WidgetSky {

    struct LinearRGB {
        var red: Double
        var green: Double
        var blue: Double

        init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        init(hex: UInt32) {
            self.init(
                red: Self.linearised(Double((hex >> 16) & 0xFF) / 255),
                green: Self.linearised(Double((hex >> 8) & 0xFF) / 255),
                blue: Self.linearised(Double(hex & 0xFF) / 255)
            )
        }

        static func linearised(_ channel: Double) -> Double {
            let c = min(max(channel, 0), 1)
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }

        static func encoded(_ channel: Double) -> Double {
            let c = min(max(channel, 0), 1)
            return c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
        }

        var color: Color {
            Color(
                .sRGB,
                red: Self.encoded(red),
                green: Self.encoded(green),
                blue: Self.encoded(blue),
                opacity: 1
            )
        }
    }

    /// Oklab, so a mid point between two anchors looks like a mid point. Mixing the
    /// gamma encoded components instead sends violet to amber through a dead grey,
    /// which is the muddy band the adaptive sky must not have.
    struct Oklab {
        var l: Double
        var a: Double
        var b: Double
    }

    static func oklab(_ rgb: LinearRGB) -> Oklab {
        let l = 0.4122214708 * rgb.red + 0.5363325363 * rgb.green + 0.0514459929 * rgb.blue
        let m = 0.2119034982 * rgb.red + 0.6806995451 * rgb.green + 0.1073969566 * rgb.blue
        let s = 0.0883024619 * rgb.red + 0.2817188376 * rgb.green + 0.6299787005 * rgb.blue
        let lr = cbrt(l), mr = cbrt(m), sr = cbrt(s)
        return Oklab(
            l: 0.2104542553 * lr + 0.7936177850 * mr - 0.0040720468 * sr,
            a: 1.9779984951 * lr - 2.4285922050 * mr + 0.4505937099 * sr,
            b: 0.0259040371 * lr + 0.7827717662 * mr - 0.8086757660 * sr
        )
    }

    static func linear(_ lab: Oklab) -> LinearRGB {
        let lr = lab.l + 0.3963377774 * lab.a + 0.2158037573 * lab.b
        let mr = lab.l - 0.1055613458 * lab.a - 0.0638541728 * lab.b
        let sr = lab.l - 0.0894841775 * lab.a - 1.2914855480 * lab.b
        let l = lr * lr * lr, m = mr * mr * mr, s = sr * sr * sr
        return LinearRGB(
            red: min(max(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s, 0), 1),
            green: min(max(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s, 0), 1),
            blue: min(max(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s, 0), 1)
        )
    }

    static func mix(_ x: LinearRGB, _ y: LinearRGB, _ t: Double) -> LinearRGB {
        let f = min(max(t, 0), 1)
        let a = oklab(x), b = oklab(y)
        return linear(Oklab(
            l: a.l + (b.l - a.l) * f,
            a: a.a + (b.a - a.a) * f,
            b: a.b + (b.b - a.b) * f
        ))
    }

    private struct Anchor {
        let altitude: Double
        let top: LinearRGB
        let bottom: LinearRGB
    }

    private static let anchors: [Anchor] = [
        Anchor(altitude: -18, top: LinearRGB(hex: 0x070B18), bottom: LinearRGB(hex: 0x0D1430)),
        Anchor(altitude: -6, top: LinearRGB(hex: 0x2F2047), bottom: LinearRGB(hex: 0x6F386B)),
        Anchor(altitude: -4, top: LinearRGB(hex: 0x93678F), bottom: LinearRGB(hex: 0xAF5F51)),
        Anchor(altitude: 0, top: LinearRGB(hex: 0xAC6E91), bottom: LinearRGB(hex: 0xE9956F)),
        Anchor(altitude: 6, top: LinearRGB(hex: 0xCD7B5F), bottom: LinearRGB(hex: 0xF6BC4F)),
        Anchor(altitude: 14, top: LinearRGB(hex: 0x7684B7), bottom: LinearRGB(hex: 0x8BD4EC)),
        Anchor(altitude: 30, top: LinearRGB(hex: 0x2E7FD4), bottom: LinearRGB(hex: 0x9FD3F5))
    ]

    private static let moonlitTop = LinearRGB(hex: 0x1C203B)
    private static let moonlitBottom = LinearRGB(hex: 0x2F3B62)

    static let stopCount = 9
    private static let horizonBias = 1.4

    /// The altitude at which the ink flips from white to black. Copied from
    /// `SkyPalette.inkCrossoverAltitude`.
    static let inkCrossoverAltitude: Double = -4

    static let sunAccent = LinearRGB(hex: 0xFFB020).color
    static let moonAccent = LinearRGB(hex: 0x8FB8FF).color

    /// The panel behind the setup state.
    ///
    /// Flat, and deliberately not a sky. The gradient is a readout of a solar altitude
    /// at a place, and in the setup state there is no place, so painting one would be
    /// reporting a sky nobody is under. White ink measures 18.1 to 1 on it.
    static let setupBackground = LinearRGB(hex: 0x12161F).color
    static let setupInk = LinearRGB(hex: 0xFFFFFF).color

    static func gradient(solarAltitude: Double, moonIllumination: Double = 0) -> LinearGradient {
        let colours = skyColours(solarAltitude: solarAltitude, moonIllumination: moonIllumination)
        let stops = colours.enumerated().map {
            Gradient.Stop(color: $0.element.color, location: CGFloat($0.offset) / CGFloat(stopCount - 1))
        }
        return LinearGradient(gradient: Gradient(stops: stops), startPoint: .top, endPoint: .bottom)
    }

    /// The ink for every figure and rule laid over that sky. Drawn at full strength:
    /// the audited floor has no headroom at the crossover, so a fade of even one tenth
    /// breaks it. Hierarchy comes from size, weight and tracking instead.
    static func foreground(solarAltitude: Double) -> Color {
        solarAltitude < inkCrossoverAltitude
            ? LinearRGB(hex: 0xFFFFFF).color
            : LinearRGB(hex: 0x000000).color
    }

    /// Rules and inactive tracks. Separators only, never the visible boundary of a
    /// control, which is the restriction the app's palette documents.
    static func instrumentLine(solarAltitude: Double) -> Color {
        foreground(solarAltitude: solarAltitude).opacity(0.55)
    }

    static func skyColours(solarAltitude: Double, moonIllumination: Double) -> [LinearRGB] {
        var (top, bottom) = pair(solarAltitude: solarAltitude)
        let lift = nightWeight(solarAltitude) * min(max(moonIllumination, 0), 1) * 0.9
        if lift > 0 {
            top = mix(top, moonlitTop, lift)
            bottom = mix(bottom, moonlitBottom, lift)
        }
        return (0..<stopCount).map { index in
            let t = Double(index) / Double(stopCount - 1)
            return mix(top, bottom, pow(t, horizonBias))
        }
    }

    private static func pair(solarAltitude: Double) -> (top: LinearRGB, bottom: LinearRGB) {
        guard let first = anchors.first, let last = anchors.last else {
            return (LinearRGB(hex: 0x000000), LinearRGB(hex: 0x000000))
        }
        if solarAltitude <= first.altitude { return (first.top, first.bottom) }
        if solarAltitude >= last.altitude { return (last.top, last.bottom) }
        for index in 0..<(anchors.count - 1) {
            let lower = anchors[index], upper = anchors[index + 1]
            guard solarAltitude <= upper.altitude else { continue }
            let t = smoothstep((solarAltitude - lower.altitude) / (upper.altitude - lower.altitude))
            return (mix(lower.top, upper.top, t), mix(lower.bottom, upper.bottom, t))
        }
        return (last.top, last.bottom)
    }

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

// MARK: - Shared widget furniture

/// The day's arc: half a sine across the width, which is what a solar path projects
/// to on a flat panel, with the horizon as its baseline. Mirrors `ArcTrackShape`.
enum WidgetArc {

    static func path(in rect: CGRect, from start: Double, to end: Double) -> Path {
        var path = Path()
        let lower = min(max(start, 0), 1)
        let upper = min(max(end, 0), 1)
        guard upper > lower else { return path }
        let steps = 64
        for step in 0...steps {
            let t = lower + (upper - lower) * Double(step) / Double(steps)
            let point = self.point(at: t, in: rect)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }

    static func point(at fraction: Double, in rect: CGRect) -> CGPoint {
        let t = min(max(fraction, 0), 1)
        return CGPoint(
            x: rect.minX + rect.width * t,
            y: rect.maxY - rect.height * sin(.pi * t)
        )
    }
}

/// A small tracked label, matching the app's instrument layer. Uppercasing is visual
/// only: every caller carries its own accessibility label built from the original.
extension View {
    func widgetLabelStyle() -> some View {
        font(.system(.caption2, design: .default).weight(.medium))
            .textCase(.uppercase)
            .tracking(0.4)
    }

    /// A figure. Monospaced digits, because a ticking countdown that reflows on every
    /// frame makes the whole instrument layer twitch.
    func widgetFigureStyle(_ style: Font.TextStyle = .title2) -> some View {
        font(.system(style, design: .default).weight(.medium).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

/// The locked treatment for the system families.
///
/// The rule this satisfies: a gated feature shows what it would show, obscured, with
/// an explanation and a route to the paywall. It never vanishes and it never invents
/// a number, because a widget that disappears makes the free app look broken and a
/// widget full of plausible fiction is worse than either.
struct LockedSystemWidget<Content: View>: View {
    let solarAltitude: Double
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            content
                .blur(radius: 6)
                .opacity(0.5)
                .accessibilityHidden(true)

            VStack(spacing: 4) {
                Image(systemName: "lock.fill")
                    .imageScale(.medium)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(.footnote, design: .default).weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(explanation)
                    .font(.system(.caption2, design: .default))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 4)
            .foregroundStyle(WidgetSky.foreground(solarAltitude: solarAltitude))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text(explanation))
    }

    private var title: String {
        String(localized: "widget.locked.title", defaultValue: "Unlock in Sunlit",
               comment: "Headline of the locked state of a widget, shown when the purchase is absent")
    }

    private var explanation: String {
        String(localized: "widget.locked.body", defaultValue: "Widgets are part of the one purchase.",
               comment: "Explanation in the locked state of a widget")
    }
}

/// What every family shows before the app has shared a place.
///
/// Not a lock and not an error. There is simply nothing measured yet, and the honest
/// thing is to say which one action produces it. It carries its own background rather
/// than a sky, because a sky here would be a readout of a place that does not exist.
struct SetupPromptView: View {
    /// True only on `accessoryCircular`, which is a 72 point disc: a sentence does not
    /// fit in it at any text size, so the badge names the action in two words and
    /// VoiceOver gets the whole thing from the label and hint below.
    var compact: Bool = false

    var body: some View {
        Group {
            if compact {
                VStack(spacing: 1) {
                    Image(systemName: "sun.horizon")
                        .imageScale(.small)
                        .accessibilityHidden(true)
                    Text(shortTitle)
                        .font(.system(.caption2, design: .default))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "sun.horizon")
                        .imageScale(.medium)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.system(.footnote, design: .default).weight(.semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .multilineTextAlignment(.center)
                    Text(explanation)
                        .font(.system(.caption2, design: .default))
                        .lineLimit(4)
                        .minimumScaleFactor(0.6)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 4)
                .foregroundStyle(WidgetSky.setupInk)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text(explanation))
    }

    var title: String {
        String(localized: "widget.setup.title", defaultValue: "Open Sunlit",
               comment: "Headline shown on a widget before the app has shared a place with it")
    }

    var shortTitle: String {
        String(localized: "widget.setup.short", defaultValue: "Open app",
               comment: "Two word prompt on the circular lock screen widget before the app has shared a place")
    }

    var explanation: String {
        String(
            localized: "widget.setup.body",
            defaultValue: "Choose a place in the app and this widget follows it.",
            comment: "Explanation shown on a widget before the app has shared a place with it")
    }
}

/// Where a tap goes.
enum SunlitWidgetLink {
    static let sky = URL(string: "sunlit://sky")
    static let paywall = URL(string: "sunlit://paywall")

    /// The paywall only when there is something to unlock. A tile that has no place
    /// yet is not a locked feature, and sending that tap to a purchase sheet asks for
    /// money to fix something money does not fix.
    static func destination(for entry: SunlitEntry) -> URL? {
        if entry.needsSetup { return sky }
        return entry.isUnlocked ? sky : paywall
    }
}
