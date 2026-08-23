import Foundation

// Proof driver for the offline city database.
//
// Data source for the committed resource: GeoNames, https://www.geonames.org,
// CC BY 4.0, https://creativecommons.org/licenses/by/4.0/
//
// Run with:  ./scripts/prove.sh scripts/prove/cities.swift
//
// prove.sh concatenates the SunlitCore sources and compiles them with swiftc,
// so there is no bundle here and nothing to load a resource from. The synthetic
// half of this driver therefore writes the version 1 blob itself, in memory,
// and feeds it through the same `CityIndex(data:)` the app uses. The real half
// reads the committed file by absolute path when it is on disk, which is what
// catches a drift between the Python folding in build.py and the Swift folding
// in CityIndex.swift. Neither half alone would.

var failures = 0

func fail(_ message: String) {
    print("FAIL  \(message)")
    failures += 1
}

func checkTrue(_ label: String, _ condition: Bool) {
    if !condition { fail(label) }
}

func checkEqual<T: Equatable>(_ label: String, _ got: T, _ want: T) {
    if got != want { fail("\(label): got \(got), want \(want)") }
}

func check(_ label: String, _ got: Double, _ want: Double, _ tolerance: Double) {
    let delta = abs(got - want)
    if delta > tolerance {
        fail("\(label): got \(got), want \(want), off by \(delta)")
    }
}

// MARK: A synthetic database, written in the format CityIndex reads

struct SyntheticCity {
    let name: String
    let asciiName: String
    let countryCode: String
    let latitude: Double
    let longitude: Double
    let elevation: Int
    let population: Int
    let timeZone: String
}

func appendLittleEndian(_ bytes: inout [UInt8], _ value: UInt32) {
    bytes.append(UInt8(value & 0xFF))
    bytes.append(UInt8((value >> 8) & 0xFF))
    bytes.append(UInt8((value >> 16) & 0xFF))
    bytes.append(UInt8((value >> 24) & 0xFF))
}

func appendLittleEndian(_ bytes: inout [UInt8], _ value: UInt16) {
    bytes.append(UInt8(value & 0xFF))
    bytes.append(UInt8((value >> 8) & 0xFF))
}

/// Encode cities into the version 1 blob, mirroring build.py.
func encodeSynthetic(_ cities: [SyntheticCity]) -> Data {
    // Population descending, name ascending inside a tie, exactly as the
    // script sorts, because search ranking rides on that storage order.
    let ordered = cities.sorted {
        $0.population == $1.population ? $0.name < $1.name : $0.population > $1.population
    }
    let zones = Array(Set(cities.map { $0.timeZone })).sorted()
    var zoneIndex: [String: UInt16] = [:]
    for (position, zone) in zones.enumerated() { zoneIndex[zone] = UInt16(position) }

    var zoneTable: [UInt8] = []
    for zone in zones {
        let encoded = Array(zone.utf8)
        zoneTable.append(UInt8(encoded.count))
        zoneTable += encoded
    }

    var records: [UInt8] = []
    var nameBlob: [UInt8] = []
    var keyBlob: [UInt8] = []

    for city in ordered {
        let encodedName = Array(city.name.utf8)
        let nameOffset = UInt32(nameBlob.count)
        nameBlob += encodedName

        var keys: [String] = []
        for candidate in [city.name, city.asciiName] {
            let key = CityIndex.foldedSearchKey(candidate)
            if !key.isEmpty && !keys.contains(key) { keys.append(key) }
        }
        for (position, key) in keys.enumerated() {
            let encoded = Array(key.utf8)
            let marker: UInt8 = position == keys.count - 1 ? 0x80 : 0x00
            keyBlob.append(UInt8(encoded.count) | marker)
            keyBlob += encoded
        }

        appendLittleEndian(&records, UInt32(bitPattern: Int32(city.latitude * 1e5)))
        appendLittleEndian(&records, UInt32(bitPattern: Int32(city.longitude * 1e5)))
        appendLittleEndian(&records, UInt32(city.population))
        appendLittleEndian(&records, UInt16(bitPattern: Int16(city.elevation)))
        appendLittleEndian(&records, zoneIndex[city.timeZone]!)
        let country = Array(city.countryCode.utf8)
        records.append(country.count > 0 ? country[0] : 0x20)
        records.append(country.count > 1 ? country[1] : 0x20)
        appendLittleEndian(&records, nameOffset)
        records.append(UInt8(encodedName.count))
        records.append(0)
    }

    let headerSize = 48
    let zoneOffset = headerSize
    let recordOffset = zoneOffset + zoneTable.count
    let nameOffset = recordOffset + records.count
    let keyOffset = nameOffset + nameBlob.count

    var header: [UInt8] = Array("SUNCITY1".utf8)
    appendLittleEndian(&header, UInt32(1))
    appendLittleEndian(&header, UInt32(ordered.count))
    appendLittleEndian(&header, UInt32(zones.count))
    appendLittleEndian(&header, UInt32(zoneOffset))
    appendLittleEndian(&header, UInt32(recordOffset))
    appendLittleEndian(&header, UInt32(nameOffset))
    appendLittleEndian(&header, UInt32(nameBlob.count))
    appendLittleEndian(&header, UInt32(keyOffset))
    appendLittleEndian(&header, UInt32(keyBlob.count))
    appendLittleEndian(&header, UInt32(0))
    precondition(header.count == headerSize, "synthetic header size drifted")

    return Data(header + zoneTable + records + nameBlob + keyBlob)
}

