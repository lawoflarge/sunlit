import SwiftUI
import SunlitCore

// MARK: - Geometry

/// A direction in the observer's sky.
struct SkyPoint: Equatable, Sendable {
    /// Degrees from true north, increasing toward east.
    var azimuth: Double
    /// Degrees above the astronomical horizon.
    var altitude: Double
}

/// A three component vector in the local geographic frame used throughout this
/// file: x to true north, y to west, z up. Right handed, which is what makes
/// the rotation matrices below the standard ones.
struct Vector3: Equatable, Sendable {
    var x: Double
    var y: Double
    var z: Double

    func dot(_ other: Vector3) -> Double { x * other.x + y * other.y + z * other.z }
}

/// Where a celestial direction lands on the screen.
///
/// # The projection
///
/// Three steps, each of which can be checked on its own.
///
/// ## 1. The body becomes a direction in the world
///
/// Azimuth runs from true north toward east, altitude up from the horizon. In
/// the north, west, up frame that is
///
///     north = cos(altitude) * cos(azimuth)
///     east  = cos(altitude) * sin(azimuth)
///     up    = sin(altitude)
///     v     = (north, -east, up)
///
/// The sun, the moon and the galactic centre are all far enough away that the
/// observer's position on the Earth changes nothing here. `SkyMoment` has
/// already applied the moon's parallax, so the direction handed in is already
/// topocentric and this step is a pure change of coordinates.
///
/// ## 2. The device becomes a set of axes in the same world
///
/// `HeadingProvider` publishes CoreMotion's attitude in the true north
/// reference frame as three Euler angles. The rotation that carries the device
/// frame into the world frame is
///
///     M = Rz(yaw) * Ry(roll) * Rx(pitch)
///
/// with the device's own axes being x to the right of the screen, y to the top
/// of the screen, and z out of the screen toward the user. Its columns are the
/// device axes written in world coordinates:
///
///     xAxis = ( cy*cr,                sy*cr,                -sr    )
///     yAxis = ( cy*sr*sp - sy*cp,     sy*sr*sp + cy*cp,      cr*sp )
///     zAxis = ( cy*sr*cp + sy*sp,     sy*sr*cp - cy*sp,      cr*cp )
///
/// Two checks fix the convention, and both come from the physical meanings
/// `HeadingProvider` documents rather than from any matrix convention.
///
/// With every angle zero the device axes are north, west and up, so the phone
/// is lying on its back with its right edge to the north. With pitch at ninety
/// degrees the y axis becomes up: the top of the phone points at the sky, which
/// is exactly what `HeadingProvider` says positive pitch means. The camera then
/// looks at the horizon, which is the posture this view is used in.
///
/// The composition is also what carries the overlay through the point where
/// Euler angles fall apart. CoreMotion's pitch cannot exceed ninety degrees, so
/// tilting the phone back to look at the zenith sends pitch down again and
/// flips roll by half a turn. Feeding both into `M` reconstructs the true
/// attitude anyway: the decomposition is ill conditioned there, the rotation it
/// describes is not. Substituting pitch of `90 - d` and roll of 180 gives a
/// camera direction `d` degrees above the horizon, which is the right answer.
///
/// Yaw is recovered by inverting `HeadingProvider`'s own published formula,
/// `bearing = -yaw + 90`, so this file agrees with the sensor layer by
/// construction rather than by a second guess at CoreMotion's sign convention.
/// The absolute bearing of the whole overlay therefore rides on that one line
/// in `HeadingProvider`, and confirming it is a device check: point the centre
/// of the frame at the sun at a known time and read the aim against the sun's
/// computed azimuth.
///
/// ## 3. The direction becomes a pixel
///
/// The back camera looks along the device's negative z axis. Its image is not
/// mirrored, so world right maps to screen right and world up to screen up:
///
///     forward = -zAxis, right = xAxis, up = yAxis
///     Xc = v . right,  Yc = v . up,  Zc = v . forward
///
/// A rectilinear lens then puts the point at
///
///     x = centre.x + f * Xc / Zc
///     y = centre.y - f * Yc / Zc
///
/// with `f` the focal length in view points from `CameraOptics`, and the sign
/// on y because screen coordinates grow downward. Anything with `Zc` at or
/// below zero is behind the camera and has no image.
struct ARProjection {

    let size: CGSize
    let focalLengthPoints: Double
    let right: Vector3
    let up: Vector3
    let forward: Vector3

