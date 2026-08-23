import Foundation

var failures = 0, checks = 0
func check(_ label: String, _ got: Double, _ want: Double, _ tol: Double) {
    checks += 1
    if abs(got - want) > tol || got.isNaN {
        print("FAIL  \(label): got \(got), want \(want), off by \(abs(got - want))")
        failures += 1
    }
}
func checkTrue(_ label: String, _ ok: Bool) {
    checks += 1
    if !ok { print("FAIL  \(label)"); failures += 1 }
}

// 1. Shadows. Every value below is a cotangent worked out by hand from the
//    exact triangle, not read back out of this code.

// A one metre object at 45 degrees casts a one metre shadow: the triangle is
// isosceles.
let at45 = Shadow.cast(objectHeight: 1, solarAltitude: 45, solarAzimuth: 137)
checkTrue("45 degrees casts a shadow", at45 != nil)
check("1 m at 45 degrees", at45?.length ?? -1, 1.0, 1e-12)
check("ratio at 45 degrees", at45?.ratio ?? -1, 1.0, 1e-12)

// cot(30) = sqrt(3) = 1.7320508075688772.
let at30 = Shadow.cast(objectHeight: 1, solarAltitude: 30, solarAzimuth: 0)
check("1 m at 30 degrees is sqrt 3", at30?.length ?? -1, 1.7320508075688772, 1e-9)

// cot(60) = 1 / sqrt(3) = 0.5773502691896258.
let at60 = Shadow.cast(objectHeight: 1, solarAltitude: 60, solarAzimuth: 0)
check("1 m at 60 degrees is 1 over sqrt 3", at60?.length ?? -1, 0.5773502691896258, 1e-9)

// Length is linear in height and the ratio does not know the height at all.
let tall = Shadow.cast(objectHeight: 2.5, solarAltitude: 30, solarAzimuth: 0)
check("2.5 m at 30 degrees", tall?.length ?? -1, 4.330127018922193, 1e-9)
check("ratio does not depend on height", tall?.ratio ?? -1, at30?.ratio ?? -2, 0.0)

// cot(0.1) = 572.9572133542877. A grazing sun makes a very long, still finite,
// shadow.
let grazing = Shadow.cast(objectHeight: 1, solarAltitude: 0.1, solarAzimuth: 0)
check("1 m at 0.1 degrees", grazing?.length ?? -1, 572.9572133542877, 1e-6)

// The sun in the south throws the shadow due north.
check("shadow of a sun at azimuth 180", Shadow.cast(objectHeight: 1, solarAltitude: 30, solarAzimuth: 180)?.azimuth ?? -1, 0.0, 1e-12)
check("shadow of a sun at azimuth 0", Shadow.cast(objectHeight: 1, solarAltitude: 30, solarAzimuth: 0)?.azimuth ?? -1, 180.0, 1e-12)
check("shadow of a sun at azimuth 90", Shadow.cast(objectHeight: 1, solarAltitude: 30, solarAzimuth: 90)?.azimuth ?? -1, 270.0, 1e-12)
check("shadow of a sun at azimuth 359", Shadow.cast(objectHeight: 1, solarAltitude: 30, solarAzimuth: 359)?.azimuth ?? -1, 179.0, 1e-12)

// No finite shadow at or below the horizon.
checkTrue("no shadow at altitude 0", Shadow.cast(objectHeight: 1, solarAltitude: 0, solarAzimuth: 90) == nil)
checkTrue("no shadow below the horizon", Shadow.cast(objectHeight: 1, solarAltitude: -0.5, solarAzimuth: 90) == nil)

// 2. The horizon profile.

checkTrue("36 sectors are accepted", HorizonProfile(sectors: Array(repeating: 0, count: 36)) != nil)
checkTrue("35 sectors are rejected", HorizonProfile(sectors: Array(repeating: 0, count: 35)) == nil)
checkTrue("37 sectors are rejected", HorizonProfile(sectors: Array(repeating: 0, count: 37)) == nil)
checkTrue("0 sectors are rejected", HorizonProfile(sectors: []) == nil)
checkTrue("360 sectors are rejected", HorizonProfile(sectors: Array(repeating: 0, count: 360)) == nil)

checkTrue("the flat profile is flat", HorizonProfile.flat.isFlat)
for degrees in stride(from: 0.0, to: 360.0, by: 7.0) {
    check("flat profile at \(degrees)", HorizonProfile.flat.altitude(atAzimuth: degrees), 0.0, 0.0)
}

