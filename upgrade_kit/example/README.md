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

## HarmonyOS HAP build

Use the same Flutter OHOS SDK for dependency resolution and building. Standard
Flutter does not generate the `plugins.ohos` registration metadata required by
the Hvigor Flutter plugin. In this workspace the validated SDK is
`/Users/shj/fvm/versions/custom_3.35.8` (3.35.8-ohos-1.0.4).

From the example directory on macOS, with the existing DevEco installation:

```sh
export FLUTTER_OHOS_SDK=/Users/shj/fvm/versions/custom_3.35.8
export DEVECO_CONTENTS=/Applications/DevEco-Studio.app/Contents
export JAVA_HOME="$DEVECO_CONTENTS/jbr/Contents/Home"
export NODE_HOME="$DEVECO_CONTENTS/tools/node"
export PATH="$FLUTTER_OHOS_SDK/bin:$NODE_HOME/bin:$PATH"

"$FLUTTER_OHOS_SDK/bin/flutter" pub get --offline
"$FLUTTER_OHOS_SDK/bin/flutter" build hap --debug --no-pub --no-codesign
```

The validated output is `build/ohos/hap/entry-default-unsigned.hap`, an arm64
Debug package. Signing and device installation are separate steps.

If a copied or relocated checkout reports `Cannot find module
'flutter-hvigor-plugin'`, check from `ohos/`:

```sh
node -p "require.resolve('flutter-hvigor-plugin')"
```

The plugin is supplied by the selected Flutter SDK at
`packages/flutter_tools/hvigor`, rather than a separately downloaded npm plugin.
An old npm lock can preserve a relative link to the checkout's former location.
Back up the generated `ohos/package-lock.json` and
`ohos/node_modules/.package-lock.json`, remove those stale locks and the broken
`ohos/node_modules/flutter-hvigor-plugin` symlink, then run from `ohos/`:

```sh
npm install --offline --ignore-scripts --no-audit --no-fund
node -p "require.resolve('flutter-hvigor-plugin')"
```

The resolved path must point to the selected SDK. Re-run that SDK's `pub get`
before building to regenerate both dependency metadata and the native plugin
registrant. A `filter` error in `hvigorconfig.ts` after repairing the link can
indicate that the metadata still lacks `plugins.ohos`.
