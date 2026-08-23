import SwiftUI
import UIKit
import SunlitCore

// MARK: - The embedded city database

/// The offline GeoNames extract, parsed once and kept.
///
/// `SunlitCore` imports Foundation and nothing else, so `CityIndex` cannot reach
/// a bundle by design. The app target reads the resource and hands the bytes
/// over, which is the arrangement `CityIndex` documents at the top of its file.
///
/// Parsing validates every one of the thirty four thousand records, so it is
/// done once, off the main thread, the first time the picker opens.
enum CityDatabase {

    /// The parsed index, or nil when the resource is missing or corrupt. Nil is
    /// a state the interface shows plainly rather than an assertion, because a
    /// search field that silently returns nothing looks like a broken app.
    static let shared: CityIndex? = load()

    private static func load() -> CityIndex? {
        guard let url = Bundle.main.url(forResource: "cities", withExtension: "bin") else { return nil }
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return nil }
        return try? CityIndex(data: data)
    }
}

// MARK: - Sheet furniture
//
// Shared by the three sheets this track owns. It lives beside the first of them
// rather than in Design/, because Design/ is common ground and this is one
// track's house style.

/// The adaptive sky, plus a colour scheme that matches the audited ink flip.
///
/// The gradient is a readout and it runs from near black to a bright day blue,
/// so `SkyPalette` flips its ink at `inkCrossoverAltitude`. UIKit backed
/// controls, a graphical `DatePicker` above all, pick their own ink from the
/// environment's colour scheme and know nothing about that flip, so they are
/// told about it here. Without this the calendar draws white on a noon sky.
extension View {
    func sunlitSheetSky(solarAltitude: Double, moonIllumination: Double = 0) -> some View {
        self
            .adaptiveSky(solarAltitude: solarAltitude, moonIllumination: moonIllumination)
            .environment(
                \.colorScheme,
                solarAltitude > SkyPalette.inkCrossoverAltitude ? .light : .dark
            )
            .tint(SkyColors.sun)
    }
}

/// A sheet's title and its way out.
struct SunlitSheetHeader: View {
    let title: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(SunlitType.title)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            SunlitDismissButton()
        }
    }
}

struct SunlitDismissButton: View {
    @Environment(\.dismiss) private var dismiss

    private var title: String {
        String(
            localized: "sheet.done",
            defaultValue: "Done",
            comment: "Closes the place and date sheets. Deliberately the same word as data.done, which closes the export sheet; translate both identically"
        )
    }

    var body: some View {
        Button {
            dismiss()
        } label: {
            Text(title).font(SunlitType.body)
        }
        .buttonStyle(.plain)
        .sunlitTouchTarget()
        .accessibilityLabel(Text(title))
    }
}

/// The route to the paywall.
///
/// `PaywallView` belongs to the store track, and this extension is the only
/// place in this one that names it, so an integration mismatch is a single line
/// to repair rather than a dozen.
extension View {
    func proPaywall(isPresented: Binding<Bool>) -> some View {
        sheet(isPresented: isPresented) { PaywallView() }
    }
}

/// The standard way in.
struct ProUnlockButton: View {
    @Environment(\.solarAltitude) private var solarAltitude
    @Environment(\.displayScale) private var displayScale
    @State private var showingPaywall = false

    private var title: String {
        String(
            localized: "pro.unlock",
            defaultValue: "See what Sunlit Pro adds",
            comment: "Button that opens the purchase screen. The app uses this one wording everywhere the purchase screen is opened"
        )
    }

    var body: some View {
        Button {
            showingPaywall = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "lock.open")
                    .imageScale(.small)
                    .accessibilityHidden(true)
                Text(title).font(SunlitType.body)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(
                    SkyPalette.componentBorder(solarAltitude: solarAltitude),
                    lineWidth: 1 / displayScale
                )
        }
        .sunlitTouchTarget()
        .accessibilityLabel(Text(title))
        .proPaywall(isPresented: $showingPaywall)
    }
}

