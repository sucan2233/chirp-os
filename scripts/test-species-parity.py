#!/usr/bin/env python3
"""Protect macOS species coverage and exported resource contracts from drift."""
import json
import importlib.util
import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
# Import definitions only; the pixel audit remains a separate explicit command.
audit_spec = importlib.util.spec_from_file_location('chirp_m8_contract', ROOT / 'scripts/audit-m8-art.py')
m8 = importlib.util.module_from_spec(audit_spec)
previous_bytecode = sys.dont_write_bytecode
try:
    sys.dont_write_bytecode = True
    audit_spec.loader.exec_module(m8)
finally:
    sys.dont_write_bytecode = previous_bytecode
contract, frozen_signatures, m8_appended, m8_delivered, m8_membership = m8.load_contract(ROOT / 'scripts/m8-art-contract.json')
expansion_spec = importlib.util.spec_from_file_location('chirp_expansion_contract', ROOT / 'scripts/audit-expansion-art.py')
expansion_audit = importlib.util.module_from_spec(expansion_spec)
previous_bytecode = sys.dont_write_bytecode
try:
    sys.dont_write_bytecode = True
    expansion_spec.loader.exec_module(expansion_audit)
finally:
    sys.dont_write_bytecode = previous_bytecode
expansion_contract, all_signatures, expansion_appended, _, _ = expansion_audit.load_contract(ROOT / 'scripts/expansion-art-contract.json')

swift = (ROOT / 'platforms/macos/Sources/BirdingCore/SpeciesBehavior.swift').read_text()
source = json.loads((ROOT / 'platforms/macos/Sources/BirdingCore/Resources/species.json').read_text())
shared = json.loads((ROOT / 'shared/species.json').read_text())
assert source == shared, 'Shared catalog is stale'
weight_research = json.loads((ROOT / 'docs/research/species-weights-v2.json').read_text())
expected_weights = {bird['id']: bird['proposedWeight'] for bird in weight_research['species']}
assert {bird['id']: bird['weight'] for bird in source['species']} == expected_weights, 'Runtime defaults differ from researched preset'
assert sum(expected_weights.values()) == 5358 and all(w > 0 for w in expected_weights.values()), 'Every bird must have a positive default'
ids = {bird['id'] for bird in source['species']}
assert len(source['species']) == len(ids) == 100, 'U catalog must contain 100 unique species'
swift_rows = re.findall(r'case \.(\w+): return Motion\(action: \.(\w+), cycle: ([\d.]+), start: ([\d.]+), duration: ([\d.]+), rate: ([\d.]+), hop: ([\d.]+)\)', swift)
def normalized(rows):
    return {row[0]: (row[1], *map(float, row[2:])) for row in rows}
assert len(swift_rows) == len(ids) and set(normalized(swift_rows)) == ids, 'Missing or duplicate macOS species schedule'
assert all(math.isfinite(float(value)) and float(value) >= 0 for row in swift_rows for value in row[2:]), 'Invalid species timing'
manifest = json.loads((ROOT / 'shared/art/manifest.json').read_text())
art_source = (ROOT / 'platforms/macos/Sources/Birding/PixelArt.swift').read_text()
frames = re.findall(r'"([a-z]+\d*)"', re.search(r'static let names = \[(.*?)\]', art_source).group(1))
assert len(frames) == 34 and manifest['frames'] == frames, 'Atlas common frame order is stale'
assert set(manifest['frameSizes']) == ids, 'Missing species in atlas manifest'
# Optional species atlases append contact poses without moving common indices.
contact_frames = [f'allopreen{role}{i}' for role in ('Give', 'Receive') for i in range(3)]
specific = manifest.get('speciesFrames', {})
feeding_frames = ['feedLook', 'feedDown0', 'feedDown1', 'feedLift']
expected_extras = {'barnSwallow': contact_frames, 'swinhoesWhiteEye': contact_frames,
                   'treeSparrow': feeding_frames, 'spottedDove': feeding_frames}
