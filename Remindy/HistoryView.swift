import SwiftData
import SwiftUI

struct LogItem: Identifiable {
    let id = UUID()
    let time: Date
    let title: String
}

struct HistoryView: View {
    @Query private var reminders: [Reminder]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var month: Date = Calendar.current.startOfMonth()
    @State private var selectedDay: Date? = .now
    @State private var monthDirection = 0
    @State private var gridAppeared = false
    @Namespace private var dayNamespace

    private var calendar: Calendar { Calendar.current }

    private struct DayCell: Identifiable {
        let id: Int
        let date: Date?
        let week: Int
    }

    private var entriesByDay: [DateComponents: [LogItem]] {
        var map: [DateComponents: [LogItem]] = [:]
        for reminder in reminders {
            for date in reminder.log {
                let comps = calendar.dateComponents([.year, .month, .day], from: date)
                map[comps, default: []].append(LogItem(time: date, title: reminder.title))
            }
        }
        return map
    }

    private func items(for day: Date) -> [LogItem] {
        let comps = calendar.dateComponents([.year, .month, .day], from: day)
        return (entriesByDay[comps] ?? []).sorted { $0.time < $1.time }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                    weekdayRow
                    dayGrid
                } header: {
                    Text("Activity")
                } footer: {
                    Text("Every completed task and tag tap is logged here.")
                }

                if let day = selectedDay {
                    Section(dayLabel(day)) {
                        let items = items(for: day)
                        if items.isEmpty {
                            Text("Nothing logged")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(items) { item in
                                HStack {
                                    Text(item.title)
                                    Spacer()
                                    Text(item.time, style: .time)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        CalendarFlipGlyph()
                            .font(.headline)
                        Text("History")
                            .font(.headline)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sensoryFeedback(.selection, trigger: selectedDay)
            .sensoryFeedback(.selection, trigger: month)
            .onAppear {
                withAnimation(reduceMotion ? Motion.reveal : Motion.calendar) {
                    gridAppeared = true
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.title3.weight(.semibold))
                .contentTransition(.opacity)
            Spacer()
            HStack(spacing: 8) {
                monthButton("chevron.left") { shiftMonth(-1) }
                monthButton("chevron.right") { shiftMonth(1) }
            }
        }
        .padding(.vertical, 4)
        .animation(Motion.calendar, value: month)
    }

    private func monthButton(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .frame(width: 32, height: 32)
                .foregroundStyle(.primary)
                .background(.fill.tertiary, in: Circle())
        }
        .buttonStyle(PressStyle(scale: 0.92))
        .accessibilityLabel(systemImage == "chevron.left" ? "Previous month" : "Next month")
    }

    private var weekdayRow: some View {
        LazyVGrid(columns: gridColumns, spacing: 8) {
            ForEach(calendar.shortStandaloneWeekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
        }
    }

    private var dayGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 10) {
            ForEach(daysInMonth) { cell in
                if let date = cell.date {
                    DayButton(
                        date: date,
                        count: items(for: date).count,
                        isSelected: selectedDay.map { calendar.isDate(date, inSameDayAs: $0) } ?? false,
                        isToday: calendar.isDateInToday(date),
                        calendar: calendar,
                        namespace: dayNamespace
                    ) {
                        withAnimation(Motion.calendar) {
                            selectedDay = date
                        }
                    }
                    .opacity(gridAppeared ? 1 : 0)
                    .scaleEffect(gridAppeared ? 1 : 0.94)
                    .animation(
                        reduceMotion ? Motion.reveal : Motion.weekStagger(row: cell.week),
                        value: gridAppeared
                    )
                } else {
                    Color.clear.frame(height: 40)
                }
            }
        }
        .padding(.bottom, 6)
        .id(month)
        .transition(monthTransition)
        .animation(Motion.calendar, value: month)
    }

    private var monthTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        let incoming = CGFloat(monthDirection >= 0 ? 28 : -28)
        let outgoing = CGFloat(monthDirection >= 0 ? -28 : 28)
        return .asymmetric(
            insertion: .offset(x: incoming).combined(with: .opacity),
            removal: .offset(x: outgoing).combined(with: .opacity)
        )
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    }

    private var daysInMonth: [DayCell] {
        guard
            let interval = calendar.dateInterval(of: .month, for: month),
            let firstWeekday = calendar.dateComponents([.weekday], from: interval.start).weekday
        else { return [] }

        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7
        let dayCount = calendar.range(of: .day, in: .month, for: month)?.count ?? 0

        var cells: [DayCell] = (0..<leadingBlanks).map { DayCell(id: -$0 - 1, date: nil, week: 0) }
        cells += (1...dayCount).compactMap { day -> DayCell? in
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: interval.start) else { return nil }
            let week = (leadingBlanks + day - 1) / 7
            return DayCell(id: day, date: date, week: week)
        }
        return cells
    }

    private func dayLabel(_ day: Date) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month().day())
    }

    private func shiftMonth(_ delta: Int) {
        monthDirection = delta
        withAnimation(reduceMotion ? Motion.reveal : Motion.calendar) {
            month = calendar.date(byAdding: .month, value: delta, to: month) ?? month
        }
    }
}

private struct DayButton: View {
    let date: Date
    let count: Int
    let isSelected: Bool
    let isToday: Bool
    let calendar: Calendar
    var namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.callout.weight(isToday || isSelected ? .bold : .regular))
                    .frame(width: 32, height: 32)
                    .foregroundStyle(dayForeground)
                    .background {
                        if isSelected {
                            Circle()
                                .fill(isToday ? Color.accentColor : Color.accentColor.opacity(0.18))
                                .matchedGeometryEffect(id: "selected-day", in: namespace)
                        } else if isToday {
                            Circle()
                                .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1.5)
                        } else if count > 0 {
                            Circle()
                                .fill(Color.accentColor.opacity(0.08))
                        }
                    }

                HStack(spacing: 2) {
                    ForEach(0..<max(1, min(count, 3)), id: \.self) { _ in
                        Circle()
                            .fill(count > 0 ? Color.accentColor : Color.clear)
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)
            }
        }
        .buttonStyle(PressStyle(scale: 0.94))
        .accessibilityLabel(accessibilityDay)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var dayForeground: Color {
        if isSelected && isToday { return .white }
        return .primary
    }

    private var accessibilityDay: String {
        let day = date.formatted(.dateTime.weekday(.wide).month(.wide).day())
        if count == 0 { return day }
        return "\(day), \(count) logged"
    }
}
