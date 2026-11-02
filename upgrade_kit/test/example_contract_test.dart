import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('example depends only on the app-facing package', () {
    final pubspec = File('example/pubspec.yaml').readAsStringSync();
    final source = File('example/lib/main.dart').readAsStringSync();

    expect(pubspec, contains('upgrade_kit:'));
    expect(pubspec, isNot(contains('upgrade_kit_android:')));
    expect(pubspec, isNot(contains('upgrade_kit_ios:')));
    expect(pubspec, isNot(contains('upgrade_kit_ohos:')));
    expect(source, contains("package:upgrade_kit/upgrade_kit.dart"));
    expect(source, contains('Check OHOS store update'));
    expect(source, contains('Show OHOS update dialog'));
    expect(source, contains('Install APK'));
    expect(source, contains('Open app store'));
  });
}
