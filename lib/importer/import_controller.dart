import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/app_log.dart';
import 'bin_builder.dart';
import 'wx_login.dart';
import 'xy_endpoints.dart';

enum ImportStage { idle, qrWaiting, loggingIn, querying, picking, done }

/// 对照 naiwa-release `importer/ImportViewModel.kt`
class ImportController extends ChangeNotifier {
  ImportStage stage = ImportStage.idle;
  String message = '';
  bool busy = false;

  Uint8List? qrBytes;
  String qrHint = '';

  String mobile = '';
  String smsCode = '';
  int countdown = 0;

  final roles = <RoleInfo>[];
  final selected = <int>{};

  AccountCredential? _credential;
  Timer? _pollTimer;
  Timer? _countdownTimer;
  bool _pollPending = false;
  String? _pollUuid;
  DateTime? _pollDeadline;

  void reset() {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    stage = ImportStage.idle;
    message = '';
    qrBytes = null;
    qrHint = '';
    roles.clear();
    selected.clear();
    _credential = null;
    busy = false;
    _pollPending = false;
    _pollUuid = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> startQrLogin() async {
    _pollTimer?.cancel();
    busy = true;
    message = '';
    qrBytes = null;
    notifyListeners();
    try {
      final ticket = await WxLogin.createQrCode();
      qrBytes = Uint8List.fromList(ticket.imageBytes);
      stage = ImportStage.qrWaiting;
      qrHint = '请用微信扫码';
      busy = false;
      notifyListeners();
      _startPoll(ticket.uuid);
    } catch (e) {
      busy = false;
      message = e.toString();
      notifyListeners();
    }
  }

  void _startPoll(String uuid) {
    _pollUuid = uuid;
    _pollDeadline = DateTime.now().add(const Duration(minutes: 5));
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollOnce());
  }

  Future<void> _pollOnce() async {
    final uuid = _pollUuid;
    if (uuid == null || _pollPending) return;
    if (_pollDeadline != null && DateTime.now().isAfter(_pollDeadline!)) {
      _pollTimer?.cancel();
      qrHint = '二维码已超时，请重新获取';
      stage = ImportStage.idle;
      qrBytes = null;
      notifyListeners();
      return;
    }
    _pollPending = true;
    try {
      final result = await WxLogin.pollQrCode(uuid);
      switch (result.state) {
        case WxScanState.confirmed:
          _pollTimer?.cancel();
          qrHint = '授权成功，正在登录';
          notifyListeners();
          await _loginWith(() => WxLogin.loginByWxCode(result.code!));
          break;
        case WxScanState.expired:
        case WxScanState.rejected:
          _pollTimer?.cancel();
          qrHint = '${result.state.label}，请重新获取';
          stage = ImportStage.idle;
          qrBytes = null;
          notifyListeners();
          break;
        default:
          qrHint = result.state.label;
          notifyListeners();
      }
    } catch (e) {
      qrHint = '轮询出错: $e';
      notifyListeners();
    } finally {
      _pollPending = false;
    }
  }

  Future<void> sendSms() async {
    final m = mobile.trim();
    if (!RegExp(r'^1[3-9]\d{9}$').hasMatch(m)) {
      message = '请输入有效的手机号';
      notifyListeners();
      return;
    }
    busy = true;
    message = '';
    notifyListeners();
    try {
      await WxLogin.sendSmsCode(m);
      message = '验证码已发送，请注意接收';
      _startCountdown();
    } catch (e) {
      message = e.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    countdown = 120;
    notifyListeners();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      countdown -= 1;
      if (countdown <= 0) {
        t.cancel();
        countdown = 0;
      }
      notifyListeners();
    });
  }

  Future<void> loginBySms() async {
    final c = smsCode.trim();
    if (c.length < 4) {
      message = '请输入有效的验证码';
      notifyListeners();
      return;
    }
    await _loginWith(() => WxLogin.loginBySms(mobile.trim(), c));
  }

  Future<void> _loginWith(Future<LoginResult> Function() block) async {
    busy = true;
    stage = ImportStage.loggingIn;
    message = '';
    notifyListeners();
    try {
      final login = await block();
      stage = ImportStage.querying;
      message = '登录成功，正在查询区服';
      notifyListeners();
      final cred = BinBuilder.credentialFromCombUser(
        login.combUser,
        login.timestamp,
        login.sign,
      );
      _credential = cred;
      final list = await BinBuilder.queryRoles(cred);
      roles
        ..clear()
        ..addAll(list);
      selected.clear();
      stage = ImportStage.picking;
      message = '共找到 ${list.length} 个角色，请选择要导入的';
    } catch (e) {
      stage = ImportStage.idle;
      message = e.toString();
      AppLog.e('import', message);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> queryFromBin(List<int> binBytes) async {
    busy = true;
    message = '';
    stage = ImportStage.querying;
    notifyListeners();
    try {
      final cred = BinBuilder.parseCredential(binBytes);
      _credential = cred;
      final list = await BinBuilder.queryRoles(cred);
      roles
        ..clear()
        ..addAll(list);
      selected.clear();
      stage = ImportStage.picking;
      message = '共找到 ${list.length} 个角色，请选择要导入的';
    } catch (e) {
      stage = ImportStage.idle;
      final raw = e.toString();
      AppLog.e('import', raw);
      if (raw.contains('解码') || raw.contains('缺少 info')) {
        message = '$raw\n该文件可能不是有效的 bin，或已损坏';
      } else if (raw.contains('凭据') || raw.contains('角色列表')) {
        message = '$raw\n登录态可能已过期，请改用扫码或手机号导入';
      } else {
        message = raw;
      }
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void toggle(int index) {
    if (selected.contains(index)) {
      selected.remove(index);
    } else {
      selected.add(index);
    }
    notifyListeners();
  }

  void selectAll(bool on) {
    selected.clear();
    if (on) selected.addAll(List.generate(roles.length, (i) => i));
    notifyListeners();
  }

  List<GeneratedBin> buildSelected() {
    final cred = _credential;
    if (cred == null) return const [];
    final picked = selected.toList()..sort();
    final roleList = picked.map((i) => roles[i]).toList();
    return BinBuilder.buildBins(cred, roleList);
  }
}
