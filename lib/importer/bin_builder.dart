import 'dart:convert';
import 'dart:typed_data';

import '../core/app_log.dart';
import '../data/role_avatar_cache.dart';
import 'bon.dart';
import 'http_client.dart';
import 'wx_login.dart';
import 'xy_endpoints.dart';

class RoleInfo {
  RoleInfo({
    required this.serverId,
    required this.roleId,
    required this.name,
    required this.power,
    required this.level,
    required this.loginAt,
    this.avatarUrl,
    this.serverLabel,
  });

  final int serverId;
  final int roleId;
  final String name;
  final int power;
  final int level;
  final String loginAt;
  String? avatarUrl;
  final String? serverLabel;

  /// 取可持久化的主头像：仅真实 http（进游戏后拿到的）；默认头像不落库。
  String? get primaryAvatar {
    for (final p in (avatarUrl ?? '').split('|')) {
      final t = p.trim();
      if (!t.startsWith('http')) continue;
      if (t.contains('xiaoyugan.png') || t.contains('default_avatar')) continue;
      return t;
    }
    return null;
  }

  String get zoneText {
    final label = serverLabel?.trim();
    if (label != null && label.isNotEmpty) return label;
    if (serverId > 0) return '区服 ${RoleInfo.displayZone(serverId)}';
    return '未知区';
  }

  /// 对照鸟哥之王 Pro：服务端 serverId 含 +27 偏移，展示要减 27。
  static int displayZone(int serverId) {
    var sid = serverId;
    if (sid >= 2000000) {
      sid -= 2000000;
    } else if (sid >= 1000000) {
      sid -= 1000000;
    }
    return sid - 27;
  }

  static String roleTag(int serverId) {
    if (serverId >= 2000000) return '③';
    if (serverId >= 1000000) return '②';
    return '①';
  }

  String powerText() {
    if (power >= 100000000) return '${(power / 1e8).toStringAsFixed(2)}亿';
    if (power >= 10000) return '${(power / 1e4).toStringAsFixed(2)}万';
    return '$power';
  }
}

class GeneratedBin {
  GeneratedBin(this.fileName, this.bytes, this.role);
  final String fileName;
  final Uint8List bytes;
  final RoleInfo role;
}

class AccountCredential {
  AccountCredential({
    required this.platform,
    required this.platformExt,
    required this.info,
    required this.scene,
    required this.referrerInfo,
  });

  final String platform;
  final String platformExt;
  final Map<String, dynamic> info;
  final dynamic scene;
  final dynamic referrerInfo;

  Map<String, dynamic> toMap(int? serverId) => {
        'platform': platform,
        'platformExt': platformExt,
        'info': info,
        'serverId': serverId,
        'scene': scene,
        'referrerInfo': referrerInfo,
      };
}

/// 对照 naiwa-release `importer/BinBuilder.kt`
abstract final class BinBuilder {
  static Map<String, dynamic> _parseInfo(dynamic raw) {
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    if (raw is String && raw.isNotEmpty) {
      final obj = jsonDecode(raw);
      if (obj is Map<String, dynamic>) return obj;
      if (obj is Map) return Map<String, dynamic>.from(obj);
      throw ImportException('info 是字符串但不是合法 JSON，文件可能已损坏');
    }
    throw ImportException('bin 缺少 info 字段');
  }

  static AccountCredential parseCredential(List<int> binBytes) {
    final plain = XyCrypto.decrypt(binBytes);
    final obj = BonDecoder().decode(plain);
    if (obj is! Map) throw ImportException('bin 解码结果不是对象');
    final map = Map<String, dynamic>.from(obj);
    final info = _parseInfo(map['info']);
    if (info['encryptCombUser'] == null) {
      throw ImportException('bin 里没有登录凭据（encryptCombUser），无法反查区服');
    }
    return AccountCredential(
      platform: '${map['platform'] ?? 'hortor'}',
      platformExt: '${map['platformExt'] ?? 'mix'}',
      info: info,
      scene: map['scene'] ?? 0,
      referrerInfo: map['referrerInfo'] ?? '',
    );
  }

  static AccountCredential credentialFromCombUser(
    String combUser,
    int timestamp,
    String sign,
  ) =>
      AccountCredential(
        platform: 'hortor',
        platformExt: 'mix',
        info: {
          'encryptCombUser': combUser,
          'timestamp': timestamp,
          'sign': sign,
        },
        scene: 0,
        referrerInfo: '',
      );

