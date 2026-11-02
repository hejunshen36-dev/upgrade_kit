import 'dart:async';

import 'package:flutter/material.dart';
import 'package:upgrade_kit/upgrade_kit.dart';

import 'host_apk_upgrade.dart';

/// UI and policy belong to the HOST. The plugin only runs the download/install.
class ApkUpgradeDemo extends StatefulWidget {
  const ApkUpgradeDemo({super.key});
  @override
  State<ApkUpgradeDemo> createState() => _ApkUpgradeDemoState();
}

class _ApkUpgradeDemoState extends State<ApkUpgradeDemo> {
  final _host = HostApkUpgrade();
  final _manifest = TextEditingController();
  final _path = TextEditingController();
  final _build = TextEditingController(text: '1');
  ApkDownloadTask? _task;
  StreamSubscription<ApkDownloadProgress>? _subscription;
  HostApkRelease? _release;
  ApkDownloadResult? _download;
  ApkDownloadProgress? _progress;
  bool _busy = false;
  String _status =
      'Host checks and compares; plugin downloads; host verifies before install.';

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _download = null;
    });
    try {
      final uri = Uri.parse(_manifest.text.trim());
      if (!['http', 'https'].contains(uri.scheme) || uri.host.isEmpty) {
        throw ArgumentError('Enter a manifest HTTP(S) URL.');
      }
      final currentBuild = BigInt.parse(_build.text.trim());
      if (currentBuild < BigInt.zero) {
        throw ArgumentError('Current build must be non-negative.');
      }
      final release = await _host.check(uri, currentBuild: currentBuild);
      if (!mounted) return;
      if (release == null) {
        setState(() => _status = 'No update.');
        return;
      }
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Update to ${release.versionName}?'),
          content: Text(release.releaseNotes),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Download'),
            ),
          ],
        ),
      );
      if (!mounted || accepted != true) return;
      await _subscription?.cancel();
      await _task?.dispose();
      if (!mounted) return;
      _release = release;
      final task = _host.createDownload(release, _path.text.trim());
      _task = task;
      _subscription = task.progress.listen((progress) {
        if (mounted) setState(() => _progress = progress);
      });
      _receive(await task.start());
    } on Object catch (error) {
      if (mounted) setState(() => _status = 'Failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _receive(ApkDownloadResult result) {
    if (!mounted) return;
    setState(() {
      _download = result;
      _status = result.status == ApkDownloadState.completed
          ? 'Downloaded. Use Verify and install to validate SHA-256 first.'
          : '${result.status.name}: ${result.errorCode ?? ''}';
    });
  }

  Future<void> _retry() async {
    setState(() {
      _busy = true;
      _download = null;
    });
    try {
      _receive(await _task!.retry());
    } on Object catch (error) {
      if (mounted) setState(() => _status = 'Failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _install() async {
    setState(() => _busy = true);
    try {
      final result = await _host.verifyAndInstall(_download!, _release!);
      if (mounted) {
        setState(
          () => _status = result == ApkInstallResult.permissionRequired
              ? 'Grant install permission, return, then Verify and install again.'
              : 'Installer result: ${result.name}',
        );
      }
    } on Object catch (error) {
      if (mounted) setState(() => _status = 'Installation blocked: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_task?.dispose());
    _manifest.dispose();
    _path.dispose();
    _build.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    final active =
        progress != null &&
        [
          ApkDownloadState.connecting,
          ApkDownloadState.downloading,
        ].contains(progress.state);
    final retryable =
        progress != null &&
        [
          ApkDownloadState.failed,
          ApkDownloadState.cancelled,
        ].contains(progress.state);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Host-controlled APK update',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _manifest,
          enabled: !_busy,
          decoration: const InputDecoration(
            labelText: 'Host version manifest URL',
          ),
        ),
        TextField(
          controller: _build,
          enabled: !_busy,
          decoration: const InputDecoration(labelText: 'Current build number'),
        ),
        TextField(
          controller: _path,
          enabled: !_busy,
          decoration: const InputDecoration(
            labelText: 'New APK path in existing app files/cache directory',
          ),
        ),
        FilledButton(
          onPressed: _busy ? null : _check,
          child: const Text('Check host service and prompt'),
        ),
        if (progress != null) ...[
          if (active) LinearProgressIndicator(value: progress.fraction),
          Text(
            '${progress.state.name}: ${progress.receivedBytes} / ${progress.totalBytes ?? 'unknown'} bytes; attempt ${progress.attempt}',
          ),
        ],
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: active
                  ? () async {
                      await _task?.cancel();
                    }
                  : null,
              child: const Text('Cancel download'),
            ),
            TextButton(
              onPressed: !_busy && retryable ? _retry : null,
              child: const Text('Retry download'),
            ),
            FilledButton(
              onPressed:
                  !_busy && _download?.status == ApkDownloadState.completed
                  ? _install
                  : null,
              child: const Text('Verify and install'),
            ),
          ],
        ),
        Text(_status),
      ],
    );
  }
}
