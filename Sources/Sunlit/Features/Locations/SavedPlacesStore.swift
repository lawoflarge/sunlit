import Foundation
import Observation
import SunlitCore

/// The places the user has kept, and the skylines they have measured.
///
/// Small on purpose: one JSON file in Application Support, read once at launch
/// and rewritten whenever something changes. A dozen places and thirty six
/// doubles per measured horizon is not a database problem, and a database here
/// would be a dependency the offline promise has to carry forever.
///
/// Two collections rather than one, because a horizon profile does not only
/// belong to a saved place. The commonest sweep of all is the one taken at the
/// device's current location, which is never in `places`, and losing it at the
/// next launch would make the terrain feature a toy. Profiles are therefore
/// keyed by coordinate, at three decimal places, which is about 110 metres and
/// is the distance over which a skyline is still the same skyline.
@Observable
final class SavedPlacesStore {

    /// The instance the interface uses.
    ///
    /// A singleton rather than an environment object because `SunlitApp` is
    /// outside this track's territory and cannot be asked to inject one. Views
    /// hold it in `@State`, which is what gives them observation.
    static let shared = SavedPlacesStore()

    /// Kept places, in the order they were added.
    private(set) var places: [Place] = []

    /// Measured skylines, keyed by `coordinateKey(latitude:longitude:)`.
    private(set) var profiles: [String: HorizonProfile] = [:]

    private let fileURL: URL?

    /// - Parameter fileURL: where to persist. Nil disables persistence, which is
    ///   what a test wants and what a device with no writable Application
    ///   Support directory gets.
    init(fileURL: URL? = SavedPlacesStore.defaultFileURL()) {
        self.fileURL = fileURL
        load()
    }

    // MARK: Places

    /// Whether a place with this coordinate is already kept.
    func isSaved(_ place: Place) -> Bool {
        let key = Self.coordinateKey(latitude: place.latitude, longitude: place.longitude)
        return places.contains { Self.coordinateKey(latitude: $0.latitude, longitude: $0.longitude) == key }
    }

    /// Keeps a place. Adding one that is already kept renames it rather than
    /// duplicating it, because two rows a hundred metres apart with the same
    /// name is a bug report and not a feature.
    func save(_ place: Place) {
        let key = Self.coordinateKey(latitude: place.latitude, longitude: place.longitude)
        var stored = place
        // A kept place is never the device's own position: the current location
        // has its own row in the picker and moves with the device.
        stored.isCurrentLocation = false
        if let index = places.firstIndex(where: {
            Self.coordinateKey(latitude: $0.latitude, longitude: $0.longitude) == key
        }) {
            places[index] = stored
        } else {
            places.append(stored)
        }
        persist()
    }

    /// Forgets a place. The measured skyline stays, because the user removed a
    /// bookmark and not a measurement, and re-adding the place brings it back.
    func remove(_ place: Place) {
        let key = Self.coordinateKey(latitude: place.latitude, longitude: place.longitude)
        places.removeAll { Self.coordinateKey(latitude: $0.latitude, longitude: $0.longitude) == key }
        persist()
    }

    // MARK: Horizon profiles

    /// The measured skyline stored for a coordinate, if there is one.
    func profile(for place: Place) -> HorizonProfile? {
        profiles[Self.coordinateKey(latitude: place.latitude, longitude: place.longitude)]
    }

    /// Stores or clears the measured skyline for a coordinate.
    func setProfile(_ profile: HorizonProfile?, for place: Place) {
        let key = Self.coordinateKey(latitude: place.latitude, longitude: place.longitude)
        if let profile, profile.isMeasured {
            profiles[key] = profile
        } else {
            // An unmeasured profile is the flat assumption, which is what the
            // absence of a profile already means. Storing it would claim a sweep
            // that never happened.
            profiles.removeValue(forKey: key)
        }
        if let index = places.firstIndex(where: {
            Self.coordinateKey(latitude: $0.latitude, longitude: $0.longitude) == key
        }) {
            places[index].horizonProfile = profiles[key]
        }
        persist()
    }

    // MARK: Keys

    /// Three decimal places, about 110 metres. Formatted without a locale, so a
    /// device set to German writes the same key as one set to English and a
    /// stored skyline is not lost by changing the system language.
    static func coordinateKey(latitude: Double, longitude: Double) -> String {
        String(format: "%.3f,%.3f", latitude, longitude)
    }

    // MARK: Persistence

    private struct Payload: Codable {
        var places: [Place]
        var profiles: [String: HorizonProfile]
    }

    static func defaultFileURL() -> URL? {
        let manager = FileManager.default
        guard let base = try? manager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        let folder = base.appendingPathComponent("Sunlit", isDirectory: true)
        try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("places.json")
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return }
        places = payload.places
        profiles = payload.profiles
    }

    private func persist() {
        guard let fileURL else { return }
        let payload = Payload(places: places, profiles: profiles)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        // Atomic, because the alternative is a truncated file after a kill and
        // an empty list on the next launch.
        try? data.write(to: fileURL, options: [.atomic])
    }
}
