package com.egeio.upgrade_kit_android

internal enum class AndroidStoreVendorId(val wireName: String) {
    HUAWEI("huawei"),
    HONOR("honor"),
    XIAOMI("xiaomi"),
    VIVO("vivo"),
    OPPO("oppo"),
    SAMSUNG("samsung"),
    UNKNOWN("unknown"),
}

internal data class StoreTarget(
    val uri: String,
    val packageName: String?,
)

internal object AndroidStoreResolver {
    fun detectVendor(brand: String?, manufacturer: String?): AndroidStoreVendorId {
        val device = "${brand.orEmpty()} ${manufacturer.orEmpty()}".lowercase()
        return when {
            device.contains("honor") -> AndroidStoreVendorId.HONOR
            device.contains("huawei") -> AndroidStoreVendorId.HUAWEI
            device.contains("xiaomi") || device.contains("redmi") -> AndroidStoreVendorId.XIAOMI
            device.contains("vivo") || device.contains("iqoo") -> AndroidStoreVendorId.VIVO
            device.contains("oppo") ||
                device.contains("realme") ||
                device.contains("oneplus") -> AndroidStoreVendorId.OPPO
            device.contains("samsung") -> AndroidStoreVendorId.SAMSUNG
            else -> AndroidStoreVendorId.UNKNOWN
        }
    }

    fun resolveTargets(
        vendor: AndroidStoreVendorId,
        packageName: String,
        fallbackTarget: String?,
    ): List<StoreTarget> {
        val vendorTargets = when (vendor) {
            AndroidStoreVendorId.HUAWEI -> listOf(
                StoreTarget("appmarket://details?id=$packageName", "com.huawei.appmarket"),
            )
            AndroidStoreVendorId.HONOR -> listOf(
                StoreTarget("honormarket://details?id=$packageName", "com.hihonor.appmarket"),
            )
            AndroidStoreVendorId.XIAOMI -> listOf(
                StoreTarget("market://details?id=$packageName", "com.xiaomi.market"),
            )
            AndroidStoreVendorId.VIVO -> listOf(
                StoreTarget(
                    "vivomarket://details?id=$packageName&th_name=self_update",
                    "com.vivo.appstore",
                ),
            )
            AndroidStoreVendorId.OPPO -> listOf(
                StoreTarget(
                    "market://details?id=$packageName&atd=true",
                    "com.heytap.market",
                ),
                StoreTarget(
                    "market://details?id=$packageName&atd=true",
                    "com.oppo.market",
                ),
            )
            AndroidStoreVendorId.SAMSUNG -> listOf(
                StoreTarget(
                    "samsungapps://ProductDetail/$packageName",
                    "com.sec.android.app.samsungapps",
                ),
            )
            AndroidStoreVendorId.UNKNOWN -> emptyList()
        }
        val fallback = fallbackTarget?.let { StoreTarget(it, null) }
        return if (fallback == null) vendorTargets else vendorTargets + fallback
    }
}
