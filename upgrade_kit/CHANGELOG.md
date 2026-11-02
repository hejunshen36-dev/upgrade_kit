## 0.0.1

* Configure pub.dev metadata, hosted federated dependencies and local development overrides.
* Add repository-level clean-snapshot publishing checks and GitHub CI.

* Complete Artifact naming with snapshot `artifact`, `artifactPath()` and
  `isDownloadReady`, retaining old constructors, getters and methods.
* Move the legacy service implementation into `compat/` and keep its old import
  path forwarding. Clarify download-only states and OHOS example labels.
* Add explicit `verifyCachedApk(deleteInvalid: false)` file retention; default
  verification and legacy cleanup behavior stay unchanged.

* Organize implementation by `check`, `store` and `apk` capabilities.
* Add focused `StoreUpgradeService` / `StoreUpgradeConfiguration`, consistent
  store/vendor result names, `ApkArtifact` and `ApkPrepareResult`.
* Clarify OHOS-only operations, download preparation and cached-file verification
  with explicit method names. Keep existing public types and methods compatible.
* Update examples to separate configured stores from host-controlled APK work;
  document migration and invalid cached-file cleanup behavior.

* Add configured Android/iOS/OHOS store service with automatic platform routing.
* Query iOS App Store releases and compare against the native current version.
* Add foreground streamed APK tasks with progress, cancellation, manual retry,
  protected destinations and partial-file cleanup; downloads never auto-install.
* Demonstrate host-owned HTTP checks, comparison, popup and SHA-256 verification
  before explicit installation in the example.

* Add host-supplied upgrade sources, normalized requests/releases/results and
  `UpgradeKit.checkForUpdate` without native registration or new dependencies.
* Add strict SemVer and arbitrary-size build number comparison, a custom
  comparator extension point, explicit query failures and timeouts.
* Preserve existing native and Android vendor API signatures and behavior.
* Keep missing native registration diagnosable as `MissingPluginException`;
  explicit platform unsupported errors remain `UnsupportedError`.
* Normalize invalid native response types to `invalid-response` errors.
* Add a runnable local-source example and integration documentation.

* Add federated Android, iOS, and HarmonyOS implementations.
* Support Android APK installation and store URI launch.
* Support iOS App Store launch.
* Support HarmonyOS AppGallery update checks and native update dialogs.
* Add Android vendor context, automatic market routing, and Flutter-side
  Huawei, Honor, Xiaomi, vivo, and OPPO version queries.
