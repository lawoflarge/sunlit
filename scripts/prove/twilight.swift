import Foundation

// Reference values in this file are published times fetched from two
// independent authorities, neither of which is this code.
//
// Source A, US Naval Observatory, Astronomical Applications Department,
// "Sun or Moon Rise/Set Table for an Entire Year" and "Complete Sun and Moon
// Data for One Day", fetched 23 August 2026:
//   https://aa.usno.navy.mil/calculated/rstt/year?ID=AA&year=2026&task=T
//        &lat=LAT&lon=LON&tz=TZ&tz_sign=SIGN
//        with task 0 sunrise/sunset, 2 civil, 3 nautical, 4 astronomical
//   https://aa.usno.navy.mil/api/rstt/oneday?date=DATE&coords=LAT,LON&tz=TZ
// Source B, Meteorologisk institutt, the Norwegian national meteorological
// office, sunrise API 3.0, fetched 23 August 2026:
//   https://api.met.no/weatherapi/sunrise/3.0/sun?lat=LAT&lon=LON&date=DATE
//        &offset=OFFSET
//
// Tolerance is two minutes on every published time. Both authorities publish
// rounded to the whole minute, so each carries up to thirty seconds of its own
// rounding, and on the same event they disagree with each other by up to a
// whole minute: USNO puts Quito sunset on 2026-03-20 at 18:25 while MET Norway
// puts it at 18:24. A tolerance tighter than two minutes would be measuring the
// disagreement between the sources rather than the error of this code.
//
// Every table below is fetched with that place's own UTC offset, so the printed
// times are local clock times and the row belongs to the local day, which is
// the day `Twilight.phases` is asked about. 2026 offsets: Berlin +2 in June and
// +1 in December, Quito -5, Sydney +10, Tromso +2 in June and +1 in December.

var failures = 0, checks = 0
func fail(_ message: String) {
    print("FAIL  \(message)")
    failures += 1
}
func check(_ label: String, _ got: Double, _ want: Double, _ tolerance: Double) {
    checks += 1
    if abs(got - want) > tolerance {
        fail("\(label): got \(got), want \(want), off by \(abs(got - want))")
    }
}
func checkTrue(_ label: String, _ ok: Bool) {
    checks += 1
    if !ok { fail(label) }
}

struct Place {
    let name: String
    let geographic: Coordinates.Geographic
    let year: Int
    let month: Int
    let day: Int
    let offsetHours: Double

    var localMidnight: JulianDay {
        JulianDay.from(year: year, month: month, day: Double(day))
            .adding(days: -offsetHours / 24.0)
    }
    /// A local clock time such as "0443" as a Julian day.
    func at(_ hhmm: String) -> JulianDay {
        let hours = Double(hhmm.prefix(2))!
        let minutes = Double(hhmm.suffix(2))!
        return localMidnight.adding(days: (hours * 60.0 + minutes) / 1440.0)
    }
    /// Local clock time of an instant, for readable failure messages.
    func clock(_ jd: JulianDay) -> String {
        let dayFraction = (jd.value - localMidnight.value) * 1440.0
        let total = Int(dayFraction.rounded())
        return String(format: "%02d:%02d", (total / 60 + 24) % 24, (total % 60 + 60) % 60)
    }
}

let berlinJune = Place(name: "Berlin 2026-06-21",
                       geographic: Coordinates.Geographic(latitude: 52.5200, longitude: 13.4050),
                       year: 2026, month: 6, day: 21, offsetHours: 2)
let berlinDecember = Place(name: "Berlin 2026-12-21",
                           geographic: Coordinates.Geographic(latitude: 52.5200, longitude: 13.4050),
                           year: 2026, month: 12, day: 21, offsetHours: 1)
let quito = Place(name: "Quito 2026-03-20",
                  geographic: Coordinates.Geographic(latitude: -0.1807, longitude: -78.4678),
                  year: 2026, month: 3, day: 20, offsetHours: -5)
let sydney = Place(name: "Sydney 2026-09-22",
                   geographic: Coordinates.Geographic(latitude: -33.8688, longitude: 151.2093),
                   year: 2026, month: 9, day: 22, offsetHours: 10)
