import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// 对照 naiwa-release `bon/*`：BON + LZ4 帧 + XyCrypto。

class BonException implements Exception {
  BonException(this.message);
  final String message;
  @override
  String toString() => 'BonException: $message';
}

class BonDate {
  BonDate(this.millis);
  final int millis;
}

abstract final class _Tag {
  static const null_ = 0;
  static const int32 = 1;
  static const int64 = 2;
  static const float32 = 3;
  static const float64 = 4;
  static const string = 5;
  static const boolean = 6;
  static const binary = 7;
  static const object = 8;
  static const array = 9;
  static const datetime = 10;
  static const stringRef = 99;
}

class _DataReader {
  _DataReader(this.data);
  final List<int> data;
  var position = 0;

  void _need(int n) {
    if (position + n > data.length) {
      throw BonException('read eof at $position need $n');
    }
  }

  int readUInt8() {
    _need(1);
    return data[position++] & 0xFF;
  }

  int readInt32() {
    _need(4);
    final v = (data[position] & 0xFF) |
        ((data[position + 1] & 0xFF) << 8) |
        ((data[position + 2] & 0xFF) << 16) |
        ((data[position + 3] & 0xFF) << 24);
    position += 4;
    return v;
  }

  int readInt64() {
    _need(8);
    var v = 0;
    for (var i = 7; i >= 0; i--) {
      v = (v << 8) | (data[position + i] & 0xFF);
    }
    position += 8;
    return v;
  }

  double readFloat64() {
    final bd = ByteData(8);
    for (var i = 0; i < 8; i++) {
      bd.setUint8(i, data[position + i] & 0xFF);
    }
    position += 8;
    return bd.getFloat64(0, Endian.little);
  }

  int read7BitInt() {
    var value = 0;
    var shift = 0;
    var count = 0;
    while (true) {
      if (++count == 5) throw BonException('Format_Bad7BitInt32');
      final b = readUInt8();
      value |= (b & 0x7F) << shift;
      if ((b & 0x80) == 0) break;
      shift += 7;
    }
    return value;
  }

  String readUtf() {
    final len = read7BitInt();
    _need(len);
    final s = utf8.decode(data.sublist(position, position + len));
    position += len;
    return s;
  }

  Uint8List readBytes(int len) {
    _need(len);
    final out = Uint8List.fromList(data.sublist(position, position + len));
    position += len;
    return out;
  }
}

class _DataWriter {
  var _buf = Uint8List(256);
  var _size = 0;

  void _ensure(int n) {
    if (_size + n <= _buf.length) return;
    var cap = _buf.length;
    while (cap < _size + n) {
      cap <<= 1;
    }
    final next = Uint8List(cap);
    next.setRange(0, _size, _buf);
    _buf = next;
  }

  void writeUInt8(int v) {
    _ensure(1);
    _buf[_size++] = v & 0xFF;
  }

  void writeInt32(int v) {
    _ensure(4);
    _buf[_size++] = v & 0xFF;
    _buf[_size++] = (v >> 8) & 0xFF;
    _buf[_size++] = (v >> 16) & 0xFF;
    _buf[_size++] = (v >> 24) & 0xFF;
  }

  void writeInt64(int v) {
    _ensure(8);
    for (var i = 0; i < 8; i++) {
      _buf[_size++] = (v >> (i * 8)) & 0xFF;
    }
  }

  void writeFloat64(double v) {
    final bd = ByteData(8)..setFloat64(0, v, Endian.little);
    writeBytes(bd.buffer.asUint8List());
  }

  void write7BitInt(int value) {
    var v = value;
    while (true) {
      final b = v & 0x7F;
      v >>= 7;
      if (v != 0) {
        writeUInt8(b | 0x80);
      } else {
        writeUInt8(b);
        break;
      }
    }
  }

  void writeUtf(String s) {
    final bytes = utf8.encode(s);
    write7BitInt(bytes.length);
    writeBytes(bytes);
  }

  void writeBytes(List<int> b) {
    _ensure(b.length);
    _buf.setRange(_size, _size + b.length, b);
    _size += b.length;
  }

  Uint8List toBytes() => Uint8List.fromList(_buf.sublist(0, _size));
}

class BonDecoder {
  late _DataReader _reader;
  final _strPool = <String>[];

  dynamic decode(List<int> data) {
    _reader = _DataReader(data);
    _strPool.clear();
    return _read();
  }

