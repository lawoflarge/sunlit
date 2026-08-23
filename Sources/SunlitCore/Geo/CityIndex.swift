import Foundation

// The embedded offline city database.
//
// Data source
// ===========
// GeoNames cities15000, every populated place above 15000 inhabitants.
//
// This work is licensed under a Creative Commons Attribution 4.0 License,
// see https://creativecommons.org/licenses/by/4.0/
// The Data is provided "as is" without warranty or any representation of
// accuracy, timeliness or completeness.
//
//     Data source: GeoNames, https://www.geonames.org, CC BY 4.0
//
// That attribution is a licence obligation and is owed in three places: in
// Settings inside the app, in the repository README, and on the website. As of
// this writing the website carries it (web/index.html, web/privacy.html and
// web/support.html) and the other two do not exist yet: there is no README in
// this repository and Sources/Sunlit/Features/Settings is still empty. Neither
// may ship without it, and `CityIndex.attribution` below is the string to use.
//
// The resource is produced by Sources/Sunlit/Resources/Cities/build.py and is
// committed to the repository, because the app has to build with no network
// access. SunlitCore imports Foundation and nothing else, so this type never
// reaches for a bundle. The app target reads the file and hands over the Data.
//
// Binary format, version 1
// ========================
// All integers are little endian and unaligned. Byte offsets are absolute.
// The identical layout is documented at the top of build.py, which writes it.
//
//   header, 48 bytes
//     0   magic, the 8 ASCII bytes "SUNCITY1"
//     8   u32   format version, currently 1
//     12  u32   city count
//     16  u32   time zone count
//     20  u32   offset of the time zone table
//     24  u32   offset of the record table
//     28  u32   offset of the name blob
//     32  u32   length of the name blob
//     36  u32   offset of the key blob
//     40  u32   length of the key blob
//     44  u32   reserved, zero
//
//   time zone table
//     One entry per zone, ordered alphabetically:
//       u8    length in bytes
//       ...   IANA identifier, ASCII
//
//   record table
//     City count records of exactly 24 bytes, sorted by population descending
//     and by GeoNames id ascending within equal populations. Search ranking
//     therefore falls out of the storage order and costs nothing at runtime:
//     walking the keys in file order already visits the most populous city
//     first, so a match can be appended without ever sorting.
//       0   i32   latitude in units of 1e-5 degrees
//       4   i32   longitude in units of 1e-5 degrees
//       8   u32   population
//       12  i16   elevation in metres
//       14  u16   index into the time zone table
//       16  2     ISO 3166-1 alpha-2 country code, ASCII
//       18  u32   offset of the display name inside the name blob
//       22  u8    length of the display name in bytes
//       23  u8    reserved, zero
//
//   name blob
//     Display names, UTF-8, not terminated. The GeoNames `name` field, which
//     keeps its diacritics.
//
//   key blob
//     The folded search keys, in the same order as the record table, so the
//     city a key belongs to is implied by counting. Each key is
//       u8    length, with bit 7 set when this is the last key of a city
//       ...   the key, ASCII, at most 127 bytes
//     A city carries one key when its GeoNames `name` and `asciiname` fold to
//     the same thing, and two when they differ. Köln stores "koln", folded from
//     the name, and "koeln", folded from the ASCII name "Koeln", so both
//     spellings find it. 390 of the 34,106 cities carry two keys.
//
// Not indexed: the `alternatenames` column. It is where GeoNames keeps every
// other spelling of a place, but it keeps them without language tags and mixed
// with transliteration noise, and folding every entry in it measures 3,245,149
// bytes for the resource, past the 3 MB budget. Search runs against the `name`
// and `asciiname` columns only.
//
// The consequence is bigger than the phrase "no alternate names" suggests, and
// it is not the consequence one would guess. GeoNames `name` is frequently the
// English exonym rather than the local endonym, so it is the *local* spelling
// that is missing: "munich" finds Munich and "muenchen" does not, "gothenburg"
// finds Gothenburg and "goteborg" does not. Measured over a sample of 36
// European endonyms, 21 of them reach nothing or the wrong place, among them
// München, Praha, Warszawa, Firenze, Venezia, Bruxelles, København, Moskva and
// Athina. The app sells in ten languages, so this is a known product gap and
// not merely a note on the file format. Closing it means indexing part of
// `alternatenames` and re-arguing the 3 MB budget.

