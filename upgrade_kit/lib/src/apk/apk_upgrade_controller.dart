import 'dart:async';

import 'package:upgrade_kit_platform_interface/upgrade_kit_platform_interface.dart';

import 'download/apk_download_models.dart';
import 'download/apk_downloader.dart';
import 'installation/apk_installer.dart';
import 'verification/apk_verifier.dart';

/// Host-selected artifact identity. Authentication and business policy stay outside.
final class ApkArtifact {
  ApkArtifact({required this.version, this.url, String? expectedMd5})
    : expectedMd5 = expectedMd5?.trim().toLowerCase() ?? '';

  final String version;
  final String? url;

  /// Empty means no checksum verification is requested.
  final String expectedMd5;

  bool sameArtifact(ApkArtifact? other) =>
      other != null &&
      version == other.version &&
      expectedMd5 == other.expectedMd5;
}

enum ApkPrepareResult { started, alreadyRunning, ready, busy, failed }

final class ApkUpgradeSnapshot {
  const ApkUpgradeSnapshot({
    ApkArtifact? artifact,
    ApkArtifact? package,
    this.state = ApkDownloadState.idle,
    this.receivedBytes = 0,
    this.totalBytes,
    this.errorCode,
  }) : assert(
         artifact == null || package == null,
         'Pass either artifact or package, not both.',
       ),
       artifact = artifact ?? package;

  /// The artifact whose download/cache preparation this snapshot describes.
  final ApkArtifact? artifact;

  /// Compatibility name for [artifact].
  ApkArtifact? get package => artifact;

  /// Download/cache preparation only. Completed does not mean installed,
  /// nor does it establish that the host has performed its own verification.
  final ApkDownloadState state;
  final int receivedBytes;
  final int? totalBytes;
  final String? errorCode;
  bool get isRunning => const [
    ApkDownloadState.connecting,
    ApkDownloadState.downloading,
    ApkDownloadState.verifying,
    ApkDownloadState.cancelling,
  ].contains(state);

  /// Last observed download/cache readiness, not a fresh file verification.
  bool get isDownloadReady => state == ApkDownloadState.completed;

  /// Compatibility name for [isDownloadReady].
  bool get isReady => isDownloadReady;
  double? get fraction => isDownloadReady
      ? 1
      : totalBytes == null || totalBytes! <= 0
      ? null
      : receivedBytes / totalBytes!;
}

/// One foreground upgrade session. Cache reuse and lifecycle are generic;
/// choosing a version, replacing a different task and installing are explicit.
final class ApkUpgradeController {
  ApkUpgradeController({
    required this.cacheDirectory,
    this.filePrefix = 'upgrade',
  });

  final Future<String> Function() cacheDirectory;
  final String filePrefix;
  final _events = StreamController<ApkUpgradeSnapshot>.broadcast();
  ApkUpgradeSnapshot _snapshot = const ApkUpgradeSnapshot();
  ApkUpgradeSnapshot get snapshot => _snapshot;
  ApkDownloadTask? _task;
  Future<void>? _completion;
  Future<void> _tail = Future<void>.value();
  Future<void>? _disposal;
  bool _disposing = false;
  bool _disposed = false;
  FutureOr<Map<String, String>> Function()? _headers;

  /// Each subscription receives the current state, including terminal states.
  Stream<ApkUpgradeSnapshot> get states => Stream.multi((listener) {
    if (_disposed) {
      listener.close();
      return;
    }
    final subscription = _events.stream.listen(
      listener.add,
      onError: listener.addError,
      onDone: listener.close,
    );
    listener.add(_snapshot);
    listener.onCancel = subscription.cancel;
  });

