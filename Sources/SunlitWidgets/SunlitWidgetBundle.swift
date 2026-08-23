import SwiftUI
import WidgetKit

/// The extension's entry point.
///
/// Four widgets over one provider and one shared place. Every figure any of them
/// shows is computed here by `SunlitCore` at render time: there is no network, and
/// nothing but the place and the entitlement is handed across from the app.
@main
struct SunlitWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextEventWidget()
        DayArcWidget()
        GoldenHourRingWidget()
        SkyDigestWidget()
    }
}

// MARK: - Gallery previews

/// A preview entry for a fixed place, so the four previews below never depend on
/// whatever the app happened to write into the shared suite.
private func previewEntry(isUnlocked: Bool = true) -> SunlitEntry {
    SunlitEntryBuilder.singleEntry(
        at: Date(),
        place: SunlitSharedStore.fallbackPlace,
        isUnlocked: isUnlocked
    )
}

/// The state every family shows before the app has shared a place. Third in each
/// timeline below, so the branch is visible in Xcode rather than only reachable on a
/// device that has never opened the app.
private func previewSetupEntry() -> SunlitEntry {
    SunlitEntryBuilder.setupEntry(at: Date())
}

#Preview("Next event", as: .systemSmall) {
    NextEventWidget()
} timeline: {
    previewEntry()
    previewEntry(isUnlocked: false)
    previewSetupEntry()
}

#Preview("Day arc", as: .systemMedium) {
    DayArcWidget()
} timeline: {
    previewEntry()
    previewEntry(isUnlocked: false)
    previewSetupEntry()
}

#Preview("Golden hour ring", as: .accessoryCircular) {
    GoldenHourRingWidget()
} timeline: {
    previewEntry()
    previewEntry(isUnlocked: false)
    previewSetupEntry()
}

#Preview("Sun and moon", as: .accessoryRectangular) {
    SkyDigestWidget()
} timeline: {
    previewEntry()
    previewEntry(isUnlocked: false)
    previewSetupEntry()
}
