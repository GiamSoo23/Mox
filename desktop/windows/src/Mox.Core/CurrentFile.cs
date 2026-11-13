using System.Text.Json.Serialization;

namespace Mox.Core;

/// <summary>A row the protocol's rules refuse (shared/PROTOCOL.md §5).</summary>
public sealed class InvalidRowException(string reason)
    : Exception($"The current item in your project isn't valid: {reason}.");

/// <summary>
/// The single row of mox.current_file: the item in the slot right now
/// (shared/PROTOCOL.md §5). Unknown columns are ignored, so newer schemas
/// don't break this app.
/// </summary>
public sealed record CurrentFile
{
    public const long MaxSize = 52_428_800;
    private static readonly HashSet<string> Platforms = ["macos", "windows", "android", "ios"];

    [JsonPropertyName("id")] public int Id { get; init; }
    [JsonPropertyName("original_name")] public string? OriginalName { get; init; }
    [JsonPropertyName("mime_type")] public string? MimeType { get; init; }
    [JsonPropertyName("size_bytes")] public long SizeBytes { get; init; }
    [JsonPropertyName("kind")] public string? Kind { get; init; }
    [JsonPropertyName("item_count")] public int ItemCount { get; init; }
    [JsonPropertyName("source_platform")] public string? SourcePlatform { get; init; }
    [JsonPropertyName("source_device_id")] public string? SourceDeviceId { get; init; }
    [JsonPropertyName("uploaded_at")] public string? UploadedAt { get; init; }

    /// <summary>Text to paste, not a file to save (#101).</summary>
    [JsonIgnore] public bool IsText => Kind == "text";

    /// <summary>Checks the rules of §5, so a bad row gets a clear message.</summary>
    public CurrentFile Validate()
    {
        if (Id != 1)
        {
            throw new InvalidRowException("id must be 1");
        }

        var nameLength = OriginalName?.EnumerateRunes().Count() ?? 0;
        if (nameLength is < 1 or > 255)
        {
            throw new InvalidRowException("the name must be 1–255 characters");
        }

        if (SizeBytes is < 1 or > MaxSize)
        {
            throw new InvalidRowException("the size must be 1 byte to 50 MB");
        }

        var single = Kind is "file" or "text" && ItemCount == 1;
        var bundle = Kind == "bundle" && ItemCount >= 2;
        if (!single && !bundle)
        {
            throw new InvalidRowException($"kind {Kind} can't have {ItemCount} items");
        }

        if (SourcePlatform is null || !Platforms.Contains(SourcePlatform))
        {
            throw new InvalidRowException($"unknown platform {SourcePlatform}");
        }

        if (!Guid.TryParse(SourceDeviceId, out _))
        {
            throw new InvalidRowException("the sending device is missing");
        }

        return this;
    }
}
