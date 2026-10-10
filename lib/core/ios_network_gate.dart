import 'dart:io';

import 'package:flutter/cupertino.dart';

import 'app_log.dart';

/// iOS：启动时预检外网 + 触发「本地网络」权限，避免导入/进游戏时才弹窗导致失败。
class IosNetworkGate {
  IosNetworkGate._();

  static var _checked = false;

  /// 返回 true 表示当前可继续导入/进游戏。
  static Future<bool> ensureReady(BuildContext context) async {
    if (!Platform.isIOS) return true;
    if (_checked) {
      final ok = await _probe();
      if (ok) return true;
    }

    AppLog.i('net', '启动网络预检…');
    var ok = await _probe();
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
        title: const Text('需要网络权限'),
        content: const Text(
          '请先允许「无线局域网与蜂窝移动网络」，'
          '并在出现「本地网络」提示时点允许。\n'
          '完成后点下方「已授权，重试」。',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('已授权，重试'),
          ),
        ],
      ),
    );

    // 用户授权后多试几次（系统弹窗关闭后 DNS 可能稍有延迟）
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(Duration(milliseconds: 400 + i * 200));
      ok = await _probe();
      AppLog.diag('net', {'event': 'retry_probe', 'i': i, 'ok': ok});
      if (ok) break;
    }

    if (!ok && context.mounted) {
      await showCupertinoDialog<void>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('仍无法联网'),
          content: const Text(
            '请到 设置 → 咸强之王，确认已打开无线局域网/蜂窝数据，'
            '以及「本地网络」。连上 Wi‑Fi 或蜂窝后再试。',
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

  /// 静默预检（首页启动时调用，不弹窗阻塞首屏太久）。
  static Future<void> warmUp() async {
    if (!Platform.isIOS) return;
    try {
      final ok = await _probe();
      AppLog.diag('net', {'event': 'warmup', 'ok': ok});
      if (ok) _checked = true;
    } catch (e) {
      AppLog.w('net', 'warmup失败 $e');
    }
  }

  static Future<bool> _probe() async {
    // 1) 打本机 HTTP：触发本地网络相关权限路径
    try {
      final local = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      try {
        final req = await local.getUrl(Uri.parse('http://127.0.0.1:9/'));
        req.followRedirects = false;
        try {
          await req.close().timeout(const Duration(milliseconds: 800));
        } catch (_) {}
      } finally {
        local.close(force: true);
      }
    } catch (_) {}

    // 2) DNS + HTTPS：确认外网可用（导入/进服都需要）
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
      // 任何 HTTP 响应都算网络通（403/404 也说明 DNS/链路 OK）
      return res.statusCode > 0;
    } on SocketException catch (e) {
      AppLog.w('net', 'probe SocketException: $e');
      return false;
    } on HandshakeException catch (e) {
      // TLS 握手失败仍说明能解析并连上
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
