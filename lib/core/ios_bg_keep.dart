import 'dart:io';

import 'package:flutter/services.dart';

import 'app_log.dart';

/// iOS：为「游戏内切后台」申请短时后台执行，降低 WebSocket 立刻被挂起的概率。
/// 系统通常只给约 30 秒，无法保证长时间挂机；回前台仍会做 onShow/重连。
class IosBgKeep {
  IosBgKeep._();

  static const _channel = MethodChannel('xyzw/background');
  static var _active = false;

  static Future<void> begin() async {
    if (!Platform.isIOS || _active) return;
    try {
      await _channel.invokeMethod<void>('begin');
      _active = true;
      AppLog.diag('lifecycle', {'event': 'bg_task', 'action': 'begin'});
    } catch (e) {
      AppLog.w('lifecycle', 'bg_task begin 失败: $e');
    }
  }

  static Future<void> end() async {
    if (!Platform.isIOS || !_active) return;
    try {
      await _channel.invokeMethod<void>('end');
      AppLog.diag('lifecycle', {'event': 'bg_task', 'action': 'end'});
    } catch (e) {
      AppLog.w('lifecycle', 'bg_task end 失败: $e');
    } finally {
      _active = false;
    }
  }
}