// MARK: Folding

// The query is folded on the device and the keys were folded by build.py. If
// these two ever disagree the search silently stops finding accented names, so
// the algorithm is pinned case by case here and again against the real file
// further down.
checkEqual("fold Koeln", CityIndex.foldedSearchKey("Köln"), "koln")
checkEqual("fold KOELN uppercase", CityIndex.foldedSearchKey("KÖLN"), "koln")
checkEqual("fold Sao Paulo", CityIndex.foldedSearchKey("São Paulo"), "sao paulo")
checkEqual("fold Zurich", CityIndex.foldedSearchKey("Zürich"), "zurich")
// An apostrophe and a full stop vanish, so the same place typed either way
// folds to one key.
checkEqual("fold Saint John's", CityIndex.foldedSearchKey("St. John's"), "st johns")
checkEqual("fold saint johns plain", CityIndex.foldedSearchKey("st johns"), "st johns")
// A hyphen becomes a space, so does a typed space.
checkEqual("fold Baden-Baden", CityIndex.foldedSearchKey("Baden-Baden"), "baden baden")
checkEqual("fold baden baden", CityIndex.foldedSearchKey("baden baden"), "baden baden")
// Latin letters that Unicode decomposition does not touch.
checkEqual("fold Koge", CityIndex.foldedSearchKey("Køge"), "koge")
checkEqual("fold Lodz", CityIndex.foldedSearchKey("Łódź"), "lodz")
checkEqual("fold Aarhus ligature", CityIndex.foldedSearchKey("Ærø"), "aero")
checkEqual("fold sharp s", CityIndex.foldedSearchKey("Gießen"), "giessen")
checkEqual("fold dotted capital i", CityIndex.foldedSearchKey("İzmir"), "izmir")
checkEqual("fold whitespace collapse", CityIndex.foldedSearchKey("  New   York  "), "new york")
checkEqual("fold digits survive", CityIndex.foldedSearchKey("Bat Yam 3"), "bat yam 3")
// A query with nothing typeable in it must fold to nothing rather than to a
// key that matches everything.
checkEqual("fold non Latin", CityIndex.foldedSearchKey("東京"), "")
checkEqual("fold punctuation only", CityIndex.foldedSearchKey("... '' ---"), "")

// MARK: Synthetic database

