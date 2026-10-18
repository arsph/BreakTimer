import MessageUI
import SwiftUI

/// The app's only UIKit piece: Apple's mail composer, wrapped for SwiftUI.
/// Only works on a device with a Mail account (`canSendMail`); the Simulator can't send mail.
struct MailComposer: UIViewControllerRepresentable {
    let recipients: [String]
    let subject: String
    let body: String
    let attachment: Data
    let fileName: String
    var onFinish: (MFMailComposeResult, (any Error)?) -> Void

    static var canSendMail: Bool { MFMailComposeViewController.canSendMail() }

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients(recipients)
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        controller.addAttachmentData(attachment, mimeType: "text/plain", fileName: fileName)
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    // MessageUI calls the delegate on the main thread but does not annotate it.
    @MainActor
    final class Coordinator: NSObject, @preconcurrency MFMailComposeViewControllerDelegate {
        let onFinish: (MFMailComposeResult, (any Error)?) -> Void

        init(onFinish: @escaping (MFMailComposeResult, (any Error)?) -> Void) {
            self.onFinish = onFinish
        }

        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: (any Error)?) {
            onFinish(result, error)
        }
    }
}
