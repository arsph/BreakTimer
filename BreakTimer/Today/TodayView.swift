import SwiftUI

struct TodayView: View {
    @Environment(BreakController.self) private var controller
    @State private var editing: BreakSession?
    @State private var pendingDelete: BreakSession?
    @State private var forgotten: BreakSession?
    @State private var dismissedForgottenID: UUID?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    BudgetHeaderView()
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }

                Section {
                    if controller.activeSessions.isEmpty {
                        Text("Noch keine Pausen heute.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(controller.activeSessions.reversed()) { session in
                            SessionRow(session: session)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button("Löschen", systemImage: "trash", role: .destructive) {
                                        pendingDelete = session
                                    }
                                    Button("Bearbeiten", systemImage: "pencil") {
                                        editing = session
                                    }
                                    .tint(.gray)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { editing = session }
                        }
                    }
                } header: {
                    Text(controller.activeDay == DayKey(.now) ? "Heutige Pausen" : "Pausen vom \(controller.activeDay.startDate().formatted(date: .abbreviated, time: .omitted))")
                }
            }
            .navigationTitle("Heute")
            .sheet(item: $editing) { session in
                EditSessionSheet(session: session)
            }
            .sheet(item: $forgotten) { session in
                ForgottenBreakSheet(session: session) {
                    dismissedForgottenID = session.id
                }
            }
            .confirmationDialog(
                "Pause löschen?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { session in
                Button("Pause löschen", role: .destructive) { controller.delete(session) }
                Button("Abbrechen", role: .cancel) {}
            } message: { session in
                Text("Die Pause von \(session.startedAt.formatted(date: .omitted, time: .shortened)) wird endgültig entfernt.")
            }
            .task(id: controller.runningSession?.id) {
                await watchForForgottenBreak()
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                Log.info(.lifecycle, "Calendar day changed")
                controller.refresh()
            }
        }
    }

    /// Shows "Pause vergessen zu beenden?" once the running break passes 2 hours.
    private func watchForForgottenBreak() async {
        guard let session = controller.runningSession, session.id != dismissedForgottenID else { return }
        let due = session.startedAt.addingTimeInterval(BudgetRules.forgottenThreshold)
        let delay = due.timeIntervalSinceNow
        if delay > 0 {
            do { try await Task.sleep(for: .seconds(delay + 1)) } catch { return }
        }
        guard let running = controller.runningSession, running.id == session.id,
              BudgetEngine.isLikelyForgotten(running.snapshot, now: .now) else { return }
        Log.info(.timer, "Break running for over 2 hours, asking whether it was forgotten")
        forgotten = running
    }
}

#Preview("Keine Pausen · Dunkel") { TodayView().previewEnvironment(.empty) }
#Preview("Läuft · Dunkel") { TodayView().previewEnvironment(.running) }
#Preview("Unter 5 Min. · Dunkel") { TodayView().previewEnvironment(.low) }
#Preview("Überzogen · Dunkel") { TodayView().previewEnvironment(.overtime) }
#Preview("Keine Pausen · Hell") { TodayView().previewEnvironment(.empty, appearance: .light) }
#Preview("Läuft · Hell") { TodayView().previewEnvironment(.running, appearance: .light) }
#Preview("Unter 5 Min. · Hell") { TodayView().previewEnvironment(.low, appearance: .light) }
#Preview("Überzogen · Hell") { TodayView().previewEnvironment(.overtime, appearance: .light) }
