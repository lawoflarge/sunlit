import SwiftUI
import SunlitCore

/// Place and date, above all four views.
///
/// This is the structural answer to the loudest complaint about the product
/// Sunlit competes with, where each view carries its own idea of where you are
/// and scouting a distant location means setting it four times over. There is
/// one control, it is always visible, and every view follows it.
struct GlobalHeader: View {

    @Environment(AppState.self) private var state
    @Binding var showingPlacePicker: Bool
    @Binding var showingDatePicker: Bool

    /// The solar altitude the surrounding view is currently painted for, so the
    /// header's own foreground tracks the sky behind it.
    let solarAltitude: Double

    var body: some View {
        HStack(spacing: 12) {
            Button {
                showingPlacePicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: state.isCurrentLocation ? "location.fill" : "mappin")
                        .font(.footnote)
                    Text(state.place.name)
                        .font(SunlitType.body)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            Button {
                showingDatePicker = true
            } label: {
                HStack(spacing: 6) {
                    Text(dayLabel)
                        .font(SunlitType.body)
                        .monospacedDigit()
                    if !state.isToday {
                        Image(systemName: "calendar")
                            .font(.footnote)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(SkyPalette.foreground(solarAltitude: solarAltitude))
        // A 44 point minimum on the row rather than on each label, because the
        // labels are text of unpredictable width and the row is what the finger
        // actually aims at.
        .frame(minHeight: 44)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .contain)
    }

    private var dayLabel: String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: state.place.timeZoneIdentifier) ?? .current
        if state.isToday {
            return String(localized: "header.today", defaultValue: "Today")
        }
        formatter.setLocalizedDateFormatFromTemplate("dMMM")
        return formatter.string(from: state.day)
    }
}
