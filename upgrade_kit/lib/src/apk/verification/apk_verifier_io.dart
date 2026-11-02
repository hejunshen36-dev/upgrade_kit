import 'dart:io';
import 'package:crypto/crypto.dart';

/// Checks an app-owned APK; [deleteInvalid] controls invalid-file cleanup.
/// Null, empty and whitespace-only checksums skip hashing.
Future<bool> isApkFileReady(
  String filePath, {
  String? expectedMd5,
  bool deleteInvalid = true,
}) async {
  final file = File(filePath);
  if (await FileSystemEntity.type(filePath, followLinks: false) !=
      FileSystemEntityType.file) {
    return false;
  }
  final expected = expectedMd5?.trim().toLowerCase();
  final valid =
      await file.length() > 0 &&
      (expected == null ||
          expected.isEmpty ||
          (await md5.bind(file.openRead()).first).toString() == expected);
  if (!valid && deleteInvalid) await file.delete();
  return valid;
}
