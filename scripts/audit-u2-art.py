#!/usr/bin/env python3
"""Audit U2 *after* the coordinator's shared export; uses only Python stdlib.

python3 scripts/audit-u2-art.py --output /tmp/chirp-u2-art-audit.json
Reports native pixel changes, not a claim that visual review has passed.
The default baseline is the frozen local integration input, never mutable HEAD.
"""
import argparse
import hashlib
import json
import math
import struct
import subprocess
import sys
import zlib
from pathlib import Path


def png_rgba(data):
    """Decode the non-interlaced 8-bit PNGs emitted by the shared exporter."""
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("Invalid PNG signature")
    offset, compressed, palette, transparency = 8, bytearray(), b"", b""
    width = height = depth = color = interlace = None
    while offset < len(data):
        length = struct.unpack_from(">I", data, offset)[0]
        kind = data[offset + 4:offset + 8]
        chunk = data[offset + 8:offset + 8 + length]
        crc = struct.unpack_from(">I", data, offset + 8 + length)[0]
        if zlib.crc32(kind + chunk) & 0xFFFFFFFF != crc:
            raise ValueError("PNG chunk CRC mismatch")
        offset += 12 + length
        if kind == b"IHDR":
            width, height, depth, color, compression, filtering, interlace = struct.unpack(">IIBBBBB", chunk)
            if compression or filtering:
                raise ValueError("Unsupported PNG compression/filter method")
        elif kind == b"IDAT":
            compressed.extend(chunk)
        elif kind == b"PLTE":
            palette = chunk
        elif kind == b"tRNS":
            transparency = chunk
        elif kind == b"IEND":
            break
    if depth != 8 or interlace != 0 or color not in (0, 2, 3, 4, 6):
        raise ValueError(f"Unsupported PNG format: depth={depth}, color={color}, interlace={interlace}")
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[color]
    stride = width * channels
    raw = zlib.decompress(compressed)
    if len(raw) != height * (stride + 1):
        raise ValueError("Invalid PNG scanline length")
    previous, rgba = bytearray(stride), bytearray()
    for y in range(height):
        start = y * (stride + 1)
        mode, row = raw[start], bytearray(raw[start + 1:start + stride + 1])
        if mode not in range(5):
            raise ValueError("Invalid PNG filter")
        for i in range(stride) if mode else ():
            left = row[i - channels] if i >= channels else 0
            up = previous[i]
            upper_left = previous[i - channels] if i >= channels else 0
            paeth = 0
            if mode == 4:
                p = left + up - upper_left
                distances = (abs(p - left), abs(p - up), abs(p - upper_left))
                paeth = (left, up, upper_left)[distances.index(min(distances))]
            row[i] = (row[i] + (0, left, up, (left + up) // 2, paeth)[mode]) & 255
        if color == 6:
            rgba.extend(row)
            previous = row
            continue
        for x in range(width):
            pixel = row[x * channels:(x + 1) * channels]
            if color == 6:
                rgba.extend(pixel)
            elif color == 2:
                transparent = len(transparency) == 6 and tuple(pixel) == struct.unpack(">HHH", transparency)
                rgba.extend((*pixel, 0 if transparent else 255))
            elif color == 3:
                index = pixel[0]
                rgb = palette[index * 3:index * 3 + 3]
                if len(rgb) != 3:
                    raise ValueError("Invalid PNG palette index")
                rgba.extend((*rgb, transparency[index] if index < len(transparency) else 255))
            else:
                transparent = len(transparency) == 2 and pixel[0] == struct.unpack(">H", transparency)[0]
                alpha = pixel[1] if color == 4 else (0 if transparent else 255)
                rgba.extend((pixel[0], pixel[0], pixel[0], alpha))
        previous = row
    # Hidden RGB does not represent a visible pixel difference.
    for i in range(0, len(rgba), 4):
        if rgba[i + 3] == 0:
            rgba[i:i + 3] = b"\0\0\0"
    return width, height, bytes(rgba)


def atlas_frames(data, size, names):
    width, height, rgba = png_rgba(data)
    if (width, height) != (size * len(names), size):
        raise ValueError(f"Atlas is {width}x{height}; expected {size * len(names)}x{size}")
    return {name: b"".join(rgba[(y * width + index * size) * 4:
                                  (y * width + (index + 1) * size) * 4]
                           for y in range(size)) for index, name in enumerate(names)}


def equivalent(left, right):
    if isinstance(left, dict) and isinstance(right, dict):
        return left.keys() == right.keys() and all(equivalent(left[k], right[k]) for k in left)
    if isinstance(left, list) and isinstance(right, list):
        return len(left) == len(right) and all(equivalent(a, b) for a, b in zip(left, right))
    if isinstance(left, (int, float)) and isinstance(right, (int, float)):
        return math.isclose(left, right, rel_tol=0, abs_tol=1e-9)
    return left == right


def audit(root, shared, baseline):
    def historical(path):
        return subprocess.check_output(["git", "show", f"{baseline}:{path}"], cwd=root)

    old = json.loads(historical("shared/art/manifest.json"))
    manifest = json.loads((shared / "art/manifest.json").read_text())
    catalog = json.loads((shared / "species.json").read_text())
    bundled = json.loads((root / "platforms/macos/Sources/BirdingCore/Resources/species.json").read_text())
    support = json.loads((shared / "species-support.json").read_text())
    old_support = json.loads(historical("shared/species-support.json"))
    checks, errors, differences, expansion = {}, [], [], []

    def check(name, condition):
        checks[name] = bool(condition)
        if not condition:
            errors.append(name)

    ids = [row["id"] for row in catalog["species"]]
    legacy = set(old["frameSizes"])
    new_ids = set(ids) - legacy
    common = manifest["frames"]
    specific = manifest.get("speciesFrames", {})
    check("100 unique species; frozen 46 plus 54", len(ids) == len(set(ids)) == 100 and len(legacy) == 46
          and legacy.issubset(ids) and len(new_ids) == 54)
    check("bundled and shared catalogs agree", catalog == bundled)
    check("34 common names and order unchanged", common == old["frames"] and len(common) == 34)
    check("logical frame and foot anchor unchanged", manifest["logicalFrameSize"] == 48 and manifest["footAnchor"] == [29, 39])
    check("100 native frame sizes", set(manifest["frameSizes"]) == set(ids))
    check("187 local appended frames and order retained", specific == old["speciesFrames"]
          and sum(len(names) - 34 for names in specific.values()) == 187)
    check("3587 atlas slots", sum(len(specific.get(sid, common)) for sid in ids) == 3587)
    check("pose metadata and anchors retained", equivalent(manifest.get("poseClips"), old.get("poseClips"))
          and manifest.get("poseClock") == old.get("poseClock"))
    props = json.loads((shared / "art/props/manifest.json").read_text())
    check("prop metadata retained", equivalent(props, json.loads(historical("shared/art/props/manifest.json"))))
    old_prop_paths = subprocess.check_output(["git", "ls-tree", "-r", "--name-only", baseline,
                                              "shared/art/props"], cwd=root).decode().splitlines()
    for path in old_prop_paths:
        if path.endswith(".png"):
            target = shared / Path(path).relative_to("shared")
            check(f"prop pixels retained: {target.name}", target.exists() and png_rgba(target.read_bytes()) == png_rgba(historical(path)))
    by_id = {row["species"]: row for row in support}
    check("100 unique support rows", len(support) == len(by_id) == 100 and set(by_id) == set(ids))
    for row in old_support:
        current = by_id.get(row["species"], {})
        check(f"legacy permissions retained: {row['species']}",
              all(equivalent(current.get(k), v) for k, v in row.items()))
    for sid in ids:
        names, size = specific.get(sid, common), manifest["frameSizes"][sid]
        frames = atlas_frames((shared / "art" / f"{sid}.png").read_bytes(), size, names)
        check(f"nonempty unique slots: {sid}", len(names) == len(set(names)) and
              all(any(pixels[3::4]) for pixels in frames.values()))
        if sid in legacy:
            old_names = old.get("speciesFrames", {}).get(sid, old["frames"])
            before = atlas_frames(historical(f"shared/art/{sid}.png"), old["frameSizes"][sid], old_names)
            for index, name in enumerate(old_names):
                a, b = before[name], frames[name]
                same_size = len(a) == len(b)
                differences.append({"species": sid, "frame": name, "appended": index >= 34,
                    "changed": a != b, "nativeSizeBefore": old["frameSizes"][sid], "nativeSizeAfter": size,
                    "changedPixels": sum(a[i:i + 4] != b[i:i + 4] for i in range(0, len(a), 4)) if same_size else None,
                    "changedAlphaPixels": sum(x != y for x, y in zip(a[3::4], b[3::4])) if same_size else None,
                    "beforeSHA256": hashlib.sha256(a).hexdigest(), "afterSHA256": hashlib.sha256(b).hexdigest()})
        else:
            side = sid == "eurasianNuthatch"
            expected_fallback = dict.fromkeys(["stretch", "shake", "poop0", "poop1"] +
                                             ([] if side else ["cling0", "cling1", "peck0", "peck1"]), "stand")
            row = by_id.get(sid, {})
            review = row.get("contentReview", {})
            check(f"explicit fallback metadata: {sid}", review.get("fallbackFrames") == expected_fallback
                  and review.get("sidePerching") == side and review.get("managedBehaviorReviewPending") is True)
            check(f"fallback pixels equal stand: {sid}", all(frames[k] == frames[v] for k, v in expected_fallback.items()))
            check(f"no unreviewed managed behaviors: {sid}", bool(row.get("behaviors")) and
                  all(b["productAllowed"] == (b["kind"] == "relocate") and
                      b["contentSupported"] == (b["kind"] == "relocate") for b in row["behaviors"]))
            check(f"no inferred enhanced capabilities: {sid}", set(row.get("capabilities", [])) ==
                  {"standing", "blinking", "flight", "landing"} and row.get("poseFrames") == [])
            if side:
                check("nuthatch has real side pose and probing change", frames["cling0"] != frames["stand"]
                      and frames["peck0"] != frames["peck1"])
            expansion.append({"species": sid, "slots": len(names), "distinctImages": len(set(frames.values())),
                              "fallbackFrames": expected_fallback, "sidePerching": side})
    changed_legacy = {row["species"] for row in differences if row["changed"] and not row["appended"]}
    check("all 46 legacy base atlases regenerated", changed_legacy == legacy)
    return {"baseline": baseline, "checks": checks, "errors": errors, "passed": not errors,
            "pendingVisualReview": True, "pixelDifferences": differences, "expansion": expansion,
            "note": "Pixel identity is not semantic behavior approval. Shared export separately checks runtime hit caches and pigment alpha bounds."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--shared", type=Path, help="Export folder; defaults to ROOT/shared")
    parser.add_argument("--baseline", default="53680ae5738cdd5caabe460c4bf25e7090659ada")
    parser.add_argument("--output", type=Path, help="Write JSON evidence here; otherwise stdout")
    args = parser.parse_args()
    try:
        report = audit(args.root, args.shared or args.root / "shared", args.baseline)
    except (OSError, ValueError, KeyError, IndexError, struct.error, zlib.error, subprocess.CalledProcessError) as error:
        report = {"passed": False, "errors": [str(error)], "pendingVisualReview": True}
    output = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(output)
    else:
        sys.stdout.write(output)
    if not report["passed"]:
        for error in report["errors"]:
            print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
