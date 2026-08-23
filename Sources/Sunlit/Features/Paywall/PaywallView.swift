import SwiftUI
import SunlitCore

/// What is free, then what costs money, then the price. In that order.
///
/// The order is the whole argument. A paywall that opens with a price is asking
/// for a decision before it has said what the free app is, and the free app here
/// is not a teaser: today at your current location, in all four views, forever.
/// So that list is written out in full first, honestly, and only then does the
/// screen say what the purchase adds.
///
/// Everything scrolls. There is no primary control pinned below a fixed layout,
/// because App Review runs at the largest Dynamic Type size on the smallest
/// supported device and a purchase button under the fold has taken down two apps
/// in this portfolio.
struct PaywallView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.solarAltitude) private var solarAltitude
    @Environment(AppState.self) private var state

    /// The service the app injects at launch, so the `Transaction.updates`
    /// listener has been running since before this screen existed.
    @Environment(StoreService.self) private var injectedStore: StoreService?

    /// A service of this screen's own, made only if nothing was injected. The
    /// paywall must work even when it is presented from a context that never set
    /// one up; a purchase screen that silently does nothing is worse than a
    /// missing one.
    @State private var ownedStore: StoreService?

    private var store: StoreService? { injectedStore ?? ownedStore }

    /// Whether Pro is already owned.
    ///
    /// `ProGate` is asked first, because it is the object the rest of the app
    /// asks and it is already correct by the time this screen opens. Reading only
    /// this screen's own service would show "Unlock everything" to someone who
    /// owns it, for as long as a freshly built service takes to finish its first
    /// entitlement pass.
    private var isUnlocked: Bool {
        state.pro.isPurchased || store?.isEntitled == true
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            HairlineDivider()
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    intro
                    freeSection
                    proSection
                    priceSection
                    legalSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .adaptiveSky(solarAltitude: solarAltitude)
        .task {
            if injectedStore == nil, ownedStore == nil {
                ownedStore = StoreService(gate: state.pro)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Text(String(
                localized: "paywall.title",
                defaultValue: "Sunlit Pro",
                comment: "Title of the purchase screen"))
                .font(SunlitType.title)
                // Every other Text on this screen already wraps. This one sits in
                // an HStack beside a 44 point button, which is exactly where a
                // Text truncates at the accessibility sizes instead.
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 8)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .sunlitTouchTarget()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(String(
                localized: "paywall.close",
                defaultValue: "Close",
                comment: "Dismisses the purchase screen")))
        }
        .frame(minHeight: SunlitLayout.minimumTouchTarget)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private var intro: some View {
        Text(String(
            localized: "paywall.intro",
            defaultValue: "Sunlit is free to install and free to use. Here is exactly what that means, and what the one purchase adds.",
            comment: "Opening line of the purchase screen"))
            .font(SunlitType.body)
    }

    // MARK: 1. What stays free

    private var freeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            PaywallHeading(
                title: String(
                    localized: "paywall.free.heading",
                    defaultValue: "Free, forever",
                    comment: "Heading of the list of things that never cost money"),
                note: String(
                    localized: "paywall.free.note",
                    defaultValue: "No account, no advertising, nothing collected. This is not a trial and it does not expire.",
                    comment: "Caption under the free heading"))

            VStack(alignment: .leading, spacing: 14) {
                ForEach(freeItems) { item in
                    PaywallFeatureRow(item: item)
                }
            }
        }
    }

    /// The actual free tier, written out. Not a selection of it.
    private var freeItems: [PaywallItem] {
        [
            PaywallItem(
                symbol: "checkmark",
                title: String(
                    localized: "paywall.free.today",
                    defaultValue: "Today at your current location, in all four views",
                    comment: "Free tier item")),
            PaywallItem(
                symbol: "checkmark",
                title: String(
                    localized: "paywall.free.position",
                    defaultValue: "Where the sun is now: azimuth and altitude, live",
                    comment: "Free tier item")),
            PaywallItem(
                symbol: "checkmark",
                title: String(
                    localized: "paywall.free.compass",
                    defaultValue: "The compass and the sun path in the camera view",
                    comment: "Free tier item")),
            PaywallItem(
                symbol: "checkmark",
                title: String(
                    localized: "paywall.free.sunriseSunset",
                    defaultValue: "Sunrise and sunset, with their directions",
                    comment: "Free tier item")),
            PaywallItem(
                symbol: "checkmark",
                title: String(
                    localized: "paywall.free.twilight",
                    defaultValue: "Civil, nautical and astronomical twilight",
                    comment: "Free tier item")),
            PaywallItem(
                symbol: "checkmark",
                title: String(
                    localized: "paywall.free.goldenBlue",
                    defaultValue: "Golden hour and blue hour, morning and evening",
                    comment: "Free tier item")),
            PaywallItem(
                symbol: "checkmark",
                title: String(
                    localized: "paywall.free.noonLength",
                    defaultValue: "Solar noon, day length, and how much it changed since yesterday",
                    comment: "Free tier item")),
            PaywallItem(
                symbol: "checkmark",
                title: String(
                    localized: "paywall.free.shadow",
                    defaultValue: "Shadow length and direction",
                    comment: "Free tier item")),
            PaywallItem(
                symbol: "checkmark",
                title: String(
                    localized: "paywall.free.uv",
                    defaultValue: "UV index and solar irradiance for today",
                    comment: "Free tier item"),
                note: String(
                    localized: "paywall.free.uv.note",
                    defaultValue: "Clear sky models, not measurements. Sunlit says so wherever they appear.",
                    comment: "Mandatory honesty caption: UV and irradiance are modelled, not measured")),
            PaywallItem(
                symbol: "checkmark",
                title: String(
                    localized: "paywall.free.offline",
                    defaultValue: "Every figure computed on your device, no account, no tracking",
                    comment: "Free tier item")),
        ]
    }

    // MARK: 2. What the purchase adds

    private var proSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            PaywallHeading(
                title: String(
                    localized: "paywall.pro.heading",
                    defaultValue: "What the purchase adds",
                    comment: "Heading of the list of paid capabilities"),
                note: String(
                    localized: "paywall.pro.note",
                    defaultValue: "Everything below works offline too.",
                    comment: "Caption under the paid heading"))

            // Driven off the capability list itself, so this screen cannot
            // promise a capability the gate does not know about, and cannot
            // quietly stop mentioning one that it does.
            VStack(alignment: .leading, spacing: 16) {
                ForEach(ProCapability.allCases, id: \.self) { capability in
                    PaywallFeatureRow(item: PaywallItem(
                        symbol: capability.paywallSymbol,
                        title: capability.paywallTitle,
                        note: capability.paywallDetail))
                }
            }
        }
    }

    // MARK: 3. The price, once

    private var priceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isUnlocked {
                unlockedBlock
            } else {
                purchaseBlock
            }

            if let outcome = store?.outcome {
                PaywallNotice(
                    message: outcome.message,
                    needsAttention: outcome.needsAttention)
            }

            restoreBlock
        }
    }

    private var purchaseBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            // When the product could not be fetched there is no price and no
            // purchase to offer, so the screen says why and offers a retry
            // instead of a dead button that claims to be loading something it
            // has already given up on.
            if case .unavailable(let reason)? = store?.availability {
                PaywallNotice(message: reason, needsAttention: true)
                PaywallSecondaryButton(
                    title: String(
                        localized: "paywall.price.retry",
                        defaultValue: "Try again",
                        comment: "Retries loading the product from the App Store"),
                    isBusy: false
                ) {
                    Task { await store?.loadProduct() }
                }
            } else {
                PurchaseButton(
                    title: String(
                        localized: "paywall.action.unlock",
                        defaultValue: "Unlock everything",
                        comment: "The purchase button"),
                    price: store?.displayPrice,
                    isBusy: store?.isPurchasing ?? false
                ) {
                    Task { await store?.purchase() }
                }
            }

            Text(String(
                localized: "paywall.price.terms",
                defaultValue: "One time purchase. Nothing renews, and there is nothing to cancel. It stays unlocked on every device signed in to the same Apple ID.",
                comment: "Caption under the purchase button"))
                .font(SunlitType.caption)
        }
    }

    private var unlockedBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            PaywallHeading(
                title: String(
                    localized: "paywall.owned.heading",
                    defaultValue: "Unlocked",
                    comment: "Heading shown when the purchase is already owned"),
                note: String(
                    localized: "paywall.owned.note",
                    defaultValue: "Sunlit Pro is active on this Apple ID. Thank you.",
                    comment: "Caption shown when the purchase is already owned"))

            PaywallSecondaryButton(
                title: String(
                    localized: "paywall.owned.continue",
                    defaultValue: "Continue",
                    comment: "Closes the purchase screen after a successful purchase"),
                isBusy: false
            ) {
                dismiss()
            }
        }
    }

    private var restoreBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            PaywallSecondaryButton(
                title: String(
                    localized: "paywall.action.restore",
                    defaultValue: "Restore purchase",
                    comment: "Restores a purchase made previously on this Apple ID"),
                isBusy: store?.isRestoring ?? false
            ) {
                Task { await store?.restore() }
            }

            Text(String(
                localized: "paywall.restore.note",
                defaultValue: "If you bought Sunlit Pro before, restore it here. Restoring asks for your Apple ID password.",
                comment: "Caption under the restore button"))
                .font(SunlitType.caption)
        }
    }

    // MARK: 4. Legal

    private var legalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HairlineDivider()

            PaywallLinkRow(
                title: String(
                    localized: "paywall.legal.privacy",
                    defaultValue: "Privacy policy",
                    comment: "Link to the privacy policy"),
                destination: PaywallLinks.privacy)

            PaywallLinkRow(
                title: String(
                    localized: "paywall.legal.terms",
                    defaultValue: "Terms of use",
                    comment: "Link to the standard Apple end user licence agreement"),
                destination: PaywallLinks.terms)

            Text(String(
                localized: "paywall.legal.note",
                defaultValue: "Payment is taken by the App Store when you confirm the purchase.",
                comment: "Caption under the legal links"))
                .font(SunlitType.caption)
        }
    }
}

