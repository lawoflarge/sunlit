import CoreLocation
import MapKit
import SwiftUI
import SunlitCore

// MARK: - Geodesy

/// Great circle arithmetic, for walking a distance along a bearing.
///
/// Nothing astronomical happens in this file. Every bearing here arrives already
/// computed, from `DayReport.sunriseAzimuth`, `DayReport.sunsetAzimuth`, or
/// `SkyMoment.moon.azimuth`. All this does is put a line on a sphere, which is
/// cartography and not ephemeris.
enum MapGeodesy {

    /// IUGG mean earth radius. The rays are direction indicators a few tens of
    /// kilometres long, so the difference between a sphere and the ellipsoid is
    /// well under a metre at the far end and invisible at every zoom the map
    /// offers.
    static let earthRadiusMetres: Double = 6_371_008.8

    static func destination(
        from origin: CLLocationCoordinate2D,
        bearingDegrees: Double,
        distanceMetres: Double
    ) -> CLLocationCoordinate2D {
        let angular = distanceMetres / earthRadiusMetres
        let bearing = bearingDegrees * .pi / 180
        let latitude = origin.latitude * .pi / 180
        let longitude = origin.longitude * .pi / 180

        let sinLatitude = sin(latitude) * cos(angular)
            + cos(latitude) * sin(angular) * cos(bearing)
        let destinationLatitude = asin(min(max(sinLatitude, -1), 1))
        let y = sin(bearing) * sin(angular) * cos(latitude)
        let x = cos(angular) - sin(latitude) * sinLatitude
        let destinationLongitude = longitude + atan2(y, x)

        return CLLocationCoordinate2D(
            latitude: destinationLatitude * 180 / .pi,
            longitude: normalisedLongitude(destinationLongitude * 180 / .pi))
    }

    /// Folds a longitude back into the range `CLLocationCoordinate2D` is defined
    /// over.
    ///
    /// A ray that starts within its own length of the 180th meridian folds here
    /// and the polyline crosses the projected map rather than the seam. That is
    /// a known limit of drawing in projected space, it affects an observer in
    /// the mid Pacific and nowhere else, and every figure in the readouts stays
    /// correct through it because none of them come from the drawing.
    static func normalisedLongitude(_ degrees: Double) -> Double {
        var value = degrees
        while value > 180 { value -= 360 }
        while value < -180 { value += 360 }
        return value
    }

    /// The ray as a sampled polyline.
    ///
    /// Sampled rather than drawn as two endpoints, because MapKit joins vertices
    /// with straight lines in projected space and a great circle is not straight
    /// there. At these lengths the difference is small; sampling costs nothing
    /// and removes the question.
    static func path(
        from origin: CLLocationCoordinate2D,
        bearingDegrees: Double,
        distanceMetres: Double,
        samples: Int = 24
    ) -> [CLLocationCoordinate2D] {
        guard distanceMetres > 0 else { return [origin, origin] }
        let steps = max(samples, 2)
        return (0...steps).map { step in
            destination(
                from: origin,
                bearingDegrees: bearingDegrees,
                distanceMetres: distanceMetres * Double(step) / Double(steps))
        }
    }
}

// MARK: - Formatting

/// The shared formatters. Every clock time on this screen is expressed in the
/// place's own zone, never the device's, unless the screen has said otherwise.
enum MapFormat {

    /// A `Date.FormatStyle` rather than a `DateFormatter`.
    ///
    /// This is called about ten times per pass of the map's body, and the body
    /// runs on every frame of a height slider drag. Allocating a `DateFormatter`
    /// costs on the order of a hundred microseconds each time; the format style
    /// is a value type over a cache Foundation keeps for us.
    static func time(_ date: Date, in zone: TimeZone) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = zone
        return date.formatted(style)
    }

    /// A bearing as whole degrees, folded so that a value that rounds to 360
    /// reads as 0 rather than as a direction that does not exist.
    static func bearingDigits(_ degrees: Double) -> String {
        var rounded = degrees.rounded()
        rounded = rounded.truncatingRemainder(dividingBy: 360)
        if rounded < 0 { rounded += 360 }
        return rounded.formatted(.number.precision(.fractionLength(0)))
    }

    static func bearingGlyph(_ degrees: Double) -> String {
        bearingDigits(degrees) + "\u{00B0}"
    }

    static func spokenBearing(_ degrees: Double) -> String {
        let figure = bearingDigits(degrees)
        return String(
            localized: "map.spokenBearing",
            defaultValue: "azimuth \(figure) degrees",
            comment: "Spoken form of a horizontal direction, as in azimuth 118 degrees. Azimuth is the app's one word for this quantity, in the Data and AR views too")
    }

    /// A coordinate as a pair of signed degrees, for naming a dropped pin.
    static func coordinate(_ coordinate: CLLocationCoordinate2D) -> String {
        let style = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(3))
        return coordinate.latitude.formatted(style) + ", " + coordinate.longitude.formatted(style)
    }
}

