#!/usr/bin/env python3
"""Create 54 U2 contact sheets from the coordinator's freshly exported atlases.

python3 scripts/preview-u2-art.py --output-dir .build/u2-contact-sheets

Stdlib only. Each PNG has nine columns (stand, fly0..fly7) and six rows
(1x, 1.5x, 2x; right and left). Multipliers refer to exported native pixels,
not the app's logical 48px drawing coordinates. Half pixels round upward.
Left views mirror source pixels; scaling uses nearest neighbor throughout.
This script never builds or exports the app and does not approve visual quality.
"""
import argparse
import hashlib
import importlib.util
import json
import re
import struct
import subprocess
import sys
import zlib
from pathlib import Path


BASELINE = "53680ae5738cdd5caabe460c4bf25e7090659ada"
FRAMES = ["stand"] + [f"fly{i}" for i in range(8)]
# Three by five bitmap labels keep PNG output independent of installed fonts.
FONT = dict(zip("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-:/ ", (
    "010101111101101", "110101110101110", "011100100100011",
    "110101101101110", "111100110100111", "111100110100100",
    "011100101101011", "101101111101101", "111010010010111",
    "001001001101010", "101101110101101", "100100100100111",
    "101111111101101", "101111111111101", "010101101101010",
    "110101110100100", "010101101111011", "110101110101101",
    "011100010001110", "111010010010010", "101101101101111",
    "101101101101010", "101101111111101", "101101010101101",
    "101101010010010", "111001010100111", "111101101101111",
    "010110010010111", "110001010100111", "110001010001110",
    "101101111001001", "111100110001110", "011100111101111",
    "111001010010010", "111101111101111", "111101111001110",
    "000000000000010", "000000111000000", "000010000010000",
    "001001010100100", "000000000000000",
)))


def png_bytes(width, height, pixels):
    def chunk(kind, data):
        return (struct.pack(">I", len(data)) + kind + data
                + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF))
    rows = b"".join(b"\0" + pixels[y * width * 4:(y + 1) * width * 4]
                    for y in range(height))
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))


def label(canvas, width, x, y, value):
    for character in value.upper():
        glyph = FONT.get(character, FONT[" "])
        for row in range(5):
            for column in range(3):
                if glyph[row * 3 + column] == "1":
                    for dy in range(2):
                        for dx in range(2):
                            offset = ((y + row * 2 + dy) * width + x + column * 2 + dx) * 4
                            canvas[offset:offset + 4] = bytes((40, 44, 48, 255))
        x += 8