  dynamic _read() {
    switch (_reader.readUInt8()) {
      case _Tag.null_:
        return null;
      case _Tag.int32:
        return _reader.readInt32();
      case _Tag.int64:
        return _reader.readInt64();
      case _Tag.float32:
        final bd = ByteData(4);
        for (var i = 0; i < 4; i++) {
          bd.setUint8(i, _reader.readUInt8());
        }
        return bd.getFloat32(0, Endian.little);
      case _Tag.float64:
        return _reader.readFloat64();
      case _Tag.string:
        final s = _reader.readUtf();
        _strPool.add(s);
        return s;
      case _Tag.boolean:
        return _reader.readUInt8() == 1;
      case _Tag.binary:
        return _reader.readBytes(_reader.read7BitInt());
      case _Tag.object:
        final n = _reader.read7BitInt();
        final map = <String, dynamic>{};
        for (var i = 0; i < n; i++) {
          final k = _read();
          map['${k ?? 'null'}'] = _read();
        }
        return map;
      case _Tag.array:
        final n = _reader.read7BitInt();
        return List.generate(n, (_) => _read());
      case _Tag.datetime:
        return BonDate(_reader.readInt64());
      case _Tag.stringRef:
        final i = _reader.read7BitInt();
        return (i >= 0 && i < _strPool.length) ? _strPool[i] : '';
      default:
        throw BonException('BonDecoder unknown type');
    }
  }
}

class BonEncoder {
  late _DataWriter _writer;
  final _strIndex = <String, int>{};

  Uint8List encode(dynamic value) {
    _writer = _DataWriter();
    _strIndex.clear();
    _write(value);
    return _writer.toBytes();
  }

  void _write(dynamic value) {
    if (value == null) {
      _writer.writeUInt8(_Tag.null_);
      return;
    }
    if (value is bool) {
      _writer.writeUInt8(_Tag.boolean);
      _writer.writeUInt8(value ? 1 : 0);
      return;
    }
    if (value is String) {
      final existing = _strIndex[value];
      if (existing != null) {
        _writer.writeUInt8(_Tag.stringRef);
        _writer.write7BitInt(existing);
      } else {
        _writer.writeUInt8(_Tag.string);
        _writer.writeUtf(value);
        _strIndex[value] = _strIndex.length;
      }
      return;
    }
    if (value is int) {
      if (value >= -2147483648 && value <= 2147483647) {
        _writer.writeUInt8(_Tag.int32);
        _writer.writeInt32(value);
      } else {
        _writer.writeUInt8(_Tag.float64);
        _writer.writeFloat64(value.toDouble());
      }
      return;
    }
    if (value is double) {
      if (value == value.floorToDouble() &&
          !value.isInfinite &&
          value >= -2147483648 &&
          value <= 2147483647) {
        _writer.writeUInt8(_Tag.int32);
        _writer.writeInt32(value.toInt());
      } else {
        _writer.writeUInt8(_Tag.float64);
        _writer.writeFloat64(value);
      }
      return;
    }
    if (value is BonDate) {
      _writer.writeUInt8(_Tag.datetime);
      _writer.writeInt64(value.millis);
      return;
    }
    if (value is Uint8List) {
      _writer.writeUInt8(_Tag.binary);
      _writer.write7BitInt(value.length);
      _writer.writeBytes(value);
      return;
    }
    if (value is List) {
      _writer.writeUInt8(_Tag.array);
      _writer.write7BitInt(value.length);
      for (final e in value) {
        _write(e);
      }
      return;
    }
    if (value is Map) {
      _writer.writeUInt8(_Tag.object);
      _writer.write7BitInt(value.length);
      value.forEach((k, v) {
        _write(k?.toString());
        _write(v);
      });
      return;
    }
    _writer.writeUInt8(_Tag.null_);
  }
}

abstract final class Lz4 {
  static const _magic = 0x184D2204;
  static const _flg = 0x40;
  static const _bd = 0x70;

  static Uint8List frameUncompressed(List<int> data) {
    final out = Uint8List(11 + data.length + 4);
    _writeLe32(out, 0, _magic);
    out[4] = _flg;
    out[5] = _bd;
    out[6] = (_xxh32([_flg, _bd]) >> 8) & 0xFF;
    _writeLe32(out, 7, data.length | 0x80000000);
    out.setRange(11, 11 + data.length, data);
    _writeLe32(out, 11 + data.length, 0);
    return out;
  }

  static void _writeLe32(Uint8List buf, int at, int v) {
    buf[at] = v & 0xFF;
    buf[at + 1] = (v >> 8) & 0xFF;
    buf[at + 2] = (v >> 16) & 0xFF;
    buf[at + 3] = (v >> 24) & 0xFF;
  }

  static const _p1 = -1640531535;
  static const _p2 = -2048144777;
  static const _p3 = -1028477379;
  static const _p4 = 668265263;
  static const _p5 = 374761393;

