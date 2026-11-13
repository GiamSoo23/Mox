namespace Mox.Tray;

/// <summary>
/// Pairs this PC by pasting a pairing link (on the Mac: Pair a Phone… → Copy
/// Link). The Windows setup window comes with #33.
/// </summary>
internal sealed class PairDialog : Form
{
    private readonly TextBox link = new() { Multiline = true, Height = 80, Dock = DockStyle.Top };

    public PairDialog()
    {
        Text = "Pair Mox";
        Width = 520;
        Height = 260;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        StartPosition = FormStartPosition.CenterScreen;
        MaximizeBox = false;
        MinimizeBox = false;
        var help = new Label
        {
            Text = "Paste the pairing link from Mox on your Mac (Pair a Phone… → Copy Link).",
            Dock = DockStyle.Top,
            Height = 40,
        };
        var ok = new Button { Text = "Pair", DialogResult = DialogResult.OK, Dock = DockStyle.Bottom, Height = 36 };
        Controls.Add(link);
        Controls.Add(help);
        Controls.Add(ok);
        AcceptButton = ok;
        Padding = new Padding(16);
    }

    public string Link => link.Text.Trim();
}
