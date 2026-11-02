import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'android_store_context.dart';
import 'upgrade_kit_exception.dart';
import 'upgrade_kit_platform.dart';
import 'upgrade_results.dart';

/// Method-channel implementation shared by native platform packages.
final class MethodChannelUpgradeKit extends UpgradeKitPlatform {
  MethodChannelUpgradeKit({MethodChannel? methodChannel})
    : methodChannel = methodChannel ?? const MethodChannel('upgrade_kit');

  @visibleForTesting
  final MethodChannel methodChannel;

  @override
  Future<String> getIosAppVersion() async {
    final value = await _invoke('getIosAppVersion');
    if (value.trim().isEmpty) throw _invalidResponse('getIosAppVersion', value);
    return value;
  }

  @override
  Future<AppUpdateAvailability> checkAppUpdate() async {
    final value = await _invoke('checkAppUpdate');
    return switch (value) {
      'updateAvailable' => AppUpdateAvailability.updateAvailable,
      'noUpdate' => AppUpdateAvailability.noUpdate,
      _ => throw _invalidResponse('checkAppUpdate', value),
    };
  }

  @override
  Future<UpdateDialogResult> showUpdateDialog() async {
    final value = await _invoke('showUpdateDialog');
    return switch (value) {
      'shown' => UpdateDialogResult.shown,
      'notShown' => UpdateDialogResult.notShown,
      _ => throw _invalidResponse('showUpdateDialog', value),
    };
  }

  @override
  Future<ApkInstallResult> installApk(String filePath) async {
    final normalizedPath = filePath.trim();
    if (normalizedPath.isEmpty) {
      throw ArgumentError.value(filePath, 'filePath', 'must not be empty');
    }
    final value = await _invoke('installApk', <String, Object?>{
      'filePath': normalizedPath,
    });
    return switch (value) {
      'launched' => ApkInstallResult.launched,
      'fileNotFound' => ApkInstallResult.fileNotFound,
      'permissionRequired' => ApkInstallResult.permissionRequired,
      'failed' => ApkInstallResult.failed,
      _ => throw _invalidResponse('installApk', value),
    };
  }

  @override
  Future<StoreLaunchResult> openStore(String target) async {
    final normalizedTarget = target.trim();
    if (normalizedTarget.isEmpty) {
      throw ArgumentError.value(target, 'target', 'must not be empty');
    }
    final value = await _invoke('openStore', <String, Object?>{
      'target': normalizedTarget,
    });
    return switch (value) {
      'launched' => StoreLaunchResult.launched,
      'failed' => StoreLaunchResult.failed,
      _ => throw _invalidResponse('openStore', value),
    };
  }

  @override
  Future<AndroidStoreContext> getAndroidStoreContext() async {
    final value = await _invokeValue<Map<Object?, Object?>>(
      'getAndroidStoreContext',
    );
    final vendor = switch (value['vendor']) {
      'huawei' => AndroidStoreVendor.huawei,
      'honor' => AndroidStoreVendor.honor,
      'xiaomi' => AndroidStoreVendor.xiaomi,
      'vivo' => AndroidStoreVendor.vivo,
      'oppo' => AndroidStoreVendor.oppo,
      'samsung' => AndroidStoreVendor.samsung,
      'unknown' => AndroidStoreVendor.unknown,
      _ => null,
    };
    final packageName = value['packageName'];
    final currentVersionName = value['currentVersionName'];
    final currentVersionCode = value['currentVersionCode'];
    if (vendor == null ||
        packageName is! String ||
        packageName.trim().isEmpty ||
        currentVersionName is! String ||
        currentVersionCode is! String ||
        currentVersionCode.trim().isEmpty) {
      throw _invalidResponse('getAndroidStoreContext', value);
    }
    return AndroidStoreContext(
      vendor: vendor,
      packageName: packageName,
      currentVersionName: currentVersionName,
      currentVersionCode: currentVersionCode,
    );
  }

  @override
  Future<StoreLaunchResult> openCurrentAppStore(String? fallbackTarget) async {
    final normalizedFallback = fallbackTarget?.trim();
    if (fallbackTarget != null && normalizedFallback!.isEmpty) {
      throw ArgumentError.value(
        fallbackTarget,
        'fallbackTarget',
        'must be null or non-empty',
      );
    }
    final value = await _invoke('openCurrentAppStore', <String, Object?>{
      'fallbackTarget': normalizedFallback,
    });
    return switch (value) {
      'launched' => StoreLaunchResult.launched,
      'failed' => StoreLaunchResult.failed,
      _ => throw _invalidResponse('openCurrentAppStore', value),
    };
  }

  Future<String> _invoke(String method, [Map<String, Object?>? arguments]) =>
      _invokeValue<String>(method, arguments);

  Future<T> _invokeValue<T>(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      final value = await methodChannel.invokeMethod<Object?>(
        method,
        arguments,
      );
      if (value is! T) {
        throw _invalidResponse(method, value);
      }
      return value;
    } on PlatformException catch (error) {
      if (error.code == 'unsupported') {
        throw UnsupportedError('$method is not supported on this platform.');
      }
      throw UpgradeKitException(
        code: error.code,
        message: error.message ?? '$method failed.',
        details: error.details,
      );
    }
  }

  UpgradeKitException _invalidResponse(String method, Object? value) {
    return UpgradeKitException(
      code: 'invalid-response',
      message: '$method returned an unsupported result: $value',
      details: value,
    );
  }
}
