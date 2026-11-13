namespace Mox.Core;

/// <summary>
/// What a desktop needs to reach the owner's Supabase project as the Mox user
/// (shared/PROTOCOL.md §1).
/// </summary>
public sealed record MoxSettings(Uri ProjectUrl, string PublishableKey, string Email, string Password);