    var centre: CGPoint { CGPoint(x: size.width / 2, y: size.height / 2) }

    init(
        size: CGSize,
        optics: CameraOptics,
        headingDegrees: Double,
        pitchDegrees: Double,
        rollDegrees: Double
    ) {
        self.size = size
        self.focalLengthPoints = optics.focalLengthPoints(displayedIn: size)
        let basis = Self.deviceBasis(
            headingDegrees: headingDegrees,
            pitchDegrees: pitchDegrees,
            rollDegrees: rollDegrees)
        self.right = basis.right
        self.up = basis.up
        self.forward = basis.forward
    }

    // MARK: The device basis

    /// The device's axes in world coordinates, and the camera direction with
    /// them. See the type's documentation for the derivation.
    static func deviceBasis(
        headingDegrees: Double,
        pitchDegrees: Double,
        rollDegrees: Double
    ) -> (right: Vector3, up: Vector3, forward: Vector3) {
        // The exact inverse of HeadingProvider's `bearing = -yaw + 90`, so this
        // recovers CoreMotion's own yaw whatever that constant turns out to be:
        // `90 - (-yaw + 90) = yaw`. The overlay is therefore built on the real
        // attitude and not on an interpretation of what the published heading
        // is supposed to mean.
        //
        // That distinction matters, because the two are not the same number.
        // With every angle zero the device frame coincides with the true north
        // reference frame, so the phone is flat on its back with its right edge
        // to the north and its top to the west, and `HeadingProvider` reports
        // ninety while a compass would report two hundred and seventy. Anything
        // that prints `trueHeading` as a bearing is half a turn out; this file
        // is not, because it never reads it as one.
        //
        // If that formula in `HeadingProvider` ever changes, this line changes
        // with it. It is the only place in this view that depends on it.
        let yaw = 90 - headingDegrees
        let cy = Angle.cos(yaw), sy = Angle.sin(yaw)
        let cr = Angle.cos(rollDegrees), sr = Angle.sin(rollDegrees)
        let cp = Angle.cos(pitchDegrees), sp = Angle.sin(pitchDegrees)

        let xAxis = Vector3(x: cy * cr, y: sy * cr, z: -sr)
        let yAxis = Vector3(
            x: cy * sr * sp - sy * cp,
            y: sy * sr * sp + cy * cp,
            z: cr * sp)
        let zAxis = Vector3(
            x: cy * sr * cp + sy * sp,
            y: sy * sr * cp - cy * sp,
            z: cr * cp)

        return (
            right: xAxis,
            up: yAxis,
            forward: Vector3(x: -zAxis.x, y: -zAxis.y, z: -zAxis.z))
    }

    /// Where the centre of the frame is aimed.
    ///
    /// The horizon sweep records against this, and the readout under the
    /// viewport shows it, so both come from the same maths as the overlay and
    /// cannot drift apart.
    static func cameraAim(
        headingDegrees: Double,
        pitchDegrees: Double,
        rollDegrees: Double
    ) -> SkyPoint {
        let forward = deviceBasis(
            headingDegrees: headingDegrees,
            pitchDegrees: pitchDegrees,
            rollDegrees: rollDegrees).forward
        return skyPoint(of: forward)
    }

    /// The world direction of a celestial position.
    static func direction(azimuth: Double, altitude: Double) -> Vector3 {
        let cosAltitude = Angle.cos(altitude)
        return Vector3(
            x: cosAltitude * Angle.cos(azimuth),
            y: -cosAltitude * Angle.sin(azimuth),
            z: Angle.sin(altitude))
    }

    /// The inverse: azimuth and altitude of a unit world direction.
    static func skyPoint(of direction: Vector3) -> SkyPoint {
        let horizontal = (direction.x * direction.x + direction.y * direction.y).squareRoot()
        // The y component is west, so east is its negation and the azimuth runs
        // the right way round the compass.
        let azimuth = Angle.normalized(Angle.atan2(-direction.y, direction.x))
        return SkyPoint(azimuth: azimuth, altitude: Angle.atan2(direction.z, horizontal))
    }

    // MARK: Projecting

