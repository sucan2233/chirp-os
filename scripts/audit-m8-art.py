#!/usr/bin/env python3
"""Audit complete M8 after the coordinator's unified shared export (stdlib only).

python3 scripts/audit-m8-art.py --output /tmp/chirp-m8-art-audit.json

Reads frozen f06448f and the separately authored m8-art-contract.json. Never
builds, exports, launches the app, or rewrites historical evidence. Exit 0 means
pixel/metadata checks passed; native runtime and visual acceptance are separate.
Evidence includes all 3745 old slots, all 450 additions, and all 608 M8/E0 slots.
"""
import argparse
import hashlib
import importlib.util
import json
import math
import re
import struct
import subprocess
import sys
import zlib
from pathlib import Path


BASELINE = "f06448f1682780e3fc4fee1f4f613f5268292a03"
CORE = ["lookNear", "lookFar", "alertRise", "alertHold", "alertRelax",
        "restLower", "restTuck", "restWake", "takeoffCrouch", "takeoffPush"]
BATCH_BUDGETS = {"M8a": 74, "M8b": 32, "M8c": 112, "M8d": 102,
                 "M8e": 102, "M8f": 102, "E0": 84}
CURRENT_BATCHES = {"M8b", "M8c", "M8d", "M8e", "M8f"}
BUDGETS = {"baselineSlots": 3745, "appendedSlots": 450, "currentSlots": 4195,
           "m8Slots": 524, "e0Slots": 84, "supportedSpecies": 52,
           "unchangedExpansionSpecies": 48, "variantsPerSpecies": 2,
           "simulationVersion": 21}
CATCH = ["catchOpen", "catchClose", "catchRecover"]
BASE_CLIPS = {"watch": ["lookNear", "lookFar", "lookNear"],
              "alert": ["alertRise", "alertHold", "alertRelax"],
              "rest": ["restLower", "restTuck", "restWake"],
              "takeoffPreparation": ["takeoffCrouch", "takeoffPush"]}
FAILURES = (OSError, ValueError, TypeError, KeyError, IndexError, AttributeError,
            ImportError, struct.error, zlib.error, subprocess.CalledProcessError)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read_json(data):
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError(f"Duplicate JSON key: {key}")
            result[key] = value
        return result

    def invalid(value):
        raise ValueError(f"Non-finite JSON number: {value}")

    def finite_float(value):
        number = float(value)
        if not math.isfinite(number):
            invalid(value)
        return number

    return json.loads(data, object_pairs_hook=pairs, parse_constant=invalid, parse_float=finite_float)


def load_contract(path):
    """Fail closed: acceptance never derives its budgets/names from the export."""
    contract = read_json(path.read_bytes())
    if (contract.get("schemaVersion") != 1 or contract.get("baselineCommit") != BASELINE
            or contract.get("budgets") != BUDGETS or contract.get("coreFrames") != CORE):
        raise ValueError("M8 contract header or independent budgets differ")
    batches = contract["batches"]
    if set(batches) != set(BATCH_BUDGETS):
        raise ValueError("M8 contract batch scope differs")
    signatures, appended, delivered, membership = {}, {}, {}, {}
    for batch, budget in BATCH_BUDGETS.items():
        entry = batches[batch]
        names_by_species, base = entry["signatures"], entry["baseAppendSpecies"]
        if (entry["budget"] != budget or len(names_by_species) != (6 if batch in ("M8a", "E0") else 8)
                or len(base) != len(set(base)) or not set(base) <= set(names_by_species)
                or 10 * len(base) + 4 * len(names_by_species) != budget):
            raise ValueError(f"Invalid fixed species/frame budget for {batch}")
        for sid, names in names_by_species.items():
            if (not re.fullmatch(r"[A-Za-z][A-Za-z0-9]*", sid) or sid in signatures
                    or not isinstance(names, list) or len(names) != 4
                    or any(not isinstance(n, str) or not re.fullmatch(r"[A-Za-z][A-Za-z0-9]*", n) for n in names)
                    or len(set(names)) != 4 or set(names) & set(CORE)):
                raise ValueError(f"Invalid frozen signature: {batch}/{sid}")
            signatures[sid] = names
            membership[sid] = batch
            delivered[sid] = (CORE if sid in base else []) + names
            if batch in CURRENT_BATCHES:
                appended[sid] = delivered[sid]
    if (len(signatures) != 52 or len(appended) != 40
            or sum(map(len, appended.values())) != 450
            or sum(map(len, delivered.values())) != 608):
        raise ValueError("M8 contract coverage differs")
    return contract, signatures, appended, delivered, membership