  void _ensureUsable() {
    if (_disposing || _disposed) {
      throw StateError('Upgrade controller is disposed.');
    }
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    _ensureUsable();
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  void _publish(ApkUpgradeSnapshot value) {
    _snapshot = value;
    if (!_events.isClosed) _events.add(value);
  }

  /// Stable names preserve the caller's namespace; path segments are escaped.
  Future<String> artifactPath(ApkArtifact artifact) async {
    final directory = await cacheDirectory();
    final name =
        '${Uri.encodeComponent(filePrefix)}-'
        '${Uri.encodeComponent(artifact.version)}-'
        '${Uri.encodeComponent(artifact.expectedMd5)}.apk';
    return '${Uri.directory(directory).toFilePath()}$name';
  }

  bool isRunning(ApkArtifact artifact) =>
      artifact.sameArtifact(_snapshot.artifact) && _snapshot.isRunning;

  /// Checks nonempty bytes and optional MD5, publishing readiness when valid.
  /// Invalid files are deleted by default. Set [deleteInvalid] to false to retain
  /// them. This may publish state even when deletion is disabled.
  Future<bool> verifyCachedApk(
    ApkArtifact artifact, {
    bool deleteInvalid = true,
  }) => _enqueue(() async {
    if (isRunning(artifact)) return false;
    final ready = await isApkFileReady(
      await artifactPath(artifact),
      expectedMd5: artifact.expectedMd5,
      deleteInvalid: deleteInvalid,
    );
    if (ready && !_snapshot.isRunning) {
      _publish(
        ApkUpgradeSnapshot(
          artifact: artifact,
          state: ApkDownloadState.completed,
        ),
      );
    }
    return ready;
  });

  /// Reuses a verified cached APK or immediately starts downloading.
  Future<ApkPrepareResult> prepareDownload(
    ApkArtifact artifact, {
    FutureOr<Map<String, String>> Function()? headers,
    bool replaceExisting = false,
  }) => _enqueue(() async {
    if (isRunning(artifact)) return ApkPrepareResult.alreadyRunning;
    if (_snapshot.isRunning) {
      if (!replaceExisting) return ApkPrepareResult.busy;
      await _stop();
    }
    _headers = headers;
    _publish(
      ApkUpgradeSnapshot(
        artifact: artifact,
        state: ApkDownloadState.connecting,
      ),
    );
    try {
      final path = await artifactPath(artifact);
      if (await isApkFileReady(path, expectedMd5: artifact.expectedMd5)) {
        _publish(
          ApkUpgradeSnapshot(
            artifact: artifact,
            state: ApkDownloadState.completed,
          ),
        );
        return ApkPrepareResult.ready;
      }
      // Validate URL and request options before starting IO.
      final request = ApkDownloadRequest(
        url: Uri.parse(artifact.url?.trim() ?? ''),
        filePath: path,
        expectedMd5: artifact.expectedMd5,
        headers: await headers?.call() ?? const {},
      );
      final task = createApkDownloadTask(request);
      _task = task;
      final subscription = task.progress.listen((progress) {
        if (!identical(_task, task) || _disposed) return;
        if (const [
          ApkDownloadState.connecting,
          ApkDownloadState.downloading,
          ApkDownloadState.verifying,
          ApkDownloadState.cancelling,
        ].contains(progress.state)) {
          _publish(
            ApkUpgradeSnapshot(
              artifact: artifact,
              state: progress.state,
              receivedBytes: progress.receivedBytes,
              totalBytes: progress.totalBytes,
            ),
          );
        }
      });
      _completion = _run(task, artifact, subscription);
      return ApkPrepareResult.started;
    } on Object catch (error) {
      _publish(
        ApkUpgradeSnapshot(
          artifact: artifact,
          state: ApkDownloadState.failed,
          errorCode: error is ArgumentError || error is FormatException
              ? 'invalid-request'
              : 'prepare-failed',
        ),
      );
      return ApkPrepareResult.failed;
    }
  });

  Future<void> _run(
    ApkDownloadTask task,
    ApkArtifact artifact,
    StreamSubscription<ApkDownloadProgress> subscription,
  ) async {
    ApkDownloadResult result;
    try {
      result = await task.start();
    } on Object {
      result = const ApkDownloadResult.failed('download-failed');
    }
    // Drain/remove the listener before publishing the terminal state.
    await subscription.cancel();
    if (identical(_task, task) && !_disposed) {
      _publish(
        ApkUpgradeSnapshot(
          artifact: artifact,
          state: result.status,
          receivedBytes: task.snapshot.receivedBytes,
          totalBytes: task.snapshot.totalBytes,
          errorCode: result.errorCode,
        ),
      );
    }
    await task.dispose();
    if (identical(_task, task)) _task = null;
  }

  Future<void> _stop() async {
    await _task?.cancel();
    await _completion;
  }

  Future<void> cancel() => _enqueue(_stop);

  /// A new full-file attempt; never automatic or a background retry.
  Future<ApkPrepareResult> retry() {
    _ensureUsable();
    final artifact = _snapshot.artifact;
    if (artifact == null ||
        !const [
          ApkDownloadState.failed,
          ApkDownloadState.cancelled,
        ].contains(_snapshot.state)) {
      throw StateError('Only failed or cancelled upgrades can retry.');
    }
    return prepareDownload(artifact, headers: _headers);
  }

  /// Reports only the optional checksum phase, ending before native installation.
  Future<ApkInstallResult> install(
    ApkArtifact artifact, {
    FutureOr<void> Function(bool verifying)? onVerificationChanged,
  }) => _enqueue(() async {
    if (isRunning(artifact)) return ApkInstallResult.failed;
    try {
      final path = await artifactPath(artifact);
      final verifyMd5 = artifact.expectedMd5.isNotEmpty;
      bool ready;
      try {
        if (verifyMd5) await onVerificationChanged?.call(true);
        ready = await isApkFileReady(path, expectedMd5: artifact.expectedMd5);
      } finally {
        if (verifyMd5) await onVerificationChanged?.call(false);
      }
      if (!ready) return ApkInstallResult.fileNotFound;
      // File integrity was checked above, including optional MD5.
      return await installApkFile(path);
    } on Object {
      return ApkInstallResult.failed;
    }
  });

  /// Compatibility name for [artifactPath]; preserves existing cache filenames.
  Future<String> packagePath(ApkArtifact package) => artifactPath(package);

  /// Compatibility alias. This operation may immediately start downloading.
  Future<ApkPrepareResult> prepare(
    ApkArtifact artifact, {
    FutureOr<Map<String, String>> Function()? headers,
    bool replaceExisting = false,
  }) => prepareDownload(
    artifact,
    headers: headers,
    replaceExisting: replaceExisting,
  );

  /// Compatibility alias; verification may delete invalid files and publish state.
  Future<bool> isReady(ApkArtifact artifact) => verifyCachedApk(artifact);

  Future<void> dispose() => _disposal ??= _dispose();
  Future<void> _dispose() async {
    _disposing = true;
    await _tail;
    await _stop();
    _disposed = true;
    // A paused page must not block resource cleanup.
    unawaited(_events.close());
  }
}

/// Compatibility name for [ApkArtifact].
typedef ApkUpgradePackage = ApkArtifact;

/// Compatibility name for [ApkPrepareResult].
typedef ApkUpgradePreparation = ApkPrepareResult;
