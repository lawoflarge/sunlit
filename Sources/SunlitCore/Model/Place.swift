import Foundation

/// Somewhere the app can compute for.
///
/// Carries its own time zone rather than borrowing the device's, because a user
/// looking at Tokyo from Berlin wants Tokyo's sunrise expressed in Tokyo's
/// clock, and carries its own horizon profile, because a measured skyline
/// belongs to a place and not to a session.
public struct Place: Hashable, Codable, Identifiable, Sendable {

    public let id: UUID
    public var name: String
    public var geographic: Coordinates.Geographic
    /// An IANA identifier such as "Europe/Berlin".
    public var timeZoneIdentifier: String
    /// The measured skyline, when one has been swept here.
    public var horizonProfile: HorizonProfile?
    /// True when this is the device's own position rather than a chosen place.
    public var isCurrentLocation: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        geographic: Coordinates.Geographic,
        timeZoneIdentifier: String,
        horizonProfile: HorizonProfile? = nil,
        isCurrentLocation: Bool = false
    ) {
        self.id = id
        self.name = name
        self.geographic = geographic
        self.timeZoneIdentifier = timeZoneIdentifier
        self.horizonProfile = horizonProfile
        self.isCurrentLocation = isCurrentLocation
    }

    /// Hashed on identity alone.
    ///
    /// The synthesised conformance would have to hash the horizon profile, which
    /// is thirty six doubles and a bitmask, on every dictionary lookup. Two
    /// places with the same id are the same place, and renaming one or sweeping
    /// its skyline does not make it a different one.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public var latitude: Double { geographic.latitude }
    public var longitude: Double { geographic.longitude }
    public var elevation: Double { geographic.elevation }

    /// The offset from UTC in seconds at a given instant, including any daylight
    /// saving in force then. Resolved through Foundation's own zone database, so
    /// historical and future transitions are handled rather than approximated by
    /// dividing the longitude by fifteen.
    public func utcOffset(at instant: Date) -> TimeInterval {
        guard let zone = TimeZone(identifier: timeZoneIdentifier) else { return 0 }
        return Double(zone.secondsFromGMT(for: instant))
    }

    /// Local midnight of the day that contains `instant`, expressed as a Julian
    /// day in Universal Time. This is the input every day-level computation
    /// wants, and getting it wrong by an offset is what puts sunrise on the
    /// wrong date near the international date line.
    public func startOfLocalDay(containing instant: Date) -> JulianDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .gmt
        let midnight = calendar.startOfDay(for: instant)
        return JulianDay(date: midnight)
    }
}
