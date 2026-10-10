import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/app_log.dart';

/// roleId → 自定义头像 URL。查全服没有 headImg，进游戏后回写，下次导入可复用。
abstract final class RoleAvatarCache {
  static final Map<int, String> _mem = {};
  static Future<void>? _loading;
  static bool _loaded = false;

  static Future<void> ensureLoaded() {
    if (_loaded) return Future.value();
    return _loading ??= _load();
  }

  static Future<void> _load() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        final raw = jsonDecode(await f.readAsString());
        if (raw is Map) {
          raw.forEach((k, v) {
            final id = int.tryParse('$k');
            final url = '$v'.trim();
            if (id != null && id > 0 && url.startsWith('http')) {
              _mem[id] = url;
            }
          });
        }
      }
    } catch (e) {
      AppLog.w('avatar', 'cache load: $e');
    } finally {
      // 用户提供的可访问样例：查全服无 headImg 时先用它验证显示链路。
      _mem.putIfAbsent(
        44944993,
        () =>
            'https://mars-face.hortorgames.com/xxz-xyzw-head-img/release/44944993/1788846384.jpg',
      );
      _loaded = true;
      _loading = null;
    }
  }

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}${Platform.pathSeparator}role_avatars.json');
  }

  static String? get(int roleId) {
    if (roleId <= 0) return null;
    return _mem[roleId];
  }

  static String normalize(String raw) {
    var s = raw.trim();
    if (s.contains('xxz-xyzw-res.hortorgames.com') &&
        s.contains('xxz-xyzw-head-img')) {
      s = s.replaceFirst(
        'xxz-xyzw-res.hortorgames.com',
        'mars-face.hortorgames.com',
      );
    }
    return s;
  }

  static Future<void> put(int roleId, String url) async {
    final u = normalize(url);
    if (roleId <= 0 || !u.startsWith('http')) return;
    // 占位图不进缓存
    if (u.contains('xiaoyugan.png') || u.contains('default_avatar')) return;
    if (_mem[roleId] == u) return;
    await ensureLoaded();
    _mem[roleId] = u;
    try {
      final f = await _file();
      await f.writeAsString(
        jsonEncode({for (final e in _mem.entries) '${e.key}': e.value}),
        flush: true,
      );
    } catch (e) {
      AppLog.w('avatar', 'cache save: $e');
    }
  }

  /// 从 bin 文件名解析 roleId：`01-战力-区服-44944993-名字.bin`
  static int? roleIdFromName(String name) {
    final ms = RegExp(r'-(\d{6,})-').allMatches(name).toList();
    if (ms.isEmpty) return null;
    return int.tryParse(ms.last.group(1)!);
  }

  /// 账号展示用头像：自身 URL → 缓存 → 原样。
  static String? displayUrl(String? avatarUrl, String accountName) {
    final raw = avatarUrl?.trim();
    if (raw != null && raw.isNotEmpty) {
      for (final p in raw.split('|')) {
        final t = p.trim();
        if (t.startsWith('http')) return t;
      }
      return raw;
    }
    final id = roleIdFromName(accountName);
    if (id != null) return get(id);
    return null;
  }
}
