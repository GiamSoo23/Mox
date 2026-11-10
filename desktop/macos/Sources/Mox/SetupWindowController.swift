import AppKit
import MoxCore

/// The setup window (#81, DESIGN.md §7.1): sign in to Supabase, pick where
/// Mox lives, set that project up, and hand the settings back. The Supabase
/// token stays in memory and is dropped when the window closes.
final class SetupWindowController: NSWindowController, NSWindowDelegate {
    let oauthClient: OAuthClient?
    let isReplacing: Bool
    let onFinished: (MoxSettings) -> Void

    var api: ManagementAPI?
    var organizations: [Organization] = []
    var choices: SetupChoices?
    var work: Task<Void, Never>?
    /// True while the project is being changed. Stopping then could leave the
    /// project with a new owner this Mac never saved (#117).
    var isProvisioning = false
    /// After a failed attempt, the project to preselect on the "where" page
    /// (one Mox just created, so trying again doesn't create a second one).
    var preferredProjectID: String?
    private var loopback: OAuthLoopbackServer?
    private var tokenField: NSSecureTextField?

    // Controls of the "where" page, read when the person continues.
    var newRadio: NSButton?
    var existingRadio: NSButton?
    var organizationPopup: NSPopUpButton?
    var regionPopup: NSPopUpButton?
    var projectPopup: NSPopUpButton?

    init(oauthClient: OAuthClient?, isReplacing: Bool, onFinished: @escaping (MoxSettings) -> Void) {
        self.oauthClient = oauthClient
        self.isReplacing = isReplacing
        self.onFinished = onFinished
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: SetupPages.width, height: 300),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Set Up Mox"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        showWelcome()
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func show(_ page: NSView) {
        window?.contentView = page
        if let size = window?.contentView?.fittingSize {
            window?.setContentSize(NSSize(width: SetupPages.width, height: size.height))
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard isProvisioning else { return true }
        Task { _ = await alert("Mox is still setting up", "Closing now could leave your project half set up. "
            + "It only takes a moment more.") }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        work?.cancel()
        loopback?.stop()
        api = nil
    }

    // MARK: Welcome

    func showWelcome(error: String? = nil) {
        var content: [NSView] = []
        if isReplacing {
            content.append(SetupPages.wrapping(
                "Mox is already set up on this Mac. Setting it up again disconnects your paired phones "
                    + "until you pair them again.", small: true, color: .systemOrange))
        }
        if let error { content.append(SetupPages.wrapping(error, color: .systemRed)) }
        content.append(SetupPages.link("New to Supabase? Start here", self, #selector(showNewAccountPage)))
        var buttons: [NSButton] = []
        if oauthClient != nil {
            content.append(SetupPages.link("Use an access token instead", self, #selector(showTokenPage)))
            buttons.append(SetupPages.button("Sign in with Supabase", self, #selector(signIn), primary: true))
        } else {
            buttons.append(SetupPages.button("Continue", self, #selector(showTokenPage), primary: true))
        }
        show(SetupPages.page(
            title: "Welcome to Mox",
            body: "Mox keeps the files you send in your own free Supabase project, so nobody else "
                + "holds your data. Sign in to Supabase and Mox sets everything up for you: no keys to copy.",
            content: content, buttons: buttons))
    }

    // MARK: Sign in with Supabase

    @objc func signIn() {
        guard let client = oauthClient else { return }
        let pkce = PKCE.generate()
        let state = PKCE.generate().verifier
        let server = OAuthLoopbackServer(expectedState: state)
        loopback = server
        show(SetupPages.page(
            title: "Finish signing in in your browser",
            body: "Supabase asks you to choose an organization and allow Mox. Then come back here.",
            content: [SetupPages.waiting("Waiting for Supabase…")],
            buttons: [SetupPages.button("Cancel", self, #selector(cancelSignIn))]))
        work = Task { [weak self] in
            let code = Task { try await server.waitForCode() }
            NSWorkspace.shared.open(SupabaseOAuth.authorizationURL(client: client, pkce: pkce, state: state))
            do {
                let tokens = try await SupabaseOAuth.exchange(code: code.value, client: client, pkce: pkce)
                NSApp.activate(ignoringOtherApps: true)
                self?.api = ManagementAPI(token: tokens.accessToken)
                await self?.loadAccount()
            } catch is CancellationError {
                return
            } catch {
                self?.showWelcome(error: error.localizedDescription)
            }
        }
    }

    @objc private func cancelSignIn() {
        loopback?.stop()
        work?.cancel()
        showWelcome()
    }

    // MARK: Access token (fallback)

    @objc func showTokenPage() {
        let field = NSSecureTextField()
        field.placeholderString = "sbp_…"
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: SetupPages.width - 56).isActive = true
        tokenField = field
        show(SetupPages.page(
            title: "Use an access token",
            body: "Create a token in your Supabase account, paste it here, and Mox uses it only for "
                + "this setup. It isn't saved. You can delete the token afterwards.",
            content: [SetupPages.link("Open Supabase access tokens", self, #selector(openTokensPage)), field],
            buttons: [SetupPages.button("Back", self, #selector(back)),
                      SetupPages.button("Continue", self, #selector(useToken), primary: true)]))
        window?.makeFirstResponder(field)
    }

    @objc private func openTokensPage() {
        NSWorkspace.shared.open(URL(string: "https://supabase.com/dashboard/account/tokens")!)
    }

    @objc private func back() { showWelcome() }

    @objc private func useToken() {
        let token = tokenField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !token.isEmpty else { return }
        api = ManagementAPI(token: token)
        work = Task { [weak self] in await self?.loadAccount() }
    }

    // MARK: Account

    /// Reads the organizations and projects, then shows where Mox can go.
    func loadAccount() async {
        guard let api else { return }
        show(SetupPages.page(title: "Looking at your Supabase account", body: nil,
                             content: [SetupPages.waiting("Reading your projects…")]))
        do {
            async let orgs = api.organizations()
            async let projects = api.projects()
            organizations = try await orgs
            guard !organizations.isEmpty else {
                self.api = nil
                return showNewAccountSteps(notice: "Your Supabase account doesn't have an organization yet. "
                    + "Create one, then sign in again.")
            }
            choices = SetupChoices(projects: try await projects)
            showChoices()
        } catch {
            self.api = nil
            showWelcome(error: error.localizedDescription)
        }
    }

    /// A sheet with one button; returns when it's dismissed.
    func alert(_ title: String, _ message: String, buttons: [String] = ["OK"]) async -> Int {
        guard let window else { return 0 }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        for title in buttons { alert.addButton(withTitle: title) }
        let response = await alert.beginSheetModal(for: window)
        return response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
    }
}
