import SwiftUI
import SunlitCore

/// When.
///
/// The calendar is never disabled. A locked control that cannot even be looked
/// at teaches nobody what the purchase buys, so the whole year stays open, the
/// sky behind the sheet repaints for whatever day is under the finger, and the
/// lock sits on the one control that would commit the change, with the reason
/// beside it.
struct DatePickerSheet: View {

    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale

    @State private var selection = Date()
    @State private var hasSeeded = false
    @State private var showingPaywall = false

    var body: some View {
        // The sky of the day being chosen, at the same clock time as now, so
        // the gradient answers the question before the button does.
        let moment = SkyMoment.at(JulianDay(date: previewInstant), place: state.place)
        let altitude = moment.sun.altitude

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SunlitSheetHeader(
                    title: String(
                        localized: "date.title",
                        defaultValue: "Date",
                        comment: "Title of the date picker sheet"
                    )
                )

                DatePicker(
                    selection: $selection,
                    displayedComponents: [.date]
                ) {
                    Text(pickerLabel)
                }
                .datePickerStyle(.graphical)
                .labelsHidden()
                .accessibilityLabel(Text(pickerLabel))

                HairlineDivider()

                todayButton

                confirmSection(altitude: altitude)

                Text(zoneNote)
                    .font(SunlitType.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .sunlitSheetSky(
            solarAltitude: altitude,
            moonIllumination: moment.moonPhase.illuminatedFraction
        )
        .onAppear {
            guard !hasSeeded else { return }
            selection = state.day
            hasSeeded = true
        }
    }

    // MARK: Controls

    private var todayButton: some View {
        Button {
            selection = Date()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sun.max")
                    .imageScale(.small)
                    .accessibilityHidden(true)
                Text(todayTitle).font(SunlitType.body)
                Spacer(minLength: 8)
                Text(freeTag).sunlitLabel()
            }
            .frame(minHeight: SunlitLayout.minimumTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(todayTitle))
        .accessibilityHint(Text(freeTag))
    }

    /// The confirm button is always here, in the same place, at the same size.
    ///
    /// Locked it wears a lock and leads to the paywall instead of committing,
    /// and the reason is set out directly beneath it. A control that disappears
    /// when it is gated teaches nobody what the purchase buys and makes the free
    /// app look like it is missing pieces.
    @ViewBuilder
    private func confirmSection(altitude: Double) -> some View {
        let locked = !selectionIsAllowed

        VStack(alignment: .leading, spacing: 12) {
            Button {
                if locked {
                    showingPaywall = true
                } else {
                    commit()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: locked ? "lock.fill" : "checkmark")
                        .imageScale(.small)
                        .accessibilityHidden(true)
                    Text(confirmTitle).font(SunlitType.body)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                // Inside the label, with the shape, because that is what the
                // finger lands on. Outside the button the frame grows the
                // layout and leaves the hit area at the height of the padded
                // text, which is forty points at the default type size and
                // short of the minimum for the one control this sheet exists
                // to offer.
                .frame(maxWidth: .infinity, minHeight: SunlitLayout.minimumTouchTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(
                        SkyPalette.componentBorder(solarAltitude: altitude),
                        lineWidth: 1 / displayScale
                    )
            }
            .accessibilityLabel(Text(confirmTitle))
            .accessibilityHint(Text(locked ? lockedHint : confirmHint))
            .proPaywall(isPresented: $showingPaywall)

            if locked {
                Text(gateReason)
                    .font(SunlitType.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var confirmHint: String {
        String(
            localized: "date.confirm.hint",
            defaultValue: "Applies this day to all four views.",
            comment: "Spoken hint on the confirm button in the date sheet"
        )
    }

    private var lockedHint: String {
        String(
            localized: "date.locked.hint",
            defaultValue: "Locked. Opens Sunlit Pro.",
            comment: "Spoken hint on the confirm button when another day is not unlocked"
        )
    }

    // MARK: Gate

    /// Today is free, at any place. Anything else is `anyDate`.
    private var selectionIsAllowed: Bool {
        selectedDayIsToday || state.pro.allows(.anyDate)
    }

    private var selectedDayIsToday: Bool {
        placeCalendar.isDateInToday(localInstant(for: selection))
    }

    private func commit() {
        state.day = localInstant(for: selection)
        // A day change moves the whole app; leaving the scrubber where it was
        // would show yesterday's clock time on a new date without saying so.
        state.resumeLiveTime()
        dismiss()
    }

    // MARK: Time

    private var placeCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: state.place.timeZoneIdentifier) ?? .current
        return calendar
    }

    /// The day the finger landed on, expressed in the place's own clock.
    ///
    /// The calendar hands back an instant in the device's time zone, and the
    /// place may be twelve hours away, so the year, month and day are taken and
    /// rebuilt at local noon. Noon rather than midnight because a handful of
    /// zones have no midnight on the day they enter summer time, and a date
    /// built on an hour that does not exist comes back as the wrong day.
    private func localInstant(for date: Date) -> Date {
        let fields = Calendar.current.dateComponents([.year, .month, .day], from: date)
        var target = DateComponents()
        target.year = fields.year
        target.month = fields.month
        target.day = fields.day
        target.hour = 12
        return placeCalendar.date(from: target) ?? date
    }

    /// The chosen day at the same clock time the app is currently showing.
    private var previewInstant: Date {
        let current = state.instant
        let midnight = state.place.startOfLocalDay(containing: current).date
        let secondsIntoDay = current.timeIntervalSince(midnight)
        let chosenMidnight = state.place.startOfLocalDay(containing: localInstant(for: selection)).date
        return chosenMidnight.addingTimeInterval(secondsIntoDay)
    }

    // MARK: Text

    private var pickerLabel: String {
        String(
            localized: "date.picker",
            defaultValue: "Day",
            comment: "Label of the calendar in the date sheet"
        )
    }

    private var todayTitle: String {
        String(
            localized: "date.today",
            defaultValue: "Back to today",
            comment: "Button that returns the calendar to the current day"
        )
    }

    private var freeTag: String {
        String(
            localized: "date.free",
            defaultValue: "Free",
            comment: "Marks today as costing nothing"
        )
    }

    private var confirmTitle: String {
        String(
            localized: "date.confirm",
            defaultValue: "Show this day",
            comment: "Button that applies the chosen date to every view"
        )
    }

    private var gateReason: String {
        String(
            localized: "date.gate",
            defaultValue: "Today at your current location is free forever, in all four views. Any other day is part of Sunlit Pro. The calendar stays open either way, so you can see what you would be looking at.",
            comment: "Explains why another day cannot be confirmed without the purchase"
        )
    }

    private var zoneNote: String {
        String(
            localized: "date.zone",
            defaultValue: "Days run on the clock of \(state.place.name), not on your own.",
            comment: "Explains that the selected day is interpreted in the place's own time zone"
        )
    }
}
