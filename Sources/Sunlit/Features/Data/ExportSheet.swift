import SwiftUI
import UIKit
import SunlitCore

// MARK: - The section

/// The row that opens export. Behind `ProCapability.export`, and greyed rather
/// than hidden when it is locked, so the free app does not look broken.
struct ExportSection: View {

    let day: DataDay
    let place: Place
    var lock: DataLock?

    @Environment(\.solarAltitude) private var solarAltitude
    @Environment(\.displayScale) private var displayScale

    @State private var showing = false

    var body: some View {
        DataSection(title: ExportStrings.title, caption: ExportStrings.caption, lock: lock) {
            Button {
                showing = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                        .accessibilityHidden(true)
                    Text(ExportStrings.open)
                        .font(SunlitType.body)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            SkyPalette.componentBorder(solarAltitude: solarAltitude),
                            lineWidth: 1 / displayScale)
                }
                // Inside the label. A minimum frame on the `Button` itself lays
                // the button out in a larger box without enlarging its hit
                // region, which stays the label's own bounds: 42 points tall at
                // the default text size.
                .sunlitTouchTarget()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(ExportStrings.open))
            .accessibilityHint(Text(ExportStrings.caption))
        }
        .sheet(isPresented: $showing) {
            ExportSheet(day: day, place: place)
        }
    }
}

// MARK: - The sheet

/// Two files, both built on the spot from the day already in hand.
///
/// The spreadsheet is written in English with ISO 8601 timestamps and dot
/// decimals, which is stated on this screen, because a file whose column names
/// and number format follow the reader's locale is a file no second reader can
/// open.
struct ExportSheet: View {

    let day: DataDay
    let place: Place

    @Environment(\.dismiss) private var dismiss

    @State private var csvURL: URL?
    @State private var imageURL: URL?
    @State private var working = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(ExportStrings.zoneHeading)
                            .font(SunlitType.title)
                        Text(zoneExplanation)
                            .font(SunlitType.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)

                    Divider()

                    block(
                        heading: ExportStrings.csvHeading,
                        detail: ExportStrings.csvDetail,
                        url: csvURL,
                        symbol: "tablecells",
                        action: ExportStrings.shareCSV)

                    Divider()

                    block(
                        heading: ExportStrings.imageHeading,
                        detail: ExportStrings.imageDetail,
                        url: imageURL,
                        symbol: "photo",
                        action: ExportStrings.shareImage)

