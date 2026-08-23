import CoreLocation
import MapKit
import SwiftUI
import SunlitCore

/// The map planning view.
///
/// One pin, and every direction that matters drawn from it: where the sun rises
/// and sets today, where the moon does, where the sun is standing right now, and
/// the shadow an object of a chosen height throws, at the scale the map is drawn
/// at.
///
/// This is the one screen in Sunlit that touches the network, because Apple
/// serves the map tiles. Nothing else here does. Every bearing, every time, and
/// every length on this screen comes out of `DayReport` and `SkyMoment`, which
/// are computed on the device with no connection of any kind, and the panel says
/// so where a reader can see it.
struct MapPlanView: View {

    @Environment(AppState.self) private var state
    @Environment(LocationProvider.self) private var location
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var camera: MapCameraPosition = .automatic
    @State private var bearings: DayBearings?
    @State private var isComputingDay = true

    /// Drives the live sun ray. The scrubber does not move on this screen, so
    /// following the wall clock is the only thing that makes the ray live, and
    /// thirty seconds moves the sun by about a tenth of a degree.
    ///
    /// A `@State` date advanced by a task rather than a `Date()` read inside the
    /// body: the body has to depend on something SwiftUI can see change, and a
    /// bare `Date()` is invisible to it, so the ray would be drawn once and then
    /// stand still.
    @State private var clockTick = Date()

    @State private var objectHeightMetres: Double = 10
    @State private var visibleSpanMetres: Double = 40_000

    /// Where a reader without the purchase tapped. Drawn greyed, so the tap has
    /// a visible result and the reader can see exactly what buying would move.
    @State private var proposedPin: CLLocationCoordinate2D?

    /// True while the times on screen are being shown in the device's zone
    /// because the pin's own zone could not be resolved.
    @State private var zoneIsDeviceFallback = false
    @State private var isResolvingZone = false

    /// Every locked control on this screen opens the real purchase screen.
    ///
    /// It used to open a sheet of this file's own that restated the free tier,
    /// the paid tier and the price, and offered a way through to the paywall
    /// only if a caller had injected one. Nothing injects one, so in the app as
    /// assembled the only button on it said Close. A gated feature has to offer
    /// a route to the paywall, and `proPaywall` is the single named seam this
    /// module already has for it.
    @State private var showingPaywall = false
    @State private var showingPlaceSheet = false
    @State private var showingDateSheet = false
    @State private var hasPositioned = false
    @State private var suppressRecentre = false
    @State private var awaitingLocationFix = false

    // MARK: Body

    var body: some View {
        let moment = SkyMoment.at(JulianDay(date: displayInstant), place: state.place)
        let projection = ShadowProjection.make(moment: moment, heightMetres: objectHeightMetres)
        let rays = SkyRayBuilder.rays(
            bearings: bearings,
            sunNowAzimuth: moment.sun.azimuth,
            sunNowTitle: liveRayTitle,
            origin: pinCoordinate,
            lengthMetres: rayLengthMetres,
            moonUnlocked: state.pro.allows(.moon))
        let altitude = moment.sun.altitude

        return GeometryReader { proxy in
            VStack(spacing: 0) {
                GlobalHeader(
                    showingPlacePicker: $showingPlaceSheet,
                    showingDatePicker: $showingDateSheet,
                    solarAltitude: altitude)

                mapSection(rays: rays, projection: projection)
                    .frame(height: mapHeight(container: proxy.size.height))

                // Everything a finger has to reach lives inside this scroll
                // view. At the accessibility text sizes the map shrinks and the
                // panel grows, and no control on this screen can be pushed off
                // the canvas, which is the rejection two apps in this portfolio
                // have already paid for.
                ScrollView {
                    panel(moment: moment, rays: rays, projection: projection)
                }
            }
        }
        .adaptiveSky(
            solarAltitude: altitude,
            moonIllumination: moment.moonPhase.illuminatedFraction)
        .task(id: dayKey) { await loadDay() }
        .task { await followTheClock() }
        .onChange(of: state.place.id) { _, _ in
            if suppressRecentre {
                suppressRecentre = false
            } else {
                recentre(on: pinCoordinate)
            }
        }
        .onChange(of: locationFixKey) { _, _ in
            guard awaitingLocationFix else { return }
            adoptCurrentLocation()
        }
        // The shared pickers, not versions of this screen's own. The place sheet
        // written here offered nothing but the current location, so the Map tab
        // was the one tab from which the embedded city list could not be
        // reached at all, and its date sheet resolved the chosen day through the
        // device calendar, which lands on the wrong local day for any place far
        // enough east or west of the reader.
        .sheet(isPresented: $showingPlaceSheet) {
            PlacePickerView()
        }
        .sheet(isPresented: $showingDateSheet) {
            DatePickerSheet()
        }
        .proPaywall(isPresented: $showingPaywall)
    }

