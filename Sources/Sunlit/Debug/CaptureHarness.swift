import Foundation
import SunlitCore

/// Puts the app into a fixed, reproducible state for screenshot capture.
///
/// Wrapped in `#if DEBUG` in its entirety, and that is not tidiness. One of its
/// launch arguments grants the paid entitlement, so in a release binary it would
/// be a way past the paywall shipped inside the product. Screenshots are taken
/// from a debug build, which is normal and is what every argument here assumes.
///
/// Nothing in this file is reachable without a launch argument, so a user who
/// somehow ran a debug build would still see the ordinary app.
#if DEBUG
enum CaptureHarness {

    struct Configuration {
        let place: Place
        let instant: Date
        let grantPro: Bool
        let screen: String?
    }

    /// Reads the configuration from the launch arguments, or returns nil when
    /// the app was started normally.
    static func configuration() -> Configuration? {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "SunlitCaptureMode") else { return nil }

        // "latitude,longitude,elevation,timeZone,name"
        let raw = defaults.string(forKey: "SunlitCapturePlace") ?? ""
        let parts = raw.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 5,
              let latitude = Double(parts[0]),
              let longitude = Double(parts[1]),
              let elevation = Double(parts[2]) else {
            return nil
        }

        let place = Place(
            name: parts[4],
            geographic: Coordinates.Geographic(
                latitude: latitude, longitude: longitude, elevation: elevation),
            timeZoneIdentifier: parts[3])

        // A fixed instant, so the gradient is the golden hour of a chosen
        // evening rather than whatever time the build machine happens to be at.
        // Posters have to be reproducible or a reshoot silently changes them.
        let formatter = ISO8601DateFormatter()
        let instant = defaults.string(forKey: "SunlitCaptureInstant")
            .flatMap(formatter.date(from:)) ?? Date()

        return Configuration(
            place: place,
            instant: instant,
            grantPro: defaults.bool(forKey: "SunlitCapturePro"),
            screen: defaults.string(forKey: "SunlitCaptureScreen"))
    }

    /// Points the AR view somewhere worth photographing.
    ///
    /// The azimuth is the sun's own, so the sun sits in the frame rather than
    /// behind the reader, and the pitch is raised enough to show the arc.
    static func aim(_ heading: HeadingProvider, at azimuth: Double) {
        // The two offsets are measured, not derived. Setting heading 292.8 put
        // the frame centre at 112.8, and pitch 24 put it at -66 altitude, so the
        // view reads the device as held flat with the camera looking out of its
        // back. Feeding the inverse gives a frame centred on the sun and tilted
        // ten degrees up, which is where the arc is.
        heading.useFixedAim(heading: azimuth - 180, pitch: 100)
    }

    /// Applies the configuration to the live state.
    static func apply(_ configuration: Configuration, to state: AppState) {
        state.isCaptureMode = true
        state.captureScreen = configuration.screen
        state.place = configuration.place
        state.isCurrentLocation = false

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: configuration.place.timeZoneIdentifier) ?? .current
        state.day = calendar.startOfDay(for: configuration.instant)
        state.scrubSeconds = configuration.instant.timeIntervalSince(state.day)

        if configuration.grantPro {
            // Freeze rather than set: StoreService.refreshEntitlements runs a
            // moment later and would otherwise put the lock back.
            state.pro.freezePurchased(true)
        }
    }
}
#endif