pose_frames = ['lookNear', 'lookFar', 'alertRise', 'alertHold', 'alertRelax', 'restLower', 'restTuck', 'restWake', 'takeoffCrouch', 'takeoffPush']
for bird in ('treeSparrow', 'spottedDove', 'barnSwallow', 'nightHeron',
             'lightVentedBulbul', 'redWhiskeredBulbul', 'chineseBlackbird', 'magpieRobin',
             'swinhoesWhiteEye', 'azureWingedMagpie', 'redBilledLeiothrix', 'littleOwl',
             'greatTit', 'orientalMagpie', 'greatSpottedWoodpecker', 'mallard', 'littleEgret',
             'eurasianGreatTit', 'whiteWagtail', 'indianWhiteEye', 'crestedMyna', 'eurasianNuthatch', 'greatEgret'):
    expected_extras[bird] = expected_extras.get(bird, []) + pose_frames
for bird in ('lightVentedBulbul', 'magpieRobin'):
    expected_extras[bird] = expected_extras[bird] + ['peekLower', 'peekLook', 'peekRecover']
for bird in ('treeSparrow', 'lightVentedBulbul'):
    expected_extras[bird] += ['bathInspect', 'bathTouch', 'bathLower', 'bath0', 'bath1', 'bath2', 'bathRise']
carry_frames = ['carryLook', 'carryLower', 'carryGrip', 'carryPlace']
for bird in ('treeSparrow', 'azureWingedMagpie'):
    expected_extras[bird] += carry_frames
catch_frames = ['catchOpen', 'catchClose', 'catchRecover']
expected_extras['barnSwallow'] += catch_frames
expected_extras['yellowRumpedFlycatcher'] = catch_frames.copy()
courtship_frames = ['courtRaise', 'courtBow0', 'courtBow1', 'courtBowRecover', 'courtObserve']
expected_extras['spottedDove'] += courtship_frames
nest_build_frames = ['nestPlace', 'nestAdjust0', 'nestAdjust1', 'nestSettle']
expected_extras['spottedDove'] += carry_frames + nest_build_frames
signature_frames = {
    'greatTit': ['inspectLean', 'inspectDown', 'inspectLift', 'inspectSettle'],
    'orientalMagpie': ['tailPoise', 'tailBalance', 'tailCounter', 'tailSettle'],
    'greatSpottedWoodpecker': ['sideBrace', 'sideDraw', 'sideTap', 'sideRecover'],
    'mallard': ['wingLook', 'wingReach', 'wingSmooth', 'wingRecover'],
    'littleEgret': ['neckPoise', 'neckReach', 'neckObserve', 'neckRecover'],
    'magpieRobin': ['tailReady', 'tailLift', 'tailPulse', 'tailRecover'],
    'eurasianGreatTit': ['inspectLean', 'inspectDown', 'inspectLift', 'inspectSettle'],
    'whiteWagtail': ['tailPoise', 'tailLift', 'tailFall', 'tailSettle'],
    'indianWhiteEye': ['gleanReady', 'gleanReach', 'gleanRecoil', 'gleanSettle'],
    'crestedMyna': ['peckReady', 'peckLower', 'peckLift', 'peckSettle'],
    'eurasianNuthatch': ['sideBrace', 'sideReach', 'sideProbe', 'sideRecover'],
    'greatEgret': ['neckPoise', 'neckReach', 'neckObserve', 'neckRecover'],
}
for bird, names in signature_frames.items():
    assert names == frozen_signatures[bird], f'Pilot signature contract changed: {bird}'
    expected_extras[bird] += names
# Preserve the entire f06448f layout before appending M8b-f. In particular the
# flycatcher's catch frames are already at 34..36, before its new base pack.
baseline_extras = {bird: names.copy() for bird, names in expected_extras.items()}
assert sum(len(names) for names in baseline_extras.values()) == 345
for bird, names in m8_appended.items():
    expected_extras[bird] = expected_extras.get(bird, []) + names
for bird, names in expansion_appended.items():
    expected_extras[bird] = expected_extras.get(bird, []) + names
signature_frames = all_signatures
assert len(signature_frames) == len(expected_extras) == 100
assert len(expansion_appended) == 48 and sum(map(len, expansion_appended.values())) == 672
assert len(m8_appended) == 40 and sum(map(len, m8_appended.values())) == 450
assert set(specific) == set(expected_extras), 'Optional poses advertised for the wrong species'
for bird, names in specific.items():
    assert names == frames + expected_extras[bird], f'Invalid species frame order: {bird}'
    assert len(names) == len(set(names)), f'Duplicate frame names: {bird}'
    old_names = frames + baseline_extras.get(bird, [])
    assert names[:len(old_names)] == old_names, f'Historical frame indices moved: {bird}'
