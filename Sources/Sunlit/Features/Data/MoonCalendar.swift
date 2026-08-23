import SwiftUI
import SunlitCore

// MARK: - Moon

/// Rise, set, phase, illumination, distance, and the next two syzygies.
///
/// Every figure is read from `DayReport` and `SkyMoment`. The only search here
/// is over the phase the core already reports: finding when a value the model
/// publishes next passes through zero and through a half is not an ephemeris,
/// and there is no core entry point for it.
struct MoonSection: View {

    let day: DataDay
    var lock: DataLock?

    @Environment(\.solarAltitude) private var solarAltitude

    @State private var syzygies: MoonSyzygies?

    private var report: DayReport { day.report }
    private var format: DataFormat { day.format }
    private var phase: MoonPosition.Phase { report.moonPhaseAtNoon }

    var body: some View {
        DataSection(title: MoonStrings.title, caption: MoonStrings.caption, lock: lock) {
            rise
            set

            HairlineDivider()

            // The crescent is a drawn shape, and a redaction does not touch a
            // shape the way it turns a figure into a bar. Behind the purchase
            // the row falls back to a phase name, which redaction does cover,
            // so the greyed section does not quietly hand over the one thing
            // the reader came to this section for.
            if lock == nil {
                phaseRow
            } else {
                DataRow(label: MoonStrings.phase, value: name(of: .waxingGibbous))
            }

            DataRow(
                label: MoonStrings.illumination,
                value: format.percent(phase.illuminatedFraction),
                spoken: format.percent(phase.illuminatedFraction))

            DataRow(
                label: MoonStrings.distance,
                value: format.number(day.noon.moonDistance, fraction: 0),
                unit: MoonStrings.kilometres,
                spoken: String(
                    localized: "data.moon.distanceSpoken",
                    defaultValue: "\(format.number(day.noon.moonDistance, fraction: 0)) kilometres",
                    comment: "Spoken form of the topocentric lunar distance"))

            HairlineDivider()

            if let syzygies {
                DataRow(
                    label: MoonStrings.nextNew,
                    value: format.dateAndTime(syzygies.nextNew) ?? MoonStrings.beyondSearch,
                    accent: SkyColors.moon)
                DataRow(
                    label: MoonStrings.nextFull,
                    value: format.dateAndTime(syzygies.nextFull) ?? MoonStrings.beyondSearch,
                    accent: SkyColors.moon)
            } else {
                DataRow(label: MoonStrings.nextNew, value: DataStrings.placeholderTime)
                DataRow(label: MoonStrings.nextFull, value: DataStrings.placeholderTime)
            }
        }
        .task(id: key) { await search() }
    }

    // MARK: Rows

    @ViewBuilder
    private var rise: some View {
        if let value = format.time(report.moonrise) {
            DataRow(label: MoonStrings.moonrise, value: value, accent: SkyColors.moon)
        } else {
            DataNote(text: absence(missingRise: true), label: MoonStrings.moonrise)
        }
    }

    @ViewBuilder
    private var set: some View {
        if let value = format.time(report.moonset) {
            DataRow(label: MoonStrings.moonset, value: value, accent: SkyColors.moon)
        } else {
            DataNote(text: absence(missingRise: false), label: MoonStrings.moonset)
        }
    }

