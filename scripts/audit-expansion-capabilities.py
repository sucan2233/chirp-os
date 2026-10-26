#!/usr/bin/env python3
"""Read-only inventory of the 54 expansion species and the full catalog.

Uses exported PNG pixels, manifests and current Swift configuration. This is
not a runtime, visual-quality or natural-history acceptance test. Outputs a
deterministic JSON report; no build, export, app launch or user data access.

python3 scripts/audit-expansion-capabilities.py --output /tmp/expansion-audit.json
"""
import argparse
from collections import Counter, defaultdict
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import sys

sys.dont_write_bytecode = True


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
    catalog = document("shared/species.json")["species"]
    support = document("shared/species-support.json")
    expansion = document("docs/species-expansion-100.json")["species"]
    motion_source = read("platforms/macos/Sources/BirdingCore/SpeciesBehavior.swift").decode()
    gallery_source = read("platforms/macos/Sources/BirdingCore/GalleryPose.swift").decode()
    pose_source = read("platforms/macos/Sources/BirdingCore/Behavior/PoseClip.swift").decode()
    art_source = read("platforms/macos/Sources/Birding/ExpansionBirdArt.swift").decode()
    # Capture provenance for permission, completion and handbook interpretations.
    for path in (
        "platforms/macos/Sources/BirdingCore/Behavior/SpeciesBehaviorProfile.swift",
        "platforms/macos/Sources/BirdingCore/Behavior/BehaviorEngine.swift",
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
    require(len(by_id) == len(catalog) == len(support_by_id) == len(support) == 100,
            "Expected 100 unique catalog/support rows; review audit scope after catalog changes")
    require(set(by_id) == set(support_by_id) == set(manifest["frameSizes"]),
            "Catalog/support/native frame-size IDs differ")
    require(len(expansion) == len(new_ids) == 54, "Expected 54 unique expansion IDs")
    require(new_ids == {sid for sid, row in support_by_id.items()
                        if row["contentReview"]["cohort"] == "upstream-v0.7-base"},
            "Expansion specification and support cohorts differ")

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
    gallery_match = re.search(
        r"switch SpeciesBehavior\.motion\(id\)\.action\s*\{\s*case ([^:]+):", gallery_source)
    require(gallery_match is not None, "Gallery action switch changed")
    gallery_idle_actions = set(re.findall(r"\.(\w+)", gallery_match[1]))
    require('if id == .eurasianNuthatch { return' in gallery_source,
            "Re-evaluate nuthatch gallery special case")
    anatomy = {sid: family for sid, family in re.findall(r'\.(\w+): Anatomy\("([^"]+)"', art_source)}
    require(set(anatomy) == new_ids, "Expansion renderer profiles differ from scope")

    matrix, measurements = [], []
    for species in catalog:
        sid = species["id"]
        row = support_by_id[sid]
        names = manifest["speciesFrames"].get(sid, manifest["frames"])
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
        require(allowed == supported == ["relocate"], f"Expansion permissions changed: {sid}; re-plan scope")
        require(not row["poseFrames"] and not any(n in frames for n in pose_names),
                f"Enhanced expansion poses added: {sid}; re-plan gaps")
        action = motions[sid]["action"]
        gallery_route = ("sidePerch" if sid == "eurasianNuthatch" else
                         "idle" if action in gallery_idle_actions else "restingFallback")
        measurements.append({
            "id": sid, "name": species["name"], "scientificName": species["scientificName"],
            "rendererFamily": anatomy[sid], "motion": motions[sid],
            "galleryOtherRoute": gallery_route,
            "frameSlots": len(names), "nativeFrameSize": native_size,
            "atlasRGBABytes": len(names) * native_size * native_size * 4,
            "distinctImagesWithinSpecies": len(groups),
            "duplicateSlotExcess": len(names) - len(groups),
            "pixelIdenticalGroups": [group for group in groups.values() if len(group) > 1],
            "idleDistinctImages": len({frames[f"idle{i}"] for i in range(3)}),
            "preenDistinctImages": len({frames[f"preen{i}"] for i in range(2)}),
            "flightDistinctImages": len({frames[f"fly{i}"] for i in range(8)}),
            "landingDistinctImages": len({frames[f"land{i}"] for i in range(3)}),
            "explicitFallbacks": fallback,
            "enhancedPoseFramesMissing": pose_names,
            "exportedPoseClipNames": sorted(manifest.get("poseClips", {}).get(sid, {}).get("clips", {})),
            "managedBehaviorsAllowed": allowed, "managedBehaviorsContentSupported": supported,
            "handbookSupportedActionCount": 0,
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
        "schemaVersion": 1, "scope": "U-integrated 100-species catalog, pixel audit focused on 54 additions",
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
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        report = audit(args.root)
    except (OSError, ValueError, KeyError, IndexError) as error:
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
