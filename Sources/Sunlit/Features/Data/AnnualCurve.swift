import SwiftUI
import SunlitCore

// MARK: - The year

/// The highest the sun reaches on every date of the selected year, drawn as one
/// curve with the equinoxes and the solstices marked.
///
/// The curve is sampled from `SkyMoment`, which is the app's one entry point
/// into the ephemeris. Nothing here derives a solar position; it walks the
/// altitude and the declination the core reports and picks out the extremes and
/// the zero crossings of that series, because there is no core call that
/// returns a year at a time.
struct AnnualSection: View {

    let place: Place
    let selected: Date
    /// The highest the sun reaches on the selected date, taken from the day
    /// report the screen already holds. Scanning for it inside the year would
    /// be a second answer to a question the core has already answered exactly,
    /// and two figures for one quantity on one screen is a defect whichever of
    /// them is right. Nil while that report is being rebuilt.
    let selectedMaximum: Double?
    var lock: DataLock?

    @State private var year: AnnualYear?

    private var format: DataFormat {
        DataFormat(timeZone: TimeZone(identifier: place.timeZoneIdentifier) ?? .gmt)
    }

    var body: some View {
        DataSection(title: AnnualStrings.title, caption: AnnualStrings.caption, lock: lock) {
            if lock != nil {
                placeholder
            } else if let year {
                AnnualCurveChart(
                    year: year,
                    selectedDayIndex: AnnualYear.dayIndex(of: selected, place: place))

                ForEach(year.markers, id: \.kind) { marker in
                    DataRow(
                        label: name(of: marker.kind),
                        value: format.degrees(marker.maximumAltitude) ?? "",
                        spoken: format.spokenDegrees(marker.maximumAltitude),
                        accent: SkyColors.sun,
                        caption: format.day(marker.date))
                }

                HairlineDivider()

                if let selectedMaximum {
                    DataRow(
                        label: AnnualStrings.thisDate,
                        value: format.degrees(selectedMaximum) ?? "",
                        spoken: format.spokenDegrees(selectedMaximum),
                        caption: format.day(selected))
                }

                DataRow(
                    label: AnnualStrings.spread,
                    value: format.degrees(year.highest - year.lowest) ?? "",
                    spoken: format.spokenDegrees(year.highest - year.lowest),
                    caption: AnnualStrings.spreadCaption)

                if year.lowest < 0 {
                    DataNote(text: AnnualStrings.belowHorizon)
                }
            } else {
                DataLoadingRow()
            }
        }
        .task(id: key) { await build() }
    }

    @ViewBuilder
    private var placeholder: some View {
        ForEach(AnnualYear.Kind.allCases, id: \.self) { kind in
            DataRow(label: name(of: kind), value: DataStrings.placeholderFigure)
        }
        DataRow(label: AnnualStrings.thisDate, value: DataStrings.placeholderFigure)
    }

    private func name(of kind: AnnualYear.Kind) -> String {
        // Neutral names. "Summer solstice" is wrong for half the planet, and
        // this app is sold in ten storefronts on both sides of the equator.
        switch kind {
        case .marchEquinox:
            return String(localized: "data.annual.marchEquinox", defaultValue: "March equinox", comment: "Solar event, hemisphere neutral name")
        case .juneSolstice:
            return String(localized: "data.annual.juneSolstice", defaultValue: "June solstice", comment: "Solar event, hemisphere neutral name")
        case .septemberEquinox:
            return String(localized: "data.annual.septemberEquinox", defaultValue: "September equinox", comment: "Solar event, hemisphere neutral name")
        case .decemberSolstice:
            return String(localized: "data.annual.decemberSolstice", defaultValue: "December solstice", comment: "Solar event, hemisphere neutral name")
        }
    }

    // MARK: Building

    /// Deliberately without the selected day in it. The curve is a property of
    /// a place and a year: nothing in it moves when the reader steps the date
    /// by one, and the upright that marks the selection is drawn from a
    /// calendar subtraction. Keying on the day made a single tap on the date
    /// picker re sweep the whole year, which is about three and a half thousand
    /// ephemeris evaluations for a picture that does not change.
    private struct Key: Equatable {
        let latitude: Double
        let longitude: Double
        let elevation: Double
        let zone: String
        let year: Int
        let locked: Bool
    }

