#!/usr/bin/env python3
"""Offline behavioral tests for Pro publication; no credentials or signing keys."""
import argparse
from contextlib import contextmanager, redirect_stderr, redirect_stdout
from copy import deepcopy
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


SPEC = importlib.util.spec_from_file_location(
    'pro_publish_under_test', Path(__file__).with_name('publish-pro-release.py'))
publisher = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(publisher)

REPOSITORY = 'sucan2233/chirp-os'
BASE = f'repos/{REPOSITORY}'
TAG = 'pro-v0.8.1'
SOURCE = '1a' * 20
RELEASE_ID = 2718
ENDPOINT = f'{BASE}/releases/{RELEASE_ID}'
TAG_ENDPOINT = f'{BASE}/commits/{TAG}'
LIST_COMMAND = ['gh', 'api', '--paginate', '--slurp',
                f'{BASE}/releases?per_page=100']


class AssetFixture:
    """Real, nonempty files; expected digests do not use publisher.manifest()."""

    def __init__(self, root, arch):
        self.folder = root / 'assets'
        self.folder.mkdir()
        self.stem = f'ChirpOS-Pro-0.8.1-macOS-{arch}'
        self.zip_name = self.stem + '.zip'
        content = {
            self.zip_name: b'Offline ZIP fixture\x00\x01\xff\n',
            self.stem + '.zip.sig': b'Offline signature fixture; no private key\n',
            self.stem + '.dmg': b'Offline DMG fixture\x00\xfe\n',
            '安装说明.txt': '离线发布测试资产。\n'.encode('utf-8'),
            'BUILD-INFO.txt': ('\n'.join([
                'Version: 0.8.1', f'Architecture: {arch}',
                f'Source commit: {SOURCE}', f'Source tag: {TAG}',
                f'Source tag commit: {SOURCE}', 'Source tree: clean',
                'Pro updates enabled: 1',
            ]) + '\n').encode('utf-8'),
        }
        content['SHA256SUMS.txt'] = ''.join(
            f'{hashlib.sha256(content[name]).hexdigest()}  {name}\n'
            for name in sorted(content)
            if name.endswith(('.zip', '.zip.sig', '.dmg'))
        ).encode('utf-8')
        for name, data in content.items():
            (self.folder / name).write_bytes(data)
        self.expected = {
            name: {'size': len(data),
                   'digest': 'sha256:' + hashlib.sha256(data).hexdigest()}
            for name, data in content.items()
        }
        self.notes = root / 'release-notes.md'
        self.notes.write_text('ChirpOS Pro 离线回归测试\n', encoding='utf-8')
        self.args = argparse.Namespace(
            assets=self.folder, tag=TAG, source=SOURCE, arch=arch,
            notes=self.notes, resume_draft=False)


