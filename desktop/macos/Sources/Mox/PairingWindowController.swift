import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// "Pair a Phone": shows the pairing link as a QR code (PROTOCOL.md §8,
/// DESIGN.md §7.2). The code carries the Mox user's password, so the
/// window opens only on request and stays out of screenshots and screen
/// sharing.
final class PairingWindowController: NSWindowController {
    private let link: String
    private var copyButton: NSButton?

    init(link: String, desktopName: String) {
        self.link = link
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 540),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Pair a Phone"
        window.isReleasedWhenClosed = false
        // Keep the QR code out of screenshots, screen recordings and sharing.
        window.sharingType = .none
        super.init(window: window)
        window.contentView = makeContent(desktopName: desktopName)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: Layout

    private func makeContent(desktopName: String) -> NSView {
        let title = NSTextField(labelWithString: "Scan with your phone's camera")
        title.font = .systemFont(ofSize: 17, weight: .semibold)

        let subtitle = NSTextField(wrappingLabelWithString:
            "Opens the pairing page, which installs Mox if needed and sets it up. No keys to type.")
        subtitle.alignment = .center
        subtitle.textColor = .secondaryLabelColor

        let qrView = NSImageView(image: Self.qrImage(for: link, side: 280) ?? NSImage())
        qrView.imageScaling = .scaleNone
        qrView.setAccessibilityLabel("Pairing QR code")

        let name = NSTextField(labelWithString: "This Mac: \(desktopName)")
        name.textColor = .secondaryLabelColor

        let warning = NSTextField(wrappingLabelWithString:
            "This code contains your Mox password. Don't share it or send screenshots of it.")
        warning.alignment = .center
        warning.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        warning.textColor = .systemOrange

        let copy = NSButton(title: "Copy Link", target: self, action: #selector(copyLink))
        copyButton = copy
        let done = NSButton(title: "Done", target: self, action: #selector(closeWindow))
        done.keyEquivalent = "\r"
        let buttons = NSStackView(views: [copy, done])

        let stack = NSStackView(views: [title, subtitle, qrView, name, warning, buttons])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 28, bottom: 24, right: 28)
        for label in [subtitle, warning] {
            label.preferredMaxLayoutWidth = 320
        }
        return stack
    }

    // MARK: Actions

    @objc private func copyLink() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)
        copyButton?.title = "Copied"
    }

    @objc private func closeWindow() {
        window?.close()
    }

    // MARK: QR code

    /// A crisp QR code about `side` points wide. Medium error correction,
    /// scaled by a whole number so the modules stay sharp.
    static func qrImage(for text: String, side: CGFloat) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scale = max(1, (side / output.extent.width).rounded(.down))
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
    }
}