    private var key: Key {
        Key(
            latitude: place.latitude,
            longitude: place.longitude,
            elevation: place.elevation,
            zone: place.timeZoneIdentifier,
            year: AnnualYear.year(of: selected, place: place),
            locked: lock != nil)
    }

    @MainActor
    private func build() async {
        guard lock == nil else {
            year = nil
            return
        }
        // Dropped first: the rows beneath the curve are captioned with dates,
        // and holding the previous place's year under them would caption one
        // place's solstice altitude with another place's calendar.
        year = nil
        let capturedPlace = self.place
        let capturedYear = AnnualYear.year(of: selected, place: place)
        let built = await Task.detached(priority: .utility) {
            AnnualYear.compute(place: capturedPlace, year: capturedYear)
        }.value
        guard !Task.isCancelled else { return }
        year = built
    }
}

// MARK: - The sampled year

struct AnnualYear: Sendable {

    struct Point: Sendable {
        let dayIndex: Int
        let maximumAltitude: Double
    }

    enum Kind: String, Sendable, CaseIterable, Hashable {
        case marchEquinox, juneSolstice, septemberEquinox, decemberSolstice
    }

    struct Marker: Sendable {
        let kind: Kind
        let dayIndex: Int
        let date: Date
        let maximumAltitude: Double
    }

    let year: Int
    let dayCount: Int
    let points: [Point]
    let markers: [Marker]
    let lowest: Double
    let highest: Double

    /// One sample every five days. The curve is a slow sinusoid, so five days
    /// draws it smoothly, and the marked dates are refined to the day
    /// afterwards rather than being read off this grid.
    private static let sampleStride = 5

    static func year(of date: Date, place: Place) -> Int {
        calendar(for: place).component(.year, from: date)
    }

