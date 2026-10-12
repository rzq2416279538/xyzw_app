import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'app_log.dart';

/// 游戏内 HSDK.chooseImage / HSDK.saveImage 的原生实现（对照拟沧澜相册能力）。
class MediaBridge {
  MediaBridge._();

  static final _picker = ImagePicker();
  static const _native = MethodChannel('xyzw/media');

  /// 选图：返回带 `data:image/...;base64,` 前缀的列表。
  ///
  /// 换头像确认框 `ChangeHeadImgConfirmDialog` 需要 **两张图**：
  /// `base64s[0]` / `base64s[1]`，点击确定会对两者做 `.replace`；
  /// 游戏常传 `imageSize=[512,98]` 表示两个边长。
  static Future<Map<String, dynamic>> chooseImage({
    List<num>? imageSize,
  }) async {
    try {
      final sizes = <int>[];
      if (imageSize != null && imageSize.isNotEmpty) {
        for (final s in imageSize) {
          final n = s.toInt();
          if (n > 0) sizes.add(n.clamp(32, 4096));
        }
      }
      if (sizes.isEmpty) {
        sizes.add(512);
        sizes.add(98);
      } else if (sizes.length == 1) {
        // 确认框仍读 [1]，单尺寸时补一张同图避免 n.replace 崩溃
        sizes.add(sizes.first);
      }

      final pickMax = sizes.reduce((a, b) => a > b ? a : b).toDouble();
      AppLog.i(
        'media',
        'chooseImage open picker max=${pickMax.toInt()} sizes=$sizes',
      );
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: pickMax.clamp(64, 4096),
        maxHeight: pickMax.clamp(64, 4096),
        imageQuality: 92,
        requestFullMetadata: false,
      );
      if (file == null) {
        AppLog.i('media', 'chooseImage 用户取消');
        return {
          'errCode': 1,
          'errMsg': 'cancel',
          'base64s': <String>[],
        };
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        return {
          'errCode': -1,
          'errMsg': 'empty',
          'base64s': <String>[],
        };
      }

      final base64s = <String>[];
      for (final side in sizes) {
        base64s.add(await _toDataUrl(bytes, maxSide: side));
      }
      AppLog.i(
        'media',
        'chooseImage ok bytes=${bytes.length} base64s=${base64s.length}',
      );
      return {
        'errCode': 0,
        'errMsg': 'chooseImage:ok',
        'base64s': base64s,
      };
    } catch (e) {
      AppLog.e('media', 'chooseImage 失败: $e');
      return {
        'errCode': -1,
        'errMsg': e.toString(),
        'base64s': <String>[],
      };
    }
  }

  /// 按最长边缩放后输出 dataURL（PNG）。
  static Future<String> _toDataUrl(Uint8List bytes, {required int maxSide}) async {
    try {
      final codec0 = await ui.instantiateImageCodec(bytes);
      final frame0 = await codec0.getNextFrame();
      final src = frame0.image;
      final w = src.width;
      final h = src.height;
      src.dispose();

      var tw = w;
      var th = h;
      if (w > maxSide || h > maxSide) {
        if (w >= h) {
          tw = maxSide;
          th = (h * maxSide / w).round().clamp(1, maxSide);
        } else {
          th = maxSide;
          tw = (w * maxSide / h).round().clamp(1, maxSide);
        }
      }

      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: tw,
        targetHeight: th,
      );
      final frame = await codec.getNextFrame();
      final bd = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      if (bd == null) {
        return 'data:image/jpeg;base64,${base64Encode(bytes)}';
      }
      return 'data:image/png;base64,${base64Encode(bd.buffer.asUint8List())}';
    } catch (e) {
      AppLog.w('media', 'resize/$maxSide 失败，回退原图: $e');
      final isJpeg = bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8;
      final mime = isJpeg ? 'image/jpeg' : 'image/png';
      return 'data:$mime;base64,${base64Encode(bytes)}';
    }
  }

  /// 保存 base64 / dataURL 到系统相册。
  static Future<Map<String, dynamic>> saveImage(String base64OrDataUrl) async {
    try {
      var raw = base64OrDataUrl.trim();
      if (raw.startsWith('data:')) {
        final idx = raw.indexOf('base64,');
        if (idx >= 0) raw = raw.substring(idx + 7);
      }
      raw = raw.replaceAll(RegExp(r'\s'), '');
      if (raw.isEmpty) {
        return {'errCode': -1, 'errMsg': 'empty base64'};
      }
      final bytes = base64Decode(raw);
      if (bytes.isEmpty) {
        return {'errCode': -1, 'errMsg': 'decode empty'};
      }

      // iOS：优先走原生 PHPhotoLibrary（自签/gal 偶发写不到「最近项目」）
      if (Platform.isIOS) {
        try {
          final ok = await _native.invokeMethod<bool>('saveImageBase64', {
            'base64': raw,
          });
          if (ok == true) {
            AppLog.i('media', 'saveImage native ok bytes=${bytes.length}');
            return {'errCode': 0, 'errMsg': 'saveImage:native'};
          }
          AppLog.w('media', 'saveImage native returned $ok，改试 gal');
        } catch (e) {
          AppLog.w('media', 'saveImage native 失败，改试 gal: $e');
        }
      }

      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        final ok = await Gal.requestAccess();
        if (!ok) {
          AppLog.w('media', 'saveImage 无相册权限');
          return {'errCode': -2, 'errMsg': 'no album permission'};
        }
      }

      final name = 'xyzw_${DateTime.now().millisecondsSinceEpoch}';
      try {
        await Gal.putImageBytes(bytes, name: name);
      } catch (e1) {
        AppLog.w('media', 'putImageBytes 失败，改走文件: $e1');
        final dir = await getTemporaryDirectory();
        final isJpeg =
            bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8;
        final path =
            '${dir.path}${Platform.pathSeparator}$name.${isJpeg ? 'jpg' : 'png'}';
        final file = File(path);
        await file.writeAsBytes(bytes, flush: true);
        await Gal.putImage(path);
        try {
          await file.delete();
        } catch (_) {}
      }
      AppLog.i('media', 'saveImage gal ok bytes=${bytes.length}');
      return {'errCode': 0, 'errMsg': 'saveImage:ok'};
    } catch (e) {
      AppLog.e('media', 'saveImage 失败: $e');
      return {'errCode': -1, 'errMsg': e.toString()};
    }
  }

  /// 供 WebView 回调：把结果塞回 JS。
  static String jsResolve(String reqId, Map<String, dynamic> result) {
    final payload = jsonEncode(result);
    return "window.__xyzwMediaDone && window.__xyzwMediaDone(${jsonEncode(reqId)}, $payload);";
  }
}
