#!/usr/bin/env python3
"""Validate clean federated package snapshots; upload only on explicit request."""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
REPOSITORY = 'https://github.com/hejunshen36-dev/upgrade_kit'
PACKAGES = (
    'upgrade_kit_platform_interface', 'upgrade_kit_android',
    'upgrade_kit_ios', 'upgrade_kit_ohos', 'upgrade_kit',
)
DEPENDENCIES = {
    name: (() if name == PACKAGES[0] else
           PACKAGES[:-1] if name == 'upgrade_kit' else (PACKAGES[0],))
    for name in PACKAGES
}
COMMON = ('pubspec.yaml', '.pubignore', 'LICENSE', 'CHANGELOG.md',
          'README.md', 'analysis_options.yaml', 'lib', 'test')
NATIVE = {
    'upgrade_kit_android': ('android/src', 'android/build.gradle', 'android/settings.gradle'),
    'upgrade_kit_ios': ('ios/Classes', 'ios/Resources', 'ios/upgrade_kit_ios.podspec'),
    'upgrade_kit_ohos': ('ohos/src', 'ohos/index.ets', 'ohos/oh-package.json5',
                         'ohos/build-profile.json5', 'ohos/hvigorfile.ts'),
}
EXAMPLE = ('README.md', 'pubspec.yaml', 'analysis_options.yaml', 'lib', 'test')
IGNORED_NAMES = {'.git', '.dart_tool', '.gradle', '.hvigor', 'oh_modules',
                 'node_modules', 'Pods', 'build', 'coverage', '__pycache__', '.DS_Store'}
IGNORED_SUFFIXES = {'.jks', '.keystore', '.p12', '.mobileprovision', '.pyc', '.log'}


def field(text, name):
    match = re.search(r'^' + re.escape(name) + r':\s*([^\n]+)$', text, re.M)
    if not match:
        raise ValueError(f'Missing {name} in pubspec')
    return match[1].strip().strip('\'"')


def validate_metadata(root):
    """Validate our intentionally simple manifest format without third-party Python."""
    texts = {name: (root / name / 'pubspec.yaml').read_text() for name in PACKAGES}
    versions = {}
    for name, text in texts.items():
        if field(text, 'name') != name:
            raise ValueError(f'{name}: package name mismatch')
        versions[name] = field(text, 'version')
        if not re.fullmatch(r'\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?', versions[name]):
            raise ValueError(f'{name}: unsupported release version')
        if re.search(r'^publish_to:', text, re.M):
            raise ValueError(f'{name}: omit publish_to for the default pub.dev target')
        if field(text, 'repository') != REPOSITORY:
            raise ValueError(f'{name}: repository does not match {REPOSITORY}')
        if field(text, 'issue_tracker') != REPOSITORY + '/issues':
            raise ValueError(f'{name}: invalid issue tracker')
    for name, text in texts.items():
        block = re.search(r'^dependencies:\n(.*?)(?=^\S|\Z)', text, re.M | re.S)
        if not block:
            raise ValueError(f'{name}: missing dependencies')
        for dep in DEPENDENCIES[name]:
            expected = f'  {dep}: ^{versions[dep]}'
            if expected not in block[1].splitlines():
                raise ValueError(f'{name}: expected hosted dependency {expected.strip()}')
        if re.search(r'^\s+(?:path|git):', block[1], re.M):
            raise ValueError(f'{name}: release dependencies cannot use path/git')
        if versions[name] not in (root / name / 'CHANGELOG.md').read_text():
            raise ValueError(f'{name}: version missing from CHANGELOG.md')
    podspec = (root / 'upgrade_kit_ios/ios/upgrade_kit_ios.podspec').read_text()
    if not re.search(r"s\.version\s*=\s*'" + re.escape(versions['upgrade_kit_ios']) + "'", podspec):
        raise ValueError('iOS podspec version differs from the Dart package')
    ohos = (root / 'upgrade_kit_ohos/ohos/oh-package.json5').read_text()
    if not re.search(r'"version"\s*:\s*"' + re.escape(versions['upgrade_kit_ohos']) + '"', ohos):
        raise ValueError('OHOS module version differs from the Dart package')
    return versions


