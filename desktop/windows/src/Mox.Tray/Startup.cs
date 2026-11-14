using System.Diagnostics;
using Microsoft.Win32;

namespace Mox.Tray;

/// <summary>Starting with Windows, and keeping one copy running (#32).</summary>
internal static class Startup
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string Name = "Mox";
    private const string FirstRunFlag = "mox-started-before";

    /// <summary>Whether Mox opens when the person signs in to Windows.</summary>
    public static bool RunsAtLogin
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey);
            return key?.GetValue(Name) is string;
        }

        set
        {
            using var key = Registry.CurrentUser.CreateSubKey(RunKey);
            if (value)
            {
                key.SetValue(Name, $"\"{Environment.ProcessPath}\"");
            }
            else
            {
                key.DeleteValue(Name, throwOnMissingValue: false);
            }
        }
    }

    /// <summary>Turns on start-with-Windows once, on first launch. If the person turns it off, it stays off.</summary>
    public static void EnableOnFirstRun()
    {
        var flag = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Mox", FirstRunFlag);
        if (File.Exists(flag))
        {
            return;
        }

        RunsAtLogin = true;
        Directory.CreateDirectory(Path.GetDirectoryName(flag)!);
        File.WriteAllText(flag, "");
    }

    /// <summary>The newest Mox wins: an older copy still running is closed, as on the Mac (#140).</summary>
    public static void QuitOtherCopies()
    {
        using var current = Process.GetCurrentProcess();
        foreach (var other in Process.GetProcessesByName(current.ProcessName))
        {
            using (other)
            {
                if (other.Id == current.Id)
                {
                    continue;
                }

                try
                {
                    other.Kill();
                    other.WaitForExit(3000);
                }
                catch (Exception error) when (error is InvalidOperationException or System.ComponentModel.Win32Exception)
                {
                    // Already gone, or not ours to close.
                }
            }
        }
    }
}
