using System.Text.Json;

namespace Mox.Core.Tests;

/// <summary>Runs the row rules against shared/fixtures/rows/, like every other client and the database.</summary>
public class CurrentFileTests
{
    public static TheoryData<string> Valid() => [.. Fixtures.Files("rows/valid", "json")];
    public static TheoryData<string> Invalid() => [.. Fixtures.Files("rows/invalid", "json")];

    private static CurrentFile? Read(string file) => JsonSerializer.Deserialize<CurrentFile>(File.ReadAllText(file));

    [Theory]
    [MemberData(nameof(Valid))]
    public void Accepts_every_valid_row(string file)
    {
        var row = Read(file);
        Assert.NotNull(row);
        row.Validate();
    }

    [Theory]
    [MemberData(nameof(Invalid))]
    public void Refuses_every_invalid_row(string file)
    {
        Assert.Throws<InvalidRowException>(() => Read(file)?.Validate());
    }

    [Fact]
    public void A_text_row_is_text()
    {
        var file = Fixtures.Files("rows/valid", "json").Single(f => f.EndsWith("text-from-android.json", StringComparison.Ordinal));
        Assert.True(Read(file)!.Validate().IsText);
    }
}
