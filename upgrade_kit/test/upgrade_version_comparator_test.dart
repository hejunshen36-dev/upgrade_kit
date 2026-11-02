import 'package:flutter_test/flutter_test.dart';
import 'package:upgrade_kit/upgrade_kit.dart';

void main() {
  int? compare(String remote, String current) => compareUpgradeVersions(
    UpgradeVersion(versionName: remote),
    UpgradeVersion(versionName: current),
  );

  test('orders numeric version components and ignores build metadata', () {
    expect(compare('1.10.0', '1.9.9'), greaterThan(0));
    expect(compare('2.0.0', '10.0.0'), lessThan(0));
    expect(compare('1.0.0+100', '1.0.0+200'), 0);
  });

  test('follows SemVer pre-release precedence', () {
    const ordered = [
      '1.0.0-alpha',
      '1.0.0-alpha.1',
      '1.0.0-alpha.beta',
      '1.0.0-beta',
      '1.0.0-beta.2',
      '1.0.0-beta.11',
      '1.0.0-rc.1',
      '1.0.0',
    ];
    for (var index = 1; index < ordered.length; index++) {
      expect(compare(ordered[index], ordered[index - 1]), greaterThan(0));
      expect(compare(ordered[index - 1], ordered[index]), lessThan(0));
    }
    expect(compare('1.0.0-beta', '1.0.0-beta'), 0);
  });

  test('rejects malformed and ambiguous versions', () {
    for (final value in [
      '',
      'v1.0.0',
      '1.0',
      '01.0.0',
      '1.0.0-01',
      '1.0.0-',
      '1.0.0+',
      '1.0.0-a..b',
      '1.0.0+meta..data',
      '1.0.0\n',
    ]) {
      expect(compare(value, '1.0.0'), isNull, reason: value);
      expect(compare('1.0.0', value), isNull, reason: value);
    }
  });

  test('prefers non-negative build numbers without integer overflow', () {
    expect(
      compareUpgradeVersions(
        const UpgradeVersion(
          versionName: 'legacy',
          buildNumber: '999999999999999999999999',
        ),
        const UpgradeVersion(versionName: '2.0.0', buildNumber: '100'),
      ),
      greaterThan(0),
    );
    expect(
      compareUpgradeVersions(
        const UpgradeVersion(versionName: '1.0.0', buildNumber: '-1'),
        const UpgradeVersion(versionName: '1.0.0', buildNumber: '1'),
      ),
      isNull,
    );
    expect(
      compareUpgradeVersions(
        const UpgradeVersion(versionName: '1.0.0', buildNumber: 'bad'),
        const UpgradeVersion(versionName: '1.0.0', buildNumber: '1'),
      ),
      isNull,
    );
  });

  test('falls back to SemVer when either build number is absent', () {
    expect(
      compareUpgradeVersions(
        const UpgradeVersion(versionName: '1.1.0', buildNumber: '10'),
        const UpgradeVersion(versionName: '1.0.0'),
      ),
      greaterThan(0),
    );
  });
}
