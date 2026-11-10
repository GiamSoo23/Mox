import AppKit
import MoxCore

/// Building blocks for the setup window's pages (#81). Each page is a
/// vertical stack: a title, a short explanation, its controls, and buttons.
enum SetupPages {
    static let width: CGFloat = 460

    static func page(title: String, body: String?, content: [NSView] = [], buttons: [NSButton] = []) -> NSView {
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 20, weight: .semibold)
        var views: [NSView] = [heading]
        if let body { views.append(wrapping(body)) }
        views.append(contentsOf: content)
        if !buttons.isEmpty {
            let spacer = NSView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            let row = NSStackView(views: [spacer] + buttons)
            row.orientation = .horizontal
            row.translatesAutoresizingMaskIntoConstraints = false
            views.append(row)
            row.widthAnchor.constraint(equalToConstant: width - 56).isActive = true
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 28, left: 28, bottom: 24, right: 28)
        return stack
    }

    static func wrapping(_ text: String, small: Bool = false, color: NSColor = .labelColor) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.preferredMaxLayoutWidth = width - 56
        label.textColor = color
        if small { label.font = .systemFont(ofSize: NSFont.smallSystemFontSize) }
        return label
    }

    static func button(_ title: String, _ target: AnyObject, _ action: Selector, primary: Bool = false) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        if primary { button.keyEquivalent = "\r" }
        return button
    }

    /// A link-styled button, for secondary choices like "use a token instead".
    static func link(_ title: String, _ target: AnyObject, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.isBordered = false
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: NSColor.linkColor,
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)
        ])
        return button
    }

    static func spinner() -> NSProgressIndicator {
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.startAnimation(nil)
        return spinner
    }

    /// A spinner next to a sentence: "Looking at your Supabase account…".
    static func waiting(_ text: String) -> NSView {
        let row = NSStackView(views: [spinner(), NSTextField(labelWithString: text)])
        row.orientation = .horizontal
        return row
    }
}

/// The checklist shown while Mox sets up a project.
final class SetupProgressList {
    enum Row: Int, CaseIterable {
        case creatingProject, waiting, migrations, schema, user, owner, key, push

        var title: String {
            switch self {
            case .creatingProject: return "Create the project"
            case .waiting: return "Wait for the project to start (new projects take a few minutes)"
            case .migrations: return "Add Mox's tables"
            case .schema: return "Turn on Mox's API"
            case .user: return "Create the Mox user"
            case .owner: return "Make that user the only one allowed in"
            case .key: return "Read the app key"
            case .push: return "Set up iPhone support"
            }
        }
    }

    let view: NSStackView
    private var icons: [Row: NSImageView] = [:]
    private var spinners: [Row: NSProgressIndicator] = [:]
    private var labels: [Row: NSTextField] = [:]
    private var skipped: Set<Row> = []
    private let rows: [Row]
    /// Overall progress across every row, so it's clear things are moving.
    private let bar = NSProgressIndicator()

    init(includesNewProject: Bool) {
        rows = Row.allCases.filter { $0 != .creatingProject || includesNewProject }
        view = NSStackView()
        view.orientation = .vertical
        view.alignment = .leading
        view.spacing = 8
        bar.style = .bar
        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = Double(rows.count)
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.widthAnchor.constraint(equalToConstant: SetupPages.width - 56).isActive = true
        view.addArrangedSubview(bar)
        view.setCustomSpacing(16, after: bar)
        for row in rows {
            let icon = NSImageView()
            let spinner = SetupPages.spinner()
            spinner.isHidden = true
            let label = SetupPages.wrapping(row.title)
            label.preferredMaxLayoutWidth = SetupPages.width - 90
            let line = NSStackView(views: [icon, spinner, label])
            line.orientation = .horizontal
            icons[row] = icon
            spinners[row] = spinner
            labels[row] = label
            view.addArrangedSubview(line)
        }
        mark(current: nil)
    }

    func show(_ step: ProvisioningStep) {
        switch step {
        case .waitingForProject: mark(current: .waiting)
        case .applyingMigrations(let done, let total):
            mark(current: .migrations, fraction: total == 0 ? 0 : Double(done) / Double(total))
            labels[.migrations]?.stringValue = total == 0
                ? Row.migrations.title : "\(Row.migrations.title) (\(done) of \(total))"
        case .exposingSchema: mark(current: .schema)
        case .creatingMoxUser: mark(current: .user)
        case .settingOwner: mark(current: .owner)
        case .readingKey: mark(current: .key)
        case .settingUpPush: mark(current: .push)
        case .pushSkipped(let reason):
            skipped.insert(.push)
            labels[.push]?.stringValue = "iPhone support is off: \(reason)"
        case .finished: mark(current: nil, allDone: true)
        }
    }

    func creatingProject() { mark(current: .creatingProject) }

    /// `fraction` is how far the current row itself has got (migrations).
    private func mark(current: Row?, allDone: Bool = false, fraction: Double = 0) {
        let finishedRows = allDone ? rows.count : current.flatMap { rows.firstIndex(of: $0) } ?? 0
        bar.doubleValue = Double(finishedRows) + (allDone ? 0 : fraction)
        for (row, icon) in icons {
            let isCurrent = !allDone && row == current
            icon.isHidden = isCurrent
            spinners[row]?.isHidden = !isCurrent
            let name: String
            let color: NSColor
            if skipped.contains(row) {
                (name, color) = ("exclamationmark.circle.fill", .systemOrange)
            } else if allDone || (current.map { row.rawValue < $0.rawValue } ?? false) {
                (name, color) = ("checkmark.circle.fill", .systemGreen)
            } else {
                (name, color) = ("circle", .tertiaryLabelColor)
            }
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
                .applying(.init(paletteColors: [color]))
            icon.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
        }
    }
}
