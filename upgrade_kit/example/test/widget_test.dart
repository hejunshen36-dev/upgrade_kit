import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upgrade_kit_example/main.dart';

void main() {
  testWidgets('shows every upgrade capability', (tester) async {
    await tester.pumpWidget(const UpgradeKitExampleApp());

    for (final label in [
      'Check configured store',
      'Update through configured store',
      'Check demo service',
      'Check host service and prompt',
      'Cancel download',
      'Retry download',
      'Verify and install',
      'Check OHOS store update',
      'Show OHOS update dialog',
      'Install APK',
      'Open app store',
      'No operation has run.',
    ]) {
      try {
        await tester.scrollUntilVisible(
          find.text(label),
          100,
          scrollable: find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
      } on Object catch (error) {
        fail('Could not reach "$label": $error');
      }
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('No operation has run.'), findsOneWidget);
  });

  testWidgets('checks a host source without native registration', (
    tester,
  ) async {
    await tester.pumpWidget(const UpgradeKitExampleApp());
    await tester.tap(find.text('Check demo service'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('updateAvailable: 1.1.0'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('updateAvailable: 1.1.0'), findsOneWidget);
  });
}
