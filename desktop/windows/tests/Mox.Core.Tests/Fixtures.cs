namespace Mox.Core.Tests;

/// <summary>The shared fixtures every Mox client is tested against (shared/fixtures/).</summary>
internal static class Fixtures
{
    public static string Root { get; } = FindRoot();

    public static IEnumerable<string> Files(string folder, string extension) =>
        Directory.GetFiles(Path.Combine(Root, folder), "*." + extension).OrderBy(f => f, StringComparer.Ordinal);

    public static string Text(string path) => File.ReadAllText(path).Trim();

    private static string FindRoot()
    {
        for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir is not null; dir = dir.Parent)
        {
            var candidate = Path.Combine(dir.FullName, "shared", "fixtures");
            if (Directory.Exists(candidate))
            {
                return candidate;
            }
        }

        throw new DirectoryNotFoundException("shared/fixtures not found above the test output.");
    }
}