let tromsoJune = Place(name: "Tromso 2026-06-21",
                       geographic: Coordinates.Geographic(latitude: 69.6492, longitude: 18.9553),
                       year: 2026, month: 6, day: 21, offsetHours: 2)
let tromsoDecember = Place(name: "Tromso 2026-12-21",
                           geographic: Coordinates.Geographic(latitude: 69.6492, longitude: 18.9553),
                           year: 2026, month: 12, day: 21, offsetHours: 1)

/// Published local clock times for one place and day. nil means the authority
/// reported that the event did not occur, printed as //// for a twilight limit
/// that is never crossed and as **** or ---- for a sun that never sets or never
/// rises.
struct Published {
    let astronomicalDawn: String?
    let nauticalDawn: String?
    let civilDawn: String?
    let sunrise: String?
    let solarNoon: String
    let sunset: String?
    let civilDusk: String?
    let nauticalDusk: String?
    let astronomicalDusk: String?
    /// MET Norway solar midnight, given only where it falls inside this local
    /// day. For Sydney and for Tromso in December the API reports the solar
    /// midnight of the previous local day, which is a different instant from
    /// the one this day contains, so it is not a reference for this day.
    let nadir: String?
    /// MET Norway disc centre elevation at solar noon, in degrees. Its noon and
    /// midnight values mirror each other exactly across the two solstices,
    /// which refraction would not do, so these are geometric altitudes and are
    /// compared against the unrefracted elevation.
    let noonElevation: Double
}

let tolerance = 2.0 / 1440.0   // two minutes, in days

func checkInstant(_ place: Place, _ label: String, _ got: JulianDay?, _ want: String?) {
    checks += 1
    switch (got, want) {
    case (nil, nil):
        return
    case let (got?, want?):
        let target = place.at(want)
        if abs(got.value - target.value) > tolerance {
            fail("\(place.name) \(label): got \(place.clock(got)), published \(want)")
        }
    case let (got?, nil):
        fail("\(place.name) \(label): got \(place.clock(got)), published as not occurring")
    case (nil, _):
        fail("\(place.name) \(label): got none, published \(want!)")
    }
}

func verify(_ place: Place, _ reference: Published) {
    let phases = Twilight.phases(date: place.localMidnight, place: place.geographic)

    checkInstant(place, "astronomical dawn", phases.astronomicalDawn, reference.astronomicalDawn)
    checkInstant(place, "nautical dawn", phases.nauticalDawn, reference.nauticalDawn)
    checkInstant(place, "civil dawn", phases.civilDawn, reference.civilDawn)
    checkInstant(place, "sunrise", phases.sunrise, reference.sunrise)
    checkInstant(place, "solar noon", phases.solarNoon, reference.solarNoon)
    checkInstant(place, "sunset", phases.sunset, reference.sunset)
    checkInstant(place, "civil dusk", phases.civilDusk, reference.civilDusk)
    checkInstant(place, "nautical dusk", phases.nauticalDusk, reference.nauticalDusk)
    checkInstant(place, "astronomical dusk", phases.astronomicalDusk, reference.astronomicalDusk)
    if let nadir = reference.nadir {
        checkInstant(place, "solar midnight", phases.nadir, nadir)
    }

    if let noon = phases.solarNoon {
        let elevation = SolarPositionSPA.evaluate(julianDay: noon, place: place.geographic)
            .elevationWithoutRefraction
        check("\(place.name) noon elevation", elevation, reference.noonElevation, 0.05)
    } else {
        fail("\(place.name): no solar noon")
    }

    // Ordering. Dawn runs from the darkest threshold up to the horizon and dusk
    // mirrors it, and this must hold without consulting any published value.
    let dawnSequence: [(String, JulianDay?)] = [
        ("astronomical dawn", phases.astronomicalDawn),
        ("nautical dawn", phases.nauticalDawn),
        ("civil dawn", phases.civilDawn),
        ("sunrise", phases.sunrise),
        ("solar noon", phases.solarNoon)]
    let duskSequence: [(String, JulianDay?)] = [
        ("solar noon", phases.solarNoon),
        ("sunset", phases.sunset),
        ("civil dusk", phases.civilDusk),
        ("nautical dusk", phases.nauticalDusk),
        ("astronomical dusk", phases.astronomicalDusk)]
    for sequence in [dawnSequence, duskSequence] {
        let present = sequence.compactMap { entry in entry.1.map { (entry.0, $0) } }
        for i in 1..<max(present.count, 1) {
            checkTrue("\(place.name): \(present[i - 1].0) must precede \(present[i].0)",
                      present[i - 1].1 < present[i].1)
        }
        checks += present.isEmpty ? 1 : 0
    }

    // Day length is the time above the sunrise altitude, so it must agree with
    // sunset minus sunrise whenever the day contains both.
    if let sunrise = phases.sunrise, let sunset = phases.sunset, sunrise < sunset {
        check("\(place.name) day length equals sunset minus sunrise",
              phases.dayLength, (sunset.value - sunrise.value) * 86400.0, 1.0)
    }

    // Day length plus night length is one day. Night length is counted here by
    // an independent Riemann sum over the day rather than as the complement of
    // day length, which would prove nothing.
    var nightSeconds = 0.0
    let step = 10.0
    var offset = step / 2.0
    while offset < 86400.0 {
        let jd = place.localMidnight.adding(seconds: offset)
        let altitude = SolarPositionSPA.evaluate(julianDay: jd, place: place.geographic)
            .elevationWithoutRefraction
        if altitude <= Refraction.sunriseAltitude { nightSeconds += step }
        offset += step
    }
    check("\(place.name) day plus night is one day",
          phases.dayLength + nightSeconds, 86400.0, 2.0 * step)

    checkTrue("\(place.name): polar day and polar night cannot both hold",
              !(phases.polarDay && phases.polarNight))
}

