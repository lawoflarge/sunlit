import SwiftUI
import SunlitCore

// MARK: - The sweep

/// Tracing the skyline with the camera.
///
/// The user aims the centre of the frame at the top of whatever is in the way
/// and turns on the spot. Each reading is the aim of the camera, which is the
/// same direction the overlay is drawn around, so what the crosshair sits on is
/// exactly what gets recorded.
///
/// A session always starts from an empty profile rather than from whatever the
/// place already carries. `HorizonProfile` does not publish which of its
/// sectors hold observations, so a session seeded from a saved profile could
/// not tell a sector it had just measured from one it inherited, and it would
/// draw a traced line over readings nobody took in this sweep. Saving replaces
/// the place's skyline, and the interface says so.
@Observable
final class HorizonSweepSession {

    private(set) var profile: HorizonProfile = .flat
    private(set) var isRecording: Bool = false
    /// Which sectors this session has actually observed.
    private(set) var observedSectors: Set<Int> = []

    var measuredSectorCount: Int { observedSectors.count }
    var hasAnyReading: Bool { !observedSectors.isEmpty }

    /// How far round the sky the sweep has come, 0 to 1.
    var progress: Double {
        Double(observedSectors.count) / Double(HorizonProfile.sectorCount)
    }

    func beginRecording() { isRecording = true }
    func endRecording() { isRecording = false }

    func reset() {
        profile = .flat
        observedSectors = []
        isRecording = false
    }

    /// Takes one reading.
    ///
    /// Called from the attitude stream, so it runs about twenty times a second
    /// while the button is held. `HorizonProfile.record` keeps the higher of
    /// the readings on a bearing, which is what makes a slow pan across a roof
    /// line record the roof rather than the last patch of sky beside it.
    func record(aim: SkyPoint) {
        guard isRecording else { return }
        guard aim.altitude.isFinite, aim.azimuth.isFinite else { return }
        // Nothing above sixty degrees is a skyline. A reading up there means the
        // phone was pointed at the sky while the button was still down, and
        // storing it would raise a sector by tens of degrees and delete a
        // sunrise.
        guard aim.altitude < 60 else { return }
        profile.record(azimuth: aim.azimuth, altitude: aim.altitude)
        observedSectors.insert(HorizonProfile.sectorIndex(forAzimuth: aim.azimuth))
    }

    /// The traced line, as runs of adjacent observed sectors.
    ///
    /// Two degrees between points inside a run, so the projected curve is
    /// smooth, and a break wherever the sweep has not been.
    var trace: [[SkyPoint]] {
        guard !observedSectors.isEmpty else { return [] }
        let width = HorizonProfile.sectorWidth
        var runs: [[SkyPoint]] = []
        var current: [SkyPoint] = []
        // Start at the first unobserved sector so that a run which wraps past
        // north is not cut in half at index zero.
        let start = (0..<HorizonProfile.sectorCount)
            .first { !observedSectors.contains($0) } ?? 0
        for step in 0..<HorizonProfile.sectorCount {
            let index = (start + step) % HorizonProfile.sectorCount
            guard observedSectors.contains(index) else {
                if current.count > 1 { runs.append(current) }
                current = []
                continue
            }
            let centre = Double(index) * width
            for offset in stride(from: -width / 2, through: width / 2, by: 2.0) {
                let azimuth = Angle.normalized(centre + offset)
                current.append(SkyPoint(
                    azimuth: azimuth,
                    altitude: profile.altitude(atAzimuth: azimuth)))
            }
        }
        if current.count > 1 { runs.append(current) }
        return runs
    }
}

// MARK: - The controls

/// The horizon sweep, under the viewport.
///
/// The controls sit below the camera image rather than on top of it. A press
/// and hold target inside a scrolling viewport fights the scroll gesture, and
/// the hand that is holding the phone up cannot reach the middle of the screen
/// anyway.
struct HorizonSweepSection: View {

