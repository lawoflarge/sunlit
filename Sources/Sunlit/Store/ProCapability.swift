import Foundation

/// What the one purchase unlocks, as data.
///
/// Naming each capability rather than scattering `if isPro` through the views
/// exists for one reason: three apps in this portfolio shipped a paid promise
/// with no code behind it. A test can enumerate this list and prove that every
/// case actually changes behaviour somewhere. A test cannot enumerate scattered
/// booleans.
public enum ProCapability: String, CaseIterable, Sendable {
    /// Any date other than today.
    case anyDate
    /// Places other than where the device is.
    case savedPlaces
    /// The moon: phase, path, rise, set, calendar.
    case moon
    /// The Milky Way: galactic centre, plane, visibility windows.
    case milkyWay
    /// Solstice and equinox reference curves, and the annual altitude curve.
    case annualPaths
    /// The measured horizon profile and the obstruction periods it produces.
    case terrain
    /// Eclipses with local circumstances.
    case eclipses
    /// Home screen and lock screen widgets.
    case widgets
    /// Notifications for solar and lunar events.
    case notifications
    /// CSV and image export.
    case export

    /// The product identifier of the single non-consumable that unlocks all of
    /// these. There is exactly one, on purpose.
    public static let productIdentifier = "com.levinschwab.sunlit.pro"
}
