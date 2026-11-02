# 命名、职责与兼容迁移

## 推荐入口

宿主仍统一导入 `package:upgrade_kit/upgrade_kit.dart`。

| 入口 | 职责 |
| --- | --- |
| `StoreUpgradeService` | 依据 Android、iOS、OHOS 配置检查商店版本，显式打开商店或鸿蒙原生弹窗 |
| `ApkUpgradeController` | 协调单个前台 APK 会话，包括缓存复用、下载、可选 MD5 校验、取消、重试和显式安装 |
| `UpgradeKit` | 提供基础下载、校验、安装、原生商店能力，以及可选的宿主查询来源接口 |

自建服务的网络请求、版本比较、业务弹窗和安装前校验策略由宿主决定。需要自己指定文件路径和执行 SHA-256 等校验时，使用 `UpgradeKit.createApkDownload()` 与 `installApk()`；需要插件协调缓存与任务生命周期时，使用 `ApkUpgradeController`。

`StoreUpgradeService` 不提供 APK 下载或安装方法。旧 `UpgradeService` 作为兼容门面保留原有商店、下载、校验和安装能力；新代码按上表选择入口，无需创建空商店配置来下载 APK。

## 目录

保留五个 Federated package、包名、默认实现注册、原生插件类与 MethodChannel 协议。主包按能力组织：

```text
lib/
├── upgrade_kit.dart
└── src/
    ├── check/                  # 通用查询来源、模型与版本比较
    ├── store/
    │   ├── android_vendor/     # 厂商配置、协议适配与比较
    │   ├── store_upgrade_service.dart
    │   ├── store_upgrade_configuration.dart
    │   ├── store_upgrade_models.dart
    │   └── upgrade_service.dart # 旧内部导入路径的转发文件
    ├── compat/
    │   └── legacy_upgrade_service.dart # 旧 UpgradeService 实现
    └── apk/
        ├── download/
        ├── verification/
        ├── installation/
        └── apk_upgrade_controller.dart
```

`lib/src` 是内部实现路径；宿主应通过公开主入口导入，不依赖内部路径稳定性。

## 名称映射

以下旧公开名称继续可用。类型采用别名，保留构造函数、枚举成员及类型兼容；旧方法转发到新实现。本次不添加弃用告警，已有宿主可逐步迁移。

| 旧名称 | 推荐名称 |
| --- | --- |
| `UpgradeService` | `StoreUpgradeService`；其 APK 能力改用 `UpgradeKit` / `ApkUpgradeController` |
| `UpgradeConfiguration` | `StoreUpgradeConfiguration` |
| `UpgradeStorePlatform` | `StoreUpgradePlatform` |
| `StoreUpdateStatus` | `StoreUpgradeCheckStatus` |
| `StoreUpdateResult` | `StoreUpgradeCheckResult` |
| `StoreUpdateAction` | `StoreUpgradeActionResult` |
| `UpgradeService.checkStoreUpdate()` | `StoreUpgradeService.checkStoreUpgrade()` |
| `UpgradeService.performStoreUpdate()` | `StoreUpgradeService.requestStoreUpgrade()` |
| `AndroidVendorUpdateStatus` | `AndroidVendorUpgradeCheckStatus` |
| `AndroidVendorUpdateResult` | `AndroidVendorUpgradeCheckResult` |
| `UpgradeKit.checkAndroidVendorUpdate()` | `UpgradeKit.checkAndroidVendorUpgrade()` |
| `UpgradeKit.checkAppUpdate()` | `UpgradeKit.checkOhosStoreUpdate()`，仅适用于鸿蒙原生商店 |
| `UpgradeKit.showUpdateDialog()` | `UpgradeKit.showOhosUpdateDialog()`，仅适用于鸿蒙原生弹窗 |
| `UpgradeKit.isApkReady()` | `UpgradeKit.verifyCachedApk()` |
| `ApkUpgradePackage` | `ApkArtifact` |
| `ApkUpgradePreparation` | `ApkPrepareResult` |
| `ApkUpgradeController.prepare()` | `ApkUpgradeController.prepareDownload()` |
| `ApkUpgradeController.isReady()` | `ApkUpgradeController.verifyCachedApk()` |
| `ApkUpgradeSnapshot(package: ...)` | `ApkUpgradeSnapshot(artifact: ...)`；两个参数仅选一个 |
| `ApkUpgradeSnapshot.package` | `ApkUpgradeSnapshot.artifact` |
| `ApkUpgradeController.packagePath()` | `ApkUpgradeController.artifactPath()`；缓存命名规则不变 |
| `ApkUpgradeSnapshot.isReady` | `ApkUpgradeSnapshot.isDownloadReady` |

