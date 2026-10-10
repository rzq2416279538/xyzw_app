import 'dart:typed_data';

import 'package:flutter/cupertino.dart';

import '../core/app_log.dart';
import '../importer/http_client.dart';
import 'app_theme.dart';

/// 有可用 http 头像则显示网络图；否则用本地默认头像。
/// 进游戏后抓到真头像会写回 URL，自动切换。
class NetAvatar extends StatefulWidget {
  const NetAvatar({
    super.key,
    required this.url,
    required this.initial,
    this.size = 40,
    this.radius = 10,
  });

  static const assetDefault = 'assets/images/default_avatar.jpg';

  final String? url;
  final String initial;
  final double size;
  final double radius;

  @override
  State<NetAvatar> createState() => _NetAvatarState();
}

class _NetAvatarState extends State<NetAvatar> {
  static final _mem = <String, Uint8List>{};

  Uint8List? _bytes;
  var _failed = false;
  var _token = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant NetAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _bytes = null;
      _failed = false;
      _load();
    }
  }

  List<String> get _httpCandidates => (widget.url ?? '')
      .split('|')
      .map((e) => e.trim())
      .where((e) => e.startsWith('http') && !_isPlaceholder(e))
      .toList();

  static bool _isPlaceholder(String u) {
    return u.contains('xiaoyugan.png') ||
        u.contains('default_avatar') ||
        u.startsWith('asset:');
  }

  Future<void> _load() async {
    final cands = _httpCandidates;
    for (final u in cands) {
      final hit = _mem[u];
      if (hit != null) {
        _bytes = hit;
        _failed = false;
        return;
      }
    }
    if (cands.isEmpty) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    final token = ++_token;
    for (final u in cands) {
      try {
        final res = await ImportHttp.get(
          u,
          headers: const {
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 Chrome/120.0.0.0 Mobile Safari/537.36',
            'Accept': 'image/*,*/*',
          },
        );
        if (token != _token || !mounted) return;
        if (res.status == 200 && res.body.length > 100) {
          final bytes = Uint8List.fromList(res.body);
          if (_mem.length > 80) _mem.remove(_mem.keys.first);
          _mem[u] = bytes;
          setState(() {
            _bytes = bytes;
            _failed = false;
          });
          return;
        }
        AppLog.w('avatar', 'HTTP ${res.status} len=${res.body.length} $u');
      } catch (e) {
        AppLog.w('avatar', 'fail $u → $e');
      }
    }
    if (token != _token || !mounted) return;
    setState(() => _failed = true);
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (_bytes != null) {
      child = Image.memory(_bytes!, fit: BoxFit.cover);
    } else if (!_failed && _httpCandidates.isNotEmpty) {
      // 加载中先显示默认头，避免闪字母
      child = Image.asset(NetAvatar.assetDefault, fit: BoxFit.cover);
    } else {
      child = Image.asset(
        NetAvatar.assetDefault,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => ColoredBox(
          color: AppTheme.badgeBg,
          child: Center(
            child: Text(
              widget.initial,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: SizedBox(width: widget.size, height: widget.size, child: child),
    );
  }
}
