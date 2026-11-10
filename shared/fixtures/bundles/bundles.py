#!/usr/bin/env python3
"""Bundle fixtures (PROTOCOL.md §9) and the reference rules they follow.

    python3 -I shared/fixtures/bundles/bundles.py make    # (re)write the fixtures
    python3 -I shared/fixtures/bundles/bundles.py check   # verify them, as CI does

`check` rebuilds every fixture and fails if a committed one differs, then
runs the reference reader over them: valid/* must unpack to exactly the
files in the matching .json, invalid/* must be refused. Every client's own
bundle tests load the same files.
"""
import io
import json
import stat
import sys
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
MAX_ENTRIES = 1000
MAX_UNPACKED = 52_428_800  # 50 MB, the same cap as the slot
IGNORED_PREFIXES = ("__MACOSX/",)
IGNORED_NAMES = (".DS_Store",)
FIXED_TIME = (2026, 11, 10, 12, 0, 0)


class Refused(Exception):
    pass


def _entry(zf, name, data=b"", method=zipfile.ZIP_STORED, mode=None):
    info = zipfile.ZipInfo(name, date_time=FIXED_TIME)
    info.compress_type = method
    info.external_attr = ((mode if mode is not None else 0o100644) & 0xFFFF) << 16
    zf.writestr(info, data)


def _zip(entries):
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as zf:
        for entry in entries:
            _entry(zf, *entry) if isinstance(entry, tuple) else _entry(zf, entry)
    return buffer.getvalue()


def fixtures():
    """name -> (bytes, files it must unpack to, or None if it must be refused)."""
    photo = bytes(range(256)) * 4
    return {
        "valid/two-photos.zip": (
            _zip([("IMG_0001.jpg", photo), ("IMG_0002.jpg", photo)]),
            ["IMG_0001.jpg", "IMG_0002.jpg"]),
        "valid/folder-structure.zip": (
            _zip(["Trip/", ("Trip/day1.txt", b"one"), ("Trip/notes/day2.txt", b"two"), ("cover.txt", b"c")]),
            ["Trip/day1.txt", "Trip/notes/day2.txt", "cover.txt"]),
        "valid/utf8-names.zip": (
            _zip([("Fotos/año nuevo.txt", b"a"), ("Résumé 👋.txt", b"b")]),
            ["Fotos/año nuevo.txt", "Résumé 👋.txt"]),
        "valid/finder-junk-ignored.zip": (
            _zip([("a.txt", b"a"), ("b.txt", b"b"), ("__MACOSX/._a.txt", b"x"), (".DS_Store", b"x")]),
            ["a.txt", "b.txt"]),
        "valid/deflated.zip": (
            _zip([("a.txt", b"a" * 1000, zipfile.ZIP_DEFLATED), ("b.txt", b"b" * 1000, zipfile.ZIP_DEFLATED)]),
            ["a.txt", "b.txt"]),
        "invalid/zip-slip.zip": (_zip([("ok.txt", b"a"), ("../evil.txt", b"x")]), None),
        "invalid/absolute-path.zip": (_zip([("ok.txt", b"a"), ("/tmp/evil.txt", b"x")]), None),
        "invalid/backslash-traversal.zip": (_zip([("ok.txt", b"a"), ("..\\evil.txt", b"x")]), None),
        "invalid/drive-letter.zip": (_zip([("ok.txt", b"a"), ("C:/evil.txt", b"x")]), None),
        "invalid/symlink.zip": (_zip([("ok.txt", b"a"), ("link", b"/etc/passwd", zipfile.ZIP_STORED, 0o120777)]), None),
        "invalid/single-file.zip": (_zip([("only.txt", b"a")]), None),
        "invalid/too-many-entries.zip": (_zip([(f"f{i}.txt", b"") for i in range(MAX_ENTRIES + 1)]), None),
        "invalid/too-big-unpacked.zip": (
            _zip([("a.bin", b"\0" * (MAX_UNPACKED // 2 + 1), zipfile.ZIP_DEFLATED),
                  ("b.bin", b"\0" * (MAX_UNPACKED // 2 + 1), zipfile.ZIP_DEFLATED)]), None),
        "invalid/not-a-zip.zip": (b"This is not a zip archive.\n", None),
    }


def read(data):
    """The reference reader: the files a bundle unpacks to, or Refused."""
    try:
        zf = zipfile.ZipFile(io.BytesIO(data))
    except zipfile.BadZipFile as error:
        raise Refused(f"not a zip: {error}")
    infos = zf.infolist()
    if len(infos) > MAX_ENTRIES:
        raise Refused("too many entries")
    files, total = [], 0
    for info in infos:
        name = info.filename
        if "\\" in name or name.startswith("/") or (len(name) > 1 and name[1] == ":"):
            raise Refused(f"unsafe path {name!r}")
        if ".." in name.split("/"):
            raise Refused(f"unsafe path {name!r}")
        if stat.S_ISLNK(info.external_attr >> 16):
            raise Refused(f"symbolic link {name!r}")
        if name.startswith(IGNORED_PREFIXES) or name.rsplit("/", 1)[-1] in IGNORED_NAMES or info.is_dir():
            continue
        total += info.file_size
        if total > MAX_UNPACKED:
            raise Refused("unpacks to more than 50 MB")
        files.append(name)
    if len(files) < 2:
        raise Refused("a bundle has at least 2 files")
    return files


def main(mode):
    failures = 0
    for name, (data, expected) in fixtures().items():
        path = HERE / name
        if mode == "make":
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            if expected is not None:
                path.with_suffix(".json").write_text(
                    json.dumps({"item_count": len(expected), "files": expected}, ensure_ascii=False, indent=2) + "\n")
            continue
        if not path.exists() or path.read_bytes() != data:
            print(f"FAIL  {name} differs from what bundles.py makes; run `bundles.py make`")
            failures += 1
            continue
        try:
            files = read(path.read_bytes())
            result = files == expected if expected is not None else False
            detail = f"unpacked to {files}"
        except Refused as error:
            result = expected is None
            detail = f"refused: {error}"
        print(("ok    " if result else "FAIL  ") + f"{name} {detail}"[:140])
        failures += 0 if result else 1
    if mode == "check":
        if failures:
            sys.exit(f"{failures} bundle fixture(s) failed")
        print("All bundle fixtures agree with the rules.")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "check")