    private var phaseRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(MoonStrings.phase).sunlitLabel()
                    Spacer(minLength: 8)
                    phaseFigure
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(MoonStrings.phase).sunlitLabel()
                    phaseFigure
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(MoonStrings.phase))
        .accessibilityValue(Text(name(of: phase.name)))
    }

    private var phaseFigure: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            MoonPhaseGlyph(
                illuminatedFraction: phase.illuminatedFraction,
                waxing: phase.cycleFraction < 0.5,
                southernHemisphere: day.report.place.latitude < 0)
            Text(name(of: phase.name))
                .font(DataType.value)
        }
    }

    /// Why there is no rise or no set. A date without a moonrise is a fact
    /// about the moon's fifty minute daily slip, not a hole in the table.
    private func absence(missingRise: Bool) -> String {
        if day.minimumMoonAltitude > 0 { return MoonStrings.alwaysUp }
        if day.maximumMoonAltitude < 0 { return MoonStrings.alwaysDown }
        return missingRise ? MoonStrings.noRiseToday : MoonStrings.noSetToday
    }

    private func name(of name: MoonPosition.Phase.Name) -> String {
        switch name {
        case .newMoon:
            return String(localized: "data.moon.new", defaultValue: "New moon", comment: "Lunar phase")
        case .waxingCrescent:
            return String(localized: "data.moon.waxingCrescent", defaultValue: "Waxing crescent", comment: "Lunar phase")
        case .firstQuarter:
            return String(localized: "data.moon.firstQuarter", defaultValue: "First quarter", comment: "Lunar phase")
        case .waxingGibbous:
            return String(localized: "data.moon.waxingGibbous", defaultValue: "Waxing gibbous", comment: "Lunar phase")
        case .fullMoon:
            return String(localized: "data.moon.full", defaultValue: "Full moon", comment: "Lunar phase")
        case .waningGibbous:
            return String(localized: "data.moon.waningGibbous", defaultValue: "Waning gibbous", comment: "Lunar phase")
        case .lastQuarter:
            return String(localized: "data.moon.lastQuarter", defaultValue: "Last quarter", comment: "Lunar phase")
        case .waningCrescent:
            return String(localized: "data.moon.waningCrescent", defaultValue: "Waning crescent", comment: "Lunar phase")
        }
    }

    // MARK: Search

    private struct Key: Equatable {
        let start: Double
        let latitude: Double
        let longitude: Double
        let locked: Bool
    }

    private var key: Key {
        Key(
            start: report.date.value,
            latitude: report.place.latitude,
            longitude: report.place.longitude,
            locked: lock != nil)
    }

    @MainActor
    private func search() async {
        guard lock == nil else {
            syzygies = nil
            return
        }
        let place = report.place
        let start = report.date
        let found = await Task.detached(priority: .utility) {
            MoonSyzygies.compute(from: start, place: place)
        }.value
        guard !Task.isCancelled else { return }
        syzygies = found
    }
}

// MARK: - Next new and full moon

/// The next two syzygies after an instant.
///
/// `SkyMoment.moonPhase.cycleFraction` runs from zero at new moon through a
/// half at full moon and back to one. New moon is where it wraps; full moon is
/// where it passes a half. Both are found by walking the value the core already
/// publishes and then bisecting the bracket. No ephemeris is recomputed here.
struct MoonSyzygies: Sendable {

    let nextNew: JulianDay?
    let nextFull: JulianDay?

    /// One synodic month plus a margin, so both events are always inside the
    /// window whatever the starting phase.
    private static let searchDays: Double = 40
    private static let stepSeconds: Double = 6 * 3600

