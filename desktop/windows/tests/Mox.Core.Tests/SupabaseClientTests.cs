using System.Net;
using System.Text;

namespace Mox.Core.Tests;

/// <summary>The client against a fake Supabase: no network.</summary>
public class SupabaseClientTests
{
    private sealed class FakeSupabase : HttpMessageHandler
    {
        public List<(HttpMethod Method, string Path, string? Profile)> Calls { get; } = [];
        public int SignIns { get; private set; }
        public bool ExpireOnce { get; set; }

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancel)
        {
            var path = request.RequestUri!.PathAndQuery;
            var profile = request.Headers.TryGetValues("Accept-Profile", out var a) ? a.First()
                : request.Headers.TryGetValues("Content-Profile", out var c) ? c.First() : null;
            Calls.Add((request.Method, path, profile));
            if (path.StartsWith("/auth/v1/token", StringComparison.Ordinal))
            {
                SignIns++;
                return Reply("{\"access_token\":\"t\",\"expires_in\":3600}");
            }

            if (ExpireOnce)
            {
                ExpireOnce = false;
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.Unauthorized));
            }

            return path switch
            {
                _ when path.StartsWith("/rest/v1/meta", StringComparison.Ordinal) => Reply("[{\"schema_version\":2}]"),
                _ when path.StartsWith("/rest/v1/current_file?id=eq.1", StringComparison.Ordinal) => Reply(
                    "[{\"id\":1,\"original_name\":\"a.jpg\",\"mime_type\":\"image/jpeg\",\"size_bytes\":3,\"kind\":\"file\"," +
                    "\"item_count\":1,\"source_platform\":\"ios\",\"source_device_id\":\"22222222-2222-2222-2222-222222222222\"," +
                    "\"uploaded_at\":\"2026-11-13T12:00:00Z\"}]"),
                _ when path.StartsWith("/storage/v1/object/mox/current", StringComparison.Ordinal) => Reply("{}"),
                _ when path.StartsWith("/rest/v1/current_file?on_conflict=id", StringComparison.Ordinal) => Reply(
                    "[{\"id\":1,\"original_name\":\"Text.txt\",\"mime_type\":\"text/plain\",\"size_bytes\":4,\"kind\":\"text\"," +
                    "\"item_count\":1,\"source_platform\":\"windows\",\"source_device_id\":\"11111111-1111-1111-1111-111111111111\"," +
                    "\"uploaded_at\":\"2026-11-13T12:00:01Z\"}]"),
                _ => Task.FromResult(new HttpResponseMessage(HttpStatusCode.NotFound)),
            };
        }

        private static Task<HttpResponseMessage> Reply(string json) =>
            Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(json, Encoding.UTF8, "application/json") });
    }

    private static (SupabaseClient, FakeSupabase) Make()
    {
        var fake = new FakeSupabase();
        var settings = new MoxSettings(new Uri("https://ref.supabase.co"), "sb_publishable_x", "mox-1@mox.invalid", "0123456789abcdef");
        return (new SupabaseClient(settings, Guid.Parse("11111111-1111-1111-1111-111111111111"), new HttpClient(fake)), fake);
    }

    [Fact]
    public async Task Reads_the_slot_from_the_mox_schema()
    {
        var (client, fake) = Make();
        using var _ = client;
        var item = await client.FetchCurrentAsync();
        Assert.Equal("a.jpg", item!.OriginalName);
        Assert.Contains(fake.Calls, c => c.Path.StartsWith("/rest/v1/current_file", StringComparison.Ordinal) && c.Profile == "mox");
    }

    [Fact]
    public async Task Sends_bytes_before_the_row()
    {
        var (client, fake) = Make();
        using var _ = client;
        var row = await client.SendTextAsync("hola");
        Assert.True(row.IsText);
        var upload = fake.Calls.FindIndex(c => c.Path.StartsWith("/storage/v1/object/mox/current", StringComparison.Ordinal));
        var replace = fake.Calls.FindIndex(c => c.Path.StartsWith("/rest/v1/current_file?on_conflict", StringComparison.Ordinal));
        Assert.True(upload >= 0 && replace > upload);
    }

    [Fact]
    public async Task Signs_in_again_once_after_a_401()
    {
        var (client, fake) = Make();
        using var _ = client;
        fake.ExpireOnce = true;
        await client.CheckSchemaAsync();
        Assert.Equal(2, fake.SignIns);
    }
}
