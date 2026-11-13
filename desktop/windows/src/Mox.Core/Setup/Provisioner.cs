using System.Security.Cryptography;
using System.Text.Json;

namespace Mox.Core.Setup;

public enum ProvisioningStep
{
    WaitingForProject, ApplyingMigrations, ExposingSchema, CreatingMoxUser, SettingOwner, ReadingKey, SettingUpPush, Finished,
}

/// <summary>Why setup stopped, in words a person can act on.</summary>
public sealed class ProvisioningException(string message) : Exception(message)
{
    public static ProvisioningException AlreadyInstalled() => new(
        "Mox is already set up in this project for another Mox user. Setting it up again means your other devices pair again.");
}

/// <summary>
/// Turns a new or existing Supabase project into a Mox backend: the same steps
/// as the Mac's Provisioner.swift, and safe to run again.
/// </summary>
public sealed class Provisioner(ManagementApi api, HttpClient http, Func<TimeSpan, Task>? pause = null, int maxWaitSeconds = 600)
{
    private readonly Func<TimeSpan, Task> pause = pause ?? (t => Task.Delay(t));

    /// <summary>Reported as setup goes; <c>Detail</c> carries progress or why iPhone support is off.</summary>
    public event Action<ProvisioningStep, string?>? Progress;

    public async Task<MoxSettings> ProvisionAsync(Project project, bool replaceExistingOwner = false)
    {
        Report(ProvisioningStep.WaitingForProject);
        await WaitUntilReadyAsync(project).ConfigureAwait(false);
        await ApplyMissingMigrationsAsync(project.Id).ConfigureAwait(false);

        Report(ProvisioningStep.ExposingSchema);
        var schemas = await api.ExposedSchemasAsync(project.Id).ConfigureAwait(false);
        if (!schemas.Contains("mox"))
        {
            await api.SetExposedSchemasAsync(project.Id, [.. schemas, "mox"]).ConfigureAwait(false);
        }

        var owner = await api.RunSqlAsync(project.Id, "select owner_id is not null as has_owner from mox.meta").ConfigureAwait(false);
        if (FirstBool(owner, "has_owner") && !replaceExistingOwner)
        {
            throw ProvisioningException.AlreadyInstalled();
        }

        var previous = replaceExistingOwner ? await GeneratedOwnerAsync(project.Id).ConfigureAwait(false) : null;

        Report(ProvisioningStep.CreatingMoxUser);
        var keys = await api.ApiKeysAsync(project.Id, reveal: true).ConfigureAwait(false);
        var secretKey = keys.FirstOrDefault(k => k.Type == "secret")?.Value
            ?? throw new ProvisioningException("This project has no secret API key. Create one in Project Settings → API Keys.");
        var email = $"mox-{Convert.ToHexString(RandomNumberGenerator.GetBytes(4)).ToLowerInvariant()}@mox.invalid";
        var password = RandomPassword();
        // The secret key is used for these calls and then dropped.
        var userId = await AuthAdmin.CreateUserAsync(http, project.Url, secretKey, email, password).ConfigureAwait(false);

        Report(ProvisioningStep.SettingOwner);
        await api.RunSqlAsync(project.Id, $"update mox.meta set owner_id = '{userId}' where id = 1").ConfigureAwait(false);
        if (previous is { } old)
        {
            // Otherwise every Set Up Again leaves one more user behind.
            try
            {
                await AuthAdmin.DeleteUserAsync(http, project.Url, secretKey, old).ConfigureAwait(false);
            }
            catch (HttpRequestException)
            {
                // Harmless: the old user no longer owns anything.
            }
        }

        Report(ProvisioningStep.ReadingKey);
        var publishable = keys.FirstOrDefault(k => k.Type == "publishable")?.Value
            ?? throw new ProvisioningException("This project has no publishable API key. Create one in Project Settings → API Keys.");

        Report(ProvisioningStep.SettingUpPush);
        try
        {
            await SetUpIPhoneAsync(project).ConfigureAwait(false);
        }
        catch (Exception error) when (error is ManagementException or HttpRequestException)
        {
            Report(ProvisioningStep.SettingUpPush, $"iPhone support is off: {error.Message}");
        }

        Report(ProvisioningStep.Finished);
        return new MoxSettings(project.Url, publishable, email, password);
    }

    private void Report(ProvisioningStep step, string? detail = null) => Progress?.Invoke(step, detail);

