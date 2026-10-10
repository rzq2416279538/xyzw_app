import 'dart:convert';

/// 对照 naiwa-release `importer/CodeBookCrypto.kt`
class CodeBookRule {
  CodeBookRule({
    required this.codeBook,
    required this.swapTimes,
    required this.keySkip,
    required this.keyOffset,
  });

  final String codeBook;
  final int swapTimes;
  final int keySkip;
  final int keyOffset;
}

abstract final class CodeBookCrypto {
  static String transCode(String str, int swapTimes) {
    if (swapTimes <= 0) return str;
    if (str.length % 2 != 0) return str;
    final half = str.length ~/ 2;
    final right = str.substring(half);
    final left = str.substring(0, half);
    return transCode(right, swapTimes - 1) + transCode(left, swapTimes - 1);
  }

  static String getKey(String codeBook, int keySkip) {
    if (codeBook.isEmpty || keySkip <= 0) return codeBook;
    final count = codeBook.length ~/ keySkip;
    final sb = StringBuffer();
    for (var i = 0; i < count; i++) {
      sb.write(codeBook[i * keySkip]);
    }
    return sb.toString();
  }

  static List<int> _xor(List<int> data, List<int> key, int startOffset) {
    if (data.isEmpty || key.isEmpty) return List<int>.from(data);
    var offset = startOffset;
    final out = List<int>.filled(data.length, 0);
    for (var i = 0; i < data.length; i++) {
      if (offset >= key.length) offset = 0;
      out[i] = data[i] ^ key[offset];
      offset++;
    }
    return out;
  }

  static String _keyStream(CodeBookRule rule) =>
      getKey(transCode(rule.codeBook, rule.swapTimes), rule.keySkip);

  static String encrypt(String json, CodeBookRule rule) {
    final inner = base64.encode(utf8.encode(json));
    final key = _keyStream(rule);
    final enc = _xor(
      latin1.encode(inner),
      latin1.encode(key),
      key.length >> rule.keyOffset,
    );
    return base64.encode(enc);
  }

  static String decrypt(String body, CodeBookRule rule) {
    final key = _keyStream(rule);
    final inner = latin1.decode(
      _xor(
        base64.decode(body),
        latin1.encode(key),
        key.length >> rule.keyOffset,
      ),
    );
    return utf8.decode(base64.decode(inner));
  }
}
