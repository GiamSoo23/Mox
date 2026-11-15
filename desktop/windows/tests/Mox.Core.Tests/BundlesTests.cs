using System.Text;
using System.Text.Json;
using Xunit;

namespace Mox.Core.Tests;

/// <summary>Bundles (PROTOCOL.md §9) against shared/fixtures/bundles/, like the Mac and Android.</summary>
public sealed class BundlesTests : IDisposable
{
    private readonly string temp = Path.Combine(Path.GetTempPath(), "mox-bundles-" + Guid.NewGuid());

    public BundlesTests() => Directory.CreateDirectory(temp);

    public void Dispose() => Directory.Delete(temp, recursive: true);

    [Fact]
    public void ValidFixturesUnpackToTheirFiles()
    {
        var zips = Fixtures.Files(Path.Combine("bundles", "valid"), "zip").ToList();
        Assert.NotEmpty(zips);
        foreach (var zip in zips)
        {
            using var json = JsonDocument.Parse(File.ReadAllText(Path.ChangeExtension(zip, ".json")));
            var expected = json.RootElement.GetProperty("files").EnumerateArray().Select(f => f.GetString()!).ToList();
            Assert.Equal(expected, Bundles.Read(File.ReadAllBytes(zip)).Select(e => e.Path).ToList());
        }
    }

    [Fact]
    public void InvalidFixturesAreRefused()
    {
        var zips = Fixtures.Files(Path.Combine("bundles", "invalid"), "zip").ToList();
        Assert.Equal(9, zips.Count);
        foreach (var zip in zips)
        {
            Assert.Throws<BundleRefusedException>(() => Bundles.Read(File.ReadAllBytes(zip)));
        }
    }

    [Fact]
    public void ExtractKeepsFoldersAndReturnsTopLevelItems()
    {
        var zip = Path.Combine(Fixtures.Root, "bundles", "valid", "folder-structure.zip");
        var folder = Path.Combine(temp, "out");
        var top = Bundles.Extract(File.ReadAllBytes(zip), folder);
        Assert.Equal(["Trip", "cover.txt"], top.Select(Path.GetFileName).ToList());
        Assert.Equal("two", File.ReadAllText(Path.Combine(folder, "Trip", "notes", "day2.txt")));
    }

    [Fact]
    public void WriteThenReadGivesTheSameFiles()
    {
        var photos = Path.Combine(temp, "Fotos");
        Directory.CreateDirectory(Path.Combine(photos, "día 1"));
        File.WriteAllText(Path.Combine(photos, "día 1", "a.txt"), "uno");
        File.WriteAllText(Path.Combine(photos, "b.txt"), "dos");
        File.WriteAllText(Path.Combine(photos, ".DS_Store"), "x");
        var note = Path.Combine(temp, "note.txt");
        File.WriteAllText(note, "tres");

        var items = Bundles.Items([photos, note]);
        Assert.Equal(["Fotos/b.txt", "Fotos/día 1/a.txt", "note.txt"], items.Select(i => i.Path).ToList());

        var entries = Bundles.Read(Bundles.Write(items));
        Assert.Equal(items.Select(i => i.Path), entries.Select(e => e.Path));
        Assert.Equal(["dos", "uno", "tres"], entries.Select(e => Encoding.UTF8.GetString(e.Data)).ToList());
    }

    [Fact]
    public void TooBigNamesTheBiggestFiles()
    {
        var half = (CurrentFile.MaxSize / 2) + 1;
        var items = new List<Bundles.Item> { new("big.mov", "x", half), new("bigger.mov", "x", half + 1) };
        var error = Assert.Throws<MoxException>(() => Bundles.Write(items));
        Assert.Contains("The biggest: bigger.mov", error.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void FileNameCountsTheFiles() => Assert.Equal("Mox – 5 files.zip", Bundles.FileName(5));
}
