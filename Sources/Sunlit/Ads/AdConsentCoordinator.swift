import AppTrackingTransparency
import SwiftUI
@preconcurrency import GoogleMobileAds
@preconcurrency import UserMessagingPlatform

/// Zugriff auf die Ansichtshierarchie, in zwei getrennten Bedeutungen.
///
/// Die Unterscheidung ist kein Feinschliff. Ein Banner haelt seinen
/// `rootViewController` schwach. Wird dort der oberste **praesentierte** Controller
/// eingetragen und dieser verschwindet spaeter, ist die Referenz nil und der Klick auf
/// das Banner oeffnet nichts mehr. Ein Vollbild dagegen laesst sich nicht von einem
/// Controller praesentieren, der bereits etwas praesentiert.
@MainActor
enum AdKitWindow {

    /// Der Wurzel-Controller des Schluesselfensters. Fuer `BannerView.rootViewController`.
    static func keyWindowRoot() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
    }

    /// Der oberste tatsaechlich praesentierte Controller. Fuer Vollbildanzeigen und
    /// fuer die UMP-Formulare.
    static func topPresented() -> UIViewController? {
        var top = keyWindowRoot()
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

/// Die Startsequenz fuer Werbung, in genau dieser Reihenfolge:
///
/// 1. UMP-Einwilligung einholen (`requestConsentInfoUpdate`, danach das Formular, falls noetig)
/// 2. ATT-Dialog anzeigen
/// 3. erst dann `MobileAds.shared.start()`
///
/// Die Reihenfolge fordert Google. Sie umzudrehen bedeutet, dass das SDK bereits laeuft,
/// bevor die Einwilligung vorliegt.
///
/// `start()` ist idempotent: nur der erste Aufruf laeuft durch. Das ist noetig, weil der
/// Aufruf an `scenePhase == .active` haengt und diese Phase mehrfach eintritt.
@MainActor
@Observable
final class AdConsentCoordinator {

    /// Einwilligung liegt vor und das SDK laeuft. Erst dann darf irgendetwas geladen werden.
    private(set) var canShowAds = false

    /// Der Nutzer muss seine Einwilligung aendern koennen. Steuert den Eintrag
    /// "Datenschutzeinstellungen" in den App-Einstellungen. Pflicht nach DSGVO.
    private(set) var isPrivacyOptionsRequired = false

    private var didStart = false

    /// Kurze Wartezeit vor den Systemdialogen. iOS verwirft den ATT-Dialog
    /// stillschweigend, wenn er angefordert wird, bevor die Szene sichtbar aktiv ist.
    /// Der Wert stammt aus zinsklar/App/Sources/Services/AdService.swift:43.
    private static let promptDelay: UInt64 = 600_000_000

    /// Laeuft die Sequenz. Mehrfachaufrufe sind unschaedlich.
    func start() async {
        guard !didStart else { return }
        didStart = true

        try? await Task.sleep(nanoseconds: Self.promptDelay)

        await requestConsent()
        await requestTrackingAuthorizationIfNeeded()

        guard ConsentInformation.shared.canRequestAds else { return }
        _ = await MobileAds.shared.start()
        canShowAds = true
    }

    /// Sperrt die Sequenz dauerhaft, ohne einen einzigen SDK-Aufruf. Fuer Premium und
    /// fuer den Screenshot-Lauf.
    func disablePermanently() {
        didStart = true
        canShowAds = false
    }

    /// Oeffnet das UMP-Formular erneut, damit der Nutzer seine Einwilligung aendern kann.
    /// Nur als Antwort auf eine Nutzereingabe aufrufen, so verlangt es die UMP-Doku.
    func showPrivacyOptionsForm() async {
        guard let root = AdKitWindow.topPresented() else { return }
        try? await ConsentForm.presentPrivacyOptionsForm(from: root)
        updatePrivacyOptionsRequirement()
    }

    // MARK: - Einzelschritte

    private func requestConsent() async {
        do {
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters())
            try await ConsentForm.loadAndPresentIfRequired(from: AdKitWindow.topPresented())
        } catch {
            // Ein gescheiterter Abruf darf die App nie aufhalten. Ohne `canRequestAds`
            // wird ohnehin nichts geladen.
        }
        updatePrivacyOptionsRequirement()
    }

    private func requestTrackingAuthorizationIfNeeded() async {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
        _ = await ATTrackingManager.requestTrackingAuthorization()
    }

    private func updatePrivacyOptionsRequirement() {
        isPrivacyOptionsRequired =
            ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }
}
