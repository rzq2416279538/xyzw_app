import 'dart:convert';
import 'dart:math';

import 'package:uuid/uuid.dart';

import 'codebook_crypto.dart';
import 'http_client.dart';
import 'xy_endpoints.dart';

class ImportException implements Exception {
  ImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

class QrTicket {
  QrTicket(this.uuid, this.imageBytes);
  final String uuid;
  final List<int> imageBytes;
}

class QrPollResult {
  QrPollResult(this.state, [this.code]);
  final WxScanState state;
  final String? code;
}

class LoginResult {
  LoginResult(this.combUser, this.timestamp, this.sign, this.rawJson);
  final String combUser;
  final int timestamp;
  final String sign;
  final String rawJson;
}

/// 对照 naiwa-release `importer/WxLogin.kt`
abstract final class WxLogin {
  static String _take(String s, int n) =>
      s.length <= n ? s : s.substring(0, n);

  static Future<QrTicket> createQrCode() async {
    DeviceInfo.newSession();
    final html = (await ImportHttp.get(
      XyEndpoints.qrConnect(),
      headers: {
        'Host': 'open.weixin.qq.com',
        'Connection': 'keep-alive',
        'Upgrade-Insecure-Requests': '1',
        'User-Agent': XyEndpoints.uaWxAndroid,
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7',
        'X-Requested-With': 'com.muhua.w0',
      },
    )).text();

    final uuid = RegExp(r'qrcode/([A-Za-z0-9_\-]+)').firstMatch(html)?.group(1) ??
        RegExp(r'uuid=([A-Za-z0-9_\-]+)').firstMatch(html)?.group(1) ??
        RegExp(r'"uuid"\s*:\s*"([^"]+)"').firstMatch(html)?.group(1);
    if (uuid == null || uuid.isEmpty) {
      throw ImportException(
        '未能解析二维码 uuid。响应片段: ${_take(html.replaceAll(RegExp(r'\s+'), ' '), 150)}',
      );
    }

    final img = await ImportHttp.get(
      XyEndpoints.qrImage(uuid),
      headers: {
        'Host': 'open.weixin.qq.com',
        'User-Agent': XyEndpoints.uaWxAndroid,
      },
    );
    if (img.status != 200 || img.body.isEmpty) {
      throw ImportException('二维码图片下载失败 (HTTP ${img.status})');
    }
    return QrTicket(uuid, img.body);
  }

  static Future<QrPollResult> pollQrCode(String uuid) async {
    final body = (await ImportHttp.get(
      XyEndpoints.qrPoll(uuid),
      headers: {
        'Host': 'long.open.weixin.qq.com',
        'User-Agent': XyEndpoints.uaWxAndroid,
      },
    )).text();

    final errCode = int.tryParse(
          RegExp(r'wx_errcode\s*=\s*(\d+)').firstMatch(body)?.group(1) ?? '',
        ) ??
        -1;
    final state = WxScanState.of(errCode);
    if (state != WxScanState.confirmed) return QrPollResult(state);

    final redirect = RegExp("wx_redirecturl\\s*=\\s*['\"]([^'\"]*)['\"]")
        .firstMatch(body)
        ?.group(1);
    if (redirect == null || redirect.isEmpty) {
      throw ImportException('授权成功但跳转地址为空。响应: ${_take(body, 200)}');
    }
    final code = RegExp(r'[?&]code=([^&]+)').firstMatch(redirect)?.group(1);
    if (code == null || code.isEmpty) {
      throw ImportException('跳转地址中没有 code: $redirect');
    }
    return QrPollResult(state, code);
  }

  static Future<void> sendSmsCode(String mobile) async {
    if (!RegExp(r'^1[3-9]\d{9}$').hasMatch(mobile)) {
      throw ImportException('手机号格式不正确');
    }
    final device = DeviceInfo.newSession();
    final payload = jsonEncode({
      'gameId': 'xyzwapp',
      'gameTp': 'app',
      'accountNum': mobile,
      'sysInfo': device.sysInfo(),
      'activeLoginMatchId': device.activeLoginMatchId(),
      'channel': 'android',
      'verifyCodeTp': 'login',
      'distinctId': device.distinctId,
      'oaidThirdSdk': '',
      'ipv6': '',
      'limit': true,
      'packageName': XyEndpoints.bundleId,
      'signPrint': XyEndpoints.signPrint,
      'androidId': device.androidId,
      'oaId': '',
      'oaid': '',
    });

    final res = await ImportHttp.post(
      XyEndpoints.smsCode(),
      headers: {
        'Host': 'ucenter-app-server.hortorgames.com',
        'Content-Type': 'application/json; charset=utf-8',
        'User-Agent': XyEndpoints.uaApp,
        'Accept-Encoding': 'gzip',
      },
      body: utf8.encode(payload),
    );
    final text = res.text();
    if (res.status != 200) throw ImportException('发送失败 (HTTP ${res.status})');
    final o = jsonDecode(text) as Map<String, dynamic>;
    final meta = o['meta'] as Map<String, dynamic>?;
    final err = (meta?['errCode'] as num?)?.toInt() ?? (o['errCode'] as num?)?.toInt() ?? 0;
    if (err != 0) {
      final msg = meta?['errMsg'] ?? o['errMsg'];
      throw ImportException('发送失败: $msg (errCode=$err)');
    }
  }

