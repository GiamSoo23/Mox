import AppKit
import MoxCore

/// Where Mox goes, chosen on the "where" page.
enum SetupTarget {
    case newProject(organization: Organization, region: SupabaseRegion)
    case existing(Project)

    var organizationID: String {
        switch self {
        case .newProject(let organization, _): return organization.id
        case .existing(let project): return project.organizationID
        }
    }
}

extension SetupWindowController {
    // MARK: Where should Mox live?

    func showChoices() {
        guard let choices else { return }
        let newRadio = NSButton(radioButtonWithTitle: "Create a new project called “Mox”",
                                target: self, action: #selector(choiceChanged))
        let existingRadio = NSButton(radioButtonWithTitle: "Install in a project you already have",
                                     target: self, action: #selector(choiceChanged))
        let otherRadio = NSButton(radioButtonWithTitle: "Another service (coming later)",
                                  target: nil, action: nil)
        otherRadio.isEnabled = false
        self.newRadio = newRadio
        self.existingRadio = existingRadio

        let orgs = NSPopUpButton()
        orgs.addItems(withTitles: organizations.map(\.name))
        orgs.isHidden = organizations.count < 2
        organizationPopup = orgs
        let regions = NSPopUpButton()
        regions.addItems(withTitles: SupabaseRegion.all.map(\.name))
        regions.selectItem(withTitle: SupabaseRegion.guess(timeZone: TimeZone.current.identifier).name)
        regionPopup = regions
        let projects = projectsPopup(choices.existing)
        projectPopup = projects
        existingRadio.isEnabled = !choices.existing.isEmpty
        newRadio.isEnabled = !organizations.isEmpty

        if let preferred = preferredProjectID {
            let index = projects.indexOfItem(withRepresentedObject: preferred)
            if index >= 0 { projects.selectItem(at: index) }
        }
        let pickNew = (choices.recommendation == .newProject && preferredProjectID == nil)
            || !existingRadio.isEnabled
        newRadio.state = pickNew && newRadio.isEnabled ? .on : .off
        existingRadio.state = newRadio.state == .on ? .off : .on

        show(SetupPages.page(
            title: "Where should Mox keep your files?", body: nil,
            content: [newRadio, indented([SetupPages.wrapping(newNote(choices), small: true,
                                                              color: .secondaryLabelColor), orgs, regions]),
                      existingRadio, indented([SetupPages.wrapping(existingNote(choices), small: true,
                                                                   color: .secondaryLabelColor), projects]),
                      otherRadio],
            buttons: [SetupPages.button("Install Mox", self, #selector(install), primary: true)]))
        choiceChanged()
    }

    private func newNote(_ choices: SetupChoices) -> String {
        choices.atFreeLimit
            ? "Your account already has \(SetupChoices.freeProjectLimit) active projects, the most the free "
                + "plan allows, so Supabase will probably refuse a new one."
            : "Recommended. Free, and only Mox uses it. Supabase takes a few minutes to start it."
    }

    private func existingNote(_ choices: SetupChoices) -> String {
        (choices.atFreeLimit ? "Recommended for you. " : "")
            + "Mox adds its own tables in a separate “mox” schema and doesn't touch your data. "
            + "Paused projects need to be restored in Supabase first."
    }

    private func projectsPopup(_ projects: [Project]) -> NSPopUpButton {
        let popup = NSPopUpButton()
        popup.autoenablesItems = false
        for project in projects {
            popup.addItem(withTitle: project.isPaused ? "\(project.name) (paused)" : project.name)
            popup.lastItem?.isEnabled = !project.isPaused
            popup.lastItem?.representedObject = project.id
        }
        if let firstReady = projects.firstIndex(where: { !$0.isPaused }) { popup.selectItem(at: firstReady) }
        return popup
    }

    private func indented(_ views: [NSView]) -> NSView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 4, right: 0)
        return stack
    }

    @objc private func choiceChanged() {
        let isNew = newRadio?.state == .on
        organizationPopup?.isEnabled = isNew
        regionPopup?.isEnabled = isNew
        projectPopup?.isEnabled = !isNew
    }

    private var selectedTarget: SetupTarget? {
        if newRadio?.state == .on {
            let org = organizations[max(0, organizationPopup?.indexOfSelectedItem ?? 0)]
            let region = SupabaseRegion.all[max(0, regionPopup?.indexOfSelectedItem ?? 0)]
            return .newProject(organization: org, region: region)
        }
        let ref = projectPopup?.selectedItem?.representedObject as? String
        guard let project = choices?.existing.first(where: { $0.id == ref }), !project.isPaused else { return nil }
        return .existing(project)
    }

    // MARK: Installing

    @objc private func install() {
        guard let target = selectedTarget else { return }
        work = Task { [weak self] in await self?.install(target) }
    }

    private func install(_ target: SetupTarget) async {
        guard let api, await confirmSharedProject(target, api: api) else { return }
        var isNew = false
        if case .newProject = target { isNew = true }
        let list = SetupProgressList(includesNewProject: isNew)
        show(SetupPages.page(title: "Setting up Mox",
                             body: "Keep this window open. You can keep using your Mac meanwhile.",
                             content: [list.view]))
        var created: Project?
        isProvisioning = true
        defer { isProvisioning = false }
        do {
            let project: Project
            switch target {
            case .existing(let existing):
                project = existing
            case .newProject(let organization, let region):
                list.creatingProject()
                project = try await api.createProject(name: "Mox", organization: organization.id,
                                                      region: region.code,
                                                      databasePassword: Self.randomDatabasePassword())
                created = project
            }
            let settings = try await provision(project, api: api, list: list)
            onFinished(settings)
            close()
        } catch {
            // Closing the window cancels the work; there's nobody to tell.
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            if let created, let choices {
                self.choices = SetupChoices(projects: choices.existing + [created])
                preferredProjectID = created.id
            } else if case .existing(let project) = target {
                preferredProjectID = project.id
            }
            _ = await alert("Mox couldn't finish setting up", error.localizedDescription)
            showChoices()
        }
    }

    /// Runs the provisioner, asking first before replacing another Mox user.
    private func provision(_ project: Project, api: ManagementAPI,
                           list: SetupProgressList) async throws -> MoxSettings {
        let provisioner = Provisioner(api: api)
        let progress: (ProvisioningStep) -> Void = { step in
            DispatchQueue.main.async { list.show(step) }
        }
        do {
            return try await provisioner.provision(project: project, progress: progress)
        } catch ProvisioningError.alreadyInstalled {
            let answer = await alert("Mox is already set up in “\(project.name)”",
                                     "Setting it up again creates a new Mox user. Phones and computers paired "
                                        + "with this project stop receiving until you pair them again.",
                                     buttons: ["Set Up Again", "Cancel"])
            guard answer == 0 else { throw CancellationErrorShowingChoices() }
            return try await provisioner.provision(project: project, replaceExistingOwner: true, progress: progress)
        }
    }

    /// Warns when other people administer the project, because they could
    /// read what goes through Mox (#78). Returns false if the person backs out.
    private func confirmSharedProject(_ target: SetupTarget, api: ManagementAPI) async -> Bool {
        guard let members = try? await api.members(organization: target.organizationID) else { return true }
        let others = SharedProjectCheck.otherAdmins(members)
        guard !others.isEmpty else { return true }
        let answer = await alert(
            "Other people can manage this project",
            "These accounts administer this Supabase organization: \(others.joined(separator: ", ")). "
                + "They could see the files you send with Mox. If that matters, choose a project only you manage.",
            buttons: ["Install Anyway", "Choose Another"])
        return answer == 0
    }

    /// The new project's database password. Mox never needs it again, and it
    /// can be reset from the Supabase dashboard.
    static func randomDatabasePassword() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "A").replacingOccurrences(of: "/", with: "B")
    }
}

/// The person declined to replace an existing install: back to the choices.
struct CancellationErrorShowingChoices: LocalizedError {
    var errorDescription: String? { "Nothing was changed. Choose another project, or set this one up again." }
}
