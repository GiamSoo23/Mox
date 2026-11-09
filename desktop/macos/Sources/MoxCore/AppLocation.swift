import Foundation

/// Decides whether Mox should offer to move itself to Applications (#90).
public enum AppLocation {
    /// True for an app opened from Downloads, the Desktop, or the temporary
    /// copy macOS runs a downloaded app from. `isSourceBuild` is true next
    /// to a Package.swift, where a developer built it on purpose.
    public static func shouldOfferMove(bundlePath: String, home: String, isSourceBuild: Bool) -> Bool {
        guard bundlePath.hasSuffix(".app"), !isSourceBuild else { return false }
        if bundlePath.contains("/AppTranslocation/") { return true }
        return bundlePath.hasPrefix(home + "/Downloads/") || bundlePath.hasPrefix(home + "/Desktop/")
    }
}
