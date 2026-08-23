#if DEBUG
import SwiftUI

/// The whole design system on one screen: nine solar altitudes from below the deep night
/// floor to the zenith, each carrying the instrument layer, each reporting the contrast
/// it actually measures. If a palette edit costs legibility, this screen shows where.
struct DesignSystemGallery: View {
    private static let altitudes: [Double] = [-90, -18, -12, -6, -4, 0, 6, 30, 90]

    /// Swept once per process rather than on every body evaluation. The sweep is a few
    /// hundred thousand luminance samples and a preview reruns its body constantly.
    private static let audit = SkyContrast.audit(step: 1, illuminationSteps: 3)

    private let reference = Date()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Self.altitudes, id: \.self) { altitude in
                        column(altitude: altitude)
                    }
                }
            }
            proof
        }
    }

    private func column(altitude: Double) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Solar altitude").sunlitLabel()
                    Text(verbatim: "\(altitude.formatted(.number.precision(.fractionLength(0))))°")
                        .font(SunlitType.display)
                        .monospacedDigit()
                }

                ArcTrack(progress: arcProgress(for: altitude))
                    .frame(height: 84)

                HairlineDivider()

                MetricGroup {
                    MetricReadout(label: "Azimuth", value: "184.6", unit: "°")
                    MetricReadout(label: "Altitude", value: altitude.formatted(.number.precision(.fractionLength(1))), unit: "°")
                    MetricReadout(label: "UV index", value: uvFigure(for: altitude), unit: nil)
                }

                // The caveat travels with the figure, everywhere the figure appears.
                Text("Clear sky model, not a measurement")
                    .font(SunlitType.caption)
                    .fixedSize(horizontal: false, vertical: true)

                HairlineDivider()

                VStack(alignment: .leading, spacing: 10) {
                    EventChip(
                        systemImage: "sunrise",
                        label: "Sunrise",
                        date: reference.addingTimeInterval(3600 * 5.5)
                    )
                    EventChip(
                        systemImage: "moon",
                        label: "Moonset",
                        date: reference.addingTimeInterval(3600 * 9.25),
                        tint: SkyColors.moon
                    )
                    HStack(spacing: 10) {
                        AccuracyChip(degrees: 3)
                        AccuracyChip(degrees: 12)
                    }
                }

                HairlineDivider()

                MetricReadout(
                    label: "Measured contrast",
                    value: SkyContrast.worstContrast(solarAltitude: altitude)
                        .formatted(.number.precision(.fractionLength(2))),
                    unit: "to 1",
                    valueFont: SunlitType.metricSmall
                )
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 300)
        .adaptiveSky(solarAltitude: altitude, moonIllumination: altitude < -6 ? 1 : 0)
    }

    private var proof: some View {
        let audit = Self.audit
        return VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: "Worst case over every solar altitude and moon illumination 0 to 1")
                .font(SunlitType.caption)
            Text(verbatim: "\(audit.worstRatio.formatted(.number.precision(.fractionLength(3)))) to 1 "
                + "at \(audit.solarAltitude.formatted(.number.precision(.fractionLength(2))))°, "
                + "floor \(audit.required.formatted(.number.precision(.fractionLength(1)))), "
                + "isoluminant ceiling 4.583 before quantisation")
                .font(SunlitType.metricSmall)
        }
        .foregroundStyle(SkyColors.onWarning)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(audit.passes ? SkyColors.sun : SkyColors.warning)
    }

    /// Stands in for the real day fraction so the marker moves across the gallery.
    private func arcProgress(for altitude: Double) -> Double {
        min(max((altitude + 90) / 180, 0), 1)
    }

    /// Illustrative only. The real figure comes from the clear sky model in SunlitCore.
    private func uvFigure(for altitude: Double) -> String {
        max(0, altitude / 9).formatted(.number.precision(.fractionLength(1)))
    }
}

#Preview("Adaptive Sky") {
    DesignSystemGallery()
}

#Preview("Adaptive Sky, largest text") {
    DesignSystemGallery()
        .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
