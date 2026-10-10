import 'dart:io';

import 'package:flutter/foundation.dart';

/// 首页就绪后预拉本地引擎关键文件，暖热磁盘与 WebView HTTP 缓存，
/// 让第二次及以后进游戏少走「滚动下载」。
class RendererWarmup {
  RendererWarmup._();

  static Future<void> prefetch(String baseUrl, Directory root) async {
    final paths = await _criticalPaths(root);
    if (paths.isEmpty) return;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    var ok = 0;
    try {
      for (final path in paths) {
        try {
          final uri = Uri.parse('$baseUrl/$path');
          final req = await client.getUrl(uri);
          req.headers.set(HttpHeaders.cacheControlHeader, 'max-age=604800');
          final res = await req.close().timeout(const Duration(seconds: 8));
          await res.drain<void>();
          if (res.statusCode == 200) ok++;
        } catch (_) {}
      }
    } finally {
      client.close(force: true);
    }
    debugPrint('[咸强之王] 资源预热 $ok/${paths.length}');
  }

  static Future<List<String>> _criticalPaths(Directory root) async {
    final names = <String>{
      'index.html',
      'patch.js',
      'cocos-bundle-patch.js',
      'hsdk-mock.js',
      'naiwa-uifix.css',
    };
    try {
      await for (final e in root.list(followLinks: false)) {
        if (e is! File) continue;
        final name = e.uri.pathSegments.isEmpty
            ? e.path.split(Platform.pathSeparator).last
            : e.uri.pathSegments.last;
        if (name.startsWith('main.') && name.endsWith('.js')) names.add(name);
        if (name.startsWith('cocos2d-js-min.') && name.endsWith('.js')) {
          names.add(name);
        }
        if (name.startsWith('game-defines.') && name.endsWith('.js')) {
          names.add(name);
        }
        if (name.startsWith('style-mobile.') && name.endsWith('.css')) {
          names.add(name);
        }
      }
      final src = Directory('${root.path}${Platform.pathSeparator}src');
      if (await src.exists()) {
        await for (final e in src.list(followLinks: false)) {
          if (e is! File) continue;
          final name = e.path.split(Platform.pathSeparator).last;
          if (name.startsWith('settings.') && name.endsWith('.js')) {
            names.add('src/$name');
          }
        }
      }
    } catch (e) {
      debugPrint('[咸强之王] 预热清单失败 $e');
    }
    return names.toList()..sort();
  }
}
