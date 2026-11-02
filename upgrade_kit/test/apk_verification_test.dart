import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upgrade_kit/upgrade_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const kit = UpgradeKit();
  const channel = MethodChannel('upgrade_kit');
  late Directory directory;
  late File file;
  var installs = 0;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('apk-verify-');
    file = await File('${directory.path}/app.apk').writeAsString('abc');
    installs = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          installs++;
          return 'permissionRequired';
        });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });
  for (final checksum in <String?>[
    null,
    '',
    ' \t ',
    ' 900150983CD24FB0D6963F7D28E17F72 ',
  ]) {
    test('ready and install with optional checksum: $checksum', () async {
      expect(await kit.isApkReady(file.path, expectedMd5: checksum), isTrue);
      await kit.installApk(file.path, expectedMd5: checksum);
      await kit.installApk(file.path, expectedMd5: checksum);
      expect(installs, 2);
      expect(await file.exists(), isTrue);
    });
  }
  test('omitted checksum skips hashing', () async {
    expect(await kit.isApkReady(file.path), isTrue);
    await kit.installApk(file.path);
    expect(installs, 1);
  });
  test(
    'verification can retain mismatched and empty files without installing',
    () async {
      expect(
        await kit.verifyCachedApk(
          file.path,
          expectedMd5: 'bad',
          deleteInvalid: false,
        ),
        isFalse,
      );
      expect(await file.readAsString(), 'abc');
      await file.writeAsString('');
      expect(
        await kit.verifyCachedApk(file.path, deleteInvalid: false),
        isFalse,
      );
      expect(await file.exists(), isTrue);
      expect(installs, 0);
      // The legacy API still cleans up invalid files by default.
      expect(await kit.isApkReady(file.path), isFalse);
      expect(await file.exists(), isFalse);
    },
  );
  test(
    'tampered package never reaches native install and is removed',
    () async {
      expect(
        await kit.installApk(file.path, expectedMd5: 'bad'),
        ApkInstallResult.failed,
      );
      expect(installs, 0);
      expect(await file.exists(), isFalse);
    },
  );
  test(
    'missing and empty files are not ready even without a checksum',
    () async {
      await file.writeAsString('');
      expect(await kit.isApkReady(file.path), isFalse);
      expect(await file.exists(), isFalse);
      expect(await kit.isApkReady(file.path), isFalse);
    },
  );
}
