import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/user_script.dart';

/// 把启用的脚本写到本地 HTTP 根目录的 `userscripts/`，由页面 `<script src>` 加载。
/// 大脚本必须从磁盘复制，禁止对整份正文做哈希/再编码，否则会 OOM 导致发布中断，
/// 表现就是只有内置脚本生效、外部脚本永远挂不上。
class ScriptCache {
  ScriptCache._();

  static const subdir = 'userscripts';

  /// 只根据 id 生成文件名，与正文长度无关，避免扫 3MB+ 字符串。
  /// 必须用 BigInt：Dart 的 `0xFFFFFFFFFFFFFFFF == -1`，普通 int FNV 会得到
  /// 负十六进制名（如 `-7284….js`），被 HTTP 校验丢掉 → 发布 2/2 却只挂上 1 个。
  static String fileNameOf(String id) {
    var h = BigInt.parse('cbf29ce484222325', radix: 16);
    final mask = (BigInt.one << 64) - BigInt.one;
    final prime = BigInt.parse('100000001b3', radix: 16);
    for (final b in id.codeUnits) {
      h ^= BigInt.from(b);
      h = (h * prime) & mask;
    }
    return '${h.toRadixString(16).padLeft(16, '0')}.js';
  }

  static Future<List<({String id, String name, String url, int bytes})>> publish({
    required Directory root,
    required List<UserScript> scripts,
    File? Function(String id)? sourceFile,
  }) async {
    final dir = Directory('${root.path}${Platform.pathSeparator}$subdir');
    if (!await dir.exists()) await dir.create(recursive: true);

    final alive = <String>{'_order.json'};
    final out = <({String id, String name, String url, int bytes})>[];

    for (final s in scripts) {
      try {
        final name = fileNameOf(s.id);
        alive.add(name);
        final dest = File('${dir.path}${Platform.pathSeparator}$name');
        final src = sourceFile?.call(s.id);
        var bytes = 0;

        if (src != null && await src.exists()) {
          bytes = await src.length();
          if (bytes <= 0) {
            debugPrint('[咸强之王] 跳过空脚本文件 ${s.name}');
            continue;
          }
          if (!await dest.exists() || await dest.length() != bytes) {
            await src.copy(dest.path);
          }
        } else if (s.code.isNotEmpty) {
          final data = utf8.encode(s.code);
          bytes = data.length;
          if (!await dest.exists() || await dest.length() != bytes) {
            await dest.writeAsBytes(data, flush: true);
          }
        } else {
          debugPrint('[咸强之王] 跳过无正文脚本 ${s.name}');
          continue;
        }

        bytes = await dest.length();
        out.add((
          id: s.id,
          name: s.displayName,
          url: '$subdir/$name',
          bytes: bytes,
        ));
        debugPrint(
          '[咸强之王] 已发布 ${s.displayName} → $name ($bytes bytes, preset=${s.preset})',
        );
      } catch (e, st) {
        debugPrint('[咸强之王] 发布失败 ${s.name}: $e\n$st');
      }
    }

    final order = File('${dir.path}${Platform.pathSeparator}_order.json');
    await order.writeAsString(
      jsonEncode([for (final e in out) e.url.split('/').last]),
      flush: true,
    );

    try {
      await for (final e in dir.list()) {
        if (e is File &&
            !alive.contains(e.path.split(Platform.pathSeparator).last)) {
          await e.delete();
        }
      }
    } catch (_) {}

    debugPrint('[咸强之王] 共发布 ${out.length}/${scripts.length} 个脚本到 ${dir.path}');
    return out;
  }
}
