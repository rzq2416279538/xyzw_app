import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// 内存环形日志 + iOS 落盘，便于真机 IPA 导出排查。
class AppLog {
  AppLog._();

  static const _cap = 4000;
  static final _lines = Queue<String>();
  static var _headerWritten = false;
  static IOSink? _sink;
  static var _clientBurst = 0;
  static DateTime? _clientBurstAt;

  static void i(String tag, String msg) => _add('I', tag, msg);

  static void w(String tag, String msg) => _add('W', tag, msg);

  static void e(String tag, String msg) => _add('E', tag, msg);

  static void js(String msg) => _add('JS', 'webview', msg);

  /// 结构化诊断，方便在导出日志里用 `[DIAG]` 搜索。
  static void diag(String tag, Map<String, Object?> fields) {
    final body = fields.entries
        .map((e) => '${e.key}=${e.value ?? 'null'}')
        .join(' ');
    _add('D', tag, body);
  }

  static Future<void> ensureBootHeader({
    required String appVersion,
  }) async {
    if (_headerWritten) return;
    _headerWritten = true;
    final os = Platform.isIOS
        ? 'iOS'
        : Platform.isAndroid
            ? 'Android'
            : Platform.operatingSystem;
    i('boot', '==== 咸强之王启动 ====');
    diag('boot', {
      'platform': os,
      'osVersion': Platform.operatingSystemVersion,
      'locale': Platform.localeName,
      'appVersion': appVersion,
      'debug': kDebugMode,
      'numberOfProcessors': Platform.numberOfProcessors,
    });
    if (Platform.isIOS) {
      await _openPersistFile();
    }
  }

  static Future<void> _openPersistFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(
        '${dir.path}${Platform.pathSeparator}xyzw_latest.log',
      );
      // 追加写入，保留最近若干次运行痕迹
      _sink = file.openWrite(mode: FileMode.writeOnlyAppend);
      _sink!.writeln('');
      _sink!.writeln('======== session ${DateTime.now().toIso8601String()} ========');
      await _sink!.flush();
      i('boot', 'iOS日志落盘 ${file.path}');
    } catch (e) {
      w('boot', '日志落盘失败 $e');
    }
  }

  static void _add(String level, String tag, String msg) {
    // client/webview 异常刷屏会淹没 lifecycle，导出日志就只剩垃圾
    if (tag == 'client' || (tag == 'webview' && msg.contains('CLIENT_ANOMALY'))) {
      final now = DateTime.now();
      if (_clientBurstAt == null ||
          now.difference(_clientBurstAt!).inSeconds >= 3) {
        _clientBurstAt = now;
        _clientBurst = 0;
      }
      _clientBurst++;
      if (_clientBurst > 12) return;
    }
    final t = DateTime.now().toIso8601String();
    final line = '$t [$level][$tag] $msg';
    // lifecycle/game 优先保留：满了先丢非关键行
    if (_lines.length >= _cap &&
        (tag == 'lifecycle' || tag == 'game' || tag == 'boot')) {
      String? victim;
      for (final e in _lines) {
        if (!e.contains('[lifecycle]') &&
            !e.contains('[game]') &&
            !e.contains('[boot]')) {
          victim = e;
          break;
        }
      }
      if (victim != null) {
        _lines.remove(victim);
      } else {
        _lines.removeFirst();
      }
    } else {
      while (_lines.length >= _cap) {
        _lines.removeFirst();
      }
    }
    _lines.add(line);
    try {
      _sink?.writeln(line);
    } catch (_) {}
    final noisy = tag == 'webview' && !msg.contains('咸强之王');
    if (!noisy && (kDebugMode || level == 'E' || level == 'D' || tag == 'game' || tag == 'boot' || tag == 'lifecycle')) {
      debugPrint('[咸强之王][$tag] $msg');
    }
  }

  static String dump() {
    final buf = StringBuffer();
    buf.writeln('咸强之王诊断日志');
    buf.writeln('导出时间: ${DateTime.now().toIso8601String()}');
    buf.writeln('平台: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    buf.writeln('---');
    if (_lines.isEmpty) {
      buf.writeln('（暂无日志）');
    } else {
      buf.writeln(_lines.join('\n'));
    }
    buf.writeln('');
    return buf.toString();
  }

  /// iOS：优先写入 Documents 并复制剪贴板；Android：系统保存框。
  static Future<String> exportFile() async {
    try {
      await _sink?.flush();
    } catch (_) {}
    final text = dump();
    final bytes = Uint8List.fromList(utf8.encode(text));
    final name =
        '咸强之王-日志-${DateTime.now().toIso8601String().replaceAll(':', '-')}.txt';

    if (Platform.isIOS) {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}$name');
      await file.writeAsBytes(bytes, flush: true);
      // 同步覆盖 latest，方便用户从「文件」App 找
      try {
        final latest = File(
          '${dir.path}${Platform.pathSeparator}xyzw_latest.log',
        );
        await latest.writeAsString(text, flush: true);
      } catch (_) {}
      await Clipboard.setData(ClipboardData(text: text));
      return '已保存到「文件」App → 我的 iPhone → 咸强之王\n$name\n并已复制到剪贴板';
    }

    try {
      final saved = await FilePicker.platform.saveFile(
        dialogTitle: '导出日志',
        fileName: name,
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: const ['txt'],
      );
      if (saved != null && saved.isNotEmpty) return '已保存：$saved';
    } catch (_) {}
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(bytes, flush: true);
    await Clipboard.setData(ClipboardData(text: text));
    return '已写入 ${file.path}，并复制到剪贴板';
  }

  static Future<void> dispose() async {
    try {
      await _sink?.flush();
      await _sink?.close();
    } catch (_) {}
    _sink = null;
  }
}
