import SwiftUI
import SunlitCore

// MARK: - Ranges

extension DataFormat {
    /// A window, written as one figure so a table row holds it on one line.
    func range(_ start: JulianDay, _ end: JulianDay) -> String {
        let from = time(start) ?? ""
        let to = time(end) ?? ""
        return String(
            localized: "data.format.range",
            defaultValue: "\(from) to \(to)",
            comment: "A window between two clock times")
    }
}

// MARK: - Sun

/// Rise, transit and set, with the azimuths the sun actually stands at when it
/// gets there, the length of the day and how much of it yesterday did not have.
struct SunSection: View {

    let day: DataDay
    var lock: DataLock?

    private var report: DayReport { day.report }
    private var phases: Twilight.Phases { report.phases }
    private var format: DataFormat { day.format }

    var body: some View {
        DataSection(title: SunStrings.title, lock: lock) {
            if phases.polarDay {
                DataNote(text: SunStrings.polarDay)
            } else if phases.polarNight {
                DataNote(text: SunStrings.polarNight)
            } else {
                riseTransitSet
            }

            DataRow(
                label: SunStrings.dayLength,
                value: format.span(report.dayLength),
                spoken: format.span(report.dayLength))

            DataRow(
                label: SunStrings.change,
                value: format.signedShortSpan(day.dayLengthChange),
                spoken: format.signedShortSpan(day.dayLengthChange))

            DataRow(
                label: SunStrings.maximumAltitude,
                value: format.degrees(report.maximumSolarAltitude) ?? "",
                spoken: format.spokenDegrees(report.maximumSolarAltitude))

            HairlineDivider()

            DataRow(
                label: SunStrings.peakUV,
                value: format.number(day.peak.uv.index, fraction: 1),
                spoken: format.number(day.peak.uv.index, fraction: 1),
                caption: uvCaption)

            DataRow(
                label: SunStrings.peakIrradiance,
                value: format.number(day.peak.irradiance.global, fraction: 0),
                unit: SunStrings.wattsPerSquareMetre,
                spoken: String(
                    localized: "data.sun.irradianceSpoken",
                    defaultValue: "\(format.number(day.peak.irradiance.global, fraction: 0)) watts per square metre",
                    comment: "Spoken form of a global horizontal irradiance figure"),
                caption: DataStrings.clearSkyShort)
        }
    }

    @ViewBuilder
    private var riseTransitSet: some View {
        row(label: SunStrings.sunrise, instant: phases.sunrise, absence: SunStrings.noSunrise)
        row(label: SunStrings.sunriseAzimuth, angle: report.sunriseAzimuth)
        row(label: SunStrings.solarNoon, instant: phases.solarNoon, absence: SunStrings.noTransit)
        row(label: SunStrings.transitAzimuth, angle: report.transitAzimuth)
        row(label: SunStrings.sunset, instant: phases.sunset, absence: SunStrings.noSunset)
        row(label: SunStrings.sunsetAzimuth, angle: report.sunsetAzimuth)
    }

    @ViewBuilder
    private func row(label: String, instant: JulianDay?, absence: String) -> some View {
        if let value = format.time(instant) {
            DataRow(label: label, value: value, accent: SkyColors.sun)
        } else {
            DataNote(text: absence, label: label)
        }
    }

    @ViewBuilder
    private func row(label: String, angle: Double?) -> some View {
        if let value = format.degrees(angle), let spoken = format.spokenDegrees(angle) {
            DataRow(label: label, value: value, spoken: spoken)
        } else {
            DataNote(text: SunStrings.noAzimuth, label: label)
        }
    }

    private var uvCaption: String {
        categoryName(day.peak.uv.category) + ". " + DataStrings.clearSkyShort
    }

    private func categoryName(_ category: UVIndex.Category) -> String {
        switch category {
        case .low:
            return String(localized: "data.uv.low", defaultValue: "Low", comment: "WHO UV exposure category")
        case .moderate:
            return String(localized: "data.uv.moderate", defaultValue: "Moderate", comment: "WHO UV exposure category")
        case .high:
            return String(localized: "data.uv.high", defaultValue: "High", comment: "WHO UV exposure category")
        case .veryHigh:
            return String(localized: "data.uv.veryHigh", defaultValue: "Very high", comment: "WHO UV exposure category")
        case .extreme:
            return String(localized: "data.uv.extreme", defaultValue: "Extreme", comment: "WHO UV exposure category")
        }
    }
}

