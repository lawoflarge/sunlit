import SwiftUI
import UIKit
import UserNotifications
import SunlitCore

// MARK: - Preferences

/// Metric or imperial, for the two quantities in the app that have a choice:
/// shadow length and elevation. Angles are degrees everywhere, because there is
/// no imperial degree, and times follow the locale.
enum SunlitUnits: String, CaseIterable, Sendable {
    case metric
    case imperial
}

/// The clock. `system` follows the device setting, which is what almost every
/// reader wants; the two overrides exist because a photographer working from a
/// call sheet in the other format should not have to change their whole phone.
enum SunlitTimeFormat: String, CaseIterable, Sendable {
    case system
    case twelveHour
    case twentyFourHour
}

/// The preferences this track owns, readable from anywhere in the app.
///
/// Plain `UserDefaults` behind static accessors rather than an observable
/// object, because these are read inside formatting helpers that run in
/// hundreds of table cells and must not each become an observation dependency.
/// `SettingsView` binds the same keys through `@AppStorage`, which is what
/// republishes the interface when one of them changes.
enum SunlitSettings {

    static let unitsKey = "settings.units"
    static let timeFormatKey = "settings.timeFormat"

    static var units: SunlitUnits {
        SunlitUnits(rawValue: UserDefaults.standard.string(forKey: unitsKey) ?? "") ?? .metric
    }

    static var timeFormat: SunlitTimeFormat {
        SunlitTimeFormat(rawValue: UserDefaults.standard.string(forKey: timeFormatKey) ?? "") ?? .system
    }

    /// A clock reading in a given zone, honouring the override.
    static func timeString(_ date: Date, timeZone: TimeZone) -> String {
        switch timeFormat {
        case .system:
            var style = Date.FormatStyle(date: .omitted, time: .shortened)
            style.timeZone = timeZone
            return date.formatted(style)
        case .twelveHour:
            return date.formatted(
                Date.FormatStyle(timeZone: timeZone)
                    .hour(.defaultDigits(amPM: .abbreviated))
                    .minute(.twoDigits))
        case .twentyFourHour:
            // Omitting the am and pm symbol is what selects the 24 hour cycle.
            return date.formatted(
                Date.FormatStyle(timeZone: timeZone)
                    .hour(.twoDigits(amPM: .omitted))
                    .minute(.twoDigits))
        }
    }

    /// A length, in the chosen system. Used for shadows.
    static func lengthString(metres: Double, fractionDigits: Int = 1) -> String {
        let measurement = Measurement(value: metres, unit: UnitLength.meters)
        let converted = units == .metric ? measurement : measurement.converted(to: .feet)
        return converted.formatted(
            .measurement(
                width: .abbreviated,
                usage: .asProvided,
                numberFormatStyle: .number.precision(.fractionLength(fractionDigits))))
    }

    /// An elevation above sea level, in the chosen system.
    static func elevationString(metres: Double) -> String {
        lengthString(metres: metres, fractionDigits: 0)
    }
}

// MARK: - Event notifications

/// Sunrise, sunset, golden hour and full moon, scheduled locally.
///
/// Every time comes from `DayReport`, which is the same computation the rest of
/// the app reads, so a notification can never disagree with the screen. Nothing
/// is fetched and no server is told when the user's sun rises.
///
/// The horizon is deliberately short and deliberately stated in the interface:
/// iOS keeps at most sixty four pending local notifications per app, and the app
/// cannot wake itself to extend the list, so a week is what one visit buys.
enum SunlitEventNotifications {

    static let identifierPrefix = "sunlit.event."
    static let horizonDays = 7
    private static let maximumRequests = 60

    struct Selection: Equatable, Sendable {
        var sunrise: Bool
        var sunset: Bool
        var goldenHour: Bool
        var fullMoon: Bool

        var isEmpty: Bool { !sunrise && !sunset && !goldenHour && !fullMoon }
    }

