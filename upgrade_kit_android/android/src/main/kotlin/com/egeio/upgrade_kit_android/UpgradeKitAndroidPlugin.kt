package com.egeio.upgrade_kit_android

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File

/** UpgradeKitAndroidPlugin */
class UpgradeKitAndroidPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware {
    private lateinit var channel: MethodChannel
    private lateinit var applicationContext: Context
    private var activity: Activity? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "upgrade_kit")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result
    ) {
        when (call.method) {
            "installApk" -> installApk(call, result)
            "openStore" -> openStore(call, result)
            "getAndroidStoreContext" -> getAndroidStoreContext(result)
            "openCurrentAppStore" -> openCurrentAppStore(call, result)
            "checkAppUpdate", "showUpdateDialog" -> unsupported(call.method, result)
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    private fun installApk(call: MethodCall, result: Result) {
        val filePath = call.argument<String>("filePath")?.trim().orEmpty()
        val apkFile = File(filePath)
        if (filePath.isEmpty() || !apkFile.isFile || apkFile.length() <= 0L) {
            result.success("fileNotFound")
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !applicationContext.packageManager.canRequestPackageInstalls()
        ) {
            val settingsIntent = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:${applicationContext.packageName}"),
            )
            val permissionSettingsFailed = try {
                launch(settingsIntent)
                false
            } catch (_: Exception) {
                true
            }
            result.success(if (permissionSettingsFailed) "failed" else "permissionRequired")
            return
        }

        try {
            val apkUri = FileProvider.getUriForFile(
                applicationContext,
                "${applicationContext.packageName}.upgrade_kit.provider",
                apkFile,
            )
            val installIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(apkUri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            launch(installIntent)
            result.success("launched")
        } catch (_: Exception) {
            result.success("failed")
        }
    }

    private fun openStore(call: MethodCall, result: Result) {
        val target = call.argument<String>("target")?.trim().orEmpty()
        val uri = target.takeIf { it.isNotEmpty() }?.let(Uri::parse)
        if (uri?.scheme.isNullOrEmpty()) {
            result.success("failed")
            return
        }

        try {
            launch(Intent(Intent.ACTION_VIEW, uri))
            result.success("launched")
        } catch (_: Exception) {
            result.success("failed")
        }
    }

    @Suppress("DEPRECATION")
    private fun getAndroidStoreContext(result: Result) {
        try {
            val packageName = applicationContext.packageName
            val packageInfo = applicationContext.packageManager.getPackageInfo(packageName, 0)
            val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                packageInfo.longVersionCode
            } else {
                packageInfo.versionCode.toLong()
            }
            val vendor = AndroidStoreResolver.detectVendor(Build.BRAND, Build.MANUFACTURER)
            result.success(
                mapOf(
                    "vendor" to vendor.wireName,
                    "packageName" to packageName,
                    "currentVersionName" to packageInfo.versionName.orEmpty(),
                    "currentVersionCode" to versionCode.toString(),
                ),
            )
        } catch (_: Exception) {
            result.error(
                "android-store-context-failed",
                "Unable to read the Android store context.",
                null,
            )
        }
    }

    private fun openCurrentAppStore(call: MethodCall, result: Result) {
        val fallbackTarget = call.argument<String>("fallbackTarget")?.trim()
        if (fallbackTarget != null && Uri.parse(fallbackTarget).scheme.isNullOrEmpty()) {
            result.success("failed")
            return
        }

        val vendor = AndroidStoreResolver.detectVendor(Build.BRAND, Build.MANUFACTURER)
        val targets = AndroidStoreResolver.resolveTargets(
            vendor = vendor,
            packageName = applicationContext.packageName,
            fallbackTarget = fallbackTarget,
        )
        for (target in targets) {
            val uri = Uri.parse(target.uri)
            if (uri.scheme.isNullOrEmpty()) {
                continue
            }
            val intent = Intent(Intent.ACTION_VIEW, uri).apply {
                target.packageName?.let(::setPackage)
            }
            try {
                launch(intent)
                result.success("launched")
                return
            } catch (_: Exception) {
                // Try the next vendor package or the caller-provided fallback.
            }
        }
        result.success("failed")
    }

    private fun launch(intent: Intent) {
        val currentActivity = activity
        if (currentActivity != null) {
            currentActivity.startActivity(intent)
            return
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        applicationContext.startActivity(intent)
    }

    private fun unsupported(method: String, result: Result) {
        result.error("unsupported", "$method is not supported on Android.", null)
    }
}
