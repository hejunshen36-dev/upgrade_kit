import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upgrade_kit/upgrade_kit.dart';

class _LoopbackHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const checksum = '900150983cd24fb0d6963f7d28e17f72'; // abc
  const native = MethodChannel('upgrade_kit');
  late Directory directory;
  late HttpServer server;
  late ApkUpgradeController controller;
  late String url;
  var installs = 0;
  late HttpOverrides? previousHttpOverrides;
  setUp(() async {
    previousHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = _LoopbackHttpOverrides();
    directory = await Directory.systemTemp.createTemp('upgrade-session-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    url = 'http://127.0.0.1:${server.port}/app.apk';
    controller = ApkUpgradeController(
      cacheDirectory: () async => directory.path,
      filePrefix: 'fangcloud',
    );
    installs = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(native, (_) async {
          installs++;
          return 'permissionRequired';
        });
  });
  tearDown(() async {
    HttpOverrides.global = previousHttpOverrides;
    await controller.dispose();
    await server.close(force: true);
    await directory.delete(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(native, null);
  });
  ApkArtifact makeArtifact({String version = '1.0', String? md5}) =>
      ApkArtifact(version: version, url: url, expectedMd5: md5);
  Future<ApkUpgradeSnapshot> terminal() => controller.states
      .firstWhere(
        (s) =>
            s.state == ApkDownloadState.completed ||
            s.state == ApkDownloadState.failed ||
            s.state == ApkDownloadState.cancelled,
      )
      .timeout(const Duration(seconds: 5));

  test(
    'concurrent equivalent prepares use one GET and replay terminal state',
    () async {
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      var gets = 0;
      server.listen((request) async {
        expect(request.method, 'GET');
        gets++;
        await release.future;
        request.response.write('abc');
        await request.response.close();
      });
      final results = await Future.wait([
        controller.prepareDownload(makeArtifact(md5: checksum)),
        controller.prepareDownload(
          makeArtifact(md5: ' ${checksum.toUpperCase()} '),
        ),
      ]);
      expect(results, [
        ApkPrepareResult.started,
        ApkPrepareResult.alreadyRunning,
      ]);
      expect(controller.isRunning(makeArtifact(md5: checksum)), isTrue);
      final completed = terminal();
      release.complete();
      expect((await completed).isDownloadReady, isTrue);
      expect(gets, 1);
      final replay = await controller.states.first;
      expect(replay.isDownloadReady, isTrue);
      expect(replay.fraction, 1);
      expect(
        await controller.prepareDownload(makeArtifact(md5: checksum)),
        ApkPrepareResult.ready,
      );
      expect(gets, 1);
      expect(installs, 0); // Download never auto-installs.
      expect(
        await controller.install(makeArtifact(md5: checksum)),
        ApkInstallResult.permissionRequired,
      );
      expect(
        await controller.install(makeArtifact(md5: checksum)),
        ApkInstallResult.permissionRequired,
      );
      expect(installs, 2);
    },
  );

  test(
    'null empty and whitespace hashes share cached file without requesting headers',
    () async {
      final path = await controller.artifactPath(makeArtifact());
      expect(path, '${directory.path}/fangcloud-1.0-.apk');
      await File(path).writeAsString('abc');
      for (final hash in <String?>[null, '', ' \t ']) {
        expect(await controller.artifactPath(makeArtifact(md5: hash)), path);
        expect(
          await controller.prepareDownload(
            makeArtifact(md5: hash),
            headers: () =>
                throw StateError('Cached files must not need authentication'),
          ),
          ApkPrepareResult.ready,
        );
        expect(
          await controller.verifyCachedApk(makeArtifact(md5: hash)),
          isTrue,
        );
      }
    },
  );

  test(
    'replacement requires policy, waits for old task and ignores old events',
    () async {
      final oldConnected = Completer<void>();
      var gets = 0;
      server.listen((request) async {
        gets++;
        if (gets == 1) {
          request.response.contentLength = 6;
          request.response.add([1]);
          await request.response.flush();
          oldConnected.complete();
        } else {
          request.response.write('abc');
          await request.response.close();
        }
      });
      final states = <ApkUpgradeSnapshot>[];
      final subscription = controller.states.listen(states.add);
      addTearDown(subscription.cancel);
      await controller.prepareDownload(makeArtifact(version: 'old'));
      await oldConnected.future.timeout(const Duration(seconds: 5));
      expect(
        await controller.prepareDownload(makeArtifact(version: 'new')),
        ApkPrepareResult.busy,
      );
      expect(controller.snapshot.artifact!.version, 'old');
      expect(
        await controller.prepareDownload(
          makeArtifact(version: 'new'),
          replaceExisting: true,
        ),
        ApkPrepareResult.started,
      );
      expect((await terminal()).artifact!.version, 'new');
      expect(controller.snapshot.isDownloadReady, isTrue);
      await Future<void>.delayed(Duration.zero);
      final newIndex = states.indexWhere((s) => s.artifact?.version == 'new');
      expect(
        states.skip(newIndex).every((s) => s.artifact?.version == 'new'),
        isTrue,
      );
      expect(gets, 2);
      expect(await directory.list().length, 1);
    },
  );

  test(
    'cancel clears partial file, late subscribers replay cancellation and retry is explicit',
    () async {
      final connected = Completer<void>();
      var gets = 0;
      server.listen((request) async {
        gets++;
        if (gets == 1) {
          request.response.contentLength = 6;
          request.response.add([1]);
          await request.response.flush();
          connected.complete();
        } else {
          request.response.write('abc');
          await request.response.close();
        }
      });
      await controller.prepareDownload(makeArtifact());
      await connected.future.timeout(const Duration(seconds: 5));
      await controller.cancel();
      expect(await directory.list().length, 0);
      expect((await controller.states.first).state, ApkDownloadState.cancelled);
      expect(gets, 1);
      expect(await controller.retry(), ApkPrepareResult.started);
      expect((await terminal()).isDownloadReady, isTrue);
      expect(gets, 2);
    },
  );

  test(
    'checksum failure removes bad bytes and can retry; tampered install is blocked',
    () async {
      var gets = 0;
      server.listen((request) async {
        request.response.write(++gets == 1 ? 'bad' : 'abc');
        await request.response.close();
      });
      final artifact = makeArtifact(md5: checksum);
      await controller.prepareDownload(artifact);
      expect((await terminal()).errorCode, 'checksum-mismatch');
      expect(await directory.list().length, 0);
      expect(gets, 1);
      await controller.retry();
      expect((await terminal()).isDownloadReady, isTrue);
      final file = File(await controller.artifactPath(artifact));
      await file.writeAsString('tampered');
      expect(await controller.install(artifact), ApkInstallResult.fileNotFound);
      expect(installs, 0);
      expect(await file.exists(), isFalse);
    },
  );

  test(
    'install verification finishes before native launch and always closes on failure',
    () async {
      final artifact = makeArtifact(md5: checksum);
      final file = File(await controller.artifactPath(artifact));
      await file.writeAsString('abc');
      final events = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(native, (_) async {
            events.add('native');
            return 'permissionRequired';
          });
      Future<void> report(bool active) async => events.add('verify:$active');
      expect(
        await controller.install(artifact, onVerificationChanged: report),
        ApkInstallResult.permissionRequired,
      );
      expect(events, ['verify:true', 'verify:false', 'native']);
      events.clear();
      await file.writeAsString('bad');
      expect(
        await controller.install(artifact, onVerificationChanged: report),
        ApkInstallResult.fileNotFound,
      );
      expect(events, ['verify:true', 'verify:false']);
    },
  );

  test(
    'cached verification can retain invalid bytes without native installation',
    () async {
      final artifact = makeArtifact(md5: checksum);
      final file = File(await controller.artifactPath(artifact));
      await file.writeAsString('bad');
      expect(
        await controller.verifyCachedApk(artifact, deleteInvalid: false),
        isFalse,
      );
      expect(await file.readAsString(), 'bad');
      expect(controller.snapshot.isDownloadReady, isFalse);
      expect(installs, 0);
      expect(await controller.isReady(artifact), isFalse);
      expect(await file.exists(), isFalse);
    },
  );

  test('blank MD5 never reports an installation verification phase', () async {
    final artifact = makeArtifact(md5: '  ');
    await File(await controller.artifactPath(artifact)).writeAsString('abc');
    final phases = <bool>[];
    await controller.install(artifact, onVerificationChanged: phases.add);
    expect(phases, isEmpty);
    expect(installs, 1);
  });

  test(
    'invalid URL returns typed failure without leaving a running session',
    () async {
      expect(
        await controller.prepareDownload(
          ApkArtifact(version: '1', url: 'file:///app.apk'),
        ),
        ApkPrepareResult.failed,
      );
      expect(controller.snapshot.errorCode, 'invalid-request');
      expect(controller.snapshot.isRunning, isFalse);
      expect(await directory.list().length, 0);
    },
  );

  test(
    'disposal waits for pending preparation and closes replay subscriptions',
    () async {
      final folder = Completer<String>();
      final slow = ApkUpgradeController(cacheDirectory: () => folder.future);
      final preparation = slow.prepareDownload(makeArtifact());
      await Future<void>.delayed(Duration.zero);
      final disposal = slow.dispose();
      folder.complete(directory.path);
      await preparation;
      await disposal.timeout(const Duration(seconds: 5));
      expect(await slow.states.isEmpty, isTrue);
      expect(() => slow.prepareDownload(makeArtifact()), throwsStateError);
      expect(await directory.list().length, 0);
    },
  );

  test(
    'artifact path escapes separators and preserves the cache directory',
    () async {
      final path = await controller.artifactPath(
        makeArtifact(version: '../../other'),
      );
      expect(File(path).parent.path, directory.path);
    },
  );
}