/// One populated place, as stored in the embedded database.
public struct City: Equatable, Hashable, Sendable {
    /// The local name, diacritics intact, as GeoNames writes it.
    public let name: String
    /// ISO 3166-1 alpha-2, uppercase.
    public let countryCode: String
    /// Degrees north, negative south.
    public let latitude: Double
    /// Degrees east, negative west.
    public let longitude: Double
    /// Metres above sea level. Zero where GeoNames has no value.
    public let elevation: Double
    public let population: Int
    /// An IANA identifier such as `Europe/Berlin`.
    public let timeZoneIdentifier: String

    public init(
        name: String,
        countryCode: String,
        latitude: Double,
        longitude: Double,
        elevation: Double,
        population: Int,
        timeZoneIdentifier: String
    ) {
        self.name = name
        self.countryCode = countryCode
        self.latitude = latitude
        self.longitude = longitude
        self.elevation = elevation
        self.population = population
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}

public enum CityIndexError: Error, CustomStringConvertible {
    case tooShort
    case badMagic
    case unsupportedVersion(UInt32)
    case sectionOutOfBounds(String)
    case timeZoneTableMalformed
    case keyBlobMalformed(cities: Int, expected: Int)

    public var description: String {
        switch self {
        case .tooShort:
            return "city database is shorter than its header"
        case .badMagic:
            return "city database does not begin with SUNCITY1"
        case .unsupportedVersion(let version):
            return "city database format version \(version) is not supported"
        case .sectionOutOfBounds(let name):
            return "city database section \(name) runs past the end of the file"
        case .timeZoneTableMalformed:
            return "city database time zone table does not match its declared count"
        case .keyBlobMalformed(let cities, let expected):
            return "city database key blob covers \(cities) cities, expected \(expected)"
        }
    }
}

/// Offline search over the embedded GeoNames extract.
///
/// Construct it once with the resource bytes and keep it. Construction copies
/// the blob into contiguous storage and validates every section, which is what
/// lets `search` and `nearest` read raw pointers without bounds checks.
public struct CityIndex: Sendable {

    /// The GeoNames attribution required by CC BY 4.0.
    public static let attribution = "Data source: GeoNames, https://www.geonames.org, CC BY 4.0"

    private static let magic: [UInt8] = Array("SUNCITY1".utf8)
    private static let headerSize = 48
    private static let recordSize = 24
    private static let supportedVersion: UInt32 = 1

    private let bytes: [UInt8]
    private let recordOffset: Int
    private let nameOffset: Int
    private let keyOffset: Int
    private let keyLength: Int
    private let timeZones: [String]

    /// How many cities the database holds.
    public let count: Int

    // MARK: Loading

