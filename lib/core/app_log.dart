import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// 内存环形日志，供导出排查。
class AppLog {
  AppLog._();

  static const _cap = 2500;
  static final _lines = Queue<String>();

  static void i(String tag, String msg) => _add('I', tag, msg);

  static void w(String tag, String msg) => _add('W', tag, msg);

  static void e(String tag, String msg) => _add('E', tag, msg);

  static void js(String msg) => _add('JS', 'webview', msg);

  static void _add(String level, String tag, String msg) {
    final t = DateTime.now().toIso8601String();
    final line = '$t [$level][$tag] $msg';
    _lines.add(line);
    while (_lines.length > _cap) {
      _lines.removeFirst();
    }
    // WebView 控制台非常吵，打印会拖住界面线程。
    if (kDebugMode && tag != 'webview') {
      debugPrint('[咸强之王][$tag] $msg');
    }
  }

  static String dump() {
    if (_lines.isEmpty) return '（暂无日志）\n';
    return '${_lines.join('\n')}\n';
  }

  /// 弹出系统保存框；失败则写入应用目录并复制到剪贴板。
  static Future<String> exportFile() async {
    final text = dump();
    final bytes = Uint8List.fromList(utf8.encode(text));
    final name =
        '咸强之王-日志-${DateTime.now().toIso8601String().replaceAll(':', '-')}.txt';
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
}
