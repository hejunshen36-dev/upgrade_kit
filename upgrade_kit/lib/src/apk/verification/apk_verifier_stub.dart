Future<bool> isApkFileReady(
  String filePath, {
  String? expectedMd5,
  bool deleteInvalid = true,
}) => Future.error(UnsupportedError('APK files require an IO platform.'));
