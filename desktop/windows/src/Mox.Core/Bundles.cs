using System.IO.Compression;
using System.Text;

namespace Mox.Core;

/// <summary>Several files sent as one zip (shared/PROTOCOL.md §9).</summary>
public static class Bundles
{
    public const int MaxEntries = 1000;
    public const long MaxUnpacked = CurrentFile.MaxSize;

    /// <summary>One file in a bundle: its path inside the bundle, and its bytes.</summary>
    public sealed record Entry(string Path, byte[] Data);

    /// <summary>A file to pack: where it goes in the bundle, and where it is now.</summary>
    public sealed record Item(string Path, string Source, long Size);

    /// <summary>"Mox – 5 files.zip", the name the row carries.</summary>
    public static string FileName(int count) => $"Mox – {count} files.zip";

    /// <summary>The files in a bundle, in order. Throws <see cref="BundleRefusedException"/>, unpacking nothing.</summary>
    public static IReadOnlyList<Entry> Read(byte[] zip)
    {
        ZipArchive archive;
        try
        {
            archive = new ZipArchive(new MemoryStream(zip, writable: false), ZipArchiveMode.Read, false, Encoding.UTF8);
        }
        catch (InvalidDataException)
        {
            throw new BundleRefusedException("it isn't a zip");
        }

        using (archive)
        {
            if (archive.Entries.Count > MaxEntries)
            {
                throw new BundleRefusedException("it has too many files");
            }

            var kept = new List<ZipArchiveEntry>();
            long total = 0;
            foreach (var entry in archive.Entries)
            {
                Check(entry);
                if (IsSkipped(entry.FullName))
                {
                    continue;
                }

                total += entry.Length;
                if (total > MaxUnpacked)
                {
                    throw new BundleRefusedException("they add up to more than 50 MB");
                }

                kept.Add(entry);
            }

            if (kept.Count < 2)
            {
                throw new BundleRefusedException("a bundle has at least 2 files");
            }

            return kept.Select(entry => new Entry(entry.FullName, Contents(entry))).ToList();
        }
    }

    /// <summary>Unpacks a bundle into <paramref name="folder"/> and returns the top-level items, for the clipboard.</summary>
    public static IReadOnlyList<string> Extract(byte[] zip, string folder)
    {
        var entries = Read(zip);
        Directory.CreateDirectory(folder);
        var topLevel = new List<string>();
        foreach (var entry in entries)
        {
            var parts = entry.Path.Split('/', StringSplitOptions.RemoveEmptyEntries);
            var dir = Path.Combine([folder, .. parts[..^1]]);
            Directory.CreateDirectory(dir);
            var file = Receiving.UniquePath(dir, parts[^1]);
            File.WriteAllBytes(file, entry.Data);
            var top = parts.Length > 1 ? Path.Combine(folder, parts[0]) : file;
            if (!topLevel.Contains(top))
            {
                topLevel.Add(top);
            }
        }

        return topLevel;
    }

    /// <summary>The files to send for what was selected. Folders keep their structure; hidden files are left out.</summary>
    public static IReadOnlyList<Item> Items(IEnumerable<string> paths)
    {
        var items = new List<Item>();
        var taken = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var path in paths)
        {
            var trimmed = path.TrimEnd('\\', '/');
            var top = UniqueName(Path.GetFileName(trimmed), taken);
            if (Directory.Exists(trimmed))
            {
                var files = new DirectoryInfo(trimmed).EnumerateFiles("*", SearchOption.AllDirectories)
                    .Where(file => !IsHidden(file, trimmed))
                    .Select(file => new Item(
                        top + "/" + Path.GetRelativePath(trimmed, file.FullName).Replace('\\', '/'), file.FullName, file.Length))
                    .OrderBy(item => item.Path, StringComparer.Ordinal);
                items.AddRange(files);
            }
            else if (File.Exists(trimmed))
            {
                items.Add(new Item(top, trimmed, new FileInfo(trimmed).Length));
            }
        }

        return items;
    }

    /// <summary>Checks the 50 MB limit before packing, then writes an uncompressed zip with UTF-8 names.</summary>
    public static byte[] Write(IReadOnlyList<Item> items)
    {
        var total = items.Sum(item => item.Size);
        if (total > MaxUnpacked)
        {
            var biggest = string.Join(", ", items.OrderByDescending(item => item.Size).Take(3)
                .Select(item => $"{Path.GetFileName(item.Path)} ({Megabytes(item.Size)})"));
            throw new MoxException($"These files add up to {Megabytes(total)}, and Mox sends up to 50 MB. The biggest: {biggest}.");
        }

        using var buffer = new MemoryStream();
        using (var archive = new ZipArchive(buffer, ZipArchiveMode.Create, true, Encoding.UTF8))
        {
            foreach (var item in items)
            {
                var entry = archive.CreateEntry(item.Path, CompressionLevel.NoCompression);
                using var output = entry.Open();
                using var input = File.OpenRead(item.Source);
                input.CopyTo(output);
            }
        }

        return buffer.ToArray();
    }

    private static void Check(ZipArchiveEntry entry)
    {
        var name = entry.FullName;
        if (name.Contains('\\', StringComparison.Ordinal) || name.StartsWith('/') || (name.Length > 1 && name[1] == ':')
            || name.Split('/').Contains(".."))
        {
            throw new BundleRefusedException($"“{name}” points outside the folder");
        }

        if (((entry.ExternalAttributes >> 16) & 0xF000) == 0xA000)
        {
            throw new BundleRefusedException($"“{name}” is a link");
        }
    }

    private static bool IsSkipped(string name) =>
        name.EndsWith('/') || name.StartsWith("__MACOSX/", StringComparison.Ordinal) || name.Split('/')[^1] == ".DS_Store";

    /// <summary>Reads at most the declared size, so a lying header can't unpack more.</summary>
    private static byte[] Contents(ZipArchiveEntry entry)
    {
        var data = new byte[entry.Length];
        try
        {
            using var input = entry.Open();
            input.ReadExactly(data);
            if (input.ReadByte() != -1)
            {
                throw new BundleRefusedException($"“{entry.FullName}” is damaged");
            }
        }
        catch (Exception error) when (error is InvalidDataException or EndOfStreamException)
        {
            throw new BundleRefusedException($"“{entry.FullName}” is damaged");
        }

        return data;
    }

    private static bool IsHidden(FileInfo file, string root)
    {
        for (var current = file as FileSystemInfo; current is not null && current.FullName.Length > root.Length;
             current = (current as FileInfo)?.Directory ?? (current as DirectoryInfo)?.Parent)
        {
            if (current.Name.StartsWith('.') || current.Attributes.HasFlag(FileAttributes.Hidden))
            {
                return true;
            }
        }

        return false;
    }

    private static string UniqueName(string name, HashSet<string> taken)
    {
        var stem = Path.GetFileNameWithoutExtension(name);
        var ext = Path.GetExtension(name);
        var candidate = name;
        for (var number = 1; !taken.Add(candidate); number++)
        {
            candidate = $"{stem} ({number}){ext}";
        }

        return candidate;
    }

    private static string Megabytes(long bytes) =>
        string.Create(System.Globalization.CultureInfo.InvariantCulture, $"{bytes / 1_048_576.0:0.#} MB");
}

/// <summary>A bundle that breaks a rule of PROTOCOL.md §9.</summary>
public sealed class BundleRefusedException(string reason) : Exception($"Mox didn't unpack these files: {reason}.");
