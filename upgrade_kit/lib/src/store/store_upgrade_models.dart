import '../check/upgrade_models.dart';

enum StoreUpgradePlatform { android, ios, ohos, unsupported }

enum StoreUpgradeCheckStatus {
  updateAvailable,
  noUpdate,
  notConfigured,
  unsupported,
  failed,
}

enum StoreUpgradeActionResult { storeLaunched, dialogShown, notShown, failed }

final class StoreUpgradeCheckResult {
  const StoreUpgradeCheckResult({
    required this.status,
    this.release,
    this.errorCode,
  });
  final StoreUpgradeCheckStatus status;

  /// AppGallery checks report availability without release metadata.
  final UpgradeRelease? release;
  final String? errorCode;
}

/// Compatibility name for [StoreUpgradePlatform].
typedef UpgradeStorePlatform = StoreUpgradePlatform;

/// Compatibility name for [StoreUpgradeCheckStatus].
typedef StoreUpdateStatus = StoreUpgradeCheckStatus;

/// Compatibility name for [StoreUpgradeCheckResult].
typedef StoreUpdateResult = StoreUpgradeCheckResult;

/// Compatibility name for [StoreUpgradeActionResult].
typedef StoreUpdateAction = StoreUpgradeActionResult;
