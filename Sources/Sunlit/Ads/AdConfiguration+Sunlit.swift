import Foundation

/// The AdMob blocks of this app.
///
/// The real blocks, on purpose. A Debug build never loads any of them:
/// `AdConfiguration.app` swaps them for Google's official test blocks, and the
/// initialiser is private so there is no way past it.
///
/// This lives under `Sources/Sunlit` and nowhere else. The widget extension is
/// its own target with its own sources, and no advertising code may reach it.
extension AdConfiguration {
    static let sunlit = AdConfiguration.app(
        applicationID: "ca-app-pub-6563643868702361~3448225723",
        bannerUnitID: "ca-app-pub-6563643868702361/6726949583",
        interstitialUnitID: "ca-app-pub-6563643868702361/1560428988")
}