def load_pilot():
    """Reuse historical decoder and native-pixel anchor math without running it."""
    path = Path(__file__).with_name("audit-pilot-art.py")
    spec = importlib.util.spec_from_file_location("chirp_m8_pilot_math", path)
    module = importlib.util.module_from_spec(spec)
    previous = sys.dont_write_bytecode
    try:
        sys.dont_write_bytecode = True
        spec.loader.exec_module(module)
    finally:
        sys.dont_write_bytecode = previous
    return module


def finite_positive(value):
    return (not isinstance(value, bool) and isinstance(value, (int, float))
            and math.isfinite(value) and value > 0)


def audit(root, shared, baseline, tolerance, contract_path):
    contract, signatures, expected_append, delivered, membership = load_contract(contract_path)
    pilot = load_pilot()
    decoder = pilot.load_decoder()
    report = {"schemaVersion": 1, "baseline": baseline, "passed": False,
              "sharedDirectory": str(shared.resolve()), "contract": contract,
              "contractSHA256": sha(contract_path.read_bytes()), "checks": {}, "errors": [],
              "species": [], "legacyFrames": [], "newFrames": [], "deliveredFrames": [],
              "clips": [], "support": [], "props": [], "batches": {}, "sources": [],
              "pendingVisualReview": True, "pendingNativeRuntimeReview": True,
              "limits": [
                  "Invisible RGB is normalized to zero by the historical PNG decoder.",
                  "Alpha proximity measures native pixel centers, not semantic bill identity.",
                  "Scale/mirror placements are mathematical transforms, not native desktop captures.",
                  "Transparent borders cannot detect geometry already clipped before PNG export.",
                  "Pixel uniqueness does not establish authorship, readable anatomy or motion continuity.",
                  "Simulation replay fixtures and native lifecycle checks belong to unified validation."]}

    def check(name, condition):
        report["checks"][name] = bool(condition)
        if not condition:
            report["errors"].append(name)

    def git(*args):
        return subprocess.check_output(["git", *args], cwd=root, stderr=subprocess.PIPE)

    try:
        commit = git("rev-parse", "--verify", f"{baseline}^{{commit}}").decode().strip()
        report["baselineCommit"] = commit
        if commit != BASELINE:
            raise ValueError("Baseline must resolve to the frozen f06448f commit")

        def historical(path):
            return git("show", f"{commit}:{path}")

        old_data = historical("shared/art/manifest.json")
        new_data = (shared / "art/manifest.json").read_bytes()
        old, new = read_json(old_data), read_json(new_data)
        report.update(baselineManifestSHA256=sha(old_data), currentManifestSHA256=sha(new_data))
        for name in ("audit-pilot-art.py", "audit-u2-art.py", "audit-m8-art.py"):
            path = Path(__file__).with_name(name)
            report["sources"].append({"path": f"scripts/{name}", "sha256": sha(path.read_bytes())})
        # Source comparison is additional evidence, never the expected-name oracle.
        for batch, entry in contract["batches"].items():
            path = root / "platforms/macos/Sources/BirdingCore/Behavior" / entry["geometry"]
            try:
                data = path.read_bytes()
                text = data.decode()
                body = text.split("func signatureFrameNames", 1)[1].split("default:", 1)[0]
                rows = re.findall(r'case\s+\.(\w+)\s*:\s*return\s*\[([^]]*)\]', body)
                actual = {sid: re.findall(r'"([A-Za-z0-9]+)"', names) for sid, names in rows}
                check(f"{batch}: source signature names match frozen contract", actual == entry["signatures"])
                report["sources"].append({"path": str(path.relative_to(root)), "sha256": sha(data),
                                          "signatureNames": actual})
            except FAILURES as error:
                check(f"{batch}: geometry readable ({error})", False)

        old_ids, ids = set(old["frameSizes"]), set(new["frameSizes"])
        check("100 baseline and current species", len(old_ids) == len(ids) == 100 and ids == old_ids)
        check("34 common frame names and indices retained", old["frames"] == new["frames"] and len(new["frames"]) == 34)
        check("48-unit canvas and foot retained", old["logicalFrameSize"] == new["logicalFrameSize"] == 48
              and old["footAnchor"] == new["footAnchor"] == [29, 39])
        check("native densities retained", old["frameSizes"] == new["frameSizes"])
        check("manifest schema retained", old["schemaVersion"] == new["schemaVersion"] == 2)
        for key in ("poseClock", "signatureClock"):
            check(f"{key} retained", new.get(key) == old.get(key) and bool(new.get(key)))
        check("52 species-specific atlases", set(new.get("speciesFrames", {})) == set(signatures))
        check("52 pose metadata entries", set(new.get("poseClips", {})) == set(signatures))
        check("100 atlas PNG files", {p.stem for p in (shared / "art").glob("*.png")} == ids)
        old_count = current_count = append_count = 0
        old_hashes, current_hashes = {}, {}

        for sid in sorted(old_ids | ids):
            if not re.fullmatch(r"[A-Za-z][A-Za-z0-9]*", sid):
                raise ValueError(f"Unsafe species ID: {sid!r}")
            old_names = old.get("speciesFrames", {}).get(sid, old["frames"]) if sid in old_ids else []
            names = new.get("speciesFrames", {}).get(sid, new["frames"]) if sid in ids else []
            appended = names[len(old_names):]
            expected = expected_append.get(sid, [])
            old_count += len(old_names)
            current_count += len(names)
            append_count += len(appended)
            row = {"species": sid, "batch": membership.get(sid), "oldSlots": len(old_names),
                   "currentSlots": len(names), "appended": appended, "expectedAppended": expected}
            report["species"].append(row)
            check(f"{sid}: unique names", len(names) == len(set(names)) and len(old_names) == len(set(old_names)))
            check(f"{sid}: exact old prefix and approved append order", names == old_names + expected)
            if sid in signatures:
                check(f"{sid}: complete 10+4 pack", set(CORE + signatures[sid]) <= set(names))
            else:
                check(f"{sid}: unexpanded 34-frame atlas", names == old_names == old["frames"])
            if sid == "yellowRumpedFlycatcher":
                check("flycatcher: old catch indices 34..36", names[34:37] == old_names[34:37] == CATCH)
                check("flycatcher: base follows catch", names[37:47] == CORE and len(names) == 51)
            try:
                size, old_size = new["frameSizes"][sid], old["frameSizes"][sid]
                if type(size) is not int or type(old_size) is not int or size < 48 or old_size < 48:
                    raise ValueError("Invalid native frame size")
                before_png = historical(f"shared/art/{sid}.png")
                after_png = (shared / "art" / f"{sid}.png").read_bytes()
                before = decoder.atlas_frames(before_png, old_size, old_names)
                frames = decoder.atlas_frames(after_png, size, names)
                dimensions = list(struct.unpack_from(">II", after_png, 16))
                row.update(nativeSize=size, baselineAtlasSHA256=sha(before_png), currentAtlasSHA256=sha(after_png),
                           atlasSizeNative=dimensions, expectedAtlasSizeNative=[size * len(names), size],
                           decodedSlots=len(frames), cropSizeNative=[size, size])
                check(f"{sid}: atlas dimensions/count and square crops", dimensions == [size * len(names), size]
                      and len(frames) == len(names) and all(len(p) == size * size * 4 for p in frames.values()))
                for name, pixels in before.items():
                    old_hashes.setdefault((old_size, sha(pixels)), []).append({"species": sid, "frame": name})
                for name, pixels in frames.items():
                    current_hashes.setdefault((size, sha(pixels)), []).append({"species": sid, "frame": name})
                for index, name in enumerate(old_names):
                    a, b = before[name], frames.get(name)
                    actual_index = names.index(name) if name in names else None
                    same = old_size == size and a == b and actual_index == index
                    report["legacyFrames"].append({"species": sid, "frame": name, "baselineIndex": index,
                        "currentIndex": actual_index, "sameNameIndexPixels": same,
                        "beforeSHA256": sha(a), "afterSHA256": sha(b) if b is not None else None,
                        "baselineCropRectNative": [index * old_size, 0, old_size, old_size],
                        "currentCropRectNative": [actual_index * size, 0, size, size] if actual_index is not None else None,
                        "changedPixels": sum(a[i:i+4] != b[i:i+4] for i in range(0, len(a), 4))
                        if b is not None and len(a) == len(b) else None})
                    check(f"{sid}/{name}: old name/index/pixels retained", same)
                anchors = new.get("poseClips", {}).get(sid, {}).get("beakAnchors", {})
                # Inspect every contracted M8/E0 delivery, including retained pilots.
                for name in delivered.get(sid, []):
                    if name not in frames:
                        check(f"{sid}/{name}: delivered frame exists", False)
                        continue
                    pixels, index = frames[name], names.index(name)
                    ink = pilot.ink_points(pixels, size)
                    bounds = [min(x for x, y in ink), min(y for x, y in ink),
                              max(x for x, y in ink)+1, max(y for x, y in ink)+1] if ink else None
                    border = [list(p) for p in ink if p[0] in (0, size-1) or p[1] in (0, size-1)]
                    beak = pilot.anchor_evidence(anchors.get(name), pixels, size, ink, tolerance)
                    foot = pilot.anchor_evidence(new["footAnchor"], pixels, size, ink, tolerance)
                    entry = {"species": sid, "batch": membership[sid], "frame": name, "index": index,
                             "sha256": sha(pixels), "nativeSize": size, "cropRectNative": [index*size, 0, size, size],
                             "cropSizeNative": [size, size], "cropRGBABytes": len(pixels),
                             "opaquePixelCount": len(ink), "inkBoundsNative": bounds,
                             "inkBoundsLogical": [v*48/size for v in bounds] if bounds else None,
                             "borderPixels": border, "beak": beak, "foot": foot,
                             "newInThisBatch": name in expected}
                    check(f"{sid}/{name}: nonempty bounded ink", bool(ink) and not border)
                    check(f"{sid}/{name}: beak native distance", beak["passed"])
                    check(f"{sid}/{name}: foot native distance", foot["passed"])
                    if sid == "greatSpottedWoodpecker" and name in signatures[sid]:
                        grip = pilot.anchor_evidence([29, 33], pixels, size, ink, tolerance)
                        entry["upperWallGrip"] = grip
                        check(f"{sid}/{name}: upper wall grip", grip["passed"])
                        if name == "sideTap":
                            check("woodpecker sideTap wall plane", decoder.equivalent(anchors.get(name), [29, 13.7]))
                    report["deliveredFrames"].append(entry)
                    if name in expected:
                        report["newFrames"].append(entry)
            except FAILURES as error:
                row["error"] = str(error)
                check(f"{sid}: complete atlas decoding/evidence ({error})", False)

        # Full-image identity across every species at the same native resolution.
        # Retained pilot slots exclude only their own historical/current identity.
        for entry in report["deliveredFrames"]:
            identity = {"species": entry["species"], "frame": entry["frame"]}
            key = (entry["nativeSize"], entry["sha256"])
            duplicates_old = [p for p in old_hashes.get(key, [])
                              if entry["newInThisBatch"] or p != identity]
            duplicates_current = [p for p in current_hashes.get(key, []) if p != identity]
            entry.update(duplicatesOld=duplicates_old, duplicatesCurrent=duplicates_current)
            check(f"{entry['species']}/{entry['frame']}: unique non-copy pixels", not duplicates_old and not duplicates_current)

        check("3745 baseline slots individually compared", old_count == len(report["legacyFrames"]) == 3745)
        check("450 appended slots individually inspected", append_count == len(report["newFrames"]) == 450)
        check("4195 total atlas slots", current_count == 4195)
        check("608 cumulative M8/E0 deliveries inspected", len(report["deliveredFrames"]) == 608)
        check("40 species append frames", {r["species"] for r in report["species"] if r["appended"]} == set(expected_append))
        for batch, budget in BATCH_BUDGETS.items():
            inspected = sum(r["batch"] == batch for r in report["deliveredFrames"])
            appended = sum(r["batch"] == batch for r in report["newFrames"])
            report["batches"][batch] = {"budget": budget, "inspectedSlots": inspected,
                                         "appendedThisBatch": appended,
                                         "species": sorted(contract["batches"][batch]["signatures"])}
            check(f"{batch}: independent delivery budget", inspected == budget)
            check(f"{batch}: independent append budget", appended == (budget if batch in CURRENT_BATCHES else 0))
        report["counts"] = {"oldSlots": old_count, "oldSlotsCompared": len(report["legacyFrames"]),
                            "newSlots": append_count, "newSlotsCompared": len(report["newFrames"]),
                            "currentSlots": current_count, "deliveredSlots": len(report["deliveredFrames"]),
                            "m8Slots": sum(r["batch"] != "E0" for r in report["deliveredFrames"]),
                            "e0Slots": sum(r["batch"] == "E0" for r in report["deliveredFrames"])}
        check("M8 cumulative 524 slots; E0 retained at 84", report["counts"]["m8Slots"] == 524
              and report["counts"]["e0Slots"] == 84)
        audit_metadata(old, new, signatures, decoder, pilot, check, report)
        audit_support(root, shared, historical, ids, signatures, decoder, check, report)
        audit_props(shared, historical, git, commit, decoder, check, report)
    except FAILURES as error:
        check(f"audit input/completion error: {error}", False)
    report["passed"] = not report["errors"]
    return report


