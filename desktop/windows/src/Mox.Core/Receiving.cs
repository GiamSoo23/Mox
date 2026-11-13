namespace Mox.Core;

/// <summary>Deciding what to receive (shared/PROTOCOL.md §6) and where to save it.</summary>
public static class Receiving
{
    /// <summary>Act only on items from other devices that weren't handled yet.</summary>
    public static bool IsNew(CurrentFile? item, Guid deviceId, string? lastHandled) =>
        item is not null
        && !string.Equals(item.SourceDeviceId, deviceId.ToString(), StringComparison.OrdinalIgnoreCase)
        && item.UploadedAt != lastHandled;

    /// <summary>A path in <paramref name="folder"/> that doesn't exist yet: name.ext, name (1).ext, …</summary>
    public static string UniquePath(string folder, string fileName)
    {
        var safe = string.Concat(fileName.Split(Path.GetInvalidFileNameChars()));
        if (safe.Length == 0)
        {
            safe = "File";
        }

        var stem = Path.GetFileNameWithoutExtension(safe);
        var extension = Path.GetExtension(safe);
        var candidate = Path.Combine(folder, safe);
        for (var n = 1; File.Exists(candidate); n++)
        {
            candidate = Path.Combine(folder, $"{stem} ({n}){extension}");
        }

        return candidate;
    }
}
