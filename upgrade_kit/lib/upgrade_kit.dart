library;

import 'src/apk/installation/apk_installer.dart';
import 'src/apk/verification/apk_verifier.dart';

import 'package:upgrade_kit_platform_interface/upgrade_kit_platform_interface.dart';

import 'src/store/android_vendor/android_vendor_upgrade.dart';
import 'src/store/android_vendor/android_vendor_upgrade_service.dart';
import 'src/check/upgrade_checker.dart';
import 'src/check/upgrade_models.dart';
import 'src/check/upgrade_source.dart';
import 'src/check/upgrade_version_comparator.dart';
import 'src/apk/download/apk_download_models.dart';
import 'src/apk/download/apk_downloader.dart';

export 'package:upgrade_kit_platform_interface/upgrade_kit_platform_interface.dart'
    show
        AndroidStoreContext,
        AndroidStoreVendor,
        ApkInstallResult,
        AppUpdateAvailability,
        StoreLaunchResult,
        UpdateDialogResult,
        UpgradeKitException;
export 'src/store/android_vendor/android_vendor_upgrade.dart';
export 'src/check/upgrade_models.dart';
export 'src/check/upgrade_source.dart';
export 'src/check/upgrade_version_comparator.dart';
export 'src/apk/download/apk_download_models.dart';
export 'src/apk/apk_upgrade_controller.dart';
export 'src/store/store_upgrade_configuration.dart';
export 'src/store/store_upgrade_models.dart';
export 'src/store/store_upgrade_service.dart';
export 'src/compat/legacy_upgrade_service.dart' show UpgradeService;

/// Platform-independent entry point for native app upgrade capabilities.
final class UpgradeKit {
  const UpgradeKit();

  /// Creates an idle task. The plugin checks any supplied MD5
  /// before completion. The host explicitly calls [installApk]. No installation is automatic.
  ApkDownloadTask createApkDownload(ApkDownloadRequest request) =>
      createApkDownloadTask(request);

  /// Checks a host-owned source on any platform without invoking native code.
  ///
  /// A timeout stops waiting; the host owns cancellation of its network request.
  Future<UpgradeCheckResult> checkForUpdate({
    required UpgradeSource source,
    required UpgradeCheckRequest request,
    Duration timeout = const Duration(seconds: 15),
    UpgradeVersionComparator? comparator,
  }) => checkForUpgrade(
    source: source,
    request: request,
    timeout: timeout,
    comparator: comparator,
  );

  Future<AppUpdateAvailability> checkOhosStoreUpdate() =>
      UpgradeKitPlatform.instance.checkAppUpdate();

  Future<UpdateDialogResult> showOhosUpdateDialog() =>
      UpgradeKitPlatform.instance.showUpdateDialog();

  /// Checks nonempty app-owned bytes and optional MD5, deleting invalid files
  /// by default. Set [deleteInvalid] to false to retain invalid files.
  /// A true result does not imply host signature verification or installation.
  Future<bool> verifyCachedApk(
    String filePath, {
    String? expectedMd5,
    bool deleteInvalid = true,
  }) => isApkFileReady(
    filePath,
    expectedMd5: expectedMd5,
    deleteInvalid: deleteInvalid,
  );

  /// Installs explicitly; a supplied nonblank MD5 is checked before native launch.
  Future<ApkInstallResult> installApk(String filePath, {String? expectedMd5}) =>
      installApkFile(filePath, expectedMd5: expectedMd5);

  Future<StoreLaunchResult> openStore(String target) =>
      UpgradeKitPlatform.instance.openStore(target);

  Future<AndroidStoreContext> getAndroidStoreContext() =>
      UpgradeKitPlatform.instance.getAndroidStoreContext();

  Future<StoreLaunchResult> openCurrentAppStore({String? fallbackTarget}) =>
      UpgradeKitPlatform.instance.openCurrentAppStore(fallbackTarget);

  Future<AndroidVendorUpgradeCheckResult> checkAndroidVendorUpgrade(
    AndroidVendorUpgradeConfiguration configuration, {
    String locale = 'zh-CN',
  }) async {
    final service = AndroidVendorUpgradeService(
      platform: UpgradeKitPlatform.instance,
    );
    try {
      return await service.check(configuration, locale: locale);
    } finally {
      service.close();
    }
  }

  /// Compatibility alias for the OHOS-only native store check.
  Future<AppUpdateAvailability> checkAppUpdate() => checkOhosStoreUpdate();

  /// Compatibility alias for the OHOS-only native dialog.
  Future<UpdateDialogResult> showUpdateDialog() => showOhosUpdateDialog();

  /// Compatibility alias; invalid app-owned files are deleted.
  Future<bool> isApkReady(String filePath, {String? expectedMd5}) =>
      verifyCachedApk(filePath, expectedMd5: expectedMd5);

  /// Compatibility alias for [checkAndroidVendorUpgrade].
  Future<AndroidVendorUpgradeCheckResult> checkAndroidVendorUpdate(
    AndroidVendorUpgradeConfiguration configuration, {
    String locale = 'zh-CN',
  }) => checkAndroidVendorUpgrade(configuration, locale: locale);
}
