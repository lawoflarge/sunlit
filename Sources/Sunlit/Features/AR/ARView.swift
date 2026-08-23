import SwiftUI
import UIKit
import SunlitCore

/// The camera view: the sun and the moon drawn where they really are.
///
/// This is the hero feature of the category and the one the product Sunlit
/// competes with is criticised for. Three decisions answer that criticism.
///
/// The attitude comes from CoreMotion's fused true north frame through
/// `HeadingProvider`, not from raw magnetic heading. The field of view comes
/// from the capture format the device is actually running, not from a constant,
/// because it differs across iPhone models and a wrong value walks the sun off
/// target toward the edges of the frame. And the uncertainty is on the screen
/// at all times: a number with a stated error is an instrument, a number
/// without one is a guess wearing a uniform.
///
/// There is no ARKit here. World tracking buys this view nothing, because every
/// body it draws is at infinity and its place on the screen depends only on
/// which way the phone points.
struct ARView: View {

    @Environment(AppState.self) private var state
    @Environment(HeadingProvider.self) private var heading
    @Environment(\.openURL) private var openURL
    @Environment(\.locale) private var locale

    @State private var camera = CameraFeed()
    @State private var sweep = HorizonSweepSession()

    /// The parts of the scene that depend only on the place and the day, which
    /// are the expensive ones.
    @State private var dayScene = ARScene()
    /// The same scene with the selected instant applied. This is what is drawn.
    @State private var scene = ARScene()

    @State private var showSun = true
    @State private var showMoon = true
    @State private var showAnnualPaths = true
    @State private var showMilkyWay = true
    @State private var showHorizon = true
    @State private var showingPaywall = false

