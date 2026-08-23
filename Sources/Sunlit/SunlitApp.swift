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
                .task {
                    // Capture mode exists only in debug builds; see
                    // Debug/CaptureHarness.swift for why that matters.
                    #if DEBUG
                    if let configuration = CaptureHarness.configuration() {
                        CaptureHarness.apply(configuration, to: state)
                    }
                    #endif
                }
                .environment(state)
                .environment(location)
                .environment(heading)
                .preferredColorScheme(.dark)
        }
    }
}
