import SwiftUI
import SunlitCore

@main
struct SunlitApp: App {

    @State private var state: AppState
    @State private var location = LocationProvider()
    @State private var heading = HeadingProvider()

    init() {
        // A real place rather than a null island, so the first frame is useful
        // before the location permission has been answered and so a refusal
        // leaves a working app rather than an empty one.
        let fallback = Place(
            name: "Greenwich",
            geographic: Coordinates.Geographic(latitude: 51.4779, longitude: -0.0015, elevation: 47),
            timeZoneIdentifier: "Europe/London")
        _state = State(initialValue: AppState(place: fallback))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(state)
                .environment(location)
                .environment(heading)
                .preferredColorScheme(.dark)
        }
    }
}
