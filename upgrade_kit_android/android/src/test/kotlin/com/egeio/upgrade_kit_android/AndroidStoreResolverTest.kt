package com.egeio.upgrade_kit_android

import kotlin.test.Test
import kotlin.test.assertEquals

internal class AndroidStoreResolverTest {
    @Test
    fun detectVendor_usesManufacturerAndBrandAliases() {
        assertEquals(AndroidStoreVendorId.HONOR, AndroidStoreResolver.detectVendor("HONOR", "HUAWEI"))
        assertEquals(AndroidStoreVendorId.HUAWEI, AndroidStoreResolver.detectVendor("HUAWEI", "HUAWEI"))
        assertEquals(AndroidStoreVendorId.XIAOMI, AndroidStoreResolver.detectVendor("Redmi", "Xiaomi"))
        assertEquals(AndroidStoreVendorId.VIVO, AndroidStoreResolver.detectVendor("iQOO", "vivo"))
        assertEquals(AndroidStoreVendorId.OPPO, AndroidStoreResolver.detectVendor("realme", "realme"))
        assertEquals(AndroidStoreVendorId.OPPO, AndroidStoreResolver.detectVendor("OnePlus", "OnePlus"))
        assertEquals(AndroidStoreVendorId.SAMSUNG, AndroidStoreResolver.detectVendor("samsung", "samsung"))
        assertEquals(AndroidStoreVendorId.UNKNOWN, AndroidStoreResolver.detectVendor("generic", "unknown"))
    }

    @Test
    fun resolveTargets_returnsVendorMarketBeforeFallback() {
        val targets = AndroidStoreResolver.resolveTargets(
            vendor = AndroidStoreVendorId.HONOR,
            packageName = "com.example.app",
            fallbackTarget = "https://example.com/app",
        )

        assertEquals(
            listOf(
                StoreTarget(
                    uri = "honormarket://details?id=com.example.app",
                    packageName = "com.hihonor.appmarket",
                ),
                StoreTarget(uri = "https://example.com/app", packageName = null),
            ),
            targets,
        )
    }

    @Test
    fun resolveTargets_oppoSupportsNewAndLegacyMarketPackages() {
        val targets = AndroidStoreResolver.resolveTargets(
            vendor = AndroidStoreVendorId.OPPO,
            packageName = "com.example.app",
            fallbackTarget = null,
        )

        assertEquals(
            listOf(
                StoreTarget(
                    uri = "market://details?id=com.example.app&atd=true",
                    packageName = "com.heytap.market",
                ),
                StoreTarget(
                    uri = "market://details?id=com.example.app&atd=true",
                    packageName = "com.oppo.market",
                ),
            ),
            targets,
        )
    }

    @Test
    fun resolveTargets_unknownVendorUsesOnlyFallback() {
        assertEquals(
            listOf(StoreTarget("https://example.com/app", null)),
            AndroidStoreResolver.resolveTargets(
                vendor = AndroidStoreVendorId.UNKNOWN,
                packageName = "com.example.app",
                fallbackTarget = "https://example.com/app",
            ),
        )
    }
}