// MARK: - The day's bearings

/// The four fixed directions of the day, resolved once when the place or the
/// date changes.
///
/// The sun's two bearings come straight off `DayReport`. The moon's do not, so
/// they are read out of a `SkyMoment` at each event, which costs two ephemeris
/// evaluations. Doing that here, inside the same background computation that
/// builds the day, is what keeps it off the frame that drags the height slider.
struct DayBearings: Sendable {

    struct Event: Sendable {
        let bearing: Double
        let time: Date
    }

    let sunrise: Event?
    let sunset: Event?
    let moonrise: Event?
    let moonset: Event?
    /// The sun stayed above the horizon all day, so there is no rise to point at.
    let polarDay: Bool
    /// The sun stayed below it, likewise.
    let polarNight: Bool

    static func from(report: DayReport) -> DayBearings {
        func sunEvent(_ instant: JulianDay?, _ bearing: Double?) -> Event? {
            guard let instant, let bearing else { return nil }
            return Event(bearing: bearing, time: instant.date)
        }
        func moonEvent(_ instant: JulianDay?) -> Event? {
            guard let instant else { return nil }
            let moment = SkyMoment.at(instant, place: report.place)
            return Event(bearing: moment.moon.azimuth, time: instant.date)
        }
        return DayBearings(
            sunrise: sunEvent(report.phases.sunrise, report.sunriseAzimuth),
            sunset: sunEvent(report.phases.sunset, report.sunsetAzimuth),
            moonrise: moonEvent(report.moonrise),
            moonset: moonEvent(report.moonset),
            polarDay: report.phases.polarDay,
            polarNight: report.phases.polarNight)
    }
}

// MARK: - A ray

/// One direction drawn from the pin.
struct SkyRay: Identifiable {

    enum Kind: String {
        case sunrise, sunset, sunNow, moonrise, moonset

        var accent: Color {
            switch self {
            case .sunrise, .sunset, .sunNow: return SkyColors.sun
            case .moonrise, .moonset: return SkyColors.moon
            }
        }

        var symbol: String {
            switch self {
            case .sunrise: return "sunrise"
            case .sunset: return "sunset"
            case .sunNow: return "sun.max"
            case .moonrise: return "moonrise"
            case .moonset: return "moonset"
            }
        }

        var title: String {
            switch self {
            case .sunrise:
                return String(
                    localized: "map.ray.sunrise", defaultValue: "Sunrise",
                    comment: "Label on the map ray pointing at where the sun rises")
            case .sunset:
                return String(
                    localized: "map.ray.sunset", defaultValue: "Sunset",
                    comment: "Label on the map ray pointing at where the sun sets")
            case .sunNow:
                return String(
                    localized: "map.ray.sunNow", defaultValue: "Sun now",
                    comment: "Label on the map ray pointing at the sun's current direction")
            case .moonrise:
                return String(
                    localized: "map.ray.moonrise", defaultValue: "Moonrise",
                    comment: "Label on the map ray pointing at where the moon rises")
            case .moonset:
                return String(
                    localized: "map.ray.moonset", defaultValue: "Moonset",
                    comment: "Label on the map ray pointing at where the moon sets")
            }
        }
    }

    let kind: Kind
    /// What the ray is called on screen.
    ///
    /// Held rather than taken from `kind`, because the live ray is only "Sun
    /// now" on the day being lived through. On any other selected day the app
    /// shows local noon, and calling that "now" would put a name on the screen
    /// that the figure beside it does not answer to.
    let title: String
    /// Degrees from true north, increasing toward east.
    let bearing: Double
    /// When the event happens, in absolute time. Nil for the live ray, which is
    /// happening now by definition.
    let time: Date?
    let path: [CLLocationCoordinate2D]
    /// True when the reader has not bought the capability this ray belongs to.
    /// A locked ray is still drawn, faintly and dashed, because a feature that
    /// vanishes makes the free app look broken rather than free.
    let isLocked: Bool

    var id: String { kind.rawValue }

    var endCoordinate: CLLocationCoordinate2D {
        path.last ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
    }
}

enum SkyRayBuilder {

