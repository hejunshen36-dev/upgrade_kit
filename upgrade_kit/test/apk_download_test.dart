import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:upgrade_kit/upgrade_kit.dart';

void main() {
  late HttpServer server;
  late Directory directory;
  late Uri url;
  late String destination;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('upgrade-download-test-');
    destination = '${directory.path}/update.apk';
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    url = Uri.parse('http://127.0.0.1:${server.port}/app.apk');
  });
  tearDown(() async {
    await server.close(force: true);
    await directory.delete(recursive: true);
  });
  ApkDownloadTask task({Duration? timeout, String? expectedMd5}) {
    final value = const UpgradeKit().createApkDownload(
      ApkDownloadRequest(
        url: url,
        expectedMd5: expectedMd5,
        filePath: destination,
        receiveTimeout: timeout ?? const Duration(seconds: 2),
      ),
    );
    addTearDown(value.dispose);
    return value;
  }

  for (final checksum in <String?>[
    null,
    '',
    '  ',
    '900150983CD24FB0D6963F7D28E17F72',
  ]) {
    test('optional download checksum: $checksum', () async {
      server.listen((request) async {
        request.response.write('abc');
        await request.response.close();
      });
      expect(
        (await task(expectedMd5: checksum).start()).status,
        ApkDownloadState.completed,
      );
      expect(await File(destination).readAsString(), 'abc');
    });
  }
  test('checksum mismatch removes partial and permits retry', () async {
    var attempts = 0;
    server.listen((request) async {
      request.response.write(++attempts == 1 ? 'bad' : 'abc');
      await request.response.close();
    });
    final download = task(expectedMd5: '900150983cd24fb0d6963f7d28e17f72');
    expect((await download.start()).errorCode, 'checksum-mismatch');
    expect(await directory.list().length, 0);
    expect((await download.retry()).status, ApkDownloadState.completed);
  });
  test(
    'streams known-length bytes and only completes after the file is ready',
    () async {
      server.listen((request) async {
        request.response.contentLength = 6;
        request.response.add([1, 2, 3]);
        await request.response.flush();
        request.response.add([4, 5, 6]);
        await request.response.close();
      });
      final download = task();
      final events = <ApkDownloadProgress>[];
      final subscription = download.progress.listen(events.add);
      addTearDown(subscription.cancel);
      final result = await download.start();
      await Future<void>.delayed(Duration.zero);
      expect(result.status, ApkDownloadState.completed);
      expect(await File(result.filePath!).readAsBytes(), [1, 2, 3, 4, 5, 6]);
      expect(download.snapshot.receivedBytes, 6);
      expect(download.snapshot.totalBytes, 6);
      expect(download.snapshot.fraction, 1);
      expect(
        events.map((event) => event.state),
        contains(ApkDownloadState.downloading),
      );
      expect(await directory.list().length, 1);
    },
  );

  test(
    'reports bytes without a fabricated percentage for unknown length',
    () async {
      server.listen((request) async {
        request.response.add([7, 8, 9]);
        await request.response.close();
      });
      final download = task();
      expect((await download.start()).status, ApkDownloadState.completed);
      expect(download.snapshot.receivedBytes, 3);
      expect(download.snapshot.totalBytes, isNull);
      expect(download.snapshot.fraction, isNull);
    },
  );

  test(
    'HTTP failure cleans partial data and explicit retry restarts at zero',
    () async {
      var attempts = 0;
      server.listen((request) async {
        attempts++;
        if (attempts == 1) {
          request.response.statusCode = 503;
        } else {
          request.response.add([4, 5]);
        }
        await request.response.close();
      });
      final download = task();
      expect((await download.start()).errorCode, 'http-error');
      expect(await directory.list().length, 0);
      expect((await download.retry()).status, ApkDownloadState.completed);
      expect(download.snapshot.attempt, 2);
      expect(await File(destination).readAsBytes(), [4, 5]);
    },
  );

  test(
    'cancels a stalled response, cleans the partial file and can retry',
    () async {
      var attempts = 0;
      server.listen((request) async {
        attempts++;
        request.response.bufferOutput = false;
        request.response.contentLength = attempts == 1 ? 2 : 1;
        request.response.add([1]);
        await request.response.flush();
        if (attempts > 1) await request.response.close();
      });
      final download = task();
      final received = download.progress.firstWhere(
        (event) => event.receivedBytes > 0,
      );
      final completion = download.start();
      await received;
      await download.cancel();
      expect((await completion).status, ApkDownloadState.cancelled);
      expect(await directory.list().length, 0);
      expect((await download.retry()).status, ApkDownloadState.completed);
    },
  );

  test('cancel before response headers returns promptly', () async {
    final connected = Completer<void>();
    server.listen((request) {
      connected.complete();
    });
    final download = task();
    final completion = download.start();
    await connected.future;
    await download.cancel().timeout(const Duration(seconds: 1));
    expect((await completion).status, ApkDownloadState.cancelled);
    expect(await directory.list().length, 0);
  });

  test('read timeout is a failure', () async {
    server.listen((request) async {
      request.response.add([1]);
      await request.response.flush();
    });
    final download = task(timeout: const Duration(milliseconds: 50));
    expect((await download.start()).errorCode, 'timeout');
    expect(await directory.list().length, 0);
  });

  test('empty bodies fail and never create an installable file', () async {
    server.listen((request) async {
      request.response.contentLength = 0;
      await request.response.close();
    });
    expect((await task().start()).errorCode, 'empty-file');
    expect(File(destination).existsSync(), false);
  });

  test(
    'cross-origin redirects strip host credentials before downloading',
    () async {
      final cdn = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => cdn.close(force: true));
      String? leaked;
      cdn.listen((request) async {
        leaked = request.headers.value('x-api-key');
        request.response.add([8]);
        await request.response.close();
      });
      server.listen((request) async {
        expect(request.headers.value('x-api-key'), 'private');
        request.response.statusCode = 302;
        request.response.headers.set(
          'location',
          'http://127.0.0.1:${cdn.port}/app.apk',
        );
        await request.response.close();
      });
      final download = const UpgradeKit().createApkDownload(
        ApkDownloadRequest(
          url: url,
          filePath: destination,
          headers: {'x-api-key': 'private'},
        ),
      );
      addTearDown(download.dispose);
      expect((await download.start()).status, ApkDownloadState.completed);
      expect(leaked, isNull);
    },
  );

  test('a file created during download is not overwritten at commit', () async {
    server.listen((request) async {
      await File(destination).writeAsBytes([99]);
      request.response.add([1, 2]);
      await request.response.close();
    });
    expect((await task().start()).errorCode, 'file-exists');
    expect(await File(destination).readAsBytes(), [99]);
    expect(await directory.list().length, 1);
  });

  test(
    'a truncated advertised response never produces a completed file',
    () async {
      server.listen((request) async {
        final socket = await request.response.detachSocket(writeHeaders: false);
        socket.write(
          'HTTP/1.1 200 OK\r\nContent-Length: 100\r\nConnection: close\r\n\r\nabc',
        );
        await socket.flush();
        await socket.close();
      });
      final result = await task().start();
      expect(result.status, ApkDownloadState.failed);
      expect(File(destination).existsSync(), false);
      expect(await directory.list().length, 0);
    },
  );

  test('does not overwrite an existing APK', () async {
    await File(destination).writeAsBytes([99]);
    final result = await task().start();
    expect(result.errorCode, 'file-exists');
    expect(await File(destination).readAsBytes(), [99]);
  });

  test('rejects concurrent writers to the same target', () async {
    final connected = Completer<void>();
    server.listen((request) {
      connected.complete();
    });
    final first = task();
    final completion = first.start();
    await connected.future;
    expect((await task().start()).errorCode, 'destination-in-use');
    await first.cancel();
    await completion;
  });

  test('dispose cancels IO and prevents another attempt', () async {
    final download = task();
    await download.dispose();
    expect(download.start, throwsStateError);
    expect(download.retry, throwsStateError);
  });

  test('cannot restart while dispose is still cleaning up', () async {
    final download = task();
    final disposing = download.dispose();
    expect(download.retry, throwsStateError);
    await disposing;
  });

  test(
    'dispose during response wait cancels and releases the destination',
    () async {
      final connected = Completer<void>();
      server.listen((request) {
        if (!connected.isCompleted) connected.complete();
      });
      final download = task();
      final completion = download.start();
      await connected.future;
      await download.dispose().timeout(const Duration(seconds: 1));
      expect((await completion).status, ApkDownloadState.cancelled);
      expect(await directory.list().length, 0);
    },
  );

  test('validates URL, destination and timeouts before starting', () {
    expect(
      () => ApkDownloadRequest(
        url: Uri.parse('file:///tmp/app.apk'),
        filePath: destination,
      ),
      throwsArgumentError,
    );
    expect(
      () => ApkDownloadRequest(url: url, filePath: ' '),
      throwsArgumentError,
    );
    expect(
      () => ApkDownloadRequest(
        url: url,
        filePath: destination,
        receiveTimeout: Duration.zero,
      ),
      throwsArgumentError,
    );
  });
}
