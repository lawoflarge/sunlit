import CoreLocation
import MapKit
import SwiftUI
import SunlitCore

// MARK: - The projection

/// The shadow of an upright object of a chosen height, laid on the map at the
/// scale the map is drawn at.
///
/// The geometry is not recomputed here. `SkyMoment.unitShadow` already holds the
/// shadow of a one metre object at this instant, and every object at that
/// instant shares its ratio, so the only arithmetic in this file is a
/// multiplication and a walk along a bearing.
struct ShadowProjection {

    /// The height the reader chose, in metres.
    let heightMetres: Double
    /// Nil when the sun is at or below the horizon. The shadow there is not
    /// long, it is unbounded, and printing a number for it would be a lie.
    let lengthMetres: Double?
    /// The bearing the shadow points along, degrees from north toward east.
    let bearing: Double?
    let path: [CLLocationCoordinate2D]
    /// True when the shadow runs further than the drawn line does. Near sunrise
    /// a ten metre mast throws a shadow measured in kilometres, and a polyline
    /// that long would leave the reader looking at an empty ocean, so the line
    /// stops and the screen says that it stopped.
    let isClamped: Bool

    static let maximumDrawnMetres: Double = 50_000

    /// The range the height slider offers, in metres. A metre is a fence post,
    /// a hundred metres is a tower block, and beyond that the shadow stops being
    /// something anyone stands next to.
    static let minimumHeightMetres: Double = 1
    static let maximumHeightMetres: Double = 100

    static func make(moment: SkyMoment, heightMetres: Double) -> ShadowProjection {
        let origin = CLLocationCoordinate2D(
            latitude: moment.place.latitude, longitude: moment.place.longitude)
        guard let unit = moment.unitShadow else {
            return ShadowProjection(
                heightMetres: heightMetres,
                lengthMetres: nil,
                bearing: nil,
                path: [origin, origin],
                isClamped: false)
        }
        let length = unit.length * heightMetres
        let drawn = min(length, maximumDrawnMetres)
        return ShadowProjection(
            heightMetres: heightMetres,
            lengthMetres: length,
            bearing: unit.azimuth,
            path: MapGeodesy.path(
                from: origin, bearingDegrees: unit.azimuth, distanceMetres: drawn),
            isClamped: length > drawn)
    }

    /// The camera span that puts the whole shadow on screen, with room around it.
    var fittingSpanMetres: Double {
        guard let lengthMetres else { return 40_000 }
        return max(min(lengthMetres, Self.maximumDrawnMetres) * 2.6, 400)
    }
}

// MARK: - Formatting

enum ShadowFormat {

    /// Lengths are formatted through `MeasurementFormatter`, so a reader in a
    /// storefront that uses feet and miles gets feet and miles without this file
    /// knowing anything about it.
    private static let lengths: MeasurementFormatter = {
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .naturalScale
        formatter.unitStyle = .medium
        formatter.numberFormatter.maximumFractionDigits = 1
        return formatter
    }()

    static func length(_ metres: Double) -> String {
        lengths.string(from: Measurement(value: metres, unit: UnitLength.meters))
    }
}

// MARK: - The shadow on the map

/// The shadow as map content, drawn from the pin to where the shadow ends.
///
/// Black, not an accent. This is the one mark on the screen that is a picture of
/// the thing itself rather than a symbol for it, and it carries no hue for the
/// same reason: a shadow that reads as amber is decoration. The two strokes are
/// one line, the wider and fainter of them giving it an edge against a bright
/// satellite tile.
struct ShadowMapContent: MapContent {

    let projection: ShadowProjection

    @MapContentBuilder
    var body: some MapContent {
        if projection.lengthMetres != nil, projection.path.count > 1 {
            MapPolyline(coordinates: projection.path)
                .stroke(Color.black.opacity(0.55), style: StrokeStyle(lineWidth: 9, lineCap: .butt))
            MapPolyline(coordinates: projection.path)
                .stroke(Color.black.opacity(0.72), style: StrokeStyle(lineWidth: 6, lineCap: .butt))
            Annotation(coordinate: projection.path[projection.path.count - 1], anchor: .center) {
                ShadowEndLabel(projection: projection)
            } label: {
                Text(verbatim: "")
            }
        }
    }
}

/// The marker at the tip of the shadow.
struct ShadowEndLabel: View {

    let projection: ShadowProjection