    private static func calendar(for place: Place) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: place.timeZoneIdentifier) ?? .gmt
        return calendar
    }

    /// Which day of `year` a date falls on, in the place's own calendar. Pure
    /// arithmetic, so the view can do it on the main actor between frames.
    static func dayIndex(of date: Date, place: Place) -> Int {
        let calendar = calendar(for: place)
        let year = calendar.component(.year, from: date)
        guard let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1))
        else { return 0 }
        let dayCount = calendar.range(of: .day, in: .year, for: startOfYear)?.count ?? 365
        let raw = calendar.dateComponents(
            [.day], from: startOfYear, to: calendar.startOfDay(for: date)).day ?? 0
        return min(max(raw, 0), dayCount - 1)
    }

    static func compute(place: Place, year: Int) -> AnnualYear {
        let calendar = calendar(for: place)
        let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1))
            ?? Date()
        let dayCount = calendar.range(of: .day, in: .year, for: startOfYear)?.count ?? 365

        func localMidnight(dayIndex: Int) -> JulianDay {
            let date = calendar.date(byAdding: .day, value: dayIndex, to: startOfYear) ?? startOfYear
            return place.startOfLocalDay(containing: date)
        }

        func date(dayIndex: Int) -> Date {
            calendar.date(byAdding: .day, value: dayIndex, to: startOfYear) ?? startOfYear
        }

        /// Declination at local noon. One evaluation, used to place the four
        /// events; the altitude curve does not depend on it.
        func noonDeclination(dayIndex: Int) -> Double {
            SkyMoment.at(localMidnight(dayIndex: dayIndex).adding(days: 0.5), place: place)
                .sunEquatorial.declination
        }

        var points: [Point] = []
        var indices: [Int] = Array(Swift.stride(from: 0, to: dayCount, by: sampleStride))
        if indices.last != dayCount - 1 { indices.append(dayCount - 1) }
        points.reserveCapacity(indices.count)
        for index in indices {
            points.append(Point(
                dayIndex: index,
                maximumAltitude: peakAltitude(dayStart: localMidnight(dayIndex: index), place: place)))
        }

        // The four events, found from the declination the core reports rather
        // than from a calendar table, so they are right for the actual year.
        var declinations: [Int: Double] = [:]
        func declination(_ index: Int) -> Double {
            let clamped = min(max(index, 0), dayCount - 1)
            if let cached = declinations[clamped] { return cached }
            let value = noonDeclination(dayIndex: clamped)
            declinations[clamped] = value
            return value
        }

        var markers: [Marker] = []

        func addEquinox(_ kind: Kind, ascending: Bool) {
            var found: Int?
            for step in 0..<(indices.count - 1) {
                let low = declination(indices[step])
                let high = declination(indices[step + 1])
                let crosses = ascending ? (low < 0 && high >= 0) : (low > 0 && high <= 0)
                if crosses {
                    for day in indices[step]..<indices[step + 1] {
                        let a = declination(day)
                        let b = declination(day + 1)
                        let inner = ascending ? (a < 0 && b >= 0) : (a > 0 && b <= 0)
                        if inner {
                            // Take the noon that is nearer the crossing, so the
                            // date is the one that actually contains it.
                            found = abs(a) <= abs(b) ? day : day + 1
                            break
                        }
                    }
                    break
                }
            }
            guard let day = found else { return }
            markers.append(Marker(
                kind: kind,
                dayIndex: day,
                date: date(dayIndex: day),
                maximumAltitude: peakAltitude(dayStart: localMidnight(dayIndex: day), place: place)))
        }

        func addSolstice(_ kind: Kind, maximum: Bool) {
            var bestIndex = indices[0]
            var bestValue = maximum ? -Double.infinity : Double.infinity
            for index in indices {
                let value = declination(index)
                if maximum ? value > bestValue : value < bestValue {
                    bestValue = value
                    bestIndex = index
                }
            }
            var day = bestIndex
            var dayValue = declination(day)
            for candidate in (bestIndex - sampleStride)...(bestIndex + sampleStride) {
                let clamped = min(max(candidate, 0), dayCount - 1)
                let value = declination(clamped)
                if maximum ? value > dayValue : value < dayValue {
                    dayValue = value
                    day = clamped
                }
            }
            markers.append(Marker(
                kind: kind,
                dayIndex: day,
                date: date(dayIndex: day),
                maximumAltitude: peakAltitude(dayStart: localMidnight(dayIndex: day), place: place)))
        }

        addEquinox(.marchEquinox, ascending: true)
        addSolstice(.juneSolstice, maximum: true)
        addEquinox(.septemberEquinox, ascending: false)
        addSolstice(.decemberSolstice, maximum: false)
        markers.sort { $0.dayIndex < $1.dayIndex }

        let altitudes = points.map { $0.maximumAltitude }
        return AnnualYear(
            year: year,
            dayCount: dayCount,
            points: points,
            markers: markers,
            lowest: altitudes.min() ?? 0,
            highest: altitudes.max() ?? 0)
    }

    /// The highest the sun gets on one local day.
    ///
    /// Scanned rather than solved: an hourly pass over the local day finds the
    /// transit wherever the time zone puts it, which matters because solar noon
    /// is past three in the afternoon at the western edge of some zones, and a
    /// five minute pass around it lands the peak inside a hundredth of a degree
    /// because the altitude is quadratic there.
    static func peakAltitude(dayStart: JulianDay, place: Place) -> Double {
        var bestInstant = dayStart
        var bestAltitude = -Double.infinity
        for hour in 0...24 {
            let instant = dayStart.adding(seconds: Double(hour) * 3600)
            let altitude = SkyMoment.at(instant, place: place).sun.altitude
            if altitude > bestAltitude {
                bestAltitude = altitude
                bestInstant = instant
            }
        }
        let coarse = bestInstant
        for step in -11...11 {
            let instant = coarse.adding(seconds: Double(step) * 300)
            let altitude = SkyMoment.at(instant, place: place).sun.altitude
            if altitude > bestAltitude {
                bestAltitude = altitude
            }
        }
        return bestAltitude
    }
}

// MARK: - The drawing

/// The curve itself.
///
/// Hidden from VoiceOver on purpose: the four marked dates and the selected
/// one are spoken as rows immediately below, in full precision, and a spoken
/// polyline tells a reader nothing those rows have not already said.
struct AnnualCurveChart: View {

    let year: AnnualYear
    /// Which day of the year the heavier upright stands on. Passed in rather
    /// than stored on `AnnualYear`, so that stepping the date moves one line
    /// instead of rebuilding the curve.
    let selectedDayIndex: Int

    @Environment(\.solarAltitude) private var solarAltitude
    @Environment(\.displayScale) private var displayScale
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 160

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let ink = SkyPalette.foreground(solarAltitude: solarAltitude)
        let line = SkyPalette.instrumentLine(solarAltitude: solarAltitude)
        let hairline = 1 / displayScale
        let inset: CGFloat = 6
        let plot = CGRect(
            x: inset,
            y: inset,
            width: max(size.width - inset * 2, 1),
            height: max(size.height - inset * 2, 1))