for batch, budget in m8.BATCH_BUDGETS.items():
    delivered_count = sum(len(names) for bird, names in m8_delivered.items() if m8_membership[bird] == batch)
    assert delivered_count == budget, f'{batch} delivery budget differs'
    appended_count = sum(len(specific[bird]) - len(frames) - len(baseline_extras.get(bird, []))
                         for bird in contract['batches'][batch]['signatures'])
    assert appended_count == (budget if batch in m8.CURRENT_BATCHES else 0), f'{batch} append budget differs'

assert sum(len(names) - len(frames) for names in specific.values()) == 1467, 'Local appended poses were lost or expanded'
assert sum(len(specific.get(bird, frames)) for bird in ids) == 4867, 'Complete M8/E0-E5 atlas frame-slot budget differs'
assert sum(len(names) for bird, names in m8_delivered.items() if m8_membership[bird] != 'E0') == 524
assert sum(len(names) for bird, names in m8_delivered.items() if m8_membership[bird] == 'E0') == 84

support = json.loads((ROOT / 'shared/species-support.json').read_text())
assert len(support) == 100 and {row['species'] for row in support} == ids, 'Missing or duplicate species support audit'
for row in support:
    assert not row['missingPoseFrames'], f"Incomplete enhanced pose pack: {row['species']}"
    assert set(row['poseFrames']).issubset(specific.get(row['species'], frames)), 'Support audit differs from atlas'
    assert row['poseFrames'] == (pose_frames if row['species'] in signature_frames else []), 'Base pose support scope differs'
flycatcher = next(row for row in support if row['species'] == 'yellowRumpedFlycatcher')
assert flycatcher['poseFrames'] == pose_frames, 'Flycatcher base pack missing'
assert specific['yellowRumpedFlycatcher'][34:37] == catch_frames, 'Flycatcher historical catch indices moved'
assert specific['yellowRumpedFlycatcher'][37:47] == pose_frames, 'Flycatcher base pack must follow catch'
assert len(specific['yellowRumpedFlycatcher']) == 51, 'Flycatcher must append 10 base and 4 signature frames'
metadata = manifest['poseClips']
assert set(metadata) == set(expected_extras), 'Pose/catch metadata omits a delivered species or expands scope'
assert sum(bool(row['poseFrames']) for row in support) == 100
for bird, names in signature_frames.items():
    clips = metadata[bird]['clips']
    assert {key for key in clips if key.startswith('signature.')} == {'signature.v0', 'signature.v1'}
    policy = metadata[bird]['signaturePolicy']
    assert policy['variants'] == 2 and policy['recordsObservation'] is False
    assert policy['sideOnly'] is (bird in ('greatSpottedWoodpecker', 'eurasianNuthatch'))
    assert all(m8.finite_positive(policy[key]) for key in ('cycle', 'start', 'duration'))
    assert policy['start'] + policy['duration'] <= policy['cycle']
    historical_window=expansion_contract['signatureWindows'][bird]
    assert all(math.isclose(policy[k],v,rel_tol=0,abs_tol=1e-9) for k,v in historical_window.items())
    actual_window=(10,3,2) if bird == 'eurasianNuthatch' else normalized(swift_rows)[bird][1:4]
    assert tuple(historical_window[k] for k in ('cycle','start','duration')) == actual_window
    for kind, sequence in m8.BASE_CLIPS.items():
        clip = clips[kind]
        assert [f['name'] for f in clip['frames']] == sequence, f'Incomplete base clip: {bird}/{kind}'
        assert clip['foot'] == {'x': 29, 'y': 39} and clip['maximumLoops'] == 1
        assert clip['recovery'] == 'currentEngineState'
        times=expansion_contract['baseClipDurations'][kind]
        assert len(clip['frames'])==len(times) and all(math.isclose(f['duration'],t,rel_tol=0,abs_tol=1e-9)
                                                     for f,t in zip(clip['frames'],times))
    for variant, weights in enumerate(([0.20, 0.30, 0.22, 0.28], [0.28, 0.20, 0.32, 0.20])):
        clip = metadata[bird]['clips'][f'signature.v{variant}']
        assert [f['name'] for f in clip['frames']] == names
        assert clip['id'] == f'{bird}.signature.v{variant}'
        assert clip['maximumLoops'] == 1
        assert clip['foot'] == {'x': 29, 'y': 39}
        assert clip['recovery'] == 'currentEngineState'
        assert all(m8.finite_positive(f['duration']) and math.isclose(f['duration'], weight * policy['duration'],
                   rel_tol=0, abs_tol=1e-9) for f, weight in zip(clip['frames'], weights)), f'Wrong cadence: {bird}/v{variant}'
    for key in list(m8.BASE_CLIPS) + ['signature.v0', 'signature.v1']:
        for frame in clips[key]['frames']:
            anchor = metadata[bird]['beakAnchors'][frame['name']]
            assert len(anchor) == 2 and all(math.isfinite(v) and 0 <= v < 48 for v in anchor)
            assert all(abs(frame['beak'][axis] - anchor[index]) < 1e-9
                       for index, axis in enumerate(('x', 'y'))), f'Clip bill drift: {bird}/{key}'

