using System.Collections.Specialized;
using Mox.Core;

namespace Mox.Tray;

/// <summary>
/// The notification-area icon: pairing, polling the slot every 5 seconds, and
/// receiving into Downloads and the clipboard (shared/PROTOCOL.md §6).
/// </summary>
internal sealed class TrayApp : IDisposable
{
    private static readonly string Downloads =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");

    private readonly NotifyIcon icon;
    private readonly ToolStripMenuItem status = new("Mox isn't paired yet") { Enabled = false };
    private readonly ToolStripMenuItem latest = new("No file yet") { Enabled = false };
    private readonly System.Windows.Forms.Timer poll = new() { Interval = 5000 };
    private readonly HttpClient http = new();
    private readonly Guid deviceId = SettingsStore.DeviceId();
    private SupabaseClient? client;
    private bool busy;

    public TrayApp()
    {
        var menu = new ContextMenuStrip();
        menu.Items.Add(status);
        menu.Items.Add(latest);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Pair with a link…", null, (_, _) => Pair());
        menu.Items.Add("Quit Mox", null, (_, _) => Application.Exit());
        icon = new NotifyIcon { Icon = SystemIcons.Application, Text = "Mox", ContextMenuStrip = menu, Visible = true };
        poll.Tick += async (_, _) => await PollAsync();
        Connect(SettingsStore.Load());
    }

    private void Connect(MoxSettings? settings)
    {
        client = settings is null ? null : new SupabaseClient(settings, deviceId, http);
        status.Text = client is null ? "Mox isn't paired yet" : "Mox is ready";
        poll.Enabled = client is not null;
        if (client is null)
        {
            icon.ShowBalloonTip(5000, "Mox", "Right-click the Mox icon and choose Pair with a link….", ToolTipIcon.Info);
        }
    }

    private async void Pair()
    {
        using var dialog = new PairDialog();
        if (dialog.ShowDialog() != DialogResult.OK)
        {
            return;
        }

        try
        {
            var link = PairingLink.Parse(dialog.Link);
            var candidate = new SupabaseClient(link.ToSettings(), deviceId, http);
            await candidate.CheckSchemaAsync();
            SettingsStore.Save(link.ToSettings());
            Connect(link.ToSettings());
            icon.ShowBalloonTip(5000, "Mox", $"Paired with {link.DesktopName ?? "your computer"}.", ToolTipIcon.Info);
        }
        catch (Exception error) when (error is PairingException or MoxException or HttpRequestException)
        {
            MessageBox.Show(error.Message, "Mox couldn't pair", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
    }

    private async Task PollAsync()
    {
        if (client is null || busy)
        {
            return;
        }

        busy = true;
        try
        {
            var item = await client.FetchCurrentAsync();
            latest.Text = item is null ? "No file yet" : item.IsText ? "Text" : item.OriginalName;
            var lastHandled = SettingsStore.LastHandled;
            if (lastHandled is null)
            {
                // First look after pairing: what's already there isn't downloaded (#71).
                SettingsStore.SetLastHandled(item?.UploadedAt ?? "empty");
            }
            else if (Receiving.IsNew(item, deviceId, lastHandled))
            {
                SettingsStore.SetLastHandled(item!.UploadedAt!);
                await ReceiveAsync(item);
            }
        }
        catch (Exception error) when (error is MoxException or HttpRequestException or InvalidRowException or IOException)
        {
            status.Text = error.Message.Length > 60 ? error.Message[..60] + "…" : error.Message;
        }
        finally
        {
            busy = false;
        }
    }

    private async Task ReceiveAsync(CurrentFile item)
    {
        if (item.IsText)
        {
            using var buffer = new MemoryStream();
            await client!.DownloadAsync(buffer);
            Clipboard.SetText(TextPayload.Decode(buffer.ToArray()));
            icon.ShowBalloonTip(5000, "Text from your phone", "Copied. Paste it anywhere.", ToolTipIcon.Info);
            return;
        }

        Directory.CreateDirectory(Downloads);
        var path = Receiving.UniquePath(Downloads, item.OriginalName!);
        await using (var file = File.Create(path))
        {
            await client!.DownloadAsync(file);
        }

        // The file goes on the clipboard, so Ctrl+V pastes it in Explorer and in chats.
        var data = new DataObject();
        data.SetFileDropList(new StringCollection { path });
        if ((item.MimeType ?? "").StartsWith("image/", StringComparison.Ordinal))
        {
            using var image = Image.FromFile(path);
            data.SetImage(new Bitmap(image));
        }

        Clipboard.SetDataObject(data, true);
        icon.ShowBalloonTip(5000, "New file from your phone", $"{Path.GetFileName(path)} · in Downloads and on the clipboard", ToolTipIcon.Info);
    }

    public void Dispose()
    {
        poll.Dispose();
        http.Dispose();
        icon.Visible = false;
        icon.Dispose();
    }
}
