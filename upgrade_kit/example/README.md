# upgrade_kit example

[完整中文接入手册](../doc/INTEGRATION.zh-CN.md)说明五家 Android 厂商、iOS、鸿蒙配置，以及宿主检查/弹窗 → 下载进度/取消/重试 → 校验 → 安装的完整调用关系；本目录提供对应可运行源码。

Runnable three-platform example for the standalone `upgrade_kit` federated
plugin.

发布包中的 example 只包含 Dart 示例和文档，不包含平台工程。运行应用或执行下方平台构建命令时，请使用完整仓库中的 example。

Android example 的主 `AndroidManifest.xml` 已声明 `android.permission.INTERNET`，供商店查询、宿主版本请求和 APK 下载使用，覆盖 debug 与 release。运行 Android 示例时使用已连接的真机 ID。

The page exposes:

- Configured platform-store checking and explicit update actions. Enter an iOS
  numeric App Store ID in the store-target field; the example uses US lookup.
  Supply real Android vendor credentials in `_configuredStores()` as needed.
- A host-controlled APK upgrade form: host manifest query/comparison → host
  confirmation dialog → plugin progress/cancel/retry → host SHA-256 → explicit
  plugin installation. Manifest JSON fields: `versionCode` (non-negative integer
  or numeric string), `versionName`, `downloadUrl`, `sha256` (64 hex chars), and
  optional `releaseNotes`. Enter a new absolute filename inside an existing
  writable app files/cache directory. Use a trusted authenticated manifest
  endpoint; the example schema/auth policy is host code to replace.
- A host-owned upgrade query using a local callback fixture, runnable without
  native registration or a backend. Replace the callback with your repository
  request and normalize its response to `UpgradeRelease`.
- HarmonyOS AppGallery update checking (`Check OHOS store update`) and the native update dialog (`Show OHOS update dialog`).
- Android installation of an APK from an absolute app-accessible path.
- Android store URI and iOS numeric App Store ID launching.

Calls unsupported by the current platform are displayed as `Unsupported`
instead of being treated as application failures.

The query demo reports `updateAvailable: 1.1.0` against current version `1.0.0`.
It does not download, launch a store, or show an upgrade prompt automatically.
