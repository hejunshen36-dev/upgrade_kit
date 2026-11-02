import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('upgrade_kit packages do not depend on PipeX', () {
    final workspace = Directory('..');
    final files = workspace
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (file) =>
              !file.path.contains('/.dart_tool/') &&
              !file.path.contains('/build/') &&
              !file.path.contains('/example/') &&
              !file.path.contains('/test/') &&
              (file.path.endsWith('.dart') ||
                  file.path.endsWith('.yaml') ||
                  file.path.endsWith('.kt') ||
                  file.path.endsWith('.swift') ||
                  file.path.endsWith('.ets') ||
                  file.path.endsWith('.json5')),
        );

    for (final file in files) {
      final source = file.readAsStringSync();
      expect(source, isNot(contains('pipex_kit')), reason: file.path);
      expect(source, isNot(contains('PipeXHostApi')), reason: file.path);
      expect(source, isNot(contains('fusion/common')), reason: file.path);
    }
  });
}
