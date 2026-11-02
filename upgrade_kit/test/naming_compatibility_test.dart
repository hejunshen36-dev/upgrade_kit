import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upgrade_kit/upgrade_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('upgrade_kit');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'checkAppUpdate' => 'updateAvailable',
            'showUpdateDialog' => 'shown',
            'installApk' => 'permissionRequired',
            _ => throw MissingPluginException(),
          };
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'old store constructors, enum names and methods stay compatible',
    () async {
      final legacy = UpgradeService(
        configuration: const UpgradeConfiguration(
          ohos: OhosStoreUpgradeConfiguration(),
        ),
        platform: UpgradeStorePlatform.ohos,
      );
      final current = StoreUpgradeService(
        configuration: legacy.configuration,
        platform: StoreUpgradePlatform.ohos,
      );
      final StoreUpdateResult oldResult = await legacy.checkStoreUpdate();
      expect(oldResult.status, StoreUpdateStatus.updateAvailable);
      expect((await current.checkStoreUpgrade()).status, oldResult.status);
      expect(await legacy.performStoreUpdate(), StoreUpdateAction.dialogShown);
      expect(
        await current.requestStoreUpgrade(),
        StoreUpgradeActionResult.dialogShown,
      );
      expect(
        const StoreUpdateResult(status: StoreUpdateStatus.noUpdate),
        isA<StoreUpgradeCheckResult>(),
      );
      expect(
        await legacy.installApk('/app.apk'),
        ApkInstallResult.permissionRequired,
      );
    },
  );

  test('explicit OHOS methods keep the existing native protocol', () async {
    const kit = UpgradeKit();
    expect(await kit.checkOhosStoreUpdate(), await kit.checkAppUpdate());
    expect(await kit.showOhosUpdateDialog(), await kit.showUpdateDialog());
    expect(calls.map((call) => call.method), [
      'checkAppUpdate',
      'checkAppUpdate',
      'showUpdateDialog',
      'showUpdateDialog',
    ]);
  });

  test('snapshot artifact and download readiness preserve legacy names', () {
    final artifact = ApkArtifact(version: '2');
    final current = ApkUpgradeSnapshot(
      artifact: artifact,
      state: ApkDownloadState.completed,
    );
    final legacy = ApkUpgradeSnapshot(
      package: artifact,
      state: ApkDownloadState.completed,
    );
    expect(current.artifact, same(artifact));
    expect(current.package, same(artifact));
    expect(legacy.artifact, same(artifact));
    expect(legacy.package, same(artifact));
    expect(current.isDownloadReady, isTrue);
    expect(current.isReady, current.isDownloadReady);
    expect(const ApkUpgradeSnapshot().isDownloadReady, isFalse);
  });

  test(
    'controller aliases preserve cached reuse and explicit installation',
    () async {
      final directory = await Directory.systemTemp.createTemp('upgrade-names-');
      final controller = ApkUpgradeController(
        cacheDirectory: () async => directory.path,
      );
      addTearDown(() async {
        await controller.dispose();
        await directory.delete(recursive: true);
      });
      final oldArtifact = ApkUpgradePackage(version: '2');
      final artifact = ApkArtifact(version: '2');
      expect(oldArtifact.sameArtifact(artifact), isTrue);
      expect(
        await controller.packagePath(artifact),
        await controller.artifactPath(artifact),
      );
      await File(
        await controller.packagePath(artifact),
      ).writeAsString('cached APK');
      final ApkUpgradePreparation oldResult = await controller.prepare(
        oldArtifact,
      );
      expect(oldResult, ApkUpgradePreparation.ready);
      expect(
        await controller.prepareDownload(artifact),
        ApkPrepareResult.ready,
      );
      expect(await controller.isReady(oldArtifact), isTrue);
      expect(await controller.verifyCachedApk(artifact), isTrue);
      expect(calls, isEmpty);
      expect(
        await controller.install(artifact),
        ApkInstallResult.permissionRequired,
      );
      expect(calls.single.method, 'installApk');
    },
  );

  test('verification alias retains invalid-file cleanup', () async {
    final directory = await Directory.systemTemp.createTemp(
      'upgrade-verify-name-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = await File('${directory.path}/app.apk').writeAsString('abc');
    const kit = UpgradeKit();
    expect(await kit.verifyCachedApk(file.path), isTrue);
    expect(await kit.isApkReady(file.path), isTrue);
    expect(
      await kit.verifyCachedApk(file.path, expectedMd5: 'invalid'),
      isFalse,
    );
    expect(await file.exists(), isFalse);
    expect(calls, isEmpty);
  });
}
