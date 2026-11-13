using Mox.Core.Setup;

namespace Mox.Core.Tests;

public class SetupTests
{
    [Fact]
    public void Every_backend_migration_is_bundled_in_order()
    {
        var repo = Directory.GetParent(Fixtures.Root)!.Parent!.FullName;
        var onDisk = Directory.GetFiles(Path.Combine(repo, "backend", "supabase", "migrations"), "*.sql")
            .Select(Path.GetFileNameWithoutExtension).Order(StringComparer.Ordinal).ToList();
        Assert.Equal(onDisk, BundledFiles.Migrations.Select(m => $"{m.Version}_{m.Name}").ToList());
        Assert.All(BundledFiles.Migrations, m => Assert.False(string.IsNullOrWhiteSpace(m.Sql)));
    }

    [Fact]
    public void Both_iPhone_functions_are_bundled_without_their_tests()
    {
        Assert.Equal(["mox-push", "mox-send"], BundledFiles.Functions.Select(f => f.Slug).ToList());
        Assert.All(BundledFiles.Functions, f =>
        {
            Assert.Contains(f.Files, file => file.Name == "index.ts");
            Assert.DoesNotContain(f.Files, file => file.Name.EndsWith("_test.ts", StringComparison.Ordinal));
        });
    }

    [Fact]
    public void The_callback_gives_the_code_only_with_the_right_state()
    {
        Assert.Equal("abc", SupabaseOAuth.ParseCallback("GET /callback?code=abc&state=s1 HTTP/1.1", "s1"));
        Assert.Null(SupabaseOAuth.ParseCallback("GET /favicon.ico HTTP/1.1", "s1"));
        Assert.Throws<ManagementException>(() => SupabaseOAuth.ParseCallback("GET /callback?code=abc&state=evil HTTP/1.1", "s1"));
        Assert.Throws<ManagementException>(() => SupabaseOAuth.ParseCallback("GET /callback?error=access_denied&state=s1 HTTP/1.1", "s1"));
    }

    [Fact]
    public void Pkce_challenge_matches_the_RFC_example()
    {
        // RFC 7636, appendix B.
        var verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk";
        var challenge = Provisioner.Base64Url(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.ASCII.GetBytes(verifier)));
        Assert.Equal("E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", challenge);
    }

    [Fact]
    public void Generated_passwords_are_long_and_random()
    {
        var a = Provisioner.RandomPassword();
        Assert.Equal(32, a.Length);
        Assert.NotEqual(a, Provisioner.RandomPassword());
    }

    [Fact]
    public void Only_builds_with_a_secret_offer_Sign_in_with_Supabase()
    {
        Assert.Null(OAuthClient.Mox(null));
        Assert.Null(OAuthClient.Mox(""));
        Assert.Equal("http://localhost:53682/callback", OAuthClient.RedirectUri);
    }
}
