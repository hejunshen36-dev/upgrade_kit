import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:upgrade_kit_platform_interface/upgrade_kit_platform_interface.dart';

import 'android_vendor/android_vendor_upgrade_service.dart';
import 'android_vendor/android_vendor_upgrade.dart';
import '../check/upgrade_models.dart';
import 'store_upgrade_configuration.dart';
import 'store_upgrade_models.dart';

/// Configured Android, iOS and OHOS store operations.
/// Checking never opens a store or dialog; requesting an upgrade is explicit.
class StoreUpgradeService {
  StoreUpgradeService({
    required this.configuration,
    StoreUpgradePlatform? platform,
    http.Client? client,
  }) : _platformOverride = platform,
       _client = client;
  final StoreUpgradeConfiguration configuration;
  final StoreUpgradePlatform? _platformOverride;

  /// An injected HTTP client is borrowed and never closed by this service.
  final http.Client? _client;

  StoreUpgradePlatform get platform =>
      _platformOverride ??
      switch (kIsWeb ? 'web' : defaultTargetPlatform.name) {
        'android' => StoreUpgradePlatform.android,
        'iOS' => StoreUpgradePlatform.ios,
        'ohos' => StoreUpgradePlatform.ohos,
        _ => StoreUpgradePlatform.unsupported,
      };

  Future<StoreUpgradeCheckResult> checkStoreUpgrade() async {
    try {
      return switch (platform) {
        StoreUpgradePlatform.android => await _checkAndroid(),
        StoreUpgradePlatform.ios => await _checkIos(),
        StoreUpgradePlatform.ohos => await _checkOhos(),
        StoreUpgradePlatform.unsupported => const StoreUpgradeCheckResult(
          status: StoreUpgradeCheckStatus.unsupported,
        ),
      };
    } on MissingPluginException {
      rethrow;
    } on UnsupportedError {
      return const StoreUpgradeCheckResult(
        status: StoreUpgradeCheckStatus.unsupported,
      );
    } on UpgradeKitException catch (error) {
      return StoreUpgradeCheckResult(
        status: StoreUpgradeCheckStatus.failed,
        errorCode: error.code,
      );
    } on TimeoutException {
      return const StoreUpgradeCheckResult(
        status: StoreUpgradeCheckStatus.failed,
        errorCode: 'timeout',
      );
    } on Object {
      return const StoreUpgradeCheckResult(
        status: StoreUpgradeCheckStatus.failed,
        errorCode: 'store-error',
      );
    }
  }

  Future<StoreUpgradeCheckResult> _checkAndroid() async {
    final config = configuration.android;
    if (config == null) {
      return const StoreUpgradeCheckResult(
        status: StoreUpgradeCheckStatus.notConfigured,
      );
    }
    final service = AndroidVendorUpgradeService(
      platform: UpgradeKitPlatform.instance,
      client: _client,
    );
    try {
      final result = await service.check(config.vendors, locale: config.locale);
      final release = result.release;
      return StoreUpgradeCheckResult(
        status: switch (result.status) {
          AndroidVendorUpgradeCheckStatus.updateAvailable =>
            StoreUpgradeCheckStatus.updateAvailable,
          AndroidVendorUpgradeCheckStatus.noUpdate =>
            StoreUpgradeCheckStatus.noUpdate,
          AndroidVendorUpgradeCheckStatus.notConfigured =>
            StoreUpgradeCheckStatus.notConfigured,
          AndroidVendorUpgradeCheckStatus.unsupportedVendor =>
            StoreUpgradeCheckStatus.unsupported,
          AndroidVendorUpgradeCheckStatus.failed =>
            StoreUpgradeCheckStatus.failed,
        },
        release: release == null
            ? null
            : UpgradeRelease(
                version: UpgradeVersion(
                  versionName: release.versionName,
                  buildNumber: release.versionCode,
                ),
                releaseNotes: release.releaseNotes,
                storeTarget: release.storeTarget,
                fileSizeBytes: release.fileSizeBytes,
              ),
        errorCode: result.errorCode,
      );
    } finally {
      service.close();
    }
  }

