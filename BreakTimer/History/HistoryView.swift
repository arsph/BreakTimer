import Charts
import SwiftUI

/// Daily totals for the last 7 or 30 days against each day's own budget.
struct HistoryView: View {
    enum Range: Int, CaseIterable, Identifiable {
        case week = 7, month = 30
        var id: Int { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .week: "7 Tage"
            case .month: "30 Tage"
            }
        }
    }

    @Environment(BreakController.self) private var controller
    @State private var range: Range = .week
    @State private var path: [DayKey] = []

    var body: some View {
        let totals = dailyTotals()
        NavigationStack(path: $path) {
            List {
                Section {
                    Picker("Zeitraum", selection: $range) {
                        ForEach(Range.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                    VStack(alignment: .leading, spacing: 16) {
                        summary(totals)
                        chart(totals)
                        legend
                    }
                    .padding(.vertical, 8)
                }

                Section("Tage") {
                    ForEach(totals.reversed()) { total in
                        NavigationLink(value: total.day) {
                            DayTotalRow(total: total)
                        }
                    }
                }
            }
            .navigationTitle("Verlauf")
            .navigationDestination(for: DayKey.self) { day in
                DayDetailView(day: day)
            }
        }
    }

    private func dailyTotals() -> [DayTotal] {
        _ = controller.revision // recompute after every change
        let today = DayKey(.now)
        let days = (0..<range.rawValue).reversed().map { today.adding(days: -$0) }
        let sessions = controller.sessions(from: days[0], through: today).map(\.snapshot)
        return BudgetEngine.dailyTotals(
            for: days, sessions: sessions, currentBudgetMinutes: controller.budgetMinutes, today: today, now: .now
        )
    }

    private func summary(_ totals: [DayTotal]) -> some View {
        let withBreaks = totals.filter { $0.used > 0 }
        let average = withBreaks.isEmpty ? 0 : withBreaks.reduce(0) { $0 + $1.used } / Double(withBreaks.count)
        let overDays = totals.filter(\.isOverBudget).count
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Durchschnitt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(Self.minutes(average))
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Über Budget")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(overDays) von \(totals.count) Tagen")
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(overDays > 0 ? Theme.overtime : .primary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func chart(_ totals: [DayTotal]) -> some View {
        Chart {
            ForEach(totals) { total in
                let start = total.day.startDate()
                let end = total.day.adding(days: 1).startDate()
                BarMark(
                    x: .value("Tag", start, unit: .day),
                    y: .value("Minuten", total.used / 60)
                )
                .foregroundStyle(total.isOverBudget ? Theme.overtime : Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .accessibilityLabel(start.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .accessibilityValue(DayTotalRow.accessibilityValue(total))

                // Each day's own budget: past days keep the budget they were tracked against.
                RuleMark(
                    xStart: .value("Beginn", start),
                    xEnd: .value("Ende", end),
                    y: .value("Budget", total.budgetMinutes)
                )
                .foregroundStyle(Color.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                .accessibilityHidden(true)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: range == .week ? 1 : 7)) { _ in
                AxisGridLine()
                AxisValueLabel(format: range == .week ? .dateTime.weekday(.abbreviated) : .dateTime.day().month(.defaultDigits), centered: true)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartYAxisLabel("Min.")
        .chartGesture { proxy in
            SpatialTapGesture().onEnded { value in
                if let date: Date = proxy.value(atX: value.location.x) {
                    path.append(DayKey(date))
                }
            }
        }
        .frame(height: 220)
        .accessibilityLabel("Pausen pro Tag")
    }

    private var legend: some View {
        let items = Group {
            legendItem("Im Budget") { Circle().fill(Theme.accent).frame(width: 8, height: 8) }
            legendItem("Über Budget") { Circle().fill(Theme.overtime).frame(width: 8, height: 8) }
            legendItem("Budget") { Rectangle().fill(Color.secondary).frame(width: 12, height: 1.5) }
        }
        // Side by side when it fits, stacked at large text sizes.
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { items }
            VStack(alignment: .leading, spacing: 6) { items }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }

    private func legendItem(_ title: LocalizedStringKey, @ViewBuilder marker: () -> some View) -> some View {
        HStack(spacing: 6) {
            marker()
            Text(title)
                .lineLimit(1)
                .fixedSize()
        }
    }

    static func minutes(_ interval: TimeInterval) -> String {
        Duration.seconds(Int(interval.rounded())).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}

struct DayTotalRow: View {
    let total: DayTotal
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout())
        layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(total.day.startDate(), format: .dateTime.weekday(.wide))
                Text(total.day.startDate(), format: .dateTime.day().month(.wide).year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer() }
            Text("\(HistoryView.minutes(total.used)) / \(total.budgetMinutes) Min.")
                .monospacedDigit()
                .foregroundStyle(total.isOverBudget ? Theme.overtime : .secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(total.day.startDate(), format: .dateTime.weekday(.wide).day().month(.wide)))
        .accessibilityValue(Self.accessibilityValue(total))
    }

    static func accessibilityValue(_ total: DayTotal) -> String {
        let used = Duration.seconds(Int(total.used)).formatted(.units(allowed: [.hours, .minutes], width: .wide))
        return total.isOverBudget
            ? String(localized: "\(used) von \(total.budgetMinutes) Minuten, über Budget")
            : String(localized: "\(used) von \(total.budgetMinutes) Minuten")
    }
}

/// The sessions of one day (read-only; today's sessions are edited on the Today screen).
struct DayDetailView: View {
    let day: DayKey
    @Environment(BreakController.self) private var controller

    var body: some View {
        _ = controller.revision
        let sessions = controller.sessions(from: day, through: day)
        let snapshots = sessions.map(\.snapshot)
        let budget = day == DayKey(.now)
            ? controller.budgetMinutes
            : BudgetEngine.budgetMinutes(for: day, sessions: snapshots, fallback: controller.budgetMinutes)
        let status = BudgetEngine.status(day: day, sessions: snapshots, budgetMinutes: budget, now: .now)

        return List {
            Section {
                HStack(spacing: 20) {
                    BudgetRing(progress: status.progress, tint: Theme.color(for: status.level), lineWidth: 8)
                        .frame(width: 64, height: 64)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(HistoryView.minutes(status.used)) von \(budget) Min.")
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                        Text(status.isOvertime
                             ? String(localized: "\(RemainingText.clock(status)) über dem Budget")
                             : String(localized: "\(DurationFormat.clock(remaining: status.remaining)) übrig"))
                            .foregroundStyle(status.isOvertime ? Theme.overtime : .secondary)
                    }
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
            }

            Section("Pausen") {
                if sessions.isEmpty {
                    Text("Keine Pausen an diesem Tag.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sessions.reversed()) { SessionRow(session: $0) }
                }
            }
        }
        .navigationTitle(day.startDate().formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("7 Tage · Dunkel") { HistoryView().previewEnvironment(.running) }
#Preview("7 Tage · Hell") { HistoryView().previewEnvironment(.overtime, appearance: .light) }
#Preview("Keine Pausen · Dunkel") { HistoryView().previewEnvironment(.empty, history: false) }
#Preview("Tag · Dunkel") {
    NavigationStack { DayDetailView(day: DayKey(.now).adding(days: -2)) }
        .previewEnvironment(.running)
}
#Preview("Tag · Hell") {
    NavigationStack { DayDetailView(day: DayKey(.now)) }
        .previewEnvironment(.overtime, appearance: .light)
}
