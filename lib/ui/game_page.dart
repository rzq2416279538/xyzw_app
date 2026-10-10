import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../core/app_log.dart';
import '../core/game_prefs_store.dart';
import '../core/inject_scripts.dart';
import '../core/local_http_server.dart';
import '../core/renderer_status.dart';
import '../core/script_cache.dart';
import '../data/account.dart';
import '../data/account_store.dart';
import '../data/role_avatar_cache.dart';
import '../data/script_store.dart';
import 'app_theme.dart';
import 'ios_chrome.dart';
import 'net_avatar.dart';

/// 游戏壳：实色顶栏 + 多账号会话（已进入的账号切换不销毁 WebView）。
class GamePage extends StatefulWidget {
  const GamePage({
    super.key,
    required this.store,
    required this.scripts,
    required this.initialAccountId,
    required this.rendererDir,
    required this.status,
    required this.onBack,
    this.onRunningChanged,
    this.httpServer,
  });

  final AccountStore store;
  final ScriptStore scripts;
  final String initialAccountId;
  final Directory rendererDir;
  final RendererStatus status;
  final VoidCallback onBack;
  final ValueChanged<Set<String>>? onRunningChanged;
  final LocalHttpServer? httpServer;

  @override
  State<GamePage> createState() => GamePageState();
}

class _Session {
  _Session({required this.accountId, required this.controller});

  final String accountId;
  final WebViewController controller;
  bool loading = true;
  String? error;
}

