import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS package implements upgrade_kit and owns store launching', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final podspec = File('ios/upgrade_kit_ios.podspec').readAsStringSync();
    final source = File(
      'ios/Classes/UpgradeKitIosPlugin.swift',
    ).readAsStringSync();

    expect(pubspec, contains('implements: upgrade_kit'));
    expect(podspec, contains("s.platform = :ios, '12.0'"));
    expect(podspec, isNot(contains('example.com')));
    expect(podspec, isNot(contains('Your Company')));
    expect(source, contains('FlutterMethodChannel(name: "upgrade_kit"'));
    expect(source, contains('case "openStore"'));
    expect(source, contains('itms-apps://'));
    expect(source, contains('https://apps.apple.com/app/id'));
    expect(source, contains('DispatchQueue.main.async'));
    expect(source, contains('CharacterSet.decimalDigits'));
    expect(source, isNot(contains('PipeX')));
    expect(source, isNot(contains('pipex')));
  });
}