class FakeGitHub:
    """Stateful GitHub boundary: listing, upload, ID reads, and publication."""

    def __init__(self, fixture, resume):
        self.fixture = fixture
        self.events = []
        self.release = self.ready_release()
        if not resume:
            self.release['assets'] = []
        self.pages = [[deepcopy(self.release)]] if resume else [[]]
        self.tag_shas = [SOURCE, SOURCE]
        self.tag_reads = 0
        self.id_reads = 0
        self.read_responses = []

    def ready_release(self):
        return {
            'id': RELEASE_ID, 'tag_name': TAG, 'draft': True,
            'prerelease': False,
            'assets': [dict(name=name, state='uploaded', **metadata)
                       for name, metadata in sorted(self.fixture.expected.items())],
        }

    def api(self, path, method='GET', payload=None):
        self.events.append(('api', method, path, deepcopy(payload)))
        if path.startswith(f'{BASE}/releases/tags/'):
            # GitHub's tag endpoint cannot retrieve an unpublished draft.
            raise subprocess.CalledProcessError(
                1, ['gh', 'api', path], stderr='HTTP 404: Not Found')
        if path == TAG_ENDPOINT and method == 'GET':
            sha = self.tag_shas[min(self.tag_reads, len(self.tag_shas) - 1)]
            self.tag_reads += 1
            return {'sha': sha}
        if path == f'{BASE}/releases' and method == 'POST':
            self.release.update(deepcopy(payload))
            return deepcopy(self.release)
        if path == ENDPOINT and method == 'GET':
            self.id_reads += 1
            if self.read_responses:
                return deepcopy(self.read_responses.pop(0))
            return deepcopy(self.release)
        if path == ENDPOINT and method == 'PATCH':
            self.release.update(deepcopy(payload))
            return deepcopy(self.release)
        raise AssertionError(f'Unexpected offline API request: {method} {path}')

    def run(self, command, **kwargs):
        command = list(command)
        self.events.append(('subprocess', tuple(command)))
        if command == LIST_COMMAND:
            if kwargs != {'text': True, 'capture_output': True, 'check': True}:
                raise AssertionError(f'Unexpected listing options: {kwargs}')
            return subprocess.CompletedProcess(command, 0, json.dumps(self.pages), '')
        upload_prefix = ['gh', 'release', 'upload', TAG, '--repo', REPOSITORY]
        if command[:6] == upload_prefix:
            wanted = [str(self.fixture.folder / name)
                      for name in sorted(self.fixture.expected)]
            if command[6:] != wanted or kwargs != {'check': True}:
                raise AssertionError(f'Unexpected asset upload: {command}, {kwargs}')
            # Model the upload from actual disk bytes, not the expected manifest.
            self.release['assets'] = [
                {'name': Path(path).name, 'state': 'uploaded',
                 'size': Path(path).stat().st_size,
                 'digest': 'sha256:' + hashlib.sha256(Path(path).read_bytes()).hexdigest()}
                for path in command[6:]
            ]
            return subprocess.CompletedProcess(command, 0)
        raise AssertionError(f'Unexpected offline subprocess: {command}')

    def requests(self, method):
        return [event for event in self.events
                if event[0] == 'api' and event[1] == method]

    def commands(self, prefix):
        return [event[1] for event in self.events
                if event[0] == 'subprocess' and event[1][:len(prefix)] == tuple(prefix)]


@contextmanager
def offline_release(*, resume=False, arch='arm64'):
    with tempfile.TemporaryDirectory(prefix='chirpos-publish-offline-') as directory:
        # macOS temporary paths may alias /private/var; publication resolves them.
        fixture = AssetFixture(Path(directory).resolve(), arch)
        fixture.args.resume_draft = resume
        github = FakeGitHub(fixture, resume)
        stdout, stderr = io.StringIO(), io.StringIO()
        # Clear inherited tokens/configuration and replace every process/API call.
        with (mock.patch.dict(os.environ, {'GH_REPO': REPOSITORY}, clear=True),
              mock.patch.object(publisher, 'api', side_effect=github.api) as api_mock,
              mock.patch.object(publisher.subprocess, 'run', side_effect=github.run) as run_mock,
              mock.patch.object(publisher.time, 'sleep') as sleep_mock,
              redirect_stdout(stdout), redirect_stderr(stderr)):
            yield argparse.Namespace(
                fixture=fixture, args=fixture.args, github=github,
                api=api_mock, run=run_mock, sleep=sleep_mock,
                stdout=stdout, stderr=stderr)