  Future<StoreUpgradeCheckResult> _checkIos() async {
    final config = configuration.ios;
    if (config == null) {
      return const StoreUpgradeCheckResult(
        status: StoreUpgradeCheckStatus.notConfigured,
      );
    }
    final current = await UpgradeKitPlatform.instance.getIosAppVersion();
    final client = _client ?? http.Client();
    try {
      final response = await client
          .get(
            Uri.https('itunes.apple.com', '/lookup', {
              'id': config.appId,
              'country': config.country,
              'entity': 'software',
            }),
          )
          .timeout(config.requestTimeout);
      if (response.statusCode != 200) {
        return const StoreUpgradeCheckResult(
          status: StoreUpgradeCheckStatus.failed,
          errorCode: 'http-error',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['results'] is! List) {
        return _invalidResponse();
      }
      final results = decoded['results'] as List;
      if (results.isEmpty) {
        return const StoreUpgradeCheckResult(
          status: StoreUpgradeCheckStatus.failed,
          errorCode: 'not-found',
        );
      }
      Map? app;
      for (final candidate in results) {
        if (candidate is Map &&
            candidate['trackId'].toString() == config.appId) {
          app = candidate;
          break;
        }
      }
      if (app == null || app['version'] is! String) return _invalidResponse();
      final version = app['version'] as String;
      final comparison = _compareMarketingVersions(version, current);
      if (comparison == null) {
        return const StoreUpgradeCheckResult(
          status: StoreUpgradeCheckStatus.failed,
          errorCode: 'invalid-version',
        );
      }
      return StoreUpgradeCheckResult(
        status: comparison > 0
            ? StoreUpgradeCheckStatus.updateAvailable
            : StoreUpgradeCheckStatus.noUpdate,
        release: UpgradeRelease(
          version: UpgradeVersion(versionName: version),
          releaseNotes: app['releaseNotes'] is String
              ? app['releaseNotes'] as String
              : '',
          storeTarget: config.appId,
        ),
      );
    } on FormatException {
      return _invalidResponse();
    } finally {
      if (_client == null) client.close();
    }
  }

  Future<StoreUpgradeCheckResult> _checkOhos() async {
    if (configuration.ohos == null) {
      return const StoreUpgradeCheckResult(
        status: StoreUpgradeCheckStatus.notConfigured,
      );
    }
    final available = await UpgradeKitPlatform.instance.checkAppUpdate();
    return StoreUpgradeCheckResult(
      status: available == AppUpdateAvailability.updateAvailable
          ? StoreUpgradeCheckStatus.updateAvailable
          : StoreUpgradeCheckStatus.noUpdate,
    );
  }

  /// Explicit user-confirmed store navigation or native AppGallery dialog.
  Future<StoreUpgradeActionResult> requestStoreUpgrade() async {
    final native = UpgradeKitPlatform.instance;
    switch (platform) {
      case StoreUpgradePlatform.android:
        final config = configuration.android;
        if (config == null) {
          throw StateError('Android store is not configured.');
        }
        return await native.openCurrentAppStore(config.fallbackTarget) ==
                StoreLaunchResult.launched
            ? StoreUpgradeActionResult.storeLaunched
            : StoreUpgradeActionResult.failed;
      case StoreUpgradePlatform.ios:
        final config = configuration.ios;
        if (config == null) throw StateError('iOS store is not configured.');
        return await native.openStore(config.appId) ==
                StoreLaunchResult.launched
            ? StoreUpgradeActionResult.storeLaunched
            : StoreUpgradeActionResult.failed;
      case StoreUpgradePlatform.ohos:
        if (configuration.ohos == null) {
          throw StateError('OHOS store is not configured.');
        }
        return await native.showUpdateDialog() == UpdateDialogResult.shown
            ? StoreUpgradeActionResult.dialogShown
            : StoreUpgradeActionResult.notShown;
      case StoreUpgradePlatform.unsupported:
        throw UnsupportedError('No store adapter for the current platform.');
    }
  }
}

StoreUpgradeCheckResult _invalidResponse() => const StoreUpgradeCheckResult(
  status: StoreUpgradeCheckStatus.failed,
  errorCode: 'invalid-response',
);

int? _compareMarketingVersions(String remote, String current) {
  final pattern = RegExp(r'[0-9]+(?:\.[0-9]+){0,2}');
  bool valid(String value) => pattern.matchAsPrefix(value)?.end == value.length;
  if (!valid(remote) || !valid(current)) return null;
  final left = remote.split('.').map(BigInt.parse).toList();
  final right = current.split('.').map(BigInt.parse).toList();
  for (var i = 0; i < 3; i++) {
    final compared = (i < left.length ? left[i] : BigInt.zero).compareTo(
      i < right.length ? right[i] : BigInt.zero,
    );
    if (compared != 0) return compared;
  }
  return 0;
}