    static func authorisationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Asks once. A refusal is final until the user changes it in the system
    /// settings, and the interface says so rather than asking again.
    static func requestAuthorisation() async -> Bool {
        let granted = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
        return granted ?? false
    }

    /// Removes only this app's event notifications, by prefix.
    ///
    /// Not `removeAllPendingNotificationRequests`, which would also throw away
    /// anything another part of the app had scheduled. It owns none today, and
    /// a helper that quietly breaks when it does is a trap.
    static func cancelAll() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let mine = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        guard !mine.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: mine)
    }

    /// Rebuilds the whole schedule for a place. Cheap to call again.
    @discardableResult
    static func reschedule(selection: Selection, place: Place) async -> Int {
        await cancelAll()
        guard !selection.isEmpty else { return 0 }

        let days = horizonDays
        // A day report is several thousand ephemeris evaluations, so a week of
        // them stays off the main thread. Place and DayReport are both Sendable.
        let reports: [DayReport] = await Task.detached(priority: .utility) {
            var out: [DayReport] = []
            out.reserveCapacity(days)
            let start = Date()
            for offset in 0..<days {
                let day = start.addingTimeInterval(Double(offset) * 86400)
                out.append(DayReport.compute(
                    date: place.startOfLocalDay(containing: day),
                    place: place))
            }
            return out
        }.value

        let zone = TimeZone(identifier: place.timeZoneIdentifier) ?? .current
        let now = Date()
        var requests: [UNNotificationRequest?] = []

        for (dayIndex, report) in reports.enumerated() {
            if selection.sunrise, let time = report.phases.sunrise?.date {
                requests.append(request(
                    key: "sunrise", dayIndex: dayIndex, slot: 0,
                    title: sunriseTitle, at: time, now: now, zone: zone, place: place))
            }
            if selection.sunset, let time = report.phases.sunset?.date {
                requests.append(request(
                    key: "sunset", dayIndex: dayIndex, slot: 0,
                    title: sunsetTitle, at: time, now: now, zone: zone, place: place))
            }
            if selection.goldenHour {
                if let time = report.goldenHour.morning?.start.date {
                    requests.append(request(
                        key: "golden", dayIndex: dayIndex, slot: 0,
                        title: goldenTitle, at: time, now: now, zone: zone, place: place))
                }
                if let time = report.goldenHour.evening?.start.date {
                    requests.append(request(
                        key: "golden", dayIndex: dayIndex, slot: 1,
                        title: goldenTitle, at: time, now: now, zone: zone, place: place))
                }
            }
            if selection.fullMoon, report.moonPhaseAtNoon.name == .fullMoon {
                // At moonrise when there is one, because that is when it is
                // worth walking outside. Roughly one calendar day a month has
                // no moonrise in it at all, and those fall back to the evening.
                let time = report.moonrise?.date ?? eveningInstant(of: report, zone: zone)
                requests.append(request(
                    key: "fullmoon", dayIndex: dayIndex, slot: 0,
                    title: fullMoonTitle, at: time, now: now, zone: zone, place: place))
            }
        }

        let scheduled = Array(requests.compactMap { $0 }.prefix(maximumRequests))
        let center = UNUserNotificationCenter.current()
        for item in scheduled {
            try? await center.add(item)
        }
        return scheduled.count
    }

    private static func eveningInstant(of report: DayReport, zone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let midnight = report.date.date
        return calendar.date(byAdding: .hour, value: 21, to: midnight) ?? midnight
    }

    private static func request(
        key: String,
        dayIndex: Int,
        slot: Int,
        title: String,
        at date: Date,
        now: Date,
        zone: TimeZone,
        place: Place
    ) -> UNNotificationRequest? {
        let interval = date.timeIntervalSince(now)
        // Anything already past, and anything within the next minute, is noise.
        guard interval > 60 else { return nil }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = String(
            localized: "notification.body",
            defaultValue: "\(SunlitSettings.timeString(date, timeZone: zone)) in \(place.name)",
            comment: "Body of an event notification: the local time, then the place")
        content.sound = .default

        return UNNotificationRequest(
            identifier: "\(identifierPrefix)\(key).\(dayIndex).\(slot)",
            content: content,
            // An absolute interval rather than date components, because the
            // event is an instant in the place's clock and the device may be in
            // another zone entirely.
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))
    }

    private static var sunriseTitle: String {
        String(localized: "notification.sunrise", defaultValue: "Sunrise",
               comment: "Title of the sunrise notification")
    }

    private static var sunsetTitle: String {
        String(localized: "notification.sunset", defaultValue: "Sunset",
               comment: "Title of the sunset notification")
    }

    private static var goldenTitle: String {
        String(localized: "notification.golden", defaultValue: "Golden hour",
               comment: "Title of the golden hour notification")
    }

    private static var fullMoonTitle: String {
        String(localized: "notification.fullMoon", defaultValue: "Full moon",
               comment: "Title of the full moon notification")
    }
}