        var low = year.lowest
        var high = year.highest
        if high - low < 1 { high = low + 1 }
        let pad = (high - low) * 0.12
        low -= pad
        high += pad

        func x(_ dayIndex: Int) -> CGFloat {
            let span = max(Double(year.dayCount - 1), 1)
            return plot.minX + plot.width * CGFloat(Double(dayIndex) / span)
        }
        func y(_ altitude: Double) -> CGFloat {
            let span = max(high - low, 0.0001)
            return plot.maxY - plot.height * CGFloat((altitude - low) / span)
        }

        // The horizon, when the year crosses it. A curve that dips under this
        // line is a year with polar night in it, and the note below says so.
        if low < 0 && high > 0 {
            var horizon = Path()
            horizon.move(to: CGPoint(x: plot.minX, y: y(0)))
            horizon.addLine(to: CGPoint(x: plot.maxX, y: y(0)))
            context.stroke(horizon, with: .color(line), lineWidth: hairline)
        }

        // The marked dates, as uprights behind the curve.
        for marker in year.markers {
            var upright = Path()
            upright.move(to: CGPoint(x: x(marker.dayIndex), y: plot.minY))
            upright.addLine(to: CGPoint(x: x(marker.dayIndex), y: plot.maxY))
            context.stroke(upright, with: .color(line), lineWidth: hairline)
        }

        // The selected date, heavier, in the reading ink rather than the rule.
        var selected = Path()
        selected.move(to: CGPoint(x: x(selectedDayIndex), y: plot.minY))
        selected.addLine(to: CGPoint(x: x(selectedDayIndex), y: plot.maxY))
        context.stroke(selected, with: .color(ink), lineWidth: hairline * 2)

        var curve = Path()
        for (index, point) in year.points.enumerated() {
            let position = CGPoint(x: x(point.dayIndex), y: y(point.maximumAltitude))
            if index == 0 { curve.move(to: position) } else { curve.addLine(to: position) }
        }
        context.stroke(curve, with: .color(ink), lineWidth: hairline * 2.5)

        // Accent dots on the four events, each ringed in the audited ink so the
        // mark survives when the colour does not.
        for marker in year.markers {
            let centre = CGPoint(x: x(marker.dayIndex), y: y(marker.maximumAltitude))
            let radius: CGFloat = 4
            let dot = Path(ellipseIn: CGRect(
                x: centre.x - radius, y: centre.y - radius,
                width: radius * 2, height: radius * 2))
            context.fill(dot, with: .color(SkyColors.sun))
            context.stroke(dot, with: .color(ink), lineWidth: hairline * 1.5)
        }
    }
}

// MARK: - Strings

private enum AnnualStrings {
    static var title: String {
        String(localized: "data.annual.title", defaultValue: "The sun across the year", comment: "Section title")
    }
    static var caption: String {
        String(
            localized: "data.annual.caption",
            defaultValue: "The highest the sun reaches on each date of the year at this place. The four light uprights are the equinoxes and the solstices. The heavier one is the date you have selected, which is a fifth upright on all but those four dates.",
            comment: "What the annual curve shows. The selected date is always drawn as its own heavier upright, so there are five unless it falls on a marked date")
    }
    static var thisDate: String {
        String(localized: "data.annual.thisDate", defaultValue: "This date", comment: "Maximum solar altitude on the selected date")
    }
    static var spread: String {
        String(localized: "data.annual.spread", defaultValue: "Range across the year", comment: "Difference between the highest and the lowest noon sun")
    }
    static var spreadCaption: String {
        String(
            localized: "data.annual.spreadCaption",
            defaultValue: "The difference between the highest and the lowest the midday sun gets here. Outside the tropics it is about forty seven degrees, twice the tilt of the earth. Inside them it is less, because the noon sun passes overhead twice a year and turns back.",
            comment: "Explains the annual range figure")
    }
    static var belowHorizon: String {
        String(
            localized: "data.annual.belowHorizon",
            defaultValue: "Where the curve runs under the horizon line the sun does not rise at all on that date.",
            comment: "The curve crosses zero, so the place has polar night")
    }
}