  static Future<CodeBookRule> fetchCryptRule(DeviceInfo device) async {
    final res = await ImportHttp.get(
      XyEndpoints.cryptMix(device.deviceUniqueId),
      headers: {
        'Host': 'comb-platform.hortorgames.com',
        'User-Agent': XyEndpoints.uaIos,
        'Accept': '*/*',
        'Accept-Language': 'zh-Hans-CN;q=1',
        'Accept-Encoding': 'gzip',
      },
    );
    final text = res.text();
    if (res.status != 200) throw ImportException('取加密规则失败 (HTTP ${res.status})');
    final o = jsonDecode(text) as Map<String, dynamic>;
    final rule = (o['data'] as Map<String, dynamic>?)?['cryptRule'] as Map<String, dynamic>?;
    final codeBook = rule?['codeBook'] as String? ?? '';
    if (codeBook.isEmpty) throw ImportException('加密规则里没有 codeBook');
    return CodeBookRule(
      codeBook: codeBook,
      swapTimes: (rule?['swapTimes'] as num?)?.toInt() ?? 0,
      keySkip: (rule?['keySkip'] as num?)?.toInt() ?? 0,
      keyOffset: (rule?['keyOffset'] as num?)?.toInt() ?? 0,
    );
  }

  static Future<LoginResult> loginBySms(String mobile, String smsCode) async {
    final device = DeviceInfo.session();
    final payload = jsonEncode({
      'smsCode': smsCode,
      'mac': '02:00:00:00:00:00',
      'tp': 'app-mobile',
      'mobile': mobile,
      'gameId': 'xyzwapp',
      'channel': 'AppStore',
      'idfa': '00000000-0000-0000-0000-000000000000',
      'version': XyEndpoints.iosVersion,
      'distinctId': device.distinctId,
      'activeLoginMatchId': device.distinctId,
      'gameTp': 'app',
      'packageName': XyEndpoints.bundleId,
      'sysInfo': device.iosSysInfo(),
      'caidInfo': device.caidInfo(),
      'idfv': device.idfv,
      'deviceUniqueId': device.deviceUniqueId,
    });
    return _combLogin(device, payload);
  }

  static Future<LoginResult> loginByWxCode(String code) async {
    final device = DeviceInfo.session();
    final payload = jsonEncode({
      'code': code,
      'state': 'weixin',
      'mac': '02:00:00:00:00:00',
      'tp': 'app-we',
      'gameId': 'xyzwapp',
      'channel': 'AppStore',
      'idfa': '00000000-0000-0000-0000-000000000000',
      'version': XyEndpoints.iosVersion,
      'distinctId': device.distinctId,
      'activeLoginMatchId': device.distinctId,
      'gameTp': 'app',
      'packageName': XyEndpoints.bundleId,
      'sysInfo': device.iosSysInfo(),
      'caidInfo': device.caidInfo(),
      'idfv': device.idfv,
      'deviceUniqueId': device.deviceUniqueId,
    });
    return _combLogin(device, payload);
  }

  static Future<LoginResult> _combLogin(DeviceInfo device, String payload) async {
    final rule = await fetchCryptRule(device);
    final body = CodeBookCrypto.encrypt(payload, rule);
    final res = await ImportHttp.post(
      XyEndpoints.combLoginApp(device.deviceUniqueId),
      headers: {
        'Host': 'comb-platform.hortorgames.com',
        'Content-Type': 'application/json; charset=utf-8',
        'User-Agent': XyEndpoints.uaIos,
        'Accept': '*/*',
        'Accept-Language': 'zh-Hans-CN;q=1',
        'Accept-Encoding': 'gzip',
      },
      body: ascii.encode(body),
    );
    final text = res.text();
    if (res.status != 200) throw ImportException('登录失败 (HTTP ${res.status})');
    final o = jsonDecode(text) as Map<String, dynamic>;
    final meta = o['meta'] as Map<String, dynamic>?;
    final err = (meta?['errCode'] as num?)?.toInt() ?? (o['errCode'] as num?)?.toInt() ?? 0;
    if (err != 0) {
      final msg = meta?['errMsg'] ?? o['errMsg'];
      throw ImportException('登录失败: $msg (errCode=$err)');
    }
    final holder = _findCredentialHolder(o);
    if (holder == null) {
      throw ImportException('登录响应缺少 combUser，原文: ${_take(text, 300)}');
    }
    final combUser = '${holder['encryptCombUser'] ?? ''}';
    final ts = (holder['timestamp'] as num?)?.toInt() ?? 0;
    final sign = '${holder['sign'] ?? ''}';
    if (combUser.isEmpty || sign.isEmpty || ts == 0) {
      throw ImportException('凭据不完整 combUser=${combUser.length}字符 ts=$ts sign=${sign.length}字符');
    }
    return LoginResult(combUser, ts, sign, text);
  }