// MARK: - Twilight

/// All six boundaries. When one is missing the reason is written out, because
/// a place where civil twilight never ends is telling the reader something and
/// a dash tells them nothing.
struct TwilightSection: View {

    let day: DataDay
    var lock: DataLock?

    private var phases: Twilight.Phases { day.report.phases }
    private var format: DataFormat { day.format }

    /// The three bands, each with the altitude that defines it and the two
    /// sentences that explain an absence on either side of it.
    private enum Band {
        case astronomical, nautical, civil

        var altitude: Double {
            switch self {
            case .astronomical: return Twilight.astronomicalAltitude
            case .nautical: return Twilight.nauticalAltitude
            case .civil: return Twilight.civilAltitude
            }
        }

        /// The sun never sank far enough for this boundary to be crossed.
        var neverDark: String {
            switch self {
            case .astronomical:
                return String(
                    localized: "data.twilight.astronomical.neverDark",
                    defaultValue: "The sun does not sink eighteen degrees below the horizon on this date, so the night never becomes astronomically dark.",
                    comment: "Astronomical twilight boundary is never crossed, the white nights case")
            case .nautical:
                return String(
                    localized: "data.twilight.nautical.neverDark",
                    defaultValue: "The sun does not sink twelve degrees below the horizon on this date, so nautical twilight lasts all night.",
                    comment: "Nautical twilight boundary is never crossed")
            case .civil:
                return String(
                    localized: "data.twilight.civil.neverDark",
                    defaultValue: "The sun does not sink six degrees below the horizon on this date, so civil twilight lasts all night.",
                    comment: "Civil twilight boundary is never crossed")
            }
        }

        /// The sun never rose far enough for this boundary to be crossed.
        var neverLight: String {
            switch self {
            case .astronomical:
                return String(
                    localized: "data.twilight.astronomical.neverLight",
                    defaultValue: "The sun stays more than eighteen degrees below the horizon all day here. It is astronomically dark throughout.",
                    comment: "Deep polar night, the astronomical boundary is never reached from below")
            case .nautical:
                return String(
                    localized: "data.twilight.nautical.neverLight",
                    defaultValue: "The sun stays more than twelve degrees below the horizon all day here, so nautical twilight does not begin.",
                    comment: "Polar night, the nautical boundary is never reached from below")
            case .civil:
                return String(
                    localized: "data.twilight.civil.neverLight",
                    defaultValue: "The sun stays more than six degrees below the horizon all day here, so civil twilight does not begin.",
                    comment: "Polar night, the civil boundary is never reached from below")
            }
        }
    }

    var body: some View {
        DataSection(title: TwilightStrings.title, caption: TwilightStrings.caption, lock: lock) {
            row(label: TwilightStrings.astronomicalDawn, instant: phases.astronomicalDawn, band: .astronomical)
            row(label: TwilightStrings.nauticalDawn, instant: phases.nauticalDawn, band: .nautical)
            row(label: TwilightStrings.civilDawn, instant: phases.civilDawn, band: .civil)
            HairlineDivider()
            row(label: TwilightStrings.civilDusk, instant: phases.civilDusk, band: .civil)
            row(label: TwilightStrings.nauticalDusk, instant: phases.nauticalDusk, band: .nautical)
            row(label: TwilightStrings.astronomicalDusk, instant: phases.astronomicalDusk, band: .astronomical)
        }
    }

    @ViewBuilder
    private func row(label: String, instant: JulianDay?, band: Band) -> some View {
        if let value = format.time(instant) {
            DataRow(label: label, value: value)
        } else {
            DataNote(text: reason(for: band), label: label)
        }
    }

    private func reason(for band: Band) -> String {
        if day.minimumSolarAltitude > band.altitude { return band.neverDark }
        if day.maximumSolarAltitude < band.altitude { return band.neverLight }
        return TwilightStrings.noCrossing
    }
}

