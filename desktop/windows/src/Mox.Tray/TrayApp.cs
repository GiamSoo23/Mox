namespace Mox.Tray;

/// <summary>The notification-area icon and its menu. More arrives with #30–#33.</summary>
internal sealed class TrayApp : IDisposable
{
    private readonly NotifyIcon icon;

    public TrayApp()
    {
        var menu = new ContextMenuStrip();
        menu.Items.Add(new ToolStripMenuItem("Mox isn't set up yet") { Enabled = false });
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Quit Mox", null, (_, _) => Application.Exit());
        icon = new NotifyIcon
        {
            Icon = SystemIcons.Application,
            Text = "Mox",
            ContextMenuStrip = menu,
            Visible = true,
        };
    }

    public void Dispose()
    {
        icon.Visible = false;
        icon.Dispose();
    }
}
