import SwiftUI
import SunlitCore

/// The figures for the selected instant: where the sun is, how strong the light is
/// modelled to be, and how long a shadow is.
///
/// Every value is read straight off `SkyMoment`. Nothing here computes.
///
/// Two of these five are models rather than measurements, and they carry a caption that
/// says so directly beneath them. The app takes no ultraviolet reading and owns no
/// pyranometer; presenting a modelled number as an observation is the failure that has
/// cost this portfolio a rejection before, and the caption is not decoration.
struct MetricBlock: View {

    let moment: SkyMoment

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 28) {
                MetricGroup {
                    azimuth
                    altitude
                    shadow
                }
                models
            }
            VStack(alignment: .leading, spacing: 14) {
                MetricGroup {
                    azimuth
                    altitude
                    shadow
                }
                models
            }
        }
    }

    // MARK: Geometry

    private var azimuth: some View {
        MetricReadout(
            label: SkyStrings.azimuth,
            value: Self.degrees(moment.sun.azimuth),
            unit: "\u{00B0}")
    }

    private var altitude: some View {
        MetricReadout(
            label: SkyStrings.altitude,
            value: Self.degrees(moment.sun.altitude),
            unit: "\u{00B0}")
    }

    /// The shadow of an object one unit high, which is the cotangent of the solar
    /// altitude and therefore the same ratio for every object at this instant.
    ///
    /// Below the horizon there is no number to print. The shadow there is not long, it is
    /// unbounded, so the readout says none rather than a figure or a stroke of
    /// punctuation.
    private var shadow: some View {
        Group {
            if let cast = moment.unitShadow {
                MetricReadout(
                    label: SkyStrings.shadow,
                    value: cast.ratio.formatted(.number.precision(.fractionLength(2))),
                    unit: SkyStrings.shadowUnit)
            } else {
                MetricReadout(
                    label: SkyStrings.shadow,
                    value: SkyStrings.shadowNone)
            }
        }
    }

    // MARK: The two models

    private var models: some View {
        VStack(alignment: .leading, spacing: 8) {
            MetricGroup {
                MetricReadout(
                    label: SkyStrings.uvIndex,
                    value: moment.uv.index.formatted(.number.precision(.fractionLength(1))))
                MetricReadout(
                    label: SkyStrings.irradiance,
                    value: moment.irradiance.global.formatted(.number.precision(.fractionLength(0))),
                    unit: "W/m\u{00B2}")
            }
            Text(SkyStrings.clearSkyModel)
                .font(SunlitType.caption)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(Text(SkyStrings.clearSkyModelSpoken))
        }
    }

    private static func degrees(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}
