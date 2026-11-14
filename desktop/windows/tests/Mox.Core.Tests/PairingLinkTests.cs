using System.Text.Json;

namespace Mox.Core.Tests;

/// <summary>Runs PairingLink against shared/fixtures/pairing/, like the Mac, Android and the pairing page.</summary>
public class PairingLinkTests
{
    public static TheoryData<string> Valid() => [.. Fixtures.Files("pairing/valid", "txt")];
    public static TheoryData<string> Invalid() => [.. Fixtures.Files("pairing/invalid", "txt")];

    [Theory]
    [MemberData(nameof(Valid))]
    public void Parses_every_valid_fixture_exactly(string file)
    {
        var expected = JsonDocument.Parse(File.ReadAllText(Path.ChangeExtension(file, ".json"))).RootElement;
        var parsed = PairingLink.Parse(Fixtures.Text(file));
        Assert.Equal(expected.GetProperty("projectUrl").GetString(), parsed.ProjectUrl);
        Assert.Equal(expected.GetProperty("publishableKey").GetString(), parsed.PublishableKey);
        Assert.Equal(expected.GetProperty("email").GetString(), parsed.Email);
        Assert.Equal(expected.GetProperty("password").GetString(), parsed.Password);
        var name = expected.GetProperty("desktopName");
        Assert.Equal(name.ValueKind == JsonValueKind.Null ? null : name.GetString(), parsed.DesktopName);
    }

    [Theory]
    [MemberData(nameof(Invalid))]
    public void Refuses_every_invalid_fixture(string file)
    {
        Assert.Throws<PairingException>(() => PairingLink.Parse(Fixtures.Text(file)));
    }

    [Fact]
    public void There_are_fixtures_to_test()
    {
        Assert.True(Valid().Count >= 6);
        Assert.True(Invalid().Count >= 12);
    }

    [Fact]
    public void A_plus_sign_is_never_a_space()
    {
        var link = "mox://pair?v=1&u=https%3A%2F%2Fa.supabase.co&k=sb_publishable_x&e=mox+desk%40mox.invalid&p=0123456789abcdef";
        Assert.Equal("mox+desk@mox.invalid", PairingLink.Parse(link).Email);
    }

    [Fact]
    public void A_built_link_parses_back_to_the_same_settings()
    {
        var settings = new MoxSettings(new Uri("https://abcd.supabase.co"), "sb_publishable_x", "mox+1@mox.invalid", "pass word/&=+0123456");
        var link = PairingLink.Parse(PairingLink.Build(settings, "Ana's PC"));
        Assert.Equal(settings, link.ToSettings() with { ProjectUrl = new Uri("https://abcd.supabase.co") });
        Assert.Equal("Ana's PC", link.DesktopName);
    }
}