    /// The screen point for a sky direction, or nil when it is behind the
    /// camera or so far off axis that it is no longer on the screen.
    func project(_ point: SkyPoint) -> CGPoint? {
        let v = Self.direction(azimuth: point.azimuth, altitude: point.altitude)
        let depth = v.dot(forward)
        // A direction on the camera plane projects to infinity. The cutoff is a
        // little above zero so that a curve grazing the edge of vision produces
        // a break rather than a stroke a thousand screens wide.
        guard depth > 0.02 else { return nil }
        let x = centre.x + focalLengthPoints * v.dot(right) / depth
        let y = centre.y - focalLengthPoints * v.dot(up) / depth
        guard x.isFinite, y.isFinite else { return nil }
        return CGPoint(x: x, y: y)
    }

    /// A sky curve as the runs of it that are actually in front of the camera.
    ///
    /// A path drawn straight through the whole sample list would join the last
    /// visible point on one side of the sky to the first on the other with a
    /// line across the frame, which is the classic augmented reality artefact.
    /// Breaking at every point that goes behind the lens removes it.
    func polylines(_ points: [SkyPoint]) -> [[CGPoint]] {
        guard points.count > 1 else { return [] }
        // Anything this far outside the frame is off screen in every sense, and
        // keeping it only feeds enormous coordinates to the rasteriser.
        let limit = 4 * max(size.width, size.height)
        var runs: [[CGPoint]] = []
        var current: [CGPoint] = []
        for point in points {
            guard let projected = project(point),
                  abs(projected.x - centre.x) < limit,
                  abs(projected.y - centre.y) < limit else {
                if current.count > 1 { runs.append(current) }
                current = []
                continue
            }
            current.append(projected)
        }
        if current.count > 1 { runs.append(current) }
        return runs
    }
}

// MARK: - What the overlay draws

/// One hour tick on the sun's path.
struct HourMark: Equatable, Sendable {
    var point: SkyPoint
    /// Already formatted for the place's time zone and the reader's locale, in
    /// the background pass, because a date formatter inside a draw loop that
    /// runs at the display rate is a measurable cost.
    var label: String
}

/// Everything the overlay needs, computed once per day and per instant rather
/// than per frame.
///
/// Nothing here is calculated in this file. Every value is read from
/// `DayReport`, `SkyMoment` and `MilkyWay`, which are the proven core.
struct ARScene: Equatable, Sendable {

    var sunPath: [SkyPoint] = []
    var sunHourMarks: [HourMark] = []
    var moonPath: [SkyPoint] = []

    var juneSolsticePath: [SkyPoint] = []
    var decemberSolsticePath: [SkyPoint] = []
    var equinoxPath: [SkyPoint] = []

    var galacticPlane: [SkyPoint] = []
    var galacticCentre: SkyPoint?
    /// True when the sun is below the astronomical twilight boundary the core
    /// uses as its own definition of a dark sky. The Milky Way is drawn only
    /// then, and the interface says so rather than drawing a curve over a blue
    /// sky and letting the reader believe it.
    var skyIsAstronomicallyDark: Bool = false

    var sunNow: SkyPoint = SkyPoint(azimuth: 0, altitude: 0)
    var moonNow: SkyPoint = SkyPoint(azimuth: 0, altitude: 0)
    var moonIllumination: Double = 0
    var solarAltitude: Double = 0

    /// The measured skyline, when the place has one. Empty otherwise: an
    /// assumed flat horizon is drawn as the horizon line and never as a
    /// measurement.
    var measuredSkyline: [SkyPoint] = []
    var hasMeasuredHorizon: Bool = false

    /// The flat horizon, every two degrees of azimuth.
    static let horizon: [SkyPoint] = stride(from: 0.0, through: 360.0, by: 2.0)
        .map { SkyPoint(azimuth: $0, altitude: 0) }

    /// The four cardinal points, for orientation.
    ///
    /// Their letters are looked up one literal key at a time in
    /// `cardinalLetter(forAzimuth:)`. Building a key from data would compile and
    /// would then ship the raw key, because the extractor only ever sees
    /// literals.
    static let cardinals: [SkyPoint] = [
        SkyPoint(azimuth: 0, altitude: 0),
        SkyPoint(azimuth: 90, altitude: 0),
        SkyPoint(azimuth: 180, altitude: 0),
        SkyPoint(azimuth: 270, altitude: 0)
    ]