    /// Builds every ray drawn from the pin.
    ///
    /// - Parameters:
    ///   - bearings: the day's four fixed directions, or nil while the day is
    ///     still being computed.
    ///   - sunNowAzimuth: the sun's bearing at the instant the whole app is
    ///     showing, which the caller reads from `SkyMoment`.
    ///   - sunNowTitle: what to call that ray. The caller knows whether the
    ///     selected day is today; this file does not.
    ///   - lengthMetres: how far each ray runs. Sized to the visible map, so a
    ///     ray always reaches across the screen and its label stays on it.
    ///   - moonUnlocked: whether `ProCapability.moon` is available.
    static func rays(
        bearings: DayBearings?,
        sunNowAzimuth: Double,
        sunNowTitle: String,
        origin: CLLocationCoordinate2D,
        lengthMetres: Double,
        moonUnlocked: Bool
    ) -> [SkyRay] {
        var rays: [SkyRay] = []

        func append(
            _ kind: SkyRay.Kind,
            _ bearing: Double,
            _ time: Date?,
            locked: Bool,
            title: String? = nil
        ) {
            rays.append(SkyRay(
                kind: kind,
                title: title ?? kind.title,
                bearing: bearing,
                time: time,
                path: MapGeodesy.path(
                    from: origin, bearingDegrees: bearing, distanceMetres: lengthMetres),
                isLocked: locked))
        }

        if let sunrise = bearings?.sunrise {
            append(.sunrise, sunrise.bearing, sunrise.time, locked: false)
        }
        if let sunset = bearings?.sunset {
            append(.sunset, sunset.bearing, sunset.time, locked: false)
        }
        if let moonrise = bearings?.moonrise {
            append(.moonrise, moonrise.bearing, moonrise.time, locked: !moonUnlocked)
        }
        if let moonset = bearings?.moonset {
            append(.moonset, moonset.bearing, moonset.time, locked: !moonUnlocked)
        }
        append(.sunNow, sunNowAzimuth, nil, locked: false, title: sunNowTitle)
        return rays
    }
}

// MARK: - Rays on the map

/// The rays, as map content.
///
/// Each one is stroked twice. The accent colours are hue signals and nothing
/// else: measured against the skies this app paints, `#FFB020` and `#8FB8FF`
/// both reach 1.00 to 1 at their worst, and map tiles are no kinder than the
/// sky. The dark halo underneath is what makes the line a mark rather than a
/// colour, so it survives greyscale, Color Filters, and a busy satellite tile.
struct SkyRayMapContent: MapContent {

    let rays: [SkyRay]
    let timeZone: TimeZone

    @MapContentBuilder
    var body: some MapContent {
        ForEach(rays) { ray in
            MapPolyline(coordinates: ray.path)
                .stroke(Color.black.opacity(0.55), style: haloStyle(for: ray))
            MapPolyline(coordinates: ray.path)
                .stroke(ray.kind.accent.opacity(ray.isLocked ? 0.5 : 1), style: lineStyle(for: ray))
            Annotation(coordinate: ray.endCoordinate, anchor: .center) {
                RayEndLabel(ray: ray, timeZone: timeZone)
            } label: {
                Text(verbatim: "")
            }
        }
    }

    private func haloStyle(for ray: SkyRay) -> StrokeStyle {
        StrokeStyle(lineWidth: 6, lineCap: .round, dash: dash(for: ray), dashPhase: 0)
    }

    private func lineStyle(for ray: SkyRay) -> StrokeStyle {
        StrokeStyle(lineWidth: 3, lineCap: .round, dash: dash(for: ray), dashPhase: 0)
    }

    private func dash(for ray: SkyRay) -> [CGFloat] {
        if ray.isLocked { return [2, 10] }
        return ray.kind == .sunNow ? [] : [14, 7]
    }
}

/// The chip at the far end of a ray, carrying the event's time and its bearing.
///
/// A locked ray's figures are blurred rather than removed, and the blurred text
/// is taken out of the accessibility tree and replaced by a spoken statement
/// that it is locked, so a VoiceOver reader is told the same thing a sighted one
/// is shown rather than being read the value the blur is withholding.
struct RayEndLabel: View {

    let ray: SkyRay
    let timeZone: TimeZone

    var body: some View {
        VStack(spacing: 1) {
            if let time = ray.time {
                Text(MapFormat.time(time, in: timeZone))
                    .font(SunlitType.metricSmall)
                    .fontWeight(.semibold)
            } else {
                Text(ray.title)
                    .font(SunlitType.metricSmall)
                    .fontWeight(.semibold)
            }
            Text(verbatim: MapFormat.bearingGlyph(ray.bearing))
                .font(SunlitType.metricSmall)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            Capsule(style: .continuous).fill(Color.black.opacity(0.66))
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(ray.kind.accent.opacity(ray.isLocked ? 0.5 : 1), lineWidth: 1)
        }
        .blur(radius: ray.isLocked ? 4 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(ray.title))
        .accessibilityValue(Text(spokenValue))
    }

