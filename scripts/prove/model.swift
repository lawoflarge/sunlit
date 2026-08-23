import Foundation

var failures = 0, checks = 0
func check(_ label: String, _ got: Double, _ want: Double, _ tol: Double) {
    checks += 1
    if abs(got - want) > tol { print("FAIL  \(label): got \(got), want \(want)"); failures += 1 }
}
func checkTrue(_ label: String, _ ok: Bool) {
    checks += 1
    if !ok { print("FAIL  \(label)"); failures += 1 }
}

let berlin = Place(
    name: "Berlin",
    geographic: Coordinates.Geographic(latitude: 52.5200, longitude: 13.4050, elevation: 34),
    timeZoneIdentifier: "Europe/Berlin")

// Local midnight in Berlin on 21 June 2026 is 22:00 UT on 20 June.
let solstice = JulianDay.from(year: 2026, month: 6, day: 20.0 + 22.0 / 24.0)
let report = DayReport.compute(date: solstice, place: berlin)

// The aggregation must not corrupt what the modules produce. Recompute the same
// quantities directly and compare.
let direct = Twilight.phases(date: solstice, place: berlin.geographic)
check("phases sunrise matches the module",
      report.phases.sunrise?.value ?? -1, direct.sunrise?.value ?? -1, 1e-9)
check("phases sunset matches the module",
      report.phases.sunset?.value ?? -1, direct.sunset?.value ?? -1, 1e-9)
check("day length matches the module", report.dayLength, direct.dayLength, 1e-6)

// The maximum solar altitude at Berlin on the June solstice is
// 90 - 52.52 + 23.44 = 60.92 degrees, which is arithmetic, not a lookup.
check("maximum solar altitude", report.maximumSolarAltitude, 60.92, 0.2)

// Day length change is near zero at a solstice, by definition: the solstice is
// the turning point. This is a real astronomical invariant and it catches a
// sign error or an off by one day in the comparison.
let solsticeChange = report.dayLengthChange()
checkTrue("day length change is near zero at the solstice, got \(solsticeChange) s",
          abs(solsticeChange) < 12)

// Near an equinox it is at its largest. At Berlin it is roughly four minutes.
let equinoxDay = JulianDay.from(year: 2026, month: 3, day: 19.0 + 23.0 / 24.0)
let equinoxReport = DayReport.compute(date: equinoxDay, place: berlin)
let equinoxChange = equinoxReport.dayLengthChange()
checkTrue("day length change is large at the equinox, got \(equinoxChange) s",
          equinoxChange > 200 && equinoxChange < 320)

// The sampled arc must be ordered in time and must reach the transit altitude.
var ordered = true
for i in 1..<report.samples.count where report.samples[i].instant.value <= report.samples[i-1].instant.value {
    ordered = false
}
checkTrue("samples are ordered in time", ordered)
let sampledPeak = report.samples.map(\.sun.altitude).max() ?? -99
checkTrue("sampled peak reaches the reported maximum, \(sampledPeak) vs \(report.maximumSolarAltitude)",
          abs(sampledPeak - report.maximumSolarAltitude) < 0.01)
checkTrue("samples cover the whole day, got \(report.samples.count)", report.samples.count == 145)

// The moon has to actually move. A constant track would mean the moon sampling
// silently collapsed to one evaluation.
let moonAltitudes = report.samples.map(\.moon.altitude)
checkTrue("the moon moves across the day",
          (moonAltitudes.max()! - moonAltitudes.min()!) > 10)

// A measured horizon must change the answer. A profile with a 20 degree wall in
// the northeast, where the sun rises at Berlin in June, must delay sunrise.
var sectors = [Double](repeating: 0, count: 36)
for index in 3...9 { sectors[index] = 20.0 }        // azimuth 30 to 90 degrees
var walled = berlin
walled.horizonProfile = HorizonProfile(sectors: sectors)
let walledReport = DayReport.compute(date: solstice, place: walled)
checkTrue("a measured horizon is reported as measured", walledReport.hasMeasuredHorizon)
if let flatRise = report.phases.sunrise, let terrainRise = walledReport.terrain().sunrise {
    let delayMinutes = (terrainRise.value - flatRise.value) * 1440
    print(String(format: "  wall delays sunrise by %.1f minutes", delayMinutes))
    checkTrue("the wall delays sunrise, by \(delayMinutes) minutes",
              delayMinutes > 20 && delayMinutes < 240)
} else {
    print("FAIL  no terrain sunrise produced"); failures += 1
}
checkTrue("a flat place reports no obstruction", report.terrain().obstructionPeriods.isEmpty)
checkTrue("a walled place reports obstruction", !walledReport.terrain().obstructionPeriods.isEmpty)

// A SkyMoment must agree with the DayReport at the same instant.
if let noon = report.phases.solarNoon {
    let moment = SkyMoment.at(noon, place: berlin)
    check("noon altitude agrees with the day's maximum",
          moment.sun.altitude, report.maximumSolarAltitude, 0.01)
    check("noon azimuth agrees with the reported transit azimuth",
          moment.sun.azimuth, report.transitAzimuth ?? -1, 1e-6)
    checkTrue("noon is full day", moment.period == .day)
    checkTrue("noon is not golden hour", !moment.isGoldenHour)
    checkTrue("UV is flagged as a model", moment.uv.isClearSkyModel)
    checkTrue("irradiance is flagged as a model", moment.irradiance.isClearSkyModel)
    checkTrue("a shadow exists when the sun is up", moment.unitShadow != nil)
}

// Polar behaviour must survive the aggregation.
let tromso = Place(
    name: "Tromso",
    geographic: Coordinates.Geographic(latitude: 69.6492, longitude: 18.9553),
    timeZoneIdentifier: "Europe/Oslo")
let midnightSun = DayReport.compute(
    date: JulianDay.from(year: 2026, month: 6, day: 20.0 + 22.0 / 24.0), place: tromso)
checkTrue("Tromso reports polar day in June", midnightSun.phases.polarDay)
checkTrue("Tromso has no sunrise in June", midnightSun.phases.sunrise == nil)

// PERFORMANCE. The spec budget is 30 ms on an iPhone 12. This Mac runs the
// same arithmetic two to three times faster, so the honest equivalent of that
// budget here is 15 ms; anything that passes on this machine at 15 ms is inside
// 30 ms on the phone the budget was written for.
var sink = 0.0
let start = Date()
let iterations = 20
for i in 0..<iterations {
    let r = DayReport.compute(date: solstice.adding(days: Double(i)), place: berlin)
    sink += r.maximumSolarAltitude
}
let msPerReport = Date().timeIntervalSince(start) * 1000 / Double(iterations)
print(String(format: "  DayReport.compute: %.1f ms each (sink %.1f)", msPerReport, sink))
checkTrue("a day report computes in under 15 ms here, got \(msPerReport)", msPerReport < 15)

// And a SkyMoment, which the scrubber builds every frame, must be far cheaper.
let momentStart = Date()
var momentSink = 0.0
for i in 0..<2000 {
    momentSink += SkyMoment.at(solstice.adding(seconds: Double(i)), place: berlin).sun.altitude
}
let usPerMoment = Date().timeIntervalSince(momentStart) * 1_000_000 / 2000
print(String(format: "  SkyMoment.at: %.1f us each (sink %.1f)", usPerMoment, momentSink))
checkTrue("a sky moment costs under 300 us, got \(usPerMoment)", usPerMoment < 300)

if failures == 0 { print("model: all \(checks) checks passed") }
else { print("model: \(failures) FAILURES of \(checks)"); exit(1) }
