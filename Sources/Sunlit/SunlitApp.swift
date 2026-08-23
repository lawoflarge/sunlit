import SwiftUI
import WidgetKit
import SunlitCore

@main
struct SunlitApp: App {

    @State private var state: AppState
    @State private var store: StoreService
    @State private var location = LocationProvider()
    @State private var heading = HeadingProvider()
    /// Set when a widget tap arrives on sunlit://paywall.
    @State private var showingPaywall = false

    init() {
        // A real place rather than a null island, so the first frame is useful
        // before the location permission has been answered and so a refusal
        // leaves a working app rather than an empty one.
        let fallback = Place(
            name: "Greenwich",
            geographic: Coordinates.Geographic(latitude: 51.4779, longitude: -0.0015, elevation: 47),
            timeZoneIdentifier: "Europe/London")
        let appState = AppState(place: fallback)
        _state = State(initialValue: appState)
        _store = State(initialValue: StoreService(gate: appState.pro))
    }

    var body: some Scene {
        WindowGroup {
            RootView(showingPaywall: $showingPaywall)
                .environment(state)
                .environment(store)
                .environment(location)
                .environment(heading)
                .preferredColorScheme(.dark)
                .task {
                    // The transaction listener has to be running before any
                    // purchase can complete, and currentEntitlements is what
                    // restores a purchase offline on a fresh install.
                    store.start()
                    #if DEBUG
                    if let configuration = CaptureHarness.configuration() {
                        CaptureHarness.apply(configuration, to: state)
                    }
                    #endif
                }
                .onOpenURL { url in
                    // A locked widget tile taps through to here. Anything else
                    // is ignored rather than guessed at.
                    guard url.scheme == "sunlit" else { return }
                    if url.host == "paywall" {
                        showingPaywall = true
                    }
                }
                .onChange(of: state.place) { _, _ in
                }
        }
    }

}
