import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:http/http.dart' as http;
import 'package:upgrade_kit_platform_interface/upgrade_kit_platform_interface.dart';

import 'android_vendor_upgrade.dart';
import 'android_version_comparator.dart';

export 'android_version_comparator.dart';

final class AndroidVendorUpgradeService {
  AndroidVendorUpgradeService({
    required UpgradeKitPlatform platform,
    http.Client? client,
    DateTime Function()? now,
    String Function()? nonce,
  }) : _platform = platform,
       _client = client ?? http.Client(),
       _ownsClient = client == null,
       _now = now ?? DateTime.now,
       _nonce = nonce ?? (() => Random.secure().nextInt(1 << 31).toString());

  final UpgradeKitPlatform _platform;
  final http.Client _client;
  final bool _ownsClient;
  final DateTime Function() _now;
  final String Function() _nonce;

  Future<AndroidVendorUpgradeCheckResult> check(
    AndroidVendorUpgradeConfiguration configuration, {
    String locale = 'zh-CN',
  }) async {
    final context = await _platform.getAndroidStoreContext();
    if (context.vendor == AndroidStoreVendor.samsung ||
        context.vendor == AndroidStoreVendor.unknown) {
      return AndroidVendorUpgradeCheckResult(
        status: AndroidVendorUpgradeCheckStatus.unsupportedVendor,
        context: context,
      );
    }
    final vendorConfiguration = configuration.forVendor(context.vendor);
    if (vendorConfiguration == null) {
      return AndroidVendorUpgradeCheckResult(
        status: AndroidVendorUpgradeCheckStatus.notConfigured,
        context: context,
      );
    }

    try {
      final release = await _query(
        context,
        vendorConfiguration,
        configuration.requestTimeout,
        locale.trim().isEmpty ? 'zh-CN' : locale.trim(),
      );
      final comparison = _compare(release, context);
      if (comparison == null) {
        return AndroidVendorUpgradeCheckResult(
          status: AndroidVendorUpgradeCheckStatus.failed,
          context: context,
          release: release,
          errorCode: 'invalid-version',
          errorMessage:
              'The vendor response did not contain a comparable version.',
        );
      }
      return AndroidVendorUpgradeCheckResult(
        status: comparison > 0
            ? AndroidVendorUpgradeCheckStatus.updateAvailable
            : AndroidVendorUpgradeCheckStatus.noUpdate,
        context: context,
        release: release,
      );
    } on TimeoutException {
      return _failed(
        context,
        'timeout',
        'The vendor update request timed out.',
      );
    } on _VendorQueryException catch (error) {
      return _failed(context, error.code, error.message);
    } on Object {
      return _failed(
        context,
        'network-error',
        'The vendor update request failed.',
      );
    }
  }

  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }

  Future<AndroidVendorReleaseInfo> _query(
    AndroidStoreContext context,
    Object configuration,
    Duration timeout,
    String locale,
  ) => switch ((context.vendor, configuration)) {
    (AndroidStoreVendor.huawei, HuaweiVendorUpgradeConfiguration config) =>
      _queryHuawei(context, config, timeout, locale),
    (AndroidStoreVendor.honor, HonorVendorUpgradeConfiguration config) =>
      _queryHonor(context, config, timeout, locale),
    (AndroidStoreVendor.xiaomi, XiaomiVendorUpgradeConfiguration config) =>
      _queryXiaomi(context, config, timeout),
    (AndroidStoreVendor.vivo, VivoVendorUpgradeConfiguration config) =>
      _queryVivo(context, config, timeout),
    (AndroidStoreVendor.oppo, OppoVendorUpgradeConfiguration config) =>
      _queryOppo(context, config, timeout),
    _ => throw const _VendorQueryException(
      'invalid-config',
      'The configuration does not match the detected Android vendor.',
    ),
  };

  Future<AndroidVendorReleaseInfo> _queryHuawei(
    AndroidStoreContext context,
    HuaweiVendorUpgradeConfiguration configuration,
    Duration timeout,
    String locale,
  ) async {
    final tokenResponse = await _sendJson(
      method: 'POST',
      uri: Uri.https('connect-api.cloud.huawei.com', '/api/oauth2/v1/token'),
      body: <String, Object?>{
        'grant_type': 'client_credentials',
        'client_id': configuration.clientId,
        'client_secret': configuration.clientSecret,
      },
      timeout: timeout,
    );
    final token = _nonEmptyString(tokenResponse['access_token']);
    if (token == null) {
      throw const _VendorQueryException(
        'authentication-failed',
        'Huawei did not return an access token.',
      );
    }
    final response = await _sendRequest(
      http.Request(
          'GET',
          Uri.https(
            'connect-api.cloud.huawei.com',
            '/api/publish/v2/app-info',
            <String, String>{'appId': configuration.appId},
          ),
        )
        ..headers.addAll(<String, String>{
          'Authorization': 'Bearer $token',
          'client_id': configuration.clientId,
        }),
      timeout,
    );
    final root = _decodeMap(response.body);
    final appInfo = _map(root['appInfo']);
    final versionName = _nonEmptyString(appInfo?['versionNumber']);
    if (versionName == null) {
      throw const _VendorQueryException(
        'invalid-response',
        'Huawei did not return a published version.',
      );
    }
    return AndroidVendorReleaseInfo(
      vendor: AndroidStoreVendor.huawei,
      versionName: versionName,
      versionCode: _nonEmptyString(appInfo?['versionCode']),
      releaseNotes: _localizedText(
        root['languages'],
        locale: locale,
        localeKey: 'lang',
        valueKey: 'newFeatures',
      ),
      fileSizeBytes: _int(appInfo?['fileSizeBytes']),
      storeTarget: 'appmarket://details?id=${context.packageName}',
    );
  }

  Future<AndroidVendorReleaseInfo> _queryHonor(
    AndroidStoreContext context,
    HonorVendorUpgradeConfiguration configuration,
    Duration timeout,
    String locale,
  ) async {
    final tokenResponse = await _sendForm(
      method: 'POST',
      uri: Uri.https('iam.developer.honor.com', '/auth/token'),
      fields: <String, String>{
        'grant_type': 'client_credentials',
        'client_id': configuration.clientId,
        'client_secret': configuration.clientSecret,
      },
      timeout: timeout,
    );
    final token = _nonEmptyString(tokenResponse['access_token']);
    if (token == null) {
      throw const _VendorQueryException(
        'authentication-failed',
        'Honor did not return an access token.',
      );
    }
    final response = await _sendRequest(
      http.Request(
        'GET',
        Uri.https(
          'appmarket-openapi-drcn.cloud.honor.com',
          '/openapi/v1/publish/get-app-detail',
          <String, String>{'appId': configuration.appId},
        ),
      )..headers['Authorization'] = 'Bearer $token',
      timeout,
    );
    final root = _decodeMap(response.body);
    if (_int(root['code']) case final int code when code != 0) {
      throw const _VendorQueryException(
        'vendor-error',
        'Honor rejected the application detail request.',
      );
    }
    final data = _map(root['data']) ?? root;
    final release =
        _map(data['releaseInfo']) ?? _map(data['currentRelease']) ?? data;
    final versionName = _nonEmptyString(release['versionName']);
    if (versionName == null) {
      throw const _VendorQueryException(
        'invalid-response',
        'Honor did not return a published version.',
      );
    }
    return AndroidVendorReleaseInfo(
      vendor: AndroidStoreVendor.honor,
      versionName: versionName,
      versionCode: _nonEmptyString(release['versionCode']),
      releaseNotes: _localizedText(
        data['languageInfo'],
        locale: locale,
        localeKey: 'languageId',
        valueKey: 'newFeatures',
      ),
      fileSizeBytes: null,
      storeTarget: 'honormarket://details?id=${context.packageName}',
    );
  }

  Future<AndroidVendorReleaseInfo> _queryXiaomi(
    AndroidStoreContext context,
    XiaomiVendorUpgradeConfiguration configuration,
    Duration timeout,
  ) async {
    final requestData = jsonEncode(<String, Object?>{
      'packageName': context.packageName,
      'userName': configuration.userName,
    });
    final signaturePayload = jsonEncode(<String, Object?>{
      'sig': <Map<String, String>>[
        <String, String>{
          'name': 'RequestData',
          'hash': md5.convert(utf8.encode(requestData)).toString(),
        },
      ],
      'password': configuration.passwordOrPrivateKey,
    });
    final signature = _encryptXiaomiSignature(
      signaturePayload,
      configuration.rsaPublicKeyPem,
    );
    final request =
        http.MultipartRequest(
            'POST',
            Uri.https('api.developer.xiaomi.com', '/devupload/dev/query'),
          )
          ..fields.addAll(<String, String>{
            'RequestData': requestData,
            'SIG': signature,
          });
    final response = await _sendRequest(request, timeout);
    final root = _decodeMap(response.body);
    if (_int(root['result']) != 0) {
      throw const _VendorQueryException(
        'vendor-error',
        'Xiaomi rejected the application query.',
      );
    }
    final packageInfo = _map(root['packageInfo']);
    final versionName = _nonEmptyString(packageInfo?['versionName']);
    if (versionName == null) {
      throw const _VendorQueryException(
        'invalid-response',
        'Xiaomi did not return a published version.',
      );
    }
    return AndroidVendorReleaseInfo(
      vendor: AndroidStoreVendor.xiaomi,
      versionName: versionName,
      versionCode: _nonEmptyString(packageInfo?['versionCode']),
      releaseNotes: '',
      fileSizeBytes: null,
      storeTarget: 'market://details?id=${context.packageName}',
    );
  }

  Future<AndroidVendorReleaseInfo> _queryVivo(
    AndroidStoreContext context,
    VivoVendorUpgradeConfiguration configuration,
    Duration timeout,
  ) async {
    final timestamp = _now().millisecondsSinceEpoch;
    final business = <String, Object?>{'packageName': context.packageName};
    final unsigned = <String, Object?>{
      'account': configuration.account,
      'timestamp': timestamp,
      'bizParam': business,
    };
    final canonical = unsigned.keys.toList()..sort();
    final signatureSource = canonical
        .map((key) {
          final value = key == 'bizParam'
              ? jsonEncode(unsigned[key])
              : unsigned[key].toString();
          return '$key=$value';
        })
        .join('&');
    final signature = Hmac(
      sha256,
      utf8.encode(configuration.secret),
    ).convert(utf8.encode(signatureSource)).toString();
    final root = await _sendJson(
      method: 'POST',
      uri: Uri.https(
        'developer-api.vivo.com.cn',
        '/gateway/developer/app/publish/v1/get-online-version',
      ),
      body: <String, Object?>{...unsigned, 'sign': signature},
      timeout: timeout,
    );
    if (_int(root['code']) case final int code when code != 0) {
      throw const _VendorQueryException(
        'vendor-error',
        'vivo rejected the online version request.',
      );
    }
    final data = _map(root['data']);
    final versionName = _nonEmptyString(data?['versionName']);
    if (versionName == null) {
      throw const _VendorQueryException(
        'invalid-response',
        'vivo did not return a published version.',
      );
    }
    return AndroidVendorReleaseInfo(
      vendor: AndroidStoreVendor.vivo,
      versionName: versionName,
      versionCode: _nonEmptyString(data?['versionCode']),
      releaseNotes: '',
      fileSizeBytes: null,
      storeTarget:
          'vivomarket://details?id=${context.packageName}&th_name=self_update',
    );
  }

  Future<AndroidVendorReleaseInfo> _queryOppo(
    AndroidStoreContext context,
    OppoVendorUpgradeConfiguration configuration,
    Duration timeout,
  ) async {
    final tokenResponse = await _sendRequest(
      http.Request(
        'GET',
        Uri.https(
          'openapi.heytapmobi.com',
          '/oauth2/v1/token',
          <String, String>{
            'client_id': configuration.clientId,
            'client_secret': configuration.clientSecret,
            'grant_type': 'client_credentials',
          },
        ),
      ),
      timeout,
    );
    final tokenRoot = _decodeMap(tokenResponse.body);
    final token = _nonEmptyString(_map(tokenRoot['data'])?['access_token']);
    if (token == null) {
      throw const _VendorQueryException(
        'authentication-failed',
        'OPPO did not return an access token.',
      );
    }
    final timestamp = _now().millisecondsSinceEpoch.toString();
    final nonce = _nonce();
    final signatureSource =
        'access_token=$token&timestamp=$timestamp&nonce=$nonce&pkg=${context.packageName}';
    final signature = Hmac(
      sha256,
      utf8.encode(configuration.clientSecret),
    ).convert(utf8.encode(signatureSource)).toString();
    final response = await _sendRequest(
      http.Request(
          'GET',
          Uri.https(
            'openapi.heytapmobi.com',
            '/selfupdate/query/version',
            <String, String>{'pkg': context.packageName},
          ),
        )
        ..headers.addAll(<String, String>{
          'Authorization': token,
          'X-Client-Send-Utc-Ms': timestamp,
          'X-Nonce': nonce,
          'X-Api-Sign': signature,
        }),
      timeout,
    );
    final root = _decodeMap(response.body);
    final release = _map(root['result']);
    final versionCode = _nonEmptyString(release?['fullVersionCode']);
    if (versionCode == null) {
      throw const _VendorQueryException(
        'invalid-response',
        'OPPO did not return a published version code.',
      );
    }
    return AndroidVendorReleaseInfo(
      vendor: AndroidStoreVendor.oppo,
      versionName: _nonEmptyString(release?['versionName']) ?? '',
      versionCode: versionCode,
      releaseNotes: '',
      fileSizeBytes: null,
      storeTarget: 'market://details?id=${context.packageName}&atd=true',
    );
  }

  Future<Map<String, Object?>> _sendJson({
    required String method,
    required Uri uri,
    required Map<String, Object?> body,
    required Duration timeout,
  }) async {
    final request = http.Request(method, uri)
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode(body);
    final response = await _sendRequest(request, timeout);
    return _decodeMap(response.body);
  }

  Future<Map<String, Object?>> _sendForm({
    required String method,
    required Uri uri,
    required Map<String, String> fields,
    required Duration timeout,
  }) async {
    final request = http.Request(method, uri)..bodyFields = fields;
    final response = await _sendRequest(request, timeout);
    return _decodeMap(response.body);
  }

  Future<http.Response> _sendRequest(
    http.BaseRequest request,
    Duration timeout,
  ) async {
    final streamed = await _client.send(request).timeout(timeout);
    final response = await http.Response.fromStream(streamed).timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _VendorQueryException(
        'http-error',
        'The vendor endpoint returned HTTP ${response.statusCode}.',
      );
    }
    return response;
  }

  int? _compare(AndroidVendorReleaseInfo release, AndroidStoreContext context) {
    final codeComparison = AndroidVersionComparator.compareCodes(
      release.versionCode,
      context.currentVersionCode,
    );
    if (codeComparison != null) {
      return codeComparison;
    }
    return AndroidVersionComparator.compareNames(
      release.versionName,
      context.currentVersionName,
    );
  }

  AndroidVendorUpgradeCheckResult _failed(
    AndroidStoreContext context,
    String code,
    String message,
  ) => AndroidVendorUpgradeCheckResult(
    status: AndroidVendorUpgradeCheckStatus.failed,
    context: context,
    errorCode: code,
    errorMessage: message,
  );
}

