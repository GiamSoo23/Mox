import Foundation
import ServiceManagement

/// Thin wrapper around SMAppService for registering Mox as a Login Item.
/// The user can toggle this from the menu bar. We also auto-enable it once
/// on first launch so "always running" works without any manual setup.
enum LoginItem {
    private static let firstRunKey = "MoxDidAutoEnableLoginItem"

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Whether the Login Item machinery can be used in the current build.
    /// Returns false for unsigned dev runs from `swift run` (no bundle id
    /// surface SMAppService can latch onto), so the UI can hide the toggle.
    static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Result<Void, Error> {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    /// Enable Login Item on first run only, so a fresh install starts opening
    /// at boot without the user hunting through System Settings. If the user
    /// later disables it, we respect that — the flag prevents re-enabling.
    static func autoEnableOnFirstLaunchIfNeeded() {
        let defaults = UserDefaults.standard
        guard isAvailable, !defaults.bool(forKey: firstRunKey) else { return }
        defaults.set(true, forKey: firstRunKey)
        _ = setEnabled(true)
    }
}