    // MARK: The map

    private func mapSection(rays: [SkyRay], projection: ShadowProjection) -> some View {
        MapReader { proxy in
            Map(position: $camera, interactionModes: .all) {
                SkyRayMapContent(rays: rays, timeZone: placeTimeZone)
                ShadowMapContent(projection: projection)

                Annotation(coordinate: pinCoordinate, anchor: .bottom) {
                    PinMarker(isCurrentLocation: state.isCurrentLocation)
                } label: {
                    Text(verbatim: "")
                }

                if let proposedPin {
                    Annotation(coordinate: proposedPin, anchor: .bottom) {
                        ProposedPinMarker()
                    } label: {
                        Text(verbatim: "")
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .onTapGesture(count: 1, coordinateSpace: .local) { point in
                guard let coordinate = proxy.convert(point, from: .local) else { return }
                move(to: coordinate, recentre: false)
            }
            .gesture(dropGesture(proxy: proxy))
            .onMapCameraChange(frequency: .onEnd) { context in
                let metres = context.region.span.latitudeDelta * 111_320
                visibleSpanMetres = min(max(metres, 400), 4_000_000)
            }
            .accessibilityLabel(Text(mapAccessibilityLabel))
            .accessibilityHint(Text(mapAccessibilityHint))
        }
    }

    /// Press and hold drops a pin and brings the camera with it.
    ///
    /// The long press has to succeed before the drag in the sequence engages, so
    /// an ordinary pan, which moves at once, fails it and reaches the map
    /// untouched. The drag is only there to carry the point that was held.
    private func dropGesture(proxy: MapProxy) -> some Gesture {
        LongPressGesture(minimumDuration: 0.45)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
            .onEnded { value in
                guard case .second(true, let drag?) = value else { return }
                guard let coordinate = proxy.convert(drag.location, from: .local) else { return }
                move(to: coordinate, recentre: true)
            }
    }

    private func mapHeight(container: CGFloat) -> CGFloat {
        let fraction: CGFloat = typeSize.isAccessibilitySize ? 0.30 : 0.44
        return min(max(container * fraction, 150), 420)
    }

    // MARK: The panel

    private func panel(
        moment: SkyMoment,
        rays: [SkyRay],
        projection: ShadowProjection
    ) -> some View {
        VStack(alignment: .leading, spacing: 26) {
            timeZoneNotice

            section(sunSectionTitle) {
                sunRows(moment: moment, rays: rays)
            }

            section(moonSectionTitle) {
                moonRows(rays: rays)
            }

            section(shadowSectionTitle) {
                ShadowHeightControl(
                    heightMetres: $objectHeightMetres,
                    projection: projection,
                    onFit: { fitShadow(projection) })
            }

            section(placeSectionTitle) {
                placeRows(altitude: moment.sun.altitude)
            }

            Text(networkNotice)
                .font(SunlitType.caption)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(Text(networkNotice))
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 44)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).sunlitLabel()
            HairlineDivider()
            content()
        }
    }

    @ViewBuilder
    private func sunRows(moment: SkyMoment, rays: [SkyRay]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if isComputingDay && bearings == nil {
                Text(computingLabel).font(SunlitType.body)
            }
            if let bearings, bearings.polarDay {
                Text(polarDayNote)
                    .font(SunlitType.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let bearings, bearings.polarNight {
                Text(polarNightNote)
                    .font(SunlitType.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(rays.filter { $0.kind == .sunrise || $0.kind == .sunset }) { ray in
                SkyRayRow(ray: ray, timeZone: placeTimeZone)
            }
            ForEach(rays.filter { $0.kind == .sunNow }) { ray in
                SkyRayRow(
                    ray: ray,
                    timeZone: placeTimeZone,
                    subtitle: sunAltitudeSubtitle(moment))
            }
        }
    }

    @ViewBuilder
    private func moonRows(rays: [SkyRay]) -> some View {
        let moonRays = rays.filter { $0.kind == .moonrise || $0.kind == .moonset }
        VStack(alignment: .leading, spacing: 16) {
            ForEach(moonRays) { ray in
                SkyRayRow(
                    ray: ray,
                    timeZone: placeTimeZone,
                    onUnlock: { showingPaywall = true })
            }
            if bearings != nil && moonRays.isEmpty {
                Text(noMoonEventNote)
                    .font(SunlitType.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !state.pro.allows(.moon) {
                LockCard(
                    message: moonLockMessage,
                    onUnlock: { showingPaywall = true })
            }
        }
    }

    private func placeRows(altitude: Double) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            MetricGroup {
                MetricReadout(
                    label: coordinateLabel,
                    value: MapFormat.coordinate(pinCoordinate),
                    valueFont: SunlitType.metricSmall)
            }

            Button {
                useCurrentLocation()
            } label: {
                Label {
                    Text(currentLocationLabel).font(SunlitType.body)
                } icon: {
                    Image(systemName: "location.fill")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            SkyPalette.componentBorder(solarAltitude: altitude),
                            lineWidth: 1)
                }
                .sunlitTouchTarget()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(currentLocationLabel))

            if locationIsRefused {
                Text(locationRefusedNote)
                    .font(SunlitType.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(tapHint)
                .font(SunlitType.caption)
                .fixedSize(horizontal: false, vertical: true)

            if proposedPin != nil {
                LockCard(
                    message: placeLockMessage,
                    onUnlock: { showingPaywall = true })
            }
        }
    }

    @ViewBuilder
    private var timeZoneNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(zoneIsDeviceFallback ? deviceZoneNotice : placeZoneNotice)
                .font(SunlitType.caption)
                .fixedSize(horizontal: false, vertical: true)
            if isResolvingZone {
                Text(resolvingZoneNotice)
                    .font(SunlitType.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Derived values

    /// The instant the whole screen is drawn for.
    ///
    /// While the app follows the wall clock this is the timer's tick rather than
    /// `Date()`, so the dependency is one SwiftUI can see and the live ray
    /// actually redraws.
    ///
    /// A selected day that is not today has no "now" in it. `AppState.instant`
    /// hands back the real clock whenever the scrubber is parked, so reading it
    /// straight drew the sun's live position, the live shadow and the live sky
    /// gradient on a screen whose sunrise and sunset belong to a different date.
    /// Local noon is the instant the rest of the app falls back to for exactly
    /// this reason.
    private var displayInstant: Date {
        if state.scrubSeconds != nil { return state.instant }
        if state.isToday { return clockTick }
        return state.place.startOfLocalDay(containing: state.day).date
            .addingTimeInterval(43_200)
    }

    /// What to call the ray that points at the sun's present direction.
    ///
    /// "Sun now" is only true on the day being lived through. On any other date
    /// the figure beside it is local noon on that date, and a label that says
    /// otherwise is the same lie as an unmarked model.
    private var liveRayTitle: String {
        guard !state.isToday else { return SkyRay.Kind.sunNow.title }
        return String(
            localized: "map.ray.sunAtNoon", defaultValue: "Sun at local noon",
            comment: "Label of the sun direction ray on a selected day that is not today")
    }

    private var pinCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: state.place.latitude, longitude: state.place.longitude)
    }

    /// The zone every clock time on this screen is expressed in.
    private var placeTimeZone: TimeZone {
        TimeZone(identifier: state.place.timeZoneIdentifier) ?? .current
    }

    /// Rays are sized to the map rather than fixed, so one always reaches across
    /// the screen and its label lands inside it at every zoom.
    private var rayLengthMetres: Double {
        max(visibleSpanMetres * 0.42, 300)
    }

    private var dayKey: String {
        [
            state.place.latitude.description,
            state.place.longitude.description,
            state.place.timeZoneIdentifier,
            state.day.timeIntervalSince1970.description
        ].joined(separator: "|")
    }

    /// True when the device has refused the app its position, so the button
    /// that returns the pin there cannot work and has to say why rather than
    /// doing nothing.
    private var locationIsRefused: Bool {
        location.authorisation == .denied || location.authorisation == .restricted
    }

    private var locationFixKey: String {
        guard let coordinate = location.coordinate else { return "" }
        return coordinate.latitude.description + "," + coordinate.longitude.description
    }

    // MARK: Actions

    /// Advances the clock the live ray is drawn against.
    ///
    /// Main actor by declaration. `View.task` takes a `@Sendable` closure, so a
    /// plain method called from it runs on the cooperative pool and every
    /// `@State` write below would be a write to view state off the main thread.
    @MainActor
    private func followTheClock() async {
        while !Task.isCancelled {
            clockTick = Date()
            try? await Task.sleep(for: .seconds(30))
        }
    }

    @MainActor
    private func loadDay() async {
        isComputingDay = true
        let place = state.place
        let start = place.startOfLocalDay(containing: state.day)
        let computed = await Task.detached(priority: .userInitiated) {
            DayBearings.from(report: DayReport.compute(date: start, place: place))
        }.value
        guard !Task.isCancelled else { return }
        bearings = computed
        isComputingDay = false
        if !hasPositioned {
            hasPositioned = true
            recentre(on: pinCoordinate)
        }
    }

    /// Moves the pin, and with it every other view in the app.
    private func move(to coordinate: CLLocationCoordinate2D, recentre shouldRecentre: Bool) {
        guard state.pro.allows(.savedPlaces) else {
            // The tap is not swallowed. The pin the reader asked for appears,
            // greyed, next to a card that says what it would take to move the
            // real one. A feature that simply does nothing reads as a bug.
            proposedPin = coordinate
            return
        }
        proposedPin = nil
        suppressRecentre = !shouldRecentre

        let name = String(
            localized: "map.pinName",
            defaultValue: "Pin \(MapFormat.coordinate(coordinate))",
            comment: "Name given to a pin dropped on the map, followed by its coordinates")
        state.place = Place(
            name: name,
            geographic: Coordinates.Geographic(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                elevation: 0),
            timeZoneIdentifier: TimeZone.current.identifier,
            isCurrentLocation: false)
        state.isCurrentLocation = false
        // Said before it is known to be wrong, not after. The pin's own zone
        // needs a network lookup, and until that lookup answers, every time on
        // this screen is a device time zone time and the notice says so.
        zoneIsDeviceFallback = true

        if shouldRecentre { recentre(on: coordinate) }
        Task { await resolveTimeZone(for: coordinate) }
    }

    /// Asks the network for the pin's real time zone and a name for it.
    ///
    /// Offline this fails, and failing is fine: the fallback is already in place
    /// and already announced. What is not fine is showing a resolved time as
    /// though it were certain, which is why nothing here writes a zone it did
    /// not receive.
    @MainActor
    private func resolveTimeZone(for coordinate: CLLocationCoordinate2D) async {
        isResolvingZone = true
        defer { isResolvingZone = false }
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first else {
            return
        }
        // The reader may have moved the pin again while this was in flight.
        guard abs(state.place.latitude - coordinate.latitude) < 1e-9,
              abs(state.place.longitude - coordinate.longitude) < 1e-9 else { return }

        var place = state.place
        if let zone = placemark.timeZone {
            place.timeZoneIdentifier = zone.identifier
            zoneIsDeviceFallback = false
        }
        if let name = placemark.locality
            ?? placemark.subAdministrativeArea
            ?? placemark.administrativeArea
            ?? placemark.country {
            place.name = name
        }
        suppressRecentre = true
        state.place = place
    }

    private func useCurrentLocation() {
        location.requestAuthorisation()
        location.refresh()
        if location.coordinate == nil {
            awaitingLocationFix = true
        } else {
            adoptCurrentLocation()
        }
    }

    private func adoptCurrentLocation() {
        let name = String(
            localized: "map.currentLocation",
            defaultValue: "Current Location",
            comment: "Name of the place that is the device's own position")
        guard var place = location.currentPlace(named: name) else { return }
        place.isCurrentLocation = true
        awaitingLocationFix = false
        proposedPin = nil
        // The device's own zone is the right zone where the device is, so there
        // is nothing to warn about here.
        zoneIsDeviceFallback = false
        suppressRecentre = true
        state.place = place
        state.isCurrentLocation = true
        recentre(on: CLLocationCoordinate2D(
            latitude: place.latitude, longitude: place.longitude))
    }

    private func recentre(on coordinate: CLLocationCoordinate2D) {
        camera = .region(MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: visibleSpanMetres,
            longitudinalMeters: visibleSpanMetres))
    }

    private func fitShadow(_ projection: ShadowProjection) {
        let span = projection.fittingSpanMetres
        visibleSpanMetres = span
        camera = .region(MKCoordinateRegion(
            center: pinCoordinate,
            latitudinalMeters: span,
            longitudinalMeters: span))
    }

    // MARK: Strings

    private var sunSectionTitle: String {
        String(localized: "map.section.sun", defaultValue: "Sun rays",
               comment: "Heading of the block of sun directions under the map")
    }

    private var moonSectionTitle: String {
        String(localized: "map.section.moon", defaultValue: "Moon rays",
               comment: "Heading of the block of moon directions under the map")
    }

    private var shadowSectionTitle: String {
        String(localized: "map.section.shadow", defaultValue: "Shadow",
               comment: "Heading of the shadow projection block under the map")
    }

    private var placeSectionTitle: String {
        String(localized: "map.section.place", defaultValue: "Place",
               comment: "Heading of the block that moves the pin")
    }

    private var coordinateLabel: String {
        String(localized: "map.coordinate", defaultValue: "Coordinates",
               comment: "Label of the readout giving the pin's latitude and longitude")
    }

    private var currentLocationLabel: String {
        String(localized: "map.useCurrentLocation", defaultValue: "Use current location",
               comment: "Button that returns the pin to where the device is")
    }

    private var computingLabel: String {
        String(localized: "map.computing", defaultValue: "Working out the day",
               comment: "Shown while the day's events are still being computed")
    }

    private var tapHint: String {
        String(
            localized: "map.tapHint",
            defaultValue: "Tap the map to move the pin. Press and hold to drop one and centre on it. Every other view follows the pin.",
            comment: "Explains the two ways of moving the pin")
    }

    private var placeZoneNotice: String {
        String(
            localized: "map.zone.place",
            defaultValue: "Times shown in \(state.place.timeZoneIdentifier).",
            comment: "States which time zone the times on this screen are expressed in")
    }

    private var deviceZoneNotice: String {
        String(
            localized: "map.zone.device",
            defaultValue: "Times shown in your device time zone, \(TimeZone.current.identifier). This pin's own time zone needs a network lookup, so it has not been confirmed.",
            comment: "Warns that the times are in the device zone because the pin's zone is unknown")
    }

    private var resolvingZoneNotice: String {
        String(
            localized: "map.zone.resolving",
            defaultValue: "Looking up this pin's time zone.",
            comment: "Shown while a reverse geocode is in flight")
    }

    private var locationRefusedNote: String {
        String(
            localized: "map.locationRefused",
            defaultValue: "Sunlit has no access to your position, so it cannot put the pin there. You can grant it in Settings, or tap the map to choose a place by hand.",
            comment: "Shown when location permission has been denied and the current location button cannot work")
    }

    private var networkNotice: String {
        String(
            localized: "map.networkNotice",
            defaultValue: "Apple serves the map tiles over the network. Every bearing, time and length here is worked out on your device and needs no connection. The one thing looked up over the network is a dropped pin's own time zone, and the note at the top of this panel says when that lookup has not answered.",
            comment: "States that the map tiles come from the network while the figures do not")
    }

    private var polarDayNote: String {
        String(
            localized: "map.polarDay",
            defaultValue: "The sun stays above the horizon all day here, so there is no sunrise or sunset to point at.",
            comment: "Shown at high latitudes in summer")
    }

    private var polarNightNote: String {
        String(
            localized: "map.polarNight",
            defaultValue: "The sun stays below the horizon all day here, so there is no sunrise or sunset to point at.",
            comment: "Shown at high latitudes in winter")
    }

    private var noMoonEventNote: String {
        String(
            localized: "map.noMoonEvent",
            defaultValue: "The moon neither rises nor sets on this day here. It rises about fifty minutes later each day, so about once a month a calendar day has no moonrise in it at all.",
            comment: "Shown when the day contains no moonrise and no moonset")
    }

    private var moonLockMessage: String {
        String(
            localized: "map.locked.moon",
            defaultValue: "The moon's rise and set directions are part of Sunlit Pro. They are drawn faintly above so you can see what they add.",
            comment: "Card explaining that the moon rays are a paid capability")
    }

    private var placeLockMessage: String {
        String(
            localized: "map.locked.place",
            defaultValue: "Scouting a place other than where you are is part of Sunlit Pro. The pin you tapped is marked on the map.",
            comment: "Card explaining that moving the pin is a paid capability")
    }

    private var mapAccessibilityLabel: String {
        String(
            localized: "map.map.label",
            defaultValue: "Map around \(state.place.name)",
            comment: "Accessibility label of the map itself")
    }

    private var mapAccessibilityHint: String {
        String(
            localized: "map.map.hint",
            defaultValue: "Double tap to move the pin here. The figures below give every direction in degrees.",
            comment: "Accessibility hint of the map itself")
    }

    private func sunAltitudeSubtitle(_ moment: SkyMoment) -> String {
        let value = moment.sun.altitude.formatted(.number.precision(.fractionLength(1)))
        guard !state.isToday else {
            return String(
                localized: "map.sun.altitudeNow",
                defaultValue: "Altitude \(value) degrees",
                comment: "Subtitle of the live sun ray, giving how high the sun stands")
        }
        let clock = MapFormat.time(displayInstant, in: placeTimeZone)
        return String(
            localized: "map.sun.altitudeAt",
            defaultValue: "At \(clock), altitude \(value) degrees",
            comment: "Subtitle of the sun ray on a day that is not today, naming the instant it is drawn for")
    }
}

// MARK: - Markers

/// The pin itself.
struct PinMarker: View {

    @Environment(\.solarAltitude) private var solarAltitude
    let isCurrentLocation: Bool

    var body: some View {
        Image(systemName: isCurrentLocation ? "location.circle.fill" : "mappin.circle.fill")
            .font(.system(size: 28))
            .symbolRenderingMode(.palette)
            .foregroundStyle(Color.white, Color.black.opacity(0.75))
            .accessibilityLabel(Text(label))
    }

    private var label: String {
        isCurrentLocation
            ? String(localized: "map.pin.current", defaultValue: "Your position",
                     comment: "Accessibility label of the pin when it sits on the device's own position")
            : String(localized: "map.pin.chosen", defaultValue: "Chosen place",
                     comment: "Accessibility label of the pin when it sits on a chosen place")
    }
}

/// The greyed pin a reader without the purchase gets when they tap.
struct ProposedPinMarker: View {

    var body: some View {
        Image(systemName: "mappin.circle")
            .font(.system(size: 26))
            .foregroundStyle(Color.white.opacity(0.55))
            .accessibilityLabel(Text(String(
                localized: "map.pin.proposed",
                defaultValue: "Place you tapped, locked",
                comment: "Accessibility label of the greyed pin shown to a reader without the purchase")))
    }
}

// MARK: - Locks

/// The inline card that names a locked capability and offers the way out of it.
struct LockCard: View {

    @Environment(\.solarAltitude) private var solarAltitude

    let message: String
    let onUnlock: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(message)
                    .font(SunlitType.caption)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lock.fill").imageScale(.small)
            }
            Button(action: onUnlock) {
                Text(unlockLabel)
                    .font(SunlitType.body)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(
                                SkyPalette.componentBorder(solarAltitude: solarAltitude),
                                lineWidth: 1)
                    }
                    .sunlitTouchTarget()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(unlockLabel))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var unlockLabel: String {
        String(localized: "map.unlockPro", defaultValue: "What Sunlit Pro adds",
               comment: "Button that opens the explanation of the one purchase")
    }
}
