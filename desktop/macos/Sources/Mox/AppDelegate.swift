import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var supabase: SupabaseService?
    private var hotkey = HotKeyManager()
    private var pollTimer: Timer?
    private var pollInterval: TimeInterval = 5
    private var firstPollDone = false

    func applicationDidFinishLaunching(_ note: Notification) {
        let config: Config
        do {
            config = try Config.load()
        } catch {
            fatalAlert(error.localizedDescription)
            return
        }
        let supa = SupabaseService(config: config)
        let bar = MenuBarController(supabase: supa, hotkeyHuman: config.hotkey.human)

        self.supabase = supa
        self.menuBar = bar
        self.pollInterval = config.pollInterval

        // Request notification permission upfront so the system prompt appears
        // before the user starts pressing the hotkey, not after the first error.
        Notifier.requestAuthorization()

        LoginItem.autoEnableOnFirstLaunchIfNeeded()

        NotificationCenter.default.addObserver(self,
            selector: #selector(handleSendSelection),
            name: .moxSendSelection, object: nil)

        let regStatus = hotkey.register(config.hotkey) { [weak self] in
            self?.handleSendSelection()
        }
        if regStatus == noErr {
            bar.showStatus("Ready. Hotkey \(config.hotkey.human) registered.")
        } else {
            bar.showStatus("Hotkey \(config.hotkey.human) FAILED to register (OSStatus \(regStatus)). Use menu instead.")
        }

        Task { await self.poll() }
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { await self?.poll() }
        }
    }

    @objc private func handleSendSelection() {
        menuBar?.showStatus("Hotkey pressed…")
        let paths: [String]
        do {
            paths = try FinderSelection.current()
        } catch {
            menuBar?.showError(error.localizedDescription)
            return
        }
        guard let first = paths.first else {
            menuBar?.showError("No file selected. Click a file in a Finder window, then press the hotkey.")
            return
        }
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: first, isDirectory: &isDir)
        guard !isDir.boolValue else {
            menuBar?.showError("Folders aren't supported — zip it first.")
            return
        }

        menuBar?.tintBusy(true)
        menuBar?.showStatus("Uploading \((first as NSString).lastPathComponent)…")
        Task {
            do {
                let row = try await supabase!.uploadFile(localPath: first, uploadedFrom: "mac")
                await MainActor.run {
                    self.menuBar?.update(current: row, notify: false)
                    self.menuBar?.tintBusy(false)
                    self.menuBar?.showStatus("Sent \(row.original_name)")
                    Notifier.show(title: "Sent",
                                  body: "\(row.original_name) · \(humanSize(row.size_bytes))")
                }
            } catch {
                await MainActor.run {
                    self.menuBar?.tintBusy(false)
                    self.menuBar?.showError(error.localizedDescription)
                }
            }
        }
    }

    private func poll() async {
        guard let supa = supabase else { return }
        do {
            let row = try await supa.fetchCurrent()
            let firstRun = !firstPollDone
            firstPollDone = true
            await MainActor.run {
                self.menuBar?.update(current: row, notify: !firstRun)
            }
        } catch {
            // Network blip; ignore silently.
        }
    }

    private func fatalAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Mox can't start"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Quit")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        NSApp.terminate(nil)
    }
}
