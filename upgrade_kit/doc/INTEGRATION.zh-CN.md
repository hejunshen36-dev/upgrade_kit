# upgrade_kit 完整接入示例

适用于当前 `upgrade_kit`。插件提供两条独立路径：

| 路径 | 宿主负责 | 插件负责 |
| --- | --- | --- |
| 平台商店升级 | 提供配置，决定检查时机及是否执行更新动作 | Android 厂商查询/跳商店、iOS 商店版本查询/跳转、鸿蒙原生检查/系统弹窗 |
| 自建版本服务 | 请求接口、比较版本、业务弹窗、校验下载文件、决定安装时机 | APK 下载、进度、取消、从零重试、清理未完成文件、调用系统安装器 |

**下载完成不会自动安装。宿主校验通过后才调用安装。**

缓存校验 `verifyCachedApk(..., deleteInvalid: false)` 可保留无效文件，默认仍清理；`ApkUpgradeSnapshot.isDownloadReady` 仅表示最近的下载/缓存准备就绪，不代表宿主校验或安装完成。

本文采用整理后的推荐名称；旧 API 继续兼容，入口职责和名称对照见 [命名与迁移说明](NAMING_AND_MIGRATION.zh-CN.md)。

## 1. 依赖与入口

宿主运行时仅需依赖主包，不直接依赖三个平台实现包：