assert set(metadata['yellowRumpedFlycatcher']['clips']) == set(m8.BASE_CLIPS) | {'insectCatchRecovery', 'signature.v0', 'signature.v1'}, 'Flycatcher exported unprovided clips'
transport_frames = [f'fly{i}' for i in range(8)] + [f'land{i}' for i in range(3)] + [f'glide{i}' for i in range(3)] + [f'bank{i}' for i in range(3)] + ['bound', 'stand']
for bird in ('barnSwallow', 'yellowRumpedFlycatcher'):
    assert set(metadata[bird]['transportBeakAnchors']) == set(transport_frames + catch_frames), f'Incomplete or expanded catch beak geometry: {bird}'
for bird in ('treeSparrow', 'azureWingedMagpie'):
    assert set(metadata[bird]['transportBeakAnchors']) == set(transport_frames + carry_frames), f'Incomplete carry beak geometry: {bird}'
magpie = metadata['azureWingedMagpie']
assert len(specific['azureWingedMagpie']) == 52 and specific['azureWingedMagpie'][44:48] == carry_frames, 'Magpie historical carry prefix changed'
assert specific['azureWingedMagpie'][48:] == signature_frames['azureWingedMagpie']
assert set(magpie['clips']) == {'watch', 'alert', 'rest', 'takeoffPreparation', 'visitorGiftPickup', 'visitorGiftRelease', 'signature.v0', 'signature.v1'}, 'Gift clips changed unrelated magpie capability'
pickup = magpie['clips']['visitorGiftPickup']
release = magpie['clips']['visitorGiftRelease']
assert [frame['name'] for frame in pickup['frames']] == ['carryLook', 'carryLower', 'carryGrip', 'carryLook']
assert [frame['duration'] for frame in pickup['frames']] == [0.4, 0.3, 0.2, 0.3]
assert [frame['name'] for frame in release['frames']] == ['carryPlace'] and release['frames'][0]['duration'] == 0.3
for frame, expected in (('carryGrip', [40, 39]), ('carryPlace', [42, 23])):
    anchor = magpie['transportBeakAnchors'][frame]
    assert len(anchor) == 2 and all(abs(a - b) < 1e-9 for a, b in zip(anchor, expected)), f'Wrong magpie contact anchor: {frame}'

dove = metadata['spottedDove']
historical_dove = frames + feeding_frames + pose_frames + courtship_frames
assert len(historical_dove) == 53 and specific['spottedDove'][:53] == historical_dove, 'Dove nesting changed the historical 53 prefix'
assert len(specific['spottedDove']) == 65 and specific['spottedDove'][53:61] == carry_frames + nest_build_frames, 'Dove historical eight nest poses changed'
assert specific['spottedDove'][61:] == signature_frames['spottedDove']
assert specific['spottedDove'][48:53] == courtship_frames, 'Courtship no longer follows the historical 48'
assert set(dove['clips']) == {'watch', 'alert', 'rest', 'takeoffPreparation', 'courtshipInitiator', 'courtshipObserver',
                            'nestMaterialPickup', 'nestMaterialPlace', 'nestBuild', 'signature.v0', 'signature.v1'}
assert set(dove['courtshipBeakAnchors']) == set(courtship_frames + ['stand'])
for frame, expected in zip(courtship_frames, ([39.5, 13], [41, 24], [41.5, 30], [40, 19], [38.5, 16])):
    for key in ('beakAnchors', 'courtshipBeakAnchors'):
        anchor = dove[key][frame]
        assert len(anchor) == 2 and all(abs(a - b) < 1e-9 for a, b in zip(anchor, expected)), f'Wrong courtship bill: {frame}'
