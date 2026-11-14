import AppKit
import UserNotifications
import MoxCore

/// Owns the NSStatusItem, its menu, and the popover-less interactions.
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    /// Replaced when the setup window finishes (#81).
    var supabase: SupabaseService?
    private let deviceID: UUID
    private(set) var current: CurrentFile?
    /// uploaded_at of the last file this Mac received, kept across launches
    /// so a file sent while the Mac was off still arrives (PROTOCOL.md §6).
    private let lastHandledKey = "MoxLastHandledUploadedAt"
    /// Baseline when the slot was empty on the first poll (#71).
    private static let emptySlot = "empty"
    private let hotkeyHuman: String
    private let textHotkeyHuman: String
    private var lastStatus: String?
    /// Set by the app delegate when Mox is configured; opens the QR window.
    var onPairPhone: (() -> Void)? {
        didSet { rebuildMenu() }
    }
    /// Opens the setup window: "Set Up Mox…", or "Set Up Again…" once set up.
    var onSetUp: (() -> Void)? {
        didSet { rebuildMenu() }
    }

    /// Forgets the current file and the receive baseline, for a new project.
    func resetForNewBackend() {
        current = nil
        UserDefaults.standard.removeObject(forKey: lastHandledKey)
        rebuildMenu()
    }

    init(supabase: SupabaseService?, deviceID: UUID, hotkeyHuman: String, textHotkeyHuman: String) {
        self.supabase = supabase
        self.deviceID = deviceID
        self.hotkeyHuman = hotkeyHuman
        self.textHotkeyHuman = textHotkeyHuman
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

    /// Shows the current file, and downloads it when another device sent
    /// something this Mac hasn't handled yet (PROTOCOL.md §6).
    func update(current: CurrentFile?) {
        self.current = current
        rebuildMenu()
        let defaults = UserDefaults.standard
        guard let lastHandled = defaults.string(forKey: lastHandledKey) else {
            // First poll ever: remember what's in the slot, even when it's empty,
            // so the next file from another device counts as new (#71). What's
            // already there isn't downloaded.
            defaults.set(current?.uploadedAt ?? Self.emptySlot, forKey: lastHandledKey)
            return
        }
        guard let file = current, file.sourceDeviceId != deviceID, file.uploadedAt != lastHandled else { return }
        defaults.set(file.uploadedAt, forKey: lastHandledKey)
        tintBusy(false, accent: true)
        if file.isText {
            receiveText(file)
        } else if file.isBundle {
            receiveBundle(file, announce: true)
        } else {
            autoSaveFromPhone(file)
        }
    }

    /// Downloads a phone-sent file into ~/Downloads with a unique name and
    /// fires a notification on completion. Status line tracks progress.
    private func autoSaveFromPhone(_ file: CurrentFile) {
        guard let supabase else { return }
        showStatus("Receiving \(file.originalName)…")
        let dest = uniqueDownloadsURL(for: file.originalName)
        Task {
            do {
                try await supabase.downloadCurrent(to: dest)
                let clipped = PasteboardCopier.copy(fileURL: dest, mime: file.mimeType)
                await MainActor.run {
                    let suffix = clipped ? " · copied to clipboard" : ""
                    self.showStatus("Saved \(dest.lastPathComponent) to Downloads\(suffix)")
                    Notifier.show(
                        title: "New file from phone",
                        body: "\(dest.lastPathComponent) · \(humanSize(file.sizeBytes)) — Downloads\(suffix)"
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
        var copyNumber = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let next = ext.isEmpty ? "\(stem) (\(copyNumber))" : "\(stem) (\(copyNumber)).\(ext)"
            candidate = dir.appendingPathComponent(next)
            copyNumber += 1
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
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        lastStatus = "\(formatter.string(from: Date())) — \(text)"
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

        if let status = lastStatus {
            let statusLine = NSMenuItem(title: status, action: nil, keyEquivalent: "")
            statusLine.isEnabled = false
            menu.addItem(statusLine)
            menu.addItem(.separator())
        }

        addFileItems(to: menu)

        menu.addItem(.separator())
        let send = NSMenuItem(title: "Send Finder selection  (\(hotkeyHuman))",
                              action: #selector(sendSelection),
                              keyEquivalent: "")
        send.target = self
        menu.addItem(send)
        menu.addItem(actionItem("Send Copied Text  (\(textHotkeyHuman))", #selector(sendCopiedText)))
        if onPairPhone != nil {
            menu.addItem(actionItem("Pair a Phone…", #selector(pairPhone)))
        }
        if onSetUp != nil {
            menu.addItem(actionItem(supabase == nil ? "Set Up Mox…" : "Set Up Again…", #selector(setUp)))
        }
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

        for menuItem in menu.items where menuItem.target == nil && menuItem.action != nil
            && menuItem.action != #selector(NSApplication.terminate(_:)) {
            menuItem.target = self
        }
        statusItem.menu = menu
    }

    /// The current file and what can be done with it, or "No file yet".
    private func addFileItems(to menu: NSMenu) {
        if let file = current, file.isText {
            addTextItems(file, to: menu)
        } else if let file = current {
            let title = NSMenuItem(title: file.label, action: nil, keyEquivalent: "")
            title.isEnabled = false
            menu.addItem(title)

            let sub = "\(humanSize(file.sizeBytes)) · from \(file.sourceName)"
            let subItem = NSMenuItem(title: sub, action: nil, keyEquivalent: "")
            subItem.isEnabled = false
            menu.addItem(subItem)

            menu.addItem(.separator())
            menu.addItem(actionItem("Save to Downloads", #selector(saveToDownloads)))
            menu.addItem(actionItem("Save as…", #selector(saveAs)))
            menu.addItem(actionItem("Copy share link", #selector(copyShareLink)))
        } else {
            let empty = NSMenuItem(title: "No file yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
    }

    private func actionItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = self
        return menuItem
    }

    // MARK: Actions

    @objc private func pairPhone() {
        onPairPhone?()
    }

    @objc private func setUp() {
        onSetUp?()
    }

    @objc private func sendSelection() {
        NotificationCenter.default.post(name: .moxSendSelection, object: nil)
    }

    @objc private func saveToDownloads() {
        guard let file = current, let supabase else { return }
        if file.isBundle { return receiveBundle(file, announce: false) }
        let dest = FileManager.default
            .urls(for: .downloadsDirectory, in: .userDomainMask).first!
            .appendingPathComponent(file.originalName)
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
        guard let file = current, let supabase else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = file.originalName
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { resp in
            guard resp == .OK, let dest = panel.url else { return }
            Task {
                do {
                    try await supabase.downloadCurrent(to: dest)
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
        guard current != nil, let supabase else { return }
        Task {
            do {
                let url = try await supabase.signedDownloadURL(expiresIn: 3600)
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
