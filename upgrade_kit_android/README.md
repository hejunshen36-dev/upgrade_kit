# upgrade_kit_android

Android implementation of the federated `upgrade_kit` plugin.

It opens the system APK installer through a private `FileProvider`, handles the
unknown-app-source permission flow, and launches explicit store URIs. This
package is selected automatically by `upgrade_kit`; applications should not
depend on it directly.

It also reports the current Android manufacturer, application package, and
installed version to the app-facing package, and resolves vendor-market routes
for Huawei, Honor, Xiaomi/Redmi, vivo/iQOO, OPPO/realme/OnePlus, and Samsung.
Network version queries and credentials remain in the Flutter app-facing layer;
this Android package does not depend on PipeX or contact vendor backends.
