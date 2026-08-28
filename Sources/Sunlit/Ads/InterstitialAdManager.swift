import SwiftUI
@preconcurrency import GoogleMobileAds

/// Die reine Entscheidung, ob ein Interstitial gezeigt werden darf. Ohne SDK, ohne
/// Speicher, ohne Ansicht, damit sie sich einzeln pruefen laesst.
///
/// Alle vier Bedingungen muessen zugleich erfuellt sein. Die Reihenfolge der Pruefungen
/// ist die guenstigste zuerst.
enum AdFrequencyDecision {
    static func allows(
        caps: AdCaps,
        actionsCompleted: Int,
        actionsSinceLastAd: Int,
        secondsSinceLastAd: TimeInterval,
        shownThisSession: Int
    ) -> Bool {
        if shownThisSession >= caps.sessionCap { return false }
        if actionsCompleted < caps.graceActions { return false }
        if actionsSinceLastAd < caps.minActionGap { return false }
        if secondsSinceLastAd < caps.minSeconds { return false }
        return true
    }
}

/// Laedt Interstitials vor und zeigt sie nur, wenn die Obergrenzen es erlauben.
///
/// Die Zaehler liegen in einer eigenen `UserDefaults`-Suite, nicht in `.standard`.
/// Grund: ein Testlauf oder ein Zuruecksetzen der App-Einstellungen darf die Werbelogik
/// nicht anfassen, und die Werbelogik darf umgekehrt nicht in den Einstellungen des
/// Nutzers herumschreiben.
///
/// Verbucht wird erst, wenn feststeht, dass tatsaechlich praesentiert wird. Wird schon
/// vorher verbucht, verbraucht ein nicht geladenes Interstitial den Zeitabstand, und der
/// Nutzer sieht bei der naechsten Gelegenheit trotzdem keine Anzeige. Die Einnahme faellt
/// aus, die Obergrenze wird trotzdem bezahlt.
@MainActor
@Observable
final class InterstitialAdManager: NSObject, FullScreenContentDelegate {

    private let unitID: String
    private let caps: AdCaps
    private let store: UserDefaults

    private var ad: InterstitialAd?
    private var onDismiss: (() -> Void)?

    /// Wie oft in dieser Sitzung bereits ein Interstitial lief. Beginnt bei jedem Start
    /// wieder bei null, absichtlich nicht persistiert.
    private(set) var shownThisSession = 0

    var isReady: Bool { ad != nil }

    /// - Parameter suiteName: Name der `UserDefaults`-Suite. Darf nicht der Bundle-Bezeichner
    ///   sein, sonst faellt die Suite auf `.standard` zurueck.
    init(unitID: String, caps: AdCaps, suiteName: String) {
        self.unitID = unitID
        self.caps = caps
        self.store = UserDefaults(suiteName: suiteName) ?? .standard
        super.init()
    }

    // MARK: - Laden

    func preload() {
        guard ad == nil else { return }
        Task {
            let loaded = try? await InterstitialAd.load(with: unitID, request: Request())
            self.ad = loaded
            loaded?.fullScreenContentDelegate = self
        }
    }

    // MARK: - Zaehlen

    /// Eine gezaehlte Aktion ist abgeschlossen. Was als Aktion zaehlt, entscheidet die App:
    /// eine beendete Runde, eine fertige Auswertung, ein abgeschlossener Durchlauf.
    /// Nicht jeder Bildschirmwechsel, sonst sind die Obergrenzen bedeutungslos.
    func recordAction() {
        actionsCompleted += 1
        actionsSinceLastAd += 1
    }

    /// Wahr, wenn ein Interstitial jetzt erlaubt waere. Fuer Anzeigen im Entwicklermenue.
    /// Die eigentliche Pruefung macht `presentIfAllowed` selbst.
    var isAllowedNow: Bool {
        AdFrequencyDecision.allows(
            caps: caps,
            actionsCompleted: actionsCompleted,
            actionsSinceLastAd: actionsSinceLastAd,
            secondsSinceLastAd: secondsSinceLastAd,
            shownThisSession: shownThisSession)
    }

    // MARK: - Zeigen

    /// Zeigt ein Interstitial, falls alle Obergrenzen es erlauben und eines geladen ist.
    /// `onDismiss` laeuft in jedem Fall, auch wenn nichts gezeigt wurde. Der Aufrufer
    /// braucht deshalb keinen zweiten Zweig.
    func presentIfAllowed(onDismiss: @escaping () -> Void) {
        guard isAllowedNow,
              let ad,
              let viewController = AdKitWindow.topPresented()
        else {
            onDismiss()
            return
        }

        // Erst hier verbuchen. Von hier ab ist die Praesentation der Normalfall, und ein
        // Fehlschlag danach meldet sich ueber den Delegierten.
        shownThisSession += 1
        actionsSinceLastAd = 0
        lastShownAt = Date()

        self.onDismiss = onDismiss
        ad.present(from: viewController)
    }

    private func finish() {
        ad = nil
        preload()
        let callback = onDismiss
        onDismiss = nil
        callback?()
    }

    nonisolated func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        Task { @MainActor in self.finish() }
    }

    nonisolated func ad(
        _ ad: FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
        Task { @MainActor in self.finish() }
    }

    // MARK: - Gespeicherte Zaehler

    private enum Key {
        static let actionsCompleted = "interstitial.actionsCompleted"
        static let actionsSinceLastAd = "interstitial.actionsSinceLastAd"
        static let lastShownAt = "interstitial.lastShownAt"
    }

    private var actionsCompleted: Int {
        get { store.integer(forKey: Key.actionsCompleted) }
        set { store.set(newValue, forKey: Key.actionsCompleted) }
    }

    private var actionsSinceLastAd: Int {
        get { store.integer(forKey: Key.actionsSinceLastAd) }
        set { store.set(newValue, forKey: Key.actionsSinceLastAd) }
    }

    private var lastShownAt: Date? {
        get {
            let seconds = store.double(forKey: Key.lastShownAt)
            return seconds > 0 ? Date(timeIntervalSince1970: seconds) : nil
        }
        set { store.set(newValue?.timeIntervalSince1970 ?? 0, forKey: Key.lastShownAt) }
    }

    /// `.infinity`, solange noch nie eines lief. Dann traegt der Zeitabstand die
    /// Entscheidung nicht, und es zaehlt allein die Schonfrist.
    private var secondsSinceLastAd: TimeInterval {
        guard let lastShownAt else { return .infinity }
        return Date().timeIntervalSince(lastShownAt)
    }
}
