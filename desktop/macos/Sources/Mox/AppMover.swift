import AppKit
import MoxCore

/// Offers to move Mox to Applications when it's opened from a download (#90).
enum AppMover {
    private static let declinedKey = "MoxDeclinedMoveToApplications"
    private static let destination = URL(fileURLWithPath: "/Applications/Mox.app")

    /// Returns true when Mox moved and is reopening from Applications.
    static func offerIfNeeded() -> Bool {
        let bundle = Bundle.main.bundleURL
        let manifest = bundle.deletingLastPathComponent().appendingPathComponent("Package.swift")
        guard AppLocation.shouldOfferMove(bundlePath: bundle.path, home: NSHomeDirectory(),
                                          isSourceBuild: FileManager.default.fileExists(atPath: manifest.path)),
              !UserDefaults.standard.bool(forKey: declinedKey) else { return false }
        NSApp.activate(ignoringOtherApps: true)
        guard ask("Move Mox to Applications?",
                  "Then you'll find it with your other apps, and it can start when you log in.",
                  buttons: ["Move to Applications", "Not Now"]) else {
            UserDefaults.standard.set(true, forKey: declinedKey)
            return false
        }
        do {
            guard try install(from: bundle) else { return false }
        } catch {
            _ = ask("Mox couldn't move itself",
                    "\(error.localizedDescription) You can drag Mox.app to Applications yourself.", buttons: ["OK"])
            return false
        }
        reopen()
        return true
    }

    /// Copies the app into place. False if the person keeps the existing one.
    private static func install(from bundle: URL) throws -> Bool {
        let files = FileManager.default
        if files.fileExists(atPath: destination.path) {
            guard ask("Replace the Mox in Applications?",
                      "The current copy goes to the Trash. Your settings and paired phones stay.",
                      buttons: ["Replace", "Cancel"]) else { return false }
            try files.trashItem(at: destination, resultingItemURL: nil)
        }
        try files.copyItem(at: bundle, to: destination)
        // macOS already let this copy run; don't make the person approve it twice.
        removexattr(destination.path, "com.apple.quarantine", XATTR_NOFOLLOW)
        // A temporary copy vanishes by itself, and its original can't be located.
        if !bundle.path.contains("/AppTranslocation/") {
            try? files.trashItem(at: bundle, resultingItemURL: nil)
        }
        return true
    }

    private static func reopen() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: destination, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    /// A modal alert. True when the first button was chosen.
    private static func ask(_ title: String, _ message: String, buttons: [String]) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        for button in buttons { alert.addButton(withTitle: button) }
        return alert.runModal() == .alertFirstButtonReturn
    }
}