                    Text(DataStrings.clearSkyModel)
                        .font(SunlitType.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(Text(ExportStrings.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(DataStrings.done)
                    }
                    .accessibilityLabel(Text(DataStrings.done))
                }
            }
        }
        .task { await prepare() }
    }

    @ViewBuilder
    private func block(
        heading: String,
        detail: String,
        url: URL?,
        symbol: String,
        action: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(heading)
                .font(SunlitType.title)
            Text(detail)
                .font(SunlitType.body)
                .fixedSize(horizontal: false, vertical: true)

            if let url {
                ShareLink(item: url) {
                    HStack(spacing: 8) {
                        Image(systemName: symbol)
                            .accessibilityHidden(true)
                        Text(action)
                            .font(SunlitType.body)
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.7), lineWidth: 1)
                    }
                    // Inside the label, for the same reason as everywhere else
                    // in this territory: a frame on the control does not move
                    // the region a finger can land on.
                    .sunlitTouchTarget()
                }
                .accessibilityLabel(Text(action))
            } else if working {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(ExportStrings.preparing)
                        .font(SunlitType.body)
                }
                .frame(minHeight: SunlitLayout.minimumTouchTarget)
                .accessibilityElement(children: .combine)
            } else {
                Text(ExportStrings.failed)
                    .font(SunlitType.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var zoneExplanation: String {
        let zone = day.timeZone
        let name = zone.localizedName(for: .generic, locale: .current) ?? zone.identifier
        return String(
            localized: "data.export.zoneExplanation",
            defaultValue: "Every time in both files is written for \(name), with its offset from Universal Time attached. The spreadsheet is in English with ISO 8601 timestamps and a full stop as the decimal separator, so that anyone can open it.",
            comment: "Explains the clock and the format the export uses")
    }

    @MainActor
    private func prepare() async {
        working = true
        // The spreadsheet is text and a file write, so it goes off the main
        // actor. The picture cannot: `ImageRenderer` lays out a SwiftUI view and
        // is main actor bound by construction.
        let capturedDay = day
        let capturedPlace = place
        csvURL = await Task.detached(priority: .userInitiated) {
            DayExport.writeCSV(day: capturedDay, place: capturedPlace)
        }.value
        imageURL = DayExport.writeImage(day: day, place: place)
        working = false
    }
}

// MARK: - Files

/// Building the two files. Kept apart from the views so that the spreadsheet
/// can be reasoned about as text and not as a layout.
enum DayExport {

    // MARK: Spreadsheet

    static func writeCSV(day: DataDay, place: Place) -> URL? {
        let text = csv(day: day, place: place)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileStem(day: day, place: place) + ".csv")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    /// One table, one header row, stable English identifiers, ISO 8601 in the
    /// place's own zone, and a dot for the decimal point whatever the reader's
    /// locale does on screen.
    static func csv(day: DataDay, place: Place) -> String {
        let zone = day.timeZone
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withInternetDateTime]
        stamp.timeZone = zone

        func time(_ julianDay: JulianDay?) -> String {
            guard let julianDay else { return "" }
            return stamp.string(from: julianDay.date)
        }
        func figure(_ value: Double?, _ places: Int) -> String {
            guard let value else { return "" }
            return String(format: "%.\(places)f", value)
        }

        var rows: [[String]] = [
            ["section", "item", "value", "unit", "timestamp", "note"]
        ]
        func add(_ section: String, _ item: String,
                 value: String = "", unit: String = "",
                 timestamp: String = "", note: String = "") {
            rows.append([section, item, value, unit, timestamp, note])
        }

        let report = day.report
        let phases = report.phases

        add("place", "name", value: place.name)
        add("place", "latitude", value: figure(place.latitude, 6), unit: "degrees", note: "positive north")
        add("place", "longitude", value: figure(place.longitude, 6), unit: "degrees", note: "positive east")
        add("place", "elevation", value: figure(place.elevation, 1), unit: "metres")
        add("place", "time zone", value: place.timeZoneIdentifier)
        add("place", "utc offset", value: figure(Double(zone.secondsFromGMT(for: report.date.date)) / 3600, 2), unit: "hours")
        add("report", "local date", value: DateFormatter.isoDay(zone: zone).string(from: report.date.date))
        add("report", "generated", timestamp: stamp.string(from: Date()))
        add("report", "engine", value: "Sunlit, computed on device, no network")

        add("sun", "sunrise", timestamp: time(phases.sunrise),
            note: phases.sunrise == nil ? absentSunNote(report) : "")
        add("sun", "solar noon", timestamp: time(phases.solarNoon))
        add("sun", "sunset", timestamp: time(phases.sunset),
            note: phases.sunset == nil ? absentSunNote(report) : "")
        add("sun", "day length", value: figure(report.dayLength, 0), unit: "seconds")
        add("sun", "day length change", value: figure(day.dayLengthChange, 0), unit: "seconds",
            note: "compared with the previous local day")
        add("sun", "maximum altitude", value: figure(report.maximumSolarAltitude, 4), unit: "degrees")
        add("sun", "sunrise azimuth", value: figure(report.sunriseAzimuth, 4), unit: "degrees")
        add("sun", "transit azimuth", value: figure(report.transitAzimuth, 4), unit: "degrees")
        add("sun", "sunset azimuth", value: figure(report.sunsetAzimuth, 4), unit: "degrees")
        add("sun", "polar day", value: phases.polarDay ? "true" : "false")
        add("sun", "polar night", value: phases.polarNight ? "true" : "false")

        add("twilight", "astronomical dawn", timestamp: time(phases.astronomicalDawn))
        add("twilight", "nautical dawn", timestamp: time(phases.nauticalDawn))
        add("twilight", "civil dawn", timestamp: time(phases.civilDawn))
        add("twilight", "civil dusk", timestamp: time(phases.civilDusk))
        add("twilight", "nautical dusk", timestamp: time(phases.nauticalDusk))
        add("twilight", "astronomical dusk", timestamp: time(phases.astronomicalDusk))

        func window(_ section: String, _ item: String, _ value: GoldenHour.Window?) {
            add(section, item + " start", timestamp: value.map { time($0.start) } ?? "")
            add(section, item + " end", timestamp: value.map { time($0.end) } ?? "")
        }
        window("light", "morning blue hour", report.blueHour.morning)
        window("light", "morning golden hour", report.goldenHour.morning)
        window("light", "evening golden hour", report.goldenHour.evening)
        window("light", "evening blue hour", report.blueHour.evening)

        add("moon", "moonrise", timestamp: time(report.moonrise),
            note: report.moonrise == nil ? "no moonrise falls on this local date" : "")
        add("moon", "moonset", timestamp: time(report.moonset),
            note: report.moonset == nil ? "no moonset falls on this local date" : "")
        add("moon", "illuminated fraction", value: figure(report.moonPhaseAtNoon.illuminatedFraction, 4),
            unit: "fraction", note: "at local noon")
        add("moon", "cycle fraction", value: figure(report.moonPhaseAtNoon.cycleFraction, 4),
            unit: "fraction", note: "0 is new moon, 0.5 is full moon, at local noon")
        add("moon", "phase angle", value: figure(report.moonPhaseAtNoon.phaseAngle, 3), unit: "degrees")
        add("moon", "distance", value: figure(day.noon.moonDistance, 1), unit: "kilometres",
            note: "topocentric, at local noon")

        let milkyWay = day.milkyWay
        add("milky way", "window start", timestamp: milkyWay.window.map { time($0.start) } ?? "",
            note: milkyWay.window == nil ? (milkyWay.limitingFactor?.rawValue ?? "no window") : "")
        add("milky way", "window end", timestamp: milkyWay.window.map { time($0.end) } ?? "")
        add("milky way", "quality", value: milkyWay.quality.rawValue)
        add("milky way", "best altitude", value: figure(milkyWay.bestAltitude, 3), unit: "degrees")

        add("terrain", "horizon measured", value: report.hasMeasuredHorizon ? "true" : "false")
        add("terrain", "sunrise over skyline", timestamp: time(day.terrain.sunrise))
        add("terrain", "sunset behind skyline", timestamp: time(day.terrain.sunset))
        for (index, period) in day.terrain.obstructionPeriods.enumerated() {
            add("terrain", "obstruction \(index + 1) start", timestamp: time(period.start))
            add("terrain", "obstruction \(index + 1) end", timestamp: time(period.end))
        }

        let modelNote = "clear sky model, not a measurement"
        add("model", "uv index at solar noon", value: figure(day.peak.uv.index, 2), unit: "index", note: modelNote)
        add("model", "uv category at solar noon", value: day.peak.uv.category.rawValue, note: modelNote)
        add("model", "ozone column", value: figure(day.peak.uv.ozoneDobson, 1), unit: "dobson units",
            note: "climatology used by the clear sky uv model")
        add("model", "global irradiance at solar noon", value: figure(day.peak.irradiance.global, 1),
            unit: "watts per square metre", note: modelNote)
        add("model", "direct irradiance at solar noon", value: figure(day.peak.irradiance.direct, 1),
            unit: "watts per square metre", note: modelNote)
        add("model", "diffuse irradiance at solar noon", value: figure(day.peak.irradiance.diffuse, 1),
            unit: "watts per square metre", note: modelNote)
        add("model", "air mass at solar noon", value: figure(day.peak.irradiance.airMass, 4), unit: "relative")

        return rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    private static func absentSunNote(_ report: DayReport) -> String {
        if report.phases.polarDay { return "the sun stays above the horizon for the whole local date" }
        if report.phases.polarNight { return "the sun stays below the horizon for the whole local date" }
        return "no crossing of the horizon on this local date"
    }

    /// RFC 4180 quoting. A place name with a comma in it, and there are many,
    /// would otherwise split into two columns and silently shift every field
    /// after it.
    private static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: Image

    @MainActor
    static func writeImage(day: DataDay, place: Place) -> URL? {
        let renderer = ImageRenderer(content: DayCard(day: day, place: place))
        renderer.scale = 3
        guard let image = renderer.uiImage, let data = image.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileStem(day: day, place: place) + ".png")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    // MARK: Naming

    private static func fileStem(day: DataDay, place: Place) -> String {
        let stamp = DateFormatter.isoDay(zone: day.timeZone).string(from: day.report.date.date)
        let name = place.name
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return "Sunlit-\(name.isEmpty ? "place" : name)-\(stamp)"
    }
}

extension DateFormatter {
    /// Calendar date only, always in the machine form, for file names and for
    /// the one CSV field that is a date rather than an instant.
    static func isoDay(zone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}

// MARK: - The card

/// What the image export contains.
///
/// Drawn as a self contained view rather than snapshotted from the screen, so
/// the exported picture is a readable sheet at any Dynamic Type size the reader
/// happens to be using, and so it carries the clear sky caption whatever was on
/// screen when the button was pressed.
struct DayCard: View {

    let day: DataDay
    let place: Place

    private var format: DataFormat { day.format }
    private var phases: Twilight.Phases { day.report.phases }
    private var altitude: Double { day.peak.sun.altitude }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(place.name)
                    .font(.system(size: 26, weight: .semibold))
                Text(format.day(day.report.date) ?? "")
                    .font(.system(size: 15))
                Text(place.timeZoneIdentifier)
                    .font(.system(size: 13))
            }

            Rectangle()
                .fill(SkyPalette.instrumentLine(solarAltitude: altitude))
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 11) {
                line(ExportStrings.cardSunrise, format.time(phases.sunrise) ?? polarText)
                line(ExportStrings.cardNoon, format.time(phases.solarNoon) ?? polarText)
                line(ExportStrings.cardSunset, format.time(phases.sunset) ?? polarText)
                line(ExportStrings.cardDayLength, format.span(day.report.dayLength))
                line(ExportStrings.cardMaximumAltitude, format.degrees(day.report.maximumSolarAltitude) ?? "")
                line(ExportStrings.cardMoon, format.percent(day.report.moonPhaseAtNoon.illuminatedFraction))
                line(ExportStrings.cardUV, format.number(day.peak.uv.index, fraction: 1))
            }

            Text(DataStrings.clearSkyShort)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Text(ExportStrings.cardFooter)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(26)
        .frame(width: 390, height: 540, alignment: .topLeading)
        .adaptiveSky(solarAltitude: altitude, moonIllumination: day.noon.moonPhase.illuminatedFraction)
        // The renderer has no reader to ask, so the card is drawn at the
        // standard content size rather than at whatever the device is set to.
        .environment(\.dynamicTypeSize, .large)
    }

    private var polarText: String {
        phases.polarDay ? ExportStrings.cardPolarDay : ExportStrings.cardPolarNight
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .textCase(.uppercase)
            Spacer(minLength: 10)
            Text(value)
                .font(.system(size: 17, weight: .medium).monospacedDigit())
        }
    }
}