// MARK: - Pieces

/// One line of a feature list: a mark, a claim, and optionally the honest
/// qualification that goes with it.
private struct PaywallItem: Identifiable {
    let symbol: String
    let title: String
    let note: String?

    init(symbol: String, title: String, note: String? = nil) {
        self.symbol = symbol
        self.title = title
        self.note = note
    }

    var id: String { title }
}

private struct PaywallFeatureRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 24

    let item: PaywallItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            // Dropped at the accessibility sizes. It is decorative, it is
            // already hidden from VoiceOver, and at those sizes it would take a
            // fifth of a 375 point screen away from the sentence beside it.
            if !typeSize.isAccessibilitySize {
                Image(systemName: item.symbol)
                    .imageScale(.medium)
                    .frame(width: iconWidth, alignment: .leading)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(SunlitType.body)
                    .fixedSize(horizontal: false, vertical: true)
                if let note = item.note {
                    Text(note)
                        .font(SunlitType.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spoken))
    }

    private var spoken: String {
        guard let note = item.note else { return item.title }
        return item.title + ". " + note
    }
}

private struct PaywallHeading: View {
    let title: String
    let note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(SunlitType.title)
                .fixedSize(horizontal: false, vertical: true)
            if let note {
                Text(note)
                    .font(SunlitType.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(note.map { title + ". " + $0 } ?? title))
        .accessibilityAddTraits(.isHeader)
    }
}