initiator = dove['clips']['courtshipInitiator']
observer = dove['clips']['courtshipObserver']
assert [f['name'] for f in initiator['frames']] == ['stand', 'courtRaise'] + ['courtBow0', 'courtBow1', 'courtBowRecover'] * 2 + ['courtBowRecover'] * 2
assert [f['duration'] for f in initiator['frames']] == [0.4, 0.5] + [0.35, 0.4, 0.25] * 2 + [0.5, 0.6]
assert [f['name'] for f in observer['frames']] == ['stand', 'stand', 'stand', 'courtObserve', 'stand']
assert [f['duration'] for f in observer['frames']] == [0.4, 0.5, 2, 0.5, 0.6]
for role, clip in (('initiator', initiator), ('observer', observer)):
    assert clip['id'] == f'spottedDove.courtshipDisplay.{role}' and clip['foot'] == {'x': 29, 'y': 39}
    assert clip['maximumLoops'] == 1 and abs(sum(f['duration'] for f in clip['frames']) - 4) < 1e-9
dove_support = next(row for row in support if row['species'] == 'spottedDove')
courtship = next(row for row in dove_support['behaviors'] if row['kind'] == 'courtshipDisplay')
assert courtship['productAllowed'] and courtship['contentSupported'] and not courtship['missingFrames']
for row in support:
    if row['species'] != 'spottedDove':
        assert not next(b for b in row['behaviors'] if b['kind'] == 'courtshipDisplay')['productAllowed'], 'Courtship scope expanded'

nest_targets = ([40, 19], [40, 31], [40, 39], [40, 39], [40, 26], [40, 39], [41, 39], [40, 39])
assert set(dove['nestBeakAnchors']) == set(carry_frames + nest_build_frames + transport_frames), 'Nest transport or arrange bills incomplete'
for frame, target in zip(carry_frames + nest_build_frames, nest_targets):
    for key in ('nestBeakAnchors', 'beakAnchors'):
        actual = dove[key][frame]
        assert len(actual) == 2 and all(abs(a - b) < 1e-9 for a, b in zip(actual, target)), f'Wrong nest contact: {frame}'
nest_sequences = {
    'nestMaterialPickup': (['carryLook', 'carryLower', 'carryGrip', 'carryLook'], [0.4, 0.3, 0.2, 0.3]),
    'nestMaterialPlace': (['carryPlace', 'carryLook'], [0.4, 0.3]),
    'nestBuild': (['nestPlace', 'nestAdjust0', 'nestAdjust1', 'nestAdjust0', 'nestAdjust1', 'nestSettle', 'nestPlace'],
                  [0.3, 0.3, 0.3, 0.3, 0.3, 0.4, 0.3]),
}
for key, (names, durations) in nest_sequences.items():
    clip = dove['clips'][key]
    assert [f['name'] for f in clip['frames']] == names and [f['duration'] for f in clip['frames']] == durations
    assert clip['foot'] == {'x': 29, 'y': 39} and clip['maximumLoops'] == 1 and clip['recovery'] == 'currentEngineState'
    for frame in clip['frames']:
        assert all(abs(frame['beak'][axis] - dove['nestBeakAnchors'][frame['name']][index]) < 1e-9
                   for index, axis in enumerate(('x', 'y'))), f'Clip bill drift: {key}'
for row in support:
    for kind in ('nestMaterialCarry', 'nestBuild'):
        behavior = next(b for b in row['behaviors'] if b['kind'] == kind)
        allowed = row['species'] == 'spottedDove'
        assert behavior['productAllowed'] == allowed and behavior['contentSupported'] == allowed, 'Nest scope or content differs'
        if allowed:
            assert not behavior['missingFrames']
assert not next(b for b in dove_support['behaviors'] if b['kind'] == 'leafCarry')['productAllowed'], 'Nest art granted ordinary leaf carry'