// MARK: - Golden and blue hour

/// Four windows, each with its own duration, in the order the day meets them.
///
/// Neither is an hour. How long the sun takes to cross an altitude band depends
/// on how steeply it moves, so the duration is a figure in its own right rather
/// than a name, and at high latitude in summer it can run to the whole night.
struct GoldenBlueSection: View {

    let day: DataDay
    var lock: DataLock?

    private var format: DataFormat { day.format }

    var body: some View {
        DataSection(title: GoldenStrings.title, caption: GoldenStrings.caption, lock: lock) {
            window(
                label: GoldenStrings.morningBlue,
                window: day.report.blueHour.morning,
                lower: GoldenHour.blueLowerAltitude,
                upper: GoldenHour.blueUpperAltitude)
            window(
                label: GoldenStrings.morningGolden,
                window: day.report.goldenHour.morning,
                lower: GoldenHour.goldenLowerAltitude,
                upper: GoldenHour.goldenUpperAltitude)
            HairlineDivider()
            window(
                label: GoldenStrings.eveningGolden,
                window: day.report.goldenHour.evening,
                lower: GoldenHour.goldenLowerAltitude,
                upper: GoldenHour.goldenUpperAltitude)
            window(
                label: GoldenStrings.eveningBlue,
                window: day.report.blueHour.evening,
                lower: GoldenHour.blueLowerAltitude,
                upper: GoldenHour.blueUpperAltitude)
        }
    }

    @ViewBuilder
    private func window(
        label: String,
        window: GoldenHour.Window?,
        lower: Double,
        upper: Double
    ) -> some View {
        if let window {
            let seconds = (window.end.value - window.start.value) * 86400
            DataRow(
                label: label,
                value: format.range(window.start, window.end),
                caption: String(
                    localized: "data.golden.lasts",
                    defaultValue: "Lasts \(format.span(seconds))",
                    comment: "How long a golden or blue hour window runs for"))
        } else {
            DataNote(text: absence(lower: lower, upper: upper), label: label)
        }
    }

    private func absence(lower: Double, upper: Double) -> String {
        if day.minimumSolarAltitude > upper { return GoldenStrings.staysAbove }
        if day.maximumSolarAltitude < lower { return GoldenStrings.staysBelow }
        return GoldenStrings.noCrossing
    }
}

// MARK: - Obstruction

/// What the reader's own skyline does to their day.
///
/// The difference between the flat horizon and the measured one is the whole
/// point of sweeping a skyline, so it is a figure here rather than something
/// left for the reader to subtract.
struct ObstructionSection: View {

    let day: DataDay
    var lock: DataLock?

    private var report: DayReport { day.report }
    private var format: DataFormat { day.format }

    var body: some View {
        DataSection(title: TerrainStrings.title, caption: TerrainStrings.caption, lock: lock) {
            if report.hasMeasuredHorizon {
                measured
            } else {
                DataNote(text: TerrainStrings.notMeasured)
            }
        }
    }

    @ViewBuilder
    private var measured: some View {
        comparison(
            label: TerrainStrings.sunriseOverSkyline,
            flatLabel: TerrainStrings.sunriseFlat,
            differenceLabel: TerrainStrings.sunriseDifference,
            measured: day.terrain.sunrise,
            flat: report.phases.sunrise,
            laterIsDelay: true)

        HairlineDivider()

        comparison(
            label: TerrainStrings.sunsetOverSkyline,
            flatLabel: TerrainStrings.sunsetFlat,
            differenceLabel: TerrainStrings.sunsetDifference,
            measured: day.terrain.sunset,
            flat: report.phases.sunset,
            laterIsDelay: false)

        HairlineDivider()

        if day.terrain.obstructionPeriods.isEmpty {
            DataNote(text: TerrainStrings.noObstruction, label: TerrainStrings.blocked)
        } else {
            ForEach(Array(day.terrain.obstructionPeriods.enumerated()), id: \.offset) { entry in
                DataRow(
                    label: TerrainStrings.blocked,
                    value: format.range(entry.element.start, entry.element.end),
                    caption: blockedCaption(from: entry.element.start, to: entry.element.end))
            }
        }
    }

