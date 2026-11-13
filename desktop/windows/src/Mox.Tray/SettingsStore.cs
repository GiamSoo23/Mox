using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Mox.Core;

namespace Mox.Tray;

/// <summary>
/// What Mox keeps on this PC, in %APPDATA%\Mox. The settings include the Mox
/// user's password, so they're encrypted with Windows' data protection for
/// this user (DPAPI) and only this Windows account can read them.
/// </summary>
internal static class SettingsStore
{
    private static readonly string Folder =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Mox");

    private static string SettingsFile => Path.Combine(Folder, "settings.bin");
    private static string StateFile => Path.Combine(Folder, "last-handled.txt");
    private static string DeviceFile => Path.Combine(Folder, "device-id.txt");

    public static MoxSettings? Load()
    {
        try
        {
            var bytes = ProtectedData.Unprotect(File.ReadAllBytes(SettingsFile), null, DataProtectionScope.CurrentUser);
            return JsonSerializer.Deserialize<MoxSettings>(Encoding.UTF8.GetString(bytes));
        }
        catch (Exception error) when (error is IOException or CryptographicException or JsonException or UnauthorizedAccessException)
        {
            return null;
        }
    }

    public static void Save(MoxSettings settings)
    {
        Directory.CreateDirectory(Folder);
        var bytes = Encoding.UTF8.GetBytes(JsonSerializer.Serialize(settings));
        File.WriteAllBytes(SettingsFile, ProtectedData.Protect(bytes, null, DataProtectionScope.CurrentUser));
        // A new pairing starts from whatever is in the slot now.
        File.Delete(StateFile);
    }

    /// <summary>This installation's id (shared/PROTOCOL.md §1).</summary>
    public static Guid DeviceId()
    {
        if (File.Exists(DeviceFile) && Guid.TryParse(File.ReadAllText(DeviceFile), out var saved))
        {
            return saved;
        }

        Directory.CreateDirectory(Folder);
        var fresh = Guid.NewGuid();
        File.WriteAllText(DeviceFile, fresh.ToString());
        return fresh;
    }

    public static string? LastHandled => File.Exists(StateFile) ? File.ReadAllText(StateFile) : null;

    public static void SetLastHandled(string value)
    {
        Directory.CreateDirectory(Folder);
        File.WriteAllText(StateFile, value);
    }
}
