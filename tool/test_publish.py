"""Test release snapshots and upload gating without contacting Pub or GitHub."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

import publish


class PublishTest(unittest.TestCase):
    def invoke(self, arguments, failure=''):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            log = root / 'calls.jsonl'
            flutter = root / 'flutter'
            flutter.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
with open(os.environ['CALL_LOG'], 'a') as log:
    log.write(json.dumps({'tool': 'flutter', 'args': args, 'package': Path.cwd().name}) + '\\n')
phase = 'get' if args[:2] == ['pub', 'get'] else args[0]
if args == ['pub', 'publish', '--dry-run']:
    phase = 'dry-run'
    assert not Path('pubspec_overrides.yaml').exists()
    assert not Path('example/pubspec_overrides.yaml').exists()
    assert 'publish_to:' not in Path('pubspec.yaml').read_text()
    assert not Path('android/local.properties').exists()
    assert not Path('example/tool').exists()
    if Path('example/pubspec.yaml').exists():
        example = Path('example/pubspec.yaml').read_text()
        assert '  upgrade_kit:' in example and '    path: ../' in example
        assert 'path: ../../' not in example
if os.environ.get('FAIL_PHASE') == phase:
    print('Package validation warning or failed command')
    sys.exit(65)
''')
            flutter.chmod(0o755)
            dart = root / 'dart'
            dart.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
with open(os.environ['CALL_LOG'], 'a') as log:
    log.write(json.dumps({'tool': 'dart', 'args': sys.argv[1:], 'package': Path.cwd().name}) + '\\n')
sys.exit(1 if os.environ.get('FAIL_PHASE') == 'format' else 0)
''')
            dart.chmod(0o755)
            result = subprocess.run(
                ['bash', str(publish.ROOT / 'tool/publish.sh'), *arguments],
                cwd=root,
                env={**os.environ, 'FLUTTER_BIN': str(flutter),
                     'CALL_LOG': str(log), 'FAIL_PHASE': failure},
                capture_output=True, text=True,
            )
            calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
            return result, calls

    def test_metadata_and_native_versions_are_consistent(self):
        self.assertEqual(list(publish.validate_metadata(publish.ROOT)), list(publish.PACKAGES))

    def test_snapshot_is_allowlisted_and_keeps_native_sources(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source, release = root / 'source', root / 'release'
            publish.stage(publish.ROOT, source)
            (source / 'upgrade_kit_android/android/local.properties').write_text('local-only')
            (source / 'upgrade_kit/lib/signing.p12').write_text('not a release input')
            (source / 'upgrade_kit/lib/build').mkdir()
            (source / 'upgrade_kit/lib/build/token').write_text('not a release input')
            (source / 'credentials.txt').write_text('outside allowlist')
            publish.stage(source, release)
            for relative in ['credentials.txt', 'upgrade_kit/lib/signing.p12',
                             'upgrade_kit/lib/build', 'upgrade_kit_android/android/local.properties',
                             'upgrade_kit/example/android']:
                self.assertFalse((release / relative).exists(), relative)
            for relative in ['upgrade_kit_ios/ios/Classes/UpgradeKitIosPlugin.swift',
                             'upgrade_kit_ios/ios/Resources/PrivacyInfo.xcprivacy',
                             'upgrade_kit_ohos/ohos/index.ets',
                             'upgrade_kit/example/test/widget_test.dart']:
                self.assertTrue((release / relative).exists(), relative)

    def test_source_symlink_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'outside').write_text('outside snapshot')
            (root / 'input').symlink_to(root / 'outside')
            with self.assertRaises(ValueError):
                publish.copy_input(root / 'input', root / 'output')

    def test_hosted_preparation_keeps_example_pubspec_unchanged(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            publish.stage(publish.ROOT, root)
            package = root / 'upgrade_kit'
            example = package / 'example/pubspec.yaml'
            original = example.read_bytes()
            publish.prepare_hosted(package, publish.validate_metadata(publish.ROOT))
            self.assertEqual(example.read_bytes(), original)
            self.assertFalse((package / 'pubspec_overrides.yaml').exists())
            self.assertFalse((package / 'example/pubspec_overrides.yaml').exists())

    def test_check_runs_all_packages_and_example_without_pub_publish(self):
        result, calls = self.invoke(['--check', '--offline'])
        self.assertEqual(result.returncode, 0, result.stderr)
        gets = [c for c in calls if c['args'][:2] == ['pub', 'get']]
        self.assertEqual([c['package'] for c in gets], [*publish.PACKAGES, 'example'])
        self.assertTrue(all(c['args'][-1] == '--offline' for c in gets))
        self.assertFalse(any(c['args'][:2] == ['pub', 'publish'] for c in calls))

    def test_default_dry_run_never_uploads(self):
        result, calls = self.invoke([])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([c['package'] for c in calls if c['args'] == ['pub', 'publish', '--dry-run']],
                         list(publish.PACKAGES))
        self.assertFalse(any('--force' in c['args'] for c in calls))

    def test_explicit_publish_only_uploads_the_selected_package_last(self):
        for package in publish.PACKAGES:
            with self.subTest(package=package):
                result, calls = self.invoke(['--publish', '--package', package])
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(calls[-1]['args'], ['pub', 'publish', '--force'])
                self.assertEqual(calls[-1]['package'], package)
                self.assertEqual(sum('--force' in c['args'] for c in calls), 1)

    def test_every_failure_stops_before_upload(self):
        for phase in ['get', 'format', 'analyze', 'test', 'dry-run']:
            with self.subTest(phase=phase):
                result, calls = self.invoke(['--publish', '--package', publish.PACKAGES[0]], phase)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(any('--force' in c['args'] for c in calls))

    def test_invalid_cli_options_never_call_flutter(self):
        for arguments in [['--publish'], ['--dry-run', '--offline'],
                          ['--package', 'unknown'], ['--publish', '--check']]:
            with self.subTest(arguments=arguments):
                result, calls = self.invoke(arguments)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(calls, [])


if __name__ == '__main__':
    unittest.main()