    static func cardinalLetter(forAzimuth azimuth: Double) -> String {
        switch azimuth {
        case 90:
            return String(
                localized: "ar.cardinal.east", defaultValue: "E",
                comment: "One letter compass point for east, drawn on the horizon in the camera view")
        case 180:
            return String(
                localized: "ar.cardinal.south", defaultValue: "S",
                comment: "One letter compass point for south, drawn on the horizon in the camera view")
        case 270:
            return String(
                localized: "ar.cardinal.west", defaultValue: "W",
                comment: "One letter compass point for west, drawn on the horizon in the camera view")
        default:
            return String(
                localized: "ar.cardinal.north", defaultValue: "N",
                comment: "One letter compass point for north, drawn on the horizon in the camera view")
        }
    }
}

extension ARScene {

    /// Everything that depends on the place and the day, and on nothing else.
    ///
    /// Runs off the main actor. A `DayReport` is a couple of thousand ephemeris
    /// evaluations and there are four of them here, one for the selected day
    /// and one for each reference path, so this is tens of milliseconds and has
    /// no business on the thread that is drawing at twenty hertz. Splitting it
    /// from `applyMoment` is what keeps the scrubber and the ticking clock off
    /// this path entirely.
    ///
    /// The reference paths are computed even when the annual paths capability
    /// is locked, because a locked feature in this app shows what it would show
    /// in grey rather than vanishing, and a feature that vanishes makes the
    /// free app look broken.
    static func buildDay(place: Place, day: Date, locale: Locale) -> ARScene {
        var scene = ARScene()

        let zone = TimeZone(identifier: place.timeZoneIdentifier) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        calendar.locale = locale

        let dayStart = place.startOfLocalDay(containing: day)
        let report = DayReport.compute(date: dayStart, place: place)

        scene.sunPath = report.samples.map {
            SkyPoint(azimuth: $0.sun.azimuth, altitude: $0.sun.altitude)
        }
        scene.moonPath = report.samples.map {
            SkyPoint(azimuth: $0.moon.azimuth, altitude: $0.moon.altitude)
        }

        // One sample every five minutes, so every twelfth entry is an exact
        // local hour. Marks are kept only where the sun is near enough to the
        // horizon to be worth labelling; below that they pile up underground.
        let hourFormatter = DateFormatter()
        hourFormatter.locale = locale
        hourFormatter.timeZone = zone
        hourFormatter.setLocalizedDateFormatFromTemplate("j")
        let samplesPerHour = Int(3600 / DayReport.samplePeriodSeconds)
        for (index, sample) in report.samples.enumerated() where index % samplesPerHour == 0 {
            guard index < report.samples.count - 1 else { continue }
            guard sample.sun.altitude > -6 else { continue }
            scene.sunHourMarks.append(HourMark(
                point: SkyPoint(azimuth: sample.sun.azimuth, altitude: sample.sun.altitude),
                label: hourFormatter.string(from: sample.instant.date)))
        }

        // The reference days.
        //
        // The nominal calendar dates, not solved instants. The true solstice
        // moves within a day either side of these, and a day either side of a
        // solstice changes the sun's declination by under a hundredth of a
        // degree because the declination is at a turning point there. At the
        // equinox the day costs four tenths of a degree, which on these curves
        // is a few points on the screen. They are reference curves and are
        // labelled as the solstices and the equinox, not as a computed instant.
        let year = calendar.component(.year, from: day)
        scene.juneSolsticePath = Self.referencePath(
            year: year, month: 6, day: 21, place: place, calendar: calendar)
        scene.decemberSolsticePath = Self.referencePath(
            year: year, month: 12, day: 21, place: place, calendar: calendar)
        scene.equinoxPath = Self.referencePath(
            year: year, month: 3, day: 20, place: place, calendar: calendar)

        if let profile = place.horizonProfile, profile.isMeasured {
            scene.hasMeasuredHorizon = true
            scene.measuredSkyline = stride(from: 0.0, through: 360.0, by: 2.0).map {
                SkyPoint(azimuth: $0, altitude: profile.altitude(atAzimuth: $0))
            }
        }

        return scene
    }