// The wrap case. Sector 35 is centred on 350 degrees and sector 0 on 0 degrees,
// so 355 degrees is the exact midpoint of the pair that straddles north.
var wrapSectors = Array(repeating: 0.0, count: 36)
wrapSectors[35] = 10
wrapSectors[0] = 20
let wrap = HorizonProfile(sectors: wrapSectors)!
check("wrap: 350 degrees is sector 35", wrap.altitude(atAzimuth: 350), 10.0, 0.0)
check("wrap: 0 degrees is sector 0", wrap.altitude(atAzimuth: 0), 20.0, 0.0)
check("wrap: 355 degrees is exactly halfway", wrap.altitude(atAzimuth: 355), 15.0, 0.0)
check("wrap: 352.5 degrees", wrap.altitude(atAzimuth: 352.5), 12.5, 0.0)
check("wrap: 357.5 degrees", wrap.altitude(atAzimuth: 357.5), 17.5, 0.0)
check("wrap: 360 degrees is 0 degrees", wrap.altitude(atAzimuth: 360), 20.0, 0.0)
check("wrap: -5 degrees is 355 degrees", wrap.altitude(atAzimuth: -5), 15.0, 0.0)
check("wrap: -365 degrees is 355 degrees", wrap.altitude(atAzimuth: -365), 15.0, 0.0)
// East of sector 0 the profile falls back to sector 1, which is zero.
check("wrap: 5 degrees interpolates toward sector 1", wrap.altitude(atAzimuth: 5), 10.0, 0.0)
// A bearing a hair below zero normalises to 360.0 exactly, because the nearest
// double to 360 minus a rounding error is 360. The sector that lands on is 36,
// which does not exist, and the profile must hand back sector 0 rather than
// walk off the end of the array.
check("wrap: a bearing a rounding error below north", wrap.altitude(atAzimuth: -1e-16), 20.0, 0.0)
check("wrap: a bearing a rounding error below a full turn", wrap.altitude(atAzimuth: -720 - 1e-16), 20.0, 0.0)
check("Angle.normalized really does return 360 there", Angle.normalized(-1e-16), 360.0, 0.0)

// Every sector centre returns its own value, with a profile whose sectors are
// all different so a shifted index cannot pass by luck.
let rampSectors = (0..<36).map { Double($0) * 1.5 + 3.0 }
let ramp = HorizonProfile(sectors: rampSectors)!
for index in 0..<36 {
    check("sector \(index) centre", ramp.altitude(atAzimuth: Double(index) * 10.0), rampSectors[index], 1e-12)
}
// And the interpolation never leaves the bracket formed by its two sectors,
// including across north where sector 35 is 55.5 and sector 0 is 3.0.
var outOfBracket = 0
for tenth in 0..<3600 {
    let azimuth = Double(tenth) / 10.0
    let lower = Int(azimuth / 10.0)
    let upper = (lower + 1) % 36
    let low = min(rampSectors[lower], rampSectors[upper])
    let high = max(rampSectors[lower], rampSectors[upper])
    let value = ramp.altitude(atAzimuth: azimuth)
    if value < low - 1e-12 || value > high + 1e-12 { outOfBracket += 1 }
}
checkTrue("interpolation stays inside its bracket everywhere, \(outOfBracket) escapes", outOfBracket == 0)

// Recording writes the nearest sector and keeps the maximum.
var swept = HorizonProfile.flat
swept.record(azimuth: 92, altitude: 12)
check("a sweep at 92 lands in sector 9", swept.altitude(atAzimuth: 90), 12.0, 0.0)
swept.record(azimuth: 88, altitude: 7)
check("a lower reading at 88 does not lower sector 9", swept.altitude(atAzimuth: 90), 12.0, 0.0)
swept.record(azimuth: 88, altitude: 19)
check("a higher reading at 88 raises sector 9", swept.altitude(atAzimuth: 90), 19.0, 0.0)
checkTrue("a swept profile is not flat", !swept.isFlat)
// 356 is nearer to north than to 350, and 354 is nearer to 350.
var wrapSweep = HorizonProfile.flat
wrapSweep.record(azimuth: 356, altitude: 8)
check("a sweep at 356 lands in sector 0", wrapSweep.altitude(atAzimuth: 0), 8.0, 0.0)
check("a sweep at 356 does not land in sector 35", wrapSweep.altitude(atAzimuth: 350), 0.0, 0.0)
wrapSweep.record(azimuth: 354, altitude: 6)
check("a sweep at 354 lands in sector 35", wrapSweep.altitude(atAzimuth: 350), 6.0, 0.0)
check("sector index of 356", Double(HorizonProfile.sectorIndex(forAzimuth: 356)), 0.0, 0.0)
check("sector index of -4", Double(HorizonProfile.sectorIndex(forAzimuth: -4)), 0.0, 0.0)

