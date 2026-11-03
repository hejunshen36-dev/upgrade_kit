# upgrade_kit

面向 Android、iOS 和 HarmonyOS 的 Flutter 应用升级插件。提供统一商店升级入口，以及宿主可控制的 APK 下载、进度、取消、重试、校验和安装能力。

插件提供两条独立流程：

| 流程 | 宿主负责 | 插件负责 |
| --- | --- | --- |
| 平台商店升级 | 平台配置、检查时机、是否继续升级 | 厂商或商店查询、跳转商店、鸿蒙原生弹窗 |
| 自建服务升级 | 网络请求、版本比较、业务弹窗、文件校验策略和安装时机 | 前台 APK 下载、进度、取消、从零重试、清理未完成文件和请求系统安装 |

**下载完成不会自动安装。** `storeLaunched`、`dialogShown`、`ApkInstallResult.launched` 分别表示界面已经打开，不代表升级安装完成。

## 环境与安装

- Dart 3.9.2+、Flutter 3.35.7+。
- Android 原生插件最低 API 21；宿主还需满足所选 Flutter SDK 的平台要求。
- iOS、Android 使用官方 Flutter；HarmonyOS 使用兼容的 Flutter OHOS SDK 与 DevEco 工具链。

从 pub.dev 接入时，宿主只需依赖主包，平台实现由插件默认注册：

```yaml
dependencies:
  upgrade_kit: ^1.0.1
```

```dart
import 'package:upgrade_kit/upgrade_kit.dart';
```