    private async Task WaitUntilReadyAsync(Project project)
    {
        var current = project;
        for (var check = 0; check < Math.Max(1, maxWaitSeconds / 5); check++)
        {
            if (current.IsReady)
            {
                return;
            }

            if (current.IsPaused)
            {
                throw new ProvisioningException("This project is paused. Restore it in the Supabase dashboard, then try again.");
            }

            await pause(TimeSpan.FromSeconds(5)).ConfigureAwait(false);
            current = await api.ProjectAsync(project.Id).ConfigureAwait(false);
        }

        if (!current.IsReady)
        {
            throw new ProvisioningException("The project took too long to start. Try again in a few minutes.");
        }
    }

    /// <summary>Applies the migrations the project lacks, recorded where the Supabase CLI keeps them.</summary>
    private async Task ApplyMissingMigrationsAsync(string reference)
    {
        await api.RunSqlAsync(reference, """
            create schema if not exists supabase_migrations;
            create table if not exists supabase_migrations.schema_migrations (
                version text primary key, statements text[], name text
            );
            """).ConfigureAwait(false);
        var rows = await api.RunSqlAsync(reference, "select version from supabase_migrations.schema_migrations").ConfigureAwait(false);
        var applied = rows.ValueKind == JsonValueKind.Array
            ? rows.EnumerateArray().Select(r => r.GetProperty("version").GetString()).ToHashSet(StringComparer.Ordinal)
            : [];
        var missing = BundledFiles.Migrations.Where(m => !applied.Contains(m.Version)).ToList();
        for (var i = 0; i < missing.Count; i++)
        {
            Report(ProvisioningStep.ApplyingMigrations, $"{i} of {missing.Count}");
            await api.RunSqlAsync(reference, missing[i].Sql).ConfigureAwait(false);
            await api.RunSqlAsync(reference,
                $"insert into supabase_migrations.schema_migrations (version, name) values ('{missing[i].Version}', '{missing[i].Name}') on conflict (version) do nothing")
                .ConfigureAwait(false);
        }

        Report(ProvisioningStep.ApplyingMigrations, $"{missing.Count} of {missing.Count}");
    }

    /// <summary>The current owner, only if Mox generated it: a person's own account is never deleted.</summary>
    private async Task<Guid?> GeneratedOwnerAsync(string reference)
    {
        var rows = await api.RunSqlAsync(reference,
            "select u.id from auth.users u join mox.meta m on m.owner_id = u.id where u.email like 'mox-%@mox.invalid'").ConfigureAwait(false);
        var id = rows.ValueKind == JsonValueKind.Array && rows.GetArrayLength() > 0 ? rows[0].GetProperty("id").GetString() : null;
        return Guid.TryParse(id, out var parsed) ? parsed : null;
    }

    /// <summary>Deploys the iPhone functions with fresh push keys, and points the database at them (#27, #54).</summary>
    private async Task SetUpIPhoneAsync(Project project)
    {
        using var vapid = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        var parameters = vapid.ExportParameters(includePrivateParameters: true);
        var publicKey = Base64Url([0x04, .. parameters.Q.X!, .. parameters.Q.Y!]);
        var secret = RandomPassword();
        foreach (var function in BundledFiles.Functions)
        {
            await api.DeployFunctionAsync(project.Id, function.Slug, function.Files).ConfigureAwait(false);
        }

        await api.SetSecretsAsync(project.Id, new Dictionary<string, string>
        {
            ["MOX_PUSH_SECRET"] = secret, ["MOX_VAPID_PUBLIC_KEY"] = publicKey, ["MOX_VAPID_PRIVATE_KEY"] = Base64Url(parameters.D!),
        }).ConfigureAwait(false);
        var url = new Uri(project.Url, "functions/v1/mox-push");
        await api.RunSqlAsync(project.Id, $"""
            insert into mox.push_config (id, function_url, secret) values (1, '{url}', '{secret}')
            on conflict (id) do update set function_url = excluded.function_url, secret = excluded.secret;
            update mox.meta set vapid_public_key = '{publicKey}' where id = 1;
            delete from mox.push_subscriptions;
            """).ConfigureAwait(false);
    }

    private static bool FirstBool(JsonElement rows, string column) =>
        rows.ValueKind == JsonValueKind.Array && rows.GetArrayLength() > 0
        && rows[0].TryGetProperty(column, out var value) && value.ValueKind == JsonValueKind.True;

    /// <summary>32 URL-safe characters (192 bits of randomness).</summary>
    public static string RandomPassword() => Base64Url(RandomNumberGenerator.GetBytes(24));

    public static string Base64Url(byte[] bytes) =>
        Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');
}
