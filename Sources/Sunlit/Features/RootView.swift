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

    var body: some View {
        TabView(selection: $tab) {
            SkyView()
                .tabItem { Label("tab.sky", systemImage: "sun.horizon") }
                .tag(Tab.sky)
            ARView()
                .tabItem { Label("tab.ar", systemImage: "camera.viewfinder") }
                .tag(Tab.ar)
            MapPlanView()
                .tabItem { Label("tab.map", systemImage: "map") }
                .tag(Tab.map)
            DataView()
                .tabItem { Label("tab.data", systemImage: "tablecells") }
                .tag(Tab.data)
        }
        .tint(SkyColors.sun)
    }
}
