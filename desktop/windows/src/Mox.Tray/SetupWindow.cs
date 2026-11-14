using System.Diagnostics;
using System.Reflection;
using Mox.Core;
using Mox.Core.Setup;

namespace Mox.Tray;

/// <summary>
/// The setup window (#33), like the Mac's: sign in to Supabase (or paste an
/// access token), choose where Mox lives, set it up, then pair a phone.
/// </summary>
internal sealed class SetupWindow : Form
{
    private const string Tokens = "https://supabase.com/dashboard/account/tokens";
    private static readonly string[] Regions = ["us-east-1", "us-west-1", "sa-east-1", "eu-central-1", "eu-west-2", "ap-southeast-1", "ap-northeast-1"];
    private readonly HttpClient http;
    private readonly Action<MoxSettings> finished;
    private readonly OAuthClient? oauth = OAuthClient.Mox(typeof(SetupWindow).Assembly
        .GetCustomAttributes<AssemblyMetadataAttribute>().FirstOrDefault(a => a.Key == "MoxOAuthSecret")?.Value);
    private CancellationTokenSource? signIn;
    private ManagementApi? api;
    private bool working;

    public SetupWindow(HttpClient http, Action<MoxSettings> finished)
    {
        this.http = http;
        this.finished = finished;
        Text = "Set Up Mox";
        ClientSize = new Size(380, 460);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        BackColor = Color.White;
        Icon = TrayApp.LoadIcon();
        FormClosing += (_, e) =>
        {
            // Stopping while the project changes could leave it half set up (#117).
            if (working)
            {
                e.Cancel = true;
                MessageBox.Show("Mox is still setting up. It only takes a moment more.", "Mox");
            }
            else
            {
                signIn?.Cancel();
            }
        };
        ShowWelcome();
    }

    private void Page(params Control[] controls)
    {
        Controls.Clear();
        Controls.AddRange(controls);
    }

    private static LinkLabel Link(string text, int top, Action click)
    {
        var link = new LinkLabel { Text = text, AutoSize = false, Bounds = new Rectangle(24, top, 332, 24), TextAlign = ContentAlignment.MiddleCenter, LinkColor = Ui.Navy };
        link.LinkClicked += (_, _) => click();
        return link;
    }

