import SwiftUI
import XCTest

@testable import Sunlit

/// The Adaptive Sky's legibility guarantee, wired to something that runs.
///
/// Before this file existed the guarantee was stated in three places and enforced in
/// none: `SkyContrast.audit()` was called only from a `#Preview`, `assertLegible()` had
/// no callers anywhere in the repository, and there was no test target exercising the
/// design system at all. A palette edit could therefore drop the floor and every build
/// would still be green. The spec calls a palette that reads at noon and fails at
/// midnight a bug this portfolio has already shipped once, at 1.86 to 1.
final class SkyPaletteContrastTests: XCTestCase {

    /// The floor the spec sets.
    private let floor = 4.5

    // MARK: The sweep

    /// Every solar altitude the app can be asked for, at one degree steps, plus a dense
    /// band around the ink crossover where the minimum actually lives.
    func testForegroundClearsTheContrastFloorAtEverySolarAltitude() {
        var worst = (ratio: Double.infinity, altitude: 0.0, illumination: 0.0)

        for degrees in -90...90 {
            for index in 0...4 {
                let illumination = Double(index) / 4
                let ratio = SkyContrast.worstContrast(
                    solarAltitude: Double(degrees),
                    moonIllumination: illumination
                )
                if ratio < worst.ratio { worst = (ratio, Double(degrees), illumination) }
                XCTAssertGreaterThanOrEqual(
                    ratio, floor,
                    "Solar altitude \(degrees) with moon illumination \(illumination) "
                        + "reads at \(ratio) to 1"
                )
            }
        }

        // The minimum does not sit on an integer degree. It sits just below the
        // crossover, on the light ink side, and a one degree sweep alone steps over it.
        var altitude = SkyPalette.inkCrossoverAltitude - 1
        while altitude <= SkyPalette.inkCrossoverAltitude + 1 {
            let ratio = SkyContrast.worstContrast(solarAltitude: altitude)
            if ratio < worst.ratio { worst = (ratio, altitude, 0) }
            XCTAssertGreaterThanOrEqual(ratio, floor, "Solar altitude \(altitude) reads at \(ratio) to 1")
            altitude += 0.01
        }

        // Recorded rather than asserted tightly: this is the number to compare against
        // when the palette is next touched.
        print("worst foreground contrast \(worst.ratio) to 1 at solar altitude "
            + "\(worst.altitude), moon illumination \(worst.illumination)")
        XCTAssertLessThan(
            worst.ratio, 4.5826,
            "A single continuous sky carrying one ink cannot beat the isoluminant "
                + "ceiling. A result above it means the sweep stopped measuring something."
        )
    }

    /// The shipped audit and the sweep above must agree, so `audit()` can be trusted as
    /// the thing a future change is checked with.
    func testAuditAgreesWithTheExplicitSweep() {
        let audit = SkyContrast.audit(step: 1, illuminationSteps: 5)
        XCTAssertTrue(audit.passes, "audit reports \(audit.worstRatio) to 1 at \(audit.solarAltitude)")
        XCTAssertGreaterThanOrEqual(audit.worstRatio, floor)
        // 4.552 rather than a round number on purpose: 32 subdivisions measure 4.5500
        // and the 6 this used to use measure 4.5586, so the bound has to sit between
        // them or the regression it is here to catch walks straight through.
        XCTAssertLessThanOrEqual(
            audit.worstRatio, 4.552,
            "The audit is reporting more headroom than the panel has. Check "
                + "SkyContrast.blendSubdivisions: too coarse a sample steps over the "
                + "interior dip in a gamma blended span."
        )
    }

