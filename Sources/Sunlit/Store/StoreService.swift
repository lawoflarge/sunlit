import Foundation
import Observation
import StoreKit
import WidgetKit

/// The purchase layer: one non-consumable, StoreKit 2.
///
/// Every outcome the App Store can return is kept distinct here. Collapsing a
/// cancellation, a pending family approval and a failed signature check into one
/// "something went wrong" is how a user who is waiting for a parent to approve a
/// purchase gets told the purchase failed, taps again, and is charged twice.
/// `Outcome` therefore has a case per real outcome and each case carries its own
/// sentence.
///
/// The entitlement is written in three places on purpose:
///
/// 1. `ProGate`, which every gated view asks.
/// 2. `isEntitled` here, which the paywall reads.
/// 3. A shared `UserDefaults` suite, which the widget extension reads, because a
///    widget process cannot ask StoreKit cheaply on every timeline refresh.
///
/// The widget contract is exactly `Self.sharedSuiteName` and `Self.entitlementKey`.
/// Both are `static` so a test can assert on them rather than on a spelled-out
/// string in two targets that can drift apart.
@MainActor
@Observable
final class StoreService {

    // MARK: The widget contract

    /// The app group the widget extension shares with the app.
    static let sharedSuiteName = "group.com.levinschwab.sunlit"

    /// The key holding a `Bool`: true when the non-consumable is owned. Absent
    /// means "never established", which a widget should treat as not owned.
    static let entitlementKey = "pro.entitled"

    // MARK: State the paywall reads

    /// Whether the product itself could be fetched. Distinct from whether it is
    /// owned, and distinct from whether a purchase succeeded.
    enum Availability: Equatable {
        case loading
        case available
        /// Carries a sentence that is safe to show a user.
        case unavailable(String)
    }

    /// The result of the last purchase or restore attempt.
    enum Outcome: Equatable {
        case purchased
        case restored
        case nothingToRestore
        case cancelled
        case pending
        case unverified
        case productUnavailable
        case failed(String)

        /// The sentence shown to the user. One per case, on purpose.
        var message: String {
            switch self {
            case .purchased:
                return String(
                    localized: "store.result.purchased",
                    defaultValue: "Unlocked. Everything is available now.",
                    comment: "Shown after a successful purchase")
            case .restored:
                return String(
                    localized: "store.result.restored",
                    defaultValue: "Restored. Everything is available again.",
                    comment: "Shown after a restore that found the purchase")
            case .nothingToRestore:
                return String(
                    localized: "store.result.nothingToRestore",
                    defaultValue: "No purchase was found on this Apple ID.",
                    comment: "Shown after a restore that found nothing")
            case .cancelled:
                return String(
                    localized: "store.result.cancelled",
                    defaultValue: "Cancelled. Nothing was charged.",
                    comment: "Shown when the user dismisses the App Store sheet")
            case .pending:
                return String(
                    localized: "store.result.pending",
                    defaultValue: "Waiting for approval. Sunlit unlocks by itself as soon as the purchase is approved, even if you close the app.",
                    comment: "Shown when a purchase needs Ask to Buy approval or a bank confirmation")
            case .unverified:
                return String(
                    localized: "store.result.unverified",
                    defaultValue: "The App Store could not verify this purchase, so nothing was unlocked. Try Restore purchase, and contact Apple if you were charged.",
                    comment: "Shown when StoreKit signature verification fails")
            case .productUnavailable:
                return String(
                    localized: "store.result.productUnavailable",
                    defaultValue: "The purchase is not available right now.",
                    comment: "Shown when the product could not be loaded and the button was still tapped")
            case .failed(let reason):
                return String(
                    localized: "store.result.failed",
                    defaultValue: "The purchase did not complete. \(reason)",
                    comment: "Shown for a StoreKit error, with the system description appended")
            }
        }

        /// True for the outcomes that need the warning fill rather than a plain
        /// note. Cancelling is not one of them: the user meant it.
        var needsAttention: Bool {
            switch self {
            case .unverified, .productUnavailable, .failed:
                return true
            case .purchased, .restored, .nothingToRestore, .cancelled, .pending:
                return false
            }
        }
    }

    private(set) var product: Product?
    private(set) var availability: Availability = .loading
    private(set) var isPurchasing = false
    private(set) var isRestoring = false
    private(set) var outcome: Outcome?

    /// Whether the non-consumable is owned. Mirrors `ProGate.isPurchased`, and
    /// exists so the paywall can show its own state without reaching into the
    /// gate, which is the object every other view is supposed to ask.
    private(set) var isEntitled = false

    /// The price as the App Store formats it for this storefront. Never build
    /// this from a number: the currency, the separator and the position of the
    /// symbol all differ per storefront, and a hardcoded "9.99 EUR" is wrong in
    /// nine of the ten this app ships in.
    var displayPrice: String? { product?.displayPrice }

