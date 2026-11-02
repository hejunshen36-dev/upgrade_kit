# Configured stores and host-owned APK upgrade

For the complete Chinese integration walkthrough, see
[完整中文接入示例](INTEGRATION.zh-CN.md).

## Platform store configuration

```dart
final service = StoreUpgradeService(
  configuration: StoreUpgradeConfiguration(
    android: AndroidStoreUpgradeConfiguration(
      vendors: AndroidVendorUpgradeConfiguration(
        // Configure the vendor backends your application distributes through.
        // huawei: HuaweiVendorUpgradeConfiguration(...),
      ),
      fallbackTarget: 'market://details?id=com.example.app',
    ),
    ios: IosStoreUpgradeConfiguration(appId: '123456789', country: 'cn'),
    ohos: const OhosStoreUpgradeConfiguration(),
  ),
);

final check = await service.checkStoreUpgrade();
if (check.status == StoreUpgradeCheckStatus.updateAvailable) {
  // Call after the host has decided to proceed, e.g. after confirmation.
  await service.requestStoreUpgrade();
}
```

The service automatically selects the current platform. Missing configuration
returns `notConfigured`; unavailable vendor/platform querying returns
`unsupported`. Errors remain `failed`, distinct from `noUpdate`. Checking never
navigates or displays UI. The explicit action opens the Android vendor store or
iOS App Store, or requests the native OHOS update dialog. Samsung/unknown Android
vendors support store routing but not built-in version querying. Fill the
Android configuration with the existing per-vendor credentials you need.

iOS uses Apple's [ID-based Lookup API](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/LookupExamples.html)
with the configured App Store ID and two-letter country code (default `us`).
The current marketing version comes from native `CFBundleShortVersionString`.
One-to-three numeric components are compared with absent components treated as
zero (`1.2` equals `1.2.0`); the existing generic SemVer comparator is unchanged.
An absent store listing is `failed/not-found`, not no-update. Configure the
storefront for your distribution; native store navigation follows the user's
store account. Lookup failures use `http-error`, `timeout`, `invalid-response`,
`invalid-version`, `not-found` or `store-error`. Missing native registration
preserves `MissingPluginException` for diagnosis.

`StoreUpgradeCheckResult.release` has normalized Android/iOS release data. AppGallery
reports availability without release metadata, so release can be null when an
update is available. Actions report `storeLaunched`, `dialogShown`, `notShown`,
or `failed`; these mean launch/display, not completed installation. The OHOS
configuration enables native AppGallery use; application identity comes from
the host ability. System dialog invocation is explicit, never a check side effect.

An injected `http.Client` is borrowed and must be closed by its owner. `platform`
can explicitly select an adapter; native capability checks still apply.
Automatic store routing is unsupported on Web and desktop.

## Custom backend: host checks, prompts and verifies

The host requests and compares versions and shows its own dialog. This path
does not require `UpgradeSource` or `checkForUpdate`. After confirmation:

```dart
const upgradeKit = UpgradeKit();
final task = upgradeKit.createApkDownload(ApkDownloadRequest(
  url: Uri.parse('https://example.com/releases/app.apk'),
  filePath: absoluteApkPath, // New filename in an EXISTING app files/cache dir.
  headers: downloadAuthHeaders, // Optional host-owned download authentication.
));
final subscription = task.progress.listen((progress) {
  // Update the host UI; fraction/totalBytes are null when size is unknown.
  print('${progress.receivedBytes} / ${progress.totalBytes}');
});

try {
  final result = await task.start();
  if (result.status == ApkDownloadState.completed) {
    final valid = await hostVerifyDownloadedApk(result.filePath!);
    if (valid) {
      await upgradeKit.installApk(result.filePath!);
    }
  }
} finally {
  await subscription.cancel();
  await task.dispose();
}
```

The path, authentication headers and verification function are application
code. For an executable HTTP-query/comparison/popup/SHA-256/install example,
see `example/lib/host_apk_upgrade.dart` and `example/lib/apk_upgrade_demo.dart`.

While active, `await task.cancel()` aborts its connection and waits for partial
file cleanup. After failure/cancellation, `await task.retry()` starts a new
attempt from zero. Keep the task alive for retry; dispose it when the operation
or screen ends. Starting twice, retrying a completed task, and starting/retrying
after disposal throw `StateError`. Disposal cancels IO and closes events.
If the final file commit has started, completion wins over cancellation.

States: `idle → connecting → downloading → completed`; active attempts can go
through `cancelling → cancelled` or fail. Events expose bytes, optional total
size/fraction and attempt count; `snapshot` serves late subscribers. Downloads
stream to a temporary sibling file with backpressure. Incomplete files are
cleaned before returning; cleanup failures report `cleanup-error` and may need
host cleanup. Existing destination files are never silently replaced, and
concurrent tasks cannot write the same canonical destination.

The host owns completed files. Use a private app-owned directory and keep
verification and installation on the same file. Android FileProvider accepts
app files/cache/external-files locations; arbitrary external paths may not be
installable. Downloading does not grant storage or installation permissions.

Supported transport: full HTTP 200 responses, up to five redirects. Partial
responses and HTTPS-to-HTTP redirects fail. Custom headers are stripped across
origins. The downloader manages `Range`, `Host`, `Content-Length` and
`Accept-Encoding`. Empty/truncated content and compressed payloads fail. Default
connect/response-header timeout: 15 seconds; idle body timeout: 30 seconds.
Foreground Dart IO only: no automatic retry, background-process persistence,
Range resume, or silent installation.

| Error code | Meaning |
| --- | --- |
| `http-error` | Non-200 final response, including partial response |
| `timeout` | Connect/header/read timeout |
| `file-exists` / `destination-in-use` | Existing file or concurrent writer |
| `file-error` / `cleanup-error` | File IO or cleanup failed |
| `empty-file` / `length-mismatch` | Empty or inconsistent body length |
| `redirect-error` / `content-encoding` | Unsupported redirect or encoding |
| `network-error` | Transport failure, including peer interruption |

A completed download only means a file is ready for HOST verification. If
Android installation returns `permissionRequired`, wait for authorization and
application resume, then verify and request installation again. `launched`
means the system installer opened, not that installation completed.
