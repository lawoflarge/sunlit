import XCTest
@testable import SunlitCore

/// The core's real proof lives in scripts/prove, which compiles the sources with
/// swiftc and checks nearly two thousand reference values in seconds. That is
/// deliberate: a simulator run of the same work takes minutes and has hung for a
/// full day in this portfolio.
///
/// This bundle exists so the scheme's test action has something to run and so
/// the FRAMEWORK boundary is exercised. scripts/prove concatenates the sources
/// into one module, where every symbol is visible whether or not it is public.
/// A missing `public` therefore passes there and fails only when the app tries
/// to use it. These tests import SunlitCore as a module and touch the surface
/// the app depends on, which is the one thing the fast path cannot check.
final class CoreReachabilityTests: XCTestCase {

    func testSolarPositionIsReachableAcrossTheModuleBoundary() {
        let place = Coordinates.Geographic(latitude: 52.52, longitude: 13.405, elevation: 34)
        let jd = JulianDay.from(year: 2026, month: 6, day: 21.5)
        let result = SolarPositionSPA.evaluate(julianDay: jd, place: place)
        XCTAssertGreaterThan(result.elevation, -90)
        XCTAssertLessThan(result.elevation, 90)
        XCTAssertEqual(result.zenith, 90 - result.elevation, accuracy: 1e-9)
    }

    func testDayReportIsReachableAndAgreesWithItsOwnPhases() {
        let place = Place(
            name: "Berlin",
            geographic: Coordinates.Geographic(latitude: 52.52, longitude: 13.405, elevation: 34),
            timeZoneIdentifier: "Europe/Berlin")
        let report = DayReport.compute(
            date: JulianDay.from(year: 2026, month: 6, day: 20.0 + 22.0 / 24.0),
            place: place)
        XCTAssertNotNil(report.phases.sunrise)
        XCTAssertNotNil(report.phases.sunset)
        // 90 minus the latitude plus the obliquity, which is arithmetic rather
        // than a lookup, so it cannot drift with the tables.
        XCTAssertEqual(report.maximumSolarAltitude, 60.92, accuracy: 0.2)
    }

    func testSkyMomentIsReachableAndFlagsItsModelsAsModels() {
        let place = Place(
            name: "Berlin",
            geographic: Coordinates.Geographic(latitude: 52.52, longitude: 13.405),
            timeZoneIdentifier: "Europe/Berlin")
        let moment = SkyMoment.at(JulianDay.from(year: 2026, month: 6, day: 21.5), place: place)
        XCTAssertTrue(moment.uv.isClearSkyModel)
        XCTAssertTrue(moment.irradiance.isClearSkyModel)
    }

    func testCityIndexAndTerrainTypesAreReachable() {
        XCTAssertEqual(HorizonProfile.flat.altitude(atAzimuth: 123), 0, accuracy: 1e-12)
        XCTAssertNil(Shadow.cast(objectHeight: 1, solarAltitude: -1, solarAzimuth: 180))
        let cast = Shadow.cast(objectHeight: 1, solarAltitude: 45, solarAzimuth: 180)
        XCTAssertEqual(cast?.length ?? 0, 1.0, accuracy: 1e-9)
    }
}
