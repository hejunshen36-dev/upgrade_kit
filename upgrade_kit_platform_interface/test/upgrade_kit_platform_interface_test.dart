import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:upgrade_kit_platform_interface/upgrade_kit_platform_interface.dart';

class _FakeUpgradeKitPlatform extends UpgradeKitPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<AppUpdateAvailability> checkAppUpdate() async =>
      AppUpdateAvailability.updateAvailable;

  @override
  Future<ApkInstallResult> installApk(String filePath) async =>
      ApkInstallResult.launched;

  @override
  Future<StoreLaunchResult> openStore(String target) async =>
      StoreLaunchResult.launched;

  @override
  Future<AndroidStoreContext> getAndroidStoreContext() async =>
      const AndroidStoreContext(
        vendor: AndroidStoreVendor.honor,
        packageName: 'com.example.app',
        currentVersionName: '1.0.0',
        currentVersionCode: '100',
      );

  @override
  Future<StoreLaunchResult> openCurrentAppStore(String? fallbackTarget) async =>
      StoreLaunchResult.launched;

  @override
  Future<UpdateDialogResult> showUpdateDialog() async =>
      UpdateDialogResult.shown;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reads iOS app version and validates native response', () async {
    const channel = MethodChannel('upgrade_kit');
    final platform = MethodChannelUpgradeKit();
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'getIosAppVersion');
          return '1.2.3';
        });
    expect(await platform.getIosAppVersion(), '1.2.3');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => '');
    await expectLater(
      platform.getIosAppVersion(),
      throwsA(isA<UpgradeKitException>()),
    );
  });

  test('platform instance accepts verified fakes', () {
    final initial = UpgradeKitPlatform.instance;
    final fake = _FakeUpgradeKitPlatform();
    addTearDown(() => UpgradeKitPlatform.instance = initial);

    UpgradeKitPlatform.instance = fake;

    expect(UpgradeKitPlatform.instance, same(fake));
  });

  group('method channel result mapping', () {
    const channel = MethodChannel('upgrade_kit');
    final platform = MethodChannelUpgradeKit();

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('maps all supported native results', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            return switch (call.method) {
              'checkAppUpdate' => 'updateAvailable',
              'showUpdateDialog' => 'shown',
              'installApk' => 'permissionRequired',
              'openStore' => 'launched',
              'getAndroidStoreContext' => <String, Object?>{
                'vendor': 'honor',
                'packageName': 'com.example.app',
                'currentVersionName': '1.2.3',
                'currentVersionCode': '123',
              },
              'openCurrentAppStore' => 'launched',
              _ => throw MissingPluginException(),
            };
          });

      expect(
        await platform.checkAppUpdate(),
        AppUpdateAvailability.updateAvailable,
      );
      expect(await platform.showUpdateDialog(), UpdateDialogResult.shown);
      expect(
        await platform.installApk('/tmp/app.apk'),
        ApkInstallResult.permissionRequired,
      );
      expect(await platform.openStore('123456'), StoreLaunchResult.launched);
      final context = await platform.getAndroidStoreContext();
      expect(context.vendor, AndroidStoreVendor.honor);
      expect(context.packageName, 'com.example.app');
      expect(context.currentVersionName, '1.2.3');
      expect(context.currentVersionCode, '123');
      expect(
        await platform.openCurrentAppStore('https://example.com/app'),
        StoreLaunchResult.launched,
      );
    });

    test('rejects invalid native results', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => 'unexpected');

      await expectLater(
        platform.checkAppUpdate(),
        throwsA(
          isA<UpgradeKitException>().having(
            (error) => error.code,
            'code',
            'invalid-response',
          ),
        ),
      );
    });

    test('maps unsupported platform errors', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) => throw PlatformException(code: 'unsupported'),
          );

      await expectLater(
        platform.checkAppUpdate(),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('preserves missing registration diagnostics', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) => throw MissingPluginException('not registered'),
          );

      await expectLater(
        platform.checkAppUpdate(),
        throwsA(isA<MissingPluginException>()),
      );
    });

    test('maps wrong native value types to invalid-response', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => 42);

      for (final operation in <Future<Object> Function()>[
        platform.checkAppUpdate,
        platform.getAndroidStoreContext,
      ]) {
        await expectLater(
          operation(),
          throwsA(
            isA<UpgradeKitException>().having(
              (error) => error.code,
              'code',
              'invalid-response',
            ),
          ),
        );
      }
    });

    test(
      'validates path and store target before invoking native code',
      () async {
        await expectLater(
          platform.installApk('  '),
          throwsA(isA<ArgumentError>()),
        );
        await expectLater(
          platform.openStore(''),
          throwsA(isA<ArgumentError>()),
        );
        await expectLater(
          platform.openCurrentAppStore('  '),
          throwsA(isA<ArgumentError>()),
        );
      },
    );

    test('sends nullable fallback for the current Android store', () async {
      MethodCall? captured;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            captured = call;
            return 'failed';
          });

      expect(
        await platform.openCurrentAppStore(null),
        StoreLaunchResult.failed,
      );
      expect(captured?.method, 'openCurrentAppStore');
      expect(captured?.arguments, <String, Object?>{'fallbackTarget': null});
    });
  });
}
