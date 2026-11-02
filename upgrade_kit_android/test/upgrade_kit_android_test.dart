import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android package implements upgrade_kit with an isolated provider', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final buildScript = File('android/build.gradle').readAsStringSync();
    final manifest = File(
      'android/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final paths = File(
      'android/src/main/res/xml/upgrade_kit_file_paths.xml',
    ).readAsStringSync();
    final provider = File(
      'android/src/main/kotlin/com/egeio/upgrade_kit_android/'
      'UpgradeFileProvider.kt',
    ).readAsStringSync();

    expect(pubspec, contains('implements: upgrade_kit'));
    expect(buildScript, contains('minSdk = 21'));
    expect(manifest, contains(r'${applicationId}.upgrade_kit.provider'));
    expect(
      manifest,
      contains('com.egeio.upgrade_kit_android.UpgradeFileProvider'),
    );
    expect(provider, contains('import androidx.core.content.FileProvider'));
    expect(provider, contains('class UpgradeFileProvider : FileProvider()'));
    expect(manifest, contains('@xml/upgrade_kit_file_paths'));
    expect(paths, contains('<files-path'));
    expect(paths, contains('<cache-path'));
    expect(paths, contains('<external-files-path'));
    expect(paths, isNot(contains('<root-path')));
  });

  test('Android native implementation installs APKs and opens stores', () {
    final source = File(
      'android/src/main/kotlin/com/egeio/upgrade_kit_android/'
      'UpgradeKitAndroidPlugin.kt',
    ).readAsStringSync();

    expect(
      source,
      contains('MethodChannel(binding.binaryMessenger, "upgrade_kit")'),
    );
    expect(source, contains('"installApk"'));
    expect(source, contains('"openStore"'));
    expect(source, contains('"getAndroidStoreContext"'));
    expect(source, contains('"openCurrentAppStore"'));
    expect(source, contains('AndroidStoreResolver.detectVendor'));
    expect(source, contains('AndroidStoreResolver.resolveTargets'));
    expect(source, contains('FileProvider.getUriForFile'));
    expect(source, contains('canRequestPackageInstalls'));
    expect(source, contains('ACTION_MANAGE_UNKNOWN_APP_SOURCES'));
    expect(source, contains('permissionSettingsFailed'));
    expect(source, isNot(contains('PipeX')));
    expect(source, isNot(contains('pipex')));
  });
}
