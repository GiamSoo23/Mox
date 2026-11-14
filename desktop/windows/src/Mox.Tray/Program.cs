namespace Mox.Tray;

internal static class Program
{
    /// <summary>Mox lives in the notification area, with no main window (#29).</summary>
    [STAThread]
    private static void Main()
    {
        Startup.QuitOtherCopies();
        Startup.EnableOnFirstRun();
        ApplicationConfiguration.Initialize();
        using var tray = new TrayApp();
        Application.Run();
    }
}
