import MessageUI
import SwiftUI
import UIKit

/// Settings → Support: send the log to support, delete it, verbose logging, log size.
struct SupportSection: View {
    @Environment(BreakController.self) private var controller
    @Environment(AppSettings.self) private var settings
    @Environment(AuthService.self) private var auth
    @Environment(SyncService.self) private var sync
    @Environment(SettingsPresentation.self) private var presentation

    @State private var isPreparing = false
    @State private var logSize = 0
    @State private var confirmClear = false
    @State private var errorMessage: String?

    var body: some View {
        @Bindable var settings = settings
        Section {
            Button(action: prepareReport) {
                HStack {
                    Label("Protokoll an Support senden", systemImage: "envelope")
                    Spacer()
                    if isPreparing { ProgressView() }
                }
            }
            .disabled(isPreparing)

            Toggle("Ausführliche Protokollierung", isOn: $settings.verboseLogging)
            LabeledContent("Protokollgröße", value: logSize.formatted(.byteCount(style: .file)))
            Button("Protokoll löschen", role: .destructive) { confirmClear = true }
        } header: {
            Text("Support")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.overtime)
                }
                Text("Das Protokoll enthält technische Daten und Pausenzeiten, aber keine Passwörter.")
            }
        }
        .onAppear(perform: refreshSize)
        .onChange(of: presentation.sheet == nil) { refreshSize() }
        .confirmationDialog("Protokoll löschen?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Protokoll löschen", role: .destructive) {
                Task {
                    await LogFiles.deleteAll()
                    Log.info(.support, "Log deleted by the user")
                    await Log.writer.flush()
                    refreshSize()
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Das Protokoll hilft dem Support bei der Fehlersuche. Es wird nur auf diesem iPhone gelöscht.")
        }
    }

    private func prepareReport() {
        isPreparing = true
        errorMessage = nil
        let context = LogExporter.Context(
            maskedEmail: auth.account?.maskedEmail ?? "-",
            userID: auth.account?.id.uuidString ?? "-",
            budgetMinutes: controller.budgetMinutes,
            lastSuccessfulSync: sync.lastSuccessfulSync,
            unsyncedItems: sync.unsyncedCount
        )
        Task {
            defer { isPreparing = false }
            do {
                let report = try await LogExporter.makeReport(context: context)
                if MailComposer.canSendMail {
                    Log.info(.support, "Support report prepared (\(report.data.count) bytes), opening Mail")
                    presentation.sheet = .mail(report)
                } else {
                    Log.info(.support, "Support report prepared (\(report.data.count) bytes), Mail not set up, opening share sheet")
                    presentation.sheet = .share(report)
                }
            } catch {
                Log.error(.support, "Preparing the support report failed", error: error)
                errorMessage = String(localized: "Das Protokoll konnte nicht erstellt werden.")
            }
        }
    }

    private func refreshSize() {
        logSize = LogFiles.totalSize()
    }
}

/// Fallback when Mail isn't set up: share the file with any app and copy the support address.
struct ShareReportView: View {
    let report: SupportReport
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Image(systemName: "envelope.badge.shield.half.filled")
                        .font(.system(size: 44))
                        .foregroundStyle(Theme.accent)
                        .padding(.top, 12)
                        .accessibilityHidden(true)

                    Text("Auf diesem iPhone ist Mail nicht eingerichtet. Teile das Protokoll mit einer beliebigen Mail-App.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)

                    if let address = SupportReport.supportEmail {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Support-Adresse")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack {
                                Text(address)
                                    .font(.body.monospaced())
                                    .textSelection(.enabled)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                Spacer()
                                Button {
                                    UIPasteboard.general.string = address
                                    copied = true
                                    Log.info(.support, "Support address copied")
                                } label: {
                                    Label(copied ? "Kopiert" : "Kopieren", systemImage: copied ? "checkmark" : "doc.on.doc")
                                }
                                .secondaryActionStyle()
                                .sensoryFeedback(.success, trigger: copied)
                            }
                        }
                        .padding(16)
                        .glassCard(cornerRadius: 16)
                    }

                    ShareLink(
                        item: report.fileURL,
                        subject: Text(SupportReport.subject),
                        message: Text(SupportReport.mailBody)
                    ) {
                        Label("Protokoll teilen", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .prominentActionStyle()
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .simultaneousGesture(TapGesture().onEnded {
                        Log.info(.support, "Support report handed to the share sheet")
                    })

                    Text(report.fileName)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Protokoll senden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}

/// Sheets of the Settings screen. Presented from the Form itself: sheets attached to rows inside
/// a Form are torn down when SwiftUI rebuilds those rows.
@Observable
@MainActor
final class SettingsPresentation {
    enum Sheet: Identifiable {
        case mail(SupportReport), share(SupportReport), changePassword

        var id: String {
            switch self {
            case .mail(let report), .share(let report): report.id.uuidString
            case .changePassword: "changePassword"
            }
        }

        var report: SupportReport? {
            switch self {
            case .mail(let report), .share(let report): report
            case .changePassword: nil
            }
        }
    }

    var sheet: Sheet? {
        didSet { if let report = sheet?.report { presentedReport = report } }
    }

    /// The export shown by the current sheet; deleted once the sheet is dismissed.
    private var presentedReport: SupportReport?

    @ViewBuilder
    func content(for sheet: Sheet) -> some View {
        switch sheet {
        case .mail(let report):
            MailComposer(
                recipients: SupportReport.supportEmail.map { [$0] } ?? [],
                subject: SupportReport.subject,
                body: SupportReport.mailBody,
                attachment: report.data,
                fileName: report.fileName
            ) { [weak self] result, error in
                Self.logMailResult(result, error: error)
                self?.sheet = nil
            }
            .ignoresSafeArea()
        case .share(let report):
            ShareReportView(report: report)
        case .changePassword:
            NewPasswordView(purpose: .change)
        }
    }

    func didDismiss() {
        if let report = presentedReport {
            LogExporter.delete(report)
            presentedReport = nil
        }
    }

    private static func logMailResult(_ result: MFMailComposeResult, error: (any Error)?) {
        switch result {
        case .sent: Log.info(.support, "Support report sent via Mail")
        case .saved: Log.info(.support, "Support report saved as Mail draft")
        case .cancelled: Log.info(.support, "Support report mail cancelled")
        case .failed: Log.error(.support, "Support report mail failed: \(error.map(Log.describe) ?? "unknown error")")
        @unknown default: Log.warn(.support, "Support report mail finished with unknown result \(result.rawValue)")
        }
    }
}

#Preview("Teilen · Dunkel") {
    ShareReportView(report: SupportReport(fileURL: URL(filePath: "/tmp/BreakTimer-Log-2026-10-18-1640.txt"), data: Data()))
        .preferredColorScheme(.dark)
}

#Preview("Teilen · Hell") {
    ShareReportView(report: SupportReport(fileURL: URL(filePath: "/tmp/BreakTimer-Log-2026-10-18-1640.txt"), data: Data()))
        .preferredColorScheme(.light)
}
