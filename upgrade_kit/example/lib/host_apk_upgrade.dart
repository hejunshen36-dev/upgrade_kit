import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:upgrade_kit/upgrade_kit.dart';

/// Example HOST code: replace this manifest schema and auth with your backend.
final class HostApkRelease {
  const HostApkRelease({
    required this.versionName,
    required this.downloadUrl,
    required this.sha256Hex,
    required this.releaseNotes,
  });
  final String versionName;
  final Uri downloadUrl;
  final String sha256Hex;
  final String releaseNotes;
}

final class HostApkUpgrade {
  final _service = const UpgradeKit();

  /// The host owns BOTH networking and comparison, without UpgradeSource.
  Future<HostApkRelease?> check(
    Uri manifestUrl, {
    required BigInt currentBuild,
  }) async {
    final response = await http
        .get(manifestUrl)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw StateError('Version service request failed.');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final remoteBuild = BigInt.tryParse(data['versionCode'].toString());
    if (remoteBuild == null || remoteBuild < BigInt.zero) {
      throw const FormatException('Invalid versionCode.');
    }
    if (remoteBuild <= currentBuild) return null;
    final hash = data['sha256'];
    if (hash is! String || !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(hash)) {
      throw const FormatException('The manifest must supply SHA-256.');
    }
    return HostApkRelease(
      versionName: data['versionName'] as String,
      downloadUrl: Uri.parse(data['downloadUrl'] as String),
      sha256Hex: hash.toLowerCase(),
      releaseNotes: data['releaseNotes'] is String
          ? data['releaseNotes'] as String
          : '',
    );
  }

  ApkDownloadTask createDownload(HostApkRelease release, String filePath) =>
      _service.createApkDownload(
        ApkDownloadRequest(url: release.downloadUrl, filePath: filePath),
      );

  /// Only host verification can lead to this explicit install call.
  Future<ApkInstallResult> verifyAndInstall(
    ApkDownloadResult result,
    HostApkRelease release,
  ) async {
    if (result.status != ApkDownloadState.completed ||
        result.filePath == null) {
      throw StateError('A completed download is required.');
    }
    final digest = await sha256.bind(File(result.filePath!).openRead()).first;
    if (digest.toString() != release.sha256Hex) {
      throw StateError('APK checksum does not match; installation blocked.');
    }
    return _service.installApk(result.filePath!);
  }
}
