import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// 对照 naiwa-release:
/// `app/src/main/java/com/sharkking/assistant/core/RendererCache.kt`
///
/// 把 assets/renderer 展开到缓存目录，供 LocalHttpServer 作为静态根。
class RendererCache {
  RendererCache._();

  static const _assetRoot = 'assets/renderer';
  // 改动 renderer 下任何文件都要升这个版本号，否则旧缓存不会被替换
  static const _stampName = '.copied_v7';

  static Future<Directory> ensure() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}${Platform.pathSeparator}renderer');
    final stamp = File('${dir.path}${Platform.pathSeparator}$_stampName');

    if (await stamp.exists()) {
      debugPrint('[咸强之王] 渲染缓存目录有效');
      return dir;
    }

    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await dir.create(recursive: true);

    final keys = await _listRendererAssets();
    for (final assetPath in keys) {
      final rel = assetPath.substring('$_assetRoot/'.length);
      if (rel.isEmpty || rel.endsWith('/')) continue;
      final out = File(
        '${dir.path}${Platform.pathSeparator}${rel.replaceAll('/', Platform.pathSeparator)}',
      );
      await _copyAsset(assetPath, out);
    }

    await stamp.writeAsString(DateTime.now().millisecondsSinceEpoch.toString());
    debugPrint('[咸强之王] 已复制 ${keys.length} 个渲染文件到缓存目录: ${dir.path}');
    return dir;
  }

  /// 列出 pubspec 声明的 assets/renderer/**（兼容 AssetManifest.json / .bin）
  static Future<List<String>> _listRendererAssets() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      return manifest
          .listAssets()
          .where((k) => k.startsWith('$_assetRoot/'))
          .toList()
        ..sort();
    } catch (_) {
      // 旧引擎回退
      try {
        final raw = await rootBundle.loadString('AssetManifest.json');
        final map = jsonDecode(raw) as Map<String, dynamic>;
        return map.keys.where((k) => k.startsWith('$_assetRoot/')).toList()
          ..sort();
      } catch (e) {
        debugPrint('[咸强之王] 无法读取 AssetManifest: $e');
        return const [];
      }
    }
  }

  /// 开发期：若用户把完整 renderer 放在外部目录，可合并进缓存（不入库）。
  static Future<void> mergeFromExternal(Directory sourceDir, Directory cacheDir) async {
    if (!await sourceDir.exists()) return;
    await for (final entity in sourceDir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final rel = entity.path
          .substring(sourceDir.path.length)
          .replaceFirst(RegExp(r'^[/\\]'), '');
      if (rel.startsWith('.')) continue;
      final out = File('${cacheDir.path}${Platform.pathSeparator}$rel');
      await out.parent.create(recursive: true);
      await entity.copy(out.path);
    }
    debugPrint('[咸强之王] 已合并外部 renderer: ${sourceDir.path}');
  }

  /// 删除 stamp，下次 ensure 会重新从 assets 展开（开发换资源后调用）。
  static Future<void> invalidate() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}${Platform.pathSeparator}renderer');
    final stamp = File('${dir.path}${Platform.pathSeparator}$_stampName');
    // 顺带清掉旧版 stamp
    for (final name in [
      '.copied_v1',
      '.copied_v2',
      '.copied_v3',
      '.copied_v4',
      '.copied_v5',
      _stampName,
    ]) {
      final f = File('${dir.path}${Platform.pathSeparator}$name');
      if (await f.exists()) await f.delete();
    }
    if (await stamp.exists()) await stamp.delete();
    debugPrint('[咸强之王] 已作废渲染缓存 stamp');
  }

  static Future<void> _copyAsset(String assetPath, File outFile) async {
    try {
      final data = await rootBundle.load(assetPath);
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    } catch (e) {
      debugPrint('[咸强之王] 复制失败 $assetPath: $e');
    }
  }
}
