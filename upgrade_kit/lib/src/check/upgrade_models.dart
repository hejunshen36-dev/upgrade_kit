/// An application version supplied by the host or an upgrade source.
final class UpgradeVersion {
  const UpgradeVersion({required this.versionName, this.buildNumber});

  final String versionName;
  final String? buildNumber;
}

/// Host-owned context for a release query. No native calls are needed.
final class UpgradeCheckRequest {
  UpgradeCheckRequest({
    required String appId,
    required this.currentVersion,
    this.platform,
    this.channel,
    this.locale = 'en-US',
  }) : appId = appId.trim() {
    if (this.appId.isEmpty) {
      throw ArgumentError.value(appId, 'appId', 'must not be empty');
    }
  }

  final String appId;
  final UpgradeVersion currentVersion;

  /// Optional backend-specific platform identifier, for example `android`.
  final String? platform;
  final String? channel;
  final String locale;
}

/// Normalized release data. URLs are metadata; checking never launches them.
final class UpgradeRelease {
  const UpgradeRelease({
    required this.version,
    this.releaseNotes = '',
    this.downloadUri,
    this.storeTarget,
    this.fileSizeBytes,
  });

  final UpgradeVersion version;
  final String releaseNotes;
  final Uri? downloadUri;

  /// A target for the existing platform-specific `openStore` API.
  final String? storeTarget;
  final int? fileSizeBytes;
}

enum UpgradeCheckStatus { updateAvailable, noUpdate, failed }

/// Check outcomes keep confirmed no-update results distinct from failures.
final class UpgradeCheckResult {
  const UpgradeCheckResult.updateAvailable(UpgradeRelease this.release)
    : status = UpgradeCheckStatus.updateAvailable,
      errorCode = null,
      errorMessage = null;

  const UpgradeCheckResult.noUpdate({this.release})
    : status = UpgradeCheckStatus.noUpdate,
      errorCode = null,
      errorMessage = null;

  const UpgradeCheckResult.failed({
    required String this.errorCode,
    required String this.errorMessage,
    this.release,
  }) : status = UpgradeCheckStatus.failed;

  final UpgradeCheckStatus status;
  final UpgradeRelease? release;
  final String? errorCode;
  final String? errorMessage;
}
