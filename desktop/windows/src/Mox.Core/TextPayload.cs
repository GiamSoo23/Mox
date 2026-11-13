using System.Text;

namespace Mox.Core;

/// <summary>Plain text sent through the slot (#101, shared/PROTOCOL.md §6).</summary>
public static class TextPayload
{
    public const int MaxBytes = 1_000_000;
    public const string FileName = "Text.txt";
    public const string Mime = "text/plain";

    public static byte[] Encode(string text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            throw new MoxException("There's no text to send.");
        }

        var bytes = Encoding.UTF8.GetBytes(text);
        return bytes.Length <= MaxBytes ? bytes : throw new MoxException("That text is too long: Mox sends texts up to 1 MB.");
    }

    public static string Decode(byte[] bytes) => Encoding.UTF8.GetString(bytes);
}

/// <summary>An error a person can act on, with a message written for them.</summary>
public sealed class MoxException(string message) : Exception(message);