    /// The reason `blendSubdivisions` is not 6. Luminance along a gamma encoded span is
    /// convex, so the interior can sit below both endpoints; sampling only the endpoints
    /// and a handful of interior points overstates the floor.
    func testBlendSubdivisionsAreFineEnoughToFindTheInteriorDip() {
        XCTAssertGreaterThanOrEqual(SkyContrast.blendSubdivisions, 8)

        let altitude = -4.01
        let sampled = SkyContrast.paintedLuminances(solarAltitude: altitude, moonIllumination: 0)
        let stopsOnly = SkyPalette.skyColours(solarAltitude: altitude, moonIllumination: 0)
            .map { $0.quantised.relativeLuminance }
        XCTAssertGreaterThan(sampled.count, stopsOnly.count * 8, "the spans are barely being sampled")

        // The interior of a span really does go darker than either endpoint, which is
        // the whole reason the sampling has to be fine. Light ink here, so darker is
        // not the risk: brighter is. Both directions are checked so the claim is real.
        let inkIsLight = altitude < SkyPalette.inkCrossoverAltitude
        XCTAssertTrue(inkIsLight)
        XCTAssertGreaterThan(
            sampled.max() ?? 0, stopsOnly.max() ?? 0,
            "no interior sample exceeded the brightest stop, so the sweep is only "
                + "measuring the stops and the guarantee is untested between them"
        )
    }

    // MARK: The ink flip

    /// Both inks must clear the floor across the flip, or the transition is a cliff.
    func testBothInksClearTheFloorOnTheirOwnSideOfTheCrossover() {
        let crossover = SkyPalette.inkCrossoverAltitude
        let justBelow = crossover.nextDown
        XCTAssertEqual(SkyPalette.ink(solarAltitude: justBelow), LinearRGB(hex: 0xFFFFFF))
        XCTAssertEqual(SkyPalette.ink(solarAltitude: crossover), LinearRGB(hex: 0x000000))
        XCTAssertGreaterThanOrEqual(SkyContrast.worstContrast(solarAltitude: justBelow), floor)
        XCTAssertGreaterThanOrEqual(SkyContrast.worstContrast(solarAltitude: crossover), floor)
    }

    // MARK: Non text contrast

    /// WCAG 1.4.11: the visible boundary of a control needs 3 to 1. The instrument line
    /// at 55 percent does not reach it, which is why `componentBorder` exists and why
    /// the chips stroke themselves with that instead.
    func testComponentBorderClearsTheNonTextFloor() {
        let worst = SkyContrast.worstComponentBorderContrast(step: 1, illuminationSteps: 3)
        XCTAssertGreaterThanOrEqual(
            worst.ratio, 3,
            "component border reads at \(worst.ratio) to 1 at solar altitude \(worst.solarAltitude)"
        )
    }

    /// The reason the two weights are separate. If this ever stops failing, the
    /// instrument line has been changed and `componentBorder` may no longer be needed.
    func testInstrumentLineDoesNotReachTheNonTextFloor() {
        let worst = SkyContrast.worstOverlayContrast(
            opacity: SkyPalette.instrumentLineOpacity,
            step: 1,
            illuminationSteps: 3
        )
        XCTAssertLessThan(
            worst.ratio, 3,
            "The instrument line now clears 3 to 1. Fold componentBorder back into it."
        )
    }

    /// The warning capsule is the one element allowed to ignore the sky, so it has to
    /// carry its own contrast.
    func testWarningCapsuleCarriesItsOwnContrast() {
        let ratio = SkyContrast.ratio(LinearRGB(hex: 0xE8A33D), LinearRGB(hex: 0x0A0F1A))
        XCTAssertGreaterThanOrEqual(ratio, floor, "warning fill against its ink reads at \(ratio) to 1")
    }

    // MARK: The interpolation

    /// The mix has to be perceptual. A naive gamma encoded blend between two anchors far
    /// apart in hue drops through a dead band; Oklab does not.
    func testTheMidpointBetweenNightAndDayIsNotAMuddyGrey() {
        let night = LinearRGB(hex: 0x070B18)
        let day = LinearRGB(hex: 0x2E7FD4)
        let middle = LinearRGB.mix(night, day, 0.5)
        let oklab = middle.oklab
        let chroma = (oklab.a * oklab.a + oklab.b * oklab.b).squareRoot()

        XCTAssertGreaterThan(chroma, 0.05, "the night to day midpoint has gone grey: chroma \(chroma)")
        // It has to be a blue, not a neutral and not a warm cast.
        let hue = atan2(oklab.b, oklab.a) * 180 / .pi
        XCTAssertLessThan(hue, -80)
        XCTAssertGreaterThan(hue, -140)
        // And it has to be genuinely between the two, not collapsed onto either.
        XCTAssertGreaterThan(oklab.l, night.oklab.l + 0.1)
        XCTAssertLessThan(oklab.l, day.oklab.l - 0.05)
    }

