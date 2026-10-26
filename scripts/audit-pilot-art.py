#!/usr/bin/env python3
"""Audit M8a + E0 after the coordinator's unified shared export (stdlib only).

python3 scripts/audit-pilot-art.py --output /tmp/chirp-pilot-art-audit.json

Reads shared/art and frozen git 18ce36f, never builds, exports or starts the app.
Exit 0 means the recorded pixel/metadata checks passed, not visual acceptance.
The report contains all 3587 baseline slot hashes and all 158 appended frames.
"""
import argparse
import hashlib
import importlib.util
import json
import math
import struct
import subprocess
import sys
import zlib
from pathlib import Path


CORE = ["lookNear", "lookFar", "alertRise", "alertHold", "alertRelax",
        "restLower", "restTuck", "restWake", "takeoffCrouch", "takeoffPush"]
M8A = {
    "greatTit": ["inspectLean", "inspectDown", "inspectLift", "inspectSettle"],
    "orientalMagpie": ["tailPoise", "tailBalance", "tailCounter", "tailSettle"],
    "greatSpottedWoodpecker": ["sideBrace", "sideDraw", "sideTap", "sideRecover"],
    "mallard": ["wingLook", "wingReach", "wingSmooth", "wingRecover"],
    "littleEgret": ["neckPoise", "neckReach", "neckObserve", "neckRecover"],
    "magpieRobin": ["tailReady", "tailLift", "tailPulse", "tailRecover"],
}
E0 = {
    "eurasianGreatTit": ["inspectLean", "inspectDown", "inspectLift", "inspectSettle"],
    "whiteWagtail": ["tailPoise", "tailLift", "tailFall", "tailSettle"],
    "indianWhiteEye": ["gleanReady", "gleanReach", "gleanRecoil", "gleanSettle"],
    "crestedMyna": ["peckReady", "peckLower", "peckLift", "peckSettle"],
    "eurasianNuthatch": ["sideBrace", "sideReach", "sideProbe", "sideRecover"],
    "greatEgret": ["neckPoise", "neckReach", "neckObserve", "neckRecover"],
}
EXPECTED = {sid: ([] if sid == "magpieRobin" else CORE) + signature
            for sid, signature in {**M8A, **E0}.items()}


def load_decoder():
    """Reuse the existing PNG CRC/filter/palette and atlas extraction code."""
    path = Path(__file__).with_name("audit-u2-art.py")
    spec = importlib.util.spec_from_file_location("chirp_u2_art_decoder", path)
    module = importlib.util.module_from_spec(spec)
    # Import executes definitions only: audit-u2-art's __main__ is not entered.
    previous = sys.dont_write_bytecode
    try:
        sys.dont_write_bytecode = True
        spec.loader.exec_module(module)
    finally:
        sys.dont_write_bytecode = previous
    return module


def sha(data):
    return hashlib.sha256(data).hexdigest()


def point(value):
    if isinstance(value, dict):
        value = [value.get("x"), value.get("y")]
    if (not isinstance(value, (list, tuple)) or len(value) != 2
            or any(isinstance(v, bool) or not isinstance(v, (int, float))
                   or not math.isfinite(v) for v in value)):
        return None
    return tuple(value)


