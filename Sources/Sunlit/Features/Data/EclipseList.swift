import SwiftUI
import SunlitCore

// MARK: - Eclipses

/// The next solar and the next lunar eclipse, as this place will see them.
///
/// The search walks five years of new and full moons and costs a few hundred
/// milliseconds, so it runs off the main actor and only when the section is
/// actually unlocked. Contact times, magnitude and obscuration all come back
/// from `Eclipse`; nothing here recomputes any of them.
struct EclipseSection: View {

    let place: Place
    let after: JulianDay
    let timeZoneIdentifier: String
    var lock: DataLock?

    @State private var found: EclipseSearch?
    @State private var searching = false

    private var format: DataFormat {
        DataFormat(timeZone: TimeZone(identifier: timeZoneIdentifier) ?? .gmt)
    }

    var body: some View {
        DataSection(title: EclipseStrings.title, caption: EclipseStrings.caption, lock: lock) {
            if lock != nil {
                placeholder
            } else if let found {
                solar(found.solar)
                HairlineDivider()
                lunar(found.lunar)
            } else if searching {
                DataLoadingRow()
            } else {
                DataNote(text: EclipseStrings.searching)
            }
        }
        .task(id: key) { await run() }
    }

    // MARK: Solar

    @ViewBuilder
    private func solar(_ eclipse: Eclipse.SolarLocal?) -> some View {
        if let eclipse {
            DataRow(
                label: EclipseStrings.nextSolar,
                value: solarKind(eclipse.kind),
                accent: SkyColors.sun)

            contact(label: EclipseStrings.firstContact, instant: eclipse.firstContact,
                    absence: EclipseStrings.alreadyUnderWay)
            contact(label: EclipseStrings.maximum, instant: eclipse.maximum,
                    absence: EclipseStrings.noMaximum)
            contact(label: EclipseStrings.lastContact, instant: eclipse.lastContact,
                    absence: EclipseStrings.sunSetFirst)

            DataRow(
                label: EclipseStrings.magnitude,
                value: format.number(eclipse.magnitude, fraction: 3),
                spoken: format.number(eclipse.magnitude, fraction: 3),
                caption: EclipseStrings.magnitudeCaption)

            DataRow(
                label: EclipseStrings.obscuration,
                value: format.percent(eclipse.obscuration, digits: 1),
                spoken: format.percent(eclipse.obscuration, digits: 1),
                caption: EclipseStrings.obscurationCaption)

            DataRow(
                label: EclipseStrings.sunAltitude,
                value: format.degrees(eclipse.maximumAltitude) ?? "",
                spoken: format.spokenDegrees(eclipse.maximumAltitude),
                caption: eclipse.maximumAltitude < 5 ? EclipseStrings.lowSun : nil)
        } else {
            DataNote(text: EclipseStrings.noSolar, label: EclipseStrings.nextSolar)
        }
    }

    // MARK: Lunar

