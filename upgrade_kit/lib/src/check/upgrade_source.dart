import 'upgrade_models.dart';

/// Fetches normalized release data using the host's network and auth stack.
abstract interface class UpgradeSource {
  /// Returns null only when the source confirms there is no release.
  /// Throw on authentication, transport, or malformed response failures.
  Future<UpgradeRelease?> fetch(UpgradeCheckRequest request);
}

/// Adapts a host callback without imposing an HTTP client or JSON schema.
final class CallbackUpgradeSource implements UpgradeSource {
  const CallbackUpgradeSource(this.callback);

  final Future<UpgradeRelease?> Function(UpgradeCheckRequest request) callback;

  @override
  Future<UpgradeRelease?> fetch(UpgradeCheckRequest request) =>
      callback(request);
}