def ink_points(pixels, size):
    return [(i % size, i // size) for i, alpha in enumerate(pixels[3::4]) if alpha]


def anchor_evidence(anchor, pixels, size, ink, tolerance):
    """Nearest *native pixel center*, with no implicit y-flip or coarse rounding.

    A triangle tip can lie between samples; allow at most two native pixels by
    default and record the exact distance and RGBA. Alpha proximity does not
    prove that a pixel is a bill, nor that an occluded tucked bill is visible.
    """
    p = point(anchor)
    if p is None:
        return {"passed": False, "error": "missing or non-finite logical anchor", "anchor": anchor}
    x, y = p
    px, py = x * size / 48, y * size / 48
    nearest = min(ink, key=lambda q: (q[0]+0.5-px)**2 + (q[1]+0.5-py)**2) if ink else None
    distance = math.hypot(nearest[0]+0.5-px, nearest[1]+0.5-py) if nearest else None
    inside = 0 <= x < 48 and 0 <= y < 48
    result = {"logical": [x, y], "native": [px, py], "insideCanvas": inside,
              "toleranceNativePixels": tolerance, "distanceNativePixels": distance,
              "passed": inside and distance is not None and distance <= tolerance}
    if nearest:
        i = (nearest[1] * size + nearest[0]) * 4
        result["nearestPixel"] = list(nearest)
        result["nearestRGBA"] = list(pixels[i:i+4])
        result["distanceLogicalUnits"] = distance * 48 / size
        result["placements"] = []
        for scale in (0.5, 1, 2):
            for right in (True, False):
                mx = x if right else 48-x
                foot_x = 29 if right else 19
                native_x = nearest[0] if right else size-1-nearest[0]
                ink_x = (native_x+0.5)*48/size
                ink_y = (nearest[1]+0.5)*48/size
                result["placements"].append({
                    "scale": scale, "facingRight": right,
                    "anchorOffsetFromFoot": [(mx-foot_x)*scale, (y-39)*scale],
                    "nearestPixelOffsetFromFoot": [(ink_x-foot_x)*scale, (ink_y-39)*scale],
                    "distanceWorldUnits": distance*48/size*scale,
                })
    return result


def audit(root, shared, baseline, tolerance):
    decoder = load_decoder()

    def git(*args):
        return subprocess.check_output(["git", *args], cwd=root, stderr=subprocess.PIPE)

    commit = git("rev-parse", "--verify", f"{baseline}^{{commit}}").decode().strip()

    def historical(path):
        return git("show", f"{commit}:{path}")

    old_data = historical("shared/art/manifest.json")
    new_data = (shared / "art/manifest.json").read_bytes()
    old, new = json.loads(old_data), json.loads(new_data)
    checks, errors, species_rows, legacy_rows, new_rows = {}, [], [], [], []

    def check(name, condition):
        checks[name] = bool(condition)
        if not condition:
            errors.append(name)

    old_ids, new_ids = set(old["frameSizes"]), set(new["frameSizes"])
    check("100 baseline species and identical current species", len(old_ids) == 100 and old_ids == new_ids)
    check("34 common names retain their indices", new["frames"] == old["frames"] and len(new["frames"]) == 34)
    check("48-unit canvas and (29,39) foot unchanged", old["logicalFrameSize"] == new["logicalFrameSize"] == 48
          and old["footAnchor"] == new["footAnchor"] == [29, 39])
    check("native frame densities unchanged", old["frameSizes"] == new["frameSizes"])
    check("no foreign speciesFrames keys", set(new.get("speciesFrames", {})) <= new_ids)
    check("12 declared pilot species exist", set(EXPECTED) <= old_ids)
    check("pose clock unchanged", old.get("poseClock") == new.get("poseClock"))
    old_count = new_count = appended_count = 0
    for sid in sorted(old_ids | new_ids):
        # Species IDs are repository-controlled filenames, not arbitrary paths.
        if not sid.isalnum():
            raise ValueError(f"Invalid species ID: {sid!r}")
        old_names = old.get("speciesFrames", {}).get(sid, old["frames"]) if sid in old_ids else []
        names = new.get("speciesFrames", {}).get(sid, new["frames"]) if sid in new_ids else []
        old_count += len(old_names)
        new_count += len(names)
        added = names[len(old_names):]
        appended_count += len(added)
        expected = EXPECTED.get(sid, [])
        check(f"{sid}: unique frame names", len(names) == len(set(names)) and len(old_names) == len(set(old_names)))
        check(f"{sid}: complete old prefix unchanged", names[:len(old_names)] == old_names)
        check(f"{sid}: exact approved append order", added == expected)
        row = {"species": sid, "oldSlots": len(old_names), "currentSlots": len(names),
               "appended": added, "expectedAppended": expected}
        species_rows.append(row)
        try:
            size, old_size = new["frameSizes"][sid], old["frameSizes"][sid]
            if (not isinstance(size, int) or not isinstance(old_size, int) or size < 48 or old_size < 48):
                raise ValueError("Invalid native frame size")
            before_png = historical(f"shared/art/{sid}.png")
            after_png = (shared / "art" / f"{sid}.png").read_bytes()
            before = decoder.atlas_frames(before_png, old_size, old_names)
            frames = decoder.atlas_frames(after_png, size, names)
        except (OSError, ValueError, KeyError, IndexError, struct.error, zlib.error,
                subprocess.CalledProcessError) as error:
            row["error"] = str(error)
            check(f"{sid}: both atlases decoded", False)
            continue
        row.update({"nativeSize": size, "baselineAtlasSHA256": sha(before_png),
                    "currentAtlasSHA256": sha(after_png)})
        old_hashes, added_hashes = {}, {}
        for name, pixels in before.items():
            old_hashes.setdefault(sha(pixels), []).append(name)
        for index, name in enumerate(old_names):
            a, b = before[name], frames.get(name)
            actual_index = names.index(name) if name in names else None
            same = old_size == size and a == b and actual_index == index
            legacy_rows.append({"species": sid, "frame": name, "baselineIndex": index,
                                "currentIndex": actual_index, "sameNameIndexPixels": same,
                                "beforeSHA256": sha(a), "afterSHA256": sha(b) if b is not None else None,
                                "changedPixels": sum(a[i:i+4] != b[i:i+4] for i in range(0, len(a), 4))
                                if b is not None and len(a) == len(b) else None})
            check(f"{sid}/{name}: old slot identical", same)
        anchors = new.get("poseClips", {}).get(sid, {}).get("beakAnchors", {})
        old_anchors = old.get("poseClips", {}).get(sid, {}).get("beakAnchors", {})
        check(f"{sid}: prior beak anchors retained", all(
            name in anchors and decoder.equivalent(value, anchors[name]) for name, value in old_anchors.items()))
        for name in added:
            pixels = frames[name]
            digest = sha(pixels)
            duplicates_old = old_hashes.get(digest, [])
            duplicates_new = added_hashes.get(digest, []).copy()
            added_hashes.setdefault(digest, []).append(name)
            ink = ink_points(pixels, size)
            bounds = [min(q[0] for q in ink), min(q[1] for q in ink),
                      max(q[0] for q in ink)+1, max(q[1] for q in ink)+1] if ink else None
            border = [list(q) for q in ink if q[0] in (0, size-1) or q[1] in (0, size-1)]
            beak = anchor_evidence(anchors.get(name), pixels, size, ink, tolerance)
            foot = anchor_evidence(new["footAnchor"], pixels, size, ink, tolerance)
            check(f"{sid}/{name}: new nonempty image", bool(ink))
            check(f"{sid}/{name}: differs from all prior images", not duplicates_old)
            check(f"{sid}/{name}: differs from other new images", not duplicates_new)
            check(f"{sid}/{name}: transparent canvas border", not border)
            check(f"{sid}/{name}: beak anchor meets ink", beak["passed"])
            check(f"{sid}/{name}: foot anchor meets ink", foot["passed"])
            entry = {"species": sid, "frame": name, "index": names.index(name), "sha256": digest,
                     "nativeSize": size, "opaquePixelCount": len(ink), "inkBoundsNative": bounds,
                     "borderPixels": border, "duplicatesOld": duplicates_old, "duplicatesNew": duplicates_new,
                     "beak": beak, "foot": foot}
            if bounds:
                entry["inkBoundsLogical"] = [v*48/size for v in bounds]
            if sid == "greatSpottedWoodpecker" and name == "sideTap":
                check("woodpecker sideTap on existing wall plane", decoder.equivalent(anchors.get(name), [29, 13.7]))
            if sid == "greatSpottedWoodpecker" and name in M8A[sid]:
                grip = anchor_evidence([29, 33], pixels, size, ink, tolerance)
                entry["upperWallGrip"] = grip
                check(f"{sid}/{name}: upper wall grip meets ink", grip["passed"])
            new_rows.append(entry)
        row["distinctNewImages"] = len(added_hashes)
        row["distinctOldImages"] = len(old_hashes)
    check("3587 baseline frame slots", old_count == 3587)
    check("3587 old slots individually compared", len(legacy_rows) == 3587)
    check("158 appended frame slots", appended_count == 158 and len(new_rows) == 158)
    check("3745 total frame slots", new_count == 3745)
    check("M8a contributes 74 appended frames", sum(1 for r in new_rows if r["species"] in M8A) == 74)
    check("E0 contributes 84 appended frames", sum(1 for r in new_rows if r["species"] in E0) == 84)
    return {
        "schemaVersion": 1, "baseline": baseline, "baselineCommit": commit,
        "sharedDirectory": str(shared.resolve()),
        "baselineManifestSHA256": sha(old_data), "currentManifestSHA256": sha(new_data),
        "decoder": "scripts/audit-u2-art.py: atlas_frames/png_rgba",
        "decoderSHA256": sha(Path(__file__).with_name("audit-u2-art.py").read_bytes()),
        "counts": {"oldSlots": old_count, "oldSlotsCompared": len(legacy_rows),
                   "newSlots": appended_count, "newSlotsCompared": len(new_rows), "currentSlots": new_count},
        "passed": not errors, "checks": checks, "errors": errors,
        "species": species_rows, "legacyFrames": legacy_rows, "newFrames": new_rows,
        "pendingVisualReview": True,
        "limits": [
            "PNG hashes normalize invisible RGB to zero using the existing U2 decoder.",
            "Nearest opaque pixels verify anchor proximity, not semantic identification of the bill.",
            "Scale/direction entries transform the native pixel grid; they do not independently render desktop minification.",
            "A clear border checks exported ink containment; it cannot detect geometry already clipped outside a canvas.",
            "Original authorship, readable anatomy, motion continuity and real side contact require coordinator visual/runtime review.",
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--shared", type=Path, help="Export directory; defaults to ROOT/shared")
    parser.add_argument("--baseline", default="18ce36f")
    parser.add_argument("--anchor-tolerance", type=float, default=2.0, help="Native pixel-center distance (default 2)")
    parser.add_argument("--output", type=Path, help="JSON evidence path; otherwise stdout")
    args = parser.parse_args()
    try:
        if not math.isfinite(args.anchor_tolerance) or not 0 < args.anchor_tolerance <= 2:
            raise ValueError("Anchor tolerance must be greater than 0 and at most 2 native pixels")
        report = audit(args.root, args.shared or args.root / "shared", args.baseline, args.anchor_tolerance)
    except (OSError, ValueError, TypeError, KeyError, IndexError, AttributeError,
            ImportError, struct.error, zlib.error, subprocess.CalledProcessError) as error:
        report = {"schemaVersion": 1, "baseline": args.baseline, "passed": False,
                  "errors": [str(error)], "pendingVisualReview": True}
    output = json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True, allow_nan=False) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(output, encoding="utf-8")
    else:
        sys.stdout.write(output)
    if not report["passed"]:
        for error in report["errors"]:
            print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
