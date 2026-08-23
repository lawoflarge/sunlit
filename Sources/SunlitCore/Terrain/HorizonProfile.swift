import Foundation

/// A measured skyline: the apparent altitude of the horizon, in degrees, in
/// each of thirty six azimuth sectors ten degrees wide.
///
/// Sector `i` is centred on azimuth `i * 10`, so sector 0 looks due north and
/// sector 9 due east. Centres rather than sector edges, because the value the
/// camera sweep records is the skyline seen along one bearing, and interpolating
/// between two bearings the observer actually looked at is the only
/// interpolation that means anything.
///
/// Altitudes are apparent, which is what a camera and an eye both see, so they
/// already carry atmospheric refraction and every consumer has to treat them
/// that way. Zero everywhere is an unobstructed sea horizon seen from sea
/// level; a summit sees the sea horizon below zero.
public struct HorizonProfile: Equatable, Sendable, Codable {

    public static let sectorCount = 36
    public static let sectorWidth = 360.0 / Double(sectorCount)

    /// Apparent horizon altitude in degrees, one entry per sector, sector 0
    /// first.
    public private(set) var sectors: [Double]

    /// Which sectors carry an observation rather than the default value.
    ///
    /// Without this a sweep could never record a skyline below the astronomical
    /// horizon. `record` keeps the higher of the stored value and the new
    /// reading, the stored value starts at zero, and the sea horizon seen from
    /// a summit or a clifftop is negative, so every such reading would be
    /// discarded. That is the case the terrain layer helps most, because it is
    /// the one where sunrise comes earlier rather than later, and flooring it
    /// at zero deletes it without saying so.
    private var observed: [Bool]

    /// Returns nil rather than trapping on a wrong count.
    ///
    /// Profiles arrive from a file written by an older version of the app and
    /// from a camera sweep that can be interrupted, and neither is under the
    /// control of the code that reads them.
    public init?(sectors: [Double]) {
        guard sectors.count == HorizonProfile.sectorCount else { return nil }
        self.sectors = sectors
        // A table handed over whole is data however it was produced, so every
        // sector counts as observed and a later `record` adds to it rather than
        // overwriting it as a first reading.
        self.observed = Array(repeating: true, count: HorizonProfile.sectorCount)
    }

    private init(unchecked sectors: [Double], observed: [Bool]) {
        self.sectors = sectors
        self.observed = observed
    }

    /// The horizon assumed when nothing has been measured: zero degrees in
    /// every direction, with no sector observed.
    ///
    /// This is an assumption, not a measurement, and `isMeasured` is false for
    /// it. A local sunrise computed against this profile is the ordinary
    /// published sunrise, so an interface that shows the difference between the
    /// flat time and the measured time must not show zero minutes here. Zero
    /// would claim a sweep that never happened.
    public static let flat = HorizonProfile(
        unchecked: Array(repeating: 0, count: HorizonProfile.sectorCount),
        observed: Array(repeating: false, count: HorizonProfile.sectorCount))

    /// The apparent horizon altitude along a bearing, linearly interpolated
    /// between the two nearest sector centres.
    public func altitude(atAzimuth azimuth: Double) -> Double {
        let bearing = Angle.normalized(azimuth)
        let scaled = bearing / HorizonProfile.sectorWidth
        let index = Int(scaled)
        let fraction = scaled - Double(index)
        // The wrap. East of sector 35, centred on 350 degrees, lies sector 0 at
        // 0 degrees, not sector 36, which does not exist. Clamping instead of
        // wrapping here puts a cliff in the horizon at due north, and it is the
        // one case that never shows up in a screenshot because nobody
        // photographs the direction they are standing with their back to.
        //
        // `index` is reduced as well as `index + 1`, because a bearing a hair
        // below zero normalises to 360.0 exactly: the nearest double to
        // 360 minus a rounding error is 360 itself. That is not a hypothetical.
        // The solar azimuth is produced by the same normalisation.
        let lower = index % HorizonProfile.sectorCount
        let upper = (index + 1) % HorizonProfile.sectorCount
        return sectors[lower] * (1 - fraction) + sectors[upper] * fraction
    }

    /// Records one skyline observation into the sector whose centre is nearest
    /// the given bearing.
    ///
    /// The first reading on a bearing is taken as given. Later readings only
    /// raise the sector, because a camera sweep crosses a building twice and
    /// the pass that catches the sky beside its edge must not undo the pass
    /// that caught its roof.
    public mutating func record(azimuth: Double, altitude: Double) {
        let index = HorizonProfile.sectorIndex(forAzimuth: azimuth)
        sectors[index] = observed[index] ? Swift.max(sectors[index], altitude) : altitude
        observed[index] = true
    }

    /// The sector whose centre is nearest a bearing.
    public static func sectorIndex(forAzimuth azimuth: Double) -> Int {
        // Rounding can land on 36, which is sector 0 approached from the west
        // side of north.
        let scaled = (Angle.normalized(azimuth) / sectorWidth).rounded()
        return Int(scaled) % sectorCount
    }

    /// True when at least one sector carries an observation.
    ///
    /// The interface needs this to tell a swept horizon from the flat one it
    /// assumes by default, because the two produce the same numbers and only
    /// one of them is a measurement.
    public var isMeasured: Bool { observed.contains(true) }

    /// How many of the thirty six sectors carry an observation. A sweep that
    /// covered a third of the sky is worth being explicit about.
    public var measuredSectorCount: Int { observed.reduce(0) { $1 ? $0 + 1 : $0 } }

    /// True when no sector is raised above the astronomical horizon.
    ///
    /// A tolerance rather than an equality test, because a swept profile carries
    /// values that are a rounding error away from zero and the caller is asking
    /// whether there is any terrain worth reporting, not whether the bits match.
    ///
    /// This says nothing about whether the profile was measured. A swept sea
    /// horizon and the default assumption are both flat; `isMeasured` is what
    /// separates them.
    public var isFlat: Bool {
        sectors.allSatisfy { Swift.abs($0) < 1e-9 }
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey { case sectors, observed }

    /// Validates on the way in. A decoded profile with the wrong number of
    /// sectors would index out of bounds on the first altitude query, far from
    /// the file that caused it.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let values = try container.decode([Double].self, forKey: .sectors)
        guard var profile = HorizonProfile(sectors: values) else {
            throw DecodingError.dataCorruptedError(
                forKey: .sectors, in: container,
                debugDescription: "a horizon profile has exactly \(HorizonProfile.sectorCount) sectors, found \(values.count)")
        }
        // A payload written before the observation mask existed carries only
        // altitudes. Somebody saved that profile, so it is a measurement, and
        // the fully observed default the initialiser already applied is right.
        if let mask = try container.decodeIfPresent([Bool].self, forKey: .observed) {
            guard mask.count == HorizonProfile.sectorCount else {
                throw DecodingError.dataCorruptedError(
                    forKey: .observed, in: container,
                    debugDescription: "an observation mask has exactly \(HorizonProfile.sectorCount) entries, found \(mask.count)")
            }
            profile.observed = mask
        }
        self = profile
    }
}
