import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'apk_download_models.dart';
import '../verification/apk_verifier_io.dart';

ApkDownloadTask createApkDownloadTask(ApkDownloadRequest request) =>
    _IoApkDownloadTask(request);

final class _Cancelled implements Exception {}

final class _DownloadFailure implements Exception {
  const _DownloadFailure(this.code);
  final String code;
}

final class _IoApkDownloadTask implements ApkDownloadTask {
  _IoApkDownloadTask(this.request) {
    if (!Uri.file(request.filePath, windows: Platform.isWindows).isAbsolute) {
      throw ArgumentError('The APK destination must be an absolute path.');
    }
  }
  static final _destinations = <String>{};
  @override
  final ApkDownloadRequest request;
  final _events = StreamController<ApkDownloadProgress>.broadcast();
  @override
  ApkDownloadProgress snapshot = const ApkDownloadProgress(
    state: ApkDownloadState.idle,
  );
  @override
  Stream<ApkDownloadProgress> get progress => _events.stream;
  bool _disposed = false;
  bool _disposing = false;
  Future<void>? _disposeFuture;
  bool _cancelled = false;
  bool _committing = false;
  Completer<void>? _cancelSignal;
  HttpClient? _client;
  Future<ApkDownloadResult>? _running;

  @override
  Future<ApkDownloadResult> start() {
    _ensureUsable();
    if (snapshot.state != ApkDownloadState.idle) {
      throw StateError('Use retry after a failed or cancelled attempt.');
    }
    return _begin();
  }

  @override
  Future<ApkDownloadResult> retry() {
    _ensureUsable();
    if (_running != null ||
        ![
          ApkDownloadState.failed,
          ApkDownloadState.cancelled,
        ].contains(snapshot.state)) {
      throw StateError('Only a cleaned-up failed or cancelled task can retry.');
    }
    return _begin();
  }

  void _ensureUsable() {
    if (_disposed || _disposing) {
      throw StateError('The download task has been disposed.');
    }
  }

  Future<ApkDownloadResult> _begin() {
    _cancelled = false;
    _committing = false;
    _cancelSignal = Completer<void>();
    snapshot = ApkDownloadProgress(
      state: ApkDownloadState.connecting,
      attempt: snapshot.attempt + 1,
    );
    _events.add(snapshot);
    // _run initially yields at filesystem IO; publishing the Future is synchronous.
    final future = _run();
    _running = future;
    return future;
  }

  void _emit(ApkDownloadState state, {int? bytes, int? total}) {
    snapshot = ApkDownloadProgress(
      state: state,
      receivedBytes: bytes ?? snapshot.receivedBytes,
      totalBytes: total ?? snapshot.totalBytes,
      attempt: snapshot.attempt,
    );
    if (!_events.isClosed) _events.add(snapshot);
  }

  void _checkCancelled() {
    if (_cancelled) throw _Cancelled();
  }

  Future<T> _wait<T>(Future<T> operation) => Future.any([
    operation,
    _cancelSignal!.future.then<T>((_) => throw _Cancelled()),
  ]);

  @override
  Future<void> cancel() async {
    if (_disposed) return;
    final running = _running;
    if (running == null) {
      if (snapshot.state == ApkDownloadState.idle) {
        _emit(ApkDownloadState.cancelled);
      }
      return;
    }
    if (!_committing && !_cancelled) {
      _cancelled = true;
      _emit(ApkDownloadState.cancelling);
      _cancelSignal!.complete();
      _client?.close(force: true);
    }
    await running;
  }