let synthetic: [SyntheticCity] = [
    SyntheticCity(name: "Köln", asciiName: "Koeln", countryCode: "DE",
                  latitude: 50.93333, longitude: 6.95, elevation: 58,
                  population: 1_024_621, timeZone: "Europe/Berlin"),
    SyntheticCity(name: "São Paulo", asciiName: "Sao Paulo", countryCode: "BR",
                  latitude: -23.5475, longitude: -46.63611, elevation: 769,
                  population: 12_400_232, timeZone: "America/Sao_Paulo"),
    SyntheticCity(name: "Springfield", asciiName: "Springfield", countryCode: "US",
                  latitude: 39.80172, longitude: -89.64371, elevation: 190,
                  population: 114_394, timeZone: "America/Chicago"),
    SyntheticCity(name: "Springdale", asciiName: "Springdale", countryCode: "US",
                  latitude: 36.18674, longitude: -94.12881, elevation: 383,
                  population: 84_161, timeZone: "America/Chicago"),
    SyntheticCity(name: "Palm Springs", asciiName: "Palm Springs", countryCode: "US",
                  latitude: 33.83030, longitude: -116.54529, elevation: 148,
                  population: 44_575, timeZone: "America/Los_Angeles"),
    SyntheticCity(name: "Ushuaia", asciiName: "Ushuaia", countryCode: "AR",
                  latitude: -54.80191, longitude: -68.30295, elevation: 33,
                  population: 63_685, timeZone: "America/Argentina/Ushuaia"),
    SyntheticCity(name: "Nuku'alofa", asciiName: "Nuku'alofa", countryCode: "TO",
                  latitude: -21.13938, longitude: -175.20180, elevation: 5,
                  population: 22_400, timeZone: "Pacific/Tongatapu"),
    SyntheticCity(name: "Apia", asciiName: "Apia", countryCode: "WS",
                  latitude: -13.83333, longitude: -171.76666, elevation: 2,
                  population: 40_407, timeZone: "Pacific/Apia"),
    SyntheticCity(name: "Longyearbyen", asciiName: "Longyearbyen", countryCode: "SJ",
                  latitude: 78.22334, longitude: 15.64689, elevation: 21,
                  population: 2_000, timeZone: "Arctic/Longyearbyen"),
    SyntheticCity(name: "New York City", asciiName: "New York City", countryCode: "US",
                  latitude: 40.71427, longitude: -74.00597, elevation: 10,
                  population: 8_804_190, timeZone: "America/New_York"),
    SyntheticCity(name: "York", asciiName: "York", countryCode: "GB",
                  latitude: 53.95763, longitude: -1.08271, elevation: 17,
                  population: 156_135, timeZone: "Europe/London"),
]

guard let index = try? CityIndex(data: encodeSynthetic(synthetic)) else {
    print("FATAL  the synthetic blob did not load")
    exit(1)
}

checkEqual("synthetic count", index.count, synthetic.count)

// Storage order is population descending, and every search leans on that.
var previousPopulation = Int.max
for position in 0..<index.count {
    let city = index.city(at: position)
    if city.population > previousPopulation {
        fail("synthetic storage order broke at \(position) with \(city.name)")
        break
    }
    previousPopulation = city.population
}
checkEqual("synthetic most populous first", index.city(at: 0).name, "São Paulo")

// Every field survives the round trip, including the ones a fixed width record
// is easiest to get wrong: a negative coordinate, an elevation, a time zone.
let koeln = index.search("koeln", limit: 5)
checkEqual("koeln finds one city", koeln.count, 1)
if let city = koeln.first {
    checkEqual("koeln name", city.name, "Köln")
    checkEqual("koeln country", city.countryCode, "DE")
    check("koeln latitude", city.latitude, 50.93333, 1e-5)
    check("koeln longitude", city.longitude, 6.95, 1e-5)
    check("koeln elevation", city.elevation, 58, 1e-9)
    checkEqual("koeln population", city.population, 1_024_621)
    checkEqual("koeln time zone", city.timeZoneIdentifier, "Europe/Berlin")
}

let ushuaia = index.search("ushuaia", limit: 5)
if let city = ushuaia.first {
    check("ushuaia negative latitude", city.latitude, -54.80191, 1e-5)
    check("ushuaia negative longitude", city.longitude, -68.30295, 1e-5)
    checkEqual("ushuaia time zone", city.timeZoneIdentifier, "America/Argentina/Ushuaia")
} else {
    fail("ushuaia not found")
}

