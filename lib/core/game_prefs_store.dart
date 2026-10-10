import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 游戏 localStorage 的壳侧备份。端口/WK 丢存储时用来还原帧率、声音等设置。
class GamePrefsStore {
  GamePrefsStore._();

  static const _key = 'xyzw_game_localstorage_v1';
  static var _loaded = false;
  static Map<String, String> _data = {};

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _data = {
          for (final e in decoded.entries)
            if (e.value != null) e.key.toString(): e.value.toString(),
        };
      }
    } catch (_) {}
  }

  static Map<String, String> get data => Map<String, String>.from(_data);

  static Future<void> save(Map<String, String> next) async {
    final cleaned = <String, String>{};
    for (final e in next.entries) {
      if (e.key.startsWith('__xyzw')) continue;
      if (e.value.length > 200000) continue;
      cleaned[e.key] = e.value;
    }
    if (cleaned.isEmpty) return;
    _data = cleaned;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, jsonEncode(_data));
    } catch (_) {}
  }
}
