#!/usr/bin/env python3
"""Audit the current E0 delivery and the remaining base expansion species.

Uses exported PNG pixels, manifests and current Swift configuration. This is
not a runtime, visual-quality or natural-history acceptance test. Outputs a
deterministic JSON report; no build, export, app launch or user data access.

Run only after the coordinator has refreshed the shared art/support exports:
python3 scripts/audit-expansion-capabilities.py --output docs/evidence/e0-capability-audit-20261026.json

The expansion-capability-audit-20261026.json baseline is historical evidence;
this script reads it for comparison and refuses to overwrite it.
"""
import argparse
from collections import Counter, defaultdict
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import re
import sys

sys.dont_write_bytecode = True

BASELINE_PATH = "docs/evidence/expansion-capability-audit-20261026.json"
E0_IDS = {"eurasianGreatTit", "whiteWagtail", "indianWhiteEye",
          "crestedMyna", "eurasianNuthatch", "greatEgret"}
E0_KINDS = {"watch", "alert", "rest", "takeoffPreparation"}
BASE_CAPABILITIES = {"standing", "blinking", "flight", "landing"}
E0_CAPABILITIES = BASE_CAPABILITIES | {"observationPose", "alertPose", "restPose", "takeoffPose"}


def audit(root):
    inputs = {}

    def read(path):
        data = (root / path).read_bytes()
        inputs[path] = hashlib.sha256(data).hexdigest()
        return data

    def document(path):
        return json.loads(read(path))

    decoder_path = root / "scripts/audit-u2-art.py"
    read("scripts/audit-u2-art.py")
    spec = importlib.util.spec_from_file_location("u2_art_decoder", decoder_path)
    decoder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(decoder)

    manifest = document("shared/art/manifest.json")
    baseline = document(BASELINE_PATH)
    catalog = document("shared/species.json")["species"]
    support = document("shared/species-support.json")
    expansion = document("docs/species-expansion-100.json")["species"]
    motion_source = read("platforms/macos/Sources/BirdingCore/SpeciesBehavior.swift").decode()
    gallery_source = read("platforms/macos/Sources/BirdingCore/GalleryPose.swift").decode()
    pose_source = read("platforms/macos/Sources/BirdingCore/Behavior/PoseClip.swift").decode()
    art_source = read("platforms/macos/Sources/Birding/ExpansionBirdArt.swift").decode()
    pilot_source = read("platforms/macos/Sources/BirdingCore/Behavior/ExpansionPilotArtGeometry.swift").decode()
    profile_source = read("platforms/macos/Sources/BirdingCore/Behavior/SpeciesBehaviorProfile.swift").decode()
    lively_source = read("platforms/macos/Sources/BirdingCore/Behavior/LivelyMotion.swift").decode()
    # Capture provenance for permission, completion and handbook interpretations.
    for path in (
        "scripts/audit-expansion-capabilities.py",
        "platforms/macos/Sources/Birding/ExpansionPilotArt.swift",
        "platforms/macos/Sources/Birding/PixelArt.swift",
        "platforms/macos/Sources/Birding/PosePreviewExport.swift",
        "platforms/macos/Sources/BirdingCore/Behavior/BehaviorEngine.swift",
        "platforms/macos/Sources/BirdingCore/Behavior/BehaviorRecording.swift",
        "platforms/macos/Sources/BirdingCore/Behavior/BehaviorRuntime.swift",
        "platforms/macos/Sources/Birding/ObservationJournalWindow.swift",
        "platforms/macos/Sources/Birding/JournalPreviewView.swift",
        "platforms/macos/Sources/Birding/ContentSupportExport.swift",
    ):
        read(path)

    def require(condition, message):
        if not condition:
            raise ValueError(message)

    by_id = {row["id"]: row for row in catalog}
    support_by_id = {row["species"]: row for row in support}
    new_ids = {row["id"] for row in expansion}
    baseline_by_id = {row["id"]: row for row in baseline["expansion"]}
    require(len(by_id) == len(catalog) == len(support_by_id) == len(support) == 100,
            "Expected 100 unique catalog/support rows; review audit scope after catalog changes")
    require(set(by_id) == set(support_by_id) == set(manifest["frameSizes"]),
            "Catalog/support/native frame-size IDs differ")
    require(len(expansion) == len(new_ids) == 54, "Expected 54 unique expansion IDs")
    require(set(baseline_by_id) == new_ids and baseline["schemaVersion"] == 1,
            "Historical expansion baseline scope/schema changed")
    require(E0_IDS <= new_ids, "E0 species missing from expansion scope")
    for source, name, expected in (
        (pilot_source, "species", E0_IDS),
        (profile_source, "expansionPilotSpecies", E0_IDS),
        (profile_source, "expansionPilotKinds", E0_KINDS),
    ):
        match = re.search(r"public static let " + name + r"\s*:[^=]+?=\s*\[([^\]]+)\]", source)
        require(match is not None and set(re.findall(r"\.(\w+)", match[1])) == expected,
                f"E0 source contract changed: {name}; review audit scope")
    require(new_ids == {sid for sid, row in support_by_id.items()
                        if row["contentReview"]["cohort"] in {"upstream-v0.7-base", "expansion-e0-partial"}},
            "Expansion specification and support cohorts differ")
    require(E0_IDS == {sid for sid, row in support_by_id.items()
                       if row["contentReview"]["cohort"] == "expansion-e0-partial"},
            "E0 support export is stale or has an unexpected cohort; refresh shared exports")

    motion_pattern = (r"case \.(\w+): return Motion\(action: \.(\w+), cycle: ([\d.]+), "
                      r"start: ([\d.]+), duration: ([\d.]+), rate: ([\d.]+), hop: ([\d.]+)\)")
    motions = {}
    for sid, action, *values in re.findall(motion_pattern, motion_source):
        require(sid not in motions, f"Duplicate motion: {sid}")
        motions[sid] = {"action": action, **dict(zip(
            ("cycleSeconds", "startSeconds", "durationSeconds", "frameRate", "hopLogicalUnits"),
            map(float, values)))}
    require(set(motions) == set(by_id), "Motion parser no longer covers catalog; inspect Swift source")
    pose_match = re.search(r"public static let frameNames=\[([^\]]+)\]", pose_source)
    require(pose_match is not None, "Cannot extract enhanced pose contract")
    pose_names = re.findall(r'"([^"]+)"', pose_match[1])
    require(len(pose_names) == 10, "Enhanced pose contract changed")
    signature_match = re.search(r"public static func signatureFrameNames\([^\n]+\{(.*?)\n    \}",
                                pilot_source, re.S)
    require(signature_match is not None, "Cannot extract E0 signature frame contract")
    signatures = {sid: re.findall(r'"([^"]+)"', names) for sid, names in re.findall(
        r"case \.(\w+): return \[([^\]]+)\]", signature_match[1])}
    require(set(signatures) == E0_IDS and all(len(set(names)) == len(names) == 4
                                             for names in signatures.values()),
            "Expected four unique signature frames per E0 species")
    gallery_compact = re.sub(r"\s+", "", gallery_source)
    gallery_branches = ["LivelyMotion.previewFrame(species:id,age:t)",
                        "ifid==.eurasianNuthatch", "ifSpeciesBehaviorProfile.profile(for:id).isExpansionSpecies"]
    require(all(branch in gallery_compact for branch in gallery_branches),
            "Re-evaluate signature/side/expansion gallery routing")
    positions = [gallery_compact.index(branch) for branch in gallery_branches]
    require(positions == sorted(positions) and 'return"idle' in gallery_compact[positions[2]:].split("}", 1)[0],
            "Gallery must prefer signatures, then nuthatch side, then all expansion idle actions")
    require("ExpansionPilotArtGeometry.signatureFrameNames(for:$0)" in re.sub(r"\s+", "", lively_source),
            "LivelyMotion no longer uses the E0 signature contract")
    anatomy = {sid: family for sid, family in re.findall(r'\.(\w+): Anatomy\("([^"]+)"', art_source)}
    require(set(anatomy) == new_ids, "Expansion renderer profiles differ from scope")

    matrix, measurements = [], []
    for species in catalog:
        sid = species["id"]
        row = support_by_id[sid]
        names = manifest["speciesFrames"].get(sid, manifest["frames"])
        require(len(names) == len(set(names)), f"Duplicate atlas frame names: {sid}")
        allowed = [b["kind"] for b in row["behaviors"] if b["productAllowed"]]
        supported = [b["kind"] for b in row["behaviors"] if b["contentSupported"]]
        matrix.append({
            "id": sid, "name": species["name"], "cohort": row["contentReview"]["cohort"],
            "frameSlots": len(names), "nativeFrameSize": manifest["frameSizes"][sid],
            "reviewedCapabilities": row["capabilities"],
            "configuredPoseFrames": row["poseFrames"],
            "enhancedPoseFramesAbsentFromAtlas": [n for n in pose_names if n not in names],
            "managedBehaviorsAllowed": allowed, "managedBehaviorsContentSupported": supported,
            "handbookSupportedActionCount": len([kind for kind in supported if kind != "relocate"]),
            "sidePerching": row["contentReview"]["sidePerching"],
        })
    for original in expansion:
        sid = original["id"]
        row, species = support_by_id[sid], by_id[sid]
        require(original["name"] == species["name"], f"Catalog name drift: {sid}")
        require(original["action"] == motions[sid]["action"], f"Motion definition drift: {sid}")
        require(original["family"] == anatomy[sid], f"Renderer family drift: {sid}")
        names = manifest["speciesFrames"].get(sid, manifest["frames"])
        native_size = manifest["frameSizes"][sid]
        frames = decoder.atlas_frames(read(f"shared/art/{sid}.png"), native_size, names)
        require(all(any(pixels[3::4]) for pixels in frames.values()), f"Empty frame: {sid}")
        groups = defaultdict(list)
        for name, pixels in frames.items():
            groups[hashlib.sha256(pixels).hexdigest()].append(name)
        fallback = row["contentReview"]["fallbackFrames"]
        for name, target in fallback.items():
            require(frames[name] == frames[target], f"Fallback metadata/pixels mismatch: {sid}/{name}")
        allowed = [b["kind"] for b in row["behaviors"] if b["productAllowed"]]
        supported = [b["kind"] for b in row["behaviors"] if b["contentSupported"]]
        pilot = sid in E0_IDS
        signature_names = signatures.get(sid, [])
        expected_behaviors = {"relocate"} | (E0_KINDS if pilot else set())
        require(set(allowed) == set(supported) == expected_behaviors,
                f"Unexpected permissions/content support: {sid}; expected {sorted(expected_behaviors)}")
        require(all(not behavior["missingFrames"] for behavior in row["behaviors"]
                    if behavior["contentSupported"]), f"Supported behavior reports missing frames: {sid}")
        require(set(row["capabilities"]) == (E0_CAPABILITIES if pilot else BASE_CAPABILITIES),
                f"Reviewed capabilities differ from E0/base contract: {sid}")
        require(not row["missingPoseFrames"], f"Incomplete configured pose frames: {sid}")
        expected_extra = pose_names + signature_names if pilot else []
        require(len(expected_extra) == (14 if pilot else 0), f"E0 additions changed: {sid}")
        require(len(manifest["frames"]) == baseline_by_id[sid]["frameSlots"] == 34 and
                names[:34] == manifest["frames"] and len(names) == 34 + len(expected_extra) and
                set(names[34:]) == set(expected_extra),
                f"Expected unchanged base prefix plus E0's fourteen appended frames only: {sid}")
        require(row["poseFrames"] == (pose_names if pilot else []), f"Configured pose contract differs: {sid}")
        metadata = manifest.get("poseClips", {}).get(sid, {})
        clips = metadata.get("clips", {})
        expected_clips = E0_KINDS | {"signature.v0", "signature.v1"} if pilot else set()
        require(set(clips) == expected_clips, f"Stale/unexpected pose clip export: {sid}")
        policy = metadata.get("signaturePolicy")
        if pilot:
            anchors = metadata.get("beakAnchors", {})
            require(set(anchors) == set(expected_extra), f"Incomplete E0 pose/signature anchors: {sid}")
            for name, anchor in anchors.items():
                require(len(anchor) == 2 and all(isinstance(v, (int, float)) and math.isfinite(v) and
                                                0 <= v <= 48 for v in anchor),
                        f"Invalid exported anchor: {sid}/{name}")
            require(policy is not None and policy.get("recordsObservation") is False and
                    policy.get("sideOnly") == (sid == "eurasianNuthatch") and policy.get("variants") == 2,
                    f"Incorrect signature policy: {sid}")
            expected_window = (10, 3, 2) if sid == "eurasianNuthatch" else tuple(
                motions[sid][key] for key in ("cycleSeconds", "startSeconds", "durationSeconds"))
            require(tuple(policy.get(key) for key in ("cycle", "start", "duration")) == expected_window,
                    f"Signature must reuse its existing idle window: {sid}")
            for kind, clip in clips.items():
                clip_frames = clip["frames"]
                require(clip_frames and clip["maximumLoops"] == 1 and clip["recovery"] == "currentEngineState",
                        f"Unexpected clip lifecycle: {sid}/{kind}")
                required_names = signature_names if kind.startswith("signature.") else pose_names
                require(all(f["name"] in required_names and isinstance(f["duration"], (int, float)) and
                            math.isfinite(f["duration"]) and f["duration"] > 0 and
                            [f["beak"]["x"], f["beak"]["y"]] == anchors[f["name"]] for f in clip_frames),
                        f"Invalid exported clip frames, timing or anchors: {sid}/{kind}")
                if kind.startswith("signature."):
                    require([f["name"] for f in clip_frames] == signature_names and
                            math.isclose(sum(f["duration"] for f in clip_frames), policy["duration"], abs_tol=1e-9),
                            f"Signature sequence/window mismatch: {sid}/{kind}")
            require([f["duration"] for f in clips["signature.v0"]["frames"]] !=
                    [f["duration"] for f in clips["signature.v1"]["frames"]],
                    f"Signature variants must have distinct cadence: {sid}")
        else:
            require(policy is None, f"Non-pilot unexpectedly exports signature policy: {sid}")
        gallery_route = ("signatureSide" if sid == "eurasianNuthatch" else "signature") if pilot else "idle"
        measurements.append({
            "id": sid, "name": species["name"], "scientificName": species["scientificName"],
            "rendererFamily": anatomy[sid], "motion": motions[sid],
            "galleryOtherRoute": gallery_route,
            "historicalGalleryOtherRoute": baseline_by_id[sid]["galleryOtherRoute"],
            "cohort": row["contentReview"]["cohort"], "isE0Pilot": pilot,
            "frameSlots": len(names), "nativeFrameSize": native_size,
            "addedFrameSlotsSinceBaseline": len(names) - baseline_by_id[sid]["frameSlots"],
            "signatureFrames": signature_names,
            "signaturePolicy": policy,
            "addedFramesDistinctImages": len({frames[name] for name in expected_extra}),
            "addedFramesIdenticalToBase": {
                name: [base for base in manifest["frames"] if frames[name] == frames[base]]
                for name in expected_extra if any(frames[name] == frames[base] for base in manifest["frames"])
            },
            "atlasRGBABytes": len(names) * native_size * native_size * 4,
            "distinctImagesWithinSpecies": len(groups),
            "duplicateSlotExcess": len(names) - len(groups),
            "pixelIdenticalGroups": [group for group in groups.values() if len(group) > 1],
            "idleDistinctImages": len({frames[f"idle{i}"] for i in range(3)}),
            "preenDistinctImages": len({frames[f"preen{i}"] for i in range(2)}),
            "flightDistinctImages": len({frames[f"fly{i}"] for i in range(8)}),
            "landingDistinctImages": len({frames[f"land{i}"] for i in range(3)}),
            "explicitFallbacks": fallback,
            "enhancedPoseFramesMissing": [name for name in pose_names if name not in frames],
            "exportedPoseClipNames": sorted(clips),
            "managedBehaviorsAllowed": allowed, "managedBehaviorsContentSupported": supported,
            "handbookSupportedActionCount": len([kind for kind in supported if kind != "relocate"]),
            "managedBehaviorReviewPending": row["contentReview"]["managedBehaviorReviewPending"],
            "sidePerching": row["contentReview"]["sidePerching"],
            "existingAppearanceNotes": species.get("appearanceNotes"),
            "existingReferenceURL": original.get("referenceURL"),
            "referenceStatus": "recorded_not_reverified" if original.get("referenceURL") else "no_per_species_url_in_expansion_spec",
            "visualAcceptance": "not_performed_by_this_audit",
            "runtimeAcceptance": "not_performed_by_this_audit",
            "naturalHistoryActionEvidence": "not_reviewed_by_this_audit",
        })

    summary = {
        "catalogSpecies": len(matrix), "expansionSpecies": len(measurements),
        "e0PilotSpecies": sum(r["isE0Pilot"] for r in measurements),
        "remainingBaseExpansionSpecies": sum(not r["isE0Pilot"] for r in measurements),
        "expansionAddedFrameSlotsSinceBaseline": sum(r["addedFrameSlotsSinceBaseline"] for r in measurements),
        "expansionSignatureFrameSlots": sum(len(r["signatureFrames"]) for r in measurements),
        "handbookSupportedActionCountDistribution": dict(sorted(Counter(
            r["handbookSupportedActionCount"] for r in measurements).items())),
        "catalogFrameSlots": sum(r["frameSlots"] for r in matrix),
        "expansionFrameSlots": sum(r["frameSlots"] for r in measurements),
        "distinctImagesSummedWithinExpansionSpecies": sum(r["distinctImagesWithinSpecies"] for r in measurements),
        "expansionDuplicateSlotExcess": sum(r["duplicateSlotExcess"] for r in measurements),
        "explicitFallbackSlots": sum(len(r["explicitFallbacks"]) for r in measurements),
        "expansionAtlasRGBABytes": sum(r["atlasRGBABytes"] for r in measurements),
        "completeEnhancedPoseSpeciesInCatalog": sum(len(r["configuredPoseFrames"]) == 10 and
                                                     not r["enhancedPoseFramesAbsentFromAtlas"] for r in matrix),
        "missingEnhancedPoseSlotsInExpansion": sum(len(r["enhancedPoseFramesMissing"]) for r in measurements),
        "rendererFamilyCounts": dict(sorted(Counter(r["rendererFamily"] for r in measurements).items())),
        "idleActionCounts": dict(sorted(Counter(r["motion"]["action"] for r in measurements).items())),
        "galleryOtherRouteCounts": dict(sorted(Counter(r["galleryOtherRoute"] for r in measurements).items())),
        "distinctImageCountDistribution": dict(sorted(Counter(r["distinctImagesWithinSpecies"] for r in measurements).items())),
        "existingPerSpeciesReferenceURLs": sum(bool(r["existingReferenceURL"]) for r in measurements),
        "missingPerSpeciesReferenceURLs": [r["id"] for r in measurements if not r["existingReferenceURL"]],
    }
    return {
        "schemaVersion": 2, "scope": "M8a/E0 catalog; pixel audit of six E0 pilots and 48 base expansion species",
        "historicalBaseline": {"path": BASELINE_PATH, "schemaVersion": baseline["schemaVersion"],
                               "sha256": inputs[BASELINE_PATH]},
        "method": "Source configuration and exported atlas RGBA; transparent RGB normalized by existing U2 decoder",
        "limitations": ["Distinct pixels are not distinct behaviors or quality approval",
                        "Renderer families are implementation groups, not taxonomic families",
                        "Gallery route is inferred from source, not an executed UI test",
                        "No runtime/native/natural-history acceptance; URLs are inventory only",
                        "RGBA bytes exclude masks, allocation overhead and app memory"],
        "inputSHA256": dict(sorted(inputs.items())), "summary": summary,
        "catalogMatrix": matrix, "expansion": measurements,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path,
                        help="New report path (recommended: docs/evidence/e0-capability-audit-20261026.json); omit for stdout")
    args = parser.parse_args()
    try:
        if args.output:
            baseline_path = args.root / BASELINE_PATH
            if args.output.resolve() == baseline_path.resolve() or (
                    args.output.exists() and baseline_path.exists() and args.output.samefile(baseline_path)):
                raise ValueError("Refusing to overwrite the historical baseline; use e0-capability-audit-20261026.json")
        report = audit(args.root)
    except (OSError, ValueError, KeyError, IndexError, TypeError) as error:
        print(f"Inventory failed: {error}", file=sys.stderr)
        return 1
    result = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(result)
        print(json.dumps(report["summary"], ensure_ascii=False))
    else:
        print(result, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
