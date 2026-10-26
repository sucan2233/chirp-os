#!/usr/bin/env python3
"""Publish verified Pro assets, or finish an intact failed draft, using its release ID."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time


REPOSITORY = 'sucan2233/chirp-os'


def api(path, method='GET', payload=None):
    args = ['gh', 'api', '--method', method, path]
    if payload is not None:
        args += ['--input', '-']
    result = subprocess.run(args, input=json.dumps(payload) if payload is not None else None,
                            text=True, capture_output=True, check=True)
    return json.loads(result.stdout)


def manifest(folder, tag, source, arch):
    version = tag.removeprefix('pro-v')
    stem = f'ChirpOS-Pro-{version}-macOS-{arch}'
    names = {stem + suffix for suffix in ['.zip', '.zip.sig', '.dmg']}
    names.update(['SHA256SUMS.txt', 'BUILD-INFO.txt', '安装说明.txt'])
    if {p.name for p in folder.iterdir()} != names:
        raise ValueError('Release folder must contain exactly the six expected assets')
    expected = {}
    for name in sorted(names):
        path = folder / name
        if path.is_symlink() or not path.is_file() or path.stat().st_size == 0:
            raise ValueError(f'Invalid release asset: {name}')
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        expected[name] = {'size': path.stat().st_size, 'digest': 'sha256:' + digest}
    sums = {}
    for line in (folder / 'SHA256SUMS.txt').read_text().splitlines():
        match = re.fullmatch(r'([0-9a-f]{64}) [ *](.+)', line)
        if not match or match[2] in sums:
            raise ValueError('Invalid or duplicate checksum entry')
        sums[match[2]] = match[1]
    if set(sums) != {stem + suffix for suffix in ['.zip', '.zip.sig', '.dmg']}:
        raise ValueError('Checksum manifest must cover ZIP, signature and DMG exactly')
    for name, digest in sums.items():
        if expected[name]['digest'] != 'sha256:' + digest:
            raise ValueError(f'Checksum mismatch: {name}')
    info = (folder / 'BUILD-INFO.txt').read_text().splitlines()
    for line in [f'Version: {version}', f'Architecture: {arch}', f'Source commit: {source}',
                 f'Source tag: {tag}', f'Source tag commit: {source}', 'Source tree: clean',
                 'Pro updates enabled: 1']:
        if info.count(line) != 1:
            raise ValueError(f'Build provenance mismatch: {line}')
    return expected


def check_release(release, release_id, tag, expected, *, draft):
    if (type(release.get('id')) is not int or release['id'] != release_id
            or release.get('tag_name') != tag or release.get('draft') is not draft
            or release.get('prerelease') is not False):
        raise ValueError('Unexpected release identity or publication state')
    assets = release.get('assets', [])
    if len(assets) != len(expected) or {a['name'] for a in assets} != set(expected):
        raise ValueError('Uploaded assets do not exactly match the release manifest')
    ready = True
    for asset in assets:
        want = expected[asset['name']]
        if asset.get('state') != 'uploaded' or asset.get('size') != want['size']:
            raise ValueError(f"GitHub asset state/size mismatch: {asset['name']}")
        if not asset.get('digest'):
            ready = False
        elif asset['digest'] != want['digest']:
            raise ValueError(f"GitHub SHA-256 mismatch: {asset['name']}")
    return ready


def publish(args):
    if os.environ.get('GH_REPO') != REPOSITORY:
        raise ValueError('Only the maintained Pro repository is supported')
    if not re.fullmatch(r'pro-v(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]?)\.(0|[1-9][0-9]?)', args.tag) or args.tag == 'pro-v0.0.0':
        raise ValueError('Invalid Pro tag')
    if not re.fullmatch('[0-9a-f]{40}', args.source) or args.arch not in ['arm64', 'x86_64']:
        raise ValueError('Invalid source commit or architecture')
    folder = args.assets.resolve()
    expected = manifest(folder, args.tag, args.source, args.arch)
    base = f'repos/{REPOSITORY}'

    def check_tag():
        if api(f'{base}/commits/{args.tag}').get('sha') != args.source:
            raise ValueError('Remote tag changed; refusing publication')

    check_tag()
    result = subprocess.run(['gh', 'api', '--paginate', '--slurp', f'{base}/releases?per_page=100'],
                            text=True, capture_output=True, check=True)
    matches = [r for page in json.loads(result.stdout) for r in page if r.get('tag_name') == args.tag]
    if args.resume_draft:
        if len(matches) != 1 or matches[0].get('draft') is not True:
            raise ValueError('Recovery requires exactly one existing unpublished draft')
        release = matches[0]
    else:
        if matches:
            raise ValueError('Release already exists; recovery must be requested explicitly')
        # Existing tag is verified separately. Omitting target_commitish avoids an
        # unnecessary workflow permission check against an older source commit.
        release = api(f'{base}/releases', 'POST', {
            'tag_name': args.tag, 'draft': True, 'prerelease': False,
            'name': f'ChirpOS Pro {args.tag[5:]} · macOS {args.arch}',
            'body': args.notes.read_text(),
        })
    release_id = release.get('id')
    if type(release_id) is not int or release_id <= 0 or release.get('tag_name') != args.tag or release.get('draft') is not True:
        raise ValueError('Invalid draft returned by GitHub')
    endpoint = f'{base}/releases/{release_id}'
    print(f'Verifying draft release ID {release_id} for {args.tag}', flush=True)
    if not args.resume_draft:
        subprocess.run(['gh', 'release', 'upload', args.tag, '--repo', REPOSITORY,
                        *[str(folder / n) for n in sorted(expected)]], check=True)
    # /releases/tags/{tag} only returns published releases. Drafts must use ID.
    for attempt in range(6):
        if check_release(api(endpoint), release_id, args.tag, expected, draft=True):
            break
        if attempt == 5:
            raise ValueError('GitHub asset digests still missing; draft remains unpublished')
        time.sleep(10)
    check_tag()
    api(endpoint, 'PATCH', {'draft': False, 'make_latest': 'false'})
    if not check_release(api(endpoint), release_id, args.tag, expected, draft=False):
        raise ValueError('Published release metadata no longer matches verified assets')
    print(f'Published and verified {args.tag}; release ID {release_id}; {len(expected)} assets')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--assets', type=Path, required=True)
    parser.add_argument('--tag', required=True)
    parser.add_argument('--source', required=True)
    parser.add_argument('--arch', required=True)
    parser.add_argument('--notes', type=Path, required=True)
    parser.add_argument('--resume-draft', action='store_true')
    try:
        publish(parser.parse_args())
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f'Pro publication failed: {error}', file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError) and error.stderr:
            print(error.stderr, file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
