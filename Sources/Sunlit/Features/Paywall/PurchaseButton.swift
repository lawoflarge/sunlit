import SwiftUI

/// The primary control on the paywall.
///
/// Filled with the audited foreground ink and labelled in the ink the sky does
/// not use, so the fill clears 4.5 to 1 against every sky the palette can
/// produce and the label sits at 21 to 1 against the fill. No gradient, no
/// shadow, no glass: the instrument layer has one weight and this is it.
///
/// The price is rendered here and nowhere else on the screen, and it always
/// comes from `Product.displayPrice`. A number written into the interface is
/// wrong in nine of the ten storefronts this app ships in before anyone has
/// changed a price.
struct PurchaseButton: View {

    @Environment(\.solarAltitude) private var solarAltitude
    @ScaledMetric(relativeTo: .body) private var horizontalPadding: CGFloat = 20
    @ScaledMetric(relativeTo: .body) private var verticalPadding: CGFloat = 14
    @ScaledMetric(relativeTo: .body) private var gap: CGFloat = 10

    /// What the button does, already localised.
    let title: String
    /// The localised price, or nil while it is still being fetched.
    let price: String?
    /// True while the App Store sheet is up or the transaction is settling.
    let isBusy: Bool
    let action: () -> Void

    private var isEnabled: Bool { price != nil && !isBusy }

    var body: some View {
        Button(action: action) {
            content
                .frame(maxWidth: .infinity)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                // Inside the label, not outside the Button. A frame applied to
                // the Button pads the layout around it; the tappable region
                // belongs to the label, so the minimum has to be stated here or
                // the control merely looks 44 points tall. It also has to be
                // stated at all: both paddings are `ScaledMetric`, so at the
                // smallest text size they shrink to about 11 points each and the
                // pill measures roughly 40, under the floor, at the one setting
                // nobody thinks to check.
                .frame(minHeight: SunlitLayout.minimumTouchTarget)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(fill)
                }
                .foregroundStyle(onFill)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        // No `accessibilityElement(children: .ignore)` here. A Button is already
        // one accessibility element; wrapping it in another makes the label and
        // value below apply to the wrapper and never reach the button, and
        // VoiceOver then falls back to reading the child text. Measured on an
        // iPhone SE: with the wrapper a busy button still read out the price
        // instead of "Working", and a spinner read out as "1".
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(spokenValue))
    }

    /// Title and price side by side while they fit, stacked when they do not.
    /// Truncating either one would remove the two facts the button exists to
    /// state, and at the accessibility text sizes the horizontal form stops
    /// fitting on a 375 point screen.
    private var content: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: gap) {
                titleText
                priceText
            }
            VStack(spacing: 3) {
                titleText
                priceText
            }
        }
    }

    private var titleText: some View {
        Text(title)
            .font(SunlitType.body)
            .fontWeight(.semibold)
    }

    /// Busy wins over the price. A purchase in flight has to show motion, or a
    /// button that has merely dimmed looks like a button that did nothing and
    /// invites a second tap into an open App Store sheet.
    @ViewBuilder
    private var priceText: some View {
        if isBusy {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(onFill)
        } else if let price {
            Text(price)
                .font(SunlitType.body)
                .fontWeight(.semibold)
                .monospacedDigit()
        } else {
            Text(String(
                localized: "paywall.price.loading",
                defaultValue: "Loading the price",
                comment: "Stands in for the price while StoreKit is still answering"))
                .font(SunlitType.caption)
        }
    }

    private var fill: Color {
        isEnabled
            ? SkyPalette.foreground(solarAltitude: solarAltitude)
            : SkyColors.disabled(solarAltitude: solarAltitude)
    }

    /// The ink the sky is not using. The palette flips its foreground between
    /// pure white and pure black at the crossover, so the opposite pure value is
    /// always the maximum contrast label for a fill made of that foreground.
    private var onFill: Color {
        solarAltitude < SkyPalette.inkCrossoverAltitude ? .black : .white
    }

    private var spokenValue: String {
        if isBusy {
            return String(
                localized: "paywall.purchase.busy",
                defaultValue: "Working",
                comment: "Spoken while a purchase is in flight")
        }
        guard let price else {
            return String(
                localized: "paywall.price.loading",
                defaultValue: "Loading the price",
                comment: "Stands in for the price while StoreKit is still answering")
        }
        return price
    }
}

/// The secondary control: restore, and retry.
///
/// A bordered capsule rather than a filled one, using the boundary stroke that
/// clears 3 to 1 against every sky, which is what WCAG 1.4.11 asks of the
/// visible edge of a control. The instrument line at 55 percent does not reach
/// that and is for rules only.
struct PaywallSecondaryButton: View {

    @Environment(\.solarAltitude) private var solarAltitude
    @Environment(\.displayScale) private var displayScale
    @ScaledMetric(relativeTo: .body) private var horizontalPadding: CGFloat = 18
    @ScaledMetric(relativeTo: .body) private var verticalPadding: CGFloat = 11

    let title: String
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(SunlitType.body)
                    // "Restore purchase" becomes "Kauf wiederherstellen" and
                    // "Restaurar la compra"; without this the longest of the ten
                    // truncates instead of wrapping at the accessibility sizes.
                    .fixedSize(horizontal: false, vertical: true)
                if isBusy {
                    ProgressView()
                        .progressViewStyle(.circular)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            // After the padding, so the floor raises a small control and never
            // inflates one that already clears it. Measured, not assumed: body
            // leading is about 20 points and the scaled padding about 11 each, so
            // this capsule stood 42 points tall at the default text size and
            // about 35 at the smallest. Restore is a control App Review presses,
            // and it was under the floor.
            .frame(
                minWidth: SunlitLayout.minimumTouchTarget,
                minHeight: SunlitLayout.minimumTouchTarget)
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(
                        SkyPalette.componentBorder(solarAltitude: solarAltitude),
                        lineWidth: 1 / displayScale)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        // See PurchaseButton: never wrap a Button in another accessibility
        // element, or these two modifiers land on the wrapper.
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(isBusy ? busyValue : ""))
    }

    private var busyValue: String {
        String(
            localized: "paywall.purchase.busy",
            defaultValue: "Working",
            comment: "Spoken while a purchase is in flight")
    }
}
