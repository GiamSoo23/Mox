import AppKit
import MoxCore

/// Receiving text (#101): it goes on the pasteboard as text, and no file is saved.
extension MenuBarController {
    func receiveText(_ item: CurrentFile) {
        guard let supabase else { return }
        showStatus("Receiving text…")
        Task {
            do {
                let text = try await supabase.downloadText()
                await MainActor.run {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    self.showStatus("Text from \(item.sourceName) copied to the clipboard")
                    Notifier.show(title: "Text from \(item.sourceName) · copied", body: TextPayload.preview(text))
                }
            } catch {
                await MainActor.run { self.showError("Receiving text failed: \(error.localizedDescription)") }
            }
        }
    }

    /// The menu entries for a text in the slot.
    func addTextItems(_ item: CurrentFile, to menu: NSMenu) {
        let title = NSMenuItem(title: "Text from \(item.sourceName)", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        let copy = NSMenuItem(title: "Copy Text", action: #selector(copyCurrentText), keyEquivalent: "")
        copy.target = self
        menu.addItem(copy)
    }

    @objc func copyCurrentText() {
        guard let current else { return }
        receiveText(current)
    }

    @objc func sendCopiedText() {
        NotificationCenter.default.post(name: .moxSendText, object: nil)
    }
}

extension Notification.Name {
    static let moxSendText = Notification.Name("MoxSendText")
}