    /// Parse a database blob. The caller supplies the bytes; this type never
    /// touches the file system or a bundle.
    public init(data: Data) throws {
        let bytes = [UInt8](data)
        guard bytes.count >= CityIndex.headerSize else { throw CityIndexError.tooShort }
        guard Array(bytes[0..<8]) == CityIndex.magic else { throw CityIndexError.badMagic }

        let version = CityIndex.readUInt32(bytes, 8)
        guard version == CityIndex.supportedVersion else {
            throw CityIndexError.unsupportedVersion(version)
        }

        let cityCount = Int(CityIndex.readUInt32(bytes, 12))
        let zoneCount = Int(CityIndex.readUInt32(bytes, 16))
        let zoneOffset = Int(CityIndex.readUInt32(bytes, 20))
        let recordOffset = Int(CityIndex.readUInt32(bytes, 24))
        let nameOffset = Int(CityIndex.readUInt32(bytes, 28))
        let nameLength = Int(CityIndex.readUInt32(bytes, 32))
        let keyOffset = Int(CityIndex.readUInt32(bytes, 36))
        let keyLength = Int(CityIndex.readUInt32(bytes, 40))

        func inBounds(_ start: Int, _ length: Int) -> Bool {
            start >= CityIndex.headerSize && length >= 0 && start + length <= bytes.count
        }
        guard inBounds(zoneOffset, recordOffset - zoneOffset), recordOffset >= zoneOffset else {
            throw CityIndexError.sectionOutOfBounds("time zone table")
        }
        guard inBounds(recordOffset, cityCount * CityIndex.recordSize) else {
            throw CityIndexError.sectionOutOfBounds("record table")
        }
        guard inBounds(nameOffset, nameLength) else {
            throw CityIndexError.sectionOutOfBounds("name blob")
        }
        guard inBounds(keyOffset, keyLength) else {
            throw CityIndexError.sectionOutOfBounds("key blob")
        }

        var zones: [String] = []
        zones.reserveCapacity(zoneCount)
        var cursor = zoneOffset
        while zones.count < zoneCount {
            guard cursor < recordOffset else { throw CityIndexError.timeZoneTableMalformed }
            let length = Int(bytes[cursor])
            let start = cursor + 1
            guard start + length <= recordOffset else { throw CityIndexError.timeZoneTableMalformed }
            zones.append(String(decoding: bytes[start..<(start + length)], as: UTF8.self))
            cursor = start + length
        }
        guard cursor == recordOffset else { throw CityIndexError.timeZoneTableMalformed }

        // Every record is checked once here so that the accessors below can be
        // total. A corrupt blob must fail at load, not halfway down a list.
        for index in 0..<cityCount {
            let base = recordOffset + index * CityIndex.recordSize
            let zone = Int(CityIndex.readUInt16(bytes, base + 14))
            guard zone < zones.count else {
                throw CityIndexError.sectionOutOfBounds("time zone index in record \(index)")
            }
            let start = Int(CityIndex.readUInt32(bytes, base + 18))
            let length = Int(bytes[base + 22])
            guard start + length <= nameLength else {
                throw CityIndexError.sectionOutOfBounds("name of record \(index)")
            }
        }

        // The key blob carries no city numbers. It is walked, and the city a
        // key belongs to is the number of terminators seen so far. If that walk
        // does not land on exactly the record count, every search result would
        // point at the wrong city, so it is verified once at load.
        var walked = 0
        var keyCursor = keyOffset
        let keyEnd = keyOffset + keyLength
        while keyCursor < keyEnd {
            let header = bytes[keyCursor]
            let length = Int(header & 0x7F)
            let start = keyCursor + 1
            guard start + length <= keyEnd else {
                throw CityIndexError.keyBlobMalformed(cities: walked, expected: cityCount)
            }
            if header & 0x80 != 0 { walked += 1 }
            keyCursor = start + length
        }
        guard walked == cityCount else {
            throw CityIndexError.keyBlobMalformed(cities: walked, expected: cityCount)
        }

        self.bytes = bytes
        self.count = cityCount
        self.recordOffset = recordOffset
        self.nameOffset = nameOffset
        self.keyOffset = keyOffset
        self.keyLength = keyLength
        self.timeZones = zones
    }

    // MARK: Reading

    /// The city at a storage position. Position zero is the most populous.
    public func city(at index: Int) -> City {
        precondition(index >= 0 && index < count, "city index \(index) out of range 0..<\(count)")
        let base = recordOffset + index * CityIndex.recordSize
        let nameStart = nameOffset + Int(CityIndex.readUInt32(bytes, base + 18))
        let nameLength = Int(bytes[base + 22])
        var country = String(decoding: bytes[(base + 16)..<(base + 18)], as: UTF8.self)
        country = country.trimmingCharacters(in: .whitespaces)
        return City(
            name: String(decoding: bytes[nameStart..<(nameStart + nameLength)], as: UTF8.self),
            countryCode: country,
            latitude: Double(CityIndex.readInt32(bytes, base)) * 1e-5,
            longitude: Double(CityIndex.readInt32(bytes, base + 4)) * 1e-5,
            elevation: Double(CityIndex.readInt16(bytes, base + 12)),
            population: Int(CityIndex.readUInt32(bytes, base + 8)),
            timeZoneIdentifier: timeZones[Int(CityIndex.readUInt16(bytes, base + 14))]
        )
    }

    // MARK: Search