class PublishTests(unittest.TestCase):
    def assert_unpublished(self, case):
        self.assertEqual(case.github.requests('PATCH'), [])
        self.assertIs(case.github.release['draft'], True)

    def assert_no_remote_calls(self, case):
        case.api.assert_not_called()
        case.run.assert_not_called()
        case.sleep.assert_not_called()

    def assert_id_reads_only(self, case):
        release_gets = [event[2] for event in case.github.requests('GET')
                        if '/releases/' in event[2]]
        self.assertTrue(release_gets)
        self.assertEqual(release_gets, [ENDPOINT] * len(release_gets))
        self.assertFalse(any('/releases/tags/' in event[2]
                             for event in case.github.requests('GET')))

    def test_create_upload_verify_by_id_then_publish_without_target_commitish(self):
        for arch in ('arm64', 'x86_64'):
            with self.subTest(arch=arch), offline_release(arch=arch) as case:
                # A paginated unrelated release must not prevent creation.
                case.github.pages = [[], [{'id': 99, 'tag_name': 'pro-v0.7.0',
                                          'draft': False}]]
                publisher.publish(case.args)
                created = case.github.requests('POST')
                self.assertEqual(len(created), 1)
                self.assertEqual(created[0][2], f'{BASE}/releases')
                payload = created[0][3]
                self.assertEqual(payload, {
                    'tag_name': TAG, 'draft': True, 'prerelease': False,
                    'name': f'ChirpOS Pro 0.8.1 · macOS {arch}',
                    'body': case.fixture.notes.read_text(),
                })
                self.assertNotIn('target_commitish', payload)
                self.assertEqual(len(case.github.commands(['gh', 'release', 'upload'])), 1)
                self.assertEqual(case.github.commands(['gh', 'api']), [tuple(LIST_COMMAND)])
                requests = [event[1:3] for event in case.github.events if event[0] == 'api']
                self.assertEqual(requests, [
                    ('GET', TAG_ENDPOINT), ('POST', f'{BASE}/releases'),
                    ('GET', ENDPOINT), ('GET', TAG_ENDPOINT),
                    ('PATCH', ENDPOINT), ('GET', ENDPOINT),
                ])
                self.assertEqual([event[0] for event in case.github.events],
                                 ['api', 'subprocess', 'api', 'subprocess',
                                  'api', 'api', 'api', 'api'])
                self.assertEqual(case.github.requests('PATCH'), [
                    ('api', 'PATCH', ENDPOINT, {'draft': False, 'make_latest': 'false'})])
                self.assertIs(case.github.release['draft'], False)
                self.assertEqual(case.github.id_reads, 2)
                self.assert_id_reads_only(case)
                case.sleep.assert_not_called()
                self.assertIn('Published and verified', case.stdout.getvalue())

    def test_resume_intact_draft_from_later_page_without_create_or_upload(self):
        with offline_release(resume=True) as case:
            case.github.pages = [[{'id': 99, 'tag_name': 'pro-v0.7.0', 'draft': False}],
                                 [deepcopy(case.github.release)]]
            publisher.publish(case.args)
            self.assertEqual(case.github.requests('POST'), [])
            self.assertEqual(case.github.commands(['gh', 'release', 'upload']), [])
            self.assertEqual(case.github.tag_reads, 2)
            self.assertEqual(case.github.id_reads, 2)
            self.assertEqual(len(case.github.requests('PATCH')), 1)
            self.assertEqual([event[1:3] for event in case.github.events
                              if event[0] == 'api'], [
                ('GET', TAG_ENDPOINT), ('GET', ENDPOINT), ('GET', TAG_ENDPOINT),
                ('PATCH', ENDPOINT), ('GET', ENDPOINT),
            ])
            self.assert_id_reads_only(case)
            case.sleep.assert_not_called()

    def test_repository_tag_source_and_architecture_rejected_before_io(self):
        invalid = [
            ('repo', None, 'Only the maintained Pro repository'),
            ('repo', '', 'Only the maintained Pro repository'),
            ('repo', 'other/chirp-os', 'Only the maintained Pro repository'),
            ('repo', REPOSITORY + '\n', 'Only the maintained Pro repository'),
        ]
        invalid += [('tag', value, 'Invalid Pro tag') for value in (
            'v0.8.1', 'pro-v0.0.0', 'pro-v00.8.1', 'pro-v0.08.1',
            'pro-v0.8.01', 'pro-v0.8.1-beta', 'pro-v0.8.1\n',
            'pro-v10000.0.1', 'pro-v0.100.1', '../pro-v0.8.1', '')]
        invalid += [('source', value, 'Invalid source commit or architecture')
                    for value in ('', '1a' * 19, '1a' * 21, SOURCE.upper(),
                                  'g' * 40, SOURCE + '\n')]
        invalid += [('arch', value, 'Invalid source commit or architecture')
                    for value in ('universal', 'amd64', '', 'arm64\n')]
        for field, value, error in invalid:
            with self.subTest(field=field, value=value), offline_release() as case:
                if field == 'repo':
                    if value is None:
                        os.environ.pop('GH_REPO')
                    else:
                        os.environ['GH_REPO'] = value
                else:
                    setattr(case.args, field, value)
                with self.assertRaisesRegex(ValueError, error):
                    publisher.publish(case.args)
                self.assert_no_remote_calls(case)

    def test_resume_requires_one_unpublished_draft(self):
        for scenario in ('missing', 'duplicate', 'public', 'draft_flag_missing'):
            with self.subTest(scenario=scenario), offline_release(resume=True) as case:
                release = deepcopy(case.github.release)
                if scenario == 'missing':
                    case.github.pages = [[], [{'tag_name': 'pro-v0.7.0', 'draft': True}]]
                elif scenario == 'duplicate':
                    duplicate = deepcopy(release)
                    duplicate['id'] = RELEASE_ID + 1
                    case.github.pages = [[release], [duplicate]]
                elif scenario == 'public':
                    release['draft'] = False
                    case.github.pages = [[release]]
                else:
                    release.pop('draft')
                    case.github.pages = [[release]]
                with self.assertRaisesRegex(ValueError, 'exactly one existing unpublished draft'):
                    publisher.publish(case.args)
                self.assert_unpublished(case)
                self.assertEqual(case.github.requests('POST'), [])
                self.assertEqual(case.github.commands(['gh', 'release', 'upload']), [])
                self.assertEqual(case.github.id_reads, 0)

    def test_existing_draft_or_public_release_needs_explicit_recovery(self):
        for draft in (True, False):
            with self.subTest(draft=draft), offline_release() as case:
                release = case.github.ready_release()
                release['draft'] = draft
                case.github.pages = [[release]]
                with self.assertRaisesRegex(ValueError, 'Release already exists'):
                    publisher.publish(case.args)
                self.assert_unpublished(case)
                self.assertEqual(case.github.requests('POST'), [])
                self.assertEqual(case.github.commands(['gh', 'release', 'upload']), [])

    def test_remote_tag_drift_before_creation_or_before_publication(self):
        for resume, check in ((False, 0), (False, 1), (True, 0), (True, 1)):
            with self.subTest(resume=resume, check=check), offline_release(resume=resume) as case:
                case.github.tag_shas[check] = 'b' * 40
                with self.assertRaisesRegex(ValueError, 'Remote tag changed'):
                    publisher.publish(case.args)
                self.assert_unpublished(case)
                self.assertEqual(case.github.tag_reads, check + 1)
                if check == 0:
                    case.run.assert_not_called()
                    self.assertEqual(case.github.requests('POST'), [])
                else:
                    self.assertEqual(case.github.id_reads, 1)

    def test_remote_asset_missing_extra_duplicate_size_hash_and_state_rejected(self):
        errors = {
            'missing': 'exactly match the release manifest',
            'extra': 'exactly match the release manifest',
            'duplicate': 'exactly match the release manifest',
            'size': 'state/size mismatch',
            'hash': 'SHA-256 mismatch',
            'state': 'state/size mismatch',
        }
        for scenario, error in errors.items():
            with self.subTest(scenario=scenario), offline_release(resume=True) as case:
                assets = case.github.release['assets']
                if scenario == 'missing':
                    assets.pop()
                elif scenario == 'extra':
                    assets.append(dict(assets[0], name='unexpected.txt'))
                elif scenario == 'duplicate':
                    assets[-1] = deepcopy(assets[0])
                elif scenario == 'size':
                    assets[0]['size'] += 1
                elif scenario == 'hash':
                    assets[0]['digest'] = 'sha256:' + '0' * 64
                else:
                    assets[0]['state'] = 'new'
                with self.assertRaisesRegex(ValueError, error):
                    publisher.publish(case.args)
                self.assert_unpublished(case)
                self.assertEqual(case.github.id_reads, 1)
                case.sleep.assert_not_called()

    def test_id_read_identity_and_draft_state_must_match_before_publication(self):
        for field, value in (('id', RELEASE_ID + 1), ('id', str(RELEASE_ID)),
                             ('id', True), ('tag_name', 'pro-v0.8.2'),
                             ('draft', False), ('prerelease', True)):
            with self.subTest(field=field, value=value), offline_release(resume=True) as case:
                response = case.github.ready_release()
                response[field] = value
                case.github.read_responses = [response]
                with self.assertRaisesRegex(ValueError, 'Unexpected release identity'):
                    publisher.publish(case.args)
                self.assert_unpublished(case)
                self.assertEqual(case.github.id_reads, 1)

    def test_missing_digest_retried_until_success_including_sixth_attempt(self):
        for resume in (False, True):
            for failures in (1, 5):
                with self.subTest(resume=resume, failures=failures), offline_release(resume=resume) as case:
                    missing = case.github.ready_release()
                    missing['assets'][0].pop('digest')
                    case.github.read_responses = [deepcopy(missing) for _ in range(failures)]
                    case.github.read_responses.append(case.github.ready_release())
                    publisher.publish(case.args)
                    self.assertEqual(case.github.id_reads, failures + 2)
                    self.assertEqual(case.sleep.call_args_list, [mock.call(10)] * failures)
                    self.assertEqual(len(case.github.requests('PATCH')), 1)
                    self.assertIs(case.github.release['draft'], False)
                    self.assert_id_reads_only(case)

    def test_digest_absent_for_all_six_attempts_leaves_draft_unpublished(self):
        for resume in (False, True):
            for digest in (None, ''):
                with self.subTest(resume=resume, digest=digest), offline_release(resume=resume) as case:
                    missing = case.github.ready_release()
                    missing['assets'][0]['digest'] = digest
                    case.github.read_responses = [deepcopy(missing) for _ in range(6)]
                    with self.assertRaisesRegex(ValueError, 'digests still missing'):
                        publisher.publish(case.args)
                    self.assert_unpublished(case)
                    self.assertEqual(case.github.id_reads, 6)
                    self.assertEqual(case.github.tag_reads, 1)
                    self.assertEqual(case.sleep.call_args_list, [mock.call(10)] * 5)
                    self.assert_id_reads_only(case)

    def test_published_state_is_fetched_again_and_validated(self):
        mutations = {
            'id': lambda release: release.update(id=RELEASE_ID + 1),
            'tag': lambda release: release.update(tag_name='pro-v0.8.2'),
            'draft': lambda release: release.update(draft=True),
            'prerelease': lambda release: release.update(prerelease=True),
            'asset_missing': lambda release: release['assets'].pop(),
            'size': lambda release: release['assets'][0].update(size=0),
            'hash': lambda release: release['assets'][0].update(digest='sha256:' + '0' * 64),
            'digest_missing': lambda release: release['assets'][0].pop('digest'),
        }
        for scenario, mutate in mutations.items():
            with self.subTest(scenario=scenario), offline_release(resume=True) as case:
                # Only GET exposes the bad metadata; PATCH returns a plausible success.
                final_response = case.github.ready_release()
                final_response['draft'] = False
                mutate(final_response)
                case.github.read_responses = [case.github.ready_release(), final_response]
                with self.assertRaises(ValueError):
                    publisher.publish(case.args)
                self.assertEqual(len(case.github.requests('PATCH')), 1)
                self.assertEqual(case.github.id_reads, 2)
                self.assertEqual(case.github.events[-1][:3], ('api', 'GET', ENDPOINT))
                self.assertNotIn('Published and verified', case.stdout.getvalue())
                self.assert_id_reads_only(case)

    def test_manifest_matches_independently_hashed_real_six_asset_fixture(self):
        for arch in ('arm64', 'x86_64'):
            with self.subTest(arch=arch), offline_release(arch=arch) as case:
                self.assertEqual(len(case.fixture.expected), 6)
                self.assertEqual(publisher.manifest(case.fixture.folder, TAG, SOURCE, arch),
                                 case.fixture.expected)
                self.assert_no_remote_calls(case)

    def test_local_manifest_tampering_rejected_before_remote_io(self):
        scenarios = ('same_size_content', 'checksum_hash', 'checksum_duplicate',
                     'checksum_missing', 'checksum_extra', 'checksum_malformed',
                     'provenance_source', 'provenance_tag', 'provenance_tag_commit',
                     'provenance_version',
                     'provenance_arch', 'provenance_dirty', 'provenance_updates',
                     'provenance_duplicate', 'extra_file', 'missing_file',
                     'empty_file', 'directory', 'symlink')
        for scenario in scenarios:
            with self.subTest(scenario=scenario), offline_release() as case:
                folder = case.fixture.folder
                archive = folder / case.fixture.zip_name
                sums = folder / 'SHA256SUMS.txt'
                info = folder / 'BUILD-INFO.txt'
                if scenario == 'same_size_content':
                    data = archive.read_bytes()
                    archive.write_bytes(bytes([data[0] ^ 1]) + data[1:])
                elif scenario.startswith('checksum_'):
                    lines = sums.read_text().splitlines()
                    if scenario == 'checksum_hash':
                        lines[0] = '0' * 64 + lines[0][64:]
                    elif scenario == 'checksum_duplicate':
                        lines.append(lines[0])
                    elif scenario == 'checksum_missing':
                        lines.pop()
                    elif scenario == 'checksum_extra':
                        lines.append('0' * 64 + '  unexpected.zip')
                    else:
                        lines[0] = 'not-a-sha256  ' + case.fixture.zip_name
                    sums.write_text('\n'.join(lines) + '\n')
                elif scenario.startswith('provenance_'):
                    replacements = {
                        'provenance_source': (f'Source commit: {SOURCE}', 'Source commit: ' + 'b' * 40),
                        'provenance_tag': (f'Source tag: {TAG}', 'Source tag: pro-v0.8.2'),
                        'provenance_tag_commit': (f'Source tag commit: {SOURCE}', 'Source tag commit: ' + 'b' * 40),
                        'provenance_version': ('Version: 0.8.1', 'Version: 0.8.2'),
                        'provenance_arch': ('Architecture: arm64', 'Architecture: x86_64'),
                        'provenance_dirty': ('Source tree: clean', 'Source tree: dirty'),
                        'provenance_updates': ('Pro updates enabled: 1', 'Pro updates enabled: 0'),
                    }
                    if scenario == 'provenance_duplicate':
                        info.write_text(info.read_text() + f'Source tag commit: {SOURCE}\n')
                    else:
                        old, new = replacements[scenario]
                        info.write_text(info.read_text().replace(old, new))
                elif scenario == 'extra_file':
                    (folder / '.DS_Store').write_bytes(b'unexpected')
                elif scenario == 'missing_file':
                    archive.unlink()
                elif scenario == 'empty_file':
                    archive.write_bytes(b'')
                elif scenario == 'directory':
                    archive.unlink()
                    archive.mkdir()
                else:
                    # Same contents and checksum: the symlink itself must be refused.
                    target = folder.parent / 'outside.zip'
                    target.write_bytes(archive.read_bytes())
                    archive.unlink()
                    archive.symlink_to(target)
                with self.assertRaises(ValueError):
                    publisher.publish(case.args)
                self.assert_no_remote_calls(case)

    def test_cli_returns_success_or_reports_failure(self):
        for fail in (False, True):
            with self.subTest(fail=fail), offline_release(resume=True) as case:
                argv = [str(Path(publisher.__file__)), '--assets', str(case.args.assets),
                        '--tag', TAG, '--source', SOURCE, '--arch', case.args.arch,
                        '--notes', str(case.args.notes), '--resume-draft']
                if fail:
                    case.github.tag_shas[0] = 'b' * 40
                with mock.patch.object(sys, 'argv', argv):
                    self.assertEqual(publisher.main(), 1 if fail else 0)
                if fail:
                    self.assertIn('Pro publication failed: Remote tag changed', case.stderr.getvalue())
                    self.assert_unpublished(case)
                else:
                    self.assertEqual(case.stderr.getvalue(), '')
                    self.assertIn('Published and verified', case.stdout.getvalue())


class ApiTransportTests(unittest.TestCase):
    def test_api_serializes_method_payload_and_decodes_json_without_running_gh(self):
        for method, payload in (('GET', None), ('POST', {'tag_name': TAG, 'draft': True}),
                                ('PATCH', {'draft': False, 'make_latest': 'false'})):
            with self.subTest(method=method):
                response = {'id': RELEASE_ID, 'draft': method != 'PATCH'}
                completed = subprocess.CompletedProcess([], 0, json.dumps(response), '')
                with (mock.patch.dict(os.environ, {}, clear=True),
                      mock.patch.object(publisher.subprocess, 'run', return_value=completed) as run):
                    self.assertEqual(publisher.api(ENDPOINT, method, payload), response)
                args, kwargs = run.call_args
                command = ['gh', 'api', '--method', method, ENDPOINT]
                if payload is not None:
                    command += ['--input', '-']
                    self.assertEqual(json.loads(kwargs['input']), payload)
                else:
                    self.assertIsNone(kwargs['input'])
                self.assertEqual(args, (command,))
                self.assertEqual({key: value for key, value in kwargs.items() if key != 'input'},
                                 {'text': True, 'capture_output': True, 'check': True})


if __name__ == '__main__':
    unittest.main()
