import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('OHOS package implements upgrade_kit with AppGallery Kit', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final ohPackage = File('ohos/oh-package.json5').readAsStringSync();
    final source = File(
      'ohos/src/main/ets/components/plugin/UpgradeKitOhosPlugin.ets',
    ).readAsStringSync();

    expect(pubspec, contains('implements: upgrade_kit'));
    expect(ohPackage, contains('HarmonyOS implementation of upgrade_kit.'));
    expect(ohPackage, isNot(contains('Please describe')));
    expect(source, contains("from '@kit.AppGalleryKit'"));
    expect(source, contains('AbilityPluginBinding'));
    expect(source, contains('"checkAppUpdate"'));
    expect(source, contains('"showUpdateDialog"'));
    expect(source, contains('updateManager.checkAppUpdate'));
    expect(source, contains('updateManager.showUpdateDialog'));
    expect(source, contains('"updateAvailable"'));
    expect(source, contains('"noUpdate"'));
    expect(source, contains('"shown"'));
    expect(source, contains('"notShown"'));
    expect(source, isNot(contains('PipeX')));
    expect(source, isNot(contains('pipex')));
    expect(source, isNot(contains('fusion/common')));
  });
}
