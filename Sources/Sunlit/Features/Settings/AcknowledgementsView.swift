import SwiftUI
import SunlitCore

/// Where the data and the arithmetic come from.
///
/// The GeoNames entry is not a courtesy. The embedded city list is licensed
/// under CC BY 4.0, and attribution is a condition of that licence, owed here,
/// in the repository, and on the website. It is the first thing on this screen
/// and it does not move.
///
/// The rest is the working. An app that claims arcsecond accuracy and will not
/// say which series it used is asking to be believed; naming the sources lets
/// anyone check.
struct AcknowledgementsView: View {

    @Environment(AppState.self) private var state
    @Environment(\.openURL) private var openURL

    var body: some View {
        let moment = SkyMoment.at(state.julianDay, place: state.place)
        let altitude = moment.sun.altitude

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SunlitSheetHeader(
                    title: String(
                        localized: "credits.title",
                        defaultValue: "Data and methods",
                        comment: "Title of the acknowledgements screen"))

                geoNames

                HairlineDivider()

                methods

                HairlineDivider()

                models
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .sunlitSheetSky(
            solarAltitude: altitude,
            moonIllumination: moment.moonPhase.illuminatedFraction)
    }

    // MARK: GeoNames

    private var geoNames: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(
                localized: "credits.places",
                defaultValue: "Places",
                comment: "Heading above the city list attribution"))
                .sunlitLabel()

            // The exact attribution string the licence is satisfied by, kept in
            // SunlitCore beside the reader of the data it describes.
            Text(verbatim: CityIndex.attribution)
                .font(SunlitType.body)
                .fixedSize(horizontal: false, vertical: true)

            Text(String(
                localized: "credits.places.detail",
                defaultValue: "The offline city list is the GeoNames cities15000 extract: every populated place above fifteen thousand people, with its coordinate, elevation and time zone. It is used under the Creative Commons Attribution 4.0 licence, and it is stored in the app so that search works with no network.",
                comment: "Explains what the embedded city list is and under which licence"))
                .font(SunlitType.body)
                .fixedSize(horizontal: false, vertical: true)

            linkRow(
                title: String(localized: "credits.geonames.site",
                              defaultValue: "geonames.org",
                              comment: "Link to the GeoNames website"),
                url: URL(string: "https://www.geonames.org"))

            linkRow(
                title: String(localized: "credits.geonames.licence",
                              defaultValue: "Creative Commons Attribution 4.0",
                              comment: "Link to the CC BY 4.0 licence"),
                url: URL(string: "https://creativecommons.org/licenses/by/4.0/"))
        }
    }

    // MARK: Methods

    private var methods: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(
                localized: "credits.methods",
                defaultValue: "How the positions are computed",
                comment: "Heading above the algorithm citations"))
                .sunlitLabel()

            Text(String(
                localized: "credits.methods.detail",
                defaultValue: "Every figure in Sunlit is computed on your device from published algorithms. No server is ever asked for a sun, moon or sky figure, and nothing about you is collected or sent. Two things do use the network, both of them Apple's and neither of them a calculation: the map tiles in the Map view, and the time zone of a pin you drop somewhere new.",
                comment: "States that all computation is local"))
                .font(SunlitType.body)
                .fixedSize(horizontal: false, vertical: true)

            citation(
                subject: String(localized: "credits.sun",
                                defaultValue: "Sun",
                                comment: "Subject of the solar position citation"),
                source: "Reda and Andreas, Solar Position Algorithm for Solar Radiation Applications, NREL/TP-560-34302")

            citation(
                subject: String(localized: "credits.moon",
                                defaultValue: "Moon",
                                comment: "Subject of the lunar position citation"),
                source: "Jean Meeus, Astronomical Algorithms, chapter 47, after the ELP-2000/82 lunar theory")

            citation(
                subject: String(localized: "credits.nutation",
                                defaultValue: "Nutation and obliquity",
                                comment: "Subject of the nutation citation"),
                source: "IAU 1980 nutation series, 63 terms")

            citation(
                subject: String(localized: "credits.deltaT",
                                defaultValue: "Delta T",
                                comment: "Subject of the delta T citation"),
                source: "Espenak and Meeus, polynomial expressions for Delta T")

            citation(
                subject: String(localized: "credits.refraction",
                                defaultValue: "Refraction",
                                comment: "Subject of the refraction citation"),
                source: "Bennett, The Calculation of Astronomical Refraction in Marine Navigation, corrected for pressure and temperature")

            citation(
                subject: String(localized: "credits.eclipses",
                                defaultValue: "Eclipses",
                                comment: "Subject of the eclipse citation"),
                source: "Checked against Espenak and Meeus, Five Millennium Canon of Solar Eclipses, NASA/TP-2006-214141, and the matching lunar catalogue")

            citation(
                subject: String(localized: "credits.milkyWay",
                                defaultValue: "Milky Way",
                                comment: "Subject of the galactic centre citation"),
                source: "Galactic centre Sgr A* at J2000, precessed to date")

            // Deliberately not a citation to a magnetic field model. Sunlit
            // embeds no World Magnetic Model and computes no declination: the
            // AR view takes its bearing from the device's own true north
            // reference frame, which iOS resolves. Naming a coefficient set the
            // app does not carry would be a claim it cannot support.
            citation(
                subject: String(localized: "credits.trueNorth",
                                defaultValue: "True north",
                                comment: "Subject of the compass reference citation"),
                source: trueNorthSource)
        }
    }

    /// Written out rather than set verbatim, because unlike the algorithm
    /// citations this is a sentence about how the compass behaves and a reader
    /// in any language is owed it in theirs.
    private var trueNorthSource: String {
        String(
            localized: "credits.trueNorth.detail",
            defaultValue: "The AR view takes its bearing from the device's true north reference frame, computed by iOS from the compass, the gyroscope and your position. Sunlit does not correct it further, and it shows the current uncertainty on screen instead of hiding it.",
            comment: "Explains where the compass bearing comes from")
    }

    // MARK: Models

    private var models: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(
                localized: "credits.models",
                defaultValue: "What is modelled, not measured",
                comment: "Heading above the clear sky model disclosure"))
                .sunlitLabel()

            Text(String(
                localized: "credits.models.detail",
                defaultValue: "The UV index and the irradiance figures are clear sky models. They say what the sky would deliver with no cloud, no haze and no pollution, from your latitude, the date and the sun's height. They are not measurements, Sunlit has no sensor for either, and real weather can put them far off.",
                comment: "States plainly that UV index and irradiance are models and not measurements"))
                .font(SunlitType.body)
                .fixedSize(horizontal: false, vertical: true)

            citation(
                subject: String(localized: "credits.uv",
                                defaultValue: "UV index model",
                                comment: "Subject of the UV model citation"),
                source: "Clear sky parameterisation with an embedded total column ozone climatology")

            citation(
                subject: String(localized: "credits.irradiance",
                                defaultValue: "Irradiance model",
                                comment: "Subject of the irradiance model citation"),
                source: "Kasten and Young air mass, Haurwitz clear sky global horizontal irradiance, Erbs correlation for the direct and diffuse split")
        }
    }

    // MARK: Pieces

    /// A subject and its source. The source is set verbatim: it is a title, a
    /// report number and two surnames, and there is nothing in it to translate.
    private func citation(subject: String, source: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(subject).sunlitLabel()
            Text(verbatim: source)
                .font(SunlitType.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(subject))
        .accessibilityValue(Text(verbatim: source))
    }

    private func linkRow(title: String, url: URL?) -> some View {
        Button {
            if let url { openURL(url) }
        } label: {
            HStack(spacing: 8) {
                Text(title).font(SunlitType.body)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: SunlitLayout.minimumTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(.isLink)
    }
}
