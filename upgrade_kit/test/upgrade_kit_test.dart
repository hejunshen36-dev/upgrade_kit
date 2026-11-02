import 'package:upgrade_kit/upgrade_kit.dart';
import 'package:upgrade_kit_platform_interface/upgrade_kit_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakeUpgradeKitPlatform extends UpgradeKitPlatform
    with MockPlatformInterfaceMixin {
  _FakeUpgradeKitPlatform();

  final calls = <String>[];
  final AndroidStoreContext context = const AndroidStoreContext(
    vendor: AndroidStoreVendor.samsung,
    packageName: 'com.example.app',
    currentVersionName: '1.0.0',
    currentVersionCode: '100',
  );

  @override
  Future<AppUpdateAvailability> checkAppUpdate() async {
    calls.add('checkAppUpdate');
    return AppUpdateAvailability.noUpdate;
  }

  @override
  Future<ApkInstallResult> installApk(String filePath) async {
    calls.add('installApk:$filePath');
    return ApkInstallResult.launched;
  }

  @override
  Future<AndroidStoreContext> getAndroidStoreContext() async {
    calls.add('getAndroidStoreContext');
    return context;
  }

  @override
  Future<StoreLaunchResult> openCurrentAppStore(String? fallbackTarget) async {
    calls.add('openCurrentAppStore:$fallbackTarget');
    return StoreLaunchResult.launched;
  }

  @override
  Future<StoreLaunchResult> openStore(String target) async {
    calls.add('openStore:$target');
    return StoreLaunchResult.launched;
  }

  @override
  Future<UpdateDialogResult> showUpdateDialog() async {
    calls.add('showUpdateDialog');
    return UpdateDialogResult.notShown;
  }
}

void main() {
  test('public API forwards typed operations to the platform', () async {
    final initial = UpgradeKitPlatform.instance;
    final fake = _FakeUpgradeKitPlatform();
    addTearDown(() => UpgradeKitPlatform.instance = initial);
    UpgradeKitPlatform.instance = fake;
    const kit = UpgradeKit();

    expect(await kit.checkAppUpdate(), AppUpdateAvailability.noUpdate);
    expect(await kit.showUpdateDialog(), UpdateDialogResult.notShown);
    expect(await kit.installApk('/data/app.apk'), ApkInstallResult.launched);
    expect(await kit.openStore('123456'), StoreLaunchResult.launched);
    expect(await kit.getAndroidStoreContext(), fake.context);
    expect(
      await kit.openCurrentAppStore(
        fallbackTarget: 'market://details?id=com.example.app',
      ),
      StoreLaunchResult.launched,
    );
    expect(fake.calls, <String>[
      'checkAppUpdate',
      'showUpdateDialog',
      'installApk:/data/app.apk',
      'openStore:123456',
      'getAndroidStoreContext',
      'openCurrentAppStore:market://details?id=com.example.app',
    ]);
  });

  test(
    'vendor query exposes unsupported Android vendors without I/O',
    () async {
      final initial = UpgradeKitPlatform.instance;
      final fake = _FakeUpgradeKitPlatform();
      addTearDown(() => UpgradeKitPlatform.instance = initial);
      UpgradeKitPlatform.instance = fake;

      final result = await const UpgradeKit().checkAndroidVendorUpgrade(
        AndroidVendorUpgradeConfiguration(),
      );

      expect(result.status, AndroidVendorUpgradeCheckStatus.unsupportedVendor);
      expect(result.context, fake.context);
      expect(fake.calls, ['getAndroidStoreContext']);
    },
  );
}
