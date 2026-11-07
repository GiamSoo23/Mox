import AppKit

/// Writes a freshly received file to the system pasteboard so the user can
/// immediately `⌘V` it. For images we also publish bitmap data so apps that
/// only accept image data (chat composers, rich-text fields) can paste too.
enum PasteboardCopier {
    @discardableResult
    static func copy(fileURL: URL, mime: String?) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        var copied = pasteboard.writeObjects([fileURL as NSURL])

        if (mime ?? "").hasPrefix("image/"), let image = NSImage(contentsOf: fileURL) {
            // Append image data alongside the file URL so both Finder paste
            // (file copy) and rich-text paste (inline image) work from the
            // same clipboard entry.
            if let tiff = image.tiffRepresentation {
                pasteboard.setData(tiff, forType: .tiff)
                copied = true
            }
            if let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                pasteboard.setData(png, forType: .png)
                copied = true
            }
        }
        return copied
    }
}