def audit_metadata(old, new, signatures, decoder, pilot, check, report):
    metadata = new.get("poseClips", {})
    for sid in sorted(set(old.get("poseClips", {})) | set(signatures)):
        try:
            before = old.get("poseClips", {}).get(sid, {})
            current = metadata.get(sid, {})
            clips, anchors = current.get("clips", {}), current.get("beakAnchors", {})
            for key, values in before.items():
                if key in ("clips", "beakAnchors"):
                    actual = current.get(key, {})
                    check(f"{sid}: prior {key} retained", all(k in actual and decoder.equivalent(v, actual[k])
                          for k, v in values.items()))
                else:
                    check(f"{sid}: prior {key} retained", decoder.equivalent(values, current.get(key)))
            expected_clips = set(before.get("clips", {})) | set(BASE_CLIPS) | {"signature.v0", "signature.v1"}
            check(f"{sid}: exact clip scope", set(clips) == expected_clips)
            check(f"{sid}: exact beak anchor scope", set(anchors) ==
                  set(before.get("beakAnchors", {})) | set(CORE) | set(signatures[sid]))
            for kind, names in BASE_CLIPS.items():
                clip = clips.get(kind, {})
                check(f"{sid}/{kind}: complete base clip", [f.get("name") for f in clip.get("frames", [])] == names)
            policy = current.get("signaturePolicy", {})
            check(f"{sid}: signature policy", policy.get("variants") == 2
                  and policy.get("recordsObservation") is False
                  and policy.get("sideOnly") is (sid in ("greatSpottedWoodpecker", "eurasianNuthatch"))
                  and all(finite_positive(policy.get(k)) for k in ("cycle", "start", "duration")))
            if all(finite_positive(policy.get(k)) for k in ("cycle", "start", "duration")):
                check(f"{sid}: signature window inside cycle", policy["start"] + policy["duration"] <= policy["cycle"])
            for variant, weights in enumerate(([0.20, 0.30, 0.22, 0.28], [0.28, 0.20, 0.32, 0.20])):
                key = f"signature.v{variant}"
                clip = clips.get(key, {})
                actual = clip.get("frames", [])
                check(f"{sid}/{key}: frozen four-frame sequence", [f.get("name") for f in actual] == signatures[sid])
                check(f"{sid}/{key}: stable ID", clip.get("id") == f"{sid}.{key}")
                duration = policy.get("duration")
                check(f"{sid}/{key}: independent cadence", finite_positive(duration) and len(actual) == 4
                      and all(finite_positive(f.get("duration")) and math.isclose(f["duration"], weight*duration,
                              rel_tol=0, abs_tol=1e-9) for f, weight in zip(actual, weights)))
            for key in list(BASE_CLIPS) + ["signature.v0", "signature.v1"]:
                clip = clips.get(key, {})
                frames = clip.get("frames", [])
                check(f"{sid}/{key}: foot/loop/recovery", clip.get("foot") == {"x": 29, "y": 39}
                      and clip.get("maximumLoops") == 1 and clip.get("recovery") == "currentEngineState")
                check(f"{sid}/{key}: finite positive timing", bool(frames) and all(finite_positive(f.get("duration")) for f in frames))
                check(f"{sid}/{key}: clip bills match frame anchors", bool(frames) and all(
                    pilot.point(f.get("beak")) is not None and pilot.point(anchors.get(f.get("name"))) is not None
                    and decoder.equivalent(list(pilot.point(f["beak"])), list(pilot.point(anchors[f["name"]]))) for f in frames))
                report["clips"].append({"species": sid, "key": key, "clip": clip})
            transport = [f"fly{i}" for i in range(8)] + [f"land{i}" for i in range(3)] + [f"glide{i}" for i in range(3)] + [f"bank{i}" for i in range(3)] + ["bound", "stand"]
            if sid in ("barnSwallow", "yellowRumpedFlycatcher"):
                check(f"{sid}: catch transport excludes new extras", set(current.get("transportBeakAnchors", {})) == set(transport + CATCH))
        except FAILURES as error:
            check(f"{sid}: complete metadata evidence ({error})", False)
    check("52 complete signature variant pairs", len([r for r in report["clips"] if r["key"].startswith("signature.")]) == 104)


