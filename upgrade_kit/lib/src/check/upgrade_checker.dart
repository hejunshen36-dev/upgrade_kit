import 'dart:async';

import 'upgrade_models.dart';
import 'upgrade_source.dart';
import 'upgrade_version_comparator.dart';

/// Stateless orchestration shared by all host-supplied query sources.
Future<UpgradeCheckResult> checkForUpgrade({
  required UpgradeSource source,
  required UpgradeCheckRequest request,
  required Duration timeout,
  UpgradeVersionComparator? comparator,
}) async {
  if (timeout <= Duration.zero) {
    throw ArgumentError.value(timeout, 'timeout', 'must be greater than zero');
  }

  final UpgradeRelease? release;
  try {
    // Future.sync also captures a source that throws before returning a Future.
    release = await Future.sync(() => source.fetch(request)).timeout(timeout);
  } on TimeoutException {
    return const UpgradeCheckResult.failed(
      errorCode: 'timeout',
      errorMessage: 'The upgrade query timed out.',
    );
  } on Object {
    return const UpgradeCheckResult.failed(
      errorCode: 'source-error',
      errorMessage: 'The upgrade source failed.',
    );
  }
  if (release == null) return const UpgradeCheckResult.noUpdate();

  final int? comparison;
  try {
    comparison = (comparator ?? compareUpgradeVersions)(
      release.version,
      request.currentVersion,
    );
  } on Object {
    return UpgradeCheckResult.failed(
      errorCode: 'comparison-error',
      errorMessage: 'The version comparator failed.',
      release: release,
    );
  }
  if (comparison == null) {
    return UpgradeCheckResult.failed(
      errorCode: 'invalid-version',
      errorMessage: 'The release and current versions cannot be compared.',
      release: release,
    );
  }
  return comparison > 0
      ? UpgradeCheckResult.updateAvailable(release)
      : UpgradeCheckResult.noUpdate(release: release);
}