// MARK: - Settings

struct SettingsView: View {

    @Environment(AppState.self) private var state
    @Environment(\.openURL) private var openURL
    @Environment(\.displayScale) private var displayScale

    /// The purchase layer the app injects at launch, if it did. Restoring has to
    /// go through this and not through a private copy of the StoreKit calls: it
    /// is what writes the entitlement into the app group the widget extension
    /// reads and what reloads the widget timelines afterwards. A restore that
    /// only told `ProGate` would unlock the app and leave the widgets locked.
    @Environment(StoreService.self) private var injectedPurchases: StoreService?
    @State private var ownedPurchases: StoreService?

    private var purchases: StoreService? { injectedPurchases ?? ownedPurchases }

    @State private var store = SavedPlacesStore.shared

    @AppStorage(SunlitSettings.unitsKey) private var units: SunlitUnits = .metric
    @AppStorage(SunlitSettings.timeFormatKey) private var timeFormat: SunlitTimeFormat = .system

    @AppStorage("settings.notify.sunrise") private var notifySunrise = false
    @AppStorage("settings.notify.sunset") private var notifySunset = false
    @AppStorage("settings.notify.golden") private var notifyGolden = false
    @AppStorage("settings.notify.fullMoon") private var notifyFullMoon = false

    @State private var authorisation: UNAuthorizationStatus = .notDetermined
    @State private var scheduledCount: Int?
    @State private var restoreMessage: String?
    @State private var showingHorizon = false
    @State private var showingAcknowledgements = false

    private var selection: SunlitEventNotifications.Selection {
        SunlitEventNotifications.Selection(
            sunrise: notifySunrise,
            sunset: notifySunset,
            goldenHour: notifyGolden,
            fullMoon: notifyFullMoon)
    }

    var body: some View {
        let moment = SkyMoment.at(state.julianDay, place: state.place)
        let altitude = moment.sun.altitude

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SunlitSheetHeader(
                    title: String(
                        localized: "settings.title",
                        defaultValue: "Settings",
                        comment: "Title of the settings sheet"))

                unitsSection
                HairlineDivider()
                timeSection
                HairlineDivider()
                horizonSection(altitude: altitude)
                HairlineDivider()
                notificationsSection(altitude: altitude)
                HairlineDivider()
                purchaseSection(altitude: altitude)
                HairlineDivider()
                aboutSection(altitude: altitude)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .sunlitSheetSky(
            solarAltitude: altitude,
            moonIllumination: moment.moonPhase.illuminatedFraction)
        .sheet(isPresented: $showingHorizon) {
            HorizonProfileEditor()
        }
        .sheet(isPresented: $showingAcknowledgements) {
            AcknowledgementsView()
        }
        .task {
            // Only when nothing was injected. Settings must be able to restore a
            // purchase from wherever it is presented, and a restore button that
            // silently does nothing is worse than a missing one.
            if injectedPurchases == nil, ownedPurchases == nil {
                ownedPurchases = StoreService(gate: state.pro)
            }
            authorisation = await SunlitEventNotifications.authorisationStatus()
            // A skyline belongs to a coordinate, so a place that was swept
            // before this session gets its measurement back.
            if state.place.horizonProfile == nil, let stored = store.profile(for: state.place) {
                state.place.horizonProfile = stored
            }
        }
        .task(id: scheduleSignature) {
            await applySchedule()
        }
    }

