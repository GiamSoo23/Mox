using System.Globalization;
using System.Text.RegularExpressions;

namespace Mox.Core;

/// <summary>A pairing link that can't be used. <see cref="Code"/> is stable; the message is for people.</summary>
public sealed class PairingException(string code, string message) : Exception(message)
{
    public string Code { get; } = code;
}

/// <summary>
/// The pairing link (shared/PROTOCOL.md §8): https://…/pair/#v=1&amp;u=…&amp;k=…&amp;e=…&amp;p=…&amp;n=…
/// or its app hand-off form mox://pair?…. Same rules as the Mac, Android and
/// the pairing page, checked against shared/fixtures/pairing/.
/// </summary>
public sealed partial record PairingLink(
    int Version, string ProjectUrl, string PublishableKey, string Email, string Password, string? DesktopName)
{
    private const string HandoffPrefix = "mox://pair?";
    private static readonly string[] Required = ["v", "u", "k", "e", "p"];

    public MoxSettings ToSettings() => new(new Uri(ProjectUrl), PublishableKey, Email, Password);

    /// <summary>The link a phone scans (§8.1): the parameters go in the fragment, which browsers never send.</summary>
    public static string Build(MoxSettings settings, string? desktopName, string page = "https://giamsoo23.github.io/Mox/pair/")
    {
        var parts = new List<(string Key, string Value)>
        {
            ("v", "1"), ("u", settings.ProjectUrl.ToString().TrimEnd('/')), ("k", settings.PublishableKey),
            ("e", settings.Email), ("p", settings.Password),
        };
        if (!string.IsNullOrEmpty(desktopName))
        {
            parts.Add(("n", desktopName.Length > 64 ? desktopName[..64] : desktopName));
        }

        // EscapeDataString keeps only A–Z a–z 0–9 - . _ ~, as §8.2 asks.
        return page + "#" + string.Join("&", parts.Select(p => $"{p.Key}={Uri.EscapeDataString(p.Value)}"));
    }

    public static PairingLink Parse(string link)
    {
        var parameters = ReadParameters(ExtractRaw(link.Trim()));
        foreach (var required in Required)
        {
            if (!parameters.TryGetValue(required, out var value) || value.Length == 0)
            {
                throw new PairingException($"missing-{required}", "This pairing link is incomplete. Scan the QR code again.");
            }
        }

        if (parameters["v"] != "1")
        {
            throw new PairingException("unsupported-version",
                "This link needs a newer version of Mox. Update the app and scan again.");
        }

        var projectUrl = parameters["u"];
        if (projectUrl.EndsWith('/'))
        {
            projectUrl = projectUrl[..^1];
        }

        if (!ProjectUrlPattern().IsMatch(projectUrl))
        {
            throw new PairingException("bad-project-url", "The project address in this link isn't valid.");
        }

        var key = parameters["k"];
        if (key.StartsWith("sb_secret_", StringComparison.Ordinal))
        {
            // Never store or show it: a secret key must not reach a phone or another computer.
            throw new PairingException("secret-key",
                "This link contains a secret key, which must never be shared. Use the project's publishable key instead.");
        }

        if (!key.StartsWith("sb_publishable_", StringComparison.Ordinal))
        {
            throw new PairingException("bad-key", "This link doesn't contain a publishable key.");
        }

        var email = parameters["e"];
        if (email.Split('@').Length != 2 || email.Length > 254)
        {
            throw new PairingException("bad-email", "The Mox user in this link isn't valid.");
        }

        var password = parameters["p"];
        if (password.Length is < 16 or > 128)
        {
            throw new PairingException("bad-password", "The Mox user's password in this link isn't valid.");
        }

        string? name = parameters.TryGetValue("n", out var givenName) && givenName.Length > 0 ? givenName : null;
        if (name is not null && name.EnumerateRunes().Count() > 64)
        {
            throw new PairingException("name-too-long", "The computer name in this link is too long.");
        }

        return new PairingLink(1, projectUrl, key, email, password, name);
    }

    private static string ExtractRaw(string link)
    {
        if (link.StartsWith(HandoffPrefix, StringComparison.Ordinal))
        {
            return link[HandoffPrefix.Length..];
        }

        var hash = link.IndexOf('#', StringComparison.Ordinal);
        if (hash == -1 || hash == link.Length - 1)
        {
            throw new PairingException("no-parameters", "This pairing link is incomplete. Scan the QR code again.");
        }

        return link[(hash + 1)..];
    }

    private static Dictionary<string, string> ReadParameters(string raw)
    {
        var parameters = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var part in raw.Split('&'))
        {
            if (part.Length == 0)
            {
                continue;
            }

            var equals = part.IndexOf('=', StringComparison.Ordinal);
            var key = equals == -1 ? part : part[..equals];
            var value = equals == -1 ? "" : part[(equals + 1)..];
            if (!parameters.TryAdd(key, Decode(value)))
            {
                throw new PairingException("duplicate-key", $"This pairing link repeats \"{key}\".");
            }
        }

        return parameters;
    }

    /// <summary>Percent-decoding that never turns "+" into a space (§8.2).</summary>
    private static string Decode(string value)
    {
        try
        {
            return Uri.UnescapeDataString(value);
        }
        catch (UriFormatException)
        {
            throw new PairingException("bad-encoding", "This pairing link is damaged. Scan the QR code again.");
        }
    }

    [GeneratedRegex(@"^https://[A-Za-z0-9.-]+(:\d+)?$", RegexOptions.CultureInvariant)]
    private static partial Regex ProjectUrlPattern();

    public override string ToString() =>
        string.Create(CultureInfo.InvariantCulture, $"PairingLink v{Version} {ProjectUrl} ({DesktopName ?? "your computer"})");
}
