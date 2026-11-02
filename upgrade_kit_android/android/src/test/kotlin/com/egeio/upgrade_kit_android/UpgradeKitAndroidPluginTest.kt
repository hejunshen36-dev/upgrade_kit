package com.egeio.upgrade_kit_android

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.mockito.Mockito
import kotlin.test.Test

internal class UpgradeKitAndroidPluginTest {
    @Test
    fun checkAppUpdate_reportsUnsupported() {
        val plugin = UpgradeKitAndroidPlugin()
        val result: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)

        plugin.onMethodCall(MethodCall("checkAppUpdate", null), result)

        Mockito.verify(result).error(
            "unsupported",
            "checkAppUpdate is not supported on Android.",
            null,
        )
    }

    @Test
    fun unknownMethod_reportsNotImplemented() {
        val plugin = UpgradeKitAndroidPlugin()
        val result: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)

        plugin.onMethodCall(MethodCall("unknown", null), result)

        Mockito.verify(result).notImplemented()
    }
}
