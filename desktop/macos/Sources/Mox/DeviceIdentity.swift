import Foundation

/// This installation's device id (PROTOCOL.md §1): generated once, kept in
/// UserDefaults. It goes into every row the Mac writes, so the Mac can
/// recognize, and skip, its own uploads.
enum DeviceIdentity {
    private static let key = "MoxDeviceID"

    static var id: UUID {
        let defaults = UserDefaults.standard
        if let stored = defaults.string(forKey: key), let uuid = UUID(uuidString: stored) {
            return uuid
        }
        let fresh = UUID()
        defaults.set(fresh.uuidString, forKey: key)
        return fresh
    }

    /// The computer's name, shown on the phone after pairing.
    static var name: String {
        Host.current().localizedName ?? "Mac"
    }
}
