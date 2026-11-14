using Mox.Core;
using QRCoder;

namespace Mox.Tray;

/// <summary>
/// "Pair a phone": the pairing link as a QR code (shared/PROTOCOL.md §8). It
/// carries the Mox password, so it's shown only on request.
/// </summary>
internal sealed class PairingWindow : Form
{
    private readonly string link;

    public PairingWindow(MoxSettings settings)
    {
        link = PairingLink.Build(settings, Environment.MachineName);
        Text = "Pair a Phone";
        ClientSize = new Size(380, 520);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        BackColor = Color.White;
        Icon = TrayApp.LoadIcon();

        using var generator = new QRCodeGenerator();
        using var data = generator.CreateQrCode(link, QRCodeGenerator.ECCLevel.M);
        var png = new PngByteQRCode(data).GetGraphic(8);
        var picture = new PictureBox
        {
            Image = Image.FromStream(new MemoryStream(png)),
            SizeMode = PictureBoxSizeMode.Zoom,
            Bounds = new Rectangle(40, 70, 300, 300),
        };
        Controls.Add(Ui.Title("Scan with your phone's camera", 20));
        Controls.Add(picture);
        Controls.Add(Ui.Note("This code contains your Mox password. Don't share it or send screenshots of it.", 385, Color.DarkOrange));
        var copy = Ui.SecondaryButton("Copy Link", new Point(40, 455));
        copy.Click += (_, _) =>
        {
            Clipboard.SetText(link);
            copy.Text = "Copied";
        };
        var done = Ui.PrimaryButton("Done", new Point(200, 455));
        done.Click += (_, _) => Close();
        Controls.Add(copy);
        Controls.Add(done);
        AcceptButton = done;
    }
}

/// <summary>Small helpers so every Mox window looks the same: navy and mint, like the logo.</summary>
internal static class Ui
{
    public static readonly Color Navy = Color.FromArgb(0x1a, 0x1b, 0x2e);
    public static readonly Color Mint = Color.FromArgb(0x5f, 0xcb, 0xa6);

    public static Label Title(string text, int top) => new()
    {
        Text = text, Font = new Font("Segoe UI", 14, FontStyle.Bold), ForeColor = Navy,
        AutoSize = false, Bounds = new Rectangle(24, top, 332, 36), TextAlign = ContentAlignment.MiddleCenter,
    };

    public static Label Note(string text, int top, Color? color = null) => new()
    {
        Text = text, Font = new Font("Segoe UI", 9), ForeColor = color ?? Color.DimGray,
        AutoSize = false, Bounds = new Rectangle(24, top, 332, 60), TextAlign = ContentAlignment.TopCenter,
    };

    public static Button PrimaryButton(string text, Point at) => Style(new Button { Text = text, Location = at }, Mint, Navy);

    public static Button SecondaryButton(string text, Point at) => Style(new Button { Text = text, Location = at }, Color.White, Navy);

    private static Button Style(Button button, Color back, Color fore)
    {
        button.Size = new Size(140, 40);
        button.FlatStyle = FlatStyle.Flat;
        button.FlatAppearance.BorderColor = Navy;
        button.BackColor = back;
        button.ForeColor = fore;
        button.Font = new Font("Segoe UI", 10, FontStyle.Bold);
        return button;
    }
}
