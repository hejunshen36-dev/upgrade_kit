import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:upgrade_kit/upgrade_kit.dart';
import 'package:upgrade_kit/src/store/android_vendor/android_vendor_upgrade_service.dart';
import 'package:upgrade_kit_platform_interface/upgrade_kit_platform_interface.dart';

const _testPublicKey = '''-----BEGIN PUBLIC KEY-----
MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCzoN1rGpG4oIam1m2fup1ruY5e
nRGxF9KJtnhc2XZZoTn2mRz+oqFJEvgN0DsfNrjpAJRModM9qHFx4u2wEZgSjHvI
2IgVp0t5R2Ji/v3bwwcYKy9MUhL6Qp24EYyi6awh8uK8BovNCM7IzWFOgBxTtOJ8
oBUkko01QfIIG+uoAQIDAQAB
-----END PUBLIC KEY-----''';

final class _FakePlatform extends UpgradeKitPlatform
    with MockPlatformInterfaceMixin {
  _FakePlatform(this.context);

  final AndroidStoreContext context;

  @override
  Future<AndroidStoreContext> getAndroidStoreContext() async => context;
}

AndroidStoreContext _context(
  AndroidStoreVendor vendor, {
  String versionName = '1.0.0',
  String versionCode = '100',
}) => AndroidStoreContext(
  vendor: vendor,
  packageName: 'com.example.app',
  currentVersionName: versionName,
  currentVersionCode: versionCode,
);

AndroidVendorUpgradeService _service(
  AndroidStoreVendor vendor,
  MockClient client,
) => AndroidVendorUpgradeService(
  platform: _FakePlatform(_context(vendor)),
  client: client,
  now: () => DateTime.fromMillisecondsSinceEpoch(1700000000000),
  nonce: () => '12345',
);

