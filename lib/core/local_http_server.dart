import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

/// 对照 naiwa-release LocalHttpServer。
/// 静态文件在独立 isolate 里读盘，避免引擎资源堵住 Flutter UI。
class LocalHttpServer {
  LocalHttpServer(this.rootDir);

  final Directory rootDir;

  Isolate? _isolate;
  SendPort? _cmd;
  ReceivePort? _inbox;
  int port = 0;

  /// iOS：必须用 127.0.0.1（localhost 常走 IPv6 ::1，服务只听 IPv4）。
  /// Android：保留 localhost，兼容部分油猴脚本白名单。
  String get baseUrl =>
      Platform.isIOS ? 'http://127.0.0.1:$port' : 'http://localhost:$port';

  static String binFileName(String accountId) {
    final safe = accountId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return safe.isEmpty ? 'account' : safe;
  }

  Future<String?> start() async {
    if (port != 0) return baseUrl;
    if (!await rootDir.exists()) {
      debugPrint('[咸强之王-HTTP] 目录不存在: ${rootDir.path}');
      return null;
    }
    final inbox = ReceivePort();
    _inbox = inbox;
    try {
      final ready = Completer<Object?>();
      inbox.listen((event) {
        if (!ready.isCompleted) {
          ready.complete(event);
          return;
        }
        if (event is String) debugPrint('[咸强之王-HTTP] $event');
      });
      _isolate = await Isolate.spawn(
        _httpIsolateMain,
        (rootDir.path, inbox.sendPort),
        debugName: 'xyzw-http',
      );
      final msg = await ready.future.timeout(const Duration(seconds: 8));
      if (msg is! List || msg.length < 2 || msg[0] is! int || msg[1] is! SendPort) {
        debugPrint('[咸强之王-HTTP] 无法创建监听器: $msg');
        await stop();
        return null;
      }
      port = msg[0] as int;
      _cmd = msg[1] as SendPort;
      debugPrint('[咸强之王-HTTP] 服务器已就绪: $baseUrl');
      return baseUrl;
    } catch (e) {
      debugPrint('[咸强之王-HTTP] 无法创建监听器: $e');
      await stop();
      return null;
    }
  }

  Future<void> stop() async {
    try {
      _cmd?.send('stop');
    } catch (_) {}
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _cmd = null;
    _inbox?.close();
    _inbox = null;
    port = 0;
    debugPrint('[咸强之王-HTTP] 服务器已停止');
  }
}

void _httpIsolateMain((String root, SendPort ready) args) async {
  final rootDir = Directory(args.$1);
  final cache = <String, ({File file, int length, String mime})>{};
  HttpServer? server;
  try {
    server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
      backlog: 128,
      shared: false,
    );
    final cmd = ReceivePort();
    args.$2.send([server.port, cmd.sendPort]);
    cmd.listen((msg) async {
      if (msg == 'stop') {
        await server?.close(force: true);
        cmd.close();
        Isolate.current.kill(priority: Isolate.immediate);
      }
    });
    await for (final request in server) {
      _handle(rootDir, request, cache, args.$2);
    }
  } catch (e) {
    args.$2.send('error:$e');
  }
}

Future<void> _handle(
  Directory rootDir,
  HttpRequest request,
  Map<String, ({File file, int length, String mime})> cache,
  SendPort log,
) async {
  try {
    final path = Uri.decodeFull(request.uri.path);
    await _serveFile(rootDir, path, request.response, cache, log);
  } catch (e) {
    log.send('请求处理失败: $e');
    try {
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    } catch (_) {}
  }
}

final _authHint = RegExp(
  r'device-auth|card-keys|device-config|licen[cs]e|/auth/',
  caseSensitive: false,
);

