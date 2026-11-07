import AppKit

enum FinderSelection {
    /// Returns the POSIX paths currently selected in the front Finder window.
    /// Prompts for Automation permission the first time it runs. Throws a
    /// human-readable message if the AppleScript bridge itself fails (e.g.
    /// Automation permission denied, Finder not running).
    static func current() throws -> [String] {
        let script = """
        tell application "Finder"
            set theSel to selection
            set thePaths to {}
            repeat with anItem in theSel
                set end of thePaths to POSIX path of (anItem as alias)
            end repeat
            return thePaths
        end tell
        """
        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            throw MoxError.upload("Couldn't compile Finder AppleScript.")
        }
        let result = appleScript.executeAndReturnError(&error)
        if let err = error {
            let msg = (err[NSAppleScript.errorMessage] as? String) ?? "Unknown AppleScript error"
            let num = (err[NSAppleScript.errorNumber] as? Int).map { " (\($0))" } ?? ""
            throw MoxError.upload("Finder: \(msg)\(num)")
        }

        var paths: [String] = []
        let count = result.numberOfItems
        guard count > 0 else { return paths }
        for index in 1...count {
            if let path = result.atIndex(index)?.stringValue, !path.isEmpty {
                paths.append(path)
            }
        }
        return paths
    }
}