    /// Cities whose folded name starts with, or contains, the folded query.
    ///
    /// The query is folded exactly as the stored keys were, so the match is
    /// case insensitive and diacritic insensitive: "koln" finds Köln, "sao"
    /// finds São Paulo, "zurich" finds Zürich. Names that begin with the query
    /// come first, names that merely contain it come after, and within each of
    /// those two classes the order is population descending. That order is
    /// free, because the records are already stored in population order and the
    /// walk visits them in it.
    ///
    /// A city carrying two keys is placed by the best of them: it is a prefix
    /// hit if either key starts with the query, even when the other key only
    /// contains it.
    ///
    /// An empty query, or one that folds away to nothing, returns no results.
    public func search(_ query: String, limit: Int = 25) -> [City] {
        guard limit > 0 else { return [] }
        let needle = Array(CityIndex.foldedSearchKey(query).utf8)
        guard !needle.isEmpty else { return [] }

        var prefixHits: [Int] = []
        var substringHits: [Int] = []
        prefixHits.reserveCapacity(limit)
        substringHits.reserveCapacity(limit)

        bytes.withUnsafeBufferPointer { buffer in
            let base = buffer.baseAddress!
            needle.withUnsafeBufferPointer { needleBuffer in
                let pattern = needleBuffer.baseAddress!
                let needleCount = needleBuffer.count
                let firstByte = pattern[0]

                var cursor = keyOffset
                let end = keyOffset + keyLength
                var cityIndex = 0
                // A city can carry two keys, and the class it lands in is
                // decided only once every one of them has been looked at.
                // Stopping at the first key that matched would rank a city one
                // class low whenever an earlier key contains the query and a
                // later key starts with it, and those two keys are not exotic:
                // GeoNames writes San Sebastian as "Donostia / San Sebastián"
                // with the ASCII name "San Sebastian", so the query "san
                // sebastian" is a substring of the first key and a prefix of
                // the second. Eleven cities in the committed resource are in
                // that shape, and the largest of them, 185,357 people, was
                // ranked behind towns of 75,912, 33,340, 29,167 and 28,138.
                var cityMatchedPrefix = false
                var cityMatchedSubstring = false

                walk: while cursor < end {
                    let header = base[cursor]
                    let isLastKey = (header & 0x80) != 0
                    let length = Int(header & 0x7F)
                    let start = cursor + 1
                    cursor = start + length

                    if !cityMatchedPrefix && length >= needleCount {
                        var isPrefix = true
                        var i = 0
                        while i < needleCount {
                            if base[start + i] != pattern[i] { isPrefix = false; break }
                            i += 1
                        }
                        if isPrefix {
                            cityMatchedPrefix = true
                        } else if !cityMatchedSubstring && substringHits.count < limit {
                            let lastStart = length - needleCount
                            var position = 1
                            scan: while position <= lastStart {
                                if base[start + position] == firstByte {
                                    var j = 1
                                    var equal = true
                                    while j < needleCount {
                                        if base[start + position + j] != pattern[j] {
                                            equal = false
                                            break
                                        }
                                        j += 1
                                    }
                                    if equal {
                                        cityMatchedSubstring = true
                                        break scan
                                    }
                                }
                                position += 1
                            }
                        }
                    }

                    if isLastKey {
                        if cityMatchedPrefix {
                            prefixHits.append(cityIndex)
                            if prefixHits.count == limit { break walk }
                        } else if cityMatchedSubstring {
                            substringHits.append(cityIndex)
                        }
                        cityIndex += 1
                        cityMatchedPrefix = false
                        cityMatchedSubstring = false
                    }
                }
            }
        }

        var hits = prefixHits
        if hits.count < limit {
            hits.append(contentsOf: substringHits.prefix(limit - hits.count))
        }
        return hits.map { city(at: $0) }
    }

    /// The city closest to a coordinate, or nil when the database is empty.
    ///
    /// Distance is equirectangular, longitude scaled by the cosine of the query
    /// latitude and wrapped across the antimeridian. That is not a great circle
    /// distance, but it orders candidates the same way over the ranges that
    /// matter here, and it costs no trigonometry per city.
    public func nearest(latitude: Double, longitude: Double) -> City? {
        guard count > 0 else { return nil }
        let cosLatitude = cos(latitude * Double.pi / 180.0)
        var bestIndex = 0
        var bestDistance = Double.infinity

        bytes.withUnsafeBufferPointer { buffer in
            let base = buffer.baseAddress!
            var offset = recordOffset
            for index in 0..<count {
                let cityLatitude = Double(CityIndex.readInt32Raw(base, offset)) * 1e-5
                let cityLongitude = Double(CityIndex.readInt32Raw(base, offset + 4)) * 1e-5
                var deltaLongitude = cityLongitude - longitude
                if deltaLongitude > 180.0 {
                    deltaLongitude -= 360.0
                } else if deltaLongitude < -180.0 {
                    deltaLongitude += 360.0
                }
                let x = deltaLongitude * cosLatitude
                let y = cityLatitude - latitude
                let distance = x * x + y * y
                if distance < bestDistance {
                    bestDistance = distance
                    bestIndex = index
                }
                offset += CityIndex.recordSize
            }
        }
        return city(at: bestIndex)
    }

