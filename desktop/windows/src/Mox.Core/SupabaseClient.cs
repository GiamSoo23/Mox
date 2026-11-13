using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json.Serialization;

namespace Mox.Core;

/// <summary>
/// Speaks the Mox protocol (shared/PROTOCOL.md §2–§4) to the owner's
/// Supabase project. No SDK, the same few calls as the Mac and Android apps.
/// </summary>
public sealed class SupabaseClient(MoxSettings settings, Guid deviceId, HttpClient http)
{
    private const string Bucket = "mox";
    private const string ObjectName = "current";
    private readonly string baseUrl = settings.ProjectUrl.ToString().TrimEnd('/');
    private readonly SemaphoreSlim tokenLock = new(1, 1);
    private string? token;
    private DateTimeOffset tokenExpiresAt;

    /// <summary>§4.1: signs in and checks this user owns Mox in the project.</summary>
    public async Task CheckSchemaAsync(CancellationToken cancel = default)
    {
        var rows = await GetJsonAsync<List<MetaRow>>("rest/v1/meta?select=schema_version", cancel).ConfigureAwait(false);
        if (rows is null || rows.Count == 0)
        {
            throw new MoxException("This pairing link is out of date. On your Mac, choose Pair a Phone… and copy a new one.");
        }

        if (rows[0].SchemaVersion != 2)
        {
            throw new MoxException($"Your project has Mox schema v{rows[0].SchemaVersion}, but this app needs v2.");
        }
    }

    /// <summary>§4.2: the item in the slot, or null when nothing was sent yet.</summary>
    public async Task<CurrentFile?> FetchCurrentAsync(CancellationToken cancel = default)
    {
        var rows = await GetJsonAsync<List<CurrentFile>>("rest/v1/current_file?id=eq.1&select=*", cancel).ConfigureAwait(false);
        return rows is { Count: > 0 } ? rows[0].Validate() : null;
    }

    /// <summary>§4.5 + §4.6: downloads the current item into <paramref name="destination"/>.</summary>
    public async Task DownloadAsync(Stream destination, CancellationToken cancel = default)
    {
        using var signRequest = new HttpRequestMessage(HttpMethod.Post, $"storage/v1/object/sign/{Bucket}/{ObjectName}")
        {
            Content = JsonContent.Create(new { expiresIn = 600 }),
        };
        using var signed = await SendAsync(signRequest, cancel).ConfigureAwait(false);
        var reply = await signed.Content.ReadFromJsonAsync<SignedUrl>(cancel).ConfigureAwait(false)
            ?? throw new MoxException("Supabase didn't return a download link.");
        using var download = await http.GetAsync(new Uri($"{baseUrl}/storage/v1{reply.Url}"), HttpCompletionOption.ResponseHeadersRead, cancel).ConfigureAwait(false);
        download.EnsureSuccessStatusCode();
        await download.Content.CopyToAsync(destination, cancel).ConfigureAwait(false);
    }

    /// <summary>§4.3 then §4.4: bytes first, then the row.</summary>
    public async Task<CurrentFile> SendFileAsync(string path, CancellationToken cancel = default)
    {
        var size = new FileInfo(path).Length;
        if (size <= 0)
        {
            throw new MoxException("The file is empty.");
        }

        if (size > CurrentFile.MaxSize)
        {
            throw new MoxException("That file is over 50 MB, the most Mox sends.");
        }

        var mime = MimeTypes.ForPath(path);
        await using (var file = File.OpenRead(path))
        {
            await UploadAsync(new StreamContent(file), mime, cancel).ConfigureAwait(false);
        }

        return await ReplaceRowAsync(Path.GetFileName(path), mime, size, "file", cancel).ConfigureAwait(false);
    }

    public async Task<CurrentFile> SendTextAsync(string text, CancellationToken cancel = default)
    {
        var bytes = TextPayload.Encode(text);
        await UploadAsync(new ByteArrayContent(bytes), TextPayload.Mime, cancel).ConfigureAwait(false);
        return await ReplaceRowAsync(TextPayload.FileName, TextPayload.Mime, bytes.Length, "text", cancel).ConfigureAwait(false);
    }

    private async Task UploadAsync(HttpContent content, string mime, CancellationToken cancel)
    {
        content.Headers.ContentType = new MediaTypeHeaderValue(mime);
        using var request = new HttpRequestMessage(HttpMethod.Post, $"storage/v1/object/{Bucket}/{ObjectName}") { Content = content };
        request.Headers.Add("x-upsert", "true");
        using var response = await SendAsync(request, cancel).ConfigureAwait(false);
    }

