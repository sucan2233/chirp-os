#!/usr/bin/env python3
"""Protect the separately compiled desktop timelines and atlas contract from drift."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
swift = (ROOT / 'platforms/macos/Sources/BirdingCore/SpeciesBehavior.swift').read_text()
csharp = (ROOT / 'platforms/windows/ChirpOS.Core/SpeciesBehavior.cs').read_text()
source = json.loads((ROOT / 'platforms/macos/Sources/BirdingCore/Resources/species.json').read_text())
shared = json.loads((ROOT / 'shared/species.json').read_text())
assert source == shared, 'Shared catalog is stale'
ids = {bird['id'] for bird in source['species']}
swift_rows = re.findall(r'case \.(\w+): return Motion\(action: \.(\w+), cycle: ([\d.]+), start: ([\d.]+), duration: ([\d.]+), rate: ([\d.]+), hop: ([\d.]+)\)', swift)
cs_rows = re.findall(r'"(\w+)" => new\("(\w+)", ([\d.]+), ([\d.]+), ([\d.]+), ([\d.]+), ([\d.]+)\)', csharp)
def normalized(rows):
    return {row[0]: (row[1], *map(float, row[2:])) for row in rows}
assert set(normalized(swift_rows)) == ids, 'Missing Swift species schedule'
assert normalized(swift_rows) == normalized(cs_rows), 'Windows schedule differs from macOS'
manifest = json.loads((ROOT / 'shared/art/manifest.json').read_text())
art_source = (ROOT / 'platforms/macos/Sources/Birding/PixelArt.swift').read_text()
frames = re.findall(r'"([a-z]+\d*)"', re.search(r'static let names = \[(.*?)\]', art_source).group(1))
assert manifest['frames'] == frames, 'Atlas frame order is stale'
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
             'swinhoesWhiteEye', 'azureWingedMagpie', 'redBilledLeiothrix', 'littleOwl'):
    expected_extras[bird] = expected_extras.get(bird, []) + pose_frames
for bird in ('lightVentedBulbul', 'magpieRobin'):
    expected_extras[bird] = expected_extras[bird] + ['peekLower', 'peekLook', 'peekRecover']
for bird in ('treeSparrow', 'lightVentedBulbul'):
    expected_extras[bird] += ['bathInspect', 'bathTouch', 'bathLower', 'bath0', 'bath1', 'bath2', 'bathRise']
carry_frames = ['carryLook', 'carryLower', 'carryGrip', 'carryPlace']
for bird in ('treeSparrow', 'azureWingedMagpie'):
    expected_extras[bird] += carry_frames
expected_extras['barnSwallow'] += ['catchOpen', 'catchClose', 'catchRecover']
expected_extras['yellowRumpedFlycatcher'] = ['catchOpen', 'catchClose', 'catchRecover']
courtship_frames = ['courtRaise', 'courtBow0', 'courtBow1', 'courtBowRecover', 'courtObserve']
expected_extras['spottedDove'] += courtship_frames
assert set(specific) == set(expected_extras), 'Optional poses advertised for the wrong species'
for bird, names in specific.items():
    assert names == frames + expected_extras[bird], f'Invalid species frame order: {bird}'

support = json.loads((ROOT / 'shared/species-support.json').read_text())
assert {row['species'] for row in support} == ids, 'Missing species support audit'
for row in support:
    assert not row['missingPoseFrames'], f"Incomplete enhanced pose pack: {row['species']}"
    assert set(row['poseFrames']).issubset(specific.get(row['species'], frames)), 'Support audit differs from atlas'
flycatcher = next(row for row in support if row['species'] == 'yellowRumpedFlycatcher')
assert flycatcher['poseFrames'] == [], 'Catch-only flycatcher was added to the base pose pack'
assert len(specific['yellowRumpedFlycatcher']) == 37, 'Flycatcher must append exactly three frames after the common 34'
metadata = manifest['poseClips']
assert set(metadata) == set(expected_extras), 'Pose/catch metadata omits a delivered species or expands scope'
assert set(metadata['yellowRumpedFlycatcher']['clips']) == {'insectCatchRecovery'}, 'Flycatcher exported unprovided clips'
transport_frames = [f'fly{i}' for i in range(8)] + [f'land{i}' for i in range(3)] + [f'glide{i}' for i in range(3)] + [f'bank{i}' for i in range(3)] + ['bound', 'stand']
for bird in ('barnSwallow', 'yellowRumpedFlycatcher'):
    assert set(metadata[bird]['transportBeakAnchors']) == set(transport_frames + expected_extras['yellowRumpedFlycatcher']), f'Incomplete catch beak geometry: {bird}'
for bird in ('treeSparrow', 'azureWingedMagpie'):
    assert set(metadata[bird]['transportBeakAnchors']) == set(transport_frames + carry_frames), f'Incomplete carry beak geometry: {bird}'
magpie = metadata['azureWingedMagpie']
assert len(specific['azureWingedMagpie']) == 48, 'Magpie must append only four carry frames after its historical 44'
assert set(magpie['clips']) == {'watch', 'alert', 'rest', 'takeoffPreparation', 'visitorGiftPickup', 'visitorGiftRelease'}, 'Gift clips changed unrelated magpie capability'
pickup = magpie['clips']['visitorGiftPickup']
release = magpie['clips']['visitorGiftRelease']
assert [frame['name'] for frame in pickup['frames']] == ['carryLook', 'carryLower', 'carryGrip', 'carryLook']
assert [frame['duration'] for frame in pickup['frames']] == [0.4, 0.3, 0.2, 0.3]
assert [frame['name'] for frame in release['frames']] == ['carryPlace'] and release['frames'][0]['duration'] == 0.3
for frame, expected in (('carryGrip', [40, 39]), ('carryPlace', [42, 23])):
    anchor = magpie['transportBeakAnchors'][frame]
    assert len(anchor) == 2 and all(abs(a - b) < 1e-9 for a, b in zip(anchor, expected)), f'Wrong magpie contact anchor: {frame}'

dove = metadata['spottedDove']
assert len(specific['spottedDove']) == 53 and specific['spottedDove'][48:] == courtship_frames, 'Dove courtship must follow its unchanged historical 48'
assert set(dove['clips']) == {'watch', 'alert', 'rest', 'takeoffPreparation', 'courtshipInitiator', 'courtshipObserver'}
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
assert all((ROOT / 'shared/art' / f'{id}.png').is_file() for id in ids)
print(f'PASS: {len(ids)} matching species schedules and {len(frames)} shared frame names')

flight_swift = (ROOT / 'platforms/macos/Sources/BirdingCore/FlightBehavior.swift').read_text()
flight_cs = (ROOT / 'platforms/windows/ChirpOS.Core/FlightBehavior.cs').read_text()
swift_flights = re.findall(r'case \.(\w+): return Motion\(style: \.(\w+), transit: ([\d.]+), cycle: ([\d.]+), powered: ([\d.]+), rate: ([\d.]+), wave: ([\d.]+), orbit: ([\d.]+), period: ([\d.]+)\)', flight_swift)
cs_flights = re.findall(r'"(\w+)" => new\("(\w+)", ([\d.]+), ([\d.]+), ([\d.]+), ([\d.]+), ([\d.]+), ([\d.]+), ([\d.]+)\)', flight_cs)
assert set(normalized(swift_flights)) == ids, 'Missing explicit flight profile'
assert normalized(swift_flights) == normalized(cs_flights), 'Flight timing differs between platforms'
print(f'PASS: {len(ids)} matching flight profiles')
