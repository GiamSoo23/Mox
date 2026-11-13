using System.Runtime.InteropServices;

namespace Mox.Tray;

/// <summary>A system-wide hotkey (Ctrl+Shift+M), through RegisterHotKey on a hidden window (#31).</summary>
internal sealed partial class HotKey : NativeWindow, IDisposable
{
    private const int WmHotKey = 0x0312;
    private const uint ModControl = 0x2, ModShift = 0x4, ModNoRepeat = 0x4000;
    private const int Id = 1;
    private readonly Action pressed;

    public HotKey(Keys key, Action pressed)
    {
        this.pressed = pressed;
        CreateHandle(new CreateParams());
        Registered = RegisterHotKey(Handle, Id, ModControl | ModShift | ModNoRepeat, (uint)key);
    }

    /// <summary>False when another app already uses the combination.</summary>
    public bool Registered { get; }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WmHotKey && m.WParam == Id)
        {
            pressed();
        }

        base.WndProc(ref m);
    }

    public void Dispose()
    {
        UnregisterHotKey(Handle, Id);
        DestroyHandle();
    }

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool RegisterHotKey(IntPtr window, int id, uint modifiers, uint key);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool UnregisterHotKey(IntPtr window, int id);
}