    private async Task<CurrentFile> ReplaceRowAsync(string name, string mime, long size, string kind, CancellationToken cancel)
    {
        var row = new Dictionary<string, object>
        {
            ["id"] = 1, ["original_name"] = name, ["mime_type"] = mime, ["size_bytes"] = size, ["kind"] = kind,
            ["item_count"] = 1, ["source_platform"] = "windows", ["source_device_id"] = deviceId.ToString(),
        };
        using var request = new HttpRequestMessage(HttpMethod.Post, "rest/v1/current_file?on_conflict=id") { Content = JsonContent.Create(row) };
        request.Headers.Add("Content-Profile", "mox");
        request.Headers.Add("Prefer", "resolution=merge-duplicates,return=representation");
        using var response = await SendAsync(request, cancel).ConfigureAwait(false);
        var rows = await response.Content.ReadFromJsonAsync<List<CurrentFile>>(cancel).ConfigureAwait(false);
        return rows is { Count: > 0 } ? rows[0] : throw new MoxException("Supabase didn't return the new row.");
    }

    private async Task<T?> GetJsonAsync<T>(string path, CancellationToken cancel)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, path);
        request.Headers.Add("Accept-Profile", "mox");
        using var response = await SendAsync(request, cancel).ConfigureAwait(false);
        return await response.Content.ReadFromJsonAsync<T>(cancel).ConfigureAwait(false);
    }

    /// <summary>Every call with a valid token; on 401, signs in again and retries once.</summary>
    private async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancel)
    {
        for (var attempt = 0; attempt < 2; attempt++)
        {
            using var copy = await CloneAsync(request, cancel).ConfigureAwait(false);
            copy.Headers.Authorization = new AuthenticationHeaderValue("Bearer", await AccessTokenAsync(attempt > 0, cancel).ConfigureAwait(false));
            copy.Headers.Add("apikey", settings.PublishableKey);
            var response = await http.SendAsync(copy, cancel).ConfigureAwait(false);
            if (response.StatusCode == HttpStatusCode.Unauthorized && attempt == 0)
            {
                response.Dispose();
                continue;
            }

            if (!response.IsSuccessStatusCode)
            {
                var body = await response.Content.ReadAsStringAsync(cancel).ConfigureAwait(false);
                response.Dispose();
                throw new MoxException($"Supabase answered HTTP {(int)response.StatusCode}: {body[..Math.Min(body.Length, 200)]}");
            }

            return response;
        }

        throw new MoxException("Couldn't sign in to your Supabase project. Pair again.");
    }

    /// <summary>A request can be sent once, so each attempt sends a copy. Bodies are buffered.</summary>
    private async Task<HttpRequestMessage> CloneAsync(HttpRequestMessage request, CancellationToken cancel)
    {
        var copy = new HttpRequestMessage(request.Method, new Uri($"{baseUrl}/{request.RequestUri}"));
        foreach (var header in request.Headers)
        {
            copy.Headers.TryAddWithoutValidation(header.Key, header.Value);
        }

        if (request.Content is not null)
        {
            var bytes = await request.Content.ReadAsByteArrayAsync(cancel).ConfigureAwait(false);
            copy.Content = new ByteArrayContent(bytes);
            foreach (var header in request.Content.Headers)
            {
                copy.Content.Headers.TryAddWithoutValidation(header.Key, header.Value);
            }
        }

        return copy;
    }

    /// <summary>§2: each device signs in as the Mox user with its own session.</summary>
    private async Task<string> AccessTokenAsync(bool renew, CancellationToken cancel)
    {
        await tokenLock.WaitAsync(cancel).ConfigureAwait(false);
        try
        {
            if (token is not null && !renew && tokenExpiresAt - DateTimeOffset.UtcNow > TimeSpan.FromMinutes(1))
            {
                return token;
            }

            using var request = new HttpRequestMessage(HttpMethod.Post, new Uri($"{baseUrl}/auth/v1/token?grant_type=password"))
            {
                Content = JsonContent.Create(new { email = settings.Email, password = settings.Password }),
            };
            request.Headers.Add("apikey", settings.PublishableKey);
            using var response = await http.SendAsync(request, cancel).ConfigureAwait(false);
            if (!response.IsSuccessStatusCode)
            {
                throw new MoxException("This computer's pairing is out of date. On your Mac, choose Pair a Phone… and copy a new link.");
            }

            var reply = await response.Content.ReadFromJsonAsync<TokenReply>(cancel).ConfigureAwait(false)
                ?? throw new MoxException("Supabase didn't return a session.");
            token = reply.AccessToken;
            tokenExpiresAt = DateTimeOffset.UtcNow.AddSeconds(reply.ExpiresIn);
            return token;
        }
        finally
        {
            tokenLock.Release();
        }
    }

    private sealed record MetaRow([property: JsonPropertyName("schema_version")] int SchemaVersion);

    private sealed record SignedUrl([property: JsonPropertyName("signedURL")] string Url);

    private sealed record TokenReply(
        [property: JsonPropertyName("access_token")] string AccessToken,
        [property: JsonPropertyName("expires_in")] int ExpiresIn);
}
