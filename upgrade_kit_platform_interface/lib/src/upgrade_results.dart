/// Result of checking whether the platform store has a newer app version.
enum AppUpdateAvailability { updateAvailable, noUpdate }

/// Result of requesting the platform-owned update dialog.
enum UpdateDialogResult { shown, notShown }

/// Result of asking Android to open an APK installer.
enum ApkInstallResult { launched, fileNotFound, permissionRequired, failed }

/// Result of asking the platform to open an app store target.
enum StoreLaunchResult { launched, failed }