  static int _rotl(int x, int r) => ((x << r) | ((x & 0xFFFFFFFF) >> (32 - r))) & 0xFFFFFFFF;

  static int _xxh32(List<int> input, [int seed = 0]) {
    var h = (seed + _p5 + input.length) & 0xFFFFFFFF;
    var i = 0;
    while (i + 4 <= input.length) {
      final k = (input[i] & 0xFF) |
          ((input[i + 1] & 0xFF) << 8) |
          ((input[i + 2] & 0xFF) << 16) |
          ((input[i + 3] & 0xFF) << 24);
      h = (h + ((k * _p3) & 0xFFFFFFFF)) & 0xFFFFFFFF;
      h = (_rotl(h, 17) * _p4) & 0xFFFFFFFF;
      i += 4;
    }
    while (i < input.length) {
      h = (h + (((input[i] & 0xFF) * _p5) & 0xFFFFFFFF)) & 0xFFFFFFFF;
      h = (_rotl(h, 11) * _p1) & 0xFFFFFFFF;
      i++;
    }
    h ^= h >> 15;
    h = (h * _p2) & 0xFFFFFFFF;
    h ^= h >> 13;
    h = (h * _p3) & 0xFFFFFFFF;
    h ^= h >> 16;
    return h;
  }

  static Uint8List decompressFrame(List<int> input) {
    if (input.length < 7) throw BonException('LZ4 帧过短');
    final magic = (input[0] & 0xFF) |
        ((input[1] & 0xFF) << 8) |
        ((input[2] & 0xFF) << 16) |
        ((input[3] & 0xFF) << 24);
    if (magic != _magic) throw BonException('LZ4 magic 不匹配');

    final flg = input[4] & 0xFF;
    final blockChecksum = ((flg >> 4) & 1) == 1;
    final contentSize = ((flg >> 3) & 1) == 1;
    final contentChecksum = ((flg >> 2) & 1) == 1;
    final dictId = (flg & 1) == 1;

    var p = 7;
    if (contentSize) p += 8;
    if (dictId) p += 4;

    final parts = <Uint8List>[];
    var total = 0;
    while (p + 4 <= input.length) {
      var blockSize = (input[p] & 0xFF) |
          ((input[p + 1] & 0xFF) << 8) |
          ((input[p + 2] & 0xFF) << 16) |
          ((input[p + 3] & 0xFF) << 24);
      p += 4;
      if (blockSize == 0) break;
      final uncompressed = (blockSize & 0x80000000) != 0;
      blockSize &= 0x7FFFFFFF;
      if (blockSize < 0 || p + blockSize > input.length) {
        throw BonException('LZ4 块越界');
      }
      final block = uncompressed
          ? Uint8List.fromList(input.sublist(p, p + blockSize))
          : _decompressBlock(input, p, blockSize);
      parts.add(block);
      total += block.length;
      p += blockSize;
      if (blockChecksum) p += 4;
    }
    if (contentChecksum) p += 4;

    final result = Uint8List(total);
    var o = 0;
    for (final b in parts) {
      result.setRange(o, o + b.length, b);
      o += b.length;
    }
    return result;
  }

  static Uint8List _decompressBlock(List<int> src, int offset, int length) {
    var ip = offset;
    final end = offset + length;
    var dst = Uint8List(length * 4 + 64);
    var op = 0;

    void grow(int need) {
      if (op + need <= dst.length) return;
      var cap = dst.length;
      while (cap < op + need) {
        cap <<= 1;
      }
      final n = Uint8List(cap);
      n.setRange(0, op, dst);
      dst = n;
    }

    while (ip < end) {
      final token = src[ip++] & 0xFF;
      var litLen = token >> 4;
      if (litLen == 15) {
        while (ip < end) {
          final b = src[ip++] & 0xFF;
          litLen += b;
          if (b != 255) break;
        }
      }
      if (litLen > 0) {
        if (ip + litLen > end) throw BonException('LZ4 literal 越界');
        grow(litLen);
        dst.setRange(op, op + litLen, src, ip);
        ip += litLen;
        op += litLen;
      }
      if (ip >= end) break;
      if (ip + 2 > end) throw BonException('LZ4 offset 截断');
      final matchOffset = (src[ip] & 0xFF) | ((src[ip + 1] & 0xFF) << 8);
      ip += 2;
      if (matchOffset == 0) throw BonException('LZ4 offset 为 0');
      var matchLen = token & 0x0F;
      if (matchLen == 15) {
        while (ip < end) {
          final b = src[ip++] & 0xFF;
          matchLen += b;
          if (b != 255) break;
        }
      }
      matchLen += 4;
      var mp = op - matchOffset;
      if (mp < 0) throw BonException('LZ4 match 偏移越界');
      grow(matchLen);
      for (var i = 0; i < matchLen; i++) {
        dst[op++] = dst[mp++];
      }
    }
    return Uint8List.fromList(dst.sublist(0, op));
  }
}