def audit_support(root, shared, historical, ids, signatures, decoder, check, report):
    before = read_json(historical("shared/species-support.json"))
    data = (shared / "species-support.json").read_bytes()
    support = read_json(data)
    old_rows = {r["species"]: r for r in before}
    rows = {r["species"]: r for r in support}
    report["supportSHA256"] = sha(data)
    check("100 unique support rows", len(support) == len(rows) == 100 and set(rows) == ids)
    check("52 complete base pack support rows", {sid for sid, r in rows.items() if r.get("poseFrames")} == set(signatures))
    for sid in sorted(ids):
        a, b = old_rows.get(sid, {}), rows.get(sid, {})
        check(f"{sid}: support pose pack", b.get("poseFrames") == (CORE if sid in signatures else [])
              and b.get("missingPoseFrames") == [])
        old_behaviors = {r["kind"]: r for r in a.get("behaviors", [])}
        behaviors = {r["kind"]: r for r in b.get("behaviors", [])}
        same_permissions = (set(behaviors) == set(old_behaviors) and len(behaviors) == len(b.get("behaviors", []))
                            and all(v.get("productAllowed") is old_behaviors[k].get("productAllowed")
                                    for k, v in behaviors.items()))
        check(f"{sid}: all ecological permissions retained", same_permissions)
        check(f"{sid}: review/fallback scope retained", decoder.equivalent(a.get("contentReview"), b.get("contentReview")))
        for kind, behavior in behaviors.items():
            previous = old_behaviors.get(kind, {})
            check(f"{sid}/{kind}: previous content support retained", not previous.get("contentSupported") or behavior.get("contentSupported") is True)
            check(f"{sid}/{kind}: content requires permission and frames", not behavior.get("contentSupported")
                  or (behavior.get("productAllowed") is True and behavior.get("missingFrames") == []))
        if sid not in signatures:
            check(f"{sid}: unexpanded support unchanged", decoder.equivalent(a, b))
        report["support"].append({"species": sid, "permissionsRetained": same_permissions,
                                   "before": a, "current": b})
    check("48 unexpanded species retained", len(ids - set(signatures)) == 48)
    catalog = read_json((shared / "species.json").read_bytes())
    bundled = read_json((root / "platforms/macos/Sources/BirdingCore/Resources/species.json").read_bytes())
    check("catalog unchanged and bundled/shared agree", decoder.equivalent(catalog, read_json(historical("shared/species.json")))
          and decoder.equivalent(catalog, bundled) and len(catalog["species"]) == 100
          and {b["id"] for b in catalog["species"]} == ids)


