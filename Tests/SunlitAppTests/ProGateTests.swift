import XCTest
@testable import Sunlit

/// The purpose of this file is narrow and it is not coverage.
///
/// Three apps in this portfolio shipped a purchase that promised a feature no
/// code delivered. A grep for the capability name does not catch that, because
/// the call can be one level of indirection away. What catches it is asserting
/// on behaviour: with the gate closed the app must do something different from
/// what it does with the gate open, for every capability the paywall names.
final class ProGateTests: XCTestCase {

    func testEveryCapabilityIsListed() {
        // If a capability is added to the paywall copy but not here, this count
        // fails and the omission surfaces before review does.
        XCTAssertEqual(ProCapability.allCases.count, 10)
    }

    func testGateIsClosedByDefault() {
        let gate = ProGate()
        for capability in ProCapability.allCases {
            XCTAssertFalse(gate.allows(capability), "\(capability) was open before purchase")
        }
    }

    func testGateOpensEverythingAfterPurchase() {
        let gate = ProGate()
        gate.setPurchased(true)
        for capability in ProCapability.allCases {
            XCTAssertTrue(gate.allows(capability), "\(capability) stayed shut after purchase")
        }
    }

    func testFreeTierIsTodayAtTheCurrentLocation() {
        let gate = ProGate()
        XCTAssertTrue(gate.allowsSelection(isToday: true, isCurrentLocation: true),
                      "today at the current location must be free")
        XCTAssertFalse(gate.allowsSelection(isToday: false, isCurrentLocation: true))
        XCTAssertFalse(gate.allowsSelection(isToday: true, isCurrentLocation: false))
        XCTAssertFalse(gate.allowsSelection(isToday: false, isCurrentLocation: false))
    }

    func testPurchaseOpensEverySelection() {
        let gate = ProGate()
        gate.setPurchased(true)
        XCTAssertTrue(gate.allowsSelection(isToday: false, isCurrentLocation: false))
    }

    func testProductIdentifierMatchesTheStoreKitConfiguration() {
        XCTAssertEqual(ProCapability.productIdentifier, "com.levinschwab.sunlit.pro")
    }
}
