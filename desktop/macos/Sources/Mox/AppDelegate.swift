import AppKit
import MoxCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBar: MenuBarController?
    var supabase: SupabaseService?
    private var hotkey = HotKeyManager()
    private var pollTimer: Timer?
    private var pollInterval: TimeInterval = 5
    private var pairingWindow: PairingWindowController?

    private var setupWindow: SetupWindowController?
    private var homeWindow: HomeWindowController?
    var config = Config.load()
    private let deviceID = DeviceIdentity.id

    func applicationDidFinishLaunching(_ note: Notification) {
        quitOtherCopies()
        if AppMover.offerIfNeeded() { return }
        let bar = MenuBarController(supabase: nil, deviceID: deviceID, hotkeyHuman: config.hotkey.human,
                                    textHotkeyHuman: config.textHotkey.human)
        self.menuBar = bar
        self.pollInterval = config.pollInterval
        bar.onSetUp = { [weak self] in self?.showSetup() }

        // Request notification permission upfront so the system prompt appears
        // before the user starts pressing the hotkey, not after the first error.
        Notifier.requestAuthorization()

        LoginItem.autoEnableOnFirstLaunchIfNeeded()

        NotificationCenter.default.addObserver(self,
            selector: #selector(handleSendSelection),
            name: .moxSendSelection, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSendText),
                                               name: .moxSendText, object: nil)
        hotkey.register(config.textHotkey, id: 2) { [weak self] in self?.handleSendText() }

        let regStatus = hotkey.register(config.hotkey) { [weak self] in
            self?.handleSendSelection()
        }
        if regStatus == noErr {
            bar.showStatus("Ready. Hotkey \(config.hotkey.human) registered.")
        } else {
            bar.showStatus("Hotkey \(config.hotkey.human) FAILED to register "
                           + "(OSStatus \(regStatus)). Use menu instead.")
        }

        if let settings = SettingsStore.resolve(fromEnv: config.settings) {
            start(with: settings)
            if !launchedAtLogin { showHome() }
        } else {
            bar.showStatus("Mox isn't set up yet. Choose Set Up Mox… to begin.")
            showSetup()
        }
    }

    /// Opening Mox while it's already running, including from the Dock.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showHome()
        return false
    }

    private var launchedAtLogin: Bool {
        NSAppleEventManager.shared().currentAppleEvent?
            .paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    /// Keeps Mox reachable even when macOS hides its menu bar icon (#87).
    private func showHome() {
        guard supabase != nil else { return showSetup() }
        if homeWindow == nil {
            homeWindow = HomeWindowController(hotkey: config.hotkey.human,
                                              onPairPhone: { [weak self] in self?.menuBar?.onPairPhone?() },
                                              onSetUp: { [weak self] in self?.showSetup() })
        }
        homeWindow?.present()
    }

    /// Connects to the project in `settings` and starts polling it.
    private func start(with settings: MoxSettings) {
        pollTimer?.invalidate()
        let supa = SupabaseService(settings: settings, deviceID: deviceID)
        supabase = supa
        menuBar?.supabase = supa
        menuBar?.onPairPhone = { [weak self] in self?.showPairing(settings) }
        let bar = menuBar
        Task {
            do {
                try await supa.checkSchema()
            } catch {
                await MainActor.run { bar?.showError(error.localizedDescription) }
            }
            await self.poll()
        }
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { await self?.poll() }
        }
    }

    private var oauthSecret: String? {
        OAuthClient.secret(environment: config.oauthClientSecret, infoPlist: Bundle.main.infoDictionary)
    }

    /// Opens (or brings back) the setup window (#81).
    private func showSetup() {
        if let open = setupWindow, open.window?.isVisible == true {
            open.present()
            return
        }
        let controller = SetupWindowController(oauthClient: .mox(secret: oauthSecret),
                                               isReplacing: supabase != nil) { [weak self] settings in
            self?.finishSetup(settings)
        }
        setupWindow = controller
        controller.present()
    }

    private func finishSetup(_ settings: MoxSettings) {
        guard SettingsStore.save(settings) else {
            menuBar?.showError("Mox was set up, but the Keychain refused to save its settings. Try again.")
            return
        }
        menuBar?.resetForNewBackend()
        start(with: settings)
        menuBar?.showStatus("Set up. Pair your phone to start sending.")
        showPairing(settings)
    }

    @objc private func handleSendSelection() {
        guard let supabase else {
            menuBar?.showError("Mox isn't set up yet.")
            return
        }
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

        menuBar?.tintBusy(true)
        let what = paths.count == 1 ? (first as NSString).lastPathComponent : "\(paths.count) items"
        menuBar?.showStatus("Uploading \(what)…")
        Task {
            do {
                let row = try await supabase.uploadSelection(paths)
                await MainActor.run {
                    self.menuBar?.update(current: row)
                    self.menuBar?.tintBusy(false)
                    self.menuBar?.showStatus("Sent \(row.label)")
                    Notifier.show(title: "Sent", body: "\(row.label) · \(humanSize(row.sizeBytes))")
                }
            } catch {
                await MainActor.run {
                    self.menuBar?.tintBusy(false)
                    self.menuBar?.showError(error.localizedDescription)
                }
            }
        }
    }

    /// Opens (or brings back) the "Pair a Phone" window with a fresh QR code.
    private func showPairing(_ settings: MoxSettings) {
        let link = settings.pairingLink(desktopName: DeviceIdentity.name).url()
        let controller = PairingWindowController(link: link, desktopName: DeviceIdentity.name)
        pairingWindow = controller
        controller.present()
    }

    private func poll() async {
        guard let supa = supabase else { return }
        do {
            let row = try await supa.fetchCurrent()
            await MainActor.run { self.menuBar?.update(current: row) }
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