    /// Everything that depends on the selected instant.
    ///
    /// One `SkyMoment`, which the core is built to answer cheaply because the
    /// time scrubber asks for one on every frame, plus the galactic plane,
    /// which is a hundred and eighty coordinate conversions sharing a single
    /// orientation. Both are small enough to run while the scrubber is moving.
    mutating func applyMoment(place: Place, instant: Date) {
        let julianDay = JulianDay(date: instant)
        let moment = SkyMoment.at(julianDay, place: place)

        sunNow = SkyPoint(azimuth: moment.sun.azimuth, altitude: moment.sun.altitude)
        moonNow = SkyPoint(azimuth: moment.moon.azimuth, altitude: moment.moon.altitude)
        moonIllumination = moment.moonPhase.illuminatedFraction
        solarAltitude = moment.sun.altitude

        galacticCentre = SkyPoint(
            azimuth: moment.galacticCentre.azimuth,
            altitude: moment.galacticCentre.altitude)
        // The core's own definition of a dark sky, not a threshold invented
        // here. Drawing the galactic plane over a blue sky would be a promise
        // the sky cannot keep.
        skyIsAstronomicallyDark = moment.sun.altitude < MilkyWay.darkSunAltitude
        galacticPlane = MilkyWay
            .galacticPlane(at: julianDay, place: place.geographic, samples: 180)
            .map { SkyPoint(azimuth: $0.azimuth, altitude: $0.altitude) }
    }

    private static func referencePath(
        year: Int, month: Int, day: Int, place: Place, calendar: Calendar
    ) -> [SkyPoint] {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        guard let noon = calendar.date(from: components) else { return [] }
        let report = DayReport.compute(
            date: place.startOfLocalDay(containing: noon), place: place)
        return report.samples.map {
            SkyPoint(azimuth: $0.sun.azimuth, altitude: $0.sun.altitude)
        }
    }
}

// MARK: - Which layers are drawn

/// What the overlay shows, and what it shows in grey.
///
/// A locked layer is drawn, dimmed and unlabelled, rather than removed. Two
/// reasons: an empty screen reads as a broken app, and the reader cannot decide
/// whether nine ninety nine is worth it if the app hides what it is selling.
struct ARLayerVisibility: Equatable {
    var sun: Bool = true
    var moon: Bool = true
    var moonLocked: Bool = false
    var annualPaths: Bool = true
    var annualPathsLocked: Bool = false
    var milkyWay: Bool = true
    var milkyWayLocked: Bool = false
    var horizon: Bool = true
    /// The whole selection is outside the free tier, so everything is dimmed.
    var selectionLocked: Bool = false
    /// The skyline being traced right now, as the runs of adjacent sectors that
    /// have actually been observed. Runs rather than one list, so that a sweep
    /// which skipped the sky behind the observer does not draw a chord straight
    /// across the gap and claim a reading that was never taken.
    var sweepTrace: [[SkyPoint]] = []
}

// MARK: - The overlay

/// The instrument layer over the camera image.
///
/// One `Canvas` rather than a stack of shapes: there are on the order of two
/// thousand points here, they all move together whenever the phone moves, and
/// a view per point would rebuild the whole hierarchy at twenty hertz.
struct SkyOverlay: View {

    let scene: ARScene
    let projection: ARProjection
    let layers: ARLayerVisibility

    @Environment(\.displayScale) private var displayScale
    @Environment(\.solarAltitude) private var solarAltitude

    /// One physical pixel, the instrument weight of the design system.
    private var hairline: Double { 1 / displayScale }
    /// Two physical pixels for the two paths this view exists to show. Over a
    /// live camera image a single pixel disappears into the sensor noise, and a
    /// line the reader cannot find is not an instrument.
    private var heavyline: Double { 2 / displayScale }

    private var dimmed: Color { SkyColors.disabled(solarAltitude: solarAltitude) }
    private var instrument: Color { SkyPalette.instrumentLine(solarAltitude: solarAltitude) }

