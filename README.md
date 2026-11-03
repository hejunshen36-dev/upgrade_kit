# upgrade_kit

支持 Android、iOS 和 HarmonyOS 的 Flutter 应用升级插件，提供平台商店升级和宿主主导的 APK 升级两条接入路径。

- **平台商店升级**：配置 Android 厂商、iOS App Store ID 或鸿蒙 AppGallery，统一检查版本并显式打开商店或原生弹窗。
- **自建服务升级**：宿主完成网络请求、版本比较和业务弹窗，插件负责 APK 下载、进度、取消、重试及显式请求安装；文件校验策略由宿主决定。

下载完成不会自动安装，打开商店或系统安装器也不代表升级已经完成。

## 平台能力

| 能力 | Android | iOS | HarmonyOS |
| --- | --- | --- | --- |
| 配置化商店检查 | 华为、荣耀、小米、vivo、OPPO | App Store 版本查询 | AppGallery 原生检查 |
| 显式商店升级动作 | 跳转厂商商店 | 跳转 App Store | 展示原生更新弹窗 |
| APK 下载、进度、取消、从零重试 | 支持 | 不作为应用升级方式 | 不作为应用升级方式 |
| APK 安装及安装授权引导 | 支持 | 不支持 | 不支持 |
| 宿主自定义查询来源与比较器 | 支持 | 支持 | 支持 |

三星和未知 Android 厂商不支持内置版本查询，仍可尝试商店路由或备用地址。插件不提供业务升级弹窗、强制升级策略、忽略版本存储、断点续传或后台进程恢复。

## 环境与接入

要求 Dart 3.9.2+、Flutter 3.35.7+。鸿蒙构建使用兼容的 Flutter OHOS SDK 和 DevEco 工具链。

Android 厂商查询、宿主版本请求和 APK 下载需要 `android.permission.INTERNET`。插件与 example 的主 manifest 均已声明；宿主应保留合并后的联网权限，不能只依赖 debug manifest。配置示例见 [Android 联网权限](upgrade_kit/README.md#android-联网权限)。

从 pub.dev 接入时，宿主仅需声明主包：

```yaml
dependencies:
  upgrade_kit: ^1.0.1
```

使用本地源码或 Git 接入时，宿主还需在根 pubspec 中覆盖四个传递包的来源。完整写法见 [Git/path 接入](PUBLISHING.md#pubdev-与-git-接入)；仓库中的 example 已配置本地覆盖。

```dart
import 'package:upgrade_kit/upgrade_kit.dart';
```

## 选择入口

| 入口 | 使用场景 |
| --- | --- |
| `StoreUpgradeService` | 配置 Android、iOS、鸿蒙商店，统一检查并请求商店升级 |
| `UpgradeKit` | 宿主自行管理下载任务、文件路径、校验和安装；也可接入通用查询来源 |
| `ApkUpgradeController` | 插件协调前台 APK 会话、缓存复用、进度、取消和重试 |

商店流程：配置 → `checkStoreUpgrade()` → 宿主确认 → `requestStoreUpgrade()`。

自建服务流程：宿主请求并比较 → 宿主弹窗 → 插件下载与进度 → 宿主校验 → 插件请求安装 → 必要时授权返回后再次校验并安装。

具体配置与可复制代码见 [主包 README](upgrade_kit/README.md) 和 [完整接入示例](upgrade_kit/doc/INTEGRATION.zh-CN.md)。

## 运行 example

```sh
cd upgrade_kit/example
flutter pub get
flutter run -d YOUR_ANDROID_DEVICE_ID
```

`YOUR_ANDROID_DEVICE_ID` 替换为 `flutter devices` 列出的已连接真机 ID。example 提供商店检查、自建服务升级弹窗、下载进度、取消重试及 SHA-256 校验安装。厂商凭证、App Store ID、自建 manifest 地址和应用私有下载路径需按宿主配置。

鸿蒙的依赖解析与 HAP 构建必须使用同一 Flutter OHOS SDK，命令见 [example 构建说明](upgrade_kit/example/README.md#harmonyos-hap-build)。

## 仓库结构

本仓库采用 Federated Plugin 架构，宿主使用主包，平台实现由主包默认注册。

| Package | 职责 |
| --- | --- |
| [upgrade_kit](upgrade_kit) | 公开 API、商店服务、通用查询和 APK 会话 |
| [upgrade_kit_platform_interface](upgrade_kit_platform_interface) | 平台契约、原生结果和异常 |
| [upgrade_kit_android](upgrade_kit_android) | Android 安装器、权限与商店路由 |
| [upgrade_kit_ios](upgrade_kit_ios) | iOS 当前版本读取与 App Store 跳转 |
| [upgrade_kit_ohos](upgrade_kit_ohos) | 鸿蒙 AppGallery 原生检查与弹窗 |

主包内部按 `check/`、`store/`、`apk/`、`compat/` 分层。宿主统一导入 `package:upgrade_kit/upgrade_kit.dart`，避免依赖 `lib/src` 内部路径。

## 开发、验证与发布

```sh
# 在临时快照中检查五个包及 example，不上传。
FLUTTER_BIN=/path/to/flutter ./tool/publish.sh --check

# 检查指定包的真实 hosted 依赖和 Pub 发布清单，不上传。
FLUTTER_BIN=/path/to/flutter ./tool/publish.sh --dry-run --package upgrade_kit_platform_interface
```

发布顺序为接口包 → 三个平台实现包 → 主包。GitHub CI 执行全部包的预检，手动发布检查工作流只执行 dry-run。上传需维护者显式运行 `--publish --package NAME`。命令、版本管理和发布前置条件见 [发布说明](PUBLISHING.md)。

## 文档

- [主包 API 与接入指南](upgrade_kit/README.md)
- [Android 厂商、iOS、鸿蒙及自建服务完整示例](upgrade_kit/doc/INTEGRATION.zh-CN.md)
- [下载状态、传输约束与错误码](upgrade_kit/doc/STORE_AND_APK_FLOW.md)
- [命名与兼容迁移](upgrade_kit/doc/NAMING_AND_MIGRATION.zh-CN.md)
- [example 与平台构建](upgrade_kit/example/README.md)

许可证：[Apache-2.0](LICENSE)。
