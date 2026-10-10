import 'dart:io';

import 'package:flutter/cupertino.dart';

import 'app_log.dart';

/// iOS：只预检「能上网」（WLAN/蜂窝），不触发「查找本地网络设备」。
class IosNetworkGate {
  IosNetworkGate._();

  static var _checked = false;

  /// 返回 true 表示当前可继续导入/进游戏。
  static Future<bool> ensureReady(BuildContext context) async {
    if (!Platform.isIOS) return true;
    if (_checked) {
      final ok = await _probeInternet();
      if (ok) return true;
    }

    AppLog.i('net', '启动网络预检（仅外网）…');
    var ok = await _probeInternet();
    if (ok) {
      _checked = true;
      AppLog.i('net', '网络预检通过');
      return true;
    }

    if (!context.mounted) return false;
    await showCupertinoDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('需要网络'),
        content: const Text(
          '请允许使用无线局域网或蜂窝移动数据。\n'
          '打开网络后点「已授权，重试」。',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('已授权，重试'),
          ),
        ],
      ),
    );

    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(Duration(milliseconds: 400 + i * 200));
      ok = await _probeInternet();
      AppLog.diag('net', {'event': 'retry_probe', 'i': i, 'ok': ok});
      if (ok) break;
    }

    if (!ok && context.mounted) {
      await showCupertinoDialog<void>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('仍无法联网'),
          content: const Text(
            '请到 设置 → 咸强之王，确认无线局域网/蜂窝数据已打开，'
            '并连上可用网络后再试。',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('好'),
            ),
          ],
        ),
      );
      return false;
    }

    _checked = ok;
    return ok;
  }

  static Future<void> warmUp() async {
    if (!Platform.isIOS) return;
    try {
      final ok = await _probeInternet();
      AppLog.diag('net', {'event': 'warmup', 'ok': ok});
      if (ok) _checked = true;
    } catch (e) {
      AppLog.w('net', 'warmup失败 $e');
    }
  }

  /// 只探测公网 HTTPS，避免 127.0.0.1 / Bonjour 触发本地网络设备权限。
  static Future<bool> _probeInternet() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client.headUrl(
        Uri.parse('https://xxz-xyzw.hortorgames.com/'),
      );
      req.followRedirects = false;
      final res = await req.close().timeout(const Duration(seconds: 8));
      await res.drain<void>();
      AppLog.diag('net', {
        'event': 'probe_https',
        'status': res.statusCode,
      });
      return res.statusCode > 0;
    } on SocketException catch (e) {
      AppLog.w('net', 'probe SocketException: $e');
      return false;
    } on HandshakeException catch (e) {
      AppLog.w('net', 'probe HandshakeException(视为可达): $e');
      return true;
    } catch (e) {
      AppLog.w('net', 'probe失败: $e');
      return false;
    } finally {
      client.close(force: true);
    }
  }
}
