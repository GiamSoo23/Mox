import AppKit
import MoxCore

/// Sending the clipboard's text (#101).
extension AppDelegate {
    @objc func handleSendText() {
        guard let supabase else {
            menuBar?.showError("Mox isn't set up yet.")
            return
        }
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            menuBar?.showError("There's no text on the clipboard. "
                + "Copy some text, then press \(config.textHotkey.human).")
            return
        }
        menuBar?.tintBusy(true)
        menuBar?.showStatus("Sending text…")
        Task {
            do {
                let row = try await supabase.uploadText(text)
                await MainActor.run {
                    self.menuBar?.update(current: row)
                    self.menuBar?.tintBusy(false)
                    self.menuBar?.showStatus("Sent text")
                    Notifier.show(title: "Sent", body: TextPayload.preview(text))
                }
            } catch {
                await MainActor.run {
                    self.menuBar?.tintBusy(false)
                    self.menuBar?.showError(error.localizedDescription)
                }
            }
        }
    }
}