// Diacritic and case insensitivity, in both directions.
checkEqual("koln finds Koeln", index.search("koln", limit: 5).first?.name ?? "", "Köln")
checkEqual("KÖLN finds Koeln", index.search("KÖLN", limit: 5).first?.name ?? "", "Köln")
checkEqual("Köln finds Koeln", index.search("Köln", limit: 5).first?.name ?? "", "Köln")
checkEqual("sao finds Sao Paulo", index.search("sao", limit: 5).first?.name ?? "", "São Paulo")
checkEqual("SÃO PAULO finds Sao Paulo",
           index.search("SÃO PAULO", limit: 5).first?.name ?? "", "São Paulo")
// The apostrophe is deleted on both sides, so either spelling reaches it.
checkEqual("nukualofa without apostrophe",
           index.search("nukualofa", limit: 5).first?.name ?? "", "Nuku'alofa")
checkEqual("nuku'alofa with apostrophe",
           index.search("nuku'alofa", limit: 5).first?.name ?? "", "Nuku'alofa")

// A city with two keys must still appear once.
checkEqual("koln does not duplicate", index.search("ko", limit: 10).filter { $0.name == "Köln" }.count, 1)

// Ranking inside the prefix class is population descending, and the substring
// class follows the whole prefix class.
let springs = index.search("spring", limit: 10)
checkEqual("spring result count", springs.count, 3)
checkEqual("spring first", springs[0].name, "Springfield")     // prefix, 114,394
checkEqual("spring second", springs[1].name, "Springdale")     // prefix, 84,161
checkEqual("spring third", springs[2].name, "Palm Springs")    // substring, 44,575

// Prefix beats substring even when the substring match is far more populous.
// This is the case that a naive "sort every hit by population" would get wrong:
// York has 156,135 people and New York City has 8,804,190, and York still comes
// first, because the query starts its name.
let yorks = index.search("york", limit: 10)
checkEqual("york result count", yorks.count, 2)
checkEqual("york prefix class first", yorks[0].name, "York")
checkEqual("york substring class second", yorks[1].name, "New York City")
checkTrue("york first is the smaller city", yorks[0].population < yorks[1].population)
// Reading it the other way round: "field" only ever matches inside a name.
checkEqual("field substring", index.search("field", limit: 10).first?.name ?? "", "Springfield")

// The limit is honoured and a query that folds to nothing returns nothing.
checkEqual("limit one", index.search("s", limit: 1).count, 1)
checkEqual("limit zero", index.search("s", limit: 0).count, 0)
checkEqual("empty query", index.search("", limit: 10).count, 0)
checkEqual("blank query", index.search("   ", limit: 10).count, 0)
checkEqual("non Latin query", index.search("東京", limit: 10).count, 0)
checkEqual("no match", index.search("qzxwv", limit: 10).count, 0)

// Nearest, on the synthetic set. Longyearbyen is the only place above the
// Arctic Circle here, and the query sits a degree away from it.
checkEqual("nearest to Svalbard",
           index.nearest(latitude: 78.0, longitude: 16.0)?.name ?? "", "Longyearbyen")
// Across the antimeridian: a query at 179 degrees east must reach Apia at
// 171.77 degrees west, 9 degrees away the short way and 351 the long way.
checkEqual("nearest across the antimeridian",
           index.nearest(latitude: -13.85, longitude: 179.5)?.name ?? "", "Apia")

// MARK: The committed resource

// prove.sh runs the compiled driver from the repository root, so this is an
// absolute path built from the working directory rather than from #filePath,
// which would point into the temporary compile directory.
let resourcePath = FileManager.default.currentDirectoryPath
    + "/Sources/Sunlit/Resources/Cities/cities.bin"

