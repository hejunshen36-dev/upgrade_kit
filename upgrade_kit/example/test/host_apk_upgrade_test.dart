import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:upgrade_kit/upgrade_kit.dart';
import 'package:upgrade_kit_platform_interface/upgrade_kit_platform_interface.dart';
import 'package:upgrade_kit_example/host_apk_upgrade.dart';

class _Installer extends UpgradeKitPlatform {
  final files = <String>[];
  @override
  Future<ApkInstallResult> installApk(String path) async {
    files.add(path);
    return ApkInstallResult.launched;
  }
}

void main() {
  test(
    'host checks, downloads and verifies before explicit installer invocation',
    () async {
      final root = await Directory.systemTemp.createTemp('host-apk-flow-');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
        await root.delete(recursive: true);
      });
      final original = UpgradeKitPlatform.instance;
      final installer = _Installer();
      UpgradeKitPlatform.instance = installer;
      addTearDown(() => UpgradeKitPlatform.instance = original);
      final origin = 'http://127.0.0.1:${server.port}';
      server.listen((request) async {
        if (request.uri.path == '/release') {
          request.response.write(
            jsonEncode({
              'versionCode': '2',
              'versionName': '1.1.0',
              'downloadUrl': '$origin/app.apk',
              'sha256':
                  'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
              'releaseNotes': 'Fixes',
            }),
          );
        } else {
          request.response.add(utf8.encode('abc'));
        }
        await request.response.close();
      });
      final host = HostApkUpgrade();
      final release = await host.check(
        Uri.parse('$origin/release'),
        currentBuild: BigInt.one,
      );
      expect(release?.versionName, '1.1.0');
      expect(
        await host.check(
          Uri.parse('$origin/release'),
          currentBuild: BigInt.from(2),
        ),
        isNull,
      );
      final task = host.createDownload(release!, '${root.path}/update.apk');
      addTearDown(task.dispose);
      final result = await task.start();
      expect(result.status, ApkDownloadState.completed);
      expect(installer.files, isEmpty);
      expect(
        await host.verifyAndInstall(result, release),
        ApkInstallResult.launched,
      );
      expect(installer.files, [result.filePath]);
      installer.files.clear();
      await File(result.filePath!).writeAsString('tampered');
      await expectLater(
        host.verifyAndInstall(result, release),
        throwsStateError,
      );
      expect(installer.files, isEmpty);
    },
  );
}
