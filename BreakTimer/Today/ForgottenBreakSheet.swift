import SwiftUI

/// "Pause vergessen zu beenden?": lets the user set the real end time of a long-running break.
struct ForgottenBreakSheet: View {
    @Environment(BreakController.self) private var controller
    @Environment(\.dismiss) private var dismiss

    let session: BreakSession
    var onKeepRunning: () -> Void
    @State private var end: Date

    init(session: BreakSession, onKeepRunning: @escaping () -> Void) {
        self.session = session
        self.onKeepRunning = onKeepRunning
        // Suggest the moment the budget would have run out, if that's in the past.
        let suggestion = session.startedAt.addingTimeInterval(TimeInterval(session.budgetMinutes * 60))
        _end = State(initialValue: min(suggestion, .now))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "clock.badge.questionmark")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.low)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("Pause vergessen zu beenden?")
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text("Deine Pause läuft seit \(session.startedAt.formatted(date: .omitted, time: .shortened)) Uhr. Wann hast du sie tatsächlich beendet?")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                DatePicker("Tatsächliches Ende", selection: $end, in: session.startedAt...Date.now)
                    .datePickerStyle(.compact)
                    .padding()
                    .glassCard(cornerRadius: 16)

                VStack(spacing: 12) {
                    Button {
                        controller.endBreak(source: .app, at: end)
                        dismiss()
                    } label: {
                        Text("Pause zu dieser Zeit beenden")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .prominentActionStyle()
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)

                    Button("Pause läuft noch") {
                        Log.info(.timer, "User kept the long-running break")
                        onKeepRunning()
                        dismiss()
                    }
                    .controlSize(.large)
                }
            }
            .padding(24)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled()
    }
}

#Preview("Dunkel") {
    let controller = BreakController.preview(.overtime)
    return ForgottenBreakSheet(session: controller.runningSession!) {}
        .environment(controller)
        .preferredColorScheme(.dark)
}

#Preview("Hell") {
    let controller = BreakController.preview(.overtime)
    return ForgottenBreakSheet(session: controller.runningSession!) {}
        .environment(controller)
        .preferredColorScheme(.light)
}
