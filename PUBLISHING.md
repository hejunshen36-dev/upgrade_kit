# 发布与 GitHub 配置

本仓库采用临时发布快照，按五包 Federated 依赖关系执行预检和发布。默认目标为 pub.dev，不在 pubspec 中填写 `publish_to`。各包 `repository` / `homepage` / `issue_tracker` 指向 `https://github.com/hejunshen36-dev/upgrade_kit` 及对应子目录；执行发布前需确认远程仓库存在且可公开访问。

## 本地开发与预检

需要 Flutter 3.35.7 或更新兼容版本、Dart 3.9.2+、Python 3.10+。GitHub CI 固定使用 Flutter 3.35.7。本地可指定 SDK：

```sh
FLUTTER_BIN=/path/to/flutter ./tool/publish.sh --check
FLUTTER_BIN=/path/to/flutter ./tool/publish.sh --check --offline
```

`--check` 在临时目录复制允许发布的输入，用本地五包覆盖执行依赖解析、格式检查、静态分析、单元测试及 example 测试。`--offline` 只适用于外部依赖已缓存的 `--check`。脚本不改变工作区版本、依赖和生成文件；退出时删除临时目录。

各正式 pubspec 使用 hosted 版本依赖，仓库内提交的 `pubspec_overrides.yaml` 用于本地开发和 example。Pub 只应用当前根包的覆盖，因此主包、三个实现包和 example 分别提供覆盖；覆盖文件不进入发布包。不要把这些覆盖当成发布后宿主可自动继承的设置。

发布工具自身的测试不上传任何包：

```sh
python3 -m unittest discover -s tool -p 'test_*.py'
```

## 发布顺序

当前五个包的版本均为 `1.0.1`。发布前分别更新版本、CHANGELOG 和内部依赖约束；同时保持 iOS podspec、OHOS oh-package 版本一致。已发布版本不能覆盖。

依次处理以下包，接口包先发布，主包最后发布；三个平台包之间没有依赖，可以任意排序：

1. `upgrade_kit_platform_interface`
2. `upgrade_kit_android`
3. `upgrade_kit_ios`
4. `upgrade_kit_ohos`
5. `upgrade_kit`

```sh
# 默认也是 --dry-run：完整本地预检 + 真实 hosted 依赖解析 + Pub 校验。
./tool/publish.sh --dry-run --package upgrade_kit_platform_interface

# 仅在维护者明确执行此命令时，预检通过后上传指定的一个包。
./tool/publish.sh --publish --package upgrade_kit_platform_interface
```

重复上面两条命令处理后续包。`--publish` 必须指定一个包，避免自动批量上传；Pub 管理登录和发布权限，不在仓库保存凭证。未指定包的 `--dry-run` 按依赖顺序验证全部五包，但首次发布前后续包可能因依赖尚未发布而失败，这是发布前置条件，不能用本地覆盖或忽略警告绕过。

最终 Pub 校验和上传前会移除临时覆盖，重新解析真实 hosted 依赖。任何依赖、格式、分析、测试或 Pub 警告/错误都会停止流程；不使用忽略验证选项。仓库已配置 repository，缺少仓库地址的警告也会阻止发布。

example 对主包始终保留 `path: ../`，归档后该路径仍指向同包根目录。平台接口开发依赖使用 hosted 版本约束，本地开发由 example 的覆盖文件指向同仓库接口包。发布脚本只移除临时覆盖，不改写 example 的 pubspec，避免首次发布前解析尚不存在的主包自身 hosted 版本。

发布快照仅包含 Dart 源码、测试、公开文档、精简 example 以及 Android/iOS/OHOS 必要源码和构建描述。工作区缓存、QA 产物、签名、本地配置、示例平台工程和维护脚本不进入包。原始签名、作者和许可证归属不作迁移。

## GitHub

- 仓库根目录是本文件所在的外层 `upgrade_kit/`，五个 package 是同级子目录。
- `.github/workflows/ci.yml` 在 main/master push、PR 和手动触发时执行发布工具测试及全部包的本地预检，不启动 Android 模拟器。
- `.github/workflows/publish-check.yml` 手动选择一个包，执行真实依赖的 dry-run，不上传。首次发布依赖包之前，相关包的校验可能失败。
- 工作流只有 `contents: read`，不需要 Pub token，也没有自动上传或创建 Release 的动作。
- 将本目录作为 Git 仓库根提交；使用其他仓库地址时，同步修改五个 pubspec、podspec 和 `tool/publish.py` 中的地址。

## pub.dev 与 Git 接入

宿主仅需添加主包的 hosted 依赖：

```yaml
dependencies:
  upgrade_kit: ^1.0.1
```

首次发布前也可以完整克隆本仓库，运行自带 example。如果宿主使用 Git 主包且需要整套本地源码实现，必须在**宿主根 pubspec** 中显式覆盖四个传递包，不能只引用主包后期待其开发覆盖被继承：

```yaml
dependencies:
  upgrade_kit:
    git:
      url: https://github.com/hejunshen36-dev/upgrade_kit.git
      ref: YOUR_COMMIT_SHA
      path: upgrade_kit

dependency_overrides:
  upgrade_kit_platform_interface:
    git:
      url: https://github.com/hejunshen36-dev/upgrade_kit.git
      ref: YOUR_COMMIT_SHA
      path: upgrade_kit_platform_interface
  upgrade_kit_android:
    git:
      url: https://github.com/hejunshen36-dev/upgrade_kit.git
      ref: YOUR_COMMIT_SHA
      path: upgrade_kit_android
  upgrade_kit_ios:
    git:
      url: https://github.com/hejunshen36-dev/upgrade_kit.git
      ref: YOUR_COMMIT_SHA
      path: upgrade_kit_ios
  upgrade_kit_ohos:
    git:
      url: https://github.com/hejunshen36-dev/upgrade_kit.git
      ref: YOUR_COMMIT_SHA
      path: upgrade_kit_ohos
```

所有 ref 替换成同一个真实提交 SHA。外部宿主使用本地 path 主包时，同样在宿主根覆盖四个包为各自本地 path。

Android/iOS 使用官方 Flutter；HAP 构建仍需 Flutter OHOS SDK、DevEco 与签名环境。以上纯 Dart 预检不代替平台构建、真机验证或 Pub 服务端的名称/发布权限确认。

参考：[Pub 发布](https://dart.dev/tools/pub/publishing)、[依赖覆盖](https://dart.dev/tools/pub/dependencies#pubspec_overridesyaml)。