// USNO year tables at the local offset, USNO one day API for upper transit,
// MET Norway for solar midnight and the noon elevation. Berlin has no
// astronomical twilight in June: the sun bottoms out at -14 degrees.
verify(berlinJune, Published(
    astronomicalDawn: nil, nauticalDawn: "0229", civilDawn: "0353", sunrise: "0443",
    solarNoon: "1308", sunset: "2133", civilDusk: "2224", nauticalDusk: "2347",
    astronomicalDusk: nil, nadir: "0108", noonElevation: 60.92))

verify(berlinDecember, Published(
    astronomicalDawn: "0607", nauticalDawn: "0649", civilDawn: "0733", sunrise: "0815",
    solarNoon: "1204", sunset: "1554", civilDusk: "1636", nauticalDusk: "1720",
    astronomicalDusk: "1802", nadir: "0004", noonElevation: 14.04))

verify(quito, Published(
    astronomicalDawn: "0509", nauticalDawn: "0533", civilDawn: "0557", sunrise: "0618",
    solarNoon: "1221", sunset: "1825", civilDusk: "1845", nauticalDusk: "1909",
    astronomicalDusk: "1933", nadir: "0021", noonElevation: 89.78))

verify(sydney, Published(
    astronomicalDawn: "0422", nauticalDawn: "0451", civilDawn: "0520", sunrise: "0545",
    solarNoon: "1148", sunset: "1751", civilDusk: "1816", nauticalDusk: "1845",
    astronomicalDusk: "1915", nadir: nil, noonElevation: 55.77))

// Midnight sun. USNO prints **** for the sun and //// for all three twilight
// limits, MET Norway returns null for sunrise and sunset.
verify(tromsoJune, Published(
    astronomicalDawn: nil, nauticalDawn: nil, civilDawn: nil, sunrise: nil,
    solarNoon: "1246", sunset: nil, civilDusk: nil, nauticalDusk: nil,
    astronomicalDusk: nil, nadir: "0045", noonElevation: 43.79))

// Polar night. USNO prints ---- for the sun but real times for all three
// twilights, because the sun climbs to -3 degrees at midday.
verify(tromsoDecember, Published(
    astronomicalDawn: "0628", nauticalDawn: "0747", civilDawn: "0931", sunrise: nil,
    solarNoon: "1142", sunset: nil, civilDusk: "1353", nauticalDusk: "1538",
    astronomicalDusk: "1656", nadir: nil, noonElevation: -3.09))