    @ViewBuilder
    private func lunar(_ eclipse: Eclipse.LunarLocal?) -> some View {
        if let eclipse {
            DataRow(
                label: EclipseStrings.nextLunar,
                value: lunarKind(eclipse.kind),
                accent: SkyColors.moon)

            contact(label: EclipseStrings.penumbralBegin, instant: eclipse.penumbralBegin,
                    absence: EclipseStrings.phaseAbsent)
            if eclipse.kind == .partial || eclipse.kind == .total {
                contact(label: EclipseStrings.partialBegin, instant: eclipse.partialBegin,
                        absence: EclipseStrings.phaseAbsent)
            }
            if eclipse.kind == .total {
                contact(label: EclipseStrings.totalBegin, instant: eclipse.totalBegin,
                        absence: EclipseStrings.phaseAbsent)
            }
            contact(label: EclipseStrings.maximum, instant: eclipse.maximum,
                    absence: EclipseStrings.phaseAbsent)
            if eclipse.kind == .total {
                contact(label: EclipseStrings.totalEnd, instant: eclipse.totalEnd,
                        absence: EclipseStrings.phaseAbsent)
            }
            if eclipse.kind == .partial || eclipse.kind == .total {
                contact(label: EclipseStrings.partialEnd, instant: eclipse.partialEnd,
                        absence: EclipseStrings.phaseAbsent)
            }
            contact(label: EclipseStrings.penumbralEnd, instant: eclipse.penumbralEnd,
                    absence: EclipseStrings.phaseAbsent)

            DataRow(
                label: EclipseStrings.umbralMagnitude,
                value: format.number(eclipse.umbralMagnitude, fraction: 3),
                spoken: format.number(eclipse.umbralMagnitude, fraction: 3),
                caption: EclipseStrings.umbralCaption)

            DataRow(
                label: EclipseStrings.penumbralMagnitude,
                value: format.number(eclipse.penumbralMagnitude, fraction: 3),
                spoken: format.number(eclipse.penumbralMagnitude, fraction: 3))

            DataRow(
                label: EclipseStrings.moonAltitude,
                value: format.degrees(eclipse.moonAltitudeAtMaximum) ?? "",
                spoken: format.spokenDegrees(eclipse.moonAltitudeAtMaximum))

            if eclipse.moonAltitudeAtMaximum <= 0 {
                DataNote(text: EclipseStrings.moonBelowHorizon)
            }
        } else {
            DataNote(text: EclipseStrings.noLunar, label: EclipseStrings.nextLunar)
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func contact(label: String, instant: JulianDay?, absence: String) -> some View {
        if let value = format.dateAndTime(instant) {
            DataRow(label: label, value: value)
        } else {
            DataNote(text: absence, label: label)
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        DataRow(label: EclipseStrings.nextSolar, value: DataStrings.placeholderTime)
        DataRow(label: EclipseStrings.maximum, value: DataStrings.placeholderTime)
        DataRow(label: EclipseStrings.obscuration, value: DataStrings.placeholderFigure)
        HairlineDivider()
        DataRow(label: EclipseStrings.nextLunar, value: DataStrings.placeholderTime)
        DataRow(label: EclipseStrings.maximum, value: DataStrings.placeholderTime)
        DataRow(label: EclipseStrings.umbralMagnitude, value: DataStrings.placeholderFigure)
    }

    // MARK: Naming

    private func solarKind(_ kind: Eclipse.SolarKind) -> String {
        switch kind {
        case .none:
            return String(localized: "data.eclipse.solar.none", defaultValue: "None visible", comment: "Solar eclipse type")
        case .partial:
            return String(localized: "data.eclipse.solar.partial", defaultValue: "Partial", comment: "Solar eclipse type")
        case .annular:
            return String(localized: "data.eclipse.solar.annular", defaultValue: "Annular", comment: "Solar eclipse type")
        case .total:
            return String(localized: "data.eclipse.solar.total", defaultValue: "Total", comment: "Solar eclipse type")
        }
    }

    private func lunarKind(_ kind: Eclipse.LunarKind) -> String {
        switch kind {
        case .none:
            return String(localized: "data.eclipse.lunar.none", defaultValue: "None", comment: "Lunar eclipse type")
        case .penumbral:
            return String(localized: "data.eclipse.lunar.penumbral", defaultValue: "Penumbral", comment: "Lunar eclipse type")
        case .partial:
            return String(localized: "data.eclipse.lunar.partial", defaultValue: "Partial", comment: "Lunar eclipse type")
        case .total:
            return String(localized: "data.eclipse.lunar.total", defaultValue: "Total", comment: "Lunar eclipse type")
        }
    }

    // MARK: Search

    private struct Key: Equatable {
        let latitude: Double
        let longitude: Double
        let elevation: Double
        let after: Double
        let locked: Bool
    }

    private var key: Key {
        Key(
            latitude: place.latitude,
            longitude: place.longitude,
            elevation: place.elevation,
            after: after.value,
            locked: lock != nil)
    }

    @MainActor
    private func run() async {
        guard lock == nil else {
            found = nil
            searching = false
            return
        }
        // Dropped before the new search starts. Every row in this section is
        // captioned "as this place will see them", so holding the previous
        // place's contact times across a change of place is not a stale figure,
        // it is a false statement about where the reader is standing.
        found = nil
        searching = true
        let geographic = place.geographic
        let start = after
        let result = await Task.detached(priority: .utility) {
            EclipseSearch(
                solar: Eclipse.nextSolar(after: start, place: geographic),
                lunar: Eclipse.nextLunar(after: start, place: geographic))
        }.value
        guard !Task.isCancelled else { return }
        found = result
        searching = false
    }
}

/// What the background search brings back.
struct EclipseSearch: Sendable {
    let solar: Eclipse.SolarLocal?
    let lunar: Eclipse.LunarLocal?
}

// MARK: - Strings

private enum EclipseStrings {
    static var title: String {
        String(localized: "data.eclipse.title", defaultValue: "Eclipses", comment: "Section title")
    }
    static var caption: String {
        String(
            localized: "data.eclipse.caption",
            defaultValue: "The next of each kind visible from this place, searched over the coming five years. All times are local to this place.",
            comment: "Scope of the eclipse search")
    }
    static var searching: String {
        String(
            localized: "data.eclipse.waiting",
            defaultValue: "The next eclipses will be searched for shortly.",
            comment: "Placed before the eclipse search has started")
    }
    static var nextSolar: String {
        String(localized: "data.eclipse.nextSolar", defaultValue: "Next solar eclipse", comment: "Row label")
    }
    static var nextLunar: String {
        String(localized: "data.eclipse.nextLunar", defaultValue: "Next lunar eclipse", comment: "Row label")
    }
    static var firstContact: String {
        String(localized: "data.eclipse.firstContact", defaultValue: "First contact", comment: "The moon's limb first touches the sun's")
    }
    static var maximum: String {
        String(localized: "data.eclipse.maximum", defaultValue: "Maximum", comment: "Greatest phase of the eclipse as seen from here")
    }
    static var lastContact: String {
        String(localized: "data.eclipse.lastContact", defaultValue: "Last contact", comment: "The discs part")
    }
    static var magnitude: String {
        String(localized: "data.eclipse.magnitude", defaultValue: "Magnitude", comment: "Fraction of the sun's diameter covered")
    }
    static var magnitudeCaption: String {
        String(
            localized: "data.eclipse.magnitudeCaption",
            defaultValue: "Fraction of the sun's diameter covered at maximum.",
            comment: "What eclipse magnitude means")
    }
    static var obscuration: String {
        String(localized: "data.eclipse.obscuration", defaultValue: "Obscuration", comment: "Fraction of the sun's area covered")
    }
    static var obscurationCaption: String {
        String(
            localized: "data.eclipse.obscurationCaption",
            defaultValue: "Fraction of the sun's area covered at maximum. Never larger than the magnitude, because a bite taken out of the edge of a disc removes less of its area than of its width.",
            comment: "What obscuration means and how it differs from magnitude")
    }
    static var sunAltitude: String {
        String(localized: "data.eclipse.sunAltitude", defaultValue: "Sun altitude at maximum", comment: "How high the sun stands at greatest eclipse")
    }
    static var lowSun: String {
        String(
            localized: "data.eclipse.lowSun",
            defaultValue: "The sun is close to the horizon then, so you will need a clear view in that direction.",
            comment: "Warning for a sunrise or sunset eclipse")
    }
    static var alreadyUnderWay: String {
        String(
            localized: "data.eclipse.alreadyUnderWay",
            defaultValue: "The sun rises here with the eclipse already in progress, so there is no first contact to see.",
            comment: "First contact happened below the horizon")
    }
    static var sunSetFirst: String {
        String(
            localized: "data.eclipse.sunSetFirst",
            defaultValue: "The sun sets here before the discs part, so there is no last contact to see.",
            comment: "Last contact happens below the horizon")
    }
    static var noMaximum: String {
        String(
            localized: "data.eclipse.noMaximum",
            defaultValue: "No part of this eclipse happens while the sun is above the horizon here.",
            comment: "Nothing of the eclipse is visible from this place")
    }
    static var noSolar: String {
        String(
            localized: "data.eclipse.noSolar",
            defaultValue: "No solar eclipse is visible from this place in the next five years.",
            comment: "The five year search found nothing")
    }
    static var noLunar: String {
        String(
            localized: "data.eclipse.noLunar",
            defaultValue: "No lunar eclipse falls in the next five years.",
            comment: "The five year search found nothing")
    }
    static var penumbralBegin: String {
        String(localized: "data.eclipse.penumbralBegin", defaultValue: "Penumbra begins", comment: "Lunar eclipse contact P1")
    }
    static var partialBegin: String {
        String(localized: "data.eclipse.partialBegin", defaultValue: "Umbra begins", comment: "Lunar eclipse contact U1")
    }
    static var totalBegin: String {
        String(localized: "data.eclipse.totalBegin", defaultValue: "Totality begins", comment: "Lunar eclipse contact U2")
    }
    static var totalEnd: String {
        String(localized: "data.eclipse.totalEnd", defaultValue: "Totality ends", comment: "Lunar eclipse contact U3")
    }
    static var partialEnd: String {
        String(localized: "data.eclipse.partialEnd", defaultValue: "Umbra ends", comment: "Lunar eclipse contact U4")
    }
    static var penumbralEnd: String {
        String(localized: "data.eclipse.penumbralEnd", defaultValue: "Penumbra ends", comment: "Lunar eclipse contact P4")
    }
    static var umbralMagnitude: String {
        String(localized: "data.eclipse.umbralMagnitude", defaultValue: "Umbral magnitude", comment: "Fraction of the moon's diameter inside the umbra")
    }
    static var umbralCaption: String {
        String(
            localized: "data.eclipse.umbralCaption",
            defaultValue: "Fraction of the moon's diameter inside the dark shadow at maximum. Below zero the moon misses the umbra altogether.",
            comment: "What umbral magnitude means")
    }
    static var penumbralMagnitude: String {
        String(localized: "data.eclipse.penumbralMagnitude", defaultValue: "Penumbral magnitude", comment: "The same for the outer shadow")
    }
    static var moonAltitude: String {
        String(localized: "data.eclipse.moonAltitude", defaultValue: "Moon altitude at maximum", comment: "How high the moon stands at greatest eclipse")
    }
    static var moonBelowHorizon: String {
        String(
            localized: "data.eclipse.moonBelowHorizon",
            defaultValue: "The moon is below the horizon here at maximum, so this eclipse happens while it is out of sight from this place. The contact times are the same everywhere on Earth; only whether you can see them changes.",
            comment: "A lunar eclipse that is not visible from this place")
    }
    static var phaseAbsent: String {
        String(
            localized: "data.eclipse.phaseAbsent",
            defaultValue: "This eclipse does not reach that phase.",
            comment: "A lunar eclipse contact that does not exist for this event")
    }
}
