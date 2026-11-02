import 'package:upgrade_kit_platform_interface/upgrade_kit_platform_interface.dart';

/// Outcome of checking the current Android vendor's application store.
enum AndroidVendorUpgradeCheckStatus {
  updateAvailable,
  noUpdate,
  notConfigured,
  unsupportedVendor,
  failed,
}

/// Normalized release information returned by an Android vendor store.
final class AndroidVendorReleaseInfo {
  const AndroidVendorReleaseInfo({
    required this.vendor,
    required this.versionName,
    required this.versionCode,
    required this.releaseNotes,
    required this.fileSizeBytes,
    required this.storeTarget,
  });

  final AndroidStoreVendor vendor;
  final String versionName;
  final String? versionCode;
  final String releaseNotes;
  final int? fileSizeBytes;
  final String storeTarget;
}

/// Typed result that keeps failures distinct from a confirmed no-update state.
final class AndroidVendorUpgradeCheckResult {
  const AndroidVendorUpgradeCheckResult({
    required this.status,
    required this.context,
    this.release,
    this.errorCode,
    this.errorMessage,
  });

  final AndroidVendorUpgradeCheckStatus status;
  final AndroidStoreContext context;
  final AndroidVendorReleaseInfo? release;
  final String? errorCode;
  final String? errorMessage;
}

/// Credentials and application identifiers for Android vendor APIs.
///
/// These values are transmitted by the client and therefore cannot be treated
/// as secrets against application reverse engineering. They are never stored or
/// logged by upgrade_kit.
final class AndroidVendorUpgradeConfiguration {
  AndroidVendorUpgradeConfiguration({
    this.huawei,
    this.honor,
    this.xiaomi,
    this.vivo,
    this.oppo,
    this.requestTimeout = const Duration(seconds: 15),
  }) {
    if (requestTimeout <= Duration.zero) {
      throw ArgumentError.value(
        requestTimeout,
        'requestTimeout',
        'must be greater than zero',
      );
    }
  }

  final HuaweiVendorUpgradeConfiguration? huawei;
  final HonorVendorUpgradeConfiguration? honor;
  final XiaomiVendorUpgradeConfiguration? xiaomi;
  final VivoVendorUpgradeConfiguration? vivo;
  final OppoVendorUpgradeConfiguration? oppo;
  final Duration requestTimeout;

  Object? forVendor(AndroidStoreVendor vendor) => switch (vendor) {
    AndroidStoreVendor.huawei => huawei,
    AndroidStoreVendor.honor => honor,
    AndroidStoreVendor.xiaomi => xiaomi,
    AndroidStoreVendor.vivo => vivo,
    AndroidStoreVendor.oppo => oppo,
    AndroidStoreVendor.samsung || AndroidStoreVendor.unknown => null,
  };
}

final class HuaweiVendorUpgradeConfiguration {
  HuaweiVendorUpgradeConfiguration({
    required String clientId,
    required String clientSecret,
    required String appId,
  }) : clientId = _required(clientId, 'clientId'),
       clientSecret = _required(clientSecret, 'clientSecret'),
       appId = _required(appId, 'appId');

  final String clientId;
  final String clientSecret;
  final String appId;
}

final class HonorVendorUpgradeConfiguration {
  HonorVendorUpgradeConfiguration({
    required String clientId,
    required String clientSecret,
    required String appId,
  }) : clientId = _required(clientId, 'clientId'),
       clientSecret = _required(clientSecret, 'clientSecret'),
       appId = _required(appId, 'appId');

  final String clientId;
  final String clientSecret;
  final String appId;
}

final class XiaomiVendorUpgradeConfiguration {
  XiaomiVendorUpgradeConfiguration({
    required String userName,
    required String passwordOrPrivateKey,
    required String rsaPublicKeyPem,
  }) : userName = _required(userName, 'userName'),
       passwordOrPrivateKey = _required(
         passwordOrPrivateKey,
         'passwordOrPrivateKey',
       ),
       rsaPublicKeyPem = _required(rsaPublicKeyPem, 'rsaPublicKeyPem');

  final String userName;
  final String passwordOrPrivateKey;
  final String rsaPublicKeyPem;
}

final class VivoVendorUpgradeConfiguration {
  VivoVendorUpgradeConfiguration({
    required String account,
    required String secret,
  }) : account = _required(account, 'account'),
       secret = _required(secret, 'secret');

  final String account;
  final String secret;
}

final class OppoVendorUpgradeConfiguration {
  OppoVendorUpgradeConfiguration({
    required String clientId,
    required String clientSecret,
  }) : clientId = _required(clientId, 'clientId'),
       clientSecret = _required(clientSecret, 'clientSecret');

  final String clientId;
  final String clientSecret;
}

String _required(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
  return normalized;
}

/// Compatibility name for [AndroidVendorUpgradeCheckStatus].
typedef AndroidVendorUpdateStatus = AndroidVendorUpgradeCheckStatus;

/// Compatibility name for [AndroidVendorUpgradeCheckResult].
typedef AndroidVendorUpdateResult = AndroidVendorUpgradeCheckResult;