从 pub.dev 接入时使用 `upgrade_kit: ^0.0.1`。下面的本地 path 用法需要在宿主根配置四个传递包的本地覆盖；仓库内的 example 已提供对应覆盖。Git/path 完整写法见仓库根的 [PUBLISHING.md](https://github.com/hejunshen36-dev/upgrade_kit/blob/main/PUBLISHING.md)。

```yaml
dependencies:
  flutter:
    sdk: flutter
  upgrade_kit:
    path: ../upgrade_kit/upgrade_kit # 按宿主工程位置调整。
```

```dart
import 'package:upgrade_kit/upgrade_kit.dart';
```

如果采用下文示例的宿主 HTTP 请求和 SHA-256 校验实现，再显式声明 `http`、`crypto` 依赖；宿主已有网络/校验层时直接复用，不要求更换网络库。自带 example 已声明这些依赖。

Android 联网需要 `android.permission.INTERNET`，插件和 example 主 manifest 已声明。宿主应保留合并后的该权限，不能只配置 debug manifest；详见 [Android 联网权限](../README.md#android-联网权限)。

使用自带 example：进入 `upgrade_kit/example`，执行所选 SDK 的 `flutter pub get` 和 `flutter run`。鸿蒙必须使用 Flutter OHOS SDK 执行依赖解析和构建，详见 [example 构建说明](../example/README.md#harmonyos-hap-build)。

## 2. 配置 Android 厂商、iOS 与鸿蒙

以下字符串为占位值，接入时从宿主自己的运行时配置取得。只配置实际使用的 Android 厂商，其余字段可省略；不要直接运行占位凭证查询。

```dart
final upgradeService = StoreUpgradeService(
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
        requestTimeout: const Duration(seconds: 15),
      ),
      locale: 'zh-CN',
      fallbackTarget: 'market://details?id=com.example.app',
    ),
    ios: IosStoreUpgradeConfiguration(
      appId: '1234567890', // 替换为应用真实数字 App Store ID，不是 bundle ID。
      country: 'cn',
      requestTimeout: const Duration(seconds: 15),
    ),
    ohos: const OhosStoreUpgradeConfiguration(),
  ),
);
```

平台配置差异：

| 平台 | 配置及实际行为 |
| --- | --- |
| Android | 自动识别当前设备厂商，只查询该厂商。华为、荣耀、小米、vivo、OPPO 支持查询；三星和未知厂商查询返回 `unsupported`，仍可显式尝试商店路由/备用地址。匹配厂商未配置时返回 `notConfigured`。 |
| iOS | 使用配置的 App Store ID 和地区查询发布版本，读取本机 `CFBundleShortVersionString` 后按数字分段比较。地区默认 `us`；商店实际跳转跟随用户账户。不存在的商店条目为 `failed/not-found`。 |
| 鸿蒙 | 配置为启用标记；应用身份取自宿主 UIAbility，检查与弹窗使用 AppGallery Kit。宿主仍需满足应用注册、签名、商店分发及前台 Ability 条件。 |

客户端内的厂商凭证无法作为不可提取的秘密；配置与账号权限由宿主管理。插件不记录这些凭证。

## 3. 三端商店的统一调用

```dart
final result = await upgradeService.checkStoreUpgrade();

switch (result.status) {
  case StoreUpgradeCheckStatus.updateAvailable:
    // Android/iOS 可读取版本、说明等；鸿蒙 result.release 可能为空。
    final notes = result.release?.releaseNotes ?? '发现新版本';
    // 将 notes 展示给宿主 UI，再由宿主决定是否执行更新动作。
    break;
  case StoreUpgradeCheckStatus.noUpdate:
    // 已完成检查，没有更新。
    break;
  case StoreUpgradeCheckStatus.notConfigured:
    // 缺少当前平台或当前 Android 厂商的配置。
    break;
  case StoreUpgradeCheckStatus.unsupported:
    // 当前平台/厂商不支持检查，可由宿主提供其他入口。
    break;
  case StoreUpgradeCheckStatus.failed:
    // 记录/展示 result.errorCode；不能按“没有更新”处理。
    break;
}
```

宿主确认继续后调用一次：

```dart
final action = await upgradeService.requestStoreUpgrade();
```

| 动作结果 | 含义 |
| --- | --- |
| `storeLaunched` | Android 厂商商店或 iOS App Store 已打开 |
| `dialogShown` | 鸿蒙原生更新弹窗已展示 |
| `notShown` | 鸿蒙原生接口没有展示弹窗 |
| `failed` | 商店打开失败 |

`checkStoreUpgrade()` 不会自行跳商店或显示弹窗。商店打开/系统弹窗展示均不代表更新已经安装完成。调用商店动作前未配置平台时抛出 `StateError`；插件注册缺失保留 `MissingPluginException`，需修复集成配置，不能当作无更新。

需要业务确认框时，宿主可使用：

```dart
Future<bool> confirmUpgrade(
  BuildContext context, {
  required String title,
  required String notes,
}) async {
  if (!context.mounted) return false;
  return await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(notes),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('暂不更新'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('继续更新'),
        ),
      ],
    ),
  ) ?? false;
}
```

该函数是宿主代码，需要 `package:flutter/material.dart`。异步检查返回后，先确认页面仍 mounted，再弹框/刷新 UI；鸿蒙也可以直接调用 `requestStoreUpgrade()`，将确认过程交给系统弹窗。

## 4. 自建服务：宿主请求与版本比较

此路径不必调用插件的 `checkForUpdate()` 或实现 `UpgradeSource`。自带 [HostApkUpgrade](../example/lib/host_apk_upgrade.dart) 是**宿主示例代码**，负责以下 JSON 协议、网络请求、比较和 SHA-256 校验，宿主可按自己的接口替换：

```json
{
  "versionCode": "2",
  "versionName": "1.1.0",
  "downloadUrl": "https://example.com/releases/app-2.apk",
  "sha256": "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  "releaseNotes": "本次版本的更新说明"
}
```

这是结构示例；哈希是测试字节 `abc` 的 SHA-256，接入时必须替换为实际 APK 的摘要。`versionCode` 支持非负整数或数字字符串。宿主选择可信的版本元数据接口、鉴权与比较策略。

```dart
// 以下代码位于自带 example，可直接使用该宿主辅助类。
import 'host_apk_upgrade.dart';

final host = HostApkUpgrade();
final release = await host.check(
  Uri.parse('https://example.com/api/latest-version'),
  currentBuild: BigInt.from(1), // 替换为宿主取得的实际当前构建号。
);
if (release == null) {
  // 宿主比较后确认无需更新；结束流程。
  return;
}
```

宿主随后用 `release.versionName`、`release.releaseNotes` 展示自己的升级弹窗。用户确认后再创建下载任务；页面已退出或用户取消弹窗时不开始下载。

## 5. 创建任务、显示进度与处理下载结果

下面的 `task`、`subscription`、`release` 和下载结果应保存在同一个页面 State/Controller 中，以便按钮调用取消、重试和校验安装。不要在首次失败后立即 dispose，否则不能重试。

```dart
const upgradeKit = UpgradeKit();
final task = upgradeKit.createApkDownload(
  ApkDownloadRequest(
    url: release.downloadUrl,
    filePath: absoluteApkPath,
    headers: downloadAuthHeaders,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ),
);

final subscription = task.progress.listen((progress) {
  // 更新宿主 UI。页面销毁后不再 setState。
  final bytes = progress.receivedBytes;
  final total = progress.totalBytes;
  final ratio = progress.fraction;
  final attempt = progress.attempt;
  // total/ratio 为 null 时显示已下载字节和不确定进度，不伪造百分比。
});

final downloaded = await task.start();
switch (downloaded.status) {
  case ApkDownloadState.completed:
    // downloaded.filePath 是已关闭并提交的正式文件，等待宿主校验。
    break;
  case ApkDownloadState.cancelled:
    // 未完成文件已清理；可以显式重试。
    break;
  case ApkDownloadState.failed:
    // 根据 downloaded.errorCode 显示错误/重试按钮。
    break;
  default:
    throw StateError('下载返回了非终态');
}
```

`absoluteApkPath` 是宿主提供的绝对路径：父目录已存在且可写，文件名尚不存在。安装时应位于应用私有 files/cache 或 external-files 范围，不能随意传一个安装器无法读取的路径。插件不负责申请公共存储权限或选择宿主目录。

`downloadAuthHeaders` 是宿主提供的 `Map<String, String>`，无需鉴权时传空 Map 或省略 headers。跨域重定向会剥离自定义请求头；不要依赖原站凭证继续发送到另一个下载域名。`Range`、`Host`、`Content-Length`、`Accept-Encoding` 由下载器管理。

| 状态/进度 | 宿主处理 |
| --- | --- |
| `connecting` / `downloading` | 显示进度，允许取消 |
| `cancelling` | 等待资源清理，暂不重试 |
| `cancelled` / `failed` | 任务 Future 返回后可重试 |
| `completed` | 显示“校验并安装”，不自动安装 |
| `receivedBytes` | 当前尝试已写入字节 |
| `totalBytes` / `fraction` | 总大小及 0～1 进度；未知时为空 |
| `attempt` | 尝试次数；重试时增加 |

晚订阅时可先读取 `task.snapshot`。默认连接/响应头超时 15 秒，读取空闲超时 30 秒。

## 6. 取消、重试与页面退出

取消按钮：

```dart
await task.cancel(); // 等待连接、文件写入与未完成文件清理。
```

失败/取消后，等待原 `start()`/`retry()` 返回，再启用重试按钮：

```dart
final retried = await task.retry();
// 用新结果替换旧 downloaded，并按第 5 节处理其终态。
```

重试沿用同一 URL、请求头、目标路径，**从零重新下载**，不自动重试、不续传。需要刷新过期 URL/凭证时，dispose 旧任务并创建新任务。

取消与完成竞态：若正式文件提交已经开始，`cancel()` 等待结束后可能得到 `completed`；以任务 Future 的最终结果为准，不根据点击过取消按钮就假定文件不存在。

页面退出或流程结束时：

```dart
await subscription.cancel();
await task.dispose();
```

Flutter `State.dispose()` 不能 await，现有示例使用：

```dart
@override
void dispose() {
  unawaited(subscription?.cancel());
  unawaited(task?.dispose());
  super.dispose();
}
```

这里字段需要声明为可空，且导入 `dart:async`。任务 dispose 会取消活动下载；dispose 后不允许再次 start/retry。成功下载的正式文件属于宿主，由宿主决定何时删除。

## 7. 宿主校验与显式安装

自带 `HostApkUpgrade.verifyAndInstall` 的实际逻辑：

```dart
// 导入 dart:io、package:crypto/crypto.dart。
if (downloaded.status != ApkDownloadState.completed ||
    downloaded.filePath == null) {
  throw StateError('必须先完成下载');
}

final path = downloaded.filePath!;
final digest = await sha256.bind(File(path).openRead()).first;
if (digest.toString() != release.sha256Hex) {
  throw StateError('校验失败，禁止安装');
}

final installResult = await upgradeKit.installApk(path);
```

自带 example 也可直接调用宿主辅助方法：

```dart
final installResult = await host.verifyAndInstall(downloaded, release);
```

两种方式选择一种即可。安装接口本身不执行宿主的哈希/签名策略，必须由宿主保证校验步骤；在同一个私有目录文件上校验并安装，避免将校验后的路径替换成其他文件。

| 安装结果 | 后续动作 |
| --- | --- |
| `launched` | 系统安装器已打开；不等于安装完成 |
| `permissionRequired` | 已打开未知来源安装授权页；等待用户授权并返回应用，再校验并调用安装 |
| `fileNotFound` | 文件不存在/为空；检查文件生命周期，必要时重新下载 |
| `failed` | 安装器启动失败；展示失败并保留诊断/重试入口 |

授权返回后，不必重新下载仍然存在的完整文件；再次调用 `host.verifyAndInstall(downloaded, release)` 即可重新校验并尝试安装。只在用户明确操作或应用确认授权后触发，避免恢复页面时反复打开授权设置。

APK 安装仅支持 Android。iOS、鸿蒙的商店更新使用第 2～3 节，不调用 APK 安装流程。

## 8. 直接查看和运行完整源码

| 文件 | 内容 |
| --- | --- |
| [main.dart](../example/lib/main.dart) | Flutter 启动入口、平台商店配置服务及原有能力入口 |
| [host_apk_upgrade.dart](../example/lib/host_apk_upgrade.dart) | 宿主 HTTP 请求、版本比较、下载任务创建、SHA-256 校验与显式安装 |
| [apk_upgrade_demo.dart](../example/lib/apk_upgrade_demo.dart) | 完整 StatefulWidget：表单、业务弹窗、任务保存、进度、取消、重试、校验安装、退出清理 |
| [host_apk_upgrade_test.dart](../example/test/host_apk_upgrade_test.dart) | 本地服务验证下载后不自动安装，以及文件篡改阻止安装 |

运行 example 后：

1. 使用“Check configured store / Update through configured store”操作平台商店；Android 示例默认未填凭证，需要按第 2 节补齐；iOS 在商店目标输入框填写数字 App Store ID，示例地区为 US。
2. 使用“Host-controlled APK update”输入宿主 manifest 地址、当前构建号及新 APK 保存路径。
3. 点击检查，宿主请求并比较；发现新版本后展示确认弹窗。
4. 确认下载后观察进度，可取消；失败或取消后可点击重试。
5. 下载完成后点击“Verify and install”；校验失败会阻止安装。
6. 需要安装授权时按提示授权、返回，再次点击“Verify and install”。

该示例是前台任务流程，不包含后台进程恢复、断点续传或静默安装。错误码和底层传输约束见 [详细 API 行为](STORE_AND_APK_FLOW.md)。