原生接口里的 `checkAppUpdate`、`showUpdateDialog` 等协议名称保持不变。通用宿主查询接口 `checkForUpdate()` 与 `UpgradeCheckResult` 保持兼容。商店和厂商新增领域类型统一使用 `Upgrade` 前缀。

## 明确副作用与结果含义

- `prepareDownload()` 可能复用缓存，也可能立即开始下载；返回 `started` 表示任务已启动，完整状态通过 `states` 观察。
- `verifyCachedApk()` 只接受宿主拥有的文件，检查非空字节和可选 MD5。`deleteInvalid` 默认 `true`，保持旧 API 的无效文件清理行为；传 `false` 可保留无效文件供宿主诊断。控制器版本仍可在校验通过时发布就绪状态，因此关闭删除不等于关闭状态发布。
- `snapshot.state` / `snapshot.isDownloadReady` 只描述最近观察到的下载与缓存准备状态。`completed` 不代表宿主已完成签名或 SHA-256 校验，也不代表安装器已启动或安装完成；文件随后被删除/修改时，快照不会自动监听变化，需重新校验。
- 控制器 `states` 不跟踪安装阶段。显式 `install()` 的返回值单独处理；其可选校验阶段使用 `onVerificationChanged` 回调。
- `isApkReady()`、控制器 `isReady()`、缓存准备、下载中的 MD5 检查及安装前 MD5 检查继续保持原有清理行为；新增保留选项只用于显式 `verifyCachedApk()` 调用。
- `requestStoreUpgrade()` 表示请求打开商店或原生弹窗，返回 `storeLaunched` / `dialogShown` 不代表升级完成。
- `installApk()` / 控制器 `install()` 仍需显式调用。`ApkInstallResult.launched` 表示系统安装器已启动，`permissionRequired` 表示需要授权返回后再次尝试。

## 显式选择校验清理策略

```dart
const upgradeKit = UpgradeKit();
final valid = await upgradeKit.verifyCachedApk(
  hostApkPath,
  expectedMd5: hostExpectedMd5,
  deleteInvalid: false, // 校验失败保留文件，由宿主决定后续处理。
);
// 默认省略 deleteInvalid 时，无效文件会被清理。
// 控制器同样支持 controller.verifyCachedApk(artifact, deleteInvalid: false)。
```

省略或传入空白 MD5 时只检查普通文件非空，不验证 APK 格式或签名。宿主如要求 SHA-256、签名或版本身份验证，应在请求安装前自行完成。

## APK 会话示例

```dart
final controller = ApkUpgradeController(
  cacheDirectory: hostCacheDirectory, // 宿主提供 Future<String> Function()。
);
final artifact = ApkArtifact(
  version: '2',
  url: 'https://example.com/releases/app.apk',
  expectedMd5: hostExpectedMd5, // 可选；宿主可另外执行自己的校验策略。
);
final subscription = controller.states.listen(hostRenderUpgrade);

// 宿主完成检查、比较和用户确认后：
final result = await controller.prepareDownload(artifact);
// 在 states 里观察进度，按宿主操作调用 cancel() / retry()。
// 缓存就绪并通过宿主要求的校验后，再显式调用：
// await controller.install(artifact);

// 页面退出时仅取消页面订阅；会话结束时释放控制器。
// await subscription.cancel();
// await controller.dispose();
```

完整商店配置和宿主 SHA-256 流程见 [完整接入示例](INTEGRATION.zh-CN.md)。