class GamePageState extends State<GamePage> with WidgetsBindingObserver {
  LocalHttpServer? _server;
  var _ownsServer = false;
  String? _baseUrl;
  String? _bootError;
  late String _activeId;
  final Map<String, _Session> _sessions = {};
  final Set<String> _bootingIds = {};
  Future<void> _publishChain = Future<void>.value();
  var _scriptsReady = false;
  final Map<String, Timer> _readyTimers = {};
  final Map<String, Timer> _binKeepAlive = {};
  final Map<String, String> _binB64Cache = {};
  final Map<String, Future<void>> _injectChain = {};
  Timer? _sessionHeartbeat;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _activeId = widget.initialAccountId;
    widget.scripts.addListener(_onScripts);
    _armSessionHeartbeat();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
    _bootServerAndOpen(_activeId);
  }

  void _onScripts() {
    if (mounted) setState(() {});
    _publishScripts();
  }

  /// 把启用的脚本落到本地 HTTP 目录。页面请求 index 时会在游戏脚本前插入它们。
  Future<void> _publishScripts() {
    final run = _publishChain.then((_) => _publishScriptsOnce());
    _publishChain = run.catchError((Object _) {});
    return run;
  }

  Future<void> _publishScriptsOnce() async {
    try {
      final shim = File(
        '${widget.rendererDir.path}${Platform.pathSeparator}xyzw-gm-shim.js',
      );
      if (!await shim.exists() || await shim.length() != InjectScripts.gmShim.length) {
        await shim.writeAsString(InjectScripts.gmShim, flush: false);
      }
      final enabled = widget.scripts.enabledScripts;
      final published = await ScriptCache.publish(
        root: widget.rendererDir,
        scripts: enabled,
        sourceFile: widget.scripts.codeFile,
      );
      if (published.isEmpty) {
        AppLog.i('script', '没有启用的脚本（enabled=${enabled.length}）');
      } else {
        final detail = published
            .map((e) => '${e.name} ${e.bytes}B')
            .join('、');
        AppLog.i(
          'script',
          '已写入页面脚本 ${published.length}/${enabled.length}：$detail',
        );
      }
      _scriptsReady = true;
    } catch (e) {
      AppLog.e('script', '发布脚本失败 $e');
    }
  }

  Future<void> _bootServerAndOpen(String accountId) async {
    if (!widget.status.isReady) {
      setState(() => _bootError = widget.status.describe());
      return;
    }

    if (_server == null) {
      final existing = widget.httpServer;
      if (existing != null && existing.port != 0) {
        _server = existing;
        _ownsServer = false;
        _baseUrl = existing.baseUrl;
      } else {
        final server = LocalHttpServer(widget.rendererDir);
        final url = await server.start();
        if (url == null) {
          if (!mounted) return;
          setState(() => _bootError = '本地 HTTP 服务器启动失败');
          return;
        }
        _server = server;
        _ownsServer = true;
        _baseUrl = url;
      }
    }

    await _ensureSession(accountId);
    _emitRunning();
  }

  void _emitRunning() {
    widget.onRunningChanged?.call(Set<String>.from(_sessions.keys));
  }

  Future<void> openAccount(String accountId) => _bootServerAndOpen(accountId);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    AppLog.diag('lifecycle', {
      'event': 'app',
      'state': state.name,
      'activeId': _activeId,
      'sessions': _sessions.length,
      'ids': _sessions.keys.join(','),
    });
    if (state == AppLifecycleState.resumed) {
      // 回前台：只唤醒/探活，绝不自动 reload（避免比赛中切走再进整页重载）
      unawaited(_pingAllSessions('resume'));
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(_pingAllSessions('background'));
    }
  }

  void _armSessionHeartbeat() {
    _sessionHeartbeat?.cancel();
    // 非前台会话也定时探活，减轻 iOS 对后台 WKWebView 的冻结感
    _sessionHeartbeat = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted || _sessions.isEmpty) return;
      unawaited(_pingAllSessions('heartbeat'));
    });
  }

  Future<void> _pingAllSessions(String reason) async {
    for (final entry in _sessions.entries) {
      final id = entry.key;
      final c = entry.value.controller;
      try {
        await c.runJavaScript('''
(function(){
  try {
    if (window.cc && cc.game && typeof cc.game.resume === 'function') {
      try {
        if (typeof cc.game.isPaused === 'function' && cc.game.isPaused()) cc.game.resume();
      } catch (e0) { try { cc.game.resume(); } catch (e1) {} }
    }
    console.log('[咸强之王][keepalive] $reason id=$id vis='+(document.visibilityState||'')+
      ' hidden='+!!document.hidden+' paused='+(window.cc&&cc.game&&cc.game.isPaused&&cc.game.isPaused()));
  } catch (e) {}
})();
''');
      } catch (e) {
        AppLog.w('keepalive', 'session=$id reason=$reason ping失败: $e');
      }
    }
  }

  Future<void> closeAccount(String accountId) async {
    _readyTimers.remove(accountId)?.cancel();
    final s = _sessions.remove(accountId);
    if (s != null) {
      try {
        await s.controller.loadRequest(Uri.parse('about:blank'));
      } catch (_) {}
    }
    if (_activeId == accountId && _sessions.isNotEmpty) {
      _activeId = _sessions.keys.first;
    }
    if (mounted) setState(() {});
    _emitRunning();
    if (_sessions.isEmpty) widget.onBack();
  }

  Future<void> restartAccount(String accountId) async {
    if (_sessions.containsKey(accountId)) {
      final session = _sessions[accountId]!;
      // 先盖加载层再 reload，避免黑屏闪一下
      session.loading = true;
      if (mounted) setState(() => _activeId = accountId);
      await Future<void>.delayed(Duration.zero);
      await _stageBin(accountId);
      if (!_scriptsReady) await _publishScripts();
      _armReadyWatch(accountId);
      // reload 复用 HTTP 磁盘缓存；带新 t= 的 loadRequest 会逼整页重下
      await session.controller.reload();
      return;
    }
    await openAccount(accountId);
  }

  Future<void> _ensureSession(String accountId) async {
    if (_sessions.containsKey(accountId) || _bootingIds.contains(accountId)) {
      // 已有会话：只切 IndexedStack，绝不 reload
      AppLog.diag('game', {
        'event': 'switch_session',
        'accountId': accountId,
        'alive': _sessions.containsKey(accountId),
        'total': _sessions.length,
      });
      if (mounted) setState(() => _activeId = accountId);
      return;
    }
    final account = widget.store.byId(accountId);
    if (account == null || _baseUrl == null) return;

    _bootingIds.add(accountId);
    if (mounted) setState(() => _activeId = accountId);

    final sw = Stopwatch()..start();
    try {
      AppLog.diag('game', {
        'event': 'session_start',
        'accountId': accountId,
        'label': account.fileLabel,
        'baseUrl': _baseUrl,
        'platform': Platform.isIOS ? 'ios' : Platform.operatingSystem,
      });

      final controller = await _createController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setBackgroundColor(const Color(0xFFF2F2F7));

      if (controller.platform is AndroidWebViewController) {
        final android = controller.platform as AndroidWebViewController;
        AndroidWebViewController.enableDebugging(false);
        await android.setMediaPlaybackRequiresUserGesture(false);
        await android.setTextZoom(100);
        await android.setCustomWidgetCallbacks(
          onShowCustomWidget: (Widget widget, OnHideCustomWidgetCallback onHidden) {
            onHidden();
          },
          onHideCustomWidget: () {},
        );
      } else if (controller.platform is WebKitWebViewController) {
        final ios = controller.platform as WebKitWebViewController;
        await ios.setAllowsBackForwardNavigationGestures(false);
        await ios.setInspectable(kDebugMode);
      }

      await controller.addJavaScriptChannel(
        'XyzwBridge',
        onMessageReceived: (msg) => _onBridge(accountId, msg.message),
      );
      await controller.setOnConsoleMessage((m) {
        final text = m.message;
        final anomaly = text.contains('CLIENT_ANOMALY') ||
            text.contains('客户端数据异常') ||
            text.contains('官方最新客户端') ||
            text.contains('客户端异常') ||
            text.contains('数据异常');
        final pvp = text.contains('PVP_DIAG') ||
            text.contains('SUSPECT_MANIFEST_PIN') ||
            text.contains('盐场') ||
            text.contains('蟠桃') ||
            text.contains('isLast') ||
            text.contains('RejectLowVersionPvP');
        final important = anomaly ||
            pvp ||
            text.contains('咸强之王') ||
            text.contains('BIN') ||
            text.contains('拦截') ||
            text.contains('lifecycle') ||
            text.contains('login') ||
            text.contains('manifest') ||
            text.contains('WebSocket') ||
            text.contains('踢') ||
            m.level == JavaScriptLogLevel.error ||
            m.level == JavaScriptLogLevel.warning;
        if (important) {
          AppLog.js('${m.level.name}: $text');
        }
        if (anomaly) {
          AppLog.e('client', '[$accountId] console疑似客户端异常: $text');
        }
      });

      await controller.setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            AppLog.diag('game', {
              'event': 'page_started',
              'accountId': accountId,
              'url': url,
              'ms': sw.elapsedMilliseconds,
            });
            // 串行注入，避免与 pageFinished 抢跑把 BIN 冲掉
            unawaited(_queueInject(accountId, controller, account, 'page_started'));
          },
          onPageFinished: (url) async {
            AppLog.diag('game', {
              'event': 'page_finished',
              'accountId': accountId,
              'url': url,
              'ms': sw.elapsedMilliseconds,
            });
            AppLog.i('game', 'HTTP加载完成: $_baseUrl ($accountId)');
            try {
              // 日志根因：page_finished 后 hasBuf/xhr 变 false，登录未拦截 → roleId=0
              await _queueInject(accountId, controller, account, 'page_finished');
              await controller.runJavaScript(
                '${InjectScripts.vhFix}\n${InjectScripts.canvasGuard}\n'
                '${InjectScripts.visibilityKeepAlive}\n'
                '${InjectScripts.clientAnomalyWatch}\n'
                '${InjectScripts.pvpDiagWatch}\n'
                '${InjectScripts.lateSdkReady}\nwindow.__xyzwRoleBridge=false;\n'
                '${InjectScripts.roleBridge}\n${InjectScripts.gameReadyWatch}',
              );
              await _probeBinState(controller, accountId, 'page_finished_after');
              _armBinKeepAlive(accountId, controller, account);
            } catch (e) {
              AppLog.e('game', '晚注入失败: $e');
              _markReady(accountId);
            }
          },
          onWebResourceError: (err) {
            final url = err.url ?? '';
            final interesting = (err.isForMainFrame ?? false) ||
                url.contains('__xyzw/bin') ||
                url.contains('login') ||
                url.contains('hortorgames');
            if (interesting) {
              AppLog.diag('game', {
                'event': 'resource_error',
                'mainFrame': err.isForMainFrame,
                'code': err.errorCode,
                'type': err.errorType?.name,
                'desc': err.description,
                'url': url,
              });
            }
          },
          onHttpError: (err) {
            final uri = err.request?.uri.toString() ?? '';
            if (uri.contains('__xyzw/bin') || uri.contains('login')) {
              AppLog.diag('game', {
                'event': 'http_error',
                'status': err.response?.statusCode,
                'url': uri,
              });
            }
          },
        ),
      );

      final session = _Session(accountId: accountId, controller: controller);
      _sessions[accountId] = session;

      await _stageBin(accountId);
      if (!_scriptsReady) await _publishScripts();
      _armReadyWatch(accountId);
      final target = Uri.parse(_gameUrl(_baseUrl!));
      AppLog.diag('game', {
        'event': 'load_request',
        'url': target.toString(),
        'ms': sw.elapsedMilliseconds,
      });
      await controller.loadRequest(target);
      unawaited(widget.store.touchLastUsed(accountId));

      if (!mounted) return;
      setState(() {});
      _emitRunning();
    } catch (e, st) {
      AppLog.e('game', 'session失败 $accountId: $e\n$st');
      final s = _sessions[accountId];
      if (s != null) {
        s.loading = false;
        s.error = e.toString();
      } else {
        _bootError = e.toString();
      }
      if (mounted) setState(() {});
    } finally {
      _bootingIds.remove(accountId);
      AppLog.diag('game', {
        'event': 'session_boot_done',
        'accountId': accountId,
        'ms': sw.elapsedMilliseconds,
      });
    }
  }

  Future<WebViewController> _createController() async {
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      final params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
      return WebViewController.fromPlatformCreationParams(params);
    }
    return WebViewController();
  }

  Future<void> _probeBinState(
    WebViewController controller,
    String accountId,
    String phase,
  ) async {
    try {
      final raw = await controller.runJavaScriptReturningResult(r'''
(function(){
  var buf = window.__activeBinBuf;
  return JSON.stringify({
    hasBuf: !!buf,
    bytes: buf && buf.byteLength || 0,
    url: window.__xyzwBinUrl || '',
    xhr: !!window.__xhrIntercepted
  });
})()
''');
      AppLog.diag('game', {
        'event': 'bin_probe',
        'phase': phase,
        'accountId': accountId,
        'result': raw.toString(),
      });
    } catch (e) {
      AppLog.w('game', 'bin_probe失败 phase=$phase $e');
    }
  }

  /// 固定 query，避免每次换 t= 导致文档与关联请求缓存失效。
  String _gameUrl(String base) =>
      '$base/?origin=https://xxz-xyzw.hortorgames.com';

  Future<void> _stageBin(String accountId) async {
    final account = widget.store.byId(accountId);
    if (account == null) return;
    try {
      final dir = Directory(
        '${widget.rendererDir.path}${Platform.pathSeparator}__xyzw_bins',
      );
      await dir.create(recursive: true);
      final file = File(
        '${dir.path}${Platform.pathSeparator}${LocalHttpServer.binFileName(accountId)}.bin',
      );
      final bytes = account.binHex.length > 16384
          ? await compute(Account.hexToBytes, account.binHex)
          : Account.hexToBytes(account.binHex);
      if (!await file.exists() || await file.length() != bytes.length) {
        await file.writeAsBytes(bytes, flush: false);
      }
    } catch (e) {
      AppLog.w('game', '写入 BIN 文件失败 $e');
    }
  }

  void _armReadyWatch(String accountId) {
    _readyTimers[accountId]?.cancel();
    // 最长盖住加载层，等 canvas/SDK；超时再收起，避免一直转圈
    _readyTimers[accountId] = Timer(const Duration(seconds: 22), () {
      _markReady(accountId);
    });
  }

  void _markReady(String accountId) {
    _readyTimers.remove(accountId)?.cancel();
    final s = _sessions[accountId];
    if (s == null || !s.loading) return;
    s.loading = false;
    if (mounted) setState(() {});
  }

  Future<void> _queueInject(
    String accountId,
    WebViewController controller,
    Account account,
    String phase,
  ) {
    final prev = _injectChain[accountId] ?? Future<void>.value();
    final next = prev
        .catchError((Object _) {})
        .then((_) => _injectBinAndHooks(controller, account, phase));
    _injectChain[accountId] = next;
    return next;
  }

  void _armBinKeepAlive(
    String accountId,
    WebViewController controller,
    Account account,
  ) {
    _binKeepAlive.remove(accountId)?.cancel();
    var ticks = 0;
    _binKeepAlive[accountId] = Timer.periodic(const Duration(seconds: 2), (t) {
      ticks++;
      if (ticks > 12 || !_sessions.containsKey(accountId)) {
        t.cancel();
        _binKeepAlive.remove(accountId);
        return;
      }
      unawaited(() async {
        try {
          final raw = await controller.runJavaScriptReturningResult(r'''
(function(){
  var buf = window.__activeBinBuf;
  return JSON.stringify({
    hasBuf: !!buf,
    bytes: buf && buf.byteLength || 0,
    xhr: !!window.__xhrIntercepted
  });
})()
''');
          final text = raw.toString();
          final need = text.contains('"hasBuf":false') ||
              text.contains('"xhr":false') ||
              text.contains('"bytes":0');
          if (need) {
            AppLog.w('game', 'BIN保活补注 #$ticks $accountId $text');
            await _queueInject(accountId, controller, account, 'keepalive_$ticks');
          }
        } catch (_) {}
      }());
    });
  }

  Future<void> _injectBinAndHooks(
    WebViewController controller,
    Account account,
    String phase,
  ) async {
    final port = _server?.port ?? 0;
    final binName = LocalHttpServer.binFileName(account.id);
    // 绝对地址用 127.0.0.1，避免 iOS localhost→IPv6
    final binUrl = port > 0
        ? 'http://127.0.0.1:$port/__xyzw/bin/$binName'
        : '/__xyzw/bin/$binName';

    // xhrIntercept / 异常侦测自身幂等；页面重建后标志丢失会自动重装
    await GamePrefsStore.load();
    final prefs = GamePrefsStore.data;
    await controller.runJavaScript(
      '${InjectScripts.compat}\n${InjectScripts.xhrIntercept}\n'
      '${InjectScripts.visibilityKeepAlive}\n'
      '${InjectScripts.clientAnomalyWatch}\n'
      '${InjectScripts.pvpDiagWatch}\n'
      '${InjectScripts.persistGamePrefs}\n'
      '${prefs.isEmpty ? '' : InjectScripts.restoreGamePrefs(prefs)}',
    );

    // iOS：优先 Dart→base64 灌入缓冲；HTTP 拉取作备用
    try {
      var b64 = _binB64Cache[account.id];
      if (b64 == null) {
        final file = File(
          '${widget.rendererDir.path}${Platform.pathSeparator}__xyzw_bins'
          '${Platform.pathSeparator}$binName.bin',
        );
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          b64 = base64Encode(bytes);
          _binB64Cache[account.id] = b64;
        }
      }
      if (b64 != null) {
        await controller.runJavaScript(
          InjectScripts.activateBinBase64(b64, account.fileLabel),
        );
        AppLog.i(
          'game',
          'BIN缓冲注入成功[$phase] ${account.fileLabel} '
          '${(b64.length * 3) ~/ 4}B(approx)',
        );
      } else {
        AppLog.w('game', 'BIN文件不存在，回退HTTP $binUrl');
      }
    } catch (e) {
      AppLog.w('game', 'BIN缓冲注入失败，回退HTTP: $e');
    }

    await controller.runJavaScript(
      '${InjectScripts.activateBinUrl(binUrl, account.fileLabel)}\n'
      '${InjectScripts.gameReadyWatch}',
    );
    await _probeBinState(controller, account.id, 'inject_$phase');
    if (kDebugMode && phase == 'page_started') {
      await controller.runJavaScript(InjectScripts.hsdkProbe);
    }
    AppLog.i('game', 'BIN地址注入成功[$phase] ${account.fileLabel} → $binUrl');
  }

  void _onBridge(String accountId, String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final type = map['type'] as String?;
      if (type == 'gm') {
        final id = map['id'] as String?;
        final payload = map['payload'];
        if (id != null && payload is Map) {
          _handleGm(accountId, id, Map<String, dynamic>.from(payload));
        }
        return;
      }
      if (type == 'scriptStatus') {
        AppLog.i('script', map['message'] as String? ?? '');
        return;
      }
      if (type == 'roleLog') {
        AppLog.i('avatar', map['message'] as String? ?? raw);
        return;
      }
      if (type == 'gameReady') {
        _markReady(accountId);
        return;
      }
      if (type == 'gamePrefs') {
        final data = map['data'];
        if (data is Map) {
          final next = <String, String>{
            for (final e in data.entries)
              if (e.value != null) e.key.toString(): e.value.toString(),
          };
          unawaited(GamePrefsStore.save(next));
          AppLog.i('prefs', '已备份游戏设置 keys=${next.length}');
        }
        return;
      }
      if (type == 'clientAnomaly') {
        final kind = map['kind'] as String? ?? '';
        final key = map['key'] as String? ?? '';
        final text = map['text'] as String? ?? '';
        final fp = map['fingerprint'];
        if (kind == 'fingerprint') {
          AppLog.diag('client', {
            'event': 'fingerprint',
            'accountId': accountId,
            'fp': fp,
          });
        } else {
          AppLog.e(
            'client',
            '[$accountId] 客户端异常 key=$key kind=$kind text=$text',
          );
          AppLog.diag('client', {
            'event': 'anomaly',
            'accountId': accountId,
            'kind': kind,
            'key': key,
            'text': text,
            'fp': fp,
          });
        }
        return;
      }
      if (type == 'pvpDiag') {
        final level = map['level'] as String? ?? 'I';
        final msg = map['message'] as String? ?? '';
        final event = map['event'] as String? ?? '';
        final summary = map['summary'];
        final url = map['url'] as String? ?? '';
        final line = '[$accountId] ${event.isEmpty ? msg : '$event $msg'}'
            '${url.isEmpty ? '' : ' url=$url'}'
            '${summary == null ? '' : ' summary=$summary'}';
        if (level == 'W' || level == 'E') {
          AppLog.w('pvp', line);
        } else {
          AppLog.diag('pvp', {
            'accountId': accountId,
            'event': event.isEmpty ? 'msg' : event,
            'level': level,
            'message': msg,
            'url': url,
            'summary': summary,
          });
        }
        return;
      }
      if (type == 'role') {
        final rid = (map['roleId'] as num?)?.toInt() ?? 0;
        final name = (map['name'] as String?)?.trim() ?? '';
        AppLog.diag('game', {
          'event': 'role_bridge',
          'accountId': accountId,
          'roleId': rid,
          'name': name,
          'from': map['from'],
        });
        if (rid > 0) {
          _markReady(accountId);
        } else {
          AppLog.w('game', 'ROLE为空(roleId=0)，可能登录失败，请查BIN拦截日志');
        }
      }
      if (type != 'role') return;

      final name = (map['name'] as String?)?.trim();
      var avatar = (map['avatar'] as String?)?.trim();
      final headRaw = map['headImgRaw']?.toString() ?? '';
      final from = map['from']?.toString() ?? '';
      final lordSkinId = (map['lordSkinId'] as num?)?.toInt() ?? 0;
      var roleId = (map['roleId'] as num?)?.toInt() ?? 0;
      if (roleId <= 0) {
        roleId = RoleAvatarCache.roleIdFromName(
              widget.store.byId(accountId)?.name ?? '',
            ) ??
            0;
      }
      if (avatar != null && avatar.isNotEmpty) {
        avatar = RoleAvatarCache.normalize(avatar);
      }

      AppLog.i(
        'avatar',
        'Dart收 account=$accountId roleId=$roleId name=$name '
        'from=$from headRaw=$headRaw lordSkinId=$lordSkinId avatar=$avatar',
      );

      if (roleId > 0 && avatar != null && avatar.startsWith('http')) {
        // ignore: unawaited_futures
        RoleAvatarCache.put(roleId, avatar);
      }

      final cur = widget.store.byId(accountId);
      final nextAvatar = (avatar != null && avatar.isNotEmpty)
          ? avatar
          : cur?.avatarUrl;
      // ignore: unawaited_futures
      widget.store.updateProfile(
        accountId,
        roleName: (name != null && name.isNotEmpty) ? name : null,
        avatarUrl: nextAvatar,
      );
    } catch (e) {
      AppLog.w('avatar', 'bridge parse fail: $e raw=$raw');
    }
  }

  Future<void> _handleGm(
    String accountId,
    String reqId,
    Map<String, dynamic> payload,
  ) async {
    final result = await _gmRequest(payload);
    final s = _sessions[accountId];
    if (s == null) return;
    final js =
        'window.__gmResolve && window.__gmResolve(${jsonEncode(reqId)}, ${jsonEncode(jsonEncode(result))});';
    try {
      await s.controller.runJavaScript(js);
    } catch (_) {}
  }

  Future<Map<String, dynamic>> _gmRequest(Map<String, dynamic> payload) async {
    final url = payload['url'] as String? ?? '';
    final method = (payload['method'] as String? ?? 'GET').toUpperCase();
    final data = payload['data'] as String?;
    final timeoutMs = (payload['timeout'] as num?)?.toInt() ?? 20000;
    final headers = payload['headers'];
    AppLog.i('script', 'GM_xhr $method $url');
    try {
      final client = HttpClient();
      client.connectionTimeout = Duration(milliseconds: timeoutMs.clamp(1000, 60000));
      final req = await client.openUrl(method, Uri.parse(url));
      req.followRedirects = true;
      if (headers is Map) {
        headers.forEach((k, v) {
          req.headers.set('$k', '$v');
        });
      }
      if (data != null) {
        if (req.headers.value('content-type') == null) {
          req.headers.set('content-type', 'application/json;charset=utf-8');
        }
        req.add(utf8.encode(data));
      }
      final res = await req.close().timeout(
        Duration(milliseconds: timeoutMs.clamp(1000, 60000)),
      );
      final body = await utf8.decodeStream(res);
      final headerBuf = StringBuffer();
      res.headers.forEach((name, values) {
        headerBuf.writeln('$name: ${values.join(', ')}');
      });
      client.close(force: true);
      final preview = body.length <= 300 ? body : '${body.substring(0, 300)}…';
      AppLog.i(
        'script',
        'GM_xhr 完成 ${res.statusCode} $url (${body.length}B) body=$preview',
      );
      if (data != null && data.isNotEmpty) {
        final reqPrev = data.length <= 200 ? data : '${data.substring(0, 200)}…';
        AppLog.i('script', 'GM_xhr 请求体 $reqPrev');
      }
      return {
        'status': res.statusCode,
        'statusText': res.reasonPhrase.isEmpty ? 'OK' : res.reasonPhrase,
        'responseText': body,
        'responseHeaders': headerBuf.toString(),
        'finalUrl': res.redirects.isEmpty ? url : res.redirects.last.location.toString(),
      };
    } catch (e) {
      AppLog.w('script', 'GM_xhr 失败 $url → $e');
      return {'status': 0, 'error': e.toString()};
    }
  }

  Future<void> _switchAccount() async {
    final accounts = widget.store.accounts;
    if (accounts.isEmpty) return;

    final picked = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          child: Material(
              color: const Color(0xFFF2F2F7),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: 36,
                      height: 5,
                      decoration: BoxDecoration(
                        color: AppTheme.fill.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
                      child: Row(
                        children: [
                          Text(
                            '切换账号',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.3,
                            ),
                          ),
                          Spacer(),
                          Text(
                            '已进入的会直接切回',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(ctx).size.height * 0.5,
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: accounts.length,
                        separatorBuilder: (context, index) => Divider(
                          height: 0.5,
                          indent: 60,
                          color: AppTheme.separator.withValues(alpha: 0.55),
                        ),
                        itemBuilder: (_, i) {
                          final a = accounts[i];
                          final alive = _sessions.containsKey(a.id);
                          final active = a.id == _activeId;
                          return ListTile(
                            dense: true,
                            leading: _MiniAvatar(account: a),
                            title: Text(
                              a.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: Text(
                              alive
                                  ? (active
                                      ? '当前前台 · 会话保活中'
                                      : '后台运行中 · 点按秒切（不重载）')
                                  : '未进入 · 将新建会话',
                              style: TextStyle(
                                fontSize: 12,
                                color: alive
                                    ? AppTheme.green
                                    : AppTheme.textSecondary,
                              ),
                            ),
                            trailing: active
                                ? const Icon(
                                    CupertinoIcons.checkmark_alt,
                                    size: 20,
                                    color: AppTheme.blue,
                                  )
                                : null,
                            onTap: () => Navigator.pop(ctx, a.id),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
        );
      },
    );

    if (picked == null || picked == _activeId) return;
    await _ensureSession(picked);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.scripts.removeListener(_onScripts);
    _sessionHeartbeat?.cancel();
    for (final t in _readyTimers.values) {
      t.cancel();
    }
    _readyTimers.clear();
    for (final t in _binKeepAlive.values) {
      t.cancel();
    }
    _binKeepAlive.clear();
    if (_ownsServer) unawaited(_server?.stop());
    _sessions.clear();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.store.byId(_activeId);
    final title = active?.displayName ?? '咸强之王';

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      body: Column(
        children: [
          ClipRect(
            child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F2F7),
                  border: Border(
                    bottom: BorderSide(
                      color: AppTheme.separator.withValues(alpha: 0.45),
                      width: 0.5,
                    ),
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: SizedBox(
                    height: kToolbarHeight,
                    child: Row(
                      children: [
                        IosIconButton(
                          tooltip: '返回',
                          icon: CupertinoIcons.back,
                          color: AppTheme.blue,
                          onPressed: widget.onBack,
                        ),
                        Expanded(
                          child: Text(
                            title,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.text,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                        IosIconButton(
                          tooltip: '切换账号',
                          icon: CupertinoIcons.person_2,
                          color: AppTheme.blue,
                          onPressed: _bootError != null ? null : _switchAccount,
                        ),
                        IosIconButton(
                          tooltip: '刷新当前',
                          icon: CupertinoIcons.refresh,
                          color: AppTheme.blue,
                          onPressed: () async {
                            await _publishScripts();
                            final s = _sessions[_activeId];
                            if (s == null) return;
                            s.loading = true;
                            setState(() {});
                            await _stageBin(_activeId);
                            _armReadyWatch(_activeId);
                            await s.controller.reload();
                          },
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_bootError != null) {
      return _PlaceholderPanel(message: _bootError!);
    }
    if (_sessions.isEmpty || !_sessions.containsKey(_activeId)) {
      return const ColoredBox(
        color: Color(0xFFF2F2F7),
        child: Center(child: CupertinoActivityIndicator()),
      );
    }

    final ids = _sessions.keys.toList();

    // 后台号铺在下层保活；当前号必须最后绘制，否则 WKWebView 会抢走点击
    //（OverflowBox 露 3px 时原生视图仍是全屏，IgnorePointer 挡不住）。
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final id in ids)
          if (id != _activeId)
            Positioned.fill(
              child: IgnorePointer(
                child: TickerMode(
                  enabled: true,
                  child: _sessionView(_sessions[id]!),
                ),
              ),
            ),
        Positioned.fill(child: _sessionView(_sessions[_activeId]!)),
      ],
    );
  }

  Widget _sessionView(_Session session) {
    if (session.error != null) {
      return _PlaceholderPanel(message: session.error!);
    }
    final booting =
        session.loading || _bootingIds.contains(session.accountId);
    // iOS WKWebView：全尺寸加载 + 上层遮罩（勿缩到 1px，会影响布局/触摸）
    // Android Hybrid Composition：加载期缩到 1px，避免黑底盖住 Flutter 层
    final shrink = booting && !Platform.isIOS;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: 0,
          top: 0,
          width: shrink ? 1 : null,
          height: shrink ? 1 : null,
          right: shrink ? null : 0,
          bottom: shrink ? null : 0,
          child: RepaintBoundary(child: _buildWebView(session.controller)),
        ),
        if (booting)
          const ColoredBox(
            color: Color(0xFFF2F2F7),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipOval(
                    child: Image(
                      image: AssetImage('assets/images/app_logo_circle.png'),
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.low,
                      gaplessPlayback: true,
                    ),
                  ),
                  SizedBox(height: 16),
                  CupertinoActivityIndicator(),
                  SizedBox(height: 10),
                  Text(
                    '资源加载中…',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF8E8E93),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildWebView(WebViewController controller) {
    if (WebViewPlatform.instance is AndroidWebViewPlatform) {
      return WebViewWidget.fromPlatformCreationParams(
        params: AndroidWebViewWidgetCreationParams.fromPlatformWebViewWidgetCreationParams(
          PlatformWebViewWidgetCreationParams(
            controller: controller.platform,
          ),
          displayWithHybridComposition: true,
        ),
      );
    }
    return WebViewWidget(controller: controller);
  }
}

class _MiniAvatar extends StatelessWidget {
  const _MiniAvatar({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context) {
    final initial =
        account.displayName.isNotEmpty ? account.displayName.characters.first : '?';
    return NetAvatar(
      url: RoleAvatarCache.displayUrl(account.avatarUrl, account.name) ??
          account.avatarUrl,
      initial: initial,
      size: 32,
      radius: 6,
    );
  }
}

class _PlaceholderPanel extends StatelessWidget {
  const _PlaceholderPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppTheme.bg,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: SelectableText(
          message,
          style: const TextStyle(color: AppTheme.text, fontSize: 13, height: 1.4),
        ),
      ),
    );
  }
}
