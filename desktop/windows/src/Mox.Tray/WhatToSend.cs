using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace Mox.Tray;

/// <summary>What Ctrl+Shift+M sends: the file selected in Explorer, or else what's copied.</summary>
internal static partial class WhatToSend
{
    public abstract record Item;

    /// <summary>One file, or several files and folders sent as a bundle.</summary>
    public sealed record FilesItem(IReadOnlyList<string> Paths) : Item;

    public sealed record TextItem(string Text) : Item;

    /// <summary>Call on the UI thread, right when the hotkey is pressed.</summary>
    public static Item? Pick()
    {
        var foreground = GetForegroundWindow();
        return ExplorerSelection(foreground) ?? Copied();
    }

    /// <summary>The files and folders selected in the Explorer window in front, if that's what's in front.</summary>
    private static FilesItem? ExplorerSelection(IntPtr foreground)
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

                var paths = new List<string>();
                foreach (var selected in window.Document.SelectedItems())
                {
                    string path = selected.Path;
                    if (File.Exists(path) || Directory.Exists(path))
                    {
                        paths.Add(path);
                    }
                }

                return paths.Count > 0 ? new FilesItem(paths) : null;
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
            var paths = Clipboard.GetFileDropList().Cast<string>()
                .Where(path => File.Exists(path) || Directory.Exists(path)).ToList();
            if (paths.Count > 0)
            {
                return new FilesItem(paths);
            }
        }

        if (Clipboard.ContainsImage() && Clipboard.GetImage() is { } image)
        {
            var path = Path.Combine(Path.GetTempPath(), $"Image {DateTime.Now:yyyy-MM-dd HH.mm.ss}.png");
            image.Save(path, ImageFormat.Png);
            image.Dispose();
            return new FilesItem([path]);
        }

        return Clipboard.ContainsText() ? new TextItem(Clipboard.GetText()) : null;
    }

    [LibraryImport("user32.dll")]
    private static partial IntPtr GetForegroundWindow();
}
