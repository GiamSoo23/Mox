using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Mox.Core.Setup;

public sealed record Organization([property: JsonPropertyName("id")] string Id, [property: JsonPropertyName("name")] string Name);

public sealed record OrganizationMember(
    [property: JsonPropertyName("user_id")] string UserId, [property: JsonPropertyName("email")] string? Email);

public sealed record Project(
    [property: JsonPropertyName("id")] string Id,
    [property: JsonPropertyName("organization_id")] string OrganizationId,
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("region")] string Region,
    [property: JsonPropertyName("status")] string Status)
{
    public Uri Url => new($"https://{Id}.supabase.co");
    public bool IsReady => Status == "ACTIVE_HEALTHY";
    public bool IsPaused => Status == "INACTIVE";
}

public sealed record ApiKey(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("type")] string? Type,
    [property: JsonPropertyName("api_key")] string? Value);

/// <summary>An answer from Supabase's management API that setup can explain.</summary>
public sealed class ManagementException(string message, HttpStatusCode status) : Exception(message)
{
    public HttpStatusCode Status { get; } = status;
}

/// <summary>
/// The Supabase Management API calls setup needs, with an OAuth or personal
/// access token. Same calls as the Mac's ManagementAPI.swift.
/// </summary>
public sealed class ManagementApi(string token, HttpClient http, Uri? baseUrl = null)
{
    private readonly string root = (baseUrl ?? new Uri("https://api.supabase.com/v1/")).ToString().TrimEnd('/');

    public Task<List<Organization>> OrganizationsAsync() => GetAsync<List<Organization>>("organizations");

    public Task<List<OrganizationMember>> MembersAsync(string organization) =>
        GetAsync<List<OrganizationMember>>($"organizations/{organization}/members");

    public Task<List<Project>> ProjectsAsync() => GetAsync<List<Project>>("projects");

    public Task<Project> ProjectAsync(string reference) => GetAsync<Project>($"projects/{reference}");

    public async Task<Project> CreateProjectAsync(string name, string organization, string region, string databasePassword)
    {
        using var response = await SendAsync(HttpMethod.Post, "projects", JsonContent.Create(new Dictionary<string, string>
        {
            ["name"] = name, ["organization_id"] = organization, ["region"] = region, ["db_pass"] = databasePassword,
        })).ConfigureAwait(false);
        return (await response.Content.ReadFromJsonAsync<Project>().ConfigureAwait(false))!;
    }

    public Task<List<ApiKey>> ApiKeysAsync(string reference, bool reveal = false) =>
        GetAsync<List<ApiKey>>($"projects/{reference}/api-keys" + (reveal ? "?reveal=true" : ""));

    /// <summary>Runs SQL as the database owner and returns the rows as JSON.</summary>
    public async Task<JsonElement> RunSqlAsync(string reference, string query)
    {
        using var response = await SendAsync(HttpMethod.Post, $"projects/{reference}/database/query",
            JsonContent.Create(new { query })).ConfigureAwait(false);
        var text = await response.Content.ReadAsStringAsync().ConfigureAwait(false);
        return string.IsNullOrWhiteSpace(text) ? default : JsonDocument.Parse(text).RootElement.Clone();
    }

    public async Task<List<string>> ExposedSchemasAsync(string reference)
    {
        var config = await GetAsync<JsonElement>($"projects/{reference}/postgrest").ConfigureAwait(false);
        return [.. (config.GetProperty("db_schema").GetString() ?? "").Split(',').Select(s => s.Trim()).Where(s => s.Length > 0)];
    }

    public async Task SetExposedSchemasAsync(string reference, IEnumerable<string> schemas)
    {
        using var response = await SendAsync(HttpMethod.Patch, $"projects/{reference}/postgrest",
            JsonContent.Create(new { db_schema = string.Join(",", schemas) })).ConfigureAwait(false);
    }

    /// <summary>Deploys an Edge Function from its source files, with JWT checks off.</summary>
    public async Task DeployFunctionAsync(string reference, string slug, IEnumerable<(string Name, string Content)> files)
    {
        using var form = new MultipartFormDataContent();
        form.Add(JsonContent.Create(new { entrypoint_path = "index.ts", name = slug, verify_jwt = false }), "metadata");
        foreach (var (name, content) in files)
        {
            var part = new StringContent(content);
            part.Headers.ContentType = new MediaTypeHeaderValue("application/typescript");
            form.Add(part, "file", name);
        }

        using var response = await SendAsync(HttpMethod.Post, $"projects/{reference}/functions/deploy?slug={slug}", form).ConfigureAwait(false);
    }

    public async Task SetSecretsAsync(string reference, IReadOnlyDictionary<string, string> secrets)
    {
        var list = secrets.OrderBy(s => s.Key, StringComparer.Ordinal).Select(s => new { name = s.Key, value = s.Value });
        using var response = await SendAsync(HttpMethod.Post, $"projects/{reference}/secrets", JsonContent.Create(list)).ConfigureAwait(false);
    }

    private async Task<T> GetAsync<T>(string path)
    {
        using var response = await SendAsync(HttpMethod.Get, path, null).ConfigureAwait(false);
        return (await response.Content.ReadFromJsonAsync<T>().ConfigureAwait(false))!;
    }

    private async Task<HttpResponseMessage> SendAsync(HttpMethod method, string path, HttpContent? content)
    {
        using var request = new HttpRequestMessage(method, new Uri($"{root}/{path}")) { Content = content };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        var response = await http.SendAsync(request).ConfigureAwait(false);
        if (response.IsSuccessStatusCode)
        {
            return response;
        }

        var body = await response.Content.ReadAsStringAsync().ConfigureAwait(false);
        var status = response.StatusCode;
        response.Dispose();
        throw new ManagementException(Explain(status, body), status);
    }

    private static string Explain(HttpStatusCode status, string body)
    {
        var lower = body.ToLowerInvariant();
        if (status == HttpStatusCode.Unauthorized)
        {
            return "Supabase didn't accept the sign-in. Sign in again.";
        }

        if (lower.Contains("limit", StringComparison.Ordinal) && lower.Contains("project", StringComparison.Ordinal))
        {
            return "Your Supabase account already has the most free projects it can. Install Mox in one you already have.";
        }

        return $"Supabase answered HTTP {(int)status}: {body[..Math.Min(body.Length, 200)]}";
    }
}

/// <summary>Creates and deletes the Mox user with the project's secret key, used once and dropped.</summary>
public static class AuthAdmin
{
    public static async Task<Guid> CreateUserAsync(HttpClient http, Uri project, string secretKey, string email, string password)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(project, "auth/v1/admin/users"))
        {
            Content = JsonContent.Create(new { email, password, email_confirm = true }),
        };
        request.Headers.Add("apikey", secretKey);
        using var response = await http.SendAsync(request).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
        {
            throw new ManagementException($"Couldn't create the Mox user (HTTP {(int)response.StatusCode}).", response.StatusCode);
        }

        var created = await response.Content.ReadFromJsonAsync<JsonElement>().ConfigureAwait(false);
        return Guid.Parse(created.GetProperty("id").GetString()!);
    }

    public static async Task DeleteUserAsync(HttpClient http, Uri project, string secretKey, Guid id)
    {
        using var request = new HttpRequestMessage(HttpMethod.Delete, new Uri(project, $"auth/v1/admin/users/{id}"));
        request.Headers.Add("apikey", secretKey);
        using var response = await http.SendAsync(request).ConfigureAwait(false);
    }
}