enum XyCryptoKind { x, lx, none }

abstract final class XyCrypto {
  static final _rng = Random.secure();

  static XyCryptoKind detect(List<int> data) {
    if (data.length < 2) return XyCryptoKind.none;
    if (data[0] == 0x70 && data[1] == 0x78) return XyCryptoKind.x;
    if (data[0] == 0x70 && data[1] == 0x6C) return XyCryptoKind.lx;
    return XyCryptoKind.none;
  }

  static int _extractKey(List<int> d) {
    final b2 = d[2];
    final b3 = d[3];
    return (((b2 >> 6) & 1) << 7) |
        (((b2 >> 4) & 1) << 6) |
        (((b2 >> 2) & 1) << 5) |
        (((b2 >> 0) & 1) << 4) |
        (((b3 >> 6) & 1) << 3) |
        (((b3 >> 4) & 1) << 2) |
        (((b3 >> 2) & 1) << 1) |
        (((b3 >> 0) & 1) << 0);
  }

  static Uint8List decryptX(List<int> data) {
    if (data.length < 4) return Uint8List.fromList(data);
    final buf = List<int>.from(data);
    final key = _extractKey(buf);
    for (var i = buf.length - 1; i >= 4; i--) {
      buf[i] = buf[i] ^ key;
    }
    return Uint8List.fromList(buf.sublist(4));
  }

  static Uint8List encryptX(List<int> data) {
    final out = Uint8List(data.length + 4);
    final rid = _rng.nextInt(0x7FFFFFFF);
    out[0] = rid & 0xFF;
    out[1] = (rid >> 8) & 0xFF;
    out[2] = (rid >> 16) & 0xFF;
    out[3] = (rid >> 24) & 0xFF;
    out.setRange(4, out.length, data);
    final key = 2 + _rng.nextInt(248);
    for (var i = out.length - 1; i >= 0; i--) {
      out[i] = out[i] ^ key;
    }
    out[0] = 0x70;
    out[1] = 0x78;
    out[2] = ((0xAA & out[2]) |
            (((key >> 7) & 1) << 6) |
            (((key >> 6) & 1) << 4) |
            (((key >> 5) & 1) << 2) |
            (((key >> 4) & 1) << 0)) &
        0xFF;
    out[3] = ((0xAA & out[3]) |
            (((key >> 3) & 1) << 6) |
            (((key >> 2) & 1) << 4) |
            (((key >> 1) & 1) << 2) |
            (((key >> 0) & 1) << 0)) &
        0xFF;
    return out;
  }

  static Uint8List decryptLx(List<int> data) {
    if (data.length < 4) return Uint8List.fromList(data);
    final buf = List<int>.from(data);
    final key = _extractKey(buf);
    final n = buf.length < 100 ? buf.length : 100;
    for (var i = 2; i < n; i++) {
      buf[i] = buf[i] ^ key;
    }
    buf[0] = 0x04;
    buf[1] = 0x22;
    buf[2] = 0x4D;
    buf[3] = 0x18;
    return Lz4.decompressFrame(buf);
  }

  static Uint8List encryptLx(List<int> data) {
    final frame = Lz4.frameUncompressed(data);
    final key = 2 + _rng.nextInt(248);
    final n = frame.length < 100 ? frame.length : 100;
    for (var i = 2; i < n; i++) {
      frame[i] = frame[i] ^ key;
    }
    frame[0] = 0x70;
    frame[1] = 0x6C;
    frame[2] = ((0xAA & frame[2]) |
            (((key >> 7) & 1) << 6) |
            (((key >> 6) & 1) << 4) |
            (((key >> 5) & 1) << 2) |
            (((key >> 4) & 1) << 0)) &
        0xFF;
    frame[3] = ((0xAA & frame[3]) |
            (((key >> 3) & 1) << 6) |
            (((key >> 2) & 1) << 4) |
            (((key >> 1) & 1) << 2) |
            (((key >> 0) & 1) << 0)) &
        0xFF;
    return frame;
  }

  static Uint8List decrypt(List<int> data) {
    switch (detect(data)) {
      case XyCryptoKind.x:
        return decryptX(data);
      case XyCryptoKind.lx:
        return decryptLx(data);
      case XyCryptoKind.none:
        return Uint8List.fromList(data);
    }
  }
}