/// What a locked capability says for itself.
///
/// A gated feature shows what it would show, greyed, with the reason beside it
/// and a way to buy. Features that vanish when they are locked make the free
/// app look broken and make the purchase impossible to understand.
struct ProLockNote: View {
    let reason: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .imageScale(.small)
                    .accessibilityHidden(true)
                Text(
                    String(
                        localized: "pro.name",
                        defaultValue: "Sunlit Pro",
                        comment: "Name of the one in app purchase"
                    )
                )
                .sunlitLabel()
            }
            Text(reason)
                .font(SunlitType.body)
                .fixedSize(horizontal: false, vertical: true)
            ProUnlockButton()
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Place picker

/// Where. Current location, kept places, and thirty four thousand cities that
/// need no network.
///
/// Every place can be opened, including without the purchase, because a picker
/// that refuses to move teaches nobody what the purchase buys. What the free
/// tier covers is today at the device's own position, which is the rule
/// `ProGate.allowsSelection` states and which the Sky, AR and Data views all
/// enforce by showing their locked state over a place that is not the current
/// one. This screen says the same thing in the same words. It used to say
/// "looking at any place is free", which read as a promise and was then
/// contradicted by three views the moment a city was chosen.
struct PlacePickerView: View {

    @Environment(AppState.self) private var state
    @Environment(LocationProvider.self) private var location
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale

    @State private var store = SavedPlacesStore.shared
    @State private var query = ""
    @State private var results: [City] = []
    @State private var index: CityIndex?
    @State private var isLoadingIndex = true

    /// The city nearest the device, held rather than recomputed.
    ///
    /// `CityIndex.nearest` is a linear pass over all 34,106 records. It used to
    /// be a computed property read from the body, and the body is re-evaluated
    /// on every keystroke in the search field, so typing a nine letter city name
    /// walked the whole database nine times over for an answer that had not
    /// changed. It is refreshed when the fix moves instead.
    @State private var nearestCityName: String?

    var body: some View {
        // One evaluation for the whole sheet. The gradient, the hairlines and
        // the ink all come from this altitude, and `SkyMoment.at` is the only
        // door to the core the interface is allowed to use.
        let moment = SkyMoment.at(state.julianDay, place: state.place)
        let altitude = moment.sun.altitude
        let now = Date()

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SunlitSheetHeader(
                    title: String(
                        localized: "places.title",
                        defaultValue: "Place",
                        comment: "Title of the place picker sheet"
                    )
                )

                searchField(altitude: altitude)

                if !state.pro.allows(.savedPlaces) {
                    ProLockNote(reason: savedPlacesReason)
                    HairlineDivider()
                }

                currentLocationSection(now: now)

                if !store.places.isEmpty {
                    HairlineDivider()
                    savedSection(now: now)
                }

                HairlineDivider()
                resultsSection(now: now, altitude: altitude)

                attribution
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .sunlitSheetSky(
            solarAltitude: altitude,
            moonIllumination: moment.moonPhase.illuminatedFraction
        )
        .task {
            guard index == nil else { return }
            // Off the main thread: parsing validates all 34,106 records and
            // walks the whole key blob of a 1.5 MB resource, and the first
            // keystroke must not wait for it. CityIndex is Sendable, so it
            // crosses cleanly.
            index = await Task.detached(priority: .userInitiated) { CityDatabase.shared }.value
            isLoadingIndex = false
            runSearch()
            refreshNearestCity()
        }
        .onChange(of: locationKey) { _, _ in
            refreshNearestCity()
        }
    }

    // MARK: Search field

    private func searchField(altitude: Double) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .imageScale(.medium)
                .accessibilityHidden(true)
            TextField(
                text: $query,
                prompt: Text(searchPrompt)
            ) {
                Text(searchPrompt)
            }
            .font(SunlitType.body)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .onChange(of: query) { _, _ in runSearch() }
            .accessibilityLabel(Text(searchPrompt))