    /// Advances every thirty seconds so the markers follow the real clock.
    ///
    /// The sun moves a quarter of a degree per minute, so half a minute of
    /// staleness is an eighth of a degree, which is a fifth of the sun's own
    /// width and invisible. Recomputing per frame instead would put an
    /// ephemeris evaluation inside the draw loop for no gain the eye can see.
    @State private var clockTick = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                viewport
                cameraNotice
                readouts
                layerControls
                HairlineDivider()
                HorizonSweepSection(
                    sweep: sweep,
                    isUnlocked: state.pro.allows(.terrain),
                    aim: aim,
                    headingIsTrustworthy: !heading.quality.needsCalibration,
                    onSave: saveSweptSkyline,
                    onUnlockRequested: { showingPaywall = true })
                notes
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        // Every screen scrolls. The viewport has a fixed aspect rather than a
        // flexible height, so at the largest text sizes the controls below it
        // move down the scroll view instead of being pushed off the canvas.
        .adaptiveSky(
            solarAltitude: scene.solarAltitude,
            moonIllumination: scene.moonIllumination)
        .onAppear {
            camera.requestAccess()
            heading.start()
        }
        .onDisappear {
            camera.stop()
            heading.stop()
            sweep.endRecording()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                clockTick &+= 1
            }
        }
        .task(id: dayKey) { await rebuildDay() }
        .task(id: momentKey) { applyMoment() }
        .onChange(of: attitude) { _, sample in
            guard sweep.isRecording else { return }
            sweep.record(aim: ARProjection.cameraAim(
                headingDegrees: sample.heading,
                pitchDegrees: sample.pitch,
                rollDegrees: sample.roll))
        }
        .sheet(isPresented: $showingPaywall) { ARPaywallRoute() }
    }

    // MARK: The viewport

    private var viewport: some View {
        Color.clear
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    ZStack {
                        backdrop
                        SkyOverlay(
                            scene: scene,
                            projection: projection(in: proxy.size),
                            layers: layerVisibility)
                        crosshair
                        chrome
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        SkyPalette.componentBorder(solarAltitude: scene.solarAltitude),
                        lineWidth: 1)
            }
            .padding(.top, 8)
    }

    /// The camera image when there is one, and the sky itself when there is not.
    ///
    /// The fallback is never black and never empty. It is the adaptive gradient
    /// at the selected instant, which is the colour the sky actually is, with
    /// the same overlay drawn over it. Everything except the photograph still
    /// works.
    @ViewBuilder
    private var backdrop: some View {
        if camera.access.allowsCapture {
            CameraPreview(session: camera.session)
        } else {
            SkyPalette.gradient(
                solarAltitude: scene.solarAltitude,
                moonIllumination: scene.moonIllumination)
        }
    }

    private var crosshair: some View {
        Image(systemName: "plus")
            .font(.system(size: 22, weight: .thin))
            .foregroundStyle(
                sweep.isRecording
                    ? SkyColors.sun
                    : SkyPalette.instrumentLine(solarAltitude: scene.solarAltitude))
            .accessibilityHidden(true)
    }

    /// The one thing that lives on top of the image.
    ///
    /// The camera permission panel deliberately does not. The viewport has a
    /// fixed aspect and is clipped, so a panel inside it at the largest text
    /// size would have its button cropped off the bottom, which is the exact
    /// shape of the rejection that took down two apps in this portfolio. It
    /// sits under the viewport instead, inside the scroll view, where it can
    /// always be reached.
    private var chrome: some View {
        VStack(spacing: 12) {
            HStack {
                Spacer(minLength: 0)
                headingChip
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    /// `HeadingProvider` calls a reading poor at twenty degrees or more.
    /// `AccuracyChip` turns amber strictly above the threshold it is handed, so
    /// the threshold here is the largest double below twenty. Without that the
    /// chip stays calm at exactly twenty degrees while the note underneath says
    /// the compass needs calibrating and the sweep button is disabled, and
    /// twenty is not a hypothetical: `CLHeading.headingAccuracy` reports whole
    /// numbers.
    private static let calibrationThreshold = 20.0.nextDown

    /// The heading uncertainty, permanently on screen.
    ///
    /// Amber exactly when `HeadingProvider` says the reading needs calibrating,
    /// so the colour and the sensor layer agree on one definition rather than
    /// each carrying its own. A reading the device declines to give at all is a
    /// different state and says so, because "plus or minus minus one degrees"
    /// is not a measurement.
    @ViewBuilder
    private var headingChip: some View {
        if heading.accuracyDegrees >= 0 {
            AccuracyChip(degrees: heading.accuracyDegrees, poorAbove: Self.calibrationThreshold)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .imageScale(.small)
                    .accessibilityHidden(true)
                Text(String(
                    localized: "ar.heading.unavailable", defaultValue: "No compass",
                    comment: "Chip shown when the device gives no heading accuracy at all"))
                    .font(SunlitType.metricSmall)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background { Capsule(style: .continuous).fill(SkyColors.warning) }
            .foregroundStyle(SkyColors.onWarning)
            .sunlitTouchTarget()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(String(
                localized: "ar.heading.unavailable.axLabel",
                defaultValue: "No heading available. The overlay cannot be aimed.",
                comment: "Spoken form of the chip shown when there is no heading at all")))
        }
    }

    /// The camera permission states. Every one of them is a screen, not a crash
    /// and not a black rectangle.
    @ViewBuilder
    private var cameraNotice: some View {
        switch camera.access {
        case .authorised:
            EmptyView()
        case .undetermined:
            noticePanel(
                message: String(
                    localized: "ar.camera.undetermined",
                    defaultValue: "Sunlit can draw these paths over your real view. The image stays on your device and is never recorded or sent anywhere.",
                    comment: "Shown before the camera permission has been asked for"),
                buttonTitle: String(
                    localized: "ar.camera.allow", defaultValue: "Use the camera",
                    comment: "Button that asks for camera permission"),
                action: { camera.requestAccess() })
        case .denied:
            noticePanel(
                message: String(
                    localized: "ar.camera.denied",
                    defaultValue: "Camera access is off, so the paths are drawn over the sky colour instead of over your view. Everything else on this screen still works.",
                    comment: "Shown when the user has refused camera access"),
                buttonTitle: String(
                    localized: "ar.camera.settings", defaultValue: "Open Settings",
                    comment: "Button that opens the app's page in the Settings app"),
                action: openSettings)
        case .restricted:
            noticePanel(
                message: String(
                    localized: "ar.camera.restricted",
                    defaultValue: "The camera is restricted on this device, so the paths are drawn over the sky colour instead. Everything else on this screen still works.",
                    comment: "Shown when device policy forbids camera access"),
                buttonTitle: nil,
                action: {})
        case .unavailable:
            noticePanel(
                message: String(
                    localized: "ar.camera.unavailable",
                    defaultValue: "There is no camera here, so the paths are drawn over the sky colour instead. Everything else on this screen still works.",
                    comment: "Shown on hardware with no back camera"),
                buttonTitle: nil,
                action: {})
        }
    }

    private func noticePanel(
        message: String, buttonTitle: String?, action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message)
                .font(SunlitType.caption)
                .fixedSize(horizontal: false, vertical: true)
            if let buttonTitle {
                Button(action: action) {
                    Text(buttonTitle)
                        .font(SunlitType.body)
                        .sunlitTouchTarget()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(buttonTitle))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        // Outlined, never filled. This panel used to sit on black at forty five
        // percent, and a plate under the ink is the one thing the adaptive sky
        // cannot survive: above the ink crossover the ink is pure black, so the
        // plate darkens exactly what the text has to read against. Swept over
        // the whole altitude domain with the design system's own
        // `SkyContrast.paintedColours`, the audited 4.55 to 1 became 2.02 to 1.
        // This is also the panel App Review sees if it refuses the camera.
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    SkyPalette.componentBorder(solarAltitude: scene.solarAltitude),
                    lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    // MARK: Readouts

    private var readouts: some View {
        VStack(alignment: .leading, spacing: 16) {
            sunReadouts

            // The aim is a reading off this device's own sensors at this
            // moment, not an ephemeris for a chosen day, so it is free at every
            // selection. Locking it would be charging for the compass.
            MetricGroup {
                MetricReadout(
                    label: String(
                        localized: "ar.aim", defaultValue: "Frame centre",
                        comment: "Label of the direction the centre of the camera frame points at"),
                    value: aimValue)
            }

            moonReadouts
        }
    }

    /// The sun's figures, which are free only for today at the current place.
    ///
    /// They used to be printed at full precision whatever the header carried,
    /// while the drawn overlay beside them was dimmed and the note underneath
    /// said the screen was locked. Anyone who moved the date or the pin got the
    /// paid answer for nothing, in the one view that exists to give it, and the
    /// screen contradicted itself while doing it.
    @ViewBuilder
    private var sunReadouts: some View {
        let group = MetricGroup {
            MetricReadout(
                label: String(
                    localized: "ar.sun.azimuth", defaultValue: "Sun azimuth",
                    comment: "Label of the sun's compass bearing in the camera view"),
                value: degrees(scene.sunNow.azimuth), unit: "\u{00B0}")
            MetricReadout(
                label: String(
                    localized: "ar.sun.altitude", defaultValue: "Sun altitude",
                    comment: "Label of the sun's angle above the horizon in the camera view"),
                value: degrees(scene.sunNow.altitude), unit: "\u{00B0}")
        }

        if state.selectionIsFree {
            group
        } else {
            locked(
                group,
                spokenLabel: String(
                    localized: "ar.sun.axLabel", defaultValue: "Sun position",
                    comment: "Accessibility label of the blurred sun figures"),
                message: selectionLockMessage)
        }
    }

    @ViewBuilder
    private var moonReadouts: some View {
        let group = MetricGroup {
            MetricReadout(
                label: String(
                    localized: "ar.moon.azimuth", defaultValue: "Moon azimuth",
                    comment: "Label of the moon's compass bearing in the camera view"),
                value: degrees(scene.moonNow.azimuth), unit: "\u{00B0}")
            MetricReadout(
                label: String(
                    localized: "ar.moon.altitude", defaultValue: "Moon altitude",
                    comment: "Label of the moon's angle above the horizon in the camera view"),
                value: degrees(scene.moonNow.altitude), unit: "\u{00B0}")
            MetricReadout(
                label: String(
                    localized: "ar.moon.lit", defaultValue: "Moon lit",
                    comment: "Label of the fraction of the moon's disc that is illuminated"),
                value: (scene.moonIllumination * 100)
                    .formatted(.number.precision(.fractionLength(0))),
                unit: "%")
        }

        if state.pro.allows(.moon), state.selectionIsFree {
            group
        } else {
            locked(
                group,
                spokenLabel: String(
                    localized: "ar.moon.axLabel", defaultValue: "Moon position",
                    comment: "Accessibility label of the blurred moon figures"),
                message: moonLockMessage)
        }
    }

    /// A block of figures the purchase covers.
    ///
    /// Shown, not hidden. A gated feature that vanishes makes the free app look
    /// broken and gives the reader no way to judge whether the purchase is
    /// worth it. The figures are blurred rather than removed, and VoiceOver is
    /// told the state rather than being read a number the screen is
    /// deliberately obscuring.
    private func locked<Content: View>(
        _ content: Content, spokenLabel: String, message: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content
                .blur(radius: 5)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(spokenLabel))
                .accessibilityValue(Text(lockedSpoken))
            ARUnlockRow(message: message) { showingPaywall = true }
        }
    }

    // MARK: Layers

    private var layerControls: some View {
        // Not named `heading`: that is the sensor in this view's environment,
        // and shadowing it here is how a later edit reads a string where it
        // meant the compass.
        let layersHeading = String(
            localized: "ar.layers.title", defaultValue: "Overlay",
            comment: "Heading of the list of things drawn over the camera image")
        return VStack(alignment: .leading, spacing: 12) {
            // `sunlitLabel` uppercases for the eye, and the design system asks
            // every user of it to hand VoiceOver the original string rather
            // than a run of capitals to guess at.
            Text(layersHeading)
                .sunlitLabel()
                .accessibilityLabel(Text(layersHeading))

            ARLayerToggle(
                title: String(
                    localized: "ar.layer.sun", defaultValue: "Sun path today",
                    comment: "Name of the sun path layer"),
                tint: SkyColors.sun,
                isOn: showSun, isLocked: false,
                toggle: { showSun.toggle() }, unlock: {})

            ARLayerToggle(
                title: String(
                    localized: "ar.layer.moon", defaultValue: "Moon path today",
                    comment: "Name of the moon path layer"),
                tint: SkyColors.moon,
                isOn: showMoon, isLocked: !state.pro.allows(.moon),
                toggle: { showMoon.toggle() }, unlock: { showingPaywall = true })

            ARLayerToggle(
                title: String(
                    localized: "ar.layer.annual", defaultValue: "Solstices and equinox",
                    comment: "Name of the reference paths layer"),
                tint: SkyPalette.instrumentLine(solarAltitude: scene.solarAltitude),
                isOn: showAnnualPaths, isLocked: !state.pro.allows(.annualPaths),
                toggle: { showAnnualPaths.toggle() }, unlock: { showingPaywall = true })

            ARLayerToggle(
                title: String(
                    localized: "ar.layer.milkyWay", defaultValue: "Milky Way",
                    comment: "Name of the galactic plane layer"),
                tint: SkyColors.milkyWay,
                isOn: showMilkyWay, isLocked: !state.pro.allows(.milkyWay),
                toggle: { showMilkyWay.toggle() }, unlock: { showingPaywall = true })

            ARLayerToggle(
                title: String(
                    localized: "ar.layer.horizon", defaultValue: "Horizon",
                    comment: "Name of the horizon line layer"),
                tint: SkyPalette.instrumentLine(solarAltitude: scene.solarAltitude),
                isOn: showHorizon, isLocked: false,
                toggle: { showHorizon.toggle() }, unlock: {})

            if showMilkyWay, !scene.skyIsAstronomicallyDark {
                Text(String(
                    localized: "ar.milkyWay.notDark",
                    defaultValue: "The Milky Way is drawn once the sun is more than eighteen degrees below the horizon. It is not dark enough at the selected time.",
                    comment: "Explains why the galactic plane is not drawn"))
                    .font(SunlitType.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Notes

    private var notes: some View {
        VStack(alignment: .leading, spacing: 10) {
            HairlineDivider()
            Text(accuracyNote)
                .font(SunlitType.caption)
                .fixedSize(horizontal: false, vertical: true)
            if !camera.optics.isMeasured {
                Text(String(
                    localized: "ar.optics.assumed",
                    defaultValue: "No camera is reporting its lens here, so the overlay is drawn at an assumed field of view.",
                    comment: "Says that the overlay scale is assumed rather than read from the camera"))
                    .font(SunlitType.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if scene.hasMeasuredHorizon {
                Text(String(
                    localized: "ar.skyline.measured",
                    defaultValue: "The dashed line is the skyline measured at this place.",
                    comment: "Explains the dashed curve drawn from a measured horizon profile"))
                    .font(SunlitType.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var accuracyNote: String {
        if heading.quality.needsCalibration {
            return String(
                localized: "ar.accuracy.calibrate",
                defaultValue: "The compass needs calibrating. Move the phone in a figure of eight, and stand clear of metal, magnets and car dashboards.",
                comment: "Told to the user when the heading uncertainty is too large to trust")
        }
        return String(
            localized: "ar.accuracy.note",
            defaultValue: "The figure at the top of the frame is the compass uncertainty the device reports. The positions themselves are computed, not measured, and are accurate to far better than the compass can be aimed.",
            comment: "Explains what the heading uncertainty chip means")
    }

    // MARK: Layer visibility

    private var layerVisibility: ARLayerVisibility {
        ARLayerVisibility(
            sun: showSun,
            moon: showMoon,
            moonLocked: !state.pro.allows(.moon),
            annualPaths: showAnnualPaths,
            annualPathsLocked: !state.pro.allows(.annualPaths),
            milkyWay: showMilkyWay,
            milkyWayLocked: !state.pro.allows(.milkyWay),
            horizon: showHorizon,
            selectionLocked: !state.selectionIsFree,
            sweepTrace: state.pro.allows(.terrain) ? sweep.trace : [])
    }

    // MARK: Attitude

    /// The three angles, as one equatable value, so `onChange` fires once per
    /// attitude update rather than three times.
    private struct AttitudeSample: Equatable {
        var heading: Double
        var pitch: Double
        var roll: Double
    }

    private var attitude: AttitudeSample {
        AttitudeSample(
            heading: heading.trueHeading,
            pitch: heading.pitchDegrees,
            roll: heading.rollDegrees)
    }

    private var aim: SkyPoint {
        ARProjection.cameraAim(
            headingDegrees: heading.trueHeading,
            pitchDegrees: heading.pitchDegrees,
            rollDegrees: heading.rollDegrees)
    }

    private func projection(in size: CGSize) -> ARProjection {
        ARProjection(
            size: size,
            optics: camera.optics,
            headingDegrees: heading.trueHeading,
            pitchDegrees: heading.pitchDegrees,
            rollDegrees: heading.rollDegrees)
    }

    // MARK: Building the scene

    private struct DayKey: Equatable {
        var place: UUID
        var latitude: Double
        var longitude: Double
        var day: Date
        var skyline: Bool
    }

    private struct MomentKey: Equatable {
        var place: UUID
        var day: Date
        var scrub: TimeInterval?
        var tick: Int
    }

    private var dayKey: DayKey {
        DayKey(
            place: state.place.id,
            latitude: state.place.latitude,
            longitude: state.place.longitude,
            day: state.day,
            skyline: state.place.horizonProfile?.isMeasured ?? false)
    }

    private var momentKey: MomentKey {
        MomentKey(place: state.place.id, day: state.day, scrub: state.scrubSeconds, tick: clockTick)
    }

    /// Four day reports, off the main actor.
    ///
    /// Each one is a couple of thousand ephemeris evaluations. Doing this on the
    /// thread that redraws the overlay at twenty hertz would stall the view for
    /// long enough to be seen every time the date or the place changes.
    private func rebuildDay() async {
        let place = state.place
        let day = state.day
        let currentLocale = locale
        let built = await Task.detached(priority: .userInitiated) {
            ARScene.buildDay(place: place, day: day, locale: currentLocale)
        }.value
        dayScene = built
        applyMoment()
    }

    private func applyMoment() {
        var next = dayScene
        next.applyMoment(place: state.place, instant: state.instant)
        scene = next
    }

    // MARK: Saving a sweep

    private func saveSweptSkyline() {
        guard state.pro.allows(.terrain), sweep.hasAnyReading else { return }
        state.place.horizonProfile = sweep.profile
    }

    // MARK: Formatting

    private func degrees(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    private var aimValue: String {
        let azimuth = degrees(aim.azimuth)
        let altitude = degrees(aim.altitude)
        return String(
            localized: "ar.aim.value",
            defaultValue: "\(azimuth)\u{00B0} az, \(altitude)\u{00B0} alt",
            comment: "The bearing and altitude the centre of the camera frame points at")
    }

    private var lockedSpoken: String {
        String(
            localized: "ar.locked.value", defaultValue: "Locked",
            comment: "Spoken in place of a figure that is hidden behind the purchase")
    }

    /// Why a figure is dimmed when the header has moved off today or off the
    /// device's own position. Carried by the sun block, which is the first
    /// locked thing on the screen, so there is exactly one route to the
    /// purchase for this state rather than one per affected block.
    private var selectionLockMessage: String {
        String(
            localized: "ar.selection.locked",
            defaultValue: "Today at your current location is free forever. This screen is showing another day or another place, so the figures and the overlay are dimmed until Sunlit Pro is unlocked.",
            comment: "Explains why the figures and the drawn overlay are dimmed")
    }

    private var moonLockMessage: String {
        if !state.pro.allows(.moon) {
            return String(
                localized: "ar.moon.locked",
                defaultValue: "The moon is part of Sunlit Pro: its path over your view, its phase, and its rise and set with parallax.",
                comment: "Explanation shown when the moon figures are locked")
        }
        return String(
            localized: "ar.moon.lockedSelection",
            defaultValue: "Today at your current location is free forever. Another day or another place is part of Sunlit Pro.",
            comment: "Explanation shown when the moon figures are locked by the date or the place")
    }
}

// MARK: - Layer toggle

/// One line of the overlay list.
///
/// A locked layer keeps its row and its colour and opens the purchase screen
/// instead of toggling, so the list always describes the whole feature rather
/// than only the part that has been paid for.
struct ARLayerToggle: View {

    let title: String
    let tint: Color
    let isOn: Bool
    let isLocked: Bool
    let toggle: () -> Void
    let unlock: () -> Void

    @Environment(\.displayScale) private var displayScale
    @Environment(\.solarAltitude) private var solarAltitude

    var body: some View {
        Button {
            if isLocked { unlock() } else { toggle() }
        } label: {
            HStack(spacing: 12) {
                Rectangle()
                    .fill(tint)
                    .frame(width: 18, height: max(2 / displayScale, 2))
                    .accessibilityHidden(true)
                Text(title)
                    .font(SunlitType.body)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Image(systemName: indicator)
                    .imageScale(.medium)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .sunlitTouchTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(spokenState))
        .accessibilityAddTraits(.isButton)
    }

    private var indicator: String {
        if isLocked { return "lock.fill" }
        return isOn ? "checkmark.circle.fill" : "circle"
    }

    private var spokenState: String {
        if isLocked {
            return String(
                localized: "ar.layer.axLocked", defaultValue: "Locked",
                comment: "Spoken state of an overlay layer that needs the purchase")
        }
        return isOn
            ? String(
                localized: "ar.layer.axOn", defaultValue: "Shown",
                comment: "Spoken state of an overlay layer that is drawn")
            : String(
                localized: "ar.layer.axOff", defaultValue: "Hidden",
                comment: "Spoken state of an overlay layer that is not drawn")
    }
}

// MARK: - The way to the purchase screen

/// The one place in this territory that names the purchase screen.
///
/// The paywall is built by another part of the app. Naming it once here means
/// that if it ends up called something else there is exactly one line to
/// change, rather than one per locked feature.
struct ARPaywallRoute: View {
    var body: some View {
        PaywallView()
    }
}