// The polar flags themselves.
let tromsoJunePhases = Twilight.phases(date: tromsoJune.localMidnight, place: tromsoJune.geographic)
checkTrue("Tromso June is polar day", tromsoJunePhases.polarDay)
checkTrue("Tromso June is not polar night", !tromsoJunePhases.polarNight)
check("Tromso June day length is the whole day", tromsoJunePhases.dayLength, 86400.0, 1.0)

let tromsoDecemberPhases = Twilight.phases(date: tromsoDecember.localMidnight,
                                           place: tromsoDecember.geographic)
checkTrue("Tromso December is polar night", tromsoDecemberPhases.polarNight)
checkTrue("Tromso December is not polar day", !tromsoDecemberPhases.polarDay)
check("Tromso December day length is zero", tromsoDecemberPhases.dayLength, 0.0, 1.0)

let berlinJunePhases = Twilight.phases(date: berlinJune.localMidnight, place: berlinJune.geographic)
checkTrue("Berlin in June is neither polar day nor polar night",
          !berlinJunePhases.polarDay && !berlinJunePhases.polarNight)

// At the equator on an equinox the day is twelve hours, plus the few minutes
// that refraction and the solar semidiameter add by putting sunrise at -0.8333
// degrees rather than at zero.
let quitoPhases = Twilight.phases(date: quito.localMidnight, place: quito.geographic)
check("Quito equinox day length is close to twelve hours",
      quitoPhases.dayLength / 3600.0, 12.0, 1.0 / 6.0)
checkTrue("Quito equinox day is longer than twelve hours, not shorter",
          quitoPhases.dayLength > 12.0 * 3600.0)

// Period is a partition of the altitude line.
checkTrue("period at -20", Twilight.period(solarAltitude: -20) == .night)
checkTrue("period at -18", Twilight.period(solarAltitude: -18) == .astronomicalTwilight)
checkTrue("period at -13", Twilight.period(solarAltitude: -13) == .astronomicalTwilight)
checkTrue("period at -12", Twilight.period(solarAltitude: -12) == .nauticalTwilight)
checkTrue("period at -7", Twilight.period(solarAltitude: -7) == .nauticalTwilight)
checkTrue("period at -6", Twilight.period(solarAltitude: -6) == .civilTwilight)
checkTrue("period at -5", Twilight.period(solarAltitude: -5) == .civilTwilight)
checkTrue("period at -4", Twilight.period(solarAltitude: -4) == .goldenHour)
checkTrue("period at 0", Twilight.period(solarAltitude: 0) == .goldenHour)
checkTrue("period at 6", Twilight.period(solarAltitude: 6) == .day)
checkTrue("period at 45", Twilight.period(solarAltitude: 45) == .day)

// The band predicates and the period partition must agree.
var altitude = -30.0
var partitionMismatches = 0
while altitude <= 90.0 {
    let period = Twilight.period(solarAltitude: altitude)
    if period == .goldenHour && !GoldenHour.isWithinGolden(solarAltitude: altitude) {
        partitionMismatches += 1
    }
    if (period == .civilTwilight) != GoldenHour.isWithinBlue(solarAltitude: altitude) {
        partitionMismatches += 1
    }
    if GoldenHour.isWithinGolden(solarAltitude: altitude)
        && GoldenHour.isWithinBlue(solarAltitude: altitude) {
        partitionMismatches += 1
    }
    altitude += 0.01
}
checkTrue("golden and blue predicates agree with the period partition, \(partitionMismatches) mismatches",
          partitionMismatches == 0)

