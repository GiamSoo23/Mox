import AppKit
import MoxCore

/// Receiving several files at once (#19): unpack the bundle into a folder in
/// Downloads and put every file on the pasteboard.
extension MenuBarController {
    /// "Mox – 5 files – 14.32", a new folder in Downloads.
    static func bundleFolder(for file: CurrentFile, in downloads: URL) -> URL {
        let time = DateFormatter()
        time.dateFormat = "HH.mm"
        return UniqueName.url(for: "Mox – \(file.itemCount) files – \(time.string(from: Date()))", in: downloads)
    }

    func receiveBundle(_ file: CurrentFile, announce: Bool) {
        guard let supabase else { return }
        showStatus("Receiving \(file.label)…")
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        Task {
            let zip = FileManager.default.temporaryDirectory
                .appendingPathComponent("mox-bundle-\(UUID().uuidString).zip")
            defer { try? FileManager.default.removeItem(at: zip) }
            do {
                try await supabase.downloadCurrent(to: zip)
                let folder = Self.bundleFolder(for: file, in: downloads)
                let items = try BundleReader.extract(try Data(contentsOf: zip), into: folder)
                await MainActor.run {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    let copied = pasteboard.writeObjects(items.map { $0 as NSURL })
                    let suffix = copied ? " · copied to clipboard" : ""
                    self.showStatus("Saved \(file.label) to \(folder.lastPathComponent)\(suffix)")
                    if announce {
                        Notifier.show(title: "\(file.label) from \(file.sourceName)",
                                      body: "In Downloads › \(folder.lastPathComponent)\(suffix)")
                    } else {
                        Notifier.show(title: "Saved", body: folder.path)
                    }
                }
            } catch {
                await MainActor.run { self.showError("Couldn't receive \(file.label): \(error.localizedDescription)") }
            }
        }
    }
}