    var body: some View {
        Canvas { context, _ in
            if layers.horizon {
                draw(ARScene.horizon, in: &context, colour: instrument, width: hairline)
                if scene.hasMeasuredHorizon {
                    draw(
                        scene.measuredSkyline, in: &context,
                        colour: SkyPalette.foreground(solarAltitude: solarAltitude),
                        width: hairline, dash: [4, 3])
                }
                drawCardinals(in: &context)
            }

            if layers.annualPaths {
                let colour = layers.annualPathsLocked || layers.selectionLocked ? dimmed : instrument
                draw(scene.juneSolsticePath, in: &context, colour: colour, width: hairline, dash: [6, 4])
                draw(scene.equinoxPath, in: &context, colour: colour, width: hairline, dash: [2, 3])
                draw(scene.decemberSolsticePath, in: &context, colour: colour, width: hairline, dash: [6, 4])
            }

            if layers.milkyWay, scene.skyIsAstronomicallyDark {
                let colour = layers.milkyWayLocked || layers.selectionLocked
                    ? dimmed : SkyColors.milkyWay
                draw(scene.galacticPlane, in: &context, colour: colour, width: heavyline)
                if let centre = scene.galacticCentre, let point = projection.project(centre) {
                    context.stroke(
                        Path(ellipseIn: CGRect(x: point.x - 9, y: point.y - 9, width: 18, height: 18)),
                        with: .color(colour), lineWidth: heavyline)
                }
            }

            if layers.moon {
                let colour = layers.moonLocked || layers.selectionLocked ? dimmed : SkyColors.moon
                draw(scene.moonPath, in: &context, colour: colour, width: heavyline)
                drawMoonMarker(in: &context, colour: colour)
            }

            if layers.sun {
                let colour = layers.selectionLocked ? dimmed : SkyColors.sun
                draw(scene.sunPath, in: &context, colour: colour, width: heavyline)
                drawHourMarks(in: &context, colour: colour)
                drawSunMarker(in: &context, colour: colour)
            }

            for run in layers.sweepTrace {
                draw(
                    run, in: &context,
                    colour: SkyPalette.foreground(solarAltitude: solarAltitude),
                    width: heavyline)
            }
        }
        // The canvas is one opaque picture to VoiceOver. The figures it stands
        // for are published as their own readouts underneath the viewport,
        // where they can be read one at a time.
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    // MARK: Pieces

    private func draw(
        _ points: [SkyPoint],
        in context: inout GraphicsContext,
        colour: Color,
        width: Double,
        dash: [CGFloat] = []
    ) {
        let runs = projection.polylines(points)
        guard !runs.isEmpty else { return }
        var path = Path()
        for run in runs {
            path.addLines(run)
        }
        context.stroke(
            path,
            with: .color(colour),
            style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: dash))
    }

    private func drawCardinals(in context: inout GraphicsContext) {
        for cardinal in ARScene.cardinals {
            guard let point = projection.project(cardinal) else { continue }
            let text = Text(ARScene.cardinalLetter(forAzimuth: cardinal.azimuth))
                .font(SunlitType.metricSmall)
                .foregroundStyle(SkyPalette.foreground(solarAltitude: solarAltitude))
            context.draw(text, at: CGPoint(x: point.x, y: point.y + 14), anchor: .center)
        }
    }

    private func drawHourMarks(in context: inout GraphicsContext, colour: Color) {
        for mark in scene.sunHourMarks {
            guard let point = projection.project(mark.point) else { continue }
            let tick = CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)
            context.stroke(Path(ellipseIn: tick), with: .color(colour), lineWidth: hairline)
            let text = Text(mark.label)
                .font(SunlitType.metricSmall)
                .foregroundStyle(colour)
            context.draw(text, at: CGPoint(x: point.x, y: point.y - 14), anchor: .center)
        }
    }

    private func drawSunMarker(in context: inout GraphicsContext, colour: Color) {
        guard let point = projection.project(scene.sunNow) else { return }
        let disc = CGRect(x: point.x - 10, y: point.y - 10, width: 20, height: 20)
        context.fill(Path(ellipseIn: disc), with: .color(colour))
        let ring = CGRect(x: point.x - 17, y: point.y - 17, width: 34, height: 34)
        context.stroke(Path(ellipseIn: ring), with: .color(colour), lineWidth: hairline)
    }

    /// The moon's disc, filled in proportion to how much of it is lit.
    ///
    /// Not a crescent: the terminator's orientation depends on the bright limb
    /// angle and on how the phone is rolled, and a crescent drawn with the horns
    /// pointing the wrong way is worse than no crescent. The fraction is the
    /// figure that decides whether the moon spoils a night photograph, and it is
    /// also printed underneath the viewport.
    private func drawMoonMarker(in context: inout GraphicsContext, colour: Color) {
        guard let point = projection.project(scene.moonNow) else { return }
        let disc = CGRect(x: point.x - 9, y: point.y - 9, width: 18, height: 18)
        context.fill(
            Path(ellipseIn: disc),
            with: .color(colour.opacity(max(0.12, min(1, scene.moonIllumination)))))
        context.stroke(Path(ellipseIn: disc), with: .color(colour), lineWidth: heavyline)
    }
}
