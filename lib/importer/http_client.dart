import 'dart:convert';
import 'dart:io';

/// 对照 naiwa-release `importer/Http.kt`
class ImportHttp {
  ImportHttp._();

  static const _timeout = Duration(seconds: 20);

  static Future<ImportHttpResponse> get(
    String url, {
    Map<String, String> headers = const {},
  }) =>
      _request('GET', url, headers, null);

  static Future<ImportHttpResponse> post(
    String url, {
    Map<String, String> headers = const {},
    List<int>? body,
  }) =>
      _request('POST', url, headers, body);

  static Future<ImportHttpResponse> _request(
    String method,
    String url,
    Map<String, String> headers,
    List<int>? body,
  ) async {
    final client = HttpClient();
    client.connectionTimeout = _timeout;
    client.autoUncompress = true;
    try {
      final req = await client.openUrl(method, Uri.parse(url));
      // 禁止跟随重定向，微信轮询依赖原始响应体
      req.followRedirects = false;
      headers.forEach(req.headers.set);
      if (body != null) {
        req.contentLength = body.length;
        req.add(body);
      }
      final res = await req.close().timeout(_timeout);
      final bytes = await res.fold<List<int>>(
        <int>[],
        (prev, chunk) => prev..addAll(chunk),
      );
      return ImportHttpResponse(res.statusCode, bytes);
    } finally {
      client.close(force: true);
    }
  }
}

class ImportHttpResponse {
  ImportHttpResponse(this.status, this.body);
  final int status;
  final List<int> body;

  String text() => utf8.decode(body, allowMalformed: true);
}