checkTrue("golden band includes its lower edge", GoldenHour.isWithinGolden(solarAltitude: -4))
checkTrue("golden band includes its upper edge", GoldenHour.isWithinGolden(solarAltitude: 6))
checkTrue("golden band excludes above", !GoldenHour.isWithinGolden(solarAltitude: 6.001))
checkTrue("golden band excludes below", !GoldenHour.isWithinGolden(solarAltitude: -4.001))
checkTrue("blue band includes its lower edge", GoldenHour.isWithinBlue(solarAltitude: -6))
checkTrue("blue band hands over at its upper edge", !GoldenHour.isWithinBlue(solarAltitude: -4))
checkTrue("blue band excludes below", !GoldenHour.isWithinBlue(solarAltitude: -6.001))

// Golden and blue windows.
func elevation(_ place: Place, _ jd: JulianDay) -> Double {
    SolarPositionSPA.evaluate(julianDay: jd, place: place.geographic).elevationWithoutRefraction
}
func minutes(_ window: GoldenHour.Window) -> Double {
    (window.end.value - window.start.value) * 1440.0
}

for place in [berlinJune, berlinDecember, quito, sydney, tromsoDecember] {
    let golden = GoldenHour.golden(date: place.localMidnight, place: place.geographic)
    let blue = GoldenHour.blue(date: place.localMidnight, place: place.geographic)
    guard let goldenMorning = golden.morning, let goldenEvening = golden.evening,
          let blueMorning = blue.morning, let blueEvening = blue.evening else {
        fail("\(place.name): expected all four light windows")
        checks += 1
        continue
    }

    // Blue hour ends where golden hour begins, at the shared -4 degree edge,
    // and the same in reverse in the evening. These are the same crossing found
    // by two separate solves, so they must land on the same second.
    check("\(place.name) morning blue meets morning golden",
          (blueMorning.end.value - goldenMorning.start.value) * 86400.0, 0.0, 2.0)
    check("\(place.name) evening golden meets evening blue",
          (goldenEvening.end.value - blueEvening.start.value) * 86400.0, 0.0, 2.0)

    checkTrue("\(place.name) morning windows precede evening windows",
              blueMorning.start < goldenMorning.end && goldenMorning.end <= goldenEvening.start)

    // Every window edge that is not clipped by the day boundary sits on its
    // band edge by construction, which is checkable against the ephemeris.
    for (label, edge, want) in [
        ("morning blue start", blueMorning.start, GoldenHour.blueLowerAltitude),
        ("morning golden start", goldenMorning.start, GoldenHour.goldenLowerAltitude),
        ("evening golden end", goldenEvening.end, GoldenHour.goldenLowerAltitude),
        ("evening blue end", blueEvening.end, GoldenHour.blueLowerAltitude)
    ] {
        check("\(place.name) \(label) altitude", elevation(place, edge), want, 0.02)
    }
    // Tromso in December never reaches +6 degrees, so its golden windows are
    // bounded by solar noon rather than by the upper band edge.
    if place.name != tromsoDecember.name {
        check("\(place.name) morning golden end altitude",
              elevation(place, goldenMorning.end), GoldenHour.goldenUpperAltitude, 0.02)
        check("\(place.name) evening golden start altitude",
              elevation(place, goldenEvening.start), GoldenHour.goldenUpperAltitude, 0.02)
    }
}

// At the equator on an equinox the sun climbs vertically at fifteen degrees an
// hour, so the ten degree golden band takes forty minutes and the two degree
// blue band eight, whatever the implementation. This is the one place where the
// name "golden hour" is nearly honest.
let quitoGolden = GoldenHour.golden(date: quito.localMidnight, place: quito.geographic)
let quitoBlue = GoldenHour.blue(date: quito.localMidnight, place: quito.geographic)
check("Quito morning golden lasts ten degrees at fifteen degrees an hour",
      minutes(quitoGolden.morning!), 40.0, 2.0)
check("Quito evening golden lasts the same", minutes(quitoGolden.evening!), 40.0, 2.0)
check("Quito morning blue lasts two degrees", minutes(quitoBlue.morning!), 8.0, 1.0)
check("Quito evening blue lasts two degrees", minutes(quitoBlue.evening!), 8.0, 1.0)