  @override
  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    _disposing = true;
    await cancel();
    _disposed = true;
    // A paused listener must not keep IO cleanup/disposal waiting forever.
    unawaited(_events.close());
  }

  Future<HttpClientResponse> _open() async {
    final client = HttpClient()
      ..autoUncompress = false
      ..connectionTimeout = request.connectTimeout;
    _client = client;
    var url = request.url;
    var headers = request.headers;
    for (var redirect = 0; redirect <= 5; redirect++) {
      _checkCancelled();
      final pending = client.getUrl(url);
      final cancellation = _cancelSignal!;
      // If cancellation wins during DNS/connect, abort a late request as well.
      unawaited(
        pending.then<void>((value) {
          if (cancellation.isCompleted) {
            value.abort();
          }
        }, onError: (Object _) {}),
      );
      final outgoing = await _wait(pending.timeout(request.connectTimeout));
      outgoing.followRedirects = false;
      headers.forEach(outgoing.headers.set);
      outgoing.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final response = await _wait(
        outgoing.close().timeout(request.connectTimeout),
      );
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location == null || redirect == 5) {
          throw const _DownloadFailure('redirect-error');
        }
        final next = url.resolve(location);
        if (!['http', 'https'].contains(next.scheme) ||
            next.host.isEmpty ||
            next.userInfo.isNotEmpty ||
            (url.scheme == 'https' && next.scheme != 'https')) {
          throw const _DownloadFailure('redirect-error');
        }
        // Do not forward host credentials (including custom headers) to a CDN.
        if (url.origin != next.origin) headers = const {};
        await _wait(response.drain<void>().timeout(request.receiveTimeout));
        url = next;
        continue;
      }
      if (response.statusCode != 200) {
        throw const _DownloadFailure('http-error');
      }
      final encoding = response.headers.value(
        HttpHeaders.contentEncodingHeader,
      );
      if (encoding != null && encoding.toLowerCase() != 'identity') {
        throw const _DownloadFailure('content-encoding');
      }
      return response;
    }
    throw const _DownloadFailure('redirect-error');
  }

  Future<ApkDownloadResult> _run() async {
    String? destinationKey;
    File? partial;
    File? reservedTarget;
    RandomAccessFile? output;
    StreamIterator<List<int>>? input;
    ApkDownloadResult result;
    try {
      final target = File(request.filePath);
      final parent = await target.parent.resolveSymbolicLinks();
      _checkCancelled();
      destinationKey = File.fromUri(
        Directory(
          parent,
        ).uri.resolveUri(Uri(pathSegments: [target.uri.pathSegments.last])),
      ).path;
      if (!_destinations.add(destinationKey)) {
        destinationKey = null;
        throw const _DownloadFailure('destination-in-use');
      }
      if (await FileSystemEntity.type(target.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw const _DownloadFailure('file-exists');
      }
      _checkCancelled();
      final candidate = File(
        '${target.path}.upgrade-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}.part',
      );
      await candidate.create(exclusive: true);
      partial = candidate;
      output = await partial.open(mode: FileMode.write);
      _checkCancelled();
      final response = await _open();
      final total = response.contentLength < 0 ? null : response.contentLength;
      _emit(ApkDownloadState.downloading, total: total);
      input = StreamIterator(response.timeout(request.receiveTimeout));
      var bytes = 0;
      while (await _wait(input.moveNext())) {
        _checkCancelled();
        final chunk = input.current;
        await output.writeFrom(chunk);
        bytes += chunk.length;
        _checkCancelled();
        _emit(ApkDownloadState.downloading, bytes: bytes);
      }
      if (bytes == 0) throw const _DownloadFailure('empty-file');
      if (total != null && bytes != total) {
        throw const _DownloadFailure('length-mismatch');
      }
      await output.flush();
      await output.close();
      output = null;
      _checkCancelled();
      if (request.expectedMd5?.trim().isNotEmpty ?? false) {
        _emit(ApkDownloadState.verifying);
        if (!await isApkFileReady(
          partial.path,
          expectedMd5: request.expectedMd5,
        )) {
          throw const _DownloadFailure('checksum-mismatch');
        }
        _checkCancelled();
      }
      // Commit is a short non-cancellable phase. Exclusive reservation also
      // prevents overwriting a target created by another process during IO.
      _committing = true;
      try {
        await target.create(exclusive: true);
      } on FileSystemException {
        if (await FileSystemEntity.type(target.path, followLinks: false) !=
            FileSystemEntityType.notFound) {
          throw const _DownloadFailure('file-exists');
        }
        rethrow;
      }
      reservedTarget = target;
      await partial.rename(target.path);
      partial = null;
      reservedTarget = null;
      result = ApkDownloadResult.completed(target.path);
    } on _Cancelled {
      result = const ApkDownloadResult.cancelled();
    } on _DownloadFailure catch (error) {
      result = ApkDownloadResult.failed(error.code);
    } on TimeoutException {
      result = _cancelled
          ? const ApkDownloadResult.cancelled()
          : const ApkDownloadResult.failed('timeout');
    } on FileSystemException {
      result = _cancelled
          ? const ApkDownloadResult.cancelled()
          : const ApkDownloadResult.failed('file-error');
    } on Object {
      result = _cancelled
          ? const ApkDownloadResult.cancelled()
          : const ApkDownloadResult.failed('network-error');
    } finally {
      _client?.close(force: true);
      _client = null;
      try {
        await input?.cancel();
      } on Object {
        /* Preserve the attempt result. */
      }
      try {
        await output?.close();
      } on Object {
        /* Cleanup below reports failure. */
      }
    }
    try {
      if (partial != null && await partial.exists()) await partial.delete();
      if (reservedTarget != null && await reservedTarget.exists()) {
        await reservedTarget.delete();
      }
    } on FileSystemException {
      result = const ApkDownloadResult.failed('cleanup-error');
    } finally {
      if (destinationKey != null) _destinations.remove(destinationKey);
      _running = null;
      _committing = false;
    }
    _emit(result.status);
    return result;
  }
}
