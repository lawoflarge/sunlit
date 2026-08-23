import SwiftUI
import SunlitCore

/// The four views, and the header that governs all of them.
///
/// Place and date live here rather than inside each tab. That is the fix for
/// the loudest complaint about the product this one competes with, where every
/// view carries its own idea of where you are and scouting a distant location
/// means setting it four times.
struct RootView: View {

    @Environment(AppState.self) private var state

    enum Tab: Hashable {
        case sky, ar, map, data
    }

    @State private var tab: Tab = .sky
    /// Driven by the app, which sets it when a widget taps sunlit://paywall.
    @Binding var showingPaywall: Bool

    var body: some View {
        TabView(selection: $tab) {
            SkyView()
                .tabItem {
                    Label(String(localized: "tab.sky", defaultValue: "Sky",
                                 comment: "Tab title for the home screen"),
                          systemImage: "sun.horizon")
                }
                .tag(Tab.sky)
            ARView()
                .tabItem {
                    Label(String(localized: "tab.ar", defaultValue: "AR",
                                 comment: "Tab title for the camera overlay"),
                          systemImage: "camera.viewfinder")
                }
                .tag(Tab.ar)
            MapPlanView()
                .tabItem {
                    Label(String(localized: "tab.map", defaultValue: "Map",
                                 comment: "Tab title for the map planning view"),
                          systemImage: "map")
                }
                .tag(Tab.map)
            DataView()
                .tabItem {
                    Label(String(localized: "tab.data", defaultValue: "Data",
                                 comment: "Tab title for the tables and calendar"),
                          systemImage: "tablecells")
                }
                .tag(Tab.data)
        }
        .tint(SkyColors.sun)
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
        }
        .onChange(of: state.captureScreen, initial: true) { _, screen in
            // Screenshot capture only. Nothing sets this in a shipped run.
            switch screen {
            case "sky": tab = .sky
            case "ar": tab = .ar
            case "map": tab = .map
            case "data": tab = .data
            case "paywall":
                // The In-App Purchase review screenshot has to show the purchase
                // as the reviewer meets it, and a tap on a lock note is not
                // reproducible across ten languages and two device sizes.
                tab = .sky
                showingPaywall = true
            default: break
            }
        }
    }
}
