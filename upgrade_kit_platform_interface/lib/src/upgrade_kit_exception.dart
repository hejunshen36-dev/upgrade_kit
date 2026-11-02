/// A platform failure reported by upgrade_kit.
final class UpgradeKitException implements Exception {
  const UpgradeKitException({
    required this.code,
    required this.message,
    this.details,
  });

  final String code;
  final String message;
  final Object? details;

  @override
  String toString() => 'UpgradeKitException($code, $message)';
}
