using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace Mox.Tray;

/// <summary>What Ctrl+Shift+M sends: the file selected in Explorer, or else what's copied.</summary>
internal static partial class WhatToSend
{
    public abstract record Item;

    public sealed record FileItem(string Path) : Item;

    public sealed record TextItem(string Text) : Item;

    /// <summary>Call on the UI thread, right when the hotkey is pressed.</summary>
    public static Item? Pick()
    {
        var foreground = GetForegroundWindow();
        return ExplorerSelection(foreground) ?? Copied();
    }

    /// <summary>The first file selected in the Explorer window in front, if that's what's in front.</summary>
    private static FileItem? ExplorerSelection(IntPtr foreground)
    {
        try
        {
            var shellType = Type.GetTypeFromProgID("Shell.Application");
            if (shellType is null)
            {
                return null;
            }

            dynamic shell = Activator.CreateInstance(shellType)!;
            foreach (var window in shell.Windows())
            {
                if (window is null || new IntPtr((long)window.HWND) != foreground)
                {
                    continue;
                }

                foreach (var selected in window.Document.SelectedItems())
                {
                    string path = selected.Path;
                    if (File.Exists(path))
                    {
                        return new FileItem(path);
                    }
                }
            }
        }
        catch (Exception error) when (error is COMException or InvalidCastException or Microsoft.CSharp.RuntimeBinder.RuntimeBinderException)
        {
            // Not an Explorer window, or it has no file view: fall back to the clipboard.
        }

        return null;
    }

    private static Item? Copied()
    {
        if (Clipboard.ContainsFileDropList())
        {
            var file = Clipboard.GetFileDropList().Cast<string>().FirstOrDefault(File.Exists);
            if (file is not null)
            {
                return new FileItem(file);
            }
        }

        if (Clipboard.ContainsImage() && Clipboard.GetImage() is { } image)
        {
            var path = Path.Combine(Path.GetTempPath(), $"Image {DateTime.Now:yyyy-MM-dd HH.mm.ss}.png");
            image.Save(path, ImageFormat.Png);
            image.Dispose();
            return new FileItem(path);
        }

        return Clipboard.ContainsText() ? new TextItem(Clipboard.GetText()) : null;
    }

    [LibraryImport("user32.dll")]
    private static partial IntPtr GetForegroundWindow();
}