本地开发时，各包和 example 的 `pubspec_overrides.yaml` 解析同一仓库的实现。外部宿主使用 Git/path 主包时，需要在**宿主根 pubspec** 中显式覆盖四个传递包；开发覆盖不会由主包传递给宿主。完整配置和发布顺序见 [发布与 Git/path 接入](https://github.com/hejunshen36-dev/upgrade_kit/blob/main/PUBLISHING.md)。

### Android 联网权限

厂商商店查询、宿主版本接口请求和 APK 下载需要 `android.permission.INTERNET`。Android 插件和 example 的主 manifest 均已声明该权限；插件声明会通过 manifest 合并提供给宿主。宿主主 manifest 中的声明方式如下：

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET" />
    <!-- 保留宿主现有 application 等配置。 -->
</manifest>
```

`INTERNET` 无需运行时授权弹窗。请确保宿主没有在 manifest 合并时移除它，并检查 release 的最终声明；只在 debug/profile manifest 中添加权限无法覆盖正式版本。安装未知来源应用所需的授权仍由安装流程单独处理。

## 能力与入口

| 能力 | Android | iOS | HarmonyOS |
| --- | --- | --- | --- |
| `checkStoreUpgrade()` | 华为、荣耀、小米、vivo、OPPO 商店查询 | App Store 版本查询 | AppGallery 原生检查 |
| `requestStoreUpgrade()` | 跳转厂商商店 | 跳转 App Store | 原生更新弹窗 |
| APK 下载、进度、取消和重试 | 支持 | 仅文件任务，不用于安装应用 | 仅文件任务，不用于安装应用 |
| APK 安装与授权引导 | 支持 | 不支持 | 不支持 |
| `checkForUpdate()` | 宿主查询来源 | 宿主查询来源 | 宿主查询来源 |

- `StoreUpgradeService`：三端商店配置与统一检查、升级动作。
- `UpgradeKit`：基础下载、校验、安装和平台能力；也提供可选通用查询接口。
- `ApkUpgradeController`：前台 APK 会话、缓存复用与任务生命周期协调。

三星和未知 Android 厂商不支持内置版本查询，可显式尝试商店路由或备用地址。APK 安装仅支持 Android；Web 和桌面不提供原生商店适配。通用查询不依赖原生注册，APK 下载需要 Dart IO。

## 平台商店升级

### 配置 Android、iOS 和鸿蒙

只填写实际使用的 Android 厂商配置。下列凭证为占位值，需要替换为宿主配置。

```dart
final stores = StoreUpgradeService(
  configuration: StoreUpgradeConfiguration(
    android: AndroidStoreUpgradeConfiguration(
      vendors: AndroidVendorUpgradeConfiguration(
        huawei: HuaweiVendorUpgradeConfiguration(
          clientId: '<Huawei client ID>',
          clientSecret: '<Huawei client secret>',
          appId: '<Huawei app ID>',
        ),
        honor: HonorVendorUpgradeConfiguration(
          clientId: '<Honor client ID>',
          clientSecret: '<Honor client secret>',
          appId: '<Honor app ID>',
        ),
        xiaomi: XiaomiVendorUpgradeConfiguration(
          userName: '<Xiaomi user name>',
          passwordOrPrivateKey: '<Xiaomi credential>',
          rsaPublicKeyPem: '<Xiaomi RSA public key PEM>',
        ),
        vivo: VivoVendorUpgradeConfiguration(
          account: '<vivo account>',
          secret: '<vivo secret>',
        ),
        oppo: OppoVendorUpgradeConfiguration(
          clientId: '<OPPO client ID>',
          clientSecret: '<OPPO client secret>',
        ),
      ),
      fallbackTarget: 'market://details?id=com.example.app',
      locale: 'zh-CN',
    ),
    ios: IosStoreUpgradeConfiguration(
      appId: '1234567890', // 替换为真实数字 App Store ID，不是 bundle ID。
      country: 'cn',
    ),
    ohos: const OhosStoreUpgradeConfiguration(),
  ),
);
```

Android 识别当前设备厂商并查询对应后端。客户端中的厂商凭证可被提取，权限和分发方式由宿主管理；插件不持久化或记录这些凭证。

iOS 按 App Store ID 和地区查询发布版本，读取本机 `CFBundleShortVersionString` 后进行数字分段比较。地区默认 `us`，未发布的商店条目返回 `failed/not-found`。跳转商店时仍跟随用户的商店账户。

鸿蒙配置为 AppGallery 原生能力的启用标记，应用身份取自宿主 Ability。宿主需具备对应注册、分发、签名及前台 Ability 条件。

### 检查与显式升级

```dart
final check = await stores.checkStoreUpgrade();
if (check.status == StoreUpgradeCheckStatus.updateAvailable) {
  // 将结果交给宿主展示 UI。鸿蒙 check.release 可能为空。
  print(check.release?.releaseNotes ?? '发现新版本');
}
```

检查本身不展示弹窗或打开商店。宿主确认继续后，单独调用：

```dart
final action = await stores.requestStoreUpgrade();
print(action.name); // storeLaunched / dialogShown / notShown / failed
```

| 检查状态 | 含义 |
| --- | --- |
| `updateAvailable` | 有更新；鸿蒙可能没有版本详情 |
| `noUpdate` | 已确认没有更新 |
| `notConfigured` | 缺少当前平台或厂商配置 |
| `unsupported` | 当前平台或厂商不支持查询 |
| `failed` | 检查失败，通过 `errorCode` 诊断，不能视为无更新 |

未配置平台时请求升级会抛出 `StateError`。注入的 `http.Client` 由宿主释放。完整业务确认框示例见 [接入指南](doc/INTEGRATION.zh-CN.md)。

## 自建服务：宿主检查与 APK 完整流程

宿主使用自己的网络库请求版本服务，完成版本比较和弹窗。此流程不要求实现 `UpgradeSource`，也不要求使用插件的比较器。用户确认下载后再创建任务。

### 下载与进度

以下 `absoluteApkPath` 是宿主提供的新文件绝对路径，父目录必须存在，且位于应用私有 files/cache 或 external-files 范围。下载鉴权可通过 `headers` 传入。

```dart
const upgradeKit = UpgradeKit();
final task = upgradeKit.createApkDownload(
  ApkDownloadRequest(
    url: Uri.parse('https://example.com/releases/app.apk'),
    filePath: absoluteApkPath,
    headers: const {},
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ),
);
final progressSubscription = task.progress.listen((progress) {
  print('${progress.receivedBytes} / ${progress.totalBytes}');
  // progress.fraction 为 null 时显示不确定进度；attempt 表示尝试次数。
});
final downloaded = await task.start();
```

将 `task`、订阅和下载结果保存在同一宿主 State/Controller 中。`start()` 返回结果后，按 `completed`、`cancelled`、`failed` 更新 UI；失败时可读取 `errorCode`。

### 取消、重试和释放

以下分别对应用户操作，不应按顺序自动执行：

```dart
await task.cancel(); // 等待连接关闭和未完成文件清理。
```

```dart
final retried = await task.retry(); // 仅失败/取消后可调用，从零下载。
// 用 retried 替换宿主保存的旧下载结果。
print(retried.status.name);
```

不要在第一次失败后立即 dispose，否则无法重试。流程结束或宿主不再持有任务时：

```dart
await progressSubscription.cancel();
await task.dispose();
```

任务 dispose 会取消活动下载，完成文件由宿主管理。重复 start、完成后 retry、dispose 后 start/retry 会抛出 `StateError`。正式文件提交已开始时，取消可能仍以 `completed` 结束，应以任务最终结果为准。

### 宿主校验与安装

下面的 `verify` 由宿主提供，可执行 SHA-256、签名和其他业务校验。此函数应由用户的“校验并安装”操作调用。

```dart
Future<ApkInstallResult> verifyAndInstall(
  ApkDownloadResult downloaded, {
  required Future<bool> Function(String filePath) verify,
}) async {
  if (downloaded.status != ApkDownloadState.completed ||
      downloaded.filePath == null) {
    throw StateError('需要已完成的下载文件');
  }
  final path = downloaded.filePath!;
  if (!await verify(path)) {
    throw StateError('校验失败，禁止安装');
  }
  return const UpgradeKit().installApk(path);
}
```

Android 插件包含未知来源安装权限声明和私有 FileProvider。安装返回值需要单独处理：

| `ApkInstallResult` | 后续处理 |
| --- | --- |
| `launched` | 系统安装器已打开，等待用户继续 |
| `permissionRequired` | 已打开授权页面；用户授权并返回后，再次校验并请求安装 |
| `fileNotFound` | 文件不存在或为空，检查文件生命周期 |
| `failed` | 请求安装失败，显示错误或允许重试 |

授权返回后无需重下载仍有效的完整文件，再次调用上述函数即可。宿主应在同一个私有文件上校验和安装。

以下 `expectedMd5` 由宿主提供。插件另支持可选 MD5：给 `ApkDownloadRequest` 或 `installApk()` 传 `expectedMd5` 即可。未提供或为空白时不执行 MD5；插件不会替代宿主的签名或 SHA-256 策略。

```dart
final valid = await upgradeKit.verifyCachedApk(
  absoluteApkPath,
  expectedMd5: expectedMd5,
  deleteInvalid: false, // 保留无效文件，供宿主诊断；默认 true 会清理。
);
print(valid);
```

## APK 会话与缓存复用

需要跨页面订阅状态、复用缓存并协调单个前台任务时，使用 `ApkUpgradeController`。`cacheDirectory` 由宿主提供，返回存在且可写的应用私有目录。

```dart
final controller = ApkUpgradeController(cacheDirectory: hostCacheDirectory);
final artifact = ApkArtifact(
  version: '2', // 宿主选择的版本标识，用于缓存身份。
  url: 'https://example.com/releases/app-2.apk',
  expectedMd5: expectedMd5,
);
final subscription = controller.states.listen((snapshot) {
  print('${snapshot.artifact?.version}: ${snapshot.receivedBytes}');
});
final preparation = await controller.prepareDownload(artifact);
print(preparation.name); // started / alreadyRunning / ready / busy / failed
```

- `prepareDownload()` 复用有效缓存或立即下载；相同版本和规范化 MD5 复用运行中的任务。
- 不同制品正在下载时返回 `busy`，宿主可用 `replaceExisting: true` 显式替换。
- `artifactPath(artifact)` 获取缓存路径；`verifyCachedApk(artifact, deleteInvalid: false)` 可校验并保留无效文件。
- `cancel()`、`retry()` 对应取消与从零重试，`install(artifact)` 仍需显式调用并处理安装结果。
- 页面退出时取消自己的订阅；会话结束时调用 `controller.dispose()`。

`states` 为新订阅者重放当前快照。`completed` / `isDownloadReady` 描述下载与缓存准备，不代表宿主校验、安装器启动或安装完成。安装前以实际校验结果为准，不能仅依赖历史快照；安装过程的返回值单独处理。

## 可选通用查询来源

如果希望插件协助规范查询结果和比较版本，可实现 `UpgradeSource` 或使用 `CallbackUpgradeSource`。网络库、协议、鉴权和当前版本仍由宿主提供：

```dart
final source = CallbackUpgradeSource((request) async {
  // 将宿主实际接口响应映射成 UpgradeRelease；这里只演示返回结构。
  return const UpgradeRelease(
    version: UpgradeVersion(versionName: '1.1.0', buildNumber: '2'),
    releaseNotes: '版本更新说明',
  );
});
final result = await const UpgradeKit().checkForUpdate(
  source: source,
  request: UpgradeCheckRequest(
    appId: 'com.example.app',
    currentVersion: const UpgradeVersion(versionName: '1.0.0', buildNumber: '1'),
    platform: 'android',
    channel: 'stable',
  ),
);
print(result.status.name);
```

默认比较优先使用双方的非负整数构建号，否则使用严格 SemVer。支持大整数构建号；不同应用、平台或发布渠道之间不要直接比较构建号。可注入 `comparator`，返回正数/零/负数表示更新/相同/更旧，返回 null 表示无法比较。

来源返回 null 表示确认没有发布版本，网络或协议失败应抛出异常。`failed` 与 `noUpdate` 分开处理；查询不会下载或打开链接，超时停止等待但不会取消宿主底层网络请求。

## 约束与兼容

下载为前台完整文件任务：流式写入临时文件，结束后提交；不提供自动重试、断点续传、后台进程恢复或静默安装。既有目标文件不会被覆盖，取消会等待清理。仅接受完整 HTTP 200 响应，跨域重定向剥离自定义请求头，HTTPS 不降级到 HTTP。状态、超时和错误码见 [详细行为说明](doc/STORE_AND_APK_FLOW.md)。

原生能力明确不支持时抛出 `UnsupportedError`；注册或方法缺失保留 `MissingPluginException`，其他原生错误用 `UpgradeKitException` 报告。

旧公开名称仍保留源码调用兼容，包括 `UpgradeService`、`UpgradeConfiguration`、`ApkUpgradePackage`、`packagePath()` 等。类型别名可能改变完整 `toString()` / `runtimeType` 文本；请勿把类型文本作为协议。迁移映射见 [命名与兼容说明](doc/NAMING_AND_MIGRATION.zh-CN.md)。

## 示例与文档

- [完整接入示例](doc/INTEGRATION.zh-CN.md)：五家 Android 厂商、iOS、鸿蒙及宿主全流程。
- [example](example/README.md)：运行与平台构建说明；Android 使用已连接真机 ID。
- [宿主示例实现](example/lib/host_apk_upgrade.dart)：manifest 请求、比较和 SHA-256 校验。
- [完整示例页面](example/lib/apk_upgrade_demo.dart)：弹窗、进度、取消重试及授权返回安装。

许可证：[Apache-2.0](LICENSE)。
