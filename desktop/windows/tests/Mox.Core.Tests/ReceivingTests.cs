namespace Mox.Core.Tests;

public class ReceivingTests
{
    private static readonly Guid Me = Guid.Parse("11111111-1111-1111-1111-111111111111");

    private static CurrentFile Item(string device, string uploadedAt) => new()
    {
        Id = 1, OriginalName = "a.jpg", SizeBytes = 1, Kind = "file", ItemCount = 1, SourcePlatform = "ios",
        SourceDeviceId = device, UploadedAt = uploadedAt,
    };

    [Fact]
    public void Only_items_from_other_devices_that_werent_handled_are_new()
    {
        Assert.True(Receiving.IsNew(Item("22222222-2222-2222-2222-222222222222", "t1"), Me, "t0"));
        Assert.False(Receiving.IsNew(Item("22222222-2222-2222-2222-222222222222", "t1"), Me, "t1"));
        Assert.False(Receiving.IsNew(Item(Me.ToString(), "t2"), Me, "t1"));
        Assert.False(Receiving.IsNew(null, Me, "t1"));
    }

    [Fact]
    public void Taken_names_get_a_number()
    {
        var folder = Directory.CreateTempSubdirectory().FullName;
        File.WriteAllText(Path.Combine(folder, "photo.jpg"), "x");
        Assert.Equal(Path.Combine(folder, "photo (1).jpg"), Receiving.UniquePath(folder, "photo.jpg"));
        Assert.Equal(Path.Combine(folder, "new.txt"), Receiving.UniquePath(folder, "new.txt"));
    }

    [Fact]
    public void Texts_must_have_content_and_stay_under_one_megabyte()
    {
        Assert.Equal("Hola 👋", TextPayload.Decode(TextPayload.Encode("Hola 👋")));
        Assert.Throws<MoxException>(() => TextPayload.Encode("  "));
        Assert.Throws<MoxException>(() => TextPayload.Encode(new string('a', TextPayload.MaxBytes + 1)));
    }
}