  static Map<String, dynamic>? _findCredentialHolder(Map<String, dynamic> root, [int depth = 0]) {
    if (depth > 4) return null;
    if (root.containsKey('encryptCombUser')) return root;
    final direct = root['combUser'];
    if (direct is String && direct.length > 64 && root.containsKey('sign')) {
      return {
        'encryptCombUser': direct,
        'timestamp': root['timestamp'] ?? 0,
        'sign': root['sign'],
      };
    }
    for (final v in root.values) {
      if (v is Map<String, dynamic>) {
        final found = _findCredentialHolder(v, depth + 1);
        if (found != null) return found;
      }
    }
    return null;
  }
}

class DeviceInfo {
  DeviceInfo._({
    required this.distinctId,
    required this.androidId,
    required this.deviceUniqueId,
    required this.idfv,
    required this.system,
    required this.model,
    required this.brand,
    required this.iosModel,
    required this.iosVer,
    required this.hwModel,
  });

  final String distinctId;
  final String androidId;
  final String deviceUniqueId;
  final String idfv;
  final String system;
  final String model;
  final String brand;
  final String iosModel;
  final String iosVer;
  final String hwModel;

  static DeviceInfo? _cached;
  static final _uuid = const Uuid();
  static final _rng = Random.secure();

  static const _androidTemplates = [
    ('Android 12', 'ALN-AL1', 'HUAWEI'),
    ('Android 10', '23116PN5BC', 'Xiaomi'),
  ];
  static const _iosTemplates = [
    ('iPhone15,3', '26.4.2', 'D74AP'),
    ('iPhone14,7', '18.6.1', 'D27AP'),
  ];

  static String _hex(int n) {
    const cs = '0123456789abcdef';
    final sb = StringBuffer();
    for (var i = 0; i < n; i++) {
      sb.write(cs[_rng.nextInt(cs.length)]);
    }
    return sb.toString();
  }

  static DeviceInfo random() {
    final a = _androidTemplates[_rng.nextInt(_androidTemplates.length)];
    final i = _iosTemplates[_rng.nextInt(_iosTemplates.length)];
    final uid = _uuid.v4().toUpperCase();
    return DeviceInfo._(
      distinctId: uid,
      androidId: _hex(16),
      deviceUniqueId: uid,
      idfv: _uuid.v4().toUpperCase(),
      system: a.$1,
      model: a.$2,
      brand: a.$3,
      iosModel: i.$1,
      iosVer: i.$2,
      hwModel: i.$3,
    );
  }

  static DeviceInfo session() => _cached ??= random();
  static DeviceInfo newSession() {
    _cached = random();
    return _cached!;
  }

  String sysInfo() => jsonEncode({
        'system': system,
        'hortorSDKVersion': XyEndpoints.hortorSdkVersion,
        'model': model,
        'brand': brand,
      });

  String iosSysInfo() => jsonEncode({
        'system': 'iOS $iosVer',
        'model': iosModel,
        'brand': 'Apple',
        'hortorSDKVersion': XyEndpoints.iosSdkVersion,
      });

  Map<String, dynamic> caidInfo() => {
        'carrierInfo': 'unknown',
        'machine': iosModel,
        'mntId': '${_hex(64).toUpperCase()}@/dev/disk1s1',
        'sysFileTime': (DateTime.now().millisecondsSinceEpoch / 1000).toStringAsFixed(6),
        'countryCode': 'CN',
        'deviceInitTime': '1679115838.749221083',
        'deviceName': _hex(32),
        'systemVersion': iosVer,
        'language': 'zh-Hans-CN',
        'memory': '5909987328',
        'disk': '255866785792',
        'bootTimeInSec':
            '${DateTime.now().millisecondsSinceEpoch ~/ 1000 - 86400}',
        'timeZone': '28800',
        'model': hwModel,
      };

  String activeLoginMatchId() =>
      '${DateTime.now().millisecondsSinceEpoch}_$distinctId';
}