void main() {
  test(
    'version comparison uses numeric codes and numeric version segments',
    () {
      expect(AndroidVersionComparator.compareCodes('10', '9'), 1);
      expect(AndroidVersionComparator.compareNames('1.10.0', '1.9.9'), 1);
      expect(AndroidVersionComparator.compareNames('1.0', '1.0.0'), 0);
      expect(AndroidVersionComparator.compareNames('release', '1.0'), isNull);
    },
  );

  test(
    'Huawei obtains a token and maps localized release information',
    () async {
      final client = MockClient((request) async {
        if (request.url.path.contains('oauth2')) {
          return http.Response(jsonEncode({'access_token': 'token'}), 200);
        }
        expect(request.headers['authorization'], 'Bearer token');
        return http.Response(
          jsonEncode({
            'appInfo': {
              'versionNumber': '1.2.0',
              'versionCode': 120,
              'fileSizeBytes': 1024,
            },
            'languages': [
              {'lang': 'zh-CN', 'newFeatures': '更新说明'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final result = await _service(AndroidStoreVendor.huawei, client).check(
        AndroidVendorUpgradeConfiguration(
          huawei: HuaweiVendorUpgradeConfiguration(
            clientId: 'client',
            clientSecret: 'secret',
            appId: 'app-id',
          ),
        ),
        locale: 'zh-CN',
      );

      expect(result.status, AndroidVendorUpgradeCheckStatus.updateAvailable);
      expect(result.release?.versionName, '1.2.0');
      expect(result.release?.versionCode, '120');
      expect(result.release?.releaseNotes, '更新说明');
      expect(result.release?.fileSizeBytes, 1024);
    },
  );

  test('Honor accepts wrapped detail responses', () async {
    final client = MockClient((request) async {
      if (request.url.host.contains('iam.developer.honor.com')) {
        return http.Response(jsonEncode({'access_token': 'token'}), 200);
      }
      return http.Response(
        jsonEncode({
          'code': 0,
          'data': {
            'releaseInfo': {'versionName': '1.0.0', 'versionCode': 100},
            'languageInfo': [
              {'languageId': 'zh-CN', 'newFeatures': '说明'},
            ],
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final result = await _service(AndroidStoreVendor.honor, client).check(
      AndroidVendorUpgradeConfiguration(
        honor: HonorVendorUpgradeConfiguration(
          clientId: 'client',
          clientSecret: 'secret',
          appId: 'app-id',
        ),
      ),
    );

    expect(result.status, AndroidVendorUpgradeCheckStatus.noUpdate);
    expect(
      result.release?.storeTarget,
      'honormarket://details?id=com.example.app',
    );
  });

  test('Xiaomi sends RequestData and an RSA encrypted SIG', () async {
    final client = MockClient.streaming((request, bodyStream) async {
      expect(request, isA<http.MultipartRequest>());
      final multipart = request as http.MultipartRequest;
      expect(multipart.fields['RequestData'], contains('com.example.app'));
      expect(multipart.fields['SIG'], isNotEmpty);
      await bodyStream.drain<void>();
      return http.StreamedResponse(
        Stream<List<int>>.value(
          utf8.encode(
            jsonEncode({
              'result': 0,
              'packageInfo': {
                'versionName': '2.0.0',
                'versionCode': 200,
                'packageName': 'com.example.app',
              },
            }),
          ),
        ),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final result = await _service(AndroidStoreVendor.xiaomi, client).check(
      AndroidVendorUpgradeConfiguration(
        xiaomi: XiaomiVendorUpgradeConfiguration(
          userName: 'user@example.com',
          passwordOrPrivateKey: 'credential',
          rsaPublicKeyPem: _testPublicKey,
        ),
      ),
    );

    expect(result.status, AndroidVendorUpgradeCheckStatus.updateAvailable);
    expect(result.release?.versionCode, '200');
  });

  test('vivo signs the sorted request body and maps its version', () async {
    final client = MockClient((request) async {
      final body = jsonDecode(request.body);
      expect(body['account'], 'account');
      expect(body['timestamp'], 1700000000000);
      expect(body['sign'], isNotEmpty);
      return http.Response(
        jsonEncode({
          'code': 0,
          'data': {
            'versionName': '1.1.0',
            'versionCode': '110',
            'packageName': 'com.example.app',
          },
        }),
        200,
      );
    });
    final result = await _service(AndroidStoreVendor.vivo, client).check(
      AndroidVendorUpgradeConfiguration(
        vivo: VivoVendorUpgradeConfiguration(
          account: 'account',
          secret: 'secret',
        ),
      ),
    );

    expect(result.status, AndroidVendorUpgradeCheckStatus.updateAvailable);
    expect(result.release?.storeTarget, contains('vivomarket://'));
  });

  test(
    'OPPO obtains a token, signs the query, and compares fullVersionCode',
    () async {
      final client = MockClient((request) async {
        if (request.url.path.contains('oauth2')) {
          return http.Response(
            jsonEncode({
              'data': {'access_token': 'token'},
            }),
            200,
          );
        }
        expect(request.headers['authorization'], 'token');
        expect(request.headers['x-api-sign'], isNotEmpty);
        return http.Response(
          jsonEncode({
            'result': {'pkg': 'com.example.app', 'fullVersionCode': '101'},
          }),
          200,
        );
      });
      final result = await _service(AndroidStoreVendor.oppo, client).check(
        AndroidVendorUpgradeConfiguration(
          oppo: OppoVendorUpgradeConfiguration(
            clientId: 'client',
            clientSecret: 'secret',
          ),
        ),
      );

      expect(result.status, AndroidVendorUpgradeCheckStatus.updateAvailable);
      expect(result.release?.versionCode, '101');
    },
  );

  test(
    'queries only the detected vendor and reports missing configuration',
    () async {
      var requests = 0;
      final client = MockClient((_) async {
        requests += 1;
        return http.Response('{}', 200);
      });
      final result = await _service(AndroidStoreVendor.huawei, client).check(
        AndroidVendorUpgradeConfiguration(
          vivo: VivoVendorUpgradeConfiguration(
            account: 'account',
            secret: 'secret',
          ),
        ),
      );

      expect(result.status, AndroidVendorUpgradeCheckStatus.notConfigured);
      expect(requests, 0);
    },
  );

  test(
    'Samsung is explicit unsupported and network errors are observable',
    () async {
      final unsupported = await _service(
        AndroidStoreVendor.samsung,
        MockClient((_) async => http.Response('{}', 200)),
      ).check(AndroidVendorUpgradeConfiguration());
      expect(
        unsupported.status,
        AndroidVendorUpgradeCheckStatus.unsupportedVendor,
      );

      final failed =
          await _service(
            AndroidStoreVendor.huawei,
            MockClient((_) async => throw Exception('offline')),
          ).check(
            AndroidVendorUpgradeConfiguration(
              huawei: HuaweiVendorUpgradeConfiguration(
                clientId: 'client',
                clientSecret: 'secret',
                appId: 'app-id',
              ),
            ),
          );
      expect(failed.status, AndroidVendorUpgradeCheckStatus.failed);
      expect(failed.errorCode, 'network-error');
      expect(failed.errorMessage, isNot(contains('secret')));
    },
  );
}