    static func compute(from start: JulianDay, place: Place) -> MoonSyzygies {
        func fraction(_ instant: JulianDay) -> Double {
            SkyMoment.at(instant, place: place).moonPhase.cycleFraction
        }

        /// Signed distance from new moon, in cycles, on the interval minus a
        /// half to plus a half. Rises through zero exactly at new moon.
        func fromNew(_ instant: JulianDay) -> Double {
            let value = fraction(instant)
            return value > 0.5 ? value - 1 : value
        }

        /// Signed distance from full moon. Rises through zero at full moon.
        func fromFull(_ instant: JulianDay) -> Double {
            fraction(instant) - 0.5
        }

        func bisect(_ measure: (JulianDay) -> Double, lower: JulianDay, upper: JulianDay) -> JulianDay {
            var low = lower
            var high = upper
            for _ in 0..<32 {
                let middle = JulianDay((low.value + high.value) / 2)
                if measure(middle) < 0 { low = middle } else { high = middle }
            }
            return JulianDay((low.value + high.value) / 2)
        }

        var newMoon: JulianDay?
        var fullMoon: JulianDay?

        var previous = start
        var previousNew = fromNew(start)
        var previousFull = fromFull(start)

        let steps = Int(searchDays * 86400 / stepSeconds)
        for step in 1...steps {
            let instant = start.adding(seconds: Double(step) * stepSeconds)
            let currentNew = fromNew(instant)
            let currentFull = fromFull(instant)

            if newMoon == nil, previousNew < 0, currentNew >= 0 {
                newMoon = bisect(fromNew, lower: previous, upper: instant)
            }
            if fullMoon == nil, previousFull < 0, currentFull >= 0 {
                fullMoon = bisect(fromFull, lower: previous, upper: instant)
            }
            if newMoon != nil, fullMoon != nil { break }

            previous = instant
            previousNew = currentNew
            previousFull = currentFull
        }

        return MoonSyzygies(nextNew: newMoon, nextFull: fullMoon)
    }
}

// MARK: - The drawn crescent

/// The moon as it is actually lit at this instant.
///
/// The terminator is the projection of a circle seen edge on, so it is an
/// ellipse whose semi axis is the disc radius times one minus twice the
/// illuminated fraction. That single number carries new, crescent, quarter,
/// gibbous and full without a case distinction, and it is read straight from
/// the fraction the core computes.
struct MoonPhaseGlyph: View {

    let illuminatedFraction: Double
    let waxing: Bool
    /// South of the equator the lit limb appears on the other side.
    var southernHemisphere: Bool = false
    var diameter: CGFloat = 30

    @Environment(\.solarAltitude) private var solarAltitude
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    SkyPalette.instrumentLine(solarAltitude: solarAltitude),
                    lineWidth: 1 / displayScale)
            // The accent bottoms out at 1.00 to 1 against a day sky, so the lit
            // region is given an edge in the audited foreground ink. Without it
            // the crescent is a hue and disappears in greyscale.
            LitMoonShape(
                illuminatedFraction: illuminatedFraction,
                lightOnRight: waxing != southernHemisphere)
                .fill(SkyColors.moon)
                .overlay {
                    LitMoonShape(
                        illuminatedFraction: illuminatedFraction,
                        lightOnRight: waxing != southernHemisphere)
                        .stroke(
                            SkyPalette.foreground(solarAltitude: solarAltitude),
                            lineWidth: 1 / displayScale)
                }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

/// The lit region of the disc.
struct LitMoonShape: Shape {

    let illuminatedFraction: Double
    let lightOnRight: Bool

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let fraction = min(max(illuminatedFraction, 0), 1)
        // Plus one at new moon, zero at quarter, minus one at full.
        let terminator = 1 - 2 * fraction
        let side: CGFloat = lightOnRight ? 1 : -1
        let steps = 72