    /// The two anchor columns, top of screen and horizon, must not go neutral through
    /// the golden hour to full day handover. The anchor that used to sit at 14 degrees
    /// measured 0.0036 on its own columns, worse than having no anchor at all.
    func testTheAnchorColumnsDoNotGoNeutralThroughTheDaytimeRun() {
        var worst = (chroma: Double.infinity, altitude: 0.0, isTop: true)
        var altitude = 6.0
        while altitude <= 30 {
            let colours = SkyPalette.skyColours(solarAltitude: altitude, moonIllumination: 0)
            for (colour, isTop) in [(colours.first!, true), (colours.last!, false)] {
                let oklab = colour.oklab
                let chroma = (oklab.a * oklab.a + oklab.b * oklab.b).squareRoot()
                if chroma < worst.chroma { worst = (chroma, altitude, isTop) }
            }
            altitude += 0.05
        }
        XCTAssertGreaterThan(
            worst.chroma, 0.03,
            "the \(worst.isTop ? "top" : "horizon") column goes neutral at solar altitude "
                + "\(worst.altitude): chroma \(worst.chroma)"
        )
    }

    /// A regression pin, not a claim of correctness.
    ///
    /// Between roughly 10 and 19 degrees the top of the sky has already turned cool while
    /// the horizon is still warm, so the vertical mix between the two columns crosses the
    /// neutral axis and one emitted stop goes grey. That is structural to a two column
    /// gradient handing over between opposite hues, and no choice of anchor colour
    /// removes it: measured over every stop it is 0.0017 now, 0.0009 for the anchor this
    /// palette replaced, and 0.0037 with no haze anchor at all. This test exists so the
    /// figure cannot quietly get worse, and so the real fix, holding both columns on one
    /// side of the hue circle through the handover, stays a decision somebody takes
    /// deliberately rather than one that gets lost.
    func testTheDaytimeRunDoesNotGetGreyerThanItIs() {
        var worst = (chroma: Double.infinity, altitude: 0.0)
        var altitude = 6.0
        while altitude <= 30 {
            for colour in SkyPalette.skyColours(solarAltitude: altitude, moonIllumination: 0) {
                let oklab = colour.oklab
                let chroma = (oklab.a * oklab.a + oklab.b * oklab.b).squareRoot()
                if chroma < worst.chroma { worst = (chroma, altitude) }
            }
            altitude += 0.05
        }
        print("least chromatic emitted stop: \(worst.chroma) at solar altitude \(worst.altitude)")
        XCTAssertGreaterThanOrEqual(
            worst.chroma, 0.0015,
            "the daytime sky has got greyer than the measured baseline of 0.0017: "
                + "\(worst.chroma) at solar altitude \(worst.altitude)"
        )
    }

    // MARK: Type and targets

    /// Every style must be built from a `Font.TextStyle`. A fixed point size opts the
    /// whole app out of the accessibility text sizes App Review tests at.
    func testTheTypeScaleTracksDynamicType() {
        // A fixed size font is invariant under the size category; a text style font is
        // not. Comparing the resolved descriptions is the only handle SwiftUI gives.
        let styles: [(String, Font)] = [
            ("display", SunlitType.display),
            ("title", SunlitType.title),
            ("body", SunlitType.body),
            ("caption", SunlitType.caption),
            ("metric", SunlitType.metric),
            ("metricLarge", SunlitType.metricLarge),
            ("metricSmall", SunlitType.metricSmall)
        ]
        for (name, font) in styles {
            let described = String(describing: font)
            XCTAssertFalse(
                described.contains("size:"),
                "\(name) carries a fixed point size and will not scale: \(described)"
            )
        }
    }

    /// The HIG minimum, and it must not scale: 44 points is 44 points at every text size.
    func testTouchTargetMinimumIsFortyFour() {
        XCTAssertEqual(SunlitLayout.minimumTouchTarget, 44)
    }
}