    /// The duration is formatted before the sentence is built, so the catalogue
    /// carries a named placeholder rather than an arithmetic expression no
    /// translator can read or reorder.
    private func blockedCaption(from start: JulianDay, to end: JulianDay) -> String {
        let duration = format.span((end.value - start.value) * 86400)
        return String(
            localized: "data.terrain.blockedFor",
            defaultValue: "Behind the skyline for \(duration)",
            comment: "How long one period behind the skyline lasts")
    }

    @ViewBuilder
    private func comparison(
        label: String,
        flatLabel: String,
        differenceLabel: String,
        measured: JulianDay?,
        flat: JulianDay?,
        laterIsDelay: Bool
    ) -> some View {
        if let measuredValue = format.time(measured) {
            DataRow(label: label, value: measuredValue, accent: SkyColors.sun)
        } else {
            DataNote(text: TerrainStrings.neverClears, label: label)
        }

        if let flatValue = format.time(flat) {
            DataRow(label: flatLabel, value: flatValue)
        } else {
            DataNote(text: TerrainStrings.noFlatEvent, label: flatLabel)
        }

        if let measured, let flat {
            let seconds = (measured.value - flat.value) * 86400
            DataRow(
                label: differenceLabel,
                value: difference(seconds: seconds, laterIsDelay: laterIsDelay),
                spoken: difference(seconds: seconds, laterIsDelay: laterIsDelay))
        }
    }

    private func difference(seconds: TimeInterval, laterIsDelay: Bool) -> String {
        let magnitude = format.shortSpan(abs(seconds))
        if abs(seconds) < 1 { return TerrainStrings.noDifference }
        let delayed = laterIsDelay ? seconds > 0 : seconds < 0
        if delayed {
            return String(
                localized: "data.terrain.later",
                defaultValue: "\(magnitude) later than a flat horizon",
                comment: "The measured skyline delays the event")
        }
        return String(
            localized: "data.terrain.earlier",
            defaultValue: "\(magnitude) earlier than a flat horizon",
            comment: "The measured skyline brings the event forward")
    }
}

// MARK: - Strings

private enum SunStrings {
    static var title: String {
        String(localized: "data.sun.title", defaultValue: "Sun", comment: "Section title")
    }
    static var sunrise: String {
        String(localized: "data.sun.sunrise", defaultValue: "Sunrise", comment: "Upper limb touches a flat horizon")
    }
    static var solarNoon: String {
        String(localized: "data.sun.transit", defaultValue: "Solar noon", comment: "The sun crosses the meridian")
    }
    static var sunset: String {
        String(localized: "data.sun.sunset", defaultValue: "Sunset", comment: "Upper limb leaves a flat horizon")
    }
    static var sunriseAzimuth: String {
        String(localized: "data.sun.sunriseAzimuth", defaultValue: "Sunrise azimuth", comment: "Compass bearing of the sunrise point")
    }
    static var transitAzimuth: String {
        String(localized: "data.sun.transitAzimuth", defaultValue: "Solar noon azimuth", comment: "Azimuth of the sun at solar noon. Solar noon is the app's one name for the culmination")
    }
    static var sunsetAzimuth: String {
        String(localized: "data.sun.sunsetAzimuth", defaultValue: "Sunset azimuth", comment: "Compass bearing of the sunset point")
    }
    static var dayLength: String {
        String(localized: "data.sun.dayLength", defaultValue: "Day length", comment: "Time the sun spends above the horizon")
    }
    static var change: String {
        String(localized: "data.sun.change", defaultValue: "Change from yesterday", comment: "Difference in day length")
    }
    static var maximumAltitude: String {
        String(localized: "data.sun.maximumAltitude", defaultValue: "Maximum altitude", comment: "Highest the sun reaches on this date")
    }
    static var peakUV: String {
        String(localized: "data.sun.peakUV", defaultValue: "UV index at solar noon", comment: "Modelled peak UV index")
    }
    static var peakIrradiance: String {
        String(localized: "data.sun.peakIrradiance", defaultValue: "Irradiance at solar noon", comment: "Modelled global horizontal irradiance")
    }
    static var wattsPerSquareMetre: String {
        String(localized: "data.unit.wattsPerSquareMetre", defaultValue: "W/m²", comment: "Unit of irradiance, watts per square metre, with a superscript two")
    }
    static var polarDay: String {
        String(
            localized: "data.sun.polarDay",
            defaultValue: "The sun stays above the horizon all day here, so there is no sunrise and no sunset on this date.",
            comment: "Midnight sun")
    }
    static var polarNight: String {
        String(
            localized: "data.sun.polarNight",
            defaultValue: "The sun stays below the horizon all day here, so there is no sunrise and no sunset on this date.",
            comment: "Polar night")
    }
    static var noSunrise: String {
        String(
            localized: "data.sun.noSunrise",
            defaultValue: "The sun does not cross the horizon upward on this date.",
            comment: "Sunrise is absent outside the polar day and night cases")
    }
    static var noSunset: String {
        String(
            localized: "data.sun.noSunset",
            defaultValue: "The sun does not cross the horizon downward on this date.",
            comment: "Sunset is absent outside the polar day and night cases")
    }
    static var noTransit: String {
        String(
            localized: "data.sun.noTransit",
            defaultValue: "The sun does not cross the meridian above the horizon on this date.",
            comment: "No solar noon above the horizon")
    }
    static var noAzimuth: String {
        String(
            localized: "data.sun.noAzimuth",
            defaultValue: "There is no event to take an azimuth from on this date.",
            comment: "An azimuth is missing because its event is missing. Azimuth is the app's one word for a horizontal direction in degrees")
    }
}