// MARK: - Strings

private enum ExportStrings {
    static var title: String {
        String(localized: "data.export.title", defaultValue: "Export", comment: "Section and sheet title")
    }
    static var caption: String {
        String(
            localized: "data.export.caption",
            defaultValue: "A spreadsheet of every figure on this screen, and a picture of the day to send on.",
            comment: "What export produces")
    }
    static var open: String {
        String(localized: "data.export.open", defaultValue: "Export this day", comment: "Opens the export sheet")
    }
    static var zoneHeading: String {
        String(localized: "data.export.zoneHeading", defaultValue: "Times and format", comment: "Heading above the export format explanation")
    }
    static var csvHeading: String {
        String(localized: "data.export.csvHeading", defaultValue: "Spreadsheet", comment: "Heading for the CSV export")
    }
    static var csvDetail: String {
        String(
            localized: "data.export.csvDetail",
            defaultValue: "One row per figure, with a header row, the unit it is measured in, and a note wherever a value is absent that says why.",
            comment: "What the CSV contains")
    }
    static var imageHeading: String {
        String(localized: "data.export.imageHeading", defaultValue: "Picture", comment: "Heading for the image export")
    }
    static var imageDetail: String {
        String(
            localized: "data.export.imageDetail",
            defaultValue: "The day's headline figures on the sky colour of its own solar noon.",
            comment: "What the exported image contains")
    }
    static var shareCSV: String {
        String(localized: "data.export.shareCSV", defaultValue: "Share the spreadsheet", comment: "Share button for the CSV")
    }
    static var shareImage: String {
        String(localized: "data.export.shareImage", defaultValue: "Share the picture", comment: "Share button for the image")
    }
    static var preparing: String {
        String(localized: "data.export.preparing", defaultValue: "Preparing the file", comment: "Shown while an export file is being written")
    }
    static var failed: String {
        String(
            localized: "data.export.failed",
            defaultValue: "This file could not be written on this device.",
            comment: "Writing an export file failed")
    }
    static var cardSunrise: String {
        String(localized: "data.card.sunrise", defaultValue: "Sunrise", comment: "Label on the exported picture")
    }
    static var cardNoon: String {
        String(localized: "data.card.noon", defaultValue: "Solar noon", comment: "Label on the exported picture")
    }
    static var cardSunset: String {
        String(localized: "data.card.sunset", defaultValue: "Sunset", comment: "Label on the exported picture")
    }
    static var cardDayLength: String {
        String(localized: "data.card.dayLength", defaultValue: "Day length", comment: "Label on the exported picture")
    }
    static var cardMaximumAltitude: String {
        String(localized: "data.card.maximumAltitude", defaultValue: "Sun at noon", comment: "Label on the exported picture")
    }
    static var cardMoon: String {
        String(localized: "data.card.moon", defaultValue: "Moon lit", comment: "Label on the exported picture")
    }
    static var cardUV: String {
        String(localized: "data.card.uv", defaultValue: "UV index", comment: "Label on the exported picture")
    }
    static var cardPolarDay: String {
        String(localized: "data.card.polarDay", defaultValue: "Sun never sets", comment: "Stands in for a time on the exported picture")
    }
    static var cardPolarNight: String {
        String(localized: "data.card.polarNight", defaultValue: "Sun never rises", comment: "Stands in for a time on the exported picture")
    }
    static var cardFooter: String {
        String(
            localized: "data.card.footer",
            defaultValue: "Computed on device by Sunlit. UV index is a clear sky model.",
            comment: "Footer line on the exported picture")
    }
}
