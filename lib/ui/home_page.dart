import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/app_log.dart';
import '../core/ios_network_gate.dart';
import '../core/local_http_server.dart';
import '../core/renderer_cache.dart';
import '../core/renderer_status.dart';
import '../core/renderer_warmup.dart';
import '../data/account.dart';
import '../data/account_store.dart';
import '../data/role_avatar_cache.dart';
import '../data/script_store.dart';
import 'app_theme.dart';
import 'game_page.dart';
import 'import_page.dart';
import 'ios_chrome.dart';
import 'net_avatar.dart';
import 'scripts_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.store, required this.scripts});

  final AccountStore store;
  final ScriptStore scripts;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Directory? _rendererDir;
  LocalHttpServer? _http;
  RendererStatus? _status;
  String? _bootError;
  bool _booting = true;
  String _query = '';
  bool _sortRecent = true;
  bool _searchOpen = false;
  final _searchCtrl = TextEditingController();
  final _gameKey = GlobalKey<GamePageState>();
  var _gameMounted = false;
  var _gameVisible = false;
  String? _gameInitialId;
  final _running = <String>{};
  Account? _menuAccount;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStore);
    _init();
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStore);
    _searchCtrl.dispose();
    _http?.stop();
    super.dispose();
  }

  void _onStore() => setState(() {});

  Future<void> _init() async {
    final sw = Stopwatch()..start();
    try {
      AppLog.i('boot', '首页初始化开始 platform=${Platform.operatingSystem}');
      await widget.store.load();
      AppLog.diag('boot', {
        'event': 'accounts_loaded',
        'count': widget.store.accounts.length,
        'ms': sw.elapsedMilliseconds,
      });
      await widget.scripts.load();
      AppLog.diag('boot', {
        'event': 'scripts_loaded',
        'count': widget.scripts.scripts.length,
        'enabled': widget.scripts.enabledScripts.length,
        'ms': sw.elapsedMilliseconds,
      });
      await RoleAvatarCache.ensureLoaded();
      final dir = await RendererCache.ensure();
      final override = Directory(
        '${dir.parent.path}${Platform.pathSeparator}renderer_override',
      );
      if (await override.exists()) {
        await RendererCache.mergeFromExternal(override, dir);
      }
      final status = await RendererStatus.inspect(dir);
      AppLog.diag('boot', {
        'event': 'renderer',
        'ready': status.isReady,
        'dir': dir.path,
        'ms': sw.elapsedMilliseconds,
      });
      final http = LocalHttpServer(dir);
      await http.start();
      AppLog.diag('boot', {
        'event': 'http_ready',
        'baseUrl': http.baseUrl,
        'port': http.port,
        'ms': sw.elapsedMilliseconds,
      });
      if (!mounted) {
        await http.stop();
        return;
      }
      setState(() {
        _rendererDir = dir;
        _http = http;
        _status = status;
        _booting = false;
      });
      final base = http.baseUrl;
      // ignore: unawaited_futures
      RendererWarmup.prefetch(base, dir).then((_) {
        AppLog.i('boot', '资源预热完成 ${sw.elapsedMilliseconds}ms');
      });
      // iOS：启动立刻做联网/本地网络预检，避免导入时才弹系统权限导致失败
      if (Platform.isIOS) {
        // ignore: unawaited_futures
        Future<void>(() async {
          await IosNetworkGate.warmUp();
          if (!mounted) return;
          await IosNetworkGate.ensureReady(context);
        });
      }
    } catch (e, st) {
      AppLog.e('boot', '首页初始化失败 $e\n$st');
      if (!mounted) return;
      setState(() {
        _bootError = e.toString();
        _booting = false;
      });
    }
  }

  Future<void> _exportLog() async {
    try {
      final msg = await AppLog.exportFile();
      if (!mounted) return;
      if (Platform.isIOS) {
        await showCupertinoDialog<void>(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('日志已导出'),
            content: Text(msg),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('好'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败：$e')),
      );
    }
  }

  Future<void> _openImport() async {
    if (Platform.isIOS) {
      final ok = await IosNetworkGate.ensureReady(context);
      if (!ok || !mounted) return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => ImportPage(store: widget.store),
      ),
    );
  }

  void _minimizeGame() {
    if (!_gameVisible) return;
    setState(() => _gameVisible = false);
  }

  Future<void> _startGame(String accountId) async {
    final account = widget.store.byId(accountId);
    final dir = _rendererDir;
    final status = _status;
    if (account == null || dir == null || status == null) return;
    if (Platform.isIOS) {
      final ok = await IosNetworkGate.ensureReady(context);
      if (!ok || !mounted) return;
    }
    AppLog.diag('ui', {
      'event': 'start_game',
      'accountId': accountId,
      'label': account.fileLabel,
      'gameMounted': _gameMounted,
      'running': _running.contains(accountId),
    });
    if (!status.isReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('游戏资源未就绪，无法进入')),
      );
      return;
    }
    if (!_gameMounted) {
      setState(() {
        _gameMounted = true;
        _gameVisible = true;
        _gameInitialId = accountId;
      });
      return;
    }
    setState(() => _gameVisible = true);
    await _gameKey.currentState?.openAccount(accountId);
  }

  Future<void> _closeGame(String accountId) async {
    if (!_running.contains(accountId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该角色未在运行')),
      );
      return;
    }
    await _gameKey.currentState?.closeAccount(accountId);
  }

  Future<void> _restartGame(String accountId) async {
    await _startGame(accountId);
    await _gameKey.currentState?.restartAccount(accountId);
  }

  Future<void> _exportBin(Account account) async {
    try {
      final bytes = Account.hexToBytes(account.binHex);
      final name = '${account.displayName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}.bin';
      final saved = await FilePicker.platform.saveFile(
        dialogTitle: '导出 bin',
        fileName: name,
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: const ['bin'],
      );
      if (!mounted) return;
      if (saved == null || saved.isEmpty) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导出：$saved')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败：$e')),
      );
    }
  }

  void _openAccountMenu(Account account) {
    setState(() => _menuAccount = account);
  }

  void _closeAccountMenu() {
    if (_menuAccount == null) return;
    setState(() => _menuAccount = null);
  }

  Future<void> _runAccountAction(String action) async {
    final account = _menuAccount;
    if (account == null) return;
    final running = _running.contains(account.id);
    _closeAccountMenu();
    switch (action) {
      case 'start':
        await _startGame(account.id);
      case 'close':
        await _closeGame(account.id);
      case 'restart':
        await _restartGame(account.id);
      case 'export':
        await _exportBin(account);
      case 'delete':
        if (running) await _gameKey.currentState?.closeAccount(account.id);
        await _confirmRemove(account);
    }
  }

  Future<void> _confirmRemove(Account account) async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('删除角色'),
        content: Text('确定删除「${account.displayName}」？'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) await widget.store.remove(account.id);
  }

  List<Account> get _filtered {
    var list = widget.store.accounts.toList();
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where(
            (a) =>
                a.displayName.toLowerCase().contains(q) ||
                a.fileLabel.toLowerCase().contains(q),
          )
          .toList();
    }
    list.sort((a, b) {
      if (_sortRecent) {
        final ta = a.lastUsedAt?.millisecondsSinceEpoch ?? 0;
        final tb = b.lastUsedAt?.millisecondsSinceEpoch ?? 0;
        if (ta != tb) return tb.compareTo(ta);
      }
      return a.order.compareTo(b.order);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final home = SoftBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: GlassAppBar(
          centerTitle: false,
          leading: _searchOpen
              ? null
              : const Padding(
                  padding: EdgeInsets.only(left: 10, right: 6),
                  child: _HomeBrandLogo(),
                ),
          title: _searchOpen
              ? Padding(
                  padding: const EdgeInsets.only(left: 12, right: 4),
                  child: CupertinoSearchTextField(
                    controller: _searchCtrl,
                    placeholder: '搜索账号',
                    onChanged: (v) => setState(() => _query = v),
                    onSuffixTap: () {
                      _searchCtrl.clear();
                      setState(() {
                        _query = '';
                        _searchOpen = false;
                      });
                    },
                  ),
                )
              : const Text(
                  '咸强之王',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
          actions: [
            IosIconButton(
              tooltip: '搜索',
              icon: CupertinoIcons.search,
              color: AppTheme.blue,
              onPressed: () => setState(() => _searchOpen = !_searchOpen),
            ),
            IosIconButton(
              tooltip: _sortRecent ? '按最近使用' : '按导入顺序',
              icon: CupertinoIcons.arrow_up_arrow_down,
              color: AppTheme.orange,
              onPressed: () => setState(() => _sortRecent = !_sortRecent),
            ),
            IosIconButton(
              tooltip: '脚本管理',
              icon: CupertinoIcons.chevron_left_slash_chevron_right,
              color: AppTheme.teal,
              onPressed: () {
                Navigator.of(context).push(
                  CupertinoPageRoute<void>(
                    builder: (_) => ScriptsPage(store: widget.scripts),
                  ),
                );
              },
            ),
            IosIconButton(
              tooltip: '导出日志',
              icon: CupertinoIcons.doc_text,
              color: AppTheme.blue,
              onPressed: _booting ? null : _exportLog,
            ),
            IosIconButton(
              tooltip: '导入角色',
              icon: CupertinoIcons.add_circled_solid,
              color: AppTheme.green,
              onPressed: _booting ? null : _openImport,
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: _booting
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _CircleSplashLogo(size: 96),
                    const SizedBox(height: 18),
                    const CupertinoActivityIndicator(),
                  ],
                ),
              )
            : _bootError != null
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(20, 120, 20, 20),
                    child: SelectableText(
                      _bootError!,
                      style: const TextStyle(fontSize: 14, color: AppTheme.danger),
                    ),
                  )
                : _filtered.isEmpty
                    ? _Empty(onImport: _openImport)
                    : ListView.separated(
                        // iOS：略增缓存，滑动更顺
                        scrollCacheExtent: 480,
                        padding: EdgeInsets.fromLTRB(
                          16,
                          MediaQuery.paddingOf(context).top + kToolbarHeight + 12,
                          16,
                          28,
                        ),
                        itemCount: _filtered.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final a = _filtered[i];
                          return RepaintBoundary(
                            child: _AccountCard(
                            account: a,
                            running: _running.contains(a.id),
                            onTap: () => _openAccountMenu(a),
                            onLongPress: () => _openAccountMenu(a),
                          ),
                          );
                        },
                      ),
      ),
    );

    final dir = _rendererDir;
    final status = _status;
    final game = _gameMounted && dir != null && status != null && _gameInitialId != null
        // 回首页只隐藏，不销毁；Ticker 保持开启，后台号继续跑（应用内保活）
        ? Offstage(
            offstage: !_gameVisible,
            child: TickerMode(
              enabled: true,
              child: GamePage(
                key: _gameKey,
                store: widget.store,
                scripts: widget.scripts,
                initialAccountId: _gameInitialId!,
                rendererDir: dir,
                status: status,
                httpServer: _http,
                onBack: _minimizeGame,
                onRunningChanged: (ids) {
                  if (!mounted) return;
                  setState(() {
                    _running
                      ..clear()
                      ..addAll(ids);
                    if (ids.isEmpty) _gameVisible = false;
                  });
                },
              ),
            ),
          )
        : const SizedBox.shrink();

    return PopScope(
      canPop: !_gameVisible && _menuAccount == null,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_menuAccount != null) {
          _closeAccountMenu();
          return;
        }
        _minimizeGame();
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          home,
          if (_menuAccount != null && !_gameVisible)
            Positioned.fill(
              child: _AccountActionPanel(
                account: _menuAccount!,
                running: _running.contains(_menuAccount!.id),
                onAction: _runAccountAction,
                onDismiss: _closeAccountMenu,
              ),
            ),
          if (_gameMounted) Positioned.fill(child: game),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.person_2,
              size: 44,
              color: AppTheme.textSecondary.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 12),
            const Text(
              '暂无角色',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              '点右上角 + 扫码 / 手机号 / bin 导入',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 18),
            CupertinoButton.filled(
              onPressed: onImport,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
              child: const Text('导入角色', style: TextStyle(fontSize: 15)),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountActionPanel extends StatelessWidget {
  const _AccountActionPanel({
    required this.account,
    required this.running,
    required this.onAction,
    required this.onDismiss,
  });

  final Account account;
  final bool running;
  final ValueChanged<String> onAction;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onDismiss,
          child: const ColoredBox(color: Color(0x66000000)),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: ColoredBox(
            color: Colors.white,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      account.displayName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      running ? '运行中' : '未启动',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SheetAction(
                      label: running ? '进入' : '启动',
                      onTap: () => onAction('start'),
                    ),
                    if (running)
                      _SheetAction(
                        label: '关闭',
                        onTap: () => onAction('close'),
                      ),
                    if (running)
                      _SheetAction(
                        label: '重启',
                        onTap: () => onAction('restart'),
                      ),
                    _SheetAction(
                      label: '导出 bin',
                      onTap: () => onAction('export'),
                    ),
                    _SheetAction(
                      label: '删除',
                      danger: true,
                      onTap: () => onAction('delete'),
                    ),
                    const SizedBox(height: 4),
                    _SheetAction(label: '取消', onTap: onDismiss),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: danger ? const Color(0x14FF3B30) : const Color(0xFFF2F2F7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: danger ? AppTheme.danger : AppTheme.blue,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.account,
    required this.running,
    required this.onTap,
    required this.onLongPress,
  });

  final Account account;
  final bool running;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  String _timeText() {
    final t = account.lastUsedAt;
    if (t == null) return '尚未进入';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final initial = account.displayName.isNotEmpty
        ? account.displayName.characters.first
        : '?';
    return GlassCard(
      onTap: onTap,
      onLongPress: onLongPress,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Row(
        children: [
          NetAvatar(
            url: RoleAvatarCache.displayUrl(account.avatarUrl, account.name) ??
                account.avatarUrl,
            initial: initial,
            size: 46,
            radius: 12,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _timeText(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.badgeBg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              running ? '运行中' : '待机',
              style: TextStyle(
                fontSize: 12,
                color: running ? AppTheme.green : AppTheme.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 2),
          const Icon(
            CupertinoIcons.chevron_forward,
            size: 16,
            color: AppTheme.textSecondary,
          ),
        ],
      ),
    );
  }
}

class _HomeBrandLogo extends StatelessWidget {
  const _HomeBrandLogo();

  @override
  Widget build(BuildContext context) {
    return const _CircleSplashLogo(size: 32, shadow: false);
  }
}

/// 圆形开屏 / 品牌 logo（资源本身透明圆 + ClipOval 双保险）。
class _CircleSplashLogo extends StatelessWidget {
  const _CircleSplashLogo({required this.size, this.shadow = true});

  final double size;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final logo = ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Image.asset(
          'assets/images/app_logo_circle.png',
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
        ),
      ),
    );
    if (!shadow) return logo;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: logo,
    );
  }
}
