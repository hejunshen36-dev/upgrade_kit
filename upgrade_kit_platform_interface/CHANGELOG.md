## 1.0.1

* Align all five federated packages and internal dependencies at version 1.0.1.

## 0.0.1

* Configure pub.dev metadata, hosted federated dependencies and local development overrides.
* Add repository-level clean-snapshot publishing checks and GitHub CI.

* Add the iOS current marketing-version channel contract for configured checks.

* Preserve `MissingPluginException` for missing native method registration,
  keeping explicit `unsupported` errors mapped to `UnsupportedError`.
* Report native values with unexpected types as `invalid-response`.

* Define the shared upgrade contract, typed results, and platform exceptions.
* Add typed Android store context and current-app market routing contracts.