const _mime = {
  'html': 'text/html; charset=utf-8',
  'js': 'application/javascript; charset=utf-8',
  'css': 'text/css; charset=utf-8',
  'json': 'application/json',
  'wasm': 'application/wasm',
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'webp': 'image/webp',
  'ico': 'image/x-icon',
  'mp3': 'audio/mpeg',
  'ogg': 'audio/ogg',
  'wav': 'audio/wav',
  'ttf': 'font/ttf',
  'woff': 'font/woff',
  'woff2': 'font/woff2',
  'bin': 'application/octet-stream',
};

Future<void> _serveFile(
  Directory rootDir,
  String path,
  HttpResponse response,
  Map<String, ({File file, int length, String mime})> cache,
  SendPort log,
) async {
  if (path == '/' || path.isEmpty || path == '/index.html') {
    await _serveIndex(rootDir, response, log);
    return;
  }
  if (path.startsWith('/__xyzw/bin/')) {
    await _serveBin(rootDir, path, response);
    return;
  }
  final freshScript =
      path.contains('/userscripts/') || path.endsWith('/xyzw-gm-shim.js');
  final cached = freshScript ? null : cache[path];
  if (cached != null) {
    await _send(response, cached.file, cached.length, cached.mime, path);
    return;
  }

  final rel = path.replaceFirst(RegExp(r'^/+'), '');
  if (rel.split('/').contains('..') || rel.split(r'\').contains('..')) {
    log.send('路径越界拒绝: $path');
    await _writeStatus(response, HttpStatus.forbidden, 'Forbidden');
    return;
  }
  final relative = (rel.isEmpty ? 'index.html' : rel)
      .replaceAll('/', Platform.pathSeparator);
  final target = File('${rootDir.path}${Platform.pathSeparator}$relative');

  if (!target.existsSync() || target.statSync().type != FileSystemEntityType.file) {
    if (_authHint.hasMatch(relative)) {
      log.send('脚本把后端请求发到了本地服务: /$relative');
    }
    await _writeStatus(response, HttpStatus.notFound, 'Not Found');
    return;
  }

  final ext = target.path.split('.').last.toLowerCase();
  final mime = _mime[ext] ?? 'application/octet-stream';
  final length = await target.length();
  if (!freshScript) {
    cache[path] = (file: target, length: length, mime: mime);
  }
  await _send(response, target, length, mime, path);
}

Future<void> _serveBin(Directory rootDir, String path, HttpResponse response) async {
  final name = path.substring('/__xyzw/bin/'.length);
  if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(name)) {
    await _writeStatus(response, HttpStatus.forbidden, 'Forbidden');
    return;
  }
  final file = File(
    '${rootDir.path}${Platform.pathSeparator}__xyzw_bins${Platform.pathSeparator}$name.bin',
  );
  if (!file.existsSync()) {
    await _writeStatus(response, HttpStatus.notFound, 'No bin');
    return;
  }
  final length = await file.length();
  await _send(response, file, length, 'application/octet-stream', path);
}

Future<void> _send(
  HttpResponse response,
  File file,
  int length,
  String mime,
  String path,
) async {
  final html = path.endsWith('.html') ||
      path == '/' ||
      path.isEmpty ||
      path.contains('/userscripts/') ||
      path.endsWith('/xyzw-gm-shim.js');
  final etag = '"$length-${file.lastModifiedSync().millisecondsSinceEpoch}"';
  response.headers.set(HttpHeaders.contentTypeHeader, mime);
  response.headers.set('Access-Control-Allow-Origin', '*');
  response.headers.set(HttpHeaders.etagHeader, etag);
  final noStore = html ||
      path.startsWith('/__xyzw/bin/') ||
      path.contains('/userscripts/') ||
      path.endsWith('/xyzw-gm-shim.js');
  // 带 hash 的引擎资源可长期缓存，二次进游戏走磁盘/HTTP 缓存。
  final hashed = RegExp(r'\.[a-f0-9]{4,}\.(js|css|png|jpg|jpeg|webp|wasm)$',
          caseSensitive: false)
      .hasMatch(path);
  response.headers.set(
    HttpHeaders.cacheControlHeader,
    noStore
        ? 'no-cache'
        : hashed
            ? 'public, max-age=604800, immutable'
            : 'public, max-age=86400',
  );
  response.statusCode = HttpStatus.ok;
  response.headers.set(HttpHeaders.contentLengthHeader, length);
  await response.addStream(file.openRead());
  await response.close();
}

