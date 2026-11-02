/// Configuration for a foreground, full-file APK download.
final class ApkDownloadRequest {
  ApkDownloadRequest({
    required this.url,
    required String filePath,
    this.expectedMd5,
    Map<String, String> headers = const {},
    this.connectTimeout = const Duration(seconds: 15),
    this.receiveTimeout = const Duration(seconds: 30),
  }) : filePath = filePath.trim(),
       headers = Map.unmodifiable(headers) {
    if (!['http', 'https'].contains(url.scheme) ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty) {
      throw ArgumentError(
        'A valid HTTP(S) URL without embedded credentials is required.',
      );
    }
    if (this.filePath.isEmpty) {
      throw ArgumentError('filePath must not be empty.');
    }
    if (connectTimeout <= Duration.zero || receiveTimeout <= Duration.zero) {
      throw ArgumentError('Download timeouts must be positive.');
    }
    for (final name in headers.keys) {
      if ([
        'range',
        'accept-encoding',
        'host',
        'content-length',
      ].contains(name.toLowerCase())) {
        throw ArgumentError('The downloader manages $name.');
      }
    }
  }

  /// Optional MD5. Null, empty and whitespace-only values skip verification.
  final String? expectedMd5;
  final Uri url;
  final String filePath;
  final Map<String, String> headers;
  final Duration connectTimeout;
  final Duration receiveTimeout;
}

enum ApkDownloadState {
  idle,
  connecting,
  downloading,
  cancelling,
  cancelled,

  /// File transfer and any requested MD5 check finished. Host verification and
  /// installation are separate operations.
  completed,
  failed,
  verifying,
}

final class ApkDownloadProgress {
  const ApkDownloadProgress({
    required this.state,
    this.receivedBytes = 0,
    this.totalBytes,
    this.attempt = 0,
  });
  final ApkDownloadState state;
  final int receivedBytes;
  final int? totalBytes;
  final int attempt;
  double? get fraction => totalBytes == null || totalBytes! <= 0
      ? null
      : receivedBytes / totalBytes!;
}

/// A completed file is verified against the optional MD5, never automatic installation.
final class ApkDownloadResult {
  const ApkDownloadResult.completed(String this.filePath)
    : status = ApkDownloadState.completed,
      errorCode = null;
  const ApkDownloadResult.cancelled()
    : status = ApkDownloadState.cancelled,
      filePath = null,
      errorCode = null;
  const ApkDownloadResult.failed(String this.errorCode)
    : status = ApkDownloadState.failed,
      filePath = null;
  final ApkDownloadState status;
  final String? filePath;
  final String? errorCode;
}

abstract interface class ApkDownloadTask {
  ApkDownloadRequest get request;
  ApkDownloadProgress get snapshot;
  Stream<ApkDownloadProgress> get progress;
  Future<ApkDownloadResult> start();

  /// Cancels this attempt and waits for its IO to be cleaned up.
  /// Once the final file commit starts, completion wins over cancellation.
  Future<void> cancel();

  /// Explicitly retries a failed/cancelled attempt from byte zero.
  Future<ApkDownloadResult> retry();
  Future<void> dispose();
}