if let blob = try? Data(contentsOf: URL(fileURLWithPath: resourcePath)) {
    // The bundle budget for this resource is 3 MB.
    checkTrue("resource is under 3 MB", blob.count < 3 * 1024 * 1024)

    guard let cities = try? CityIndex(data: blob) else {
        print("FATAL  \(resourcePath) did not load")
        exit(1)
    }
    checkTrue("resource holds at least 25000 cities", cities.count >= 25_000)

    // Storage order across the whole table, not just the first page of it.
    var previous = Int.max
    var orderBroken = false
    for position in 0..<cities.count {
        let population = cities.city(at: position).population
        if population > previous { orderBroken = true; break }
        previous = population
    }
    checkTrue("resource is sorted by population descending", !orderBroken)

    // These are the cases the task names. They also prove that the Python
    // folding in build.py and the Swift folding here agree, because the keys
    // were written by one and the query is folded by the other.
    let koln = cities.search("koln", limit: 5)
    checkEqual("resource koln first name", koln.first?.name ?? "", "Köln")
    checkEqual("resource koln first country", koln.first?.countryCode ?? "", "DE")
    checkEqual("resource koln time zone", koln.first?.timeZoneIdentifier ?? "", "Europe/Berlin")
    checkEqual("resource koeln first name",
               cities.search("koeln", limit: 5).first?.name ?? "", "Köln")
    checkEqual("resource Köln typed with the umlaut",
               cities.search("Köln", limit: 5).first?.name ?? "", "Köln")

    let sao = cities.search("sao", limit: 5)
    checkEqual("resource sao first name", sao.first?.name ?? "", "São Paulo")
    checkEqual("resource sao first country", sao.first?.countryCode ?? "", "BR")
    checkEqual("resource SAO PAULO uppercase",
               cities.search("SAO PAULO", limit: 5).first?.name ?? "", "São Paulo")
    checkEqual("resource Sao Paulo with the tilde",
               cities.search("São Paulo", limit: 5).first?.name ?? "", "São Paulo")

    // Ranking, measured rather than assumed: the results of a broad query come
    // back in population order.
    let broad = cities.search("san", limit: 20)
    checkEqual("resource broad query fills the limit", broad.count, 20)
    var rankBroken = false
    for position in 1..<broad.count where broad[position].population > broad[position - 1].population {
        rankBroken = true
    }
    checkTrue("resource ranks by population", !rankBroken)
    checkEqual("resource san first", broad.first?.name ?? "", "Santiago")

    // Prefix before substring, on the real data. York in England has 156,135
    // people, New York City has 8,804,190, and York is first because the query
    // starts its name. Every prefix match precedes the first substring match.
    let realYorks = cities.search("york", limit: 20)
    checkEqual("resource york first", realYorks.first?.name ?? "", "York")
    let newYorkPosition = realYorks.firstIndex { $0.name == "New York City" } ?? -1
    checkTrue("resource york reaches New York City", newYorkPosition > 0)
    if newYorkPosition > 0 {
        checkTrue("resource ranks prefix matches above a larger substring match",
                  realYorks[newYorkPosition - 1].population < realYorks[newYorkPosition].population)
    }

    // Elevation is carried, not dropped. Mexico City sits above 2200 m, and the
    // clear-sky UV and irradiance models read that elevation.
    if let mexico = cities.search("mexico city", limit: 3).first {
        checkEqual("resource Mexico City name", mexico.name, "Mexico City")
        checkTrue("resource carries elevation, Mexico City above 2000 m", mexico.elevation > 2000)
        checkEqual("resource Mexico City time zone", mexico.timeZoneIdentifier, "America/Mexico_City")
    } else {
        fail("resource did not find Mexico City")
    }

    // Three known coordinates, one per hemisphere pairing.
    let nearMunich = cities.nearest(latitude: 48.1372, longitude: 11.5755)
    checkEqual("nearest to Munich centre", nearMunich?.name ?? "", "Munich")
    checkEqual("nearest to Munich country", nearMunich?.countryCode ?? "", "DE")

    let nearSydney = cities.nearest(latitude: -33.8688, longitude: 151.2093)
    checkEqual("nearest to Sydney harbour", nearSydney?.name ?? "", "Sydney")
    checkEqual("nearest to Sydney country", nearSydney?.countryCode ?? "", "AU")

    let nearNewYork = cities.nearest(latitude: 40.7128, longitude: -74.0060)
    checkEqual("nearest to Manhattan", nearNewYork?.name ?? "", "New York City")
    checkEqual("nearest to Manhattan country", nearNewYork?.countryCode ?? "", "US")

    // Timing. Search runs on every keystroke, so it has to finish inside a
    // frame. The queries below are chosen to be expensive: each one leaves the
    // prefix class short of the limit, which forces the substring scan across
    // the whole key blob, and most of them start with a common letter so the
    // inner comparison is entered often.
    let queries = ["a", "an", "ang", "ari", "berg", "e", "er", "eri", "ington",
                   "koln", "new", "s", "san", "sao", "ville", "zzzzz"]
    var worstQuery = ""
    var worstMilliseconds = 0.0
    // Every result is counted into a sink that is asserted on below. Without it
    // the optimiser is free to delete the timed loop, and the driver would then
    // be reporting the cost of an empty for loop as proof of a fast search.
    var searchSink = 0
    for query in queries {
        // One warm pass so the measurement is not dominated by a cold cache.
        searchSink += cities.search(query, limit: 25).count
        let rounds = 20
        let started = ProcessInfo.processInfo.systemUptime
        for _ in 0..<rounds { searchSink += cities.search(query, limit: 25).count }
        let elapsed = (ProcessInfo.processInfo.systemUptime - started) / Double(rounds) * 1000.0
        if elapsed > worstMilliseconds {
            worstMilliseconds = elapsed
            worstQuery = query
        }
    }
    checkTrue("the timed searches actually ran", searchSink > 21 * queries.count)
    print(String(format: "       search over %d cities, worst of %d queries: %.3f ms on \"%@\"",
                 cities.count, queries.count, worstMilliseconds, worstQuery))
    // The frame budget is 16 ms. Anything close to it would drop a frame while
    // the keyboard is also drawing, so the assertion is set well inside it.
    checkTrue("search stays inside the frame budget", worstMilliseconds < 16.0)
    checkTrue("search is well inside the frame budget", worstMilliseconds < 4.0)

    var nearestSink = 0
    let startedNearest = ProcessInfo.processInfo.systemUptime
    for _ in 0..<20 {
        nearestSink += cities.nearest(latitude: 48.1372, longitude: 11.5755)?.population ?? 0
    }
    let nearestMilliseconds = (ProcessInfo.processInfo.systemUptime - startedNearest) / 20.0 * 1000.0
    checkTrue("the timed nearest lookups actually ran", nearestSink > 0)
    print(String(format: "       nearest over %d cities: %.3f ms", cities.count, nearestMilliseconds))
    checkTrue("nearest stays inside the frame budget", nearestMilliseconds < 16.0)

    print(String(format: "       resource %d bytes, %d cities", blob.count, cities.count))
} else {
    // Not a pass. The generated file is committed precisely so that it is here.
    fail("the committed resource is missing at \(resourcePath)")
}

// MARK: Malformed input

// A truncated or foreign blob has to be rejected at load, because every read
// after that point trusts the header.
checkTrue("empty data is rejected", (try? CityIndex(data: Data())) == nil)
checkTrue("wrong magic is rejected",
          (try? CityIndex(data: Data(Array("NOTACITY".utf8) + [UInt8](repeating: 0, count: 64)))) == nil)
var wrongVersion = [UInt8](encodeSynthetic(synthetic))
wrongVersion[8] = 9
checkTrue("unsupported version is rejected", (try? CityIndex(data: Data(wrongVersion))) == nil)
let truncated = encodeSynthetic(synthetic).prefix(200)
checkTrue("truncated blob is rejected", (try? CityIndex(data: Data(truncated))) == nil)

if failures == 0 {
    print("cities: all checks passed")
} else {
    print("cities: \(failures) FAILURES")
    exit(1)
}