// Codable, because a measured profile is saved with a place.
let coded = try! JSONEncoder().encode(ramp)
let decoded = try! JSONDecoder().decode(HorizonProfile.self, from: coded)
checkTrue("a profile survives a round trip", decoded == ramp)
var shortPayload = false
do {
    _ = try JSONDecoder().decode(HorizonProfile.self, from: Data(#"{"sectors":[1,2,3]}"#.utf8))
} catch { shortPayload = true }
checkTrue("a short payload fails to decode", shortPayload)

// 3. Machinery for the terrain checks.
//
//    An earlier version of this file kept its own copy of the obstruction
//    formula and presented the copy as an independent authority. It was not:
//    the copy and the module said the same thing by construction, so every
//    check that leaned on it could only ever confirm that the module agreed
//    with itself. The copy is gone. `countObstructedSeconds` now walks the
//    module's own public predicate, and it is honest about what that proves: it
//    proves the intervals `obstructionPeriods` assembles agree with the
//    instant by instant predicate, and nothing whatever about whether the
//    predicate's threshold is the right one. Section 12 is what tests the
//    threshold, against published refraction values.

func obstructed(_ jd: JulianDay, _ place: Coordinates.Geographic, _ profile: HorizonProfile) -> Bool {
    Shadow.isObstructed(jd, place: place, profile: profile)
}
/// Walks the whole day in five second steps and totals the time the predicate
/// calls obstructed. Counting cannot get a boundary subtly wrong the way a
/// solver can.
func countObstructedSeconds(_ day: JulianDay, _ place: Coordinates.Geographic, _ profile: HorizonProfile) -> Double {
    var seconds = 0.0
    let step = 5.0
    var offset = step / 2
    while offset < 86400 {
        if obstructed(day.adding(seconds: offset), place, profile) { seconds += step }
        offset += step
    }
    return seconds
}
func reportedSeconds(_ periods: [(start: JulianDay, end: JulianDay)]) -> Double {
    periods.reduce(0) { $0 + ($1.end.value - $1.start.value) * 86400 }
}
/// Structure that must hold for every list of periods: each one runs forward,
/// they are in order, and no two of them touch. Two touching periods would mean
/// one stretch of shade was reported as two.
func checkStructure(_ label: String, _ periods: [(start: JulianDay, end: JulianDay)]) {
    for period in periods {
        checkTrue("\(label): a period runs forward", period.end.value > period.start.value)
    }
    for index in 1..<max(periods.count, 1) where periods.count > 1 {
        let gap = (periods[index].start.value - periods[index - 1].end.value) * 86400
        checkTrue("\(label): period \(index) starts after the one before it ends, gap \(gap) s", gap > 0)
    }
}
func flatSunEvents(_ day: JulianDay, _ place: Coordinates.Geographic) -> RiseSet.Outcome {
    // A flat horizon solve that goes nowhere near the terrain code, driven by
    // the refracted elevation the rest of the core reports.
    RiseSet.solve(
        start: day, end: day.adding(days: 1),
        precisionSeconds: 0.25,
        altitude: { SolarPositionSPA.evaluate(julianDay: $0, place: place).elevation },
        target: { _ in Refraction.sunriseAltitude })
}
func hours(_ jd: JulianDay?, from day: JulianDay) -> Double {
    guard let jd else { return -99 }
    return (jd.value - day.value) * 24.0
}
func wall(_ altitude: Double, sectors range: ClosedRange<Int>) -> HorizonProfile {
    var values = Array(repeating: 0.0, count: 36)
    for index in range { values[index] = altitude }
    return HorizonProfile(sectors: values)!
}

// 4. The flat case against published times.
//
//    US Naval Observatory, aa.usno.navy.mil/api/rstt/oneday, fetched
//    23 August 2026. Times are Universal Time, rounded by USNO to the minute.
//      0.000 N,   0.000 E, 2026-10-15: rise 05:42, transit 11:46, set 17:49
//     52.520 N,  13.405 E, 2026-06-21: rise 02:43, transit 11:08, set 19:33

let atlantic = Coordinates.Geographic(latitude: 0, longitude: 0)
let atlanticDay = JulianDay.from(year: 2026, month: 10, day: 15.0)
let berlin = Coordinates.Geographic(latitude: 52.5200, longitude: 13.4050)
let berlinDay = JulianDay.from(year: 2026, month: 6, day: 21.0)

// One minute of tolerance for the published rounding, plus a little.
let publishedTolerance = 1.2 / 60.0

check("USNO sunrise at 0 N 0 E on 2026-10-15",
      hours(Shadow.localSunrise(date: atlanticDay, place: atlantic, profile: .flat), from: atlanticDay),
      5.7, publishedTolerance)
check("USNO sunset at 0 N 0 E on 2026-10-15",
      hours(Shadow.localSunset(date: atlanticDay, place: atlantic, profile: .flat), from: atlanticDay),
      17.816666666666666, publishedTolerance)
check("USNO sunrise at Berlin on 2026-06-21",
      hours(Shadow.localSunrise(date: berlinDay, place: berlin, profile: .flat), from: berlinDay),
      2.716666666666667, publishedTolerance)
check("USNO sunset at Berlin on 2026-06-21",
      hours(Shadow.localSunset(date: berlinDay, place: berlin, profile: .flat), from: berlinDay),
      19.55, publishedTolerance)

for (label, day, place) in [("0 N 0 E", atlanticDay, atlantic), ("Berlin", berlinDay, berlin)] {
    let reference = flatSunEvents(day, place)
    let localRise = Shadow.localSunrise(date: day, place: place, profile: .flat)
    let localSet = Shadow.localSunset(date: day, place: place, profile: .flat)
    let riseError = abs(localRise!.value - reference.firstRise!.value) * 86400
    let setError = abs(localSet!.value - reference.lastSet!.value) * 86400
    print(String(format: "  %@ flat profile versus flat horizon: rise %.4f s, set %.4f s", label, riseError, setError))
    checkTrue("\(label): flat profile sunrise matches flat sunrise within a second, off by \(riseError) s", riseError < 1.0)
    checkTrue("\(label): flat profile sunset matches flat sunset within a second, off by \(setError) s", setError < 1.0)
    checkTrue("\(label): a flat profile obstructs nothing",
              Shadow.obstructionPeriods(date: day, place: place, profile: .flat).isEmpty)
}

// 5. A twenty degree wall from azimuth 90 to 120.
//
//    At the equator in mid October the sun rises near azimuth 99 and climbs
//    almost vertically, so its bearing stays on the flat top of the wall while
//    it gains the twenty degrees it needs to clear it. That makes the delay
//    attributable to the wall's height and to nothing else.

let eastWall = wall(20, sectors: 9...12)
check("the wall is 20 degrees at 90", eastWall.altitude(atAzimuth: 90), 20.0, 0.0)
check("the wall is 20 degrees at 120", eastWall.altitude(atAzimuth: 120), 20.0, 0.0)
check("the wall has fallen away by 130", eastWall.altitude(atAzimuth: 130), 0.0, 0.0)

let flatAtlantic = flatSunEvents(atlanticDay, atlantic)
let flatRise = flatAtlantic.firstRise!
let flatSet = flatAtlantic.lastSet!

let walledRise = Shadow.localSunrise(date: atlanticDay, place: atlantic, profile: eastWall)
checkTrue("the wall does not abolish sunrise", walledRise != nil)
let delayMinutes = (walledRise!.value - flatRise.value) * 1440.0
print(String(format: "  wall of 20 degrees delays sunrise by %.2f minutes", delayMinutes))
checkTrue("the delay is positive, got \(delayMinutes) minutes", delayMinutes > 0)
checkTrue("the delay is finite and of the right order, got \(delayMinutes) minutes",
          delayMinutes > 60 && delayMinutes < 120)

// The sun at the delayed sunrise must actually be up at the wall's height. A
// solver that quietly fell back to the flat horizon would put it near zero.
let atWalledRise = SolarPositionSPA.evaluate(julianDay: walledRise!, place: atlantic)
print(String(format: "  at the delayed sunrise: altitude %.4f, azimuth %.3f",
             atWalledRise.elevationWithoutRefraction, atWalledRise.azimuth))
checkTrue("the delayed sunrise happens on the flat top of the wall, azimuth \(atWalledRise.azimuth)",
          atWalledRise.azimuth > 92 && atWalledRise.azimuth < 118)
checkTrue("the sun is near twenty degrees up, not near zero, got \(atWalledRise.elevationWithoutRefraction)",
          abs(atWalledRise.elevationWithoutRefraction - 20.0) < 1.0)
// The centre sits a little below the wall's top, because what appears over the
// wall is the upper limb. How far below is a published quantity and is settled
// in section 12; here it is only bounded, so that a solver that stopped at the
// flat horizon or overshot the wall entirely is caught.
checkTrue("the sun's centre sits just below the top of the wall, got \(atWalledRise.elevationWithoutRefraction)",
          atWalledRise.elevationWithoutRefraction < 20.0
              && atWalledRise.elevationWithoutRefraction > 19.0)

// An eastern wall cannot touch the evening.
let walledSet = Shadow.localSunset(date: atlanticDay, place: atlantic, profile: eastWall)
checkTrue("an eastern wall leaves sunset alone, off by \(abs(walledSet!.value - flatSet.value) * 86400) s",
          abs(walledSet!.value - flatSet.value) * 86400 < 1.0)

// The obstruction: one stretch, from the flat sunrise to the delayed one.
let eastPeriods = Shadow.obstructionPeriods(date: atlanticDay, place: atlantic, profile: eastWall)
checkTrue("the wall obstructs exactly one stretch, got \(eastPeriods.count)", eastPeriods.count == 1)
checkStructure("eastern wall", eastPeriods)
if let period = eastPeriods.first {
    checkTrue("the stretch starts at the flat sunrise, off by \(abs(period.start.value - flatRise.value) * 86400) s",
              abs(period.start.value - flatRise.value) * 86400 < 1.0)
    checkTrue("the stretch ends at the delayed sunrise, off by \(abs(period.end.value - walledRise!.value) * 86400) s",
              abs(period.end.value - walledRise!.value) * 86400 < 1.0)

    // Inside the stretch the sun is up and hidden; a minute outside it is not.
    var inside = 0, wrong = 0
    var instant = period.start.value + 30.0 / 86400
    while instant < period.end.value - 30.0 / 86400 {
        inside += 1
        if !obstructed(JulianDay(instant), atlantic, eastWall) { wrong += 1 }
        instant += 60.0 / 86400
    }
    checkTrue("every instant inside the stretch is obstructed, \(wrong) of \(inside) were not", wrong == 0 && inside > 30)
    checkTrue("a minute before the stretch the sun is not yet up",
              !obstructed(period.start.adding(seconds: -60), atlantic, eastWall))
    checkTrue("a minute after the stretch the sun has cleared the wall",
              !obstructed(period.end.adding(seconds: 60), atlantic, eastWall))
}

let countedEast = countObstructedSeconds(atlanticDay, atlantic, eastWall)
print(String(format: "  eastern wall: counted %.0f s, reported %.1f s", countedEast, reportedSeconds(eastPeriods)))
check("the counted shade matches the reported shade", reportedSeconds(eastPeriods), countedEast, 10.0)

// 6. A wall in the west, which must move sunset and leave sunrise alone.

let westWall = wall(20, sectors: 24...27)
let westRise = Shadow.localSunrise(date: atlanticDay, place: atlantic, profile: westWall)!
let westSet = Shadow.localSunset(date: atlanticDay, place: atlantic, profile: westWall)!
checkTrue("a western wall leaves sunrise alone, off by \(abs(westRise.value - flatRise.value) * 86400) s",
          abs(westRise.value - flatRise.value) * 86400 < 1.0)
let advanceMinutes = (flatSet.value - westSet.value) * 1440.0
print(String(format: "  wall of 20 degrees advances sunset by %.2f minutes", advanceMinutes))
checkTrue("sunset comes earlier, by \(advanceMinutes) minutes", advanceMinutes > 60 && advanceMinutes < 120)

// At the equator the sun's altitude is very nearly symmetric about transit, so a
// wall of the same height either side of the meridian must cost the same number
// of minutes at each end of the day. This holds whatever the implementation, and
// it catches a sign error that a one sided test would not.
checkTrue("the morning delay and the evening advance agree, \(delayMinutes) versus \(advanceMinutes)",
          abs(delayMinutes - advanceMinutes) < 1.5)

// 7. A spike the sun goes behind and comes back out of in mid morning, which is
//    a stretch of shade with daylight on both sides of it rather than one that
//    starts at sunrise. Berlin's bearing sweeps from 47 degrees at rise to 314
//    at set, and it crosses the band from 90 to 110 degrees while climbing from
//    31 to 44 degrees, so a spike of 45 degrees standing in that band swallows
//    the sun for part of the morning and hands it back.

let spike = wall(45, sectors: 9...11)
let flatBerlin = flatSunEvents(berlinDay, berlin)
let spikePeriods = Shadow.obstructionPeriods(date: berlinDay, place: berlin, profile: spike)
checkStructure("spike", spikePeriods)
checkTrue("the spike casts exactly one stretch of shade, got \(spikePeriods.count)", spikePeriods.count == 1)
if let period = spikePeriods.first {
    let fromRise = (period.start.value - flatBerlin.firstRise!.value) * 1440
    let toSet = (flatBerlin.lastSet!.value - period.end.value) * 1440
    print(String(format: "  spike: shade from %.1f min after sunrise, ending %.1f min before sunset", fromRise, toSet))
    checkTrue("the shade begins well after sunrise, \(fromRise) min", fromRise > 30)
    checkTrue("the shade ends well before sunset, \(toSet) min", toSet > 30)
    // Both boundaries are crossings of the spike rather than of the flat
    // horizon, so at each the shade begins or ends within a second, and the sun
    // is a long way up the sky while it happens. Stated as a flip in the
    // predicate rather than as a comparison against a restated threshold: a
    // boundary is a boundary because the answer changes across it.
    checkTrue("the shade has not begun a second before it begins",
              !obstructed(period.start.adding(seconds: -1), berlin, spike))
    checkTrue("the shade has begun a second after it begins",
              obstructed(period.start.adding(seconds: 1), berlin, spike))
    checkTrue("the shade has not ended a second before it ends",
              obstructed(period.end.adding(seconds: -1), berlin, spike))
    checkTrue("the shade has ended a second after it ends",
              !obstructed(period.end.adding(seconds: 1), berlin, spike))
    for (name, edge) in [("start", period.start), ("end", period.end)] {
        let sun = SolarPositionSPA.evaluate(julianDay: edge, place: berlin)
        checkTrue("at the \(name) of the shade the sun is high above the flat horizon, \(sun.elevationWithoutRefraction)",
                  sun.elevationWithoutRefraction > 10)
        // Nothing on this profile is taller than the spike, so whatever is
        // hiding the sun at a boundary cannot be hiding it from above 45.
        checkTrue("at the \(name) of the shade the sun is below the spike, \(sun.elevationWithoutRefraction)",
                  sun.elevationWithoutRefraction < 45.0)
    }
}
let countedSpike = countObstructedSeconds(berlinDay, berlin, spike)
print(String(format: "  spike: counted %.0f s, reported %.1f s", countedSpike, reportedSeconds(spikePeriods)))
check("the counted spike shade matches the reported shade", reportedSeconds(spikePeriods), countedSpike, 10.0)

// 8. A profile that closes the sky. Berlin's sun reaches 60.9 degrees on the
//    June solstice, so a skyline of 89 degrees is a well with no sunrise in it.

let well = HorizonProfile(sectors: Array(repeating: 89.0, count: 36))!
checkTrue("no sunrise at the bottom of a well",
          Shadow.localSunrise(date: berlinDay, place: berlin, profile: well) == nil)
checkTrue("no sunset at the bottom of a well",
          Shadow.localSunset(date: berlinDay, place: berlin, profile: well) == nil)
let wellPeriods = Shadow.obstructionPeriods(date: berlinDay, place: berlin, profile: well)
checkStructure("well", wellPeriods)
checkTrue("the well is in shade for one unbroken stretch, got \(wellPeriods.count)", wellPeriods.count == 1)
if let period = wellPeriods.first {
    checkTrue("the shade starts at the flat sunrise, off by \(abs(period.start.value - flatBerlin.firstRise!.value) * 86400) s",
              abs(period.start.value - flatBerlin.firstRise!.value) * 86400 < 1.0)
    checkTrue("the shade ends at the flat sunset, off by \(abs(period.end.value - flatBerlin.lastSet!.value) * 86400) s",
              abs(period.end.value - flatBerlin.lastSet!.value) * 86400 < 1.0)
    // USNO puts Berlin's daylight on the solstice at 02:43 to 19:33, which is
    // 60600 seconds.
    check("the shade lasts the whole published day", (period.end.value - period.start.value) * 86400, 60600.0, 90.0)
}

// 9. A horizon that is below the astronomical one, which is what an observer on
//    a summit sees. Sunrise must come earlier, not later, and there is no shade
//    to report: the flat horizon calculation was the pessimistic one here.

let summit = HorizonProfile(sectors: Array(repeating: -1.5, count: 36))!
let summitRise = Shadow.localSunrise(date: atlanticDay, place: atlantic, profile: summit)!
let summitSet = Shadow.localSunset(date: atlanticDay, place: atlantic, profile: summit)!
let earlyMinutes = (flatRise.value - summitRise.value) * 1440
print(String(format: "  a horizon depressed by 1.5 degrees brings sunrise forward by %.2f minutes", earlyMinutes))
checkTrue("a depressed horizon brings sunrise forward, by \(earlyMinutes) minutes",
          earlyMinutes > 3 && earlyMinutes < 12)
checkTrue("a depressed horizon delays sunset", summitSet.value > flatSet.value)
checkTrue("a depressed horizon casts no shade",
          Shadow.obstructionPeriods(date: atlanticDay, place: atlantic, profile: summit).isEmpty)

// 10. Above the Arctic Circle, where the sun does not cross the flat horizon at
//     all. On the June solstice at Tromso it circles between 3.1 and 43.8
//     degrees, so a ridge of 10 degrees hides it around local midnight without
//     any sunset being involved. On the December solstice nothing can be
//     obstructed, because nothing is up.

let tromso = Coordinates.Geographic(latitude: 69.6492, longitude: 18.9553)
let ridge = HorizonProfile(sectors: Array(repeating: 10.0, count: 36))!

let juneTromso = JulianDay.from(year: 2026, month: 6, day: 21.0)
let midnightSunPeriods = Shadow.obstructionPeriods(date: juneTromso, place: tromso, profile: ridge)
checkStructure("midnight sun ridge", midnightSunPeriods)
let countedTromso = countObstructedSeconds(juneTromso, tromso, ridge)
print(String(format: "  Tromso ridge: %d stretches, counted %.0f s, reported %.1f s",
             midnightSunPeriods.count, countedTromso, reportedSeconds(midnightSunPeriods)))
checkTrue("the ridge hides the midnight sun without a sunset, got \(midnightSunPeriods.count) stretches",
          midnightSunPeriods.count == 2)
check("the counted midnight shade matches the reported shade",
      reportedSeconds(midnightSunPeriods), countedTromso, 10.0)
if midnightSunPeriods.count == 2 {
    // The dip straddles the end of the Universal Time day, so one stretch runs
    // to the window's end and the next day's runs from its start.
    checkTrue("the first stretch begins at the start of the window",
              abs(midnightSunPeriods[0].start.value - juneTromso.value) * 86400 < 1.0)
    checkTrue("the last stretch ends at the end of the window",
              abs(midnightSunPeriods[1].end.value - juneTromso.adding(days: 1).value) * 86400 < 1.0)
}

let decemberTromso = JulianDay.from(year: 2026, month: 12, day: 21.0)
checkTrue("polar night has no local sunrise",
          Shadow.localSunrise(date: decemberTromso, place: tromso, profile: ridge) == nil)
checkTrue("polar night obstructs nothing, because nothing is up",
          Shadow.obstructionPeriods(date: decemberTromso, place: tromso, profile: ridge).isEmpty)

// 11. Monotonicity. A higher skyline can only take daylight away, never add it,
//     and the shade it reports must equal the daylight it removed.

var previousRise = flatRise.value
var previousSet = flatSet.value
for height in [2.0, 5.0, 10.0, 15.0, 20.0] {
    let uniform = HorizonProfile(sectors: Array(repeating: height, count: 36))!
    let rise = Shadow.localSunrise(date: atlanticDay, place: atlantic, profile: uniform)!
    let set = Shadow.localSunset(date: atlanticDay, place: atlantic, profile: uniform)!
    checkTrue("a \(height) degree skyline delays sunrise further", rise.value > previousRise)
    checkTrue("a \(height) degree skyline brings sunset further forward", set.value < previousSet)
    previousRise = rise.value
    previousSet = set.value

    let periods = Shadow.obstructionPeriods(date: atlanticDay, place: atlantic, profile: uniform)
    checkStructure("\(height) degree skyline", periods)
    let lost = ((rise.value - flatRise.value) + (flatSet.value - set.value)) * 86400
    check("a \(height) degree skyline reports the daylight it removed",
          reportedSeconds(periods), lost, 2.0)
    checkTrue("a \(height) degree skyline shades morning and evening, got \(periods.count) stretches",
              periods.count == 2)
}

// 12. The skyline target against published refraction values.
//
//     This is the check the module had no equivalent of, and it is the one that
//     caught the module being wrong. A sector holds the apparent altitude of the
//     ridge, so the sun's upper limb appears over it when the sun's apparent
//     centre sits one semidiameter lower, and the true altitude the solver works
//     in is that less the atmospheric refraction at that apparent altitude.
//     Refraction is not a constant, and the module used to behave as though it
//     were, adding the ridge to the flat -0.8333 degrees and so carrying the
//     horizon's 34 arcminutes all the way up the ridge with it.
//
//     Published values, in arcminutes against apparent altitude, from the
//     Nautical Almanac altitude correction tables, thenauticalalmanac.com,
//     Increments_and_Corrections/Altitude_Correction_Tables.pdf, fetched
//     23 August 2026:
//
//       apparent altitude   6.0   10.0   20.0   30.0   45.0
//       refraction          8.5    5.4    2.7    1.7    1.0
//
//     Wikipedia's atmospheric refraction article, fetched the same day, gives
//     the same shape from an independent source, 5.3 arcminutes at ten degrees
//     and 35.4 at the horizon, and states the conventional decomposition of the
//     standard sunrise altitude as 34 arcminutes of refraction plus 16 of solar
//     semidiameter.
//
//     Nothing below reads the module's target formula. It reads the sun's true
//     altitude at the instant the public API calls local sunrise over a uniform
//     skyline, which is the target made observable, and asks how that altitude
//     moves as the skyline is raised. Between two heights it must move by the
//     change in height less the change in published refraction. That difference
//     cancels every convention the model may be anchored to and leaves only the
//     physics. The old model moved by the change in height alone, missing by 3.1
//     arcminutes over the first pair and 0.7 over the last.

let semidiameter = 0.26667
// Skyline heights chosen so the sun's apparent centre lands exactly on a
// tabulated row, which keeps interpolation out of the reference value.
let publishedRefraction: [(skyline: Double, arcminutes: Double)] = [
    (6.0 + semidiameter, 8.5),
    (10.0 + semidiameter, 5.4),
    (20.0 + semidiameter, 2.7),
    (30.0 + semidiameter, 1.7),
    (45.0 + semidiameter, 1.0),
]

func trueAltitudeAtLocalSunrise(_ skyline: Double) -> Double {
    let profile = HorizonProfile(sectors: Array(repeating: skyline, count: 36))!
    guard let rise = Shadow.localSunrise(date: atlanticDay, place: atlantic, profile: profile) else { return .nan }
    return SolarPositionSPA.evaluate(julianDay: rise, place: atlantic).elevationWithoutRefraction
}

var targets: [Double] = []
for row in publishedRefraction {
    let target = trueAltitudeAtLocalSunrise(row.skyline)
    checkTrue("a uniform skyline of \(row.skyline) degrees still has a sunrise at the equator in October", !target.isNaN)
    targets.append(target)
}

// The solver brackets to a quarter second and the sun climbs about a quarter of
// an arcminute per second here, so each endpoint carries a few hundredths of an
// arcminute. A quarter of an arcminute of tolerance leaves room for that and
// still rejects the old model by a factor of three at its smallest error.
for index in 1..<publishedRefraction.count {
    let low = publishedRefraction[index - 1]
    let high = publishedRefraction[index]
    let expected = (high.skyline - low.skyline) - (high.arcminutes - low.arcminutes) / 60.0
    let got = targets[index] - targets[index - 1]
    print(String(format: "  skyline %5.2f to %5.2f: target moves %8.5f deg, published %8.5f deg, off by %5.2f arcmin",
                 low.skyline, high.skyline, got, expected, abs(got - expected) * 60))
    check("published refraction between skylines of \(low.skyline) and \(high.skyline) degrees",
          got, expected, 0.25 / 60.0)
}

// The absolute level, which the differences above deliberately cancel. The one
// convention this model keeps is the conventional 34 arcminutes at the horizon,
// a rounded standard rather than what any refraction formula returns just below
// the horizon. That rounding is carried unchanged up the ridge, so the gap to
// the published physics must be a small constant, the same at every height, and
// never the half degree that applying the horizon's refraction at twenty
// degrees would cost.
var gaps: [Double] = []
for (index, row) in publishedRefraction.enumerated() {
    let published = row.skyline - semidiameter - row.arcminutes / 60.0
    gaps.append((targets[index] - published) * 60.0)
}
print(String(format: "  gap to published physics, arcminutes: %@",
             gaps.map { String(format: "%.2f", $0) }.joined(separator: ", ")))
for (index, row) in publishedRefraction.enumerated() {
    checkTrue("the target at a skyline of \(row.skyline) degrees sits within ten arcminutes of published refraction, gap \(gaps[index])",
              abs(gaps[index]) < 10.0)
}
checkTrue("the gap is one constant rather than a drift, spread \(gaps.max()! - gaps.min()!) arcmin",
          gaps.max()! - gaps.min()! < 0.25)

// 13. The sweep, which is the only way a profile gets filled from the camera.
//
//     A sweep that keeps the maximum against a profile that starts at zero can
//     never record a skyline below the astronomical horizon, and the sea horizon
//     seen from a summit is exactly that. Section 9 above proves the solver
//     handles a depressed horizon; this proves the capture path can produce one.
//     The Nautical Almanac dip table, on the same fetched sheet, gives the size
//     of the case: an eye height of 20 metres puts the sea horizon 7.9
//     arcminutes down, and 48 metres puts it 12.2 arcminutes down, so a cliff
//     path or a summit is a real profile with negative sectors in it.

var summitSweep = HorizonProfile.flat
checkTrue("a profile that has never been swept is not a measurement", !summitSweep.isMeasured)
check("and no sector of it is measured", Double(summitSweep.measuredSectorCount), 0.0, 0.0)
summitSweep.record(azimuth: 180, altitude: -1.5)
check("a sweep records a horizon below the astronomical one", summitSweep.altitude(atAzimuth: 180), -1.5, 0.0)
checkTrue("and the profile is now a measurement", summitSweep.isMeasured)
check("of exactly one sector", Double(summitSweep.measuredSectorCount), 1.0, 0.0)
summitSweep.record(azimuth: 180, altitude: -2.0)
check("a later lower reading does not deepen it", summitSweep.altitude(atAzimuth: 180), -1.5, 0.0)
summitSweep.record(azimuth: 180, altitude: -1.0)
check("a later higher reading raises it", summitSweep.altitude(atAzimuth: 180), -1.0, 0.0)
check("the untouched sectors are still zero", summitSweep.altitude(atAzimuth: 0), 0.0, 0.0)

// The distinction the interface has to carry: two profiles that produce
// identical numbers, one of them a measurement and one of them an assumption.
let sweptSeaHorizon = HorizonProfile(sectors: Array(repeating: 0.0, count: 36))!
checkTrue("the assumed flat horizon is flat", HorizonProfile.flat.isFlat)
checkTrue("a swept sea horizon is flat too", sweptSeaHorizon.isFlat)
checkTrue("but only one of them is a measurement",
          !HorizonProfile.flat.isMeasured && sweptSeaHorizon.isMeasured)
checkTrue("and they compute the same sunrise",
          abs(Shadow.localSunrise(date: atlanticDay, place: atlantic, profile: sweptSeaHorizon)!.value
              - Shadow.localSunrise(date: atlanticDay, place: atlantic, profile: .flat)!.value) * 86400 < 0.5)

// The observation mask survives being saved, and a file written before it
// existed still loads, as a measurement, because somebody saved it.
let sweptCoded = try! JSONEncoder().encode(summitSweep)
let sweptDecoded = try! JSONDecoder().decode(HorizonProfile.self, from: sweptCoded)
checkTrue("a partly swept profile round trips", sweptDecoded == summitSweep)
check("and keeps its measured count", Double(sweptDecoded.measuredSectorCount), 1.0, 0.0)
let legacyPayload = "{\"sectors\":[" + Array(repeating: "0", count: 36).joined(separator: ",") + "]}"
let legacyProfile = try! JSONDecoder().decode(HorizonProfile.self, from: Data(legacyPayload.utf8))
checkTrue("a payload written without the mask loads as a measurement", legacyProfile.isMeasured)
check("of every sector", Double(legacyProfile.measuredSectorCount), 36.0, 0.0)
var badMask = false
do {
    _ = try JSONDecoder().decode(
        HorizonProfile.self,
        from: Data(("{\"sectors\":[" + Array(repeating: "0", count: 36).joined(separator: ",")
                    + "],\"observed\":[true,false]}").utf8))
} catch { badMask = true }
checkTrue("a mask of the wrong length fails to decode", badMask)

if failures == 0 { print("terrain: all \(checks) checks passed") }
else { print("terrain: \(failures) FAILURES of \(checks)"); exit(1) }