/// A result or a fault, stated in a box.
///
/// The attention state fills with the warning colour and carries its own dark
/// ink, which is the one element in this system allowed to ignore the sky: at
/// 8.9 to 1 against its own fill it survives every solar altitude, and a warning
/// the sky can wash out is not a warning.
private struct PaywallNotice: View {
    @Environment(\.solarAltitude) private var solarAltitude
    @Environment(\.displayScale) private var displayScale

    let message: String
    let needsAttention: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: needsAttention ? "exclamationmark.triangle.fill" : "info.circle")
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(message)
                .font(SunlitType.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background {
            if needsAttention {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(SkyColors.warning)
            }
        }
        .overlay {
            if !needsAttention {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        SkyPalette.componentBorder(solarAltitude: solarAltitude),
                        lineWidth: 1 / displayScale)
            }
        }
        .foregroundStyle(needsAttention
            ? SkyColors.onWarning
            : SkyPalette.foreground(solarAltitude: solarAltitude))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(message))
    }
}

/// A legal link. Apple requires the terms to be reachable from the purchase
/// screen, and a dead or missing legal link under a purchase button has already
/// cost this portfolio a rejection.
private struct PaywallLinkRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize

    let title: String
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(SunlitType.body)
                    .fixedSize(horizontal: false, vertical: true)
                // Dropped at the accessibility sizes. The label wraps to two or
                // three lines there and a baseline aligned glyph then sits in the
                // middle of the sentence, which reads as a rendering fault.
                if !typeSize.isAccessibilitySize {
                    Image(systemName: "arrow.up.right")
                        .imageScale(.small)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 0)
            }
            .sunlitTouchTarget()
        }
        // A Link is already one accessibility element. Wrapping it would put
        // this label on the wrapper and leave the link reading its raw contents.
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(.isLink)
    }
}

private enum PaywallLinks {
    static let privacy = URL(string: "https://sunlit-app.vercel.app/privacy.html")!
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}

// MARK: - The capabilities, named

/// The paid list is generated from `ProCapability`, so it cannot drift from the
/// gate. Each sentence describes only what the app actually does; a paywall that
/// promises a capability with no code behind it is the exact failure that three
/// apps in this portfolio shipped.
private extension ProCapability {

    var paywallSymbol: String {
        switch self {
        case .anyDate: return "calendar"
        case .savedPlaces: return "mappin.and.ellipse"
        case .moon: return "moon.stars"
        case .milkyWay: return "sparkles"
        case .annualPaths: return "chart.xyaxis.line"
        case .terrain: return "mountain.2"
        case .eclipses: return "circle.lefthalf.filled"
        case .widgets: return "square.grid.2x2"
        case .notifications: return "bell"
        case .export: return "square.and.arrow.up"
        }
    }