def audit_props(shared, historical, git, commit, decoder, check, report):
    paths = git("ls-tree", "-r", "--name-only", commit, "shared/art/props").decode().splitlines()
    pngs = [p for p in paths if p.endswith(".png")]
    check("16 prop files retained", len(pngs) == 16 and {Path(p).name for p in pngs} ==
          {p.name for p in (shared / "art/props").glob("*.png")})
    check("prop manifest retained", decoder.equivalent(read_json(historical("shared/art/props/manifest.json")),
          read_json((shared / "art/props/manifest.json").read_bytes())))
    for path in pngs:
        try:
            a, b = historical(path), (shared / Path(path).relative_to("shared")).read_bytes()
            same = decoder.png_rgba(a) == decoder.png_rgba(b)
            report["props"].append({"file": Path(path).name, "beforeSHA256": sha(a), "afterSHA256": sha(b), "samePixels": same})
            check(f"prop {Path(path).name}: pixels retained", same)
        except FAILURES as error:
            check(f"prop {Path(path).name}: readable ({error})", False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--shared", type=Path, help="Defaults to ROOT/shared")
    parser.add_argument("--baseline", default=BASELINE, help="Must resolve to frozen f06448f")
    parser.add_argument("--contract", type=Path, default=Path(__file__).with_name("m8-art-contract.json"))
    parser.add_argument("--anchor-tolerance", type=float, default=2.0, help="At most two native pixel centers")
    parser.add_argument("--output", type=Path, help="New JSON evidence file; existing files are never overwritten")
    args = parser.parse_args()
    try:
        if not math.isfinite(args.anchor_tolerance) or not 0 < args.anchor_tolerance <= 2:
            raise ValueError("Anchor tolerance must be greater than zero and at most two native pixels")
        report = audit(args.root.resolve(), args.shared or args.root / "shared", args.baseline,
                       args.anchor_tolerance, args.contract)
    except FAILURES as error:
        report = {"schemaVersion": 1, "baseline": args.baseline, "passed": False,
                  "errors": [str(error)], "pendingVisualReview": True, "pendingNativeRuntimeReview": True}
    output = json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True, allow_nan=False) + "\n"
    if args.output:
        try:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            with args.output.open("x", encoding="utf-8") as stream:
                stream.write(output)
        except OSError as error:
            print(f"Cannot write new evidence file: {error}", file=sys.stderr)
            return 1
    else:
        sys.stdout.write(output)
    for error in report["errors"]:
        print(error, file=sys.stderr)
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