# Presentation coverage must not silently widen any ecological whitelist.
dedicated_species = {
    'edgePeek': {'treeSparrow', 'chineseBlackbird', 'hoopoe', 'whimbrel', 'lightVentedBulbul', 'magpieRobin'},
    'chase': {'treeSparrow', 'barnSwallow', 'swinhoesWhiteEye', 'lightVentedBulbul', 'azureWingedMagpie', 'blackCollaredStarling', 'redWhiskeredBulbul'},
    'travelTogether': {'treeSparrow', 'barnSwallow', 'spottedDove', 'lightVentedBulbul', 'azureWingedMagpie', 'blackCollaredStarling', 'redWhiskeredBulbul'},
    'allopreening': {'barnSwallow', 'swinhoesWhiteEye'},
    'fixedPerchVisit': {'treeSparrow', 'barnSwallow', 'swinhoesWhiteEye', 'redWhiskeredBulbul', 'magpieRobin', 'redBilledLeiothrix', 'lightVentedBulbul'},
    'foodTrayVisit': {'treeSparrow', 'spottedDove'},
    'bathVisit': {'treeSparrow', 'lightVentedBulbul'},
    'leafCarry': {'treeSparrow'},
    'insectCatch': {'barnSwallow', 'yellowRumpedFlycatcher'},
    'visitorGift': {'azureWingedMagpie'},
    'courtshipDisplay': {'spottedDove'},
    'nestMaterialCarry': {'spottedDove'},
    'nestBuild': {'spottedDove'},
    'flockPass': {'treeSparrow', 'barnSwallow', 'swinhoesWhiteEye', 'lightVentedBulbul', 'azureWingedMagpie', 'mallard', 'blackHeadedGull', 'blackCollaredStarling'},
}
e0_species = set(contract['batches']['E0']['signatures'])
legacy_species = set(frozen_signatures) - e0_species
remaining_expansion = set(expansion_appended)
assert len(legacy_species) == 46 and len(e0_species) == 6 and len(remaining_expansion) == 48
for row in support:
    bird = row['species']
    behaviors = {b['kind']: b for b in row['behaviors']}
    assert len(behaviors) == len(row['behaviors']) and set(dedicated_species) <= set(behaviors)
    for kind, behavior in behaviors.items():
        allowed = (bird in dedicated_species[kind] if kind in dedicated_species else
                   kind == 'relocate' or bird in legacy_species or (bird in (e0_species | remaining_expansion) and kind in m8.BASE_CLIPS))
        assert behavior['productAllowed'] is allowed, f'Ecological permission changed: {bird}/{kind}'
        assert behavior['contentSupported'] is (allowed and not behavior['missingFrames']), f'Content support differs: {bird}/{kind}'
    for kind in m8.BASE_CLIPS:
        required={'stand'} | ({'blink'} if kind in ('watch','rest') else set())
        if kind == 'takeoffPreparation': required |= {f'fly{i}' for i in range(8)}
        if bird in e0_species | remaining_expansion: required |= set(m8.BASE_CLIPS[kind])
        expected_missing=sorted(required-set(specific[bird]))
        assert behaviors[kind]['missingFrames']==expected_missing==[], f'False missing pose frames: {bird}/{kind}'
        assert behaviors[kind]['contentSupported'] is True, f'Foundation behavior unavailable: {bird}/{kind}'
    review = row['contentReview']
    assert review['sidePerching'] is (bird in ('greatSpottedWoodpecker', 'eurasianNuthatch'))
    assert review['managedBehaviorReviewPending'] is (bird not in legacy_species)
    if bird in legacy_species:
        assert review['cohort'] == 'local-46' and review['fallbackFrames'] == {}
    else:
        assert review['cohort'] == ('expansion-e0-partial' if bird in e0_species else 'expansion-e1-e5-partial')
        fallbacks = ['stretch', 'shake', 'poop0', 'poop1'] + ([] if bird == 'eurasianNuthatch' else ['cling0', 'cling1', 'peck0', 'peck1'])
        assert review['fallbackFrames'] == dict.fromkeys(fallbacks, 'stand')
        capabilities = {'standing', 'blinking', 'flight', 'landing'}
        if bird in e0_species | remaining_expansion:
            capabilities |= {'observationPose', 'alertPose', 'restPose', 'takeoffPose'}
        assert set(row['capabilities']) == capabilities, f'Expansion capability scope changed: {bird}'

recording_source = (ROOT / 'platforms/macos/Sources/BirdingCore/Behavior/BehaviorRecording.swift').read_text()
version_match = re.search(r'\bengineVersion\s*=\s*(\d+)', recording_source)
assert version_match and int(version_match.group(1)) == 23, 'Probability V2 simulation version must be 23; fixtures must be re-exported from source'