    private static void Open(string url) => Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });

    private void ShowWelcome(string? error = null)
    {
        var start = oauth is null ? Ui.PrimaryButton("Continue", new Point(120, 300)) : Ui.PrimaryButton("Sign in", new Point(120, 300));
        start.Click += (_, _) =>
        {
            if (oauth is null)
            {
                ShowToken();
            }
            else
            {
                SignInWithSupabase(oauth);
            }
        };
        Page(
            Ui.Title("Welcome to Mox", 30),
            Ui.Note("Mox keeps the files you send in your own free Supabase project, so nobody else holds your data. " +
                "Sign in to Supabase and Mox sets everything up for you.", 80),
            Ui.Note(error ?? "", 150, Color.Firebrick),
            Link("New to Supabase? Create a free account first", 220, () => Open("https://supabase.com/dashboard/sign-up")),
            Link("Use an access token instead", 250, ShowToken),
            start);
    }

    private async void SignInWithSupabase(OAuthClient client)
    {
        var pkce = Pkce.Generate();
        var state = Pkce.Generate().Verifier;
        signIn = new CancellationTokenSource();
        var cancel = Ui.SecondaryButton("Cancel", new Point(120, 300));
        cancel.Click += (_, _) => signIn.Cancel();
        Page(Ui.Title("Finish in your browser", 30), Ui.Note("Choose your organization and allow Mox, then come back here.", 90), cancel);
        try
        {
            var waiting = SupabaseOAuth.WaitForCodeAsync(state, signIn.Token);
            Open(SupabaseOAuth.AuthorizationUrl(client, pkce, state).ToString());
            var code = await waiting;
            api = new ManagementApi(await SupabaseOAuth.ExchangeAsync(http, client, pkce, code), http);
            Activate();
            await ShowChoicesAsync();
        }
        catch (OperationCanceledException)
        {
            ShowWelcome();
        }
        catch (Exception error) when (error is ManagementException or HttpRequestException)
        {
            ShowWelcome(error.Message);
        }
    }

    private void ShowToken()
    {
        var token = new TextBox { UseSystemPasswordChar = true, Bounds = new Rectangle(24, 200, 332, 28), PlaceholderText = "sbp_…" };
        var next = Ui.PrimaryButton("Continue", new Point(200, 300));
        var back = Ui.SecondaryButton("Back", new Point(40, 300));
        back.Click += (_, _) => ShowWelcome();
        next.Click += async (_, _) =>
        {
            api = new ManagementApi(token.Text.Trim(), http);
            await ShowChoicesAsync();
        };
        Page(
            Ui.Title("Use an access token", 30),
            Ui.Note("Create a token in your Supabase account and paste it here. Mox uses it only for this setup and doesn't keep it.", 80),
            Link("Open Supabase access tokens", 160, () => Open(Tokens)),
            token, back, next);
        AcceptButton = next;
    }

    private async Task ShowChoicesAsync()
    {
        Page(Ui.Title("Looking at your account…", 30));
        List<Organization> organizations;
        List<Project> projects;
        try
        {
            organizations = await api!.OrganizationsAsync();
            projects = await api.ProjectsAsync();
        }
        catch (Exception error) when (error is ManagementException or HttpRequestException)
        {
            ShowWelcome(error.Message);
            return;
        }

        if (organizations.Count == 0)
        {
            ShowWelcome("Your Supabase account has no organization yet. Create one in the Supabase dashboard, then sign in again.");
            return;
        }

        var usable = projects.Where(p => !p.IsPaused && p.Status is not ("REMOVED" or "GOING_DOWN" or "INIT_FAILED")).OrderBy(p => p.Name, StringComparer.CurrentCultureIgnoreCase).ToList();
        var atLimit = usable.Count >= 2;
        var create = new RadioButton { Text = "Create a new project called \"Mox\"", Bounds = new Rectangle(24, 80, 332, 24), Checked = !atLimit || usable.Count == 0 };
        var organization = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Bounds = new Rectangle(44, 110, 312, 28), DataSource = organizations, DisplayMember = "Name" };
        var region = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Bounds = new Rectangle(44, 145, 312, 28), DataSource = Regions };
        var existing = new RadioButton { Text = "Install in a project you already have", Bounds = new Rectangle(24, 195, 332, 24), Checked = !create.Checked, Enabled = usable.Count > 0 };
        var project = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Bounds = new Rectangle(44, 225, 312, 28), DataSource = usable, DisplayMember = "Name" };
        var note = Ui.Note(atLimit
            ? "Your account already has 2 active projects, the free plan's limit, so installing in one of them is recommended. Mox keeps to its own \"mox\" schema."
            : "A new project is recommended. Supabase takes a few minutes to start it.", 265);
        var install = Ui.PrimaryButton("Install Mox", new Point(120, 360));
        install.Click += async (_, _) =>
        {
            Project? target = existing.Checked ? project.SelectedItem as Project : null;
            await InstallAsync(target, (Organization)organization.SelectedItem!, (string)region.SelectedItem!);
        };
        Page(Ui.Title("Where should Mox keep your files?", 24), create, organization, region, existing, project, note, install);
    }

    private async Task InstallAsync(Project? existing, Organization organization, string region)
    {
        var organizationId = existing?.OrganizationId ?? organization.Id;
        try
        {
            var members = await api!.MembersAsync(organizationId);
            if (members.Count > 1 && MessageBox.Show(
                $"These accounts manage this Supabase organization: {string.Join(", ", members.Select(m => m.Email ?? m.UserId))}. " +
                "They could see the files you send with Mox. Install anyway?", "Other people can manage this project",
                MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes)
            {
                return;
            }
        }
        catch (ManagementException)
        {
            // Not knowing the members isn't a reason to stop.
        }

        var steps = new ListBox { Bounds = new Rectangle(24, 80, 332, 260), BorderStyle = BorderStyle.None, Font = new Font("Segoe UI", 10) };
        Page(Ui.Title("Setting up Mox", 30), steps);
        working = true;
        try
        {
            var project = existing;
            if (project is null)
            {
                steps.Items.Add("Creating the project…");
                project = await api!.CreateProjectAsync("Mox", organization.Id, region, Provisioner.RandomPassword());
            }

            var provisioner = new Provisioner(api!, http);
            provisioner.Progress += (step, detail) => BeginInvoke(() => steps.Items.Add(Describe(step, detail)));
            MoxSettings settings;
            try
            {
                settings = await provisioner.ProvisionAsync(project);
            }
            catch (ProvisioningException installed) when (installed.AlreadyInstalled)
            {
                working = false;
                if (MessageBox.Show(installed.Message + " Set it up again?", "Mox", MessageBoxButtons.YesNo) != DialogResult.Yes)
                {
                    await ShowChoicesAsync();
                    return;
                }

                working = true;
                settings = await provisioner.ProvisionAsync(project, replaceExistingOwner: true);
            }

            working = false;
            finished(settings);
            Close();
        }
        catch (Exception error) when (error is ManagementException or ProvisioningException or HttpRequestException)
        {
            working = false;
            MessageBox.Show(error.Message, "Mox couldn't finish setting up", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            await ShowChoicesAsync();
        }
    }

    private static string Describe(ProvisioningStep step, string? detail) => step switch
    {
        ProvisioningStep.WaitingForProject => "Waiting for the project to start…",
        ProvisioningStep.ApplyingMigrations => $"Adding Mox's tables ({detail})",
        ProvisioningStep.ExposingSchema => "Turning on Mox's API",
        ProvisioningStep.CreatingMoxUser => "Creating the Mox user",
        ProvisioningStep.SettingOwner => "Making that user the only one allowed in",
        ProvisioningStep.ReadingKey => "Reading the app key",
        ProvisioningStep.SettingUpPush => detail ?? "Setting up iPhone support",
        _ => "✓ Done",
    };
}