// Under the midnight sun the golden band is occupied all night and the blue
// band is never occupied at all. MET Norway publishes the Tromso solar midnight
// disc centre elevation on 2026-06-21 as 3.08 degrees, which is inside the
// golden band and above the blue one, so this is a published fact about the
// place and not an artefact of the window code.
let tromsoMidnightElevation = elevation(tromsoJune, tromsoJune.at("0045"))
check("Tromso solar midnight elevation", tromsoMidnightElevation, 3.08, 0.05)
checkTrue("Tromso solar midnight sun is inside the golden band",
          GoldenHour.isWithinGolden(solarAltitude: tromsoMidnightElevation))

let tromsoGolden = GoldenHour.golden(date: tromsoJune.localMidnight, place: tromsoJune.geographic)
let tromsoBlue = GoldenHour.blue(date: tromsoJune.localMidnight, place: tromsoJune.geographic)
checkTrue("Tromso June has no blue hour",
          tromsoBlue.morning == nil && tromsoBlue.evening == nil)
guard let tromsoGoldenMorning = tromsoGolden.morning,
      let tromsoGoldenEvening = tromsoGolden.evening else {
    fail("Tromso June must have both golden windows")
    print("\(checks) checks, \(failures) failed")
    exit(1)
}
// The band is still occupied at both ends of the local day, so both windows run
// to the day boundary rather than stopping at an invented hour.
check("Tromso June morning golden starts at local midnight",
      (tromsoGoldenMorning.start.value - tromsoJune.localMidnight.value) * 86400.0, 0.0, 1.0)
check("Tromso June evening golden ends at local midnight",
      (tromsoGoldenEvening.end.value - tromsoJune.localMidnight.adding(days: 1).value) * 86400.0,
      0.0, 1.0)
checkTrue("Tromso June golden light lasts hours, not an hour, got \(minutes(tromsoGoldenMorning) + minutes(tromsoGoldenEvening)) minutes",
          minutes(tromsoGoldenMorning) + minutes(tromsoGoldenEvening) > 180.0)

// Polar night: the sun peaks at -3 degrees, inside the golden band, so the one
// band interval spans solar noon and is divided there.
let tromsoDecemberGolden = GoldenHour.golden(date: tromsoDecember.localMidnight,
                                             place: tromsoDecember.geographic)
if let morning = tromsoDecemberGolden.morning, let evening = tromsoDecemberGolden.evening,
   let noon = tromsoDecemberPhases.solarNoon {
    check("Tromso December golden windows meet at solar noon",
          (morning.end.value - noon.value) * 86400.0, 0.0, 1.0)
    check("Tromso December evening golden starts at solar noon",
          (evening.start.value - noon.value) * 86400.0, 0.0, 1.0)
} else {
    fail("Tromso December must have golden windows around its -3 degree noon")
    checks += 1
}

// The windows must never claim light the band predicate denies.
for place in [berlinJune, quito, sydney, tromsoJune, tromsoDecember] {
    let golden = GoldenHour.golden(date: place.localMidnight, place: place.geographic)
    let blue = GoldenHour.blue(date: place.localMidnight, place: place.geographic)
    for (label, window, inside) in [
        ("golden morning", golden.morning, GoldenHour.isWithinGolden),
        ("golden evening", golden.evening, GoldenHour.isWithinGolden),
        ("blue morning", blue.morning, GoldenHour.isWithinBlue),
        ("blue evening", blue.evening, GoldenHour.isWithinBlue)
    ] {
        guard let window else { continue }
        var samples = 0, outside = 0
        var fraction = 0.05
        while fraction < 1.0 {
            let jd = JulianDay(window.start.value
                               + (window.end.value - window.start.value) * fraction)
            // The blue band is half open at the top, so a sample landing exactly
            // on -4 would read as outside it. Nudge the comparison by a
            // millidegree rather than weakening the predicate.
            if !inside(elevation(place, jd) - 1e-3) { outside += 1 }
            samples += 1
            fraction += 0.05
        }
        checkTrue("\(place.name) \(label) stays inside its band, \(outside) of \(samples) outside",
                  outside == 0)
    }
}

if failures == 0 {
    print("all \(checks) checks passed")
} else {
    print("\(checks) checks, \(failures) failed")
    exit(1)
}
