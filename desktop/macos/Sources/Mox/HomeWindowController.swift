import AppKit

/// What opening Mox shows once it's set up (#87). macOS hides menu bar icons
/// when the bar is full, so this window, and the Dock icon that comes with
/// it, keep Mox reachable. The icon stays until Mox quits.
final class HomeWindowController: NSWindowController {
    private let onPairPhone: () -> Void
    private let onSetUp: () -> Void

    init(hotkey: String, onPairPhone: @escaping () -> Void, onSetUp: @escaping () -> Void) {
        self.onPairPhone = onPairPhone
        self.onSetUp = onSetUp
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: SetupPages.width, height: 240),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Mox"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentView = SetupPages.page(
            title: "Mox is running",
            body: "Select a file in Finder and press \(hotkey) to send it to your phone. "
                + "Files from your phone arrive in Downloads.",
            content: [SetupPages.wrapping(
                "Can't see the red box in the menu bar? macOS hides icons when the bar is full. "
                    + "Open Mox again whenever you need this window.",
                small: true, color: .secondaryLabelColor)],
            buttons: [SetupPages.button("Quit Mox", self, #selector(quit)),
                      SetupPages.button("Set Up Again…", self, #selector(setUp)),
                      SetupPages.button("Pair a Phone…", self, #selector(pairPhone), primary: true)])
        if let size = window.contentView?.fittingSize {
            window.setContentSize(NSSize(width: SetupPages.width, height: size.height))
        }
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func present() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func pairPhone() {
        close()
        onPairPhone()
    }

    @objc private func setUp() {
        close()
        onSetUp()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
