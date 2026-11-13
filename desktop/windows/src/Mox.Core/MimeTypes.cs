namespace Mox.Core;

/// <summary>The type stored with a sent file, from its extension.</summary>
public static class MimeTypes
{
    private static readonly Dictionary<string, string> ByExtension = new(StringComparer.OrdinalIgnoreCase)
    {
        ["jpg"] = "image/jpeg", ["jpeg"] = "image/jpeg", ["png"] = "image/png", ["gif"] = "image/gif",
        ["heic"] = "image/heic", ["webp"] = "image/webp", ["mp4"] = "video/mp4", ["mov"] = "video/quicktime",
        ["pdf"] = "application/pdf", ["txt"] = "text/plain", ["zip"] = "application/zip",
        ["docx"] = "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        ["xlsx"] = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        ["pptx"] = "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    };

    public static string ForPath(string path) =>
        ByExtension.TryGetValue(Path.GetExtension(path).TrimStart('.'), out var mime) ? mime : "application/octet-stream";
}