private enum TwilightStrings {
    static var title: String {
        String(localized: "data.twilight.title", defaultValue: "Twilight", comment: "Section title")
    }
    static var caption: String {
        String(
            localized: "data.twilight.caption",
            defaultValue: "Civil at six degrees, nautical at twelve, astronomical at eighteen degrees below the horizon.",
            comment: "Defines the three twilight bands")
    }
    static var astronomicalDawn: String {
        String(localized: "data.twilight.astronomicalDawn", defaultValue: "Astronomical dawn", comment: "Sun reaches eighteen degrees below the horizon, rising")
    }
    static var nauticalDawn: String {
        String(localized: "data.twilight.nauticalDawn", defaultValue: "Nautical dawn", comment: "Sun reaches twelve degrees below the horizon, rising")
    }
    static var civilDawn: String {
        String(localized: "data.twilight.civilDawn", defaultValue: "Civil dawn", comment: "Sun reaches six degrees below the horizon, rising")
    }
    static var civilDusk: String {
        String(localized: "data.twilight.civilDusk", defaultValue: "Civil dusk", comment: "Sun reaches six degrees below the horizon, setting")
    }
    static var nauticalDusk: String {
        String(localized: "data.twilight.nauticalDusk", defaultValue: "Nautical dusk", comment: "Sun reaches twelve degrees below the horizon, setting")
    }
    static var astronomicalDusk: String {
        String(localized: "data.twilight.astronomicalDusk", defaultValue: "Astronomical dusk", comment: "Sun reaches eighteen degrees below the horizon, setting")
    }
    static var noCrossing: String {
        String(
            localized: "data.twilight.noCrossing",
            defaultValue: "The sun does not cross this boundary on this side of the day.",
            comment: "One of a pair of twilight boundaries is missing")
    }
}

