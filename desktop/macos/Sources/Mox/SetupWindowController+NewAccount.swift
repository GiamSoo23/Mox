import AppKit

/// For people with no Supabase account yet (#97): what to do before signing
/// in, because Supabase needs a confirmed account and an organization first.
extension SetupWindowController {
    func showNewAccountSteps(notice: String? = nil) {
        var content: [NSView] = []
        if let notice { content.append(SetupPages.wrapping(notice, color: .systemOrange)) }
        content.append(SetupPages.wrapping("1. Create your free account."))
        content.append(SetupPages.link("Open Supabase sign-up", self, #selector(openSignUp)))
        content.append(SetupPages.wrapping("2. Open the email Supabase sends you and confirm your account."))
        content.append(SetupPages.wrapping("3. Create an organization. The free plan is all Mox needs."))
        content.append(SetupPages.link("Create an organization", self, #selector(openNewOrganization)))
        content.append(SetupPages.wrapping("4. Come back here and continue. Then just allow Mox in your browser."))
        let next = oauthClient == nil
            ? SetupPages.button("Continue", self, #selector(showTokenPage), primary: true)
            : SetupPages.button("Sign in with Supabase", self, #selector(signIn), primary: true)
        show(SetupPages.page(
            title: "Get a Supabase account",
            body: "Mox keeps your files in your own free Supabase project. Setting up an account takes a few minutes.",
            content: content,
            buttons: [SetupPages.button("Back", self, #selector(backToWelcome)), next]))
    }

    @objc func showNewAccountPage() { showNewAccountSteps() }

    @objc private func openSignUp() {
        NSWorkspace.shared.open(URL(string: "https://supabase.com/dashboard/sign-up")!)
    }

    @objc private func openNewOrganization() {
        NSWorkspace.shared.open(URL(string: "https://supabase.com/dashboard/new")!)
    }

    @objc private func backToWelcome() { showWelcome() }
}
