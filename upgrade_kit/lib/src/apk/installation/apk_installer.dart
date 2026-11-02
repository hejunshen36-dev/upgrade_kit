import 'package:upgrade_kit_platform_interface/upgrade_kit_platform_interface.dart';
import '../verification/apk_verifier.dart';

Future<ApkInstallResult> installApkFile(
  String filePath, {
  String? expectedMd5,
}) async {
  // Preserve the native platform result when no checksum is requested.
  if (expectedMd5 != null &&
      expectedMd5.trim().isNotEmpty &&
      !await isApkFileReady(filePath, expectedMd5: expectedMd5)) {
    return ApkInstallResult.failed;
  }
  return UpgradeKitPlatform.instance.installApk(filePath);
}