final class _VendorQueryException implements Exception {
  const _VendorQueryException(this.code, this.message);

  final String code;
  final String message;
}

Map<String, Object?> _decodeMap(String source) {
  try {
    final decoded = jsonDecode(source);
    final result = _map(decoded);
    if (result != null) {
      return result;
    }
  } on FormatException {
    // Mapped to a stable, non-sensitive error below.
  }
  throw const _VendorQueryException(
    'invalid-response',
    'The vendor endpoint returned invalid JSON.',
  );
}

Map<String, Object?>? _map(Object? value) {
  if (value is! Map) {
    return null;
  }
  return value.map<String, Object?>(
    (key, item) => MapEntry(key.toString(), item),
  );
}

int? _int(Object? value) => switch (value) {
  int number => number,
  num number => number.toInt(),
  String text => int.tryParse(text.trim()),
  _ => null,
};

String? _nonEmptyString(Object? value) {
  if (value == null) {
    return null;
  }
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

String _localizedText(
  Object? value, {
  required String locale,
  required String localeKey,
  required String valueKey,
}) {
  if (value is! List) {
    return '';
  }
  final entries = value.map(_map).whereType<Map<String, Object?>>().toList();
  Map<String, Object?>? selected;
  for (final entry in entries) {
    if (_nonEmptyString(entry[localeKey])?.toLowerCase() ==
        locale.toLowerCase()) {
      selected = entry;
      break;
    }
  }
  if (selected == null) {
    for (final entry in entries) {
      if (_nonEmptyString(entry[localeKey])?.toLowerCase() == 'zh-cn') {
        selected = entry;
        break;
      }
    }
  }
  selected ??= entries.isEmpty ? null : entries.first;
  return _nonEmptyString(selected?[valueKey]) ?? '';
}

String _encryptXiaomiSignature(String source, String publicKeyPem) {
  try {
    final key = encrypt.RSAKeyParser().parse(publicKeyPem);
    final dynamic dynamicKey = key;
    final modulus = dynamicKey.modulus as BigInt?;
    if (modulus == null) {
      throw const FormatException();
    }
    final encryptedBlockSize = (modulus.bitLength + 7) ~/ 8;
    final plainBlockSize = encryptedBlockSize - 11;
    if (plainBlockSize <= 0) {
      throw const FormatException();
    }
    final encrypter = encrypt.Encrypter(
      encrypt.RSA(
        publicKey: key as dynamic,
        encoding: encrypt.RSAEncoding.PKCS1,
      ),
    );
    final input = utf8.encode(source);
    final output = BytesBuilder(copy: false);
    for (var offset = 0; offset < input.length; offset += plainBlockSize) {
      final end = min(offset + plainBlockSize, input.length);
      output.add(encrypter.encryptBytes(input.sublist(offset, end)).bytes);
    }
    return output
        .takeBytes()
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  } on Object {
    throw const _VendorQueryException(
      'invalid-config',
      'The Xiaomi RSA public key is invalid.',
    );
  }
}
