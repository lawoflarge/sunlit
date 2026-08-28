import SwiftUI

/// Die Fassade des Kits. Die App kennt nur diesen Typ.
///
/// Eine Zeile in `App.swift` erzeugt ihn, ein Modifier an der Wurzelansicht bindet ihn
/// samt Premium-Zustand ein. Alles Weitere, also Einwilligung, ATT, SDK-Start, Vorladen
/// und die Obergrenzen, passiert hier drin.
///
/// Bei Premium gibt es keinen einzigen SDK-Aufruf. Nicht weniger Werbung, sondern keine
/// Werbelogik ueberhaupt: kein UMP-Formular, kein ATT-Dialog, kein `MobileAds.start()`.
@MainActor
@Observable
final class AdsController {

    /// Startargument, das im Debug-Build jede Werbung und jeden Dialog abschaltet.
    /// Fuer die Screenshot-Automatisierung: ein UMP-Formular, das ueber dem Bildschirm
    /// haengt, macht jede Aufnahme unbrauchbar.
    static let disableArgument = "-adsDisabled"

    let configuration: AdConfiguration

    private let consent = AdConsentCoordinator()
    private let interstitial: InterstitialAdManager
    private var didAttemptStart = false

    /// Werbung ist dauerhaft entfernt. Dann wird auch kein Platz reserviert.
    private(set) var adsRemoved = false

    init(configuration: AdConfiguration) {
        self.configuration = configuration
        self.interstitial = InterstitialAdManager(
            unitID: configuration.interstitialUnitID,
            caps: configuration.caps,
            // Eigene Suite, nicht `.standard`. Der Bundle-Bezeichner selbst waere als
            // Suitename ungueltig und faellt still auf `.standard` zurueck, deshalb das Anhaengsel.
            suiteName: (Bundle.main.bundleIdentifier ?? "app") + ".adkit")
    }

    // MARK: - Zustand fuer die Ansichten

    /// Einwilligung liegt vor, das SDK laeuft, und Werbung ist nicht entfernt.
    /// Nur wenn das wahr ist, darf ueberhaupt etwas geladen werden.
    var canShowAds: Bool { consent.canShowAds && !adsRemoved }

    /// Steuert den Eintrag "Datenschutzeinstellungen" in den App-Einstellungen.
    /// Pflicht nach DSGVO, sobald UMP es verlangt.
    var isPrivacyOptionsRequired: Bool { consent.isPrivacyOptionsRequired && !adsRemoved }

    var isInterstitialReady: Bool { interstitial.isReady }

    // MARK: - Steuerung

    /// Wird vom Modifier gerufen, sobald sich der Premium-Zustand oder die Szenenphase
    /// aendert. `isPremium == nil` heisst: der Kaufzustand ist noch nicht bekannt, und
    /// dann passiert nichts. Sonst wuerde ein zahlender Nutzer beim Start kurz das
    /// UMP-Formular sehen.
    func update(isPremium: Bool?, sceneIsActive: Bool) async {
        guard let isPremium else { return }
        if isPremium {
            removeAds()
            return
        }
        guard sceneIsActive, !adsRemoved else { return }
        await start()
    }

    /// Entfernt Werbung dauerhaft fuer diese Sitzung.
    func removeAds() {
        adsRemoved = true
        consent.disablePermanently()
    }

    /// Eine gezaehlte Aktion ist abgeschlossen. Siehe `InterstitialAdManager.recordAction()`.
    func recordAction() {
        guard !adsRemoved else { return }
        interstitial.recordAction()
    }

    /// Zeigt ein Interstitial, falls Einwilligung und alle Obergrenzen es erlauben.
    /// `onDismiss` laeuft in jedem Fall, auch wenn nichts gezeigt wurde.
    func presentInterstitialIfAllowed(onDismiss: @escaping () -> Void = {}) {
        guard canShowAds else {
            onDismiss()
            return
        }
        interstitial.presentIfAllowed(onDismiss: onDismiss)
    }

    /// Oeffnet das UMP-Formular erneut. Nur als Antwort auf eine Nutzereingabe aufrufen.
    func showPrivacyOptionsForm() async {
        await consent.showPrivacyOptionsForm()
    }

    // MARK: - Start

    private func start() async {
        guard !didAttemptStart else { return }

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(Self.disableArgument) {
            removeAds()
            return
        }
        assertConfigurationIsSound()
        #else
        // Ein nicht ersetzter Platzhalter im Release-Build laedt nichts und wuerde nur
        // Fehler protokollieren. Dann lieber stumm bleiben.
        guard configuration.isReleaseConfigured else { return }
        #endif

        didAttemptStart = true
        await consent.start()
        guard canShowAds else { return }
        interstitial.preload()
    }

    #if DEBUG
    /// Faengt die drei Fehler ab, die beim Ausrollen auf viele Apps entstehen: vergessener
    /// Schluessel, abweichende App-ID, nicht ersetzter Platzhalter. Alle drei aeussern sich
    /// sonst erst im Release-Build, und der zweite als Absturz beim Start.
    private func assertConfigurationIsSound() {
        let fromPlist = AdConfiguration.applicationIDFromInfoPlist
        assert(
            fromPlist != nil,
            "GADApplicationIdentifier fehlt in der Info.plist. Das SDK wirft beim Start eine GADInvalidInitializationException.")
        assert(
            fromPlist == configuration.applicationID,
            "GADApplicationIdentifier in der Info.plist weicht von AdConfiguration.applicationID ab.")
        assert(
            configuration.isReleaseConfigured,
            "In AdConfiguration steht noch ein Platzhalter mit dem Praefix \(AdConfiguration.placeholderPrefix).")
    }
    #endif
}

// MARK: - Einbindung an der Wurzelansicht

extension View {

    /// Bindet das Kit ein. Der einzige Ort, an dem der Premium- oder Pro-Zustand mit der
    /// Werbung verbunden wird.
    ///
    /// - Parameter isPremium: `nil`, solange der Kaufzustand noch nicht feststeht.
    ///   Das Kit haelt dann alles an. Sobald der Wert `false` wird und die Szene aktiv
    ///   ist, laeuft die Startsequenz. Wird er `true`, ist Werbung dauerhaft entfernt.
    func adKit(_ ads: AdsController, isPremium: Bool?) -> some View {
        modifier(AdKitModifier(ads: ads, isPremium: isPremium))
    }
}

private struct AdKitModifier: ViewModifier {
    let ads: AdsController
    let isPremium: Bool?

    @Environment(\.scenePhase) private var scenePhase

    /// UMP, ATT und der SDK-Start brauchen eine sichtbar aktive Szene, sonst verwirft iOS
    /// den ATT-Dialog stillschweigend. Beide Ausloeser stehen deshalb in einem Wert.
    private struct Trigger: Equatable {
        let isPremium: Bool?
        let sceneIsActive: Bool
    }

    private var trigger: Trigger {
        Trigger(isPremium: isPremium, sceneIsActive: scenePhase == .active)
    }

    func body(content: Content) -> some View {
        content
            .environment(ads)
            .onChange(of: trigger, initial: true) { _, new in
                // Bewusst kein `.task(id:)`: dessen Abbruch beim Phasenwechsel wuerde die
                // Startsequenz mittendrin beenden, und ein zweiter Anlauf findet sie
                // bereits als begonnen vor.
                Task { await ads.update(isPremium: new.isPremium, sceneIsActive: new.sceneIsActive) }
            }
    }
}