    var paywallTitle: String {
        switch self {
        case .anyDate:
            return String(
                localized: "paywall.capability.anyDate.title",
                defaultValue: "Any date, past or future",
                comment: "Paid capability")
        case .savedPlaces:
            return String(
                localized: "paywall.capability.savedPlaces.title",
                defaultValue: "Any place, and saved places",
                comment: "Paid capability")
        case .moon:
            return String(
                localized: "paywall.capability.moon.title",
                defaultValue: "The moon",
                comment: "Paid capability")
        case .milkyWay:
            return String(
                localized: "paywall.capability.milkyWay.title",
                defaultValue: "The Milky Way",
                comment: "Paid capability")
        case .annualPaths:
            return String(
                localized: "paywall.capability.annualPaths.title",
                defaultValue: "Annual paths",
                comment: "Paid capability")
        case .terrain:
            return String(
                localized: "paywall.capability.terrain.title",
                defaultValue: "Your measured horizon",
                comment: "Paid capability")
        case .eclipses:
            return String(
                localized: "paywall.capability.eclipses.title",
                defaultValue: "Eclipses",
                comment: "Paid capability")
        case .widgets:
            return String(
                localized: "paywall.capability.widgets.title",
                defaultValue: "Widgets",
                comment: "Paid capability")
        case .notifications:
            return String(
                localized: "paywall.capability.notifications.title",
                defaultValue: "Event notifications",
                comment: "Paid capability")
        case .export:
            return String(
                localized: "paywall.capability.export.title",
                defaultValue: "Export",
                comment: "Paid capability")
        }
    }

    var paywallDetail: String {
        switch self {
        case .anyDate:
            return String(
                localized: "paywall.capability.anyDate.detail",
                defaultValue: "Scout a shoot months ahead, or read back a day from years ago.",
                comment: "Paid capability detail")
        case .savedPlaces:
            return String(
                localized: "paywall.capability.savedPlaces.detail",
                defaultValue: "Search over 30,000 cities offline, drop a pin anywhere, and keep the places you work at.",
                comment: "Paid capability detail")
        case .moon:
            return String(
                localized: "paywall.capability.moon.detail",
                defaultValue: "Phase, illuminated fraction, distance, rise and set, its path in every view, and the phase calendar.",
                comment: "Paid capability detail")
        case .milkyWay:
            return String(
                localized: "paywall.capability.milkyWay.detail",
                defaultValue: "The galactic centre, the galactic plane, and a real visibility window that names what is limiting it.",
                comment: "Paid capability detail")
        case .annualPaths:
            return String(
                localized: "paywall.capability.annualPaths.detail",
                defaultValue: "Summer solstice, winter solstice and equinox paths drawn as reference, plus the year's altitude curve.",
                comment: "Paid capability detail")
        case .terrain:
            return String(
                localized: "paywall.capability.terrain.detail",
                defaultValue: "Sweep your skyline with the camera, then get sunrise and sunset over that skyline and every period the sun is behind it.",
                comment: "Paid capability detail")
        case .eclipses:
            return String(
                localized: "paywall.capability.eclipses.detail",
                defaultValue: "Solar and lunar, with contact times, magnitude and obscuration as seen from where you are.",
                comment: "Paid capability detail")
        case .widgets:
            return String(
                localized: "paywall.capability.widgets.detail",
                defaultValue: "Home screen and lock screen: the next event, the day's arc, and the golden hour countdown.",
                comment: "Paid capability detail")
        case .notifications:
            return String(
                localized: "paywall.capability.notifications.detail",
                defaultValue: "Alerts for sun and moon events, scheduled on your device.",
                comment: "Paid capability detail")
        case .export:
            return String(
                localized: "paywall.capability.export.detail",
                defaultValue: "Take the day's tabulation with you as a spreadsheet or as an image.",
                comment: "Paid capability detail")
        }
    }
}

// MARK: - Previews

#if DEBUG
private func previewState() -> AppState {
    AppState(place: Place(
        name: "Berlin",
        geographic: Coordinates.Geographic(latitude: 52.52, longitude: 13.405, elevation: 34),
        timeZoneIdentifier: "Europe/Berlin",
        isCurrentLocation: true))
}

#Preview("Paywall, full day") {
    PaywallView()
        .environment(previewState())
        .environment(\.solarAltitude, 45)
}

#Preview("Paywall, night, accessibility 5") {
    PaywallView()
        .environment(previewState())
        .environment(\.solarAltitude, -30)
        .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
