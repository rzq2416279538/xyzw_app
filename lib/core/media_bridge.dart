import 'dart:convert';
import 'dart:io';

import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'app_log.dart';

/// 游戏内 HSDK.chooseImage / HSDK.saveImage 的原生实现（对照拟沧澜相册能力）。
class MediaBridge {
  MediaBridge._();

  static final _picker = ImagePicker();

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
      // 98 这类小数当高度不合理时，按宽度等比
      final useH = maxH >= 64 ? maxH : maxW;

      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: maxW.clamp(64, 4096),
        maxHeight: useH.clamp(64, 4096),
        imageQuality: 92,
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

      final hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasAccess) {
        final ok = await Gal.requestAccess(toAlbum: true);
        if (!ok) {
          AppLog.w('media', 'saveImage 无相册权限');
          return {'errCode': -2, 'errMsg': 'no album permission'};
        }
      }

      // gal 在部分机型对 bytes 扩展名敏感，先落临时文件再入库更稳
      final dir = await getTemporaryDirectory();
      final isJpeg = bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8;
      final path =
          '${dir.path}${Platform.pathSeparator}xyzw_save_${DateTime.now().millisecondsSinceEpoch}.${isJpeg ? 'jpg' : 'png'}';
      final file = File(path);
      await file.writeAsBytes(bytes, flush: true);
      await Gal.putImage(path);
      try {
        await file.delete();
      } catch (_) {}
      AppLog.i('media', 'saveImage ok bytes=${bytes.length}');
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