prop_manifest = json.loads((ROOT / 'shared/art/props/manifest.json').read_text())
leaf = prop_manifest['leafToken']
assert leaf['file'] == 'leafToken.png' and leaf['logicalSize'] == [16, 16], 'Gift must reuse the existing leaf'
assert leaf['gripAnchor'] == [3, 12] and leaf['surfaceAnchor'] == [10, 12] and leaf['scale'] == 'worldScale', 'Leaf scale or support contract changed'
assert leaf['giftLifetime'] == 120 and leaf['giftReceiverAnchor'] == 'resolvedFixedPerch.foot' and leaf['giftCarrierMayLand'] is False
assert leaf['giftReleaseBeak'] == [42, 23], 'Aerial release metadata differs from the actual bill'
insect = prop_manifest.get('insect', {})
assert insect.get('files') == [f'insect{i}.png' for i in range(4)], 'Missing four insect phases'
assert insect.get('logicalSize') == [16, 16] and insect.get('anchor') == [8, 8], 'Insect pivot/size differs from core'
assert insect.get('collisionRadius') == 3 and insect.get('scale') == 'worldScale', 'Insect collision/scale differs'
assert abs(insect.get('frameDuration', 0) - 1 / 12) < 1e-12, 'Insect phase timing differs'
assert insect.get('lifetime') == 12 and insect.get('maximumInstances') == 1, 'Insect lifetime/capacity differs'
assert all((ROOT / 'shared/art/props' / name).is_file() for name in insect['files'])
twig = prop_manifest['twigToken']
assert twig['file'] == 'twigToken.png' and twig['logicalSize'] == [16, 16]
assert twig['gripAnchor'] == [3, 12] and twig['surfaceAnchor'] == [8, 12] and twig['scale'] == 'worldScale'
assert twig['contactRotation'] == 0 and twig['maximumInkY'] == 12
polygon = twig['polygon']
assert min(p[0] for p in polygon) == 0 and max(p[0] for p in polygon) == 16 and max(p[1] for p in polygon) == 12
assert sorted(map(tuple, polygon)) == sorted((16 - x, y) for x, y in polygon), 'Twig grips are not silhouette-symmetric'
nest = prop_manifest['nestPlatform']
tray = prop_manifest['nestMaterialTray']
progress = prop_manifest['nestProgress']
assert nest['logicalSize'] == [144, 48] and nest['contactAnchor'] == [72, 24] and nest['contactY'] == 24
assert nest['materialPoints'] == [[60, 24], [72, 24], [84, 24]] and nest['maximumVisitors'] == 1
assert nest['initialMaterials'] == 3 and nest['lifetime'] == 900
assert tray['logicalSize'] == [32, 16] and tray['contactAnchor'] == [16, 12] and tray['contactY'] == 12
assert tray['materialPoints'] == [[8, 12], [16, 12], [24, 12]] and tray['bakedMaterials'] == 0
assert tray['horizontalOffset'] == 120 and tray['placementOrder'] == ['left', 'right']
assert progress['files'] == ['nestOverlay1.png', 'nestOverlay2.png', 'nestOverlay3.png'] and progress['zeroUsesBase'] is True
assert progress['logicalSize'] == [144, 48] and progress['contactY'] == 24 and progress['looseTwigsBaked'] is False
expected_props = {'bathBasin.png', 'leafToken.png', 'twigToken.png', 'nestPlatform.png', 'nestMaterialTray.png'}
expected_props.update(f'splash{i}.png' for i in range(4))
expected_props.update(insect['files'])
expected_props.update(progress['files'])
assert len(expected_props) == 16 and {p.name for p in (ROOT / 'shared/art/props').glob('*.png')} == expected_props, 'Prop asset budget differs'
assert all((ROOT / 'shared/art' / f'{id}.png').is_file() for id in ids)
print(f'PASS: {len(ids)} macOS species schedules and {len(frames)} shared frame names')

flight_swift = (ROOT / 'platforms/macos/Sources/BirdingCore/FlightBehavior.swift').read_text()
swift_flights = re.findall(r'case \.(\w+): return Motion\(style: \.(\w+), transit: ([\d.]+), cycle: ([\d.]+), powered: ([\d.]+), rate: ([\d.]+), wave: ([\d.]+), orbit: ([\d.]+), period: ([\d.]+)\)', flight_swift)
assert len(swift_flights) == len(ids) and set(normalized(swift_flights)) == ids, 'Missing or duplicate macOS flight profile'
assert all(math.isfinite(float(value)) and float(value) >= 0 for row in swift_flights for value in row[2:]), 'Invalid flight timing'
print(f'PASS: {len(ids)} macOS flight profiles')
