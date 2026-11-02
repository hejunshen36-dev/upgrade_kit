import 'package:upgrade_kit_platform_interface/upgrade_kit_platform_interface.dart';
import '../apk/download/apk_download_models.dart';
import '../apk/download/apk_downloader.dart';
import '../apk/installation/apk_installer.dart';
import '../apk/verification/apk_verifier.dart';
import '../store/store_upgrade_models.dart';
import '../store/store_upgrade_service.dart';

export '../store/store_upgrade_service.dart';

/// Compatibility facade. Use [StoreUpgradeService] for stores and
/// UpgradeKit or ApkUpgradeController for APK operations in new integrations.
final class UpgradeService extends StoreUpgradeService {
  UpgradeService({required super.configuration, super.platform, super.client});

  Future<StoreUpgradeCheckResult> checkStoreUpdate() => checkStoreUpgrade();
  Future<StoreUpgradeActionResult> performStoreUpdate() =>
      requestStoreUpgrade();

  ApkDownloadTask createApkDownload(ApkDownloadRequest request) =>
      createApkDownloadTask(request);

  /// Compatibility check: deletes invalid app-owned files; blank MD5 skips hashing.
  Future<bool> isApkReady(String filePath, {String? expectedMd5}) =>
      isApkFileReady(filePath, expectedMd5: expectedMd5);

  /// Installs explicitly; a supplied nonblank MD5 is checked before native launch.
  Future<ApkInstallResult> installApk(String filePath, {String? expectedMd5}) =>
      installApkFile(filePath, expectedMd5: expectedMd5);
}
