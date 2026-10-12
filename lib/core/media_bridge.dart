import 'dart:convert';
import 'dart:io';

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

  /// 选图：返回不含 data: 前缀的 base64 列表（H5 Platform 期望 `base64s`）。
  static Future<Map<String, dynamic>> chooseImage({
    List<num>? imageSize,
  }) async {
    try {
      final maxW = (imageSize != null && imageSize.isNotEmpty)
          ? imageSize[0].toDouble()
          : 1024.0;
      final maxH = (imageSize != null && imageSize.length > 1)
          ? imageSize[1].toDouble()
          : maxW;
      // 游戏常传 [512,98]：第二维过扁时按正方形边长处理，避免压成细条
      final useH =
          (maxH >= 64 && maxH >= maxW * 0.35) ? maxH : maxW;

      AppLog.i('media', 'chooseImage open picker max=${maxW.toInt()}x${useH.toInt()}');
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: maxW.clamp(64, 4096),
        maxHeight: useH.clamp(64, 4096),
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
      final b64 = base64Encode(bytes);
      AppLog.i('media', 'chooseImage ok bytes=${bytes.length}');
      return {
        'errCode': 0,
        'errMsg': 'chooseImage:ok',
        'base64s': <String>[b64],
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