Future<void> _serveIndex(Directory rootDir, HttpResponse response, SendPort log) async {
  final file = File('${rootDir.path}${Platform.pathSeparator}index.html');
  if (!file.existsSync()) {
    await _writeStatus(response, HttpStatus.notFound, 'Not Found');
    return;
  }
  var html = await file.readAsString();
  final tags = await _userScriptTags(rootDir, log);
  if (tags.isNotEmpty) {
    const anchor = '<script src="patch.js"';
    final at = html.indexOf(anchor);
    if (at >= 0) {
      html = html.replaceRange(at, at, tags);
    } else {
      final bodyAt = html.indexOf('<body>');
      if (bodyAt >= 0) {
        html = html.replaceRange(bodyAt + '<body>'.length, bodyAt + '<body>'.length, '\n$tags');
      } else {
        html = '$html\n$tags';
      }
    }
  }
  final bytes = utf8.encode(html);
  response.statusCode = HttpStatus.ok;
  response.headers.set(HttpHeaders.contentTypeHeader, 'text/html; charset=utf-8');
  response.headers.set(HttpHeaders.contentLengthHeader, bytes.length);
  response.headers.set('Access-Control-Allow-Origin', '*');
  response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
  response.add(bytes);
  await response.close();
}

Future<String> _userScriptTags(Directory rootDir, SendPort log) async {
  final order = File(
    '${rootDir.path}${Platform.pathSeparator}userscripts${Platform.pathSeparator}_order.json',
  );
  if (!await order.exists()) return '';
  List<dynamic> names;
  try {
    final decoded = jsonDecode(await order.readAsString());
    if (decoded is! List || decoded.isEmpty) return '';
    names = decoded;
  } catch (e) {
    log.send('脚本清单读取失败: $e');
    return '';
  }
  final safeName = RegExp(r'^[0-9a-fA-F]+\.js$');
  final files = <String>[];
  for (final item in names) {
    final name = item.toString();
    if (!safeName.hasMatch(name)) continue;
    final target = File(
      '${rootDir.path}${Platform.pathSeparator}userscripts${Platform.pathSeparator}$name',
    );
    if (target.existsSync()) files.add(name);
  }
  if (files.isEmpty) return '';
  log.send('页面挂载用户脚本 ${files.length} 个');
  final buf = StringBuffer()
    ..writeln('<script src="xyzw-gm-shim.js" charset="utf-8"></script>')
    ..writeln('<script>')
    ..writeln(
      "window.addEventListener('error',function(ev){"
      "var src=(ev&&ev.filename)||'';"
      "if(src.indexOf('userscripts/')<0)return;"
      "var msg=(ev&&ev.message)||'脚本异常';"
      "console.error('[咸强之王] '+msg);"
      "try{if(window.XyzwBridge)XyzwBridge.postMessage(JSON.stringify({type:'scriptStatus',message:msg}));}catch(e){}"
      '});',
    )
    ..writeln('</script>');
  for (final name in files) {
    buf.writeln('<script src="userscripts/$name" charset="utf-8"></script>');
  }
  buf.writeln(
    '<script>try{console.log("[咸强之王] 已挂上用户脚本 ${files.length}");'
    'if(window.XyzwBridge)XyzwBridge.postMessage(JSON.stringify({type:"scriptStatus",message:"已挂上用户脚本 ${files.length}"}));}'
    'catch(e){}</script>',
  );
  return buf.toString();
}

Future<void> _writeStatus(HttpResponse response, int code, String text) async {
  final body = text.codeUnits;
  response.statusCode = code;
  response.headers.set(HttpHeaders.contentTypeHeader, 'text/plain; charset=utf-8');
  response.headers.set(HttpHeaders.contentLengthHeader, body.length);
  response.add(body);
  await response.close();
}
