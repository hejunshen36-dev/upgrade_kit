import 'android_vendor/android_vendor_upgrade.dart';

final class StoreUpgradeConfiguration {
  const StoreUpgradeConfiguration({this.android, this.ios, this.ohos});
  final AndroidStoreUpgradeConfiguration? android;
  final IosStoreUpgradeConfiguration? ios;
  final OhosStoreUpgradeConfiguration? ohos;
}

final class AndroidStoreUpgradeConfiguration {
  const AndroidStoreUpgradeConfiguration({
    required this.vendors,
    this.fallbackTarget,
    this.locale = 'zh-CN',
  });
  final AndroidVendorUpgradeConfiguration vendors;
  final String? fallbackTarget;
  final String locale;
}

final class IosStoreUpgradeConfiguration {
  IosStoreUpgradeConfiguration({
    required String appId,
    String country = 'us',
    this.requestTimeout = const Duration(seconds: 15),
  }) : appId = appId.trim(),
       country = country.trim().toLowerCase() {
    if (!RegExp(r'^[0-9]+$').hasMatch(this.appId)) {
      throw ArgumentError('appId must be a numeric App Store ID.');
    }
    if (!RegExp(r'^[a-z]{2}$').hasMatch(this.country)) {
      throw ArgumentError('country must be a two-letter storefront code.');
    }
    if (requestTimeout <= Duration.zero) {
      throw ArgumentError('requestTimeout must be positive.');
    }
  }
  final String appId;
  final String country;
  final Duration requestTimeout;
}

/// Enables the native AppGallery adapter; identity comes from the host ability.
final class OhosStoreUpgradeConfiguration {
  const OhosStoreUpgradeConfiguration();
}

/// Compatibility name for [StoreUpgradeConfiguration].
typedef UpgradeConfiguration = StoreUpgradeConfiguration;
