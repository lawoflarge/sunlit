import Foundation

/// Die Werbe-Kennungen und Obergrenzen genau einer App.
///
/// Das ist die einzige Stelle im Kit, an der App-spezifische Werte stehen. Alles andere
/// ist wortgleich in jede App kopierbar.
///
/// Der Initialisierer ist absichtlich privat. Eine Konfiguration entsteht nur ueber
/// `AdConfiguration.app(...)`, und diese Fabrik tauscht im Debug-Build die Bloecke gegen
/// Googles Testbloecke aus. Dadurch gibt es keinen Weg, im Debug versehentlich einen
/// echten Block zu laden: eigene Klicks waeren sonst ungueltiger Traffic und koennen
/// das AdMob-Konto sperren.
struct AdConfiguration: Sendable {

    /// Googles offizielle Testbloecke fuer iOS. Beide sind aus den bestehenden Apps
    /// uebernommen und nicht geraten:
    /// Banner       aus zinsklar/App/Sources/Services/AdService.swift:27
    /// Interstitial aus water-eject/WaterEject/Ads/InterstitialAdManager.swift:12
    enum TestUnit {
        static let banner = "ca-app-pub-3940256099942544/2934735716"
        static let interstitial = "ca-app-pub-3940256099942544/4411468910"
    }

    /// Praefix aller Platzhalter, die ein Ausrollskript ersetzt.
    static let placeholderPrefix = "__ADMOB_"

    /// Muss zeichengleich mit `GADApplicationIdentifier` in der Info.plist sein.
    /// Wird nur zum Abgleich benutzt, nie zum Starten des SDK. Das SDK liest die
    /// Info.plist selbst und wirft beim Start eine `GADInvalidInitializationException`,
    /// wenn dort ein Platzhalter steht.
    let applicationID: String

    let bannerUnitID: String
    let interstitialUnitID: String
    let caps: AdCaps

    /// Wahr, wenn die Release-Werte echte Bloecke waren. Ist das falsch, bleibt der
    /// `AdsController` im Release-Build stumm, statt gegen Platzhalter zu laden.
    let isReleaseConfigured: Bool

    private init(
        applicationID: String,
        bannerUnitID: String,
        interstitialUnitID: String,
        caps: AdCaps,
        isReleaseConfigured: Bool
    ) {
        self.applicationID = applicationID
        self.bannerUnitID = bannerUnitID
        self.interstitialUnitID = interstitialUnitID
        self.caps = caps
        self.isReleaseConfigured = isReleaseConfigured
    }

    /// Die Konfiguration dieser App.
    ///
    /// Uebergeben werden immer die **echten** Werte. Was im Debug-Build daraus wird,
    /// entscheidet diese Fabrik, nicht der Aufrufer.
    ///
    /// - Parameters:
    ///   - applicationID: die AdMob-App-ID, Form `ca-app-pub-XXXXXXXX~YYYYYYYY`
    ///   - bannerUnitID: der Bannerblock, Form `ca-app-pub-XXXXXXXX/YYYYYYYY`
    ///   - interstitialUnitID: der Interstitial-Block, gleiche Form
    ///   - caps: die harten Obergrenzen, siehe `AdCaps`
    static func app(
        applicationID: String,
        bannerUnitID: String,
        interstitialUnitID: String,
        caps: AdCaps = AdCaps()
    ) -> AdConfiguration {
        let configured = ![applicationID, bannerUnitID, interstitialUnitID]
            .contains { $0.hasPrefix(placeholderPrefix) }

        #if DEBUG
        return AdConfiguration(
            applicationID: applicationID,
            bannerUnitID: TestUnit.banner,
            interstitialUnitID: TestUnit.interstitial,
            caps: caps,
            isReleaseConfigured: configured)
        #else
        return AdConfiguration(
            applicationID: applicationID,
            bannerUnitID: bannerUnitID,
            interstitialUnitID: interstitialUnitID,
            caps: caps,
            isReleaseConfigured: configured)
        #endif
    }

    /// Die AdMob-App-ID aus der Info.plist. `nil`, wenn der Schluessel fehlt.
    static var applicationIDFromInfoPlist: String? {
        Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String
    }
}

/// Harte Obergrenzen fuer Interstitials.
///
/// Das sind Produktzusagen, keine Stellschrauben. Zu viele Interstitials sind der
/// haeufigste Grund fuer Ein-Stern-Rezensionen in dieser App-Gattung. Die Werte sind aus
/// manymo/Manymo/Ads/AdConfig.swift:16-22 uebernommen.
///
/// Alle vier Bedingungen muessen zugleich erfuellt sein, sonst faellt die Anzeige aus.
struct AdCaps: Sendable {

    /// Schonfrist: so viele gezaehlte Aktionen am Anfang bleiben ganz ohne Interstitial.
    var graceActions: Int

    /// Mindestabstand in gezaehlten Aktionen zwischen zwei Interstitials.
    var minActionGap: Int

    /// Mindestabstand in Sekunden zwischen zwei Interstitials, ueber Starts hinweg.
    var minSeconds: TimeInterval

    /// Obergrenze je Sitzung. Wird beim Start der App auf null zurueckgesetzt.
    var sessionCap: Int

    init(
        graceActions: Int = 3,
        minActionGap: Int = 3,
        minSeconds: TimeInterval = 180,
        sessionCap: Int = 1
    ) {
        self.graceActions = graceActions
        self.minActionGap = minActionGap
        self.minSeconds = minSeconds
        self.sessionCap = sessionCap
    }
}
