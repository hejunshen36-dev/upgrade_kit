import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'method_channel_upgrade_kit.dart';
import 'android_store_context.dart';
import 'upgrade_results.dart';

/// Platform contract implemented by upgrade_kit platform packages.
abstract class UpgradeKitPlatform extends PlatformInterface {
  UpgradeKitPlatform() : super(token: _token);

  static final Object _token = Object();
  static UpgradeKitPlatform _instance = MethodChannelUpgradeKit();

  static UpgradeKitPlatform get instance => _instance;

  static set instance(UpgradeKitPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<AppUpdateAvailability> checkAppUpdate() {
    throw UnimplementedError('checkAppUpdate() has not been implemented.');
  }

  Future<String> getIosAppVersion() {
    throw UnimplementedError('getIosAppVersion() has not been implemented.');
  }

  Future<UpdateDialogResult> showUpdateDialog() {
    throw UnimplementedError('showUpdateDialog() has not been implemented.');
  }

  Future<ApkInstallResult> installApk(String filePath) {
    throw UnimplementedError('installApk() has not been implemented.');
  }

  Future<StoreLaunchResult> openStore(String target) {
    throw UnimplementedError('openStore() has not been implemented.');
  }

  Future<AndroidStoreContext> getAndroidStoreContext() {
    throw UnimplementedError(
      'getAndroidStoreContext() has not been implemented.',
    );
  }

  Future<StoreLaunchResult> openCurrentAppStore(String? fallbackTarget) {
    throw UnimplementedError('openCurrentAppStore() has not been implemented.');
  }
}
