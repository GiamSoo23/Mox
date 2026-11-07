import AppKit
import UserNotifications

/// Owns the NSStatusItem, its menu, and the popover-less interactions.
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let supabase: SupabaseService
    private var current: SupabaseService.CurrentFile?
    private let hotkeyHuman: String
    private var lastStatus: String?

    init(supabase: SupabaseService, hotkeyHuman: String) {
        self.supabase = supabase
        self.hotkeyHuman = hotkeyHuman
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = MenuBarController.icon(named: "archivebox")
        }
        rebuildMenu()
    }

    /// A red SF Symbol sized for the menu bar. Non-template so macOS doesn't
    /// recolor it to match the bar tint.
    private static func icon(named name: String) -> NSImage? {
        let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            .applying(.init(paletteColors: [.systemRed]))
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "Mox")?
            .withSymbolConfiguration(cfg)
        img?.isTemplate = false
        return img
    }

    func update(current: SupabaseService.CurrentFile?, notify: Bool) {
        let didChange = current != self.current
        self.current = current
        rebuildMenu()
        if let f = current, didChange, notify, f.uploaded_from != "mac" {
            tintBusy(false, accent: true)
            autoSaveFromPhone(f)
        }
    }

    /// Downloads a phone-sent file into ~/Downloads with a unique name and
    /// fires a notification on completion. Status line tracks progress.
    private func autoSaveFromPhone(_ file: SupabaseService.CurrentFile) {
        showStatus("Receiving \(file.original_name)…")
        let dest = uniqueDownloadsURL(for: file.original_name)
        Task {
            do {
                try await supabase.downloadCurrent(to: dest)
                let clipped = PasteboardCopier.copy(fileURL: dest, mime: file.mime_type)
                await MainActor.run {
                    let suffix = clipped ? " · copied to clipboard" : ""
                    self.showStatus("Saved \(dest.lastPathComponent) to Downloads\(suffix)")
                    Notifier.show(
                        title: "New file from phone",
                        body: "\(dest.lastPathComponent) · \(humanSize(file.size_bytes)) — Downloads\(suffix)"
                    )
                }
            } catch {
                await MainActor.run {
                    self.showError("Auto-save failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func uniqueDownloadsURL(for name: String) -> URL {
        let dir = FileManager.default
            .urls(for: .downloadsDirectory, in: .userDomainMask).first!
        var candidate = dir.appendingPathComponent(name)
        let stem = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension
        var i = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let next = ext.isEmpty ? "\(stem) (\(i))" : "\(stem) (\(i)).\(ext)"
            candidate = dir.appendingPathComponent(next)
            i += 1
        }
        return candidate
    }

    func showError(_ message: String) {
        showStatus("⚠︎ \(message)")
        Notifier.show(title: "Mox", body: message)
    }

    /// Records a one-line status string shown at the top of the menu. This
    /// channel always works, even when the user has denied notifications.
    func showStatus(_ text: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        lastStatus = "\(f.string(from: Date())) — \(text)"
        rebuildMenu()
    }

    func tintBusy(_ busy: Bool, accent: Bool = false) {
        guard let button = statusItem.button else { return }
        let name: String
        if busy {
            name = "archivebox.fill"
        } else if accent {
            name = "archivebox.circle.fill"
        } else {
            name = "archivebox"
        }
        button.image = MenuBarController.icon(named: name)
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        if let s = lastStatus {
            let it = NSMenuItem(title: s, action: nil, keyEquivalent: "")
            it.isEnabled = false
            menu.addItem(it)
            menu.addItem(.separator())
        }

        if let f = current {
            let title = NSMenuItem(title: f.original_name, action: nil, keyEquivalent: "")
            title.isEnabled = false
            menu.addItem(title)

            let sub = "\(humanSize(f.size_bytes)) · from \(f.uploaded_from)"
            let subItem = NSMenuItem(title: sub, action: nil, keyEquivalent: "")
            subItem.isEnabled = false
            menu.addItem(subItem)

            menu.addItem(.separator())
            menu.addItem(item("Save to Downloads", #selector(saveToDownloads)))
            menu.addItem(item("Save as…", #selector(saveAs)))
            menu.addItem(item("Copy share link", #selector(copyShareLink)))
        } else {
            let empty = NSMenuItem(title: "No file yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }

        menu.addItem(.separator())
        let send = NSMenuItem(title: "Send Finder selection  (\(hotkeyHuman))",
                              action: #selector(sendSelection),
                              keyEquivalent: "")
        send.target = self
        menu.addItem(send)
        menu.addItem(.separator())

        if LoginItem.isAvailable {
            let launch = NSMenuItem(title: "Launch at Login",
                                    action: #selector(toggleLaunchAtLogin),
                                    keyEquivalent: "")
            launch.target = self
            launch.state = LoginItem.isEnabled ? .on : .off
            menu.addItem(launch)
        }

        let quit = NSMenuItem(title: "Quit Mox", action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        menu.addItem(quit)

        for it in menu.items where it.target == nil && it.action != nil
            && it.action != #selector(NSApplication.terminate(_:)) {
            it.target = self
        }
        statusItem.menu = menu
    }

    private func item(_ title: String, _ sel: Selector) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        it.target = self
        return it
    }

    // MARK: Actions

    @objc private func sendSelection() {
        NotificationCenter.default.post(name: .moxSendSelection, object: nil)
    }

    @objc private func saveToDownloads() {
        guard let f = current else { return }
        let dest = FileManager.default
            .urls(for: .downloadsDirectory, in: .userDomainMask).first!
            .appendingPathComponent(f.original_name)
        Task {
            do {
                try await supabase.downloadCurrent(to: dest)
                Notifier.show(title: "Saved", body: dest.path)
            } catch {
                Notifier.show(title: "Mox", body: error.localizedDescription)
            }
        }
    }

    @objc private func saveAs() {
        guard let f = current else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = f.original_name
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { resp in
            guard resp == .OK, let dest = panel.url else { return }
            Task {
                do {
                    try await self.supabase.downloadCurrent(to: dest)
                    Notifier.show(title: "Saved", body: dest.path)
                } catch {
                    Notifier.show(title: "Mox", body: error.localizedDescription)
                }
            }
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let next = !LoginItem.isEnabled
        switch LoginItem.setEnabled(next) {
        case .success:
            showStatus(next ? "Launch at Login enabled" : "Launch at Login disabled")
        case .failure(let err):
            showError("Launch at Login: \(err.localizedDescription)")
        }
        rebuildMenu()
    }

    @objc private func copyShareLink() {
        guard let f = current else { return }
        Task {
            do {
                let url = try await supabase.signedDownloadURL(for: f.storage_path, expiresIn: 3600)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
                Notifier.show(title: "Mox", body: "Share link copied (1 h)")
            } catch {
                Notifier.show(title: "Mox", body: error.localizedDescription)
            }
        }
    }
}

extension Notification.Name {
    static let moxSendSelection = Notification.Name("MoxSendSelection")
}

enum Notifier {
    /// Trigger the one-time system prompt at launch instead of mid-action.
    static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func show(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let req = UNNotificationRequest(identifier: UUID().uuidString,
                                         content: content,
                                         trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}

func humanSize(_ bytes: Int64) -> String {
    let f = ByteCountFormatter()
    f.allowedUnits = [.useKB, .useMB, .useGB]
    f.countStyle = .file
    return f.string(fromByteCount: bytes)
}
