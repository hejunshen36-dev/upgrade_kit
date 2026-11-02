# upgrade_kit_ohos

HarmonyOS implementation of the federated `upgrade_kit` plugin.

It directly calls AppGallery Kit `checkAppUpdate` and `showUpdateDialog` with
the host `UIAbilityContext`. It contains no application-specific version,
ignore, or popup policy. This package is selected automatically by
`upgrade_kit`; applications should not depend on it directly.