    // MARK: Units

    private var unitsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "settings.units",
                        defaultValue: "Units",
                        comment: "Heading of the units section"))
                .sunlitLabel()

            Picker(selection: $units) {
                Text(String(localized: "settings.units.metric",
                            defaultValue: "Metric",
                            comment: "Metric units")).tag(SunlitUnits.metric)
                Text(String(localized: "settings.units.imperial",
                            defaultValue: "Imperial",
                            comment: "Imperial units")).tag(SunlitUnits.imperial)
            } label: {
                Text(unitsLabel)
            }
            .pickerStyle(.segmented)
            .frame(minHeight: SunlitLayout.minimumTouchTarget)
            .accessibilityLabel(Text(unitsLabel))

            Text(String(localized: "settings.units.note",
                        defaultValue: "Shadow length and elevation. Angles stay in degrees.",
                        comment: "Says which figures the unit choice changes"))
                .font(SunlitType.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var unitsLabel: String {
        String(localized: "settings.units",
               defaultValue: "Units",
               comment: "Heading of the units section")
    }

    // MARK: Time

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(timeLabel).sunlitLabel()

            Picker(selection: $timeFormat) {
                Text(String(localized: "settings.time.system",
                            defaultValue: "System",
                            comment: "Follow the device clock setting")).tag(SunlitTimeFormat.system)
                Text(String(localized: "settings.time.twelve",
                            defaultValue: "12 hour",
                            comment: "Twelve hour clock")).tag(SunlitTimeFormat.twelveHour)
                Text(String(localized: "settings.time.twentyFour",
                            defaultValue: "24 hour",
                            comment: "Twenty four hour clock")).tag(SunlitTimeFormat.twentyFourHour)
            } label: {
                Text(timeLabel)
            }
            .pickerStyle(.segmented)
            .frame(minHeight: SunlitLayout.minimumTouchTarget)
            .accessibilityLabel(Text(timeLabel))

            Text(String(localized: "settings.time.example",
                        defaultValue: "Now at \(state.place.name): \(SunlitSettings.timeString(Date(), timeZone: TimeZone(identifier: state.place.timeZoneIdentifier) ?? .current))",
                        comment: "Shows the chosen clock format using the selected place"))
                .font(SunlitType.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var timeLabel: String {
        String(localized: "settings.time",
               defaultValue: "Clock",
               comment: "Heading of the time format section")
    }

    // MARK: Horizon

    @ViewBuilder
    private func horizonSection(altitude: Double) -> some View {
        let allowed = state.pro.allows(.terrain)
        let profile = state.place.horizonProfile

        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "settings.horizon",
                        defaultValue: "Horizon",
                        comment: "Heading of the measured skyline section"))
                .sunlitLabel()

            Text(horizonStatus(profile))
                .font(SunlitType.body)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button {
                    showingHorizon = true
                } label: {
                    Text(horizonOpenTitle)
                        .font(SunlitType.body)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            SkyPalette.componentBorder(solarAltitude: altitude),
                            lineWidth: 1 / displayScale)
                }
                .sunlitTouchTarget()
                .accessibilityLabel(Text(horizonOpenTitle))

                if profile != nil {
                    Button {
                        state.place.horizonProfile = nil
                        store.setProfile(nil, for: state.place)
                    } label: {
                        Text(horizonClearTitle).font(SunlitType.body)
                    }
                    .buttonStyle(.plain)
                    .sunlitTouchTarget()
                    // Clearing is changing. The sentence below this row says
                    // that changing the skyline is part of the purchase, and a
                    // free destructive button beside that sentence contradicts
                    // it and throws away a measurement that took a sweep.
                    .disabled(!allowed)
                    .foregroundStyle(
                        allowed
                            ? SkyPalette.foreground(solarAltitude: altitude)
                            : SkyColors.disabled(solarAltitude: altitude))
                    .accessibilityLabel(Text(horizonClearTitle))
                }
            }

            if !allowed {
                ProLockNote(reason: String(
                    localized: "settings.horizon.gate",
                    defaultValue: "A measured skyline moves your sunrise and sunset to the times you actually see, and lists the periods the sun is up but behind something. Reading the table is free. Changing it is part of Sunlit Pro.",
                    comment: "Explains that editing the horizon profile is a paid capability"))
            }
        }
    }

    private func horizonStatus(_ profile: HorizonProfile?) -> String {
        guard let profile, profile.isMeasured else {
            return String(
                localized: "settings.horizon.none",
                defaultValue: "No skyline has been measured at \(state.place.name), so Sunlit assumes a flat horizon.",
                comment: "Shown when the current place has no measured horizon profile")
        }
        return String(
            localized: "settings.horizon.measured",
            defaultValue: "\(profile.measuredSectorCount) of 36 directions measured at \(state.place.name).",
            comment: "Shown when the current place has a measured horizon profile")
    }

    private var horizonOpenTitle: String {
        String(localized: "settings.horizon.open",
               defaultValue: "View the table",
               comment: "Button that opens the horizon profile table")
    }

    private var horizonClearTitle: String {
        String(localized: "settings.horizon.clear",
               defaultValue: "Clear",
               comment: "Button that discards the measured horizon profile")
    }

    // MARK: Notifications

    @ViewBuilder
    private func notificationsSection(altitude: Double) -> some View {
        let allowed = state.pro.allows(.notifications)

        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "settings.notifications",
                        defaultValue: "Notifications",
                        comment: "Heading of the notifications section"))
                .sunlitLabel()

            VStack(alignment: .leading, spacing: 4) {
                notificationToggle(
                    title: String(localized: "settings.notify.sunrise",
                                  defaultValue: "Sunrise",
                                  comment: "Toggle for the sunrise notification"),
                    isOn: $notifySunrise)
                notificationToggle(
                    title: String(localized: "settings.notify.sunset",
                                  defaultValue: "Sunset",
                                  comment: "Toggle for the sunset notification"),
                    isOn: $notifySunset)
                notificationToggle(
                    title: String(localized: "settings.notify.golden",
                                  defaultValue: "Golden hour",
                                  comment: "Toggle for the golden hour notification"),
                    isOn: $notifyGolden)
                notificationToggle(
                    title: String(localized: "settings.notify.fullMoon",
                                  defaultValue: "Full moon",
                                  comment: "Toggle for the full moon notification"),
                    isOn: $notifyFullMoon)
            }
            .disabled(!allowed)
            .opacity(allowed ? 1 : SkyColors.disabledOpacity)

            if allowed {
                permissionNote
                Text(String(
                    localized: "settings.notifications.horizon",
                    defaultValue: "Scheduled for the next \(SunlitEventNotifications.horizonDays) days at \(state.place.name), from the same figures the app shows. Open Sunlit now and then to extend them.",
                    comment: "States how far ahead notifications are scheduled and why"))
                    .font(SunlitType.caption)
                    .fixedSize(horizontal: false, vertical: true)
                if let scheduledCount {
                    Text(String(
                        localized: "settings.notifications.count",
                        defaultValue: "\(scheduledCount) waiting",
                        comment: "How many notifications are currently scheduled"))
                        .font(SunlitType.caption)
                }
            } else {
                ProLockNote(reason: String(
                    localized: "settings.notifications.gate",
                    defaultValue: "Event notifications are part of Sunlit Pro. They are computed on your device and nothing about your times or your place leaves it.",
                    comment: "Explains that notifications are a paid capability"))
            }
        }
    }

    private func notificationToggle(title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title).font(SunlitType.body)
        }
        .frame(minHeight: SunlitLayout.minimumTouchTarget)
        .accessibilityLabel(Text(title))
    }

    @ViewBuilder
    private var permissionNote: some View {
        switch authorisation {
        case .denied:
            VStack(alignment: .leading, spacing: 8) {
                Text(String(
                    localized: "settings.notifications.refused",
                    defaultValue: "Notifications are switched off for Sunlit in the system settings, so nothing will arrive until they are switched back on. Everything else keeps working.",
                    comment: "Shown when notification permission was refused"))
                    .font(SunlitType.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    Text(openSystemSettingsTitle).font(SunlitType.body).underline()
                }
                .buttonStyle(.plain)
                .sunlitTouchTarget()
                .accessibilityLabel(Text(openSystemSettingsTitle))
            }
        default:
            EmptyView()
        }
    }

    private var openSystemSettingsTitle: String {
        String(localized: "settings.openSystemSettings",
               defaultValue: "Open the system settings",
               comment: "Button that opens this app's page in the system settings")
    }

    /// Everything the schedule depends on, in one value, so `task(id:)` rebuilds
    /// it exactly when something it reads has changed.
    private var scheduleSignature: String {
        [
            state.pro.allows(.notifications) ? "1" : "0",
            notifySunrise ? "1" : "0",
            notifySunset ? "1" : "0",
            notifyGolden ? "1" : "0",
            notifyFullMoon ? "1" : "0",
            state.place.timeZoneIdentifier,
            SavedPlacesStore.coordinateKey(
                latitude: state.place.latitude, longitude: state.place.longitude)
        ].joined(separator: "|")
    }

    @MainActor
    private func applySchedule() async {
        guard state.pro.allows(.notifications), !selection.isEmpty else {
            await SunlitEventNotifications.cancelAll()
            scheduledCount = 0
            return
        }
        if authorisation == .notDetermined {
            _ = await SunlitEventNotifications.requestAuthorisation()
            authorisation = await SunlitEventNotifications.authorisationStatus()
        }
        guard authorisation == .authorized || authorisation == .provisional else {
            scheduledCount = 0
            return
        }
        scheduledCount = await SunlitEventNotifications.reschedule(
            selection: selection, place: state.place)
    }

    // MARK: Purchase

    @ViewBuilder
    private func purchaseSection(altitude: Double) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "settings.purchase",
                        defaultValue: "Purchase",
                        comment: "Heading of the purchase section"))
                .sunlitLabel()

            Text(isOwned ? purchaseOwnedText : purchaseFreeText)
                .font(SunlitType.body)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button {
                    Task { await restore() }
                } label: {
                    Text(restoreTitle)
                        .font(SunlitType.body)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            SkyPalette.componentBorder(solarAltitude: altitude),
                            lineWidth: 1 / displayScale)
                }
                .sunlitTouchTarget()
                .disabled(isRestoring)
                .accessibilityLabel(Text(restoreTitle))

                if isRestoring {
                    ProgressView()
                        .accessibilityLabel(Text(restoreTitle))
                }
            }

            if let restoreMessage {
                Text(restoreMessage)
                    .font(SunlitType.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !isOwned {
                ProUnlockButton()
            }
        }
    }

    /// Asked of the gate, capability by capability, rather than read off a
    /// purchase flag. Views in this app never see the flag.
    private var isOwned: Bool {
        ProCapability.allCases.allSatisfy { state.pro.allows($0) }
    }

    private var restoreTitle: String {
        String(localized: "settings.restore",
               defaultValue: "Restore purchase",
               comment: "Button that restores a previous purchase")
    }

    private var purchaseFreeText: String {
        String(
            localized: "settings.purchase.free",
            defaultValue: "Today at your current location is free forever, in all four views. One purchase adds every other date and place, the moon, the Milky Way, annual paths, a measured skyline, eclipses, widgets, notifications and export.",
            comment: "States what the free tier covers and what the purchase adds")
    }

    private var purchaseOwnedText: String {
        String(
            localized: "settings.purchase.owned",
            defaultValue: "Sunlit Pro is active on this Apple Account. Everything is unlocked.",
            comment: "Shown when the purchase is already owned")
    }

    /// Restore, through the one purchase layer.
    ///
    /// This used to call `AppStore.sync` and scan `currentEntitlements` here and
    /// then write straight to `ProGate`. Three things were wrong with that, and
    /// all three are the reason the store track owns a service at all. It never
    /// wrote the entitlement into the shared app group, so a restore unlocked
    /// the app and left every widget locked. It reported a cancelled Apple ID
    /// sign in, which `try?` swallowed, as "no purchase was found", which is a
    /// different sentence about a different situation. And it wrote `false` on
    /// any empty read, so a restore that went wrong could take the app away from
    /// somebody who had paid for it.
    @MainActor
    private func restore() async {
        restoreMessage = nil
        guard let purchases else { return }
        await purchases.restore()
        restoreMessage = purchases.outcome?.message
    }

    private var isRestoring: Bool { purchases?.isRestoring ?? false }

    // MARK: About

    @ViewBuilder
    private func aboutSection(altitude: Double) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "settings.about",
                        defaultValue: "About",
                        comment: "Heading of the about section"))
                .sunlitLabel()

            linkRow(
                title: String(localized: "settings.privacy",
                              defaultValue: "Privacy",
                              comment: "Link to the privacy page"),
                url: URL(string: "https://sunlit-app.vercel.app/privacy.html"))

            linkRow(
                title: String(localized: "settings.support",
                              defaultValue: "Support",
                              comment: "Link to the support page"),
                url: URL(string: "https://sunlit-app.vercel.app/support.html"))

            Button {
                showingAcknowledgements = true
            } label: {
                HStack(spacing: 8) {
                    Text(acknowledgementsTitle).font(SunlitType.body)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .imageScale(.small)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: SunlitLayout.minimumTouchTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(acknowledgementsTitle))

            Text(String(
                localized: "settings.offline",
                defaultValue: "Every figure in Sunlit is computed on this device. Nothing about you is collected and nothing is sent. Every calculation works in aeroplane mode; only Apple's map tiles and the time zone of a newly dropped pin need a connection.",
                comment: "States the offline and no data promise"))
                .font(SunlitType.caption)
                .fixedSize(horizontal: false, vertical: true)

            Text(versionText)
                .font(SunlitType.caption)
        }
    }

    private var acknowledgementsTitle: String {
        String(localized: "settings.acknowledgements",
               defaultValue: "Data and methods",
               comment: "Link to the acknowledgements screen")
    }

    private func linkRow(title: String, url: URL?) -> some View {
        Button {
            if let url { openURL(url) }
        } label: {
            HStack(spacing: 8) {
                Text(title).font(SunlitType.body)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: SunlitLayout.minimumTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(.isLink)
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return String(
            localized: "settings.version",
            defaultValue: "Version \(version), build \(build)",
            comment: "The app version and build number")
    }
}

// MARK: - Horizon profile table

/// The measured skyline, by hand.
///
/// Thirty six directions, ten degrees apart, each holding the apparent altitude
/// of whatever stands there. Zero is an unobstructed sea horizon; a value below
/// zero is what a clifftop sees, which is why the field accepts negatives.
struct HorizonProfileEditor: View {

    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var store = SavedPlacesStore.shared
    @State private var sectors: [Double] = Array(
        repeating: 0, count: HorizonProfile.sectorCount)
    @State private var hasSeeded = false

    var body: some View {
        let moment = SkyMoment.at(state.julianDay, place: state.place)
        let altitude = moment.sun.altitude
        let allowed = state.pro.allows(.terrain)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SunlitSheetHeader(
                    title: String(localized: "horizon.title",
                                  defaultValue: "Skyline",
                                  comment: "Title of the horizon profile editor"))

                Text(String(
                    localized: "horizon.explain",
                    defaultValue: "The apparent height of whatever stands in each direction, in degrees. Zero is an open sea horizon. A hilltop looking down at the sea takes a value below zero.",
                    comment: "Explains what the horizon profile table holds"))
                    .font(SunlitType.body)
                    .fixedSize(horizontal: false, vertical: true)

                if !allowed {
                    ProLockNote(reason: String(
                        localized: "horizon.gate",
                        defaultValue: "The table is here to read. Changing it, and the true sunrise and obstruction times it produces, are part of Sunlit Pro.",
                        comment: "Explains that editing the skyline is a paid capability"))
                }

                HairlineDivider()

                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(0..<HorizonProfile.sectorCount, id: \.self) { index in
                        sectorRow(index)
                    }
                }
                .disabled(!allowed)
                .opacity(allowed ? 1 : SkyColors.disabledOpacity)

                HairlineDivider()

                Button {
                    sectors = Array(repeating: 0, count: HorizonProfile.sectorCount)
                    state.place.horizonProfile = nil
                    store.setProfile(nil, for: state.place)
                } label: {
                    Text(resetTitle).font(SunlitType.body)
                }
                .buttonStyle(.plain)
                .sunlitTouchTarget()
                .disabled(!allowed)
                .accessibilityLabel(Text(resetTitle))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .sunlitSheetSky(
            solarAltitude: altitude,
            moonIllumination: moment.moonPhase.illuminatedFraction)
        .onAppear {
            guard !hasSeeded else { return }
            sectors = state.place.horizonProfile?.sectors
                ?? Array(repeating: 0, count: HorizonProfile.sectorCount)
            hasSeeded = true
        }
    }

    private func sectorRow(_ index: Int) -> some View {
        let azimuth = Double(index) * HorizonProfile.sectorWidth
        let binding = Binding<Double>(
            get: { sectors.indices.contains(index) ? sectors[index] : 0 },
            set: { newValue in
                guard sectors.indices.contains(index) else { return }
                sectors[index] = newValue
                apply()
            })

        return Stepper(value: binding, in: -20...80, step: 0.5) {
            HStack(spacing: 12) {
                // Symbols and a locale formatted number, so there is nothing
                // here for a translator to get wrong.
                Text(verbatim: "\(azimuth.formatted(.number.precision(.fractionLength(0))))°")
                    .font(SunlitType.metricSmall)
                    .frame(minWidth: 48, alignment: .leading)
                Text(verbatim: "\(binding.wrappedValue.formatted(.number.precision(.fractionLength(1))))°")
                    .font(SunlitType.metricSmall)
            }
        }
        .frame(minHeight: SunlitLayout.minimumTouchTarget)
        .accessibilityLabel(Text(String(
            localized: "horizon.sector",
            defaultValue: "Skyline height at bearing \(azimuth.formatted(.number.precision(.fractionLength(0)))) degrees",
            comment: "Spoken label of one horizon sector row")))
        .accessibilityValue(Text(String(
            localized: "horizon.degrees",
            defaultValue: "\(binding.wrappedValue.formatted(.number.precision(.fractionLength(1)))) degrees",
            comment: "Spoken value of one horizon sector row")))
    }

    /// Commits the table, or clears it when there is nothing in it.
    ///
    /// `HorizonProfile(sectors:)` marks every sector observed, because a table
    /// handed over whole is data however it was produced. That is right for a
    /// filled table and wrong for an empty one: without the guard below, one tap
    /// on a stepper and back again leaves thirty six zeros stored as a
    /// measurement, Settings reports "36 of 36 directions measured", and the
    /// Data view offers a difference between the flat sunrise and the measured
    /// sunrise that is zero minutes because no sweep ever happened. An all zero
    /// table is the flat assumption, which is exactly what no profile means.
    private func apply() {
        guard let profile = HorizonProfile(sectors: sectors), !profile.isFlat else {
            state.place.horizonProfile = nil
            store.setProfile(nil, for: state.place)
            return
        }
        state.place.horizonProfile = profile
        store.setProfile(profile, for: state.place)
    }

    private var resetTitle: String {
        String(localized: "horizon.reset",
               defaultValue: "Clear the whole table",
               comment: "Button that discards every measured sector")
    }
}
