using System.Reflection;

namespace Mox.Core.Setup;

/// <summary>
/// The backend files setup applies, embedded straight from backend/supabase/
/// at build time (see Mox.Core.csproj), so they can't drift from the repo.
/// </summary>
public static class BundledFiles
{
    public sealed record Migration(string Version, string Name, string Sql);

    public sealed record Function(string Slug, IReadOnlyList<(string Name, string Content)> Files);

    private static readonly Assembly Self = typeof(BundledFiles).Assembly;

    public static IReadOnlyList<Migration> Migrations { get; } = LoadMigrations();

    public static IReadOnlyList<Function> Functions { get; } = LoadFunctions();

    private static string Read(string resource)
    {
        using var stream = Self.GetManifestResourceStream(resource)
            ?? throw new InvalidOperationException($"Missing embedded file {resource}");
        using var reader = new StreamReader(stream);
        return reader.ReadToEnd();
    }

    private static List<Migration> LoadMigrations() =>
        [.. Self.GetManifestResourceNames()
            .Where(n => n.StartsWith("migrations/", StringComparison.Ordinal))
            .Order(StringComparer.Ordinal)
            .Select(n =>
            {
                var stem = Path.GetFileNameWithoutExtension(n["migrations/".Length..]);
                var underscore = stem.IndexOf('_', StringComparison.Ordinal);
                return new Migration(stem[..underscore], stem[(underscore + 1)..], Read(n));
            })];

    private static List<Function> LoadFunctions() =>
        [.. Self.GetManifestResourceNames()
            .Where(n => n.StartsWith("functions/", StringComparison.Ordinal))
            .Select(n => (Resource: n, Parts: n["functions/".Length..].Replace('\\', '/').Split('/')))
            .GroupBy(x => x.Parts[0], StringComparer.Ordinal)
            .OrderBy(g => g.Key, StringComparer.Ordinal)
            .Select(g => new Function(g.Key, [.. g.OrderBy(x => x.Parts[^1], StringComparer.Ordinal)
                .Select(x => (x.Parts[^1], Read(x.Resource)))]))];
}