    // MARK: Folding

    /// Fold a name or a query into its ASCII search key.
    ///
    /// This is the Swift half of a shared algorithm. `fold` in build.py is the
    /// other half, and the two must stay identical, because keys are folded by
    /// the script and queries are folded here.
    ///
    ///  1. Unicode normalisation form KD.
    ///  2. Lowercase.
    ///  3. Drop every combining mark, so "Köln" becomes "koln".
    ///  4. Transliterate the Latin letters that KD does not decompose, so
    ///     "Køge" becomes "koge" rather than losing a letter.
    ///  5. Delete apostrophes and full stops, so "St. John's" and "st johns"
    ///     fold alike. Map anything else that is not an ASCII letter, digit or
    ///     space to a space, so "Baden-Baden" and "baden baden" fold alike.
    ///  6. Collapse runs of whitespace and strip.
    public static func foldedSearchKey(_ text: String) -> String {
        var out: [UInt8] = []
        out.reserveCapacity(text.utf8.count)
        var pendingSpace = false

        func append(_ byte: UInt8) {
            if pendingSpace {
                if !out.isEmpty { out.append(0x20) }
                pendingSpace = false
            }
            out.append(byte)
        }

        for scalar in text.decomposedStringWithCompatibilityMapping.lowercased().unicodeScalars {
            switch scalar.properties.generalCategory {
            case .nonspacingMark, .spacingMark, .enclosingMark:
                continue
            default:
                break
            }

            let value = scalar.value
            if let replacement = CityIndex.transliteration(value) {
                for byte in replacement { append(byte) }
                continue
            }
            if CityIndex.isDeleted(value) {
                continue
            }
            if (value >= 0x61 && value <= 0x7A) || (value >= 0x30 && value <= 0x39) {
                append(UInt8(value))
            } else if value >= 0x41 && value <= 0x5A {
                append(UInt8(value + 0x20))
            } else {
                pendingSpace = true
            }
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// Apostrophes and full stops vanish rather than becoming a space, so a
    /// name written with one and the same name typed without one agree.
    private static func isDeleted(_ value: UInt32) -> Bool {
        switch value {
        case 0x0027, 0x002E, 0x0060, 0x00B4, 0x02BB, 0x02BC, 0x2018, 0x2019:
            return true
        default:
            return false
        }
    }

    /// Latin letters with no compatibility decomposition. Without these a
    /// Danish, Polish or Icelandic name folds to a hole rather than a letter.
    private static func transliteration(_ value: UInt32) -> [UInt8]? {
        switch value {
        case 0x00F8: return [0x6F]              // o with stroke, o
        case 0x00E6: return [0x61, 0x65]        // ae
        case 0x0153: return [0x6F, 0x65]        // oe
        case 0x00DF: return [0x73, 0x73]        // sharp s, ss
        case 0x0111: return [0x64]              // d with stroke, d
        case 0x00F0: return [0x64]              // eth, d
        case 0x00FE: return [0x74, 0x68]        // thorn, th
        case 0x0142: return [0x6C]              // l with stroke, l
        case 0x0131: return [0x69]              // dotless i, i
        case 0x0127: return [0x68]              // h with stroke, h
        case 0x014B: return [0x6E]              // eng, n
        case 0x0167: return [0x74]              // t with stroke, t
        case 0x0138: return [0x6B]              // kra, k
        case 0x017F: return [0x73]              // long s, s
        default: return nil
        }
    }

    // MARK: Little endian reads

    private static func readUInt16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func readUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    private static func readInt16(_ bytes: [UInt8], _ offset: Int) -> Int16 {
        Int16(bitPattern: readUInt16(bytes, offset))
    }

    private static func readInt32(_ bytes: [UInt8], _ offset: Int) -> Int32 {
        Int32(bitPattern: readUInt32(bytes, offset))
    }

    @inline(__always)
    private static func readInt32Raw(_ base: UnsafePointer<UInt8>, _ offset: Int) -> Int32 {
        let raw = UInt32(base[offset])
            | (UInt32(base[offset + 1]) << 8)
            | (UInt32(base[offset + 2]) << 16)
            | (UInt32(base[offset + 3]) << 24)
        return Int32(bitPattern: raw)
    }
}
