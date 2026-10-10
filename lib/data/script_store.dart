import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'user_script.dart';

/// 用户脚本持久化：元数据在 prefs，正文落盘（大脚本不塞 SharedPreferences）。
/// 仅外部导入脚本，不再同步内置预设。
class ScriptStore extends ChangeNotifier {
  ScriptStore();

  static const _prefsKey = 'scripts_meta_v1';
  static const _uuid = Uuid();

  final List<UserScript> _scripts = [];
  Directory? _dir;

  List<UserScript> get scripts {
    final list = List<UserScript>.from(_scripts)
      ..sort((a, b) => a.order.compareTo(b.order));
    return List.unmodifiable(list);
  }

  List<UserScript> get enabledScripts {
    final list = _scripts.where((s) => s.enabled).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  /// 正文落盘路径。发布到 HTTP 目录时优先 copy，避免再把大脚本读进内存编码一遍。
  File? codeFile(String id) {
    final dir = _dir;
    if (dir == null) return null;
    return File('${dir.path}${Platform.pathSeparator}$id.js');
  }

  Future<void> load() async {
    final docs = await getApplicationDocumentsDirectory();
    _dir = Directory('${docs.path}${Platform.pathSeparator}userscripts');
    if (!await _dir!.exists()) await _dir!.create(recursive: true);

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    _scripts.clear();
    if (raw != null && raw.isNotEmpty) {
      final list = jsonDecode(raw) as List<dynamic>;
      for (final item in list) {
        final meta = item as Map<String, dynamic>;
        final id = meta['id'] as String?;
        if (id == null) continue;
        // 丢掉旧版内置预设
        if (meta['preset'] == true || id.startsWith('preset:')) {
          final file = File('${_dir!.path}${Platform.pathSeparator}$id.js');
          if (await file.exists()) {
            try {
              await file.delete();
            } catch (_) {}
          }
          continue;
        }
        final file = File('${_dir!.path}${Platform.pathSeparator}$id.js');
        var code = '';
        if (await file.exists()) {
          code = await file.readAsString();
        }
        _scripts.add(UserScript.fromMeta(meta, code));
      }
    }
    await _saveMeta();
    notifyListeners();
  }

  Future<void> _saveMeta() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(_scripts.map((e) => e.toMeta()).toList()),
    );
  }

  Future<void> _writeCode(UserScript s) async {
    final dir = _dir;
    if (dir == null) return;
    final file = File('${dir.path}${Platform.pathSeparator}${s.id}.js');
    await file.writeAsString(s.code, flush: true);
  }

  Future<void> _writeCodeBytes(UserScript s, List<int> bytes) async {
    final dir = _dir;
    if (dir == null) return;
    final file = File('${dir.path}${Platform.pathSeparator}${s.id}.js');
    await file.writeAsBytes(bytes, flush: true);
  }

  Future<UserScript> addScript(String name, String code, {List<int>? rawBytes}) async {
    final item = UserScript(
      id: _uuid.v4(),
      name: name,
      code: code,
      enabled: true,
      order: (_scripts.isEmpty
              ? 0
              : _scripts.map((e) => e.order).reduce((a, b) => a > b ? a : b)) +
          1,
    );
    _scripts.add(item);
    if (rawBytes != null && rawBytes.isNotEmpty) {
      await _writeCodeBytes(item, rawBytes);
    } else {
      await _writeCode(item);
    }
    await _saveMeta();
    notifyListeners();
    debugPrint('[咸强之王] 已导入脚本 ${item.displayName} ${code.length} 字符');
    return item;
  }

  Future<void> toggle(String id, bool enabled) async {
    final i = _scripts.indexWhere((e) => e.id == id);
    if (i < 0) return;
    if (_scripts[i].locked) return;
    _scripts[i] = _scripts[i].copyWith(enabled: enabled);
    await _saveMeta();
    notifyListeners();
  }

  Future<void> setAllEnabled(bool enabled) async {
    var n = 0;
    for (var i = 0; i < _scripts.length; i++) {
      final s = _scripts[i];
      if (s.locked || s.enabled == enabled) continue;
      _scripts[i] = s.copyWith(enabled: enabled);
      n++;
    }
    if (n == 0) {
      notifyListeners();
      return;
    }
    await _saveMeta();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    final i = _scripts.indexWhere((e) => e.id == id);
    if (i < 0) return;
    if (_scripts[i].locked) return;
    final gone = _scripts.removeAt(i);
    final dir = _dir;
    if (dir != null) {
      final file = File('${dir.path}${Platform.pathSeparator}${gone.id}.js');
      if (await file.exists()) await file.delete();
    }
    await _saveMeta();
    notifyListeners();
  }
}