def copy_input(source, target):
    if source.name in IGNORED_NAMES or source.suffix in IGNORED_SUFFIXES:
        return
    if source.is_symlink():
        raise ValueError(f'Release inputs cannot be symlinks: {source}')
    if source.is_dir():
        target.mkdir(parents=True, exist_ok=True)
        for child in sorted(source.iterdir()):
            copy_input(child, target / child.name)
    else:
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)


def write_overrides(directory, dependencies, prefix):
    content = 'dependency_overrides:\n' + ''.join(
        f'  {name}:\n    path: {prefix}{name}\n' for name in dependencies)
    (directory / 'pubspec_overrides.yaml').write_text(content)


def stage(root, target):
    for name in PACKAGES:
        source, package = root / name, target / name
        for relative in COMMON + NATIVE.get(name, ()):
            copy_input(source / relative, package / relative)
        if name == 'upgrade_kit':
            copy_input(source / 'doc', package / 'doc')
            for relative in EXAMPLE:
                copy_input(source / 'example' / relative, package / 'example' / relative)
        if DEPENDENCIES[name]:
            write_overrides(package, DEPENDENCIES[name], '../')
    write_overrides(target / 'upgrade_kit/example', PACKAGES[:-1], '../../')


def run(flutter, arguments, directory):
    print(f'[{directory.name}] flutter {" ".join(arguments)}', flush=True)
    subprocess.run([flutter, *arguments], cwd=directory, check=True)


def prepare_hosted(package, versions):
    """Remove dev overrides without rewriting the example's self path."""
    (package / 'pubspec_overrides.yaml').unlink(missing_ok=True)
    (package / 'example/pubspec_overrides.yaml').unlink(missing_ok=True)


def check(flutter, target, selected, offline=False):
    directories = [target / name for name in selected]
    if 'upgrade_kit' in selected:
        directories.append(target / 'upgrade_kit/example')
    # Resolve example separately before analysis; only a root package's overrides apply.
    for directory in directories:
        run(flutter, ['pub', 'get', *(['--offline'] if offline else [])], directory)
    for directory in directories:
        sources = ['lib', 'test']
        # dart format uses the Dart executable from the same selected Flutter SDK.
        resolved = Path(shutil.which(flutter)).resolve()
        dart = resolved.parent / ('dart.bat' if os.name == 'nt' else 'dart')
        subprocess.run([str(dart), 'format', '--output=none', '--set-exit-if-changed', *sources],
                       cwd=directory, check=True)
        run(flutter, ['analyze', '--no-pub'], directory)
        run(flutter, ['test', '--no-pub'], directory)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument('--check', action='store_true', help='local checks only; no pub publish command')
    modes.add_argument('--dry-run', action='store_true', help='checks plus hosted-dependency Pub validation (default)')
    modes.add_argument('--publish', action='store_true', help='explicitly upload one selected package after checks')
    parser.add_argument('--package', choices=PACKAGES)
    parser.add_argument('--offline', action='store_true', help='use cached external dependencies with --check')
    args = parser.parse_args(argv)
    if args.publish and not args.package:
        parser.error('--publish requires --package; publish dependencies first in documented order')
    if args.offline and not args.check:
        parser.error('--offline is supported only with --check; Pub validation requires network access')
    flutter = os.environ.get('FLUTTER_BIN', 'flutter')
    if not shutil.which(flutter):
        parser.error(f'Flutter executable not found: {flutter}')
    versions = validate_metadata(ROOT)
    selected = [name for name in PACKAGES if args.package is None or name == args.package]
    with tempfile.TemporaryDirectory(prefix='upgrade-kit-publish-') as temporary:
        target = Path(temporary)
        stage(ROOT, target)
        check(flutter, target, selected, args.offline)
        if args.check:
            return 0
        for name in selected:
            package = target / name
            # Final validation must use published dependencies, never local overrides.
            prepare_hosted(package, versions)
            run(flutter, ['pub', 'get'], package)
            run(flutter, ['pub', 'publish', '--dry-run'], package)
        if args.publish:
            run(flutter, ['pub', 'publish', '--force'], target / args.package)
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f'Release checks failed; no further uploads attempted: {error}', file=sys.stderr)
        sys.exit(1)
