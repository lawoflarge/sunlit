import SwiftUI
@preconcurrency import GoogleMobileAds
import UIKit

/// Bannerflaeche mit vorab reserviertem Platz.
///
/// Die Hoehe eines verankerten adaptiven Banners haengt nur von Breite und Geraet ab,
/// nicht von der geladenen Anzeige. Sie steht also fest, sobald die Breite bekannt ist,
/// und damit lange bevor ueberhaupt etwas geladen wurde. Genau deshalb laesst sich der
/// Platz reservieren, und genau deshalb springt beim Einblenden nichts.
///
/// Ueber `onHeightChange` meldet die Ansicht ihre Hoehe nach oben, damit das umgebende
/// Layout den Platz freihalten kann, zum Beispiel als unteres Inset einer Scrollansicht.
///
/// Bei Premium ist die Hoehe null und es wird nichts gezeichnet.
struct AdBannerView: View {

    let ads: AdsController
    var onHeightChange: (CGFloat) -> Void = { _ in }

    @State private var width: CGFloat = 0

    /// `largeAnchoredAdaptiveBanner` und nicht `currentOrientationAnchoredAdaptiveBanner`.
    /// Die aeltere Familie ist ab SDK 13 als veraltet gekennzeichnet, mit genau dieser
    /// Funktion als Ersatz. Die Hoehe liegt dadurch zwischen 50 und 150 Punkten statt
    /// zwischen 50 und 90, hoechstens aber bei 20 Prozent der Geraetehoehe.
    ///
    /// Die Breite kommt aus der Ansicht selbst, nicht aus `UIScreen.main`. Der Bildschirm
    /// ist nicht die Ansicht: er kennt weder Seitenleisten noch geteilte Fenster, und
    /// `UIScreen.main` ist ab iOS 26 ohnehin veraltet.
    private var adSize: AdSize? {
        guard !ads.adsRemoved, width > 0 else { return nil }
        return largeAnchoredAdaptiveBanner(width: width)
    }

    private var reservedHeight: CGFloat {
        adSize?.size.height ?? 0
    }

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: reservedHeight)
            .overlay {
                if let adSize, ads.canShowAds {
                    AdKitBannerContainer(adSize: adSize, adUnitID: ads.configuration.bannerUnitID)
                }
            }
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { width = geometry.size.width }
                        .onChange(of: geometry.size.width) { _, newWidth in width = newWidth }
                }
            }
            .onChange(of: reservedHeight, initial: true) { _, height in
                onHeightChange(height)
            }
    }
}

private struct AdKitBannerContainer: UIViewRepresentable {
    let adSize: AdSize
    let adUnitID: String

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: adSize)
        banner.adUnitID = adUnitID
        // Der Wurzel-Controller, nicht der oberste praesentierte. Das Banner haelt diese
        // Referenz schwach: verschwindet ein Blatt, das hier eingetragen war, klickt das
        // Banner danach ins Leere.
        banner.rootViewController = AdKitWindow.keyWindowRoot()
        banner.load(Request())
        return banner
    }

    func updateUIView(_ banner: BannerView, context: Context) {
        guard banner.adSize.size != adSize.size else { return }
        banner.adSize = adSize
        banner.load(Request())
    }
}
