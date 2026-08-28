import Foundation
import Observation

/// The single place that answers whether a capability is available.
///
/// Views ask this and never read the purchase state directly, so that the free
/// tier can be reasoned about in one file and tested in one place.
@Observable
final class ProGate {

    /// Whether the non-consumable has been purchased.
    private(set) var isPurchased: Bool = false

    /// Whether the first entitlement check has come back.
    ///
    /// `isPurchased` starts false, so until then a buyer looks exactly like a
    /// free reader. For a locked feature that only meant a moment of a lock
    /// symbol; for advertising it would mean the consent form on launch for
    /// somebody who has paid. While this is false the app hands the ad kit
    /// `nil` and the kit does nothing at all.
    private(set) var hasSettled = false

    /// When frozen, the store's asynchronous entitlement refresh cannot change
    /// the answer. Used only by the screenshot harness.
    private var isFrozen = false

    /// Set by the store layer when entitlements change, and by tests.
    func setPurchased(_ purchased: Bool) {
        // Before the freeze check on purpose: the answer has come back either
        // way, and a frozen gate is one that already knows what it is.
        hasSettled = true
        guard !isFrozen else { return }
        isPurchased = purchased
    }

    /// Grants and then freezes, so a later refresh cannot take it back.
    func freezePurchased(_ purchased: Bool) {
        isFrozen = false
        isPurchased = purchased
        isFrozen = true
        hasSettled = true
    }

    /// The one question every gated feature asks.
    func allows(_ capability: ProCapability) -> Bool {
        isPurchased
    }

    /// Convenience for the commonest gate, which is not a capability in its own
    /// right but a combination: today at the current location is free, anything
    /// else is not.
    ///
    /// - Parameters:
    ///   - isToday: whether the selected day is the device's today.
    ///   - isCurrentLocation: whether the selected place is the device's own.
    func allowsSelection(isToday: Bool, isCurrentLocation: Bool) -> Bool {
        if isPurchased { return true }
        return isToday && isCurrentLocation
    }
}
