/// Android application stores supported by upgrade_kit.
enum AndroidStoreVendor { huawei, honor, xiaomi, vivo, oppo, samsung, unknown }

/// Android device and host-application facts used for an update check.
final class AndroidStoreContext {
  const AndroidStoreContext({
    required this.vendor,
    required this.packageName,
    required this.currentVersionName,
    required this.currentVersionCode,
  });

  final AndroidStoreVendor vendor;
  final String packageName;
  final String currentVersionName;

  /// Decimal Android version code encoded as a string to preserve 64-bit values.
  final String currentVersionCode;
}