            if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                } label: {
                    Image(systemName: "xmark.circle.fill").imageScale(.medium)
                }
                .buttonStyle(.plain)
                .sunlitTouchTarget()
                .accessibilityLabel(
                    Text(
                        String(
                            localized: "places.search.clear",
                            defaultValue: "Clear the search",
                            comment: "Button that empties the place search field"
                        )
                    )
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: SunlitLayout.minimumTouchTarget)
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(
                    SkyPalette.componentBorder(solarAltitude: altitude),
                    lineWidth: 1 / displayScale
                )
        }
    }

    private var searchPrompt: String {
        String(
            localized: "places.search.prompt",
            defaultValue: "Search a city",
            comment: "Placeholder in the place search field"
        )
    }

    private func runSearch() {
        guard let index, !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            return
        }
        // Synchronous on purpose. The walk is a tight pass over roughly half a
        // megabyte of folded keys and stops at the limit, which is well inside
        // one frame; a background hop would only add ordering bugs.
        results = index.search(query, limit: 40)
    }

    // MARK: Current location

    private func currentLocationSection(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(
                String(
                    localized: "places.here",
                    defaultValue: "Here",
                    comment: "Section heading above the device's own location"
                )
            )
            .sunlitLabel()

            Button {
                selectCurrentLocation()
            } label: {
                PlaceRowLabel(
                    name: currentLocationName,
                    detail: currentLocationDetail,
                    time: currentLocationTime(now: now),
                    isSelected: state.isCurrentLocation,
                    symbol: "location.fill"
                )
            }
            .buttonStyle(.plain)

            if location.authorisation == .denied || location.authorisation == .restricted {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    Text(openSystemSettingsTitle)
                        .font(SunlitType.body)
                        .underline()
                }
                .buttonStyle(.plain)
                .sunlitTouchTarget()
                .accessibilityLabel(Text(openSystemSettingsTitle))
            }
        }
    }

    private var openSystemSettingsTitle: String {
        String(
            localized: "places.openSystemSettings",
            defaultValue: "Open the system settings to allow location",
            comment: "Button shown when location permission was refused"
        )
    }

    private var currentLocationName: String {
        String(
            localized: "places.currentLocation",
            defaultValue: "Current location",
            comment: "The row that follows the device's own position"
        )
    }

    private var currentLocationDetail: String {
        switch location.authorisation {
        case .denied, .restricted:
            return String(
                localized: "places.locationRefused",
                defaultValue: "Location is off, so Sunlit cannot follow you",
                comment: "Shown under the current location row when permission was refused"
            )
        case .notDetermined:
            return String(
                localized: "places.locationAsk",
                defaultValue: "Tap to let Sunlit use your position",
                comment: "Shown under the current location row before permission is answered"
            )
        default:
            if location.coordinate == nil {
                return String(
                    localized: "places.locating",
                    defaultValue: "Locating",
                    comment: "Shown under the current location row while waiting for a fix"
                )
            }
            return nearestCityName ?? String(
                localized: "places.located",
                defaultValue: "Following your position",
                comment: "Shown under the current location row once there is a fix"
            )
        }
    }

    /// A key that only changes when the fix has moved about a hundred metres.
    ///
    /// Three decimal places, the same rounding the saved place store uses, so
    /// ordinary GPS jitter does not set the whole database walking again.
    private var locationKey: String {
        guard let coordinate = location.coordinate else { return "" }
        return SavedPlacesStore.coordinateKey(
            latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    private func refreshNearestCity() {
        guard let coordinate = location.coordinate, let index else {
            nearestCityName = nil
            return
        }
        guard let city = index.nearest(
            latitude: coordinate.latitude, longitude: coordinate.longitude) else {
            nearestCityName = nil
            return
        }
        nearestCityName = city.name + ", " + countryName(city.countryCode)
    }

    private func currentLocationTime(now: Date) -> String? {
        guard location.coordinate != nil else { return nil }
        return SunlitSettings.timeString(now, timeZone: .current)
    }

    private func selectCurrentLocation() {
        switch location.authorisation {
        case .notDetermined:
            location.requestAuthorisation()
            return
        case .denied, .restricted:
            return
        default:
            break
        }
        location.refresh()
        let name = nearestCityName.map { $0.components(separatedBy: ",").first ?? $0 } ?? currentLocationName
        guard var place = location.currentPlace(named: name) else { return }
        place.isCurrentLocation = true
        place.horizonProfile = store.profile(for: place)
        state.place = place
        state.isCurrentLocation = true
        dismiss()
    }

    // MARK: Saved places

    private func savedSection(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(
                String(
                    localized: "places.saved",
                    defaultValue: "Saved",
                    comment: "Section heading above the kept places"
                )
            )
            .sunlitLabel()

            ForEach(store.places) { place in
                HStack(spacing: 8) {
                    Button {
                        select(place)
                    } label: {
                        PlaceRowLabel(
                            name: place.name,
                            detail: coordinateText(latitude: place.latitude, longitude: place.longitude),
                            time: SunlitSettings.timeString(
                                now,
                                timeZone: TimeZone(identifier: place.timeZoneIdentifier) ?? .current
                            ),
                            isSelected: !state.isCurrentLocation
                                && SavedPlacesStore.coordinateKey(
                                    latitude: state.place.latitude, longitude: state.place.longitude)
                                    == SavedPlacesStore.coordinateKey(
                                        latitude: place.latitude, longitude: place.longitude),
                            symbol: "mappin"
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        store.remove(place)
                    } label: {
                        Image(systemName: "trash")
                            .imageScale(.medium)
                    }
                    .buttonStyle(.plain)
                    .sunlitTouchTarget()
                    .accessibilityLabel(
                        Text(
                            String(
                                localized: "places.forget",
                                defaultValue: "Forget this place",
                                comment: "Button that removes a kept place"
                            )
                        )
                    )
                }
            }
        }
    }

    // MARK: Results

    private func resultsSection(now: Date, altitude: Double) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(
                String(
                    localized: "places.results",
                    defaultValue: "Cities",
                    comment: "Section heading above the offline city search results"
                )
            )
            .sunlitLabel()

            if isLoadingIndex {
                Text(
                    String(
                        localized: "places.loading",
                        defaultValue: "Opening the offline city list",
                        comment: "Shown while the embedded city database is being read"
                    )
                )
                .font(SunlitType.body)
            } else if index == nil {
                Text(
                    String(
                        localized: "places.unavailable",
                        defaultValue: "The offline city list could not be read on this device. Current location still works.",
                        comment: "Shown when the embedded city database is missing or damaged"
                    )
                )
                .font(SunlitType.body)
                .fixedSize(horizontal: false, vertical: true)
            } else if query.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(
                    String(
                        localized: "places.hint",
                        defaultValue: "Type a name. The list holds every city above fifteen thousand people and needs no network. Accents are optional, so koln finds Köln.",
                        comment: "Explains what the offline city search covers"
                    )
                )
                .font(SunlitType.body)
                .fixedSize(horizontal: false, vertical: true)
            } else if results.isEmpty {
                Text(
                    String(
                        localized: "places.noResults",
                        defaultValue: "Nothing found. Many places are listed under their English name, so try that spelling.",
                        comment: "Shown when the offline city search finds nothing"
                    )
                )
                .font(SunlitType.body)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(results.enumerated()), id: \.offset) { pair in
                    cityRow(pair.element, now: now, altitude: altitude)
                }
            }
        }
    }

    private func cityRow(_ city: City, now: Date, altitude: Double) -> some View {
        let place = self.place(from: city)
        let saved = store.isSaved(place)
        return HStack(spacing: 8) {
            Button {
                select(place)
            } label: {
                PlaceRowLabel(
                    name: city.name,
                    detail: countryName(city.countryCode),
                    time: SunlitSettings.timeString(
                        now,
                        timeZone: TimeZone(identifier: city.timeZoneIdentifier) ?? .current
                    ),
                    isSelected: false,
                    symbol: "building.2"
                )
            }
            .buttonStyle(.plain)

            saveButton(for: place, isSaved: saved, altitude: altitude)
        }
    }

    @ViewBuilder
    private func saveButton(for place: Place, isSaved: Bool, altitude: Double) -> some View {
        if state.pro.allows(.savedPlaces) {
            Button {
                if isSaved {
                    store.remove(place)
                } else {
                    store.save(place)
                }
            } label: {
                Image(systemName: isSaved ? "star.fill" : "star")
                    .imageScale(.medium)
                    .foregroundStyle(isSaved ? SkyColors.sun : SkyPalette.foreground(solarAltitude: altitude))
            }
            .buttonStyle(.plain)
            .sunlitTouchTarget()
            .accessibilityLabel(
                Text(
                    isSaved
                        ? String(
                            localized: "places.forget",
                            defaultValue: "Forget this place",
                            comment: "Button that removes a kept place")
                        : String(
                            localized: "places.keep",
                            defaultValue: "Keep this place",
                            comment: "Button that saves a place")
                )
            )
        } else {
            // Greyed, not gone. The control stays where it will be after the
            // purchase, so the free app reads as complete rather than broken.
            LockedSaveButton()
        }
    }

    // MARK: Selection

    private func place(from city: City) -> Place {
        Place(
            name: city.name,
            geographic: Coordinates.Geographic(
                latitude: city.latitude,
                longitude: city.longitude,
                elevation: city.elevation),
            timeZoneIdentifier: city.timeZoneIdentifier)
    }

    private func select(_ place: Place) {
        var chosen = place
        chosen.isCurrentLocation = false
        // A skyline belongs to a coordinate, so a place that has been swept
        // before arrives with its measurement rather than with a flat horizon.
        chosen.horizonProfile = store.profile(for: place) ?? place.horizonProfile
        state.place = chosen
        state.isCurrentLocation = false
        dismiss()
    }

    // MARK: Attribution

    /// The city list is GeoNames under CC BY 4.0, and the attribution is a
    /// condition of that licence rather than a courtesy. It is owed in Settings,
    /// in the repository and on the website; it is repeated here, under the
    /// results it belongs to, because this is the screen that uses the data.
    private var attribution: some View {
        VStack(alignment: .leading, spacing: 8) {
            HairlineDivider()
            Text(verbatim: CityIndex.attribution)
                .font(SunlitType.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }

    // MARK: Text

    private var savedPlacesReason: String {
        String(
            localized: "places.gate.saved",
            defaultValue: "Today at your current location is free forever, in all four views. You can open any other place from here, but its figures stay locked, and so does keeping a place so it is waiting next time. Both are part of Sunlit Pro.",
            comment: "Explains that the free tier is today at the current location: another place can be opened, but every view shows it locked until the purchase"
        )
    }

    private func countryName(_ code: String) -> String {
        Locale.current.localizedString(forRegionCode: code) ?? code
    }

    private func coordinateText(latitude: Double, longitude: Double) -> String {
        let lat = latitude.formatted(.number.precision(.fractionLength(2)))
        let lon = longitude.formatted(.number.precision(.fractionLength(2)))
        return lat + (latitude >= 0 ? "N" : "S") + " " + lon + (longitude >= 0 ? "E" : "W")
    }
}

// MARK: - Rows

/// One place: what it is called, where it is, and what time it is there.
private struct PlaceRowLabel: View {
    let name: String
    let detail: String
    let time: String?
    let isSelected: Bool
    let symbol: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: isSelected ? "checkmark" : symbol)
                .imageScale(.small)
                .frame(width: 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(SunlitType.body)
                    .lineLimit(2)
                Text(detail)
                    .font(SunlitType.caption)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if let time {
                Text(time)
                    .font(SunlitType.metricSmall)
            }
        }
        .frame(minHeight: SunlitLayout.minimumTouchTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(name + ", " + detail))
        .accessibilityValue(Text(spokenTime))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var spokenTime: String {
        guard let time else { return "" }
        return String(
            localized: "places.localTime",
            defaultValue: "Local time \(time)",
            comment: "Spoken form of the clock shown beside a place"
        )
    }
}

/// The save control before the purchase: present, explained, and inert.
private struct LockedSaveButton: View {
    @Environment(\.solarAltitude) private var solarAltitude

    private var label: String {
        String(
            localized: "places.keep.locked",
            defaultValue: "Keeping places is part of Sunlit Pro",
            comment: "Spoken label of the disabled save control"
        )
    }

    var body: some View {
        Image(systemName: "lock.fill")
            .imageScale(.medium)
            .foregroundStyle(SkyColors.disabled(solarAltitude: solarAltitude))
            .sunlitTouchTarget()
            .accessibilityLabel(Text(label))
    }
}
