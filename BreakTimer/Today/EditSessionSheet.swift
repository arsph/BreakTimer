import SwiftUI

/// Edit start/end of one of today's sessions, or delete it.
struct EditSessionSheet: View {
    @Environment(BreakController.self) private var controller
    @Environment(\.dismiss) private var dismiss

    let session: BreakSession
    @State private var start: Date
    @State private var end: Date
    @State private var error: SessionEditError?
    @State private var confirmDelete = false

    init(session: BreakSession) {
        self.session = session
        _start = State(initialValue: session.startedAt)
        _end = State(initialValue: session.endedAt ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Beginn", selection: $start, in: dayRange, displayedComponents: .hourAndMinute)
                    if session.isRunning {
                        LabeledContent("Ende", value: String(localized: "läuft noch"))
                    } else {
                        DatePicker("Ende", selection: $end, in: start...Date.now, displayedComponents: .hourAndMinute)
                    }
                    LabeledContent("Dauer", value: SessionRow.duration(max(0, (session.isRunning ? Date.now : end).timeIntervalSince(start))))
                } footer: {
                    if let message = validationMessage {
                        Text(message)
                            .foregroundStyle(Theme.overtime)
                    }
                }

                Section {
                    Button("Pause löschen", role: .destructive) { confirmDelete = true }
                }
            }
            .navigationTitle("Pause bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern", action: save)
                        .disabled(validationMessage != nil)
                }
            }
            .confirmationDialog("Pause löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Pause löschen", role: .destructive) {
                    controller.delete(session)
                    dismiss()
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Die Pause wird endgültig entfernt.")
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Times can move within the session's day, up to now.
    private var dayRange: ClosedRange<Date> {
        let dayStart = session.dayKey.startDate()
        return dayStart...max(dayStart, Date.now)
    }

    private var validationMessage: String? {
        let issue = BudgetEngine.validateEdit(
            sessionID: session.id,
            start: start,
            end: session.isRunning ? nil : end,
            sessions: controller.activeSessions.map(\.snapshot),
            now: .now
        ) ?? error
        return issue.map(Self.message)
    }

    static func message(for error: SessionEditError) -> String {
        switch error {
        case .endBeforeStart: String(localized: "Das Ende muss nach dem Beginn liegen.")
        case .startInFuture: String(localized: "Der Beginn darf nicht in der Zukunft liegen.")
        case .endInFuture: String(localized: "Das Ende darf nicht in der Zukunft liegen.")
        case .overlapsOtherSession: String(localized: "Die Pause überschneidet sich mit einer anderen Pause.")
        }
    }

    private func save() {
        do {
            try controller.update(session, start: start, end: session.isRunning ? nil : end)
            dismiss()
        } catch {
            self.error = error
        }
    }
}

#Preview("Dunkel") {
    let controller = BreakController.preview(.running)
    return EditSessionSheet(session: controller.activeSessions[0])
        .environment(controller)
        .preferredColorScheme(.dark)
}

#Preview("Hell") {
    let controller = BreakController.preview(.overtime)
    return EditSessionSheet(session: controller.activeSessions[1])
        .environment(controller)
        .preferredColorScheme(.light)
}
