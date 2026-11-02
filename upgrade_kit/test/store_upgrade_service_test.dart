import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:upgrade_kit/upgrade_kit.dart';
import 'package:upgrade_kit_platform_interface/upgrade_kit_platform_interface.dart';

class _Platform extends UpgradeKitPlatform {
  final calls = <String>[];
  @override
  Future<String> getIosAppVersion() async => '1.0';
  @override
  Future<StoreLaunchResult> openStore(String target) async {
    calls.add(target);
    return StoreLaunchResult.launched;
  }

  @override
  Future<StoreLaunchResult> openCurrentAppStore(String? target) async {
    calls.add('android:$target');
    return StoreLaunchResult.launched;
  }

  @override
  Future<AppUpdateAvailability> checkAppUpdate() async =>
      AppUpdateAvailability.updateAvailable;
  @override
  Future<UpdateDialogResult> showUpdateDialog() async {
    calls.add('dialog');
    return UpdateDialogResult.shown;
  }

  @override
  Future<AndroidStoreContext> getAndroidStoreContext() async =>
      const AndroidStoreContext(
        vendor: AndroidStoreVendor.samsung,
        packageName: 'app',
        currentVersionName: '1.0',
        currentVersionCode: '1',
      );
}

void main() {
  late _Platform platform;
  setUp(() {
    final original = UpgradeKitPlatform.instance;
    platform = _Platform();
    UpgradeKitPlatform.instance = platform;
    addTearDown(() {
      UpgradeKitPlatform.instance = original;
      debugDefaultTargetPlatformOverride = null;
    });
  });
  test(
    'iOS configuration queries by ID and country, compares current version and opens configured ID',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final service = StoreUpgradeService(
        configuration: StoreUpgradeConfiguration(
          ios: IosStoreUpgradeConfiguration(appId: '123456', country: 'cn'),
        ),
        client: MockClient((request) async {
          expect(request.url.host, 'itunes.apple.com');
          expect(request.url.queryParameters['id'], '123456');
          expect(request.url.queryParameters['country'], 'cn');
          return http.Response(
            jsonEncode({
              'resultCount': 1,
              'results': [
                {'trackId': 123456, 'version': '1.1', 'releaseNotes': 'Fixes'},
              ],
            }),
            200,
          );
        }),
      );
      final result = await service.checkStoreUpgrade();
      expect(result.status, StoreUpgradeCheckStatus.updateAvailable);
      expect(result.release?.version.versionName, '1.1');
      expect(result.release?.releaseNotes, 'Fixes');
      expect(platform.calls, isEmpty);
      expect(
        await service.requestStoreUpgrade(),
        StoreUpgradeActionResult.storeLaunched,
      );
      expect(platform.calls, ['123456']);
    },
  );
  test('iOS empty, malformed and failed responses are not noUpdate', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    for (final response in [
      http.Response('{"results":[]}', 200),
      http.Response('invalid', 200),
      http.Response('{}', 503),
      http.Response('{"results":[{"trackId":999,"version":"2.0"}]}', 200),
    ]) {
      final service = StoreUpgradeService(
        configuration: StoreUpgradeConfiguration(
          ios: IosStoreUpgradeConfiguration(appId: '123456'),
        ),
        client: MockClient((_) async => response),
      );
      expect(
        (await service.checkStoreUpgrade()).status,
        StoreUpgradeCheckStatus.failed,
      );
    }
  });
  test('iOS equal numeric components mean no update', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final service = StoreUpgradeService(
      configuration: StoreUpgradeConfiguration(
        ios: IosStoreUpgradeConfiguration(appId: '123456'),
      ),
      client: MockClient(
        (_) async => http.Response(
          '{"results":[{"trackId":123456,"version":"1.0.0"}]}',
          200,
        ),
      ),
    );
    expect(
      (await service.checkStoreUpgrade()).status,
      StoreUpgradeCheckStatus.noUpdate,
    );
  });
  test('missing configuration and unsupported platform are explicit', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final service = StoreUpgradeService(
      configuration: const StoreUpgradeConfiguration(),
    );
    expect(
      (await service.checkStoreUpgrade()).status,
      StoreUpgradeCheckStatus.notConfigured,
    );
    await expectLater(service.requestStoreUpgrade(), throwsStateError);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(
      (await service.checkStoreUpgrade()).status,
      StoreUpgradeCheckStatus.unsupported,
    );
  });
  test(
    'Android configuration uses existing vendor status and store fallback',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final service = StoreUpgradeService(
        configuration: StoreUpgradeConfiguration(
          android: AndroidStoreUpgradeConfiguration(
            vendors: AndroidVendorUpgradeConfiguration(),
            fallbackTarget: 'market://details?id=app',
          ),
        ),
      );
      expect(
        (await service.checkStoreUpgrade()).status,
        StoreUpgradeCheckStatus.unsupported,
      );
      expect(
        await service.requestStoreUpgrade(),
        StoreUpgradeActionResult.storeLaunched,
      );
      expect(platform.calls, ['android:market://details?id=app']);
    },
  );
  test(
    'OHOS adapter checks and invokes native dialog without downloading',
    () async {
      final service = StoreUpgradeService(
        configuration: const StoreUpgradeConfiguration(
          ohos: OhosStoreUpgradeConfiguration(),
        ),
        platform: StoreUpgradePlatform.ohos,
      );
      expect(
        (await service.checkStoreUpgrade()).status,
        StoreUpgradeCheckStatus.updateAvailable,
      );
      expect(
        await service.requestStoreUpgrade(),
        StoreUpgradeActionResult.dialogShown,
      );
      expect(platform.calls, ['dialog']);
    },
  );
  test('validates iOS IDs and storefront before I/O', () {
    expect(() => IosStoreUpgradeConfiguration(appId: ' '), throwsArgumentError);
    expect(
      () => IosStoreUpgradeConfiguration(appId: '1?bad'),
      throwsArgumentError,
    );
    expect(
      () => IosStoreUpgradeConfiguration(appId: '123', country: 'china'),
      throwsArgumentError,
    );
  });
}
