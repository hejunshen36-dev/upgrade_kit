import 'package:flutter/material.dart';
import 'package:upgrade_kit/upgrade_kit.dart';
import 'apk_upgrade_demo.dart';

void main() {
  runApp(const UpgradeKitExampleApp());
}

class UpgradeKitExampleApp extends StatelessWidget {
  const UpgradeKitExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'upgrade_kit example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const UpgradeKitExamplePage(),
    );
  }
}

class UpgradeKitExamplePage extends StatefulWidget {
  const UpgradeKitExamplePage({super.key});

  @override
  State<UpgradeKitExamplePage> createState() => _UpgradeKitExamplePageState();
}

class _UpgradeKitExamplePageState extends State<UpgradeKitExamplePage> {
  static const UpgradeKit _upgradeKit = UpgradeKit();

  final TextEditingController _apkPathController = TextEditingController();
  final TextEditingController _storeTargetController = TextEditingController();
  String _status = 'No operation has run.';
  bool _isRunning = false;

  StoreUpgradeService _configuredStores() {
    final appId = _storeTargetController.text.trim();
    return StoreUpgradeService(
      configuration: StoreUpgradeConfiguration(
        android: AndroidStoreUpgradeConfiguration(
          vendors: AndroidVendorUpgradeConfiguration(),
        ),
        ios: RegExp(r'^[0-9]+$').hasMatch(appId)
            ? IosStoreUpgradeConfiguration(appId: appId)
            : null,
        ohos: const OhosStoreUpgradeConfiguration(),
      ),
    );
  }

  Future<String> _checkDemoService() async {
    // Replace this local fixture with your repository's authenticated request.
    // Map a backend response to UpgradeRelease, and throw on request failure.
    final source = CallbackUpgradeSource((request) async {
      return const UpgradeRelease(
        version: UpgradeVersion(versionName: '1.1.0'),
        releaseNotes: 'Example release returned by a host-owned source.',
      );
    });
    final result = await _upgradeKit.checkForUpdate(
      source: source,
      request: UpgradeCheckRequest(
        appId: 'com.example.app',
        currentVersion: const UpgradeVersion(versionName: '1.0.0'),
        channel: 'stable',
      ),
    );
    if (result.status == UpgradeCheckStatus.failed) {
      return '${result.errorCode}: ${result.errorMessage}';
    }
    return '${result.status.name}: ${result.release?.version.versionName ?? 'no release'}';
  }

  Future<void> _run(Future<Object> Function() operation) async {
    setState(() {
      _isRunning = true;
      _status = 'Running...';
    });

    try {
      final result = await operation();
      if (!mounted) {
        return;
      }
      setState(() => _status = result.toString());
    } on UpgradeKitException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _status = '${error.code}: ${error.message}');
    } on UnsupportedError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _status = 'Unsupported: ${error.message}');
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _status = 'Failed: $error');
    } finally {
      if (mounted) {
        setState(() => _isRunning = false);
      }
    }
  }

  @override
  void dispose() {
    _apkPathController.dispose();
    _storeTargetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('upgrade_kit example')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton(
            onPressed: _isRunning
                ? null
                : () => _run(() async {
                    final result = await _configuredStores()
                        .checkStoreUpgrade();
                    return '${result.status.name}: ${result.release?.version.versionName ?? result.errorCode ?? ''}';
                  }),
            child: const Text('Check configured store'),
          ),
          FilledButton(
            onPressed: _isRunning
                ? null
                : () => _run(() => _configuredStores().requestStoreUpgrade()),
            child: const Text('Update through configured store'),
          ),
          const Text(
            'Custom upgrade service (local demo)',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _isRunning ? null : () => _run(_checkDemoService),
            child: const Text('Check demo service'),
          ),
          const SizedBox(height: 24),
          const ApkUpgradeDemo(),
          const SizedBox(height: 24),
          const Text(
            'HarmonyOS AppGallery update',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _isRunning
                ? null
                : () => _run(_upgradeKit.checkOhosStoreUpdate),
            child: const Text('Check OHOS store update'),
          ),
          FilledButton(
            onPressed: _isRunning
                ? null
                : () => _run(_upgradeKit.showOhosUpdateDialog),
            child: const Text('Show OHOS update dialog'),
          ),
          const SizedBox(height: 24),
          const Text(
            'Android APK installation',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _apkPathController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Absolute APK path',
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _isRunning
                ? null
                : () => _run(
                    () => _upgradeKit.installApk(_apkPathController.text),
                  ),
            child: const Text('Install APK'),
          ),
          const SizedBox(height: 24),
          const Text(
            'Android vendor store',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _isRunning
                ? null
                : () => _run(_upgradeKit.getAndroidStoreContext),
            child: const Text('Read Android store context'),
          ),
          FilledButton(
            onPressed: _isRunning
                ? null
                : () => _run(() {
                    final fallback = _storeTargetController.text.trim();
                    return _upgradeKit.openCurrentAppStore(
                      fallbackTarget: fallback.isEmpty ? null : fallback,
                    );
                  }),
            child: const Text('Open current vendor store'),
          ),
          const SizedBox(height: 24),
          const Text(
            'Store launch',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _storeTargetController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'iOS app ID or Android store URI',
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _isRunning
                ? null
                : () => _run(
                    () => _upgradeKit.openStore(_storeTargetController.text),
                  ),
            child: const Text('Open app store'),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_status),
            ),
          ),
        ],
      ),
    );
  }
}