    var body: some View {
        VStack(spacing: 1) {
            Text(text)
                .font(SunlitType.metricSmall)
                .fontWeight(.semibold)
            if projection.isClamped {
                Image(systemName: "arrow.right.to.line")
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            Capsule(style: .continuous).fill(Color.black.opacity(0.72))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(
            localized: "map.shadow.tip",
            defaultValue: "Shadow tip",
            comment: "Accessibility label of the marker at the end of the drawn shadow")))
        .accessibilityValue(Text(text))
    }

    private var text: String {
        guard let lengthMetres = projection.lengthMetres else { return "" }
        return ShadowFormat.length(lengthMetres)
    }
}

// MARK: - The height control

/// The slider that sets the object's height, and the two figures it produces.
///
/// The shadow is exact geometry on level ground, not a model, and the caption
/// says exactly that. It is the one number on this screen that is neither an
/// ephemeris result nor a clear sky estimate, and the difference is worth a
/// line of type.
struct ShadowHeightControl: View {

    @Environment(\.solarAltitude) private var solarAltitude
    @ScaledMetric(relativeTo: .body) private var rowSpacing: CGFloat = 14

    @Binding var heightMetres: Double
    let projection: ShadowProjection
    /// Moves the camera so the whole shadow is on screen. Offered only when
    /// there is a shadow to fit.
    let onFit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            VStack(alignment: .leading, spacing: 6) {
                Text(heightLabel).sunlitLabel()
                Text(ShadowFormat.length(heightMetres))
                    .font(SunlitType.metric)
                Slider(
                    value: $heightMetres,
                    in: ShadowProjection.minimumHeightMetres...ShadowProjection.maximumHeightMetres,
                    step: 0.5)
                    .tint(SkyColors.sun)
                    // The slider's own track is shorter than a fingertip. The
                    // rule is about the area a finger can land on, so the frame
                    // goes on the outside of it.
                    .frame(minHeight: SunlitLayout.minimumTouchTarget)
                    .accessibilityLabel(Text(heightLabel))
                    .accessibilityValue(Text(ShadowFormat.length(heightMetres)))
            }

            if let lengthMetres = projection.lengthMetres, let bearing = projection.bearing {
                MetricGroup {
                    MetricReadout(
                        label: lengthLabel,
                        value: ShadowFormat.length(lengthMetres))
                    MetricReadout(
                        label: bearingLabel,
                        value: MapFormat.bearingDigits(bearing),
                        unit: "\u{00B0}")
                }

                Text(groundCaption)
                    .font(SunlitType.caption)
                    .fixedSize(horizontal: false, vertical: true)

                if projection.isClamped {
                    Text(clampedCaption)
                        .font(SunlitType.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: onFit) {
                    Label {
                        Text(fitLabel).font(SunlitType.body)
                    } icon: {
                        Image(systemName: "arrow.down.left.and.arrow.up.right")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(
                                SkyPalette.componentBorder(solarAltitude: solarAltitude),
                                lineWidth: 1)
                    }
                    .sunlitTouchTarget()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(fitLabel))
            } else {
                Text(noShadowCaption)
                    .font(SunlitType.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(Text(lengthLabel))
                    .accessibilityValue(Text(noShadowCaption))
            }
        }
    }

    private var heightLabel: String {
        String(
            localized: "map.shadow.height", defaultValue: "Object height",
            comment: "Label of the slider that sets the height of the object casting the shadow")
    }

    private var lengthLabel: String {
        String(
            localized: "map.shadow.length", defaultValue: "Shadow length",
            comment: "Label of the shadow length readout")
    }

    private var bearingLabel: String {
        String(
            localized: "map.shadow.bearing", defaultValue: "Shadow bearing",
            comment: "Label of the readout giving the direction the shadow points")
    }

    private var groundCaption: String {
        String(
            localized: "map.shadow.levelGround",
            defaultValue: "Exact geometry on level ground. The map does not know what the shadow falls on, or what stands in its way.",
            comment: "Caption stating the limits of the drawn shadow")
    }

    private var clampedCaption: String {
        String(
            localized: "map.shadow.clamped",
            defaultValue: "The shadow runs further than the drawn line, which stops at 50 km. The length above is the whole of it.",
            comment: "Caption shown when the shadow is longer than the line drawn for it")
    }

    private var fitLabel: String {
        String(
            localized: "map.shadow.fit", defaultValue: "Fit shadow on map",
            comment: "Button that zooms the map until the whole shadow is visible")
    }

    private var noShadowCaption: String {
        String(
            localized: "map.shadow.none",
            defaultValue: "The sun is below the horizon at this instant, so there is no shadow to draw.",
            comment: "Shown instead of a shadow length when the sun is down")
    }
}
