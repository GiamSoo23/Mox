import AppKit

extension AppDelegate {
    /// Only one Mox may run. An older copy left running after an update
    /// keeps old settings that stop working, so the newest copy wins (#140).
    func quitOtherCopies() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let current = NSRunningApplication.current.processIdentifier
        for other in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        where other.processIdentifier != current {
            other.terminate()
        }
    }
}