    let sweep: HorizonSweepSession
    let isUnlocked: Bool
    let aim: SkyPoint
    let headingIsTrustworthy: Bool
    let onSave: () -> Void
    let onUnlockRequested: () -> Void

    @Environment(\.solarAltitude) private var solarAltitude

    private var canRecord: Bool { isUnlocked && headingIsTrustworthy }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(String(
                    localized: "ar.sweep.title", defaultValue: "Horizon sweep",
                    comment: "Heading of the section that traces the skyline with the camera"))
                    .font(SunlitType.title)
                if !isUnlocked {
                    Image(systemName: "lock.fill")
                        .imageScale(.small)
                        .accessibilityHidden(true)
                }
            }

            Text(explanation)
                .font(SunlitType.body)
                .fixedSize(horizontal: false, vertical: true)

            progressRow

            recordButton

            HStack(spacing: 12) {
                Button {
                    onSave()
                } label: {
                    Text(String(
                        localized: "ar.sweep.save", defaultValue: "Save to place",
                        comment: "Button that stores the traced skyline on the selected place"))
                        .font(SunlitType.body)
                        .frame(maxWidth: .infinity)
                        .sunlitTouchTarget()
                }
                .buttonStyle(.plain)
                .disabled(!isUnlocked || !sweep.hasAnyReading)
                .accessibilityLabel(Text(String(
                    localized: "ar.sweep.save.axLabel",
                    defaultValue: "Save the traced skyline to this place",
                    comment: "Accessibility label of the save button in the horizon sweep")))

                Button {
                    sweep.reset()
                } label: {
                    Text(String(
                        localized: "ar.sweep.clear", defaultValue: "Start over",
                        comment: "Button that discards the readings taken so far in the sweep"))
                        .font(SunlitType.body)
                        .frame(maxWidth: .infinity)
                        .sunlitTouchTarget()
                }
                .buttonStyle(.plain)
                .disabled(!isUnlocked || !sweep.hasAnyReading)
                .accessibilityLabel(Text(String(
                    localized: "ar.sweep.clear.axLabel",
                    defaultValue: "Discard the readings taken so far",
                    comment: "Accessibility label of the start over button in the horizon sweep")))
            }

            Text(String(
                localized: "ar.sweep.replaces",
                defaultValue: "Saving replaces the skyline stored for this place.",
                comment: "Warning that saving a sweep overwrites the place's previous skyline"))
                .font(SunlitType.caption)
                .fixedSize(horizontal: false, vertical: true)

            if !isUnlocked {
                ARUnlockRow(
                    message: String(
                        localized: "ar.sweep.locked",
                        defaultValue: "A measured skyline is part of Sunlit Pro. It gives you the sunrise and sunset your own horizon actually produces, and the periods when the sun is up but behind it.",
                        comment: "Explanation shown when the horizon sweep is locked"),
                    action: onUnlockRequested)
            }
        }
        .opacity(isUnlocked ? 1 : 0.6)
    }

    private var explanation: String {
        String(
            localized: "ar.sweep.explanation",
            defaultValue: "Aim the centre of the frame at the top of whatever blocks your view, then hold Record and turn on the spot. The sky is divided into thirty six sectors of ten degrees and each one fills as you reach it.",
            comment: "Instructions for tracing the skyline with the camera")
    }

    private var progressRow: some View {
        MetricGroup {
            MetricReadout(
                label: String(
                    localized: "ar.sweep.sectors", defaultValue: "Sectors traced",
                    comment: "Label of the count of horizon sectors that carry a reading"),
                value: sectorsValue,
                valueFont: SunlitType.metric)
            MetricReadout(
                label: String(
                    localized: "ar.aim.altitude", defaultValue: "Aim altitude",
                    comment: "Label of the altitude the centre of the camera frame points at"),
                value: aim.altitude.formatted(.number.precision(.fractionLength(1))),
                unit: "\u{00B0}",
                valueFont: SunlitType.metric)
        }
    }

    private var sectorsValue: String {
        let done = sweep.measuredSectorCount.formatted(.number)
        let total = HorizonProfile.sectorCount.formatted(.number)
        return String(
            localized: "ar.sweep.sectorsValue",
            defaultValue: "\(done) of \(total)",
            comment: "How many of the horizon sectors carry a reading, as in 12 of 36")
    }

    /// Press and hold, and a plain tap works too.
    ///
    /// A drag gesture with no minimum distance fires the moment the finger
    /// lands, so a tap records the sector the frame is on and a hold keeps
    /// recording while the user turns. A `LongPressGesture` would swallow the
    /// tap and a `Button` would not report the release.
    private var recordButton: some View {
        let label = sweep.isRecording
            ? String(
                localized: "ar.sweep.recording", defaultValue: "Recording",
                comment: "State of the sweep button while a reading is being taken")
            : String(
                localized: "ar.sweep.record", defaultValue: "Hold to record",
                comment: "Sweep button that records the skyline while it is held")

        return Text(label)
            .font(SunlitType.body)
            .frame(maxWidth: .infinity)
            .sunlitTouchTarget(minimum: 56)
            .contentShape(Rectangle())
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        sweep.isRecording
                            ? SkyColors.sun
                            : SkyPalette.componentBorder(solarAltitude: solarAltitude),
                        lineWidth: 1)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard canRecord else { return }
                        if !sweep.isRecording { sweep.beginRecording() }
                        sweep.record(aim: aim)
                    }
                    .onEnded { _ in sweep.endRecording() }
            )
            .disabled(!canRecord)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text(String(
                localized: "ar.sweep.record.axLabel",
                defaultValue: "Record the skyline",
                comment: "Accessibility label of the sweep record button")))
            .accessibilityValue(Text(recordAccessibilityValue))
            .accessibilityHint(Text(String(
                localized: "ar.sweep.record.axHint",
                defaultValue: "Aim the centre of the frame at the skyline and activate once for each direction",
                comment: "Accessibility hint of the sweep record button")))
            // A press and hold cannot be performed with VoiceOver running, so
            // an activation takes one reading on its own. Sweeping then means
            // turning a little and activating again, which is slower than
            // holding and turning but is the same measurement.
            .accessibilityAction {
                guard canRecord else { return }
                sweep.beginRecording()
                sweep.record(aim: aim)
                sweep.endRecording()
            }
    }

    private var recordAccessibilityValue: String {
        if !isUnlocked {
            return String(
                localized: "ar.sweep.record.axLocked", defaultValue: "Locked",
                comment: "Spoken state of the sweep record button when the capability is not purchased")
        }
        if !headingIsTrustworthy {
            return String(
                localized: "ar.sweep.record.axUncalibrated",
                defaultValue: "Unavailable until the compass is calibrated",
                comment: "Spoken state of the sweep record button while the heading cannot be trusted")
        }
        return sectorsValue
    }
}

// MARK: - Unlock row

/// An explanation of a locked capability and the way to it.
///
/// Used by every gated block in this view, so that a locked feature always
/// looks the same: it is still on the screen, it is dimmed, it says what it
/// does, and it offers exactly one way forward.
struct ARUnlockRow: View {

    let message: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(SunlitType.caption)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: action) {
                HStack(spacing: 6) {
                    Image(systemName: "lock.open")
                        .imageScale(.small)
                        .accessibilityHidden(true)
                    Text(String(
                        localized: "ar.unlock", defaultValue: "See what Pro unlocks",
                        comment: "Button that opens the purchase screen from a locked feature"))
                        .font(SunlitType.body)
                }
                .sunlitTouchTarget()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(String(
                localized: "ar.unlock.axLabel", defaultValue: "See what Sunlit Pro unlocks",
                comment: "Accessibility label of the button that opens the purchase screen")))
        }
        .accessibilityElement(children: .contain)
    }
}