        var path = Path()
        for step in 0...steps {
            let angle = -Double.pi / 2 + Double.pi * Double(step) / Double(steps)
            let point = CGPoint(
                x: centre.x + side * radius * CGFloat(cos(angle)),
                y: centre.y + radius * CGFloat(sin(angle)))
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        for step in 0...steps {
            let angle = Double.pi / 2 - Double.pi * Double(step) / Double(steps)
            let point = CGPoint(
                x: centre.x + side * CGFloat(terminator) * radius * CGFloat(cos(angle)),
                y: centre.y + radius * CGFloat(sin(angle)))
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Milky Way

/// Tonight's window on the galactic centre, or the condition that removed it.
///
/// A planner that says only "not visible" is useless. The answer to twilight is
/// to wait a month, the answer to moonlight is to wait a week, and the answer
/// to a centre that never clears the horizon is to drive south, so the core
/// names the limiting factor and this table prints it.
struct MilkyWaySection: View {

    let day: DataDay
    var lock: DataLock?

    private var visibility: MilkyWay.Visibility { day.milkyWay }
    private var format: DataFormat { day.format }

    var body: some View {
        DataSection(title: MilkyWayStrings.title, caption: MilkyWayStrings.caption, lock: lock) {
            if let window = visibility.window {
                DataRow(
                    label: MilkyWayStrings.window,
                    value: format.range(window.start, window.end),
                    accent: SkyColors.milkyWay,
                    caption: String(
                        localized: "data.milkyWay.lasts",
                        defaultValue: "Lasts \(format.span((window.end.value - window.start.value) * 86400))",
                        comment: "How long the Milky Way window runs for"))

                DataRow(
                    label: MilkyWayStrings.quality,
                    value: quality(visibility.quality))

                if let best = format.time(visibility.bestMoment) {
                    DataRow(label: MilkyWayStrings.best, value: best)
                }

                DataRow(
                    label: MilkyWayStrings.bestAltitude,
                    value: format.degrees(visibility.bestAltitude) ?? "",
                    spoken: format.spokenDegrees(visibility.bestAltitude))
            } else {
                DataNote(text: limiting(visibility.limitingFactor), label: MilkyWayStrings.window)
                DataRow(
                    label: MilkyWayStrings.highestTonight,
                    value: format.degrees(visibility.bestAltitude) ?? "",
                    spoken: format.spokenDegrees(visibility.bestAltitude),
                    caption: MilkyWayStrings.highestCaption)
            }
        }
    }

    private func quality(_ quality: MilkyWay.Quality) -> String {
        switch quality {
        case .none:
            return String(localized: "data.milkyWay.quality.none", defaultValue: "No window", comment: "Milky Way visibility grade")
        case .poor:
            return String(localized: "data.milkyWay.quality.poor", defaultValue: "Poor", comment: "Milky Way visibility grade")
        case .fair:
            return String(localized: "data.milkyWay.quality.fair", defaultValue: "Fair", comment: "Milky Way visibility grade")
        case .good:
            return String(localized: "data.milkyWay.quality.good", defaultValue: "Good", comment: "Milky Way visibility grade")
        case .excellent:
            return String(localized: "data.milkyWay.quality.excellent", defaultValue: "Excellent", comment: "Milky Way visibility grade")
        }
    }

    private func limiting(_ factor: MilkyWay.LimitingFactor?) -> String {
        switch factor {
        case .galacticCentreBelowHorizon:
            return String(
                localized: "data.milkyWay.limit.belowHorizon",
                defaultValue: "The galactic centre never rises ten degrees above the horizon from this place tonight. It stands higher the further south you go.",
                comment: "Why there is no Milky Way window")
        case .twilight:
            return String(
                localized: "data.milkyWay.limit.twilight",
                defaultValue: "The sun never sinks eighteen degrees below the horizon tonight, so the sky never becomes astronomically dark. This is the northern summer case.",
                comment: "Why there is no Milky Way window")
        case .moonlight:
            return String(
                localized: "data.milkyWay.limit.moonlight",
                defaultValue: "A bright moon is above the horizon through every dark hour tonight. Wait for a thinner moon.",
                comment: "Why there is no Milky Way window")
        case .season:
            return String(
                localized: "data.milkyWay.limit.season",
                defaultValue: "The galactic centre is high, and the night is dark, but never at the same time. This is the wrong half of the year at this latitude.",
                comment: "Why there is no Milky Way window")
        case .none:
            return String(
                localized: "data.milkyWay.limit.unknown",
                defaultValue: "There is no window on the galactic centre tonight.",
                comment: "There is no window and the core named no single cause")
        }
    }
}

// MARK: - Strings

private enum MoonStrings {
    static var title: String {
        String(localized: "data.moon.title", defaultValue: "Moon", comment: "Section title")
    }
    static var caption: String {
        String(
            localized: "data.moon.caption",
            defaultValue: "Phase, illumination and distance at local noon. Rise and set include the moon's own parallax, which lifts it by nearly a degree.",
            comment: "What instant the moon figures refer to")
    }
    static var moonrise: String {
        String(localized: "data.moon.moonrise", defaultValue: "Moonrise", comment: "Moon crosses the horizon upward")
    }
    static var moonset: String {
        String(localized: "data.moon.moonset", defaultValue: "Moonset", comment: "Moon crosses the horizon downward")
    }
    static var phase: String {
        String(localized: "data.moon.phase", defaultValue: "Phase", comment: "Named lunar phase")
    }
    static var illumination: String {
        String(localized: "data.moon.illumination", defaultValue: "Illuminated", comment: "Fraction of the disc that is lit")
    }
    static var distance: String {
        String(localized: "data.moon.distance", defaultValue: "Distance", comment: "Topocentric distance to the moon")
    }
    static var kilometres: String {
        String(localized: "data.unit.kilometres", defaultValue: "km", comment: "Unit of distance")
    }
    static var nextNew: String {
        String(localized: "data.moon.nextNew", defaultValue: "Next new moon", comment: "Next new moon after the selected date")
    }
    static var nextFull: String {
        String(localized: "data.moon.nextFull", defaultValue: "Next full moon", comment: "Next full moon after the selected date")
    }
    static var beyondSearch: String {
        String(
            localized: "data.moon.beyondSearch",
            defaultValue: "Not within forty days",
            comment: "The syzygy search window found nothing, which should not happen for the moon")
    }
    static var alwaysUp: String {
        String(
            localized: "data.moon.alwaysUp",
            defaultValue: "The moon stays above the horizon for the whole date.",
            comment: "Circumpolar moon")
    }
    static var alwaysDown: String {
        String(
            localized: "data.moon.alwaysDown",
            defaultValue: "The moon stays below the horizon for the whole date.",
            comment: "The moon never rises here today")
    }
    static var noRiseToday: String {
        String(
            localized: "data.moon.noRiseToday",
            defaultValue: "The moon does not rise on this date. It rises about fifty minutes later each day, so roughly once a month a date has no moonrise in it at all.",
            comment: "A calendar day with no moonrise, which is normal")
    }
    static var noSetToday: String {
        String(
            localized: "data.moon.noSetToday",
            defaultValue: "The moon does not set on this date. It sets about fifty minutes later each day, so roughly once a month a date has no moonset in it at all.",
            comment: "A calendar day with no moonset, which is normal")
    }
}

private enum MilkyWayStrings {
    static var title: String {
        String(localized: "data.milkyWay.title", defaultValue: "Milky Way", comment: "Section title")
    }
    static var caption: String {
        String(
            localized: "data.milkyWay.caption",
            defaultValue: "The galactic centre above ten degrees, the sun below eighteen degrees, and no bright moon up. For the night that begins on this date.",
            comment: "The three conditions that define a Milky Way window")
    }
    static var window: String {
        String(localized: "data.milkyWay.window", defaultValue: "Window", comment: "The stretch of the night when all conditions hold")
    }
    static var quality: String {
        String(localized: "data.milkyWay.quality", defaultValue: "Quality", comment: "Graded quality of the window")
    }
    static var best: String {
        String(localized: "data.milkyWay.best", defaultValue: "Best moment", comment: "When the galactic centre stands highest inside the window")
    }
    static var bestAltitude: String {
        String(localized: "data.milkyWay.bestAltitude", defaultValue: "Altitude then", comment: "Altitude of the galactic centre at the best moment")
    }
    static var highestTonight: String {
        String(localized: "data.milkyWay.highestTonight", defaultValue: "Highest tonight", comment: "The best the galactic centre managed even though there was no window")
    }
    static var highestCaption: String {
        String(
            localized: "data.milkyWay.highestCaption",
            defaultValue: "The highest the galactic centre reached at any point in the night, whether or not the sky was dark then.",
            comment: "Explains the highest altitude figure when there is no window")
    }
}
