package com.egeio.upgrade_kit_android

import androidx.core.content.FileProvider

// A distinct manifest key prevents host FileProvider overrides from replacing
// the upgrade authority and its private file roots during manifest merging.
class UpgradeFileProvider : FileProvider()
