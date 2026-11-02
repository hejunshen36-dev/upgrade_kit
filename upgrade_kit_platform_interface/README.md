# upgrade_kit_platform_interface

Shared platform contract for the federated `upgrade_kit` plugin.

Applications should depend on `upgrade_kit`, not this package. Platform
implementations extend `UpgradeKitPlatform` and return the typed result enums
defined here.

Native implementations should return the `unsupported` error code for a known
unsupported capability. Missing methods or registration preserve
`MissingPluginException` for diagnosis. Unexpected result types and values are
reported as `UpgradeKitException` with code `invalid-response`.

Host-owned query source models live in the app-facing package because they do
not require a platform channel implementation.
