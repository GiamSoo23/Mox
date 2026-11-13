using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Serialization;

namespace Mox.Core.Setup;

/// <summary>Mox's OAuth app on Supabase. The id is public; official builds carry the secret (#82).</summary>
public sealed record OAuthClient(string Id, string Secret)
{
    public const string MoxClientId = "eba42d5a-0991-450c-9f60-44865c10765e";
    public const int Port = 53682;
    public static string RedirectUri => $"http://localhost:{Port}/callback";

    /// <summary>Mox's OAuth app with <paramref name="secret"/>, or null when this build has none.</summary>
    public static OAuthClient? Mox(string? secret) => string.IsNullOrEmpty(secret) ? null : new OAuthClient(MoxClientId, secret);
}

/// <summary>A PKCE verifier and its S256 challenge (RFC 7636).</summary>
public sealed record Pkce(string Verifier, string Challenge)
{
    public static Pkce Generate()
    {
        var verifier = Provisioner.Base64Url(RandomNumberGenerator.GetBytes(64));
        return new Pkce(verifier, Provisioner.Base64Url(SHA256.HashData(Encoding.ASCII.GetBytes(verifier))));
    }
}

/// <summary>"Sign in with Supabase" (#33): OAuth with PKCE and a one-shot loopback listener, like the Mac.</summary>
public static class SupabaseOAuth
{
    public static Uri AuthorizationUrl(OAuthClient client, Pkce pkce, string state) => new(
        "https://api.supabase.com/v1/oauth/authorize?" + string.Join("&", new Dictionary<string, string>
        {
            ["client_id"] = client.Id, ["redirect_uri"] = OAuthClient.RedirectUri, ["response_type"] = "code",
            ["code_challenge"] = pkce.Challenge, ["code_challenge_method"] = "S256", ["state"] = state,
        }.Select(p => $"{p.Key}={Uri.EscapeDataString(p.Value)}")));

    public static async Task<string> ExchangeAsync(HttpClient http, OAuthClient client, Pkce pkce, string code)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, new Uri("https://api.supabase.com/v1/oauth/token"))
        {
            Content = new FormUrlEncodedContent(new Dictionary<string, string>
            {
                ["grant_type"] = "authorization_code", ["code"] = code,
                ["redirect_uri"] = OAuthClient.RedirectUri, ["code_verifier"] = pkce.Verifier,
            }),
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Basic",
            Convert.ToBase64String(Encoding.UTF8.GetBytes($"{client.Id}:{client.Secret}")));
        using var response = await http.SendAsync(request).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
        {
            throw new ManagementException("Supabase didn't accept the sign-in. Try again.", response.StatusCode);
        }

        return (await response.Content.ReadFromJsonAsync<TokenReply>().ConfigureAwait(false))!.AccessToken;
    }

    /// <summary>
    /// The code from a request line like <c>GET /callback?code=…&amp;state=… HTTP/1.1</c>,
    /// null for other requests. A wrong state is refused, so another page can't feed Mox a code.
    /// </summary>
    public static string? ParseCallback(string requestLine, string expectedState)
    {
        var parts = requestLine.Split(' ');
        if (parts.Length < 2 || parts[0] != "GET" || !parts[1].StartsWith("/callback", StringComparison.Ordinal))
        {
            return null;
        }

        var query = parts[1].Contains('?', StringComparison.Ordinal) ? parts[1][(parts[1].IndexOf('?', StringComparison.Ordinal) + 1)..] : "";
        var values = query.Split('&', StringSplitOptions.RemoveEmptyEntries)
            .Select(p => p.Split('=', 2))
            .GroupBy(p => p[0], StringComparer.Ordinal)
            .ToDictionary(g => g.Key, g => Uri.UnescapeDataString(g.First().ElementAtOrDefault(1) ?? ""), StringComparer.Ordinal);
        if (values.TryGetValue("error", out var error))
        {
            throw new ManagementException(values.GetValueOrDefault("error_description", error), HttpStatusCode.Forbidden);
        }

        if (values.GetValueOrDefault("state") != expectedState)
        {
            throw new ManagementException("The sign-in answer didn't match this request. Try again.", HttpStatusCode.Forbidden);
        }

        return values.TryGetValue("code", out var code) && code.Length > 0
            ? code
            : throw new ManagementException("Supabase didn't send a sign-in code. Try again.", HttpStatusCode.BadRequest);
    }

    /// <summary>Waits for the browser to come back to localhost:53682 and returns the code.</summary>
    public static async Task<string> WaitForCodeAsync(string expectedState, CancellationToken cancel)
    {
        var listeners = new[] { new TcpListener(IPAddress.Loopback, OAuthClient.Port), new TcpListener(IPAddress.IPv6Loopback, OAuthClient.Port) };
        var started = listeners.Where(TryStart).ToList();
        if (started.Count == 0)
        {
            throw new ManagementException(
                $"Another app is using port {OAuthClient.Port}, which Mox needs to finish signing in. Use an access token instead.",
                HttpStatusCode.Conflict);
        }

        try
        {
            while (true)
            {
                var accepts = started.Select(l => l.AcceptTcpClientAsync(cancel).AsTask()).ToList();
                using var connection = await await Task.WhenAny(accepts).ConfigureAwait(false);
                await using var stream = connection.GetStream();
                var buffer = new byte[16_384];
                var read = await stream.ReadAsync(buffer, cancel).ConfigureAwait(false);
                var firstLine = Encoding.UTF8.GetString(buffer, 0, read).Split("\r\n")[0];
                string? code;
                try
                {
                    code = ParseCallback(firstLine, expectedState);
                }
                catch (ManagementException failure)
                {
                    await RespondAsync(stream, $"Mox couldn't sign in: {failure.Message}", cancel).ConfigureAwait(false);
                    throw;
                }

                if (code is null)
                {
                    await RespondAsync(stream, null, cancel).ConfigureAwait(false);
                    continue;
                }

                await RespondAsync(stream, "Signed in. You can close this tab and go back to Mox.", cancel).ConfigureAwait(false);
                return code;
            }
        }
        finally
        {
            foreach (var listener in started)
            {
                listener.Stop();
            }
        }
    }

    private static bool TryStart(TcpListener listener)
    {
        try
        {
            listener.Start();
            return true;
        }
        catch (SocketException)
        {
            return false;
        }
    }

    private static async Task RespondAsync(Stream stream, string? message, CancellationToken cancel)
    {
        var body = message is null ? "" : $"<!DOCTYPE html><html><body style=\"font-family:sans-serif;text-align:center;margin-top:20vh\"><h2>{WebUtility.HtmlEncode(message)}</h2></body></html>";
        var bytes = Encoding.UTF8.GetBytes(body);
        var head = $"HTTP/1.1 {(message is null ? "404 Not Found" : "200 OK")}\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {bytes.Length}\r\nConnection: close\r\n\r\n";
        await stream.WriteAsync(Encoding.UTF8.GetBytes(head), cancel).ConfigureAwait(false);
        await stream.WriteAsync(bytes, cancel).ConfigureAwait(false);
    }

    private sealed record TokenReply([property: JsonPropertyName("access_token")] string AccessToken);
}