def sheet(species, native, frames):
    cell, left, top = native * 2 + 16, 96, 64
    width, height = left + len(FRAMES) * cell, top + 6 * cell
    canvas = bytearray(bytes((242, 242, 242, 255)) * (width * height))
    label(canvas, width, 12, 10, species)
    label(canvas, width, 12, 28, f"NATIVE {native}PX / NEAREST / R RIGHT L LEFT")
    for column, name in enumerate(FRAMES):
        label(canvas, width, left + column * cell + 8, 48, name)
    rows = []
    for scale_index, numerator in enumerate((2, 3, 4)):
        size = (native * numerator + 1) // 2
        for direction_index, direction in enumerate(("right", "left")):
            row = scale_index * 2 + direction_index
            scale = numerator / 2
            label(canvas, width, 8, top + row * cell + 12,
                  f"{scale:g}X {direction[0]}")
            rows.append({"scale": scale, "direction": direction, "tilePixels": size})
            for column, name in enumerate(FRAMES):
                cell_x, cell_y = left + column * cell, top + row * cell
                # Checkerboard reveals light/dark feathers without altering alpha evidence.
                for y in range(cell - 2):
                    for x in range(cell - 2):
                        shade = 210 if ((x // 8) + (y // 8)) % 2 else 232
                        offset = ((cell_y + y) * width + cell_x + x) * 4
                        canvas[offset:offset + 4] = bytes((shade, shade, shade, 255))
                origin_x = cell_x + (cell - size) // 2
                origin_y = cell_y + (cell - size) // 2
                source = frames[name]
                for y in range(size):
                    sy = min(native - 1, ((2 * y + 1) * native) // (2 * size))
                    for x in range(size):
                        sx = min(native - 1, ((2 * x + 1) * native) // (2 * size))
                        if direction == "left":
                            sx = native - 1 - sx
                        source_offset = (sy * native + sx) * 4
                        alpha = source[source_offset + 3]
                        offset = ((origin_y + y) * width + origin_x + x) * 4
                        for channel in range(3):
                            canvas[offset + channel] = (
                                source[source_offset + channel] * alpha
                                + canvas[offset + channel] * (255 - alpha) + 127) // 255
    return png_bytes(width, height, canvas), rows, [width, height]


def generate(args):
    shared = (args.shared or args.root / "shared").resolve()
    output = args.output_dir.resolve()
    if output == shared or shared in output.parents:
        raise ValueError("Output directory must be outside the exported shared directory")
    baseline = json.loads(subprocess.check_output(
        ["git", "show", f"{args.baseline}:shared/art/manifest.json"], cwd=args.root))
    manifest_data = (shared / "art/manifest.json").read_bytes()
    manifest = json.loads(manifest_data)
    catalog = json.loads((shared / "species.json").read_text())
    ids = [item["id"] for item in catalog["species"]]
    legacy = set(baseline["frameSizes"])
    expansion = [item for item in catalog["species"] if item["id"] not in legacy]
    if (len(ids) != 100 or len(set(ids)) != 100 or len(legacy) != 46
            or not legacy.issubset(ids) or len(expansion) != 54):
        raise ValueError("Expected frozen 46 legacy species plus exactly 54 new species")
    extras = manifest.get("speciesFrames", {})
    extra_counts = {sid: len(names) - len(manifest["frames"]) for sid, names in extras.items()}
    if (manifest["frames"] != baseline["frames"] or len(manifest["frames"]) != 34
            or extras != baseline["speciesFrames"] or sum(extra_counts.values()) != 187):
        raise ValueError("The original 34 frame order or 187 appended frame names/order changed")
    if set(manifest["frameSizes"]) != set(ids):
        raise ValueError("Manifest must declare the native sizes of all 100 species")

    # Import helpers without executing audit.main or writing a __pycache__ directory.
    spec = importlib.util.spec_from_file_location("u2_art_audit", Path(__file__).with_name("audit-u2-art.py"))
    decoder = importlib.util.module_from_spec(spec)
    previous = sys.dont_write_bytecode
    try:
        sys.dont_write_bytecode = True
        spec.loader.exec_module(decoder)
    finally:
        sys.dont_write_bytecode = previous

    # Read every requested source before writing previews; never substitute missing art.
    sources = []
    for item in expansion:
        sid = item["id"]
        if not re.fullmatch(r"[A-Za-z][A-Za-z0-9]*", sid):
            raise ValueError(f"Unsafe species ID: {sid}")
        native = manifest["frameSizes"][sid]
        if not isinstance(native, int) or not 1 <= native <= 512:
            raise ValueError(f"Invalid native frame size: {sid}={native}")
        data = (shared / "art" / f"{sid}.png").read_bytes()
        names = extras.get(sid, manifest["frames"])
        frames = decoder.atlas_frames(data, native, names)
        if len(names) != len(set(names)) or any(name not in frames or not any(frames[name][3::4]) for name in FRAMES):
            raise ValueError(f"Missing, empty or duplicate preview frame: {sid}")
        sources.append((item, native, data, frames))
    output.mkdir(parents=True, exist_ok=True)
    entries = []
    for item, native, data, frames in sources:
        sid = item["id"]
        image, rows, dimensions = sheet(sid, native, frames)
        filename = f"{sid}.png"
        (output / filename).write_bytes(image)
        entries.append({"species": item, "file": filename, "nativeFrameSize": native,
                        "sourceAtlas": str(shared / "art" / filename),
                        "sourceSHA256": hashlib.sha256(data).hexdigest(),
                        "previewSHA256": hashlib.sha256(image).hexdigest(),
                        "dimensions": dimensions, "rows": rows})
    report = {"baseline": args.baseline, "shared": str(shared), "speciesCount": len(entries),
              "manifestSHA256": hashlib.sha256(manifest_data).hexdigest(),
              "columns": FRAMES, "scaleBasis": "exported native pixels; half pixels round upward",
              "resampling": "nearest neighbor", "leftView": "horizontal mirror",
              "appendedFrameCount": sum(extra_counts.values()), "appendedFramesBySpecies": extra_counts,
              "appendedNamesAndOrderMatchBaseline": True,
              "pendingVisualReview": True, "sheets": entries,
              "note": "Metadata count is not a pixel audit. Run audit-u2-art.py after export for pixel evidence."}
    (output / "index.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {len(entries)} contact sheets and index.json to {output}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--shared", type=Path, help="Fresh exported directory; defaults to ROOT/shared")
    parser.add_argument("--baseline", default=BASELINE)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    try:
        generate(args)
    except (OSError, ValueError, KeyError, IndexError, TypeError, struct.error,
            zlib.error, subprocess.CalledProcessError) as error:
        print(f"U2 preview failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