  static num? _num(dynamic v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v);
    return null;
  }

  static Future<List<RoleInfo>> queryRoles(AccountCredential cred) async {
    await RoleAvatarCache.ensureLoaded();
    final payload = XyCrypto.encryptX(BonEncoder().encode(cred.toMap(null)));
    final res = await ImportHttp.post(
      XyEndpoints.serverList(),
      headers: {
        'Host': 'xxz-xyzw.hortorgames.com',
        'Referer': XyEndpoints.refererMinigame,
        'Content-Type': 'application/octet-stream',
        'User-Agent': XyEndpoints.uaMinigame,
      },
      body: payload,
    );
    if (res.status != 200) throw ImportException('查询区服失败 (HTTP ${res.status})');
    if (res.body.isEmpty) throw ImportException('查询区服返回空响应');

    final outerDyn = BonDecoder().decode(XyCrypto.decrypt(res.body));
    if (outerDyn is! Map) throw ImportException('响应解码失败');
    final outer = Map<String, dynamic>.from(outerDyn);
    final cmd = outer['cmd'] as String?;
    if (cmd != null && cmd.toLowerCase().contains('error')) {
      throw ImportException('服务端返回错误: $cmd');
    }

    final bodyBytes = outer['body'];
    if (bodyBytes is! Uint8List && bodyBytes is! List<int>) {
      throw ImportException('响应缺少 body。cmd=$cmd');
    }
    final bodyDyn = BonDecoder().decode(
      bodyBytes is Uint8List ? bodyBytes : Uint8List.fromList(bodyBytes as List<int>),
    );
    if (bodyDyn is! Map) throw ImportException('body 解码失败');
    final body = Map<String, dynamic>.from(bodyDyn);
    AppLog.i('import', 'serverlist body keys=${body.keys.take(24).join(",")}');
    final rawRoles = body['roles'] ?? body['roleList'] ?? body['roleMap'];
    final entries = <({String key, Map<String, dynamic> role})>[];
    if (rawRoles is Map) {
      rawRoles.forEach((key, v) {
        if (v is Map) {
          entries.add((key: '$key', role: Map<String, dynamic>.from(v)));
        }
      });
    } else if (rawRoles is List) {
      for (var i = 0; i < rawRoles.length; i++) {
        final v = rawRoles[i];
        if (v is Map) {
          entries.add((key: '$i', role: Map<String, dynamic>.from(v)));
        }
      }
    }
    if (entries.isEmpty) {
      throw ImportException('未找到角色列表，凭据可能已失效');
    }

    final out = <RoleInfo>[];
    var logged = false;
    for (final e in entries) {
      final r = _flattenRole(e.role);
      final zone = _zone(r, e.key);
      if (zone.sid == null) continue;
      final roleId = _num(r['roleId'] ?? r['id'] ?? r['uid'])?.toInt() ?? 0;
      final loginAt = r['loginAt'] ?? r['lastLogin'] ?? r['loginTime'];
      final avatar = _avatarUrl(r, roleId);
      final power = _num(r['power'] ?? r['fightPower'] ?? r['zhanli'])?.toInt() ?? 0;
      if (!logged || power >= 100000000) {
        logged = true;
        final fields = r.entries
            .map((kv) => '${kv.key}=${_dbg(kv.value)}')
            .take(24)
            .join(' ');
        AppLog.i(
          'import',
          'role key=${e.key} sid=${zone.sid} label=${zone.label} '
          'roleId=$roleId avatar=$avatar | $fields',
        );
      }
      out.add(
        RoleInfo(
          serverId: zone.sid!,
          roleId: roleId,
          name: '${r['name'] ?? r['nickname'] ?? r['roleName'] ?? '未命名'}',
          power: power,
          level: _num(r['level'] ?? r['lv'])?.toInt() ?? 0,
          loginAt: _loginAtText(loginAt),
          avatarUrl: avatar,
          serverLabel: zone.label,
        ),
      );
    }
    out.sort((a, b) => b.loginAt.compareTo(a.loginAt));
    await resolveAvatars(out);
    return out;
  }

  /// 校验缓存/已有 URL；没有真头像则留空，UI 显示本地默认头。
  static Future<void> resolveAvatars(List<RoleInfo> roles) async {
    await Future.wait(roles.map(_resolveOneAvatar));
  }

  static Future<void> _resolveOneAvatar(RoleInfo role) async {
    final cands = <String>[];
    void add(String? u) {
      if (u == null || u.isEmpty || cands.contains(u)) return;
      if (u.startsWith('http')) cands.add(u);
    }

    for (final p in (role.avatarUrl ?? '').split('|')) {
      final t = p.trim();
      if (t.startsWith('http')) add(RoleAvatarCache.normalize(t));
    }
    final cached = RoleAvatarCache.get(role.roleId);
    if (cached != null && cached.startsWith('http')) {
      role.avatarUrl = cached;
      return;
    }
    // 仅用已缓存的真头像；loginAt 试拼不可靠且拖慢导入，进游戏后再抓。

    for (final u in cands) {
      if (await _urlOk(u)) {
        role.avatarUrl = u;
        await RoleAvatarCache.put(role.roleId, u);
        AppLog.i('avatar', 'ok roleId=${role.roleId} $u');
        return;
      }
    }

    // 未进游戏前不写假 URL，UI 用本地默认头像 assets/images/default_avatar.jpg
    role.avatarUrl = null;
    AppLog.i('avatar', 'fallback roleId=${role.roleId} → 本地默认头');
  }

  static Future<bool> _urlOk(String url) async {
    try {
      final res = await ImportHttp.get(
        url,
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 Chrome/120.0.0.0 Mobile Safari/537.36',
          'Accept': 'image/*,*/*',
        },
      );
      return res.status == 200 && res.body.length > 200;
    } catch (_) {
      return false;
    }
  }

  static ({int? sid, String? label}) _zone(
    Map<String, dynamic> r,
    String key,
  ) {
    // 对照鸟哥之王 Pro：bin 用原始 serverId；展示只做 serverId-27，不用 serverList 名称（会错号）。
    int? bind = _num(r['serverId'] ?? r['sid'] ?? r['svrId'])?.toInt();
    bind ??= int.tryParse(key);
    if (bind == null || bind <= 0) return (sid: null, label: null);
    final shown = RoleInfo.displayZone(bind);
    final tag = RoleInfo.roleTag(bind);
    final label = tag == '①' ? '区服$shown' : '$tag区服$shown';
    return (sid: bind, label: label);
  }

  static Map<String, dynamic> _flattenRole(Map<String, dynamic> r) {
    var out = Map<String, dynamic>.from(r);
    for (final k in ['roleInfo', 'role', 'info', 'user', 'ext', 'data']) {
      final n = out[k];
      if (n is Map) {
        out = {...Map<String, dynamic>.from(n), ...out};
      }
    }
    return out;
  }

  /// 其他网页端头像：
  /// `https://mars-face.hortorgames.com/xxz-xyzw-head-img/release/{roleId}/{ver}.jpg`
  /// 查全服常无 headImg；有缓存则用缓存，否则进游戏后再抓。
  static String? _avatarUrl(Map<String, dynamic> r, int roleId) {
    final cands = <String>[];
    void add(String? u) {
      if (u == null || u.isEmpty || cands.contains(u)) return;
      cands.add(u);
    }

    for (final k in [
      'headImg',
      'headimg',
      'headUrl',
      'headImgUrl',
      'headimgurl',
      'customHead',
      'faceUrl',
    ]) {
      add(_resolveHead(r[k], roleId));
    }
    add(RoleAvatarCache.get(roleId));
    if (cands.isEmpty) return null;
    return cands.join('|');
  }

  static String? _marsFace(int roleId, int? ver) {
    if (roleId <= 0 || ver == null || ver <= 0) return null;
    return 'https://mars-face.hortorgames.com/xxz-xyzw-head-img/release/$roleId/$ver.jpg';
  }

  static String _dbg(dynamic v) {
    if (v == null) return 'null';
    if (v is BonDate) return 'BonDate(${v.millis})';
    return '$v(${v.runtimeType})';
  }

  static int? _headVer(dynamic v) {
    if (v == null || v is Map || v is List) return null;
    if (v is BonDate) {
      final m = v.millis;
      if (m <= 0) return null;
      return m > 20000000000 ? m ~/ 1000 : m;
    }
    final n = _num(v)?.toInt();
    if (n == null || n <= 0) return null;
    return n > 20000000000 ? n ~/ 1000 : n;
  }

  static String? _resolveHead(dynamic v, int roleId) {
    if (v == null || v is Map || v is List) return null;
    if (v is BonDate) return _marsFace(roleId, _headVer(v));
    var s = '$v'.trim();
    if (s.isEmpty || s == 'null' || s == '0') return null;
    if (s.startsWith('http://') || s.startsWith('https://')) {
      // 星驰会把路径拼到 -res；自定义头像实际在 mars-face。
      if (s.contains('xxz-xyzw-res.hortorgames.com') &&
          s.contains('xxz-xyzw-head-img')) {
        return s.replaceFirst(
          'xxz-xyzw-res.hortorgames.com',
          'mars-face.hortorgames.com',
        );
      }
      return s;
    }
    if (s.startsWith('//')) return 'https:$s';
    if (s.contains('xxz-xyzw-head-img') || s.contains('mars-face')) {
      if (!s.startsWith('/')) s = '/$s';
      return 'https://mars-face.hortorgames.com$s';
    }
    final ver = _headVer(v);
    if (ver != null) return _marsFace(roleId, ver);
    return null;
  }

  static String _loginAtText(dynamic v) {
    if (v == null) return '';
    if (v is BonDate) return '${v.millis}';
    return '$v';
  }

  static List<GeneratedBin> buildBins(
    AccountCredential cred,
    List<RoleInfo> roles,
  ) {
    final out = <GeneratedBin>[];
    for (var i = 0; i < roles.length; i++) {
      final role = roles[i];
      final bytes = XyCrypto.encryptLx(BonEncoder().encode(cred.toMap(role.serverId)));
      final safe = role.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final name =
          '${(i + 1).toString().padLeft(2, '0')}-${role.powerText()}-${role.zoneText}-${role.roleId}-$safe.bin';
      out.add(GeneratedBin(name, bytes, role));
    }
    return out;
  }
}
