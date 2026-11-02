import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:upgrade_kit/upgrade_kit.dart';

void main() {
  const kit = UpgradeKit();
  final request = UpgradeCheckRequest(
    appId: 'com.example.app',
    currentVersion: const UpgradeVersion(versionName: '1.0.0'),
    platform: 'ios',
    channel: 'beta',
    locale: 'en-US',
  );

  Future<UpgradeCheckResult> check(UpgradeRelease? release) =>
      kit.checkForUpdate(
        source: CallbackUpgradeSource((_) async => release),
        request: request,
      );

  test(
    'adapts a host backend and carries request context and release data',
    () async {
      final result = await kit.checkForUpdate(
        source: CallbackUpgradeSource((input) async {
          expect(input.appId, 'com.example.app');
          expect(input.platform, 'ios');
          expect(input.channel, 'beta');
          expect(input.locale, 'en-US');
          expect(input.currentVersion.versionName, '1.0.0');
          return UpgradeRelease(
            version: const UpgradeVersion(versionName: '1.2.0'),
            releaseNotes: 'Bug fixes',
            downloadUri: Uri.parse('https://example.com/app.apk'),
            storeTarget: '123456789',
            fileSizeBytes: 2048,
          );
        }),
        request: request,
      );
      expect(result.status, UpgradeCheckStatus.updateAvailable);
      expect(result.release?.version.versionName, '1.2.0');
      expect(result.release?.releaseNotes, 'Bug fixes');
      expect(
        result.release?.downloadUri.toString(),
        'https://example.com/app.apk',
      );
      expect(result.release?.storeTarget, '123456789');
      expect(result.release?.fileSizeBytes, 2048);
      expect(result.errorCode, isNull);
    },
  );

  test('null, equal and older releases are confirmed noUpdate', () async {
    expect((await check(null)).status, UpgradeCheckStatus.noUpdate);
    for (final name in ['1.0.0', '0.9.0']) {
      final result = await check(
        UpgradeRelease(version: UpgradeVersion(versionName: name)),
      );
      expect(result.status, UpgradeCheckStatus.noUpdate);
      expect(result.release?.version.versionName, name);
    }
  });

  test('invalid release versions are distinct from noUpdate', () async {
    final result = await check(
      const UpgradeRelease(version: UpgradeVersion(versionName: 'unknown')),
    );
    expect(result.status, UpgradeCheckStatus.failed);
    expect(result.errorCode, 'invalid-version');
    expect(result.release?.version.versionName, 'unknown');
  });

  test('source errors produce stable non-sensitive failures', () async {
    final result = await kit.checkForUpdate(
      source: CallbackUpgradeSource((_) => throw StateError('secret-token')),
      request: request,
    );
    expect(result.status, UpgradeCheckStatus.failed);
    expect(result.errorCode, 'source-error');
    expect(result.errorMessage, isNot(contains('secret-token')));
    expect(result.release, isNull);
  });

  test('times out without reporting noUpdate or leaking late errors', () async {
    final pending = Completer<UpgradeRelease?>();
    final result = await kit.checkForUpdate(
      source: CallbackUpgradeSource((_) => pending.future),
      request: request,
      timeout: const Duration(milliseconds: 1),
    );
    expect(result.status, UpgradeCheckStatus.failed);
    expect(result.errorCode, 'timeout');
    pending.completeError(StateError('late failure'));
    await Future<void>.delayed(Duration.zero);
  });

  test('custom comparison supports versions outside SemVer', () async {
    final result = await kit.checkForUpdate(
      source: CallbackUpgradeSource(
        (_) async =>
            const UpgradeRelease(version: UpgradeVersion(versionName: 'r20')),
      ),
      request: request,
      comparator: (remote, current) {
        expect(remote.versionName, 'r20');
        expect(current.versionName, '1.0.0');
        return 1;
      },
    );
    expect(result.status, UpgradeCheckStatus.updateAvailable);
  });

  test('comparison errors remain distinct from source failures', () async {
    final result = await kit.checkForUpdate(
      source: CallbackUpgradeSource(
        (_) async =>
            const UpgradeRelease(version: UpgradeVersion(versionName: '2.0.0')),
      ),
      request: request,
      comparator: (_, _) => throw StateError('private-data'),
    );
    expect(result.status, UpgradeCheckStatus.failed);
    expect(result.errorCode, 'comparison-error');
    expect(result.errorMessage, isNot(contains('private-data')));
  });

  test('rejects invalid parameters before calling the source', () async {
    expect(
      () => UpgradeCheckRequest(
        appId: ' ',
        currentVersion: request.currentVersion,
      ),
      throwsArgumentError,
    );
    var calls = 0;
    for (final timeout in [Duration.zero, const Duration(seconds: -1)]) {
      await expectLater(
        kit.checkForUpdate(
          source: CallbackUpgradeSource((_) async {
            calls++;
            return null;
          }),
          request: request,
          timeout: timeout,
        ),
        throwsArgumentError,
      );
    }
    expect(calls, 0);
  });

  test('concurrent calls keep release results independent', () async {
    final pending = Completer<UpgradeRelease?>();
    final first = kit.checkForUpdate(
      source: CallbackUpgradeSource((_) => pending.future),
      request: request,
    );
    final second = await check(null);
    pending.complete(
      const UpgradeRelease(version: UpgradeVersion(versionName: '2.0.0')),
    );
    expect(second.status, UpgradeCheckStatus.noUpdate);
    expect((await first).status, UpgradeCheckStatus.updateAvailable);
  });
}