private enum GoldenStrings {
    static var title: String {
        String(localized: "data.golden.title", defaultValue: "Golden and blue hour", comment: "Section title")
    }
    static var caption: String {
        String(
            localized: "data.golden.caption",
            defaultValue: "Golden is the sun between four degrees below and six degrees above the horizon. Blue is between six and four degrees below it. Neither is an hour.",
            comment: "Defines the two photographic light bands")
    }
    static var morningBlue: String {
        String(localized: "data.golden.morningBlue", defaultValue: "Morning blue hour", comment: "Blue hour before sunrise")
    }
    static var morningGolden: String {
        String(localized: "data.golden.morningGolden", defaultValue: "Morning golden hour", comment: "Golden hour after sunrise")
    }
    static var eveningGolden: String {
        String(localized: "data.golden.eveningGolden", defaultValue: "Evening golden hour", comment: "Golden hour before sunset")
    }
    static var eveningBlue: String {
        String(localized: "data.golden.eveningBlue", defaultValue: "Evening blue hour", comment: "Blue hour after sunset")
    }
    static var staysAbove: String {
        String(
            localized: "data.golden.staysAbove",
            defaultValue: "The sun stays above this band all day here, so there is no window.",
            comment: "The sun never descends into the band")
    }
    static var staysBelow: String {
        String(
            localized: "data.golden.staysBelow",
            defaultValue: "The sun stays below this band all day here, so there is no window.",
            comment: "The sun never rises into the band")
    }
    static var noCrossing: String {
        String(
            localized: "data.golden.noCrossing",
            defaultValue: "The sun does not cross this band on this side of solar noon.",
            comment: "One side of the day has no window")
    }
}

private enum TerrainStrings {
    static var title: String {
        String(localized: "data.terrain.title", defaultValue: "Skyline", comment: "Section title for the results of the swept skyline. Skyline is the app's one name for the measured horizon profile")
    }
    static var caption: String {
        String(
            localized: "data.terrain.caption",
            defaultValue: "Compared against the skyline you swept here, not against a flat horizon.",
            comment: "Explains that this section uses the swept skyline rather than the ideal flat horizon")
    }
    static var notMeasured: String {
        String(
            localized: "data.terrain.notMeasured",
            defaultValue: "No skyline has been swept for this place yet. Sweep one in the AR view and this table fills in with the times your own surroundings block the sun.",
            comment: "There is no skyline for this place yet")
    }
    static var sunriseOverSkyline: String {
        String(localized: "data.terrain.sunriseOverSkyline", defaultValue: "Sunrise over your skyline", comment: "Sunrise against the swept skyline. Over here, and behind in the sunset row, is deliberate: the sun climbs out from behind the skyline at dawn and disappears behind it at dusk")
    }
    static var sunsetOverSkyline: String {
        String(localized: "data.terrain.sunsetOverSkyline", defaultValue: "Sunset behind your skyline", comment: "Sunset against the swept skyline. Behind here, and over in the sunrise row, is deliberate: the sun climbs out from behind the skyline at dawn and disappears behind it at dusk")
    }
    static var sunriseFlat: String {
        String(localized: "data.terrain.sunriseFlat", defaultValue: "Sunrise on a flat horizon", comment: "Sunrise ignoring the skyline. Horizon here is the ideal flat one, never the swept skyline")
    }
    static var sunsetFlat: String {
        String(localized: "data.terrain.sunsetFlat", defaultValue: "Sunset on a flat horizon", comment: "Sunset ignoring the skyline. Horizon here is the ideal flat one, never the swept skyline")
    }
    static var sunriseDifference: String {
        String(localized: "data.terrain.sunriseDifference", defaultValue: "Sunrise difference", comment: "Measured minus flat sunrise")
    }
    static var sunsetDifference: String {
        String(localized: "data.terrain.sunsetDifference", defaultValue: "Sunset difference", comment: "Measured minus flat sunset")
    }
    static var blocked: String {
        String(localized: "data.terrain.blocked", defaultValue: "Sun blocked", comment: "A period when the skyline hides the sun")
    }
    static var noObstruction: String {
        String(
            localized: "data.terrain.noObstruction",
            defaultValue: "Your skyline does not block the sun at any point on this date.",
            comment: "No obstruction periods on this day")
    }
    static var neverClears: String {
        String(
            localized: "data.terrain.neverClears",
            defaultValue: "The sun does not clear your skyline at all on this date.",
            comment: "The measured horizon is never cleared")
    }
    static var noFlatEvent: String {
        String(
            localized: "data.terrain.noFlatEvent",
            defaultValue: "There is no flat horizon event on this date to compare against.",
            comment: "Polar day or polar night, so there is nothing to compare with")
    }
    static var noDifference: String {
        String(
            localized: "data.terrain.noDifference",
            defaultValue: "The same as a flat horizon",
            comment: "The measured skyline makes no difference to this event")
    }
}
