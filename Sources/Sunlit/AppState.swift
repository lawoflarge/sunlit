import Foundation
import Observation
import SunlitCore

/// The state every view reads: where, when, and what is unlocked.
///
/// Place and instant are global on purpose. The single most common complaint
/// about the app this one competes with is that scouting a distant location is
/// awkward, and the cause is that each of its views carries its own idea of
/// where you are. Here there is one, in the header, and all four views follow
/// it.
@Observable
final class AppState {

    /// Where. Defaults to a fixed place so the app is useful before location
    /// permission is answered, and is replaced the moment it is granted.
    var place: Place

    /// Which local day is selected.
    var day: Date

    /// Where the scrubber sits within that day, in seconds from local midnight.
    /// `nil` means the app is following the real clock, which is the state it
    /// starts in and returns to.
    var scrubSeconds: TimeInterval?

    /// The purchase gate.
    let pro: ProGate

    /// Whether `place` is the device's own location rather than a chosen one.
    var isCurrentLocation: Bool

    /// True only while the app is being driven for screenshots.
    ///
    /// Two pieces of ordinary behaviour are wrong during a capture and are
    /// suppressed by this flag: the Sky view returns to live time whenever the
    /// selected day is today, which throws away the instant the capture chose,
    /// and the store overwrites the entitlement asynchronously a moment after
    /// launch, which locks the screens the capture is meant to show. Both were
    /// observed, not guessed: the first capture came out at the wall clock time
    /// with a lock banner across it.
    var isCaptureMode: Bool = false

    /// Which tab a capture should open on, or nil for the default.
    ///
    /// Set from a launch argument rather than by tapping the tab bar, because a
    /// tap depends on where the bar happens to be laid out and a poster set has
    /// to be reproducible across ten languages and two device sizes.
    var captureScreen: String?

    init(place: Place, pro: ProGate = ProGate()) {
        self.place = place
        self.day = Calendar.current.startOfDay(for: Date())
        self.scrubSeconds = nil
        self.pro = pro
        self.isCurrentLocation = true
    }

    /// The instant the whole interface is currently showing.
    var instant: Date {
        guard let scrubSeconds else { return Date() }
        return day.addingTimeInterval(scrubSeconds)
    }

    var julianDay: JulianDay { JulianDay(date: instant) }

    /// True when the selected day is the device's today, in the place's own
    /// time zone rather than the device's, because a user looking at Tokyo
    /// should see Tokyo's today.
    var isToday: Bool {
        var calendar = Calendar.current
        if let zone = TimeZone(identifier: place.timeZoneIdentifier) {
            calendar.timeZone = zone
        }
        return calendar.isDateInToday(day)
    }

    /// Whether the current selection is inside the free tier.
    var selectionIsFree: Bool {
        pro.allowsSelection(isToday: isToday, isCurrentLocation: isCurrentLocation)
    }

    /// Returns to following the real clock.
    func resumeLiveTime() {
        scrubSeconds = nil
    }

    /// Moves the scrubber, which stops following the clock.
    func scrub(toSecondsSinceMidnight seconds: TimeInterval) {
        scrubSeconds = min(max(0, seconds), 86400)
    }
}