    private var spokenValue: String {
        if ray.isLocked {
            return String(
                localized: "map.ray.lockedValue",
                defaultValue: "Locked. Part of Sunlit Pro.",
                comment: "Spoken instead of the figure on a ray label drawn over the map. Deliberately the same sentence as map.ray.lockedRowValue, which is the panel row below; translate both identically")
        }
        guard let time = ray.time else { return MapFormat.spokenBearing(ray.bearing) }
        return MapFormat.time(time, in: timeZone) + ", " + MapFormat.spokenBearing(ray.bearing)
    }
}

// MARK: - Rays in the panel

/// One ray as a row of figures beneath the map.
///
/// The map carries the direction; this carries the numbers, because a bearing
/// read off a drawn line is a guess and a bearing printed in tabular figures is
/// not.
struct SkyRayRow: View {

    @Environment(\.solarAltitude) private var solarAltitude
    @ScaledMetric(relativeTo: .body) private var gap: CGFloat = 10

    let ray: SkyRay
    let timeZone: TimeZone
    /// Shown instead of a clock time on the live ray, where the altitude is the
    /// figure that means something.
    let subtitle: String?
    let onUnlock: () -> Void

    init(
        ray: SkyRay,
        timeZone: TimeZone,
        subtitle: String? = nil,
        onUnlock: @escaping () -> Void = {}
    ) {
        self.ray = ray
        self.timeZone = timeZone
        self.subtitle = subtitle
        self.onUnlock = onUnlock
    }

    var body: some View {
        // The unlock button is a sibling of the row, not an overlay on it. As an
        // overlay it was drawn on top of the very figures the blur is there to
        // show, and at the accessibility text sizes a button wide enough to read
        // covered the whole row. Stacked, nothing overlaps at any text size and
        // the button is an accessibility element in its own right rather than
        // one hung off a view that has already declared itself a leaf.
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: gap) {
                Image(systemName: ray.kind.symbol)
                    .imageScale(.medium)
                    .foregroundStyle(ray.kind.accent)
                    .accessibilityHidden(true)

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: gap) {
                        titles
                        Spacer(minLength: gap)
                        figures
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        titles
                        figures
                    }
                }
            }
            .blur(radius: ray.isLocked ? 5 : 0)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(ray.title))
            .accessibilityValue(Text(spokenValue))

            if ray.isLocked {
                Button(action: onUnlock) {
                    Label {
                        Text(String(
                            localized: "map.unlock", defaultValue: "Unlock",
                            comment: "Button that opens the Sunlit Pro purchase screen"))
                            .font(SunlitType.metricSmall)
                    } icon: {
                        Image(systemName: "lock.fill").imageScale(.small)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(
                                SkyPalette.componentBorder(solarAltitude: solarAltitude),
                                lineWidth: 1)
                    }
                    .sunlitTouchTarget()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(spokenLockLabel))
            }
        }
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ray.title).sunlitLabel()
            if let subtitle {
                Text(subtitle).font(SunlitType.metricSmall)
            } else if let time = ray.time {
                Text(MapFormat.time(time, in: timeZone))
                    .font(SunlitType.metricSmall)
                    .fontWeight(.semibold)
            }
        }
    }

    private var figures: some View {
        Text(verbatim: MapFormat.bearingGlyph(ray.bearing))
            .font(SunlitType.metric)
    }

    private var spokenValue: String {
        if ray.isLocked {
            return String(
                localized: "map.ray.lockedRowValue",
                defaultValue: "Locked. Part of Sunlit Pro.",
                comment: "Spoken value of a locked readout row in the panel. Deliberately the same sentence as map.ray.lockedValue, which is the label drawn over the map; translate both identically")
        }
        var parts: [String] = []
        if let subtitle { parts.append(subtitle) }
        else if let time = ray.time { parts.append(MapFormat.time(time, in: timeZone)) }
        parts.append(MapFormat.spokenBearing(ray.bearing))
        return parts.joined(separator: ", ")
    }

    private var spokenLockLabel: String {
        // Two sentences, so the interpolated row name never has to take an
        // article that agrees with it. Sunrise, Moonrise and Sun now all differ
        // in gender and number once the app leaves English.
        let name = ray.title
        return String(
            localized: "map.ray.unlockButton",
            defaultValue: "\(name). Unlock with Sunlit Pro.",
            comment: "Accessibility label of the unlock button on a locked readout row. The placeholder is the row name, such as Sunrise or Moonrise")
    }
}