    // MARK: Wiring

    private let gate: ProGate
    private var updates: Task<Void, Never>?
    private var hasStarted = false

    /// Creating the service starts it. The `Transaction.updates` listener has to
    /// be running before anything else happens, because a transaction that was
    /// approved while the app was not running is delivered through it and is
    /// delivered once.
    init(gate: ProGate) {
        self.gate = gate
        start()
    }

    /// Idempotent, so an app entry point may call it again without doubling the
    /// listener.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        updates = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }

        Task { await loadProduct() }
        Task { await refreshEntitlements() }
    }

    /// Stops the listener. The app never needs this; a test that creates a
    /// service per case does.
    func stop() {
        updates?.cancel()
        updates = nil
        hasStarted = false
    }

    // MARK: Product

    /// Fetches the one product. Safe to call again, which is what the retry
    /// button on the paywall does.
    func loadProduct() async {
        availability = .loading
        do {
            let products = try await Product.products(for: [ProCapability.productIdentifier])
            if let match = products.first(where: { $0.id == ProCapability.productIdentifier }) {
                product = match
                availability = .available
            } else {
                // The request succeeded and the product was not in it. That is a
                // different fault from a network failure and it needs a different
                // sentence, because "check your connection" is useless advice for
                // a product that is not approved for sale yet.
                product = nil
                availability = .unavailable(String(
                    localized: "store.error.notOffered",
                    defaultValue: "This purchase is not offered on this account or in this region.",
                    comment: "The product request succeeded but did not contain the product"))
            }
        } catch {
            product = nil
            availability = .unavailable(String(
                localized: "store.error.load",
                defaultValue: "The price could not be loaded. Check your connection and try again.",
                comment: "The product request itself failed"))
        }
    }

    // MARK: Purchase

    func purchase() async {
        guard !isPurchasing else { return }
        guard let product else {
            outcome = .productUnavailable
            return
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    await refreshEntitlements()
                    outcome = .purchased
                case .unverified:
                    // Deliberately not finished and deliberately not granted. An
                    // unfinished transaction is offered again on the next launch,
                    // which is the only honest recovery: the signature did not
                    // check out and this app is not the place to decide it was
                    // fine anyway.
                    outcome = .unverified
                }
            case .userCancelled:
                outcome = .cancelled
            case .pending:
                // Ask to Buy, or a payment method that needs confirmation. The
                // purchase is alive; the updates listener will deliver it.
                outcome = .pending
            @unknown default:
                outcome = .failed(String(
                    localized: "store.error.unknownResult",
                    defaultValue: "The App Store returned a result Sunlit does not recognise.",
                    comment: "A purchase result case that did not exist when this was written"))
            }
        } catch StoreKitError.userCancelled {
            outcome = .cancelled
        } catch {
            outcome = .failed(error.localizedDescription)
        }
    }

    // MARK: Restore

    /// Restores through `AppStore.sync()`, which asks for the Apple ID password.
    /// That is why it is a button the user presses and never something the app
    /// does by itself: entitlements already arrive through
    /// `currentEntitlements` at launch without any prompt.
    func restore() async {
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
            outcome = isEntitled ? .restored : .nothingToRestore
        } catch StoreKitError.userCancelled {
            outcome = .cancelled
        } catch {
            outcome = .failed(error.localizedDescription)
        }
    }

    // MARK: Entitlement

    /// Reads what this Apple ID currently owns.
    ///
    /// This works with no network: StoreKit keeps the signed transactions on the
    /// device, which is what makes an offline app with a purchase possible at
    /// all.
    func refreshEntitlements() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.productID == ProCapability.productIdentifier else { continue }
            guard transaction.revocationDate == nil else { continue }
            entitled = true
        }
        apply(entitled: entitled)
    }

    private func handle(_ update: VerificationResult<Transaction>) async {
        switch update {
        case .verified(let transaction):
            await transaction.finish()
            await refreshEntitlements()
            if transaction.productID == ProCapability.productIdentifier,
               transaction.revocationDate == nil {
                outcome = .purchased
            }
        case .unverified:
            outcome = .unverified
        }
    }

    private func apply(entitled: Bool) {
        isEntitled = entitled
        gate.setPurchased(entitled)
        if writeSharedEntitlement(entitled) {
            // Only when it actually changed. A widget reload on every launch
            // would burn the extension's refresh budget for no new information.
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Writes the entitlement where the widget extension can read it.
    ///
    /// - Returns: true when the stored value changed.
    @discardableResult
    private func writeSharedEntitlement(_ entitled: Bool) -> Bool {
        guard let defaults = UserDefaults(suiteName: Self.sharedSuiteName) else { return false }
        let previous = defaults.object(forKey: Self.entitlementKey) as? Bool
        guard previous != entitled else { return false }
        defaults.set(entitled, forKey: Self.entitlementKey)
        return true
    }
}
