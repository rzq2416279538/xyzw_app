import 'dart:convert';
import 'dart:typed_data';

/// 对照 naiwa-release `data/Models.kt` 的 AccountItem。
/// binHex 是登录请求体的十六进制串，注入到 window.__activeBinHex。
class Account {
  Account({
    required this.id,
    required this.name,
    required this.binHex,
    this.order = 0,
    this.roleName,
    this.avatarUrl,
    this.lastUsedAt,
  });

  final String id;
  final String name;
  final String binHex;
  final int order;

  /// 游戏内角色名（登录后由桥接回写，可选）
  final String? roleName;

  /// 游戏内头像 URL（可选）
  final String? avatarUrl;

  /// 最近进入游戏时间
  final DateTime? lastUsedAt;

  String get fileLabel =>
      name.toLowerCase().endsWith('.bin') ? name.substring(0, name.length - 4) : name;

  /// 列表优先显示游戏昵称，否则 bin 文件名
  String get displayName {
    final role = roleName?.trim();
    if (role != null && role.isNotEmpty) return role;
    return fileLabel;
  }

  int get sizeBytes => binHex.length ~/ 2;

  Account copyWith({
    String? id,
    String? name,
    String? binHex,
    int? order,
    String? roleName,
    String? avatarUrl,
    DateTime? lastUsedAt,
    bool clearRoleName = false,
    bool clearAvatarUrl = false,
  }) {
    return Account(
      id: id ?? this.id,
      name: name ?? this.name,
      binHex: binHex ?? this.binHex,
      order: order ?? this.order,
      roleName: clearRoleName ? null : (roleName ?? this.roleName),
      avatarUrl: clearAvatarUrl ? null : (avatarUrl ?? this.avatarUrl),
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'bin': binHex,
        'order': order,
        if (roleName != null) 'roleName': roleName,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
        if (lastUsedAt != null) 'lastUsedAt': lastUsedAt!.millisecondsSinceEpoch,
      };

  factory Account.fromJson(Map<String, dynamic> json) => Account(
        id: json['id'] as String,
        name: json['name'] as String,
        binHex: json['bin'] as String,
        order: (json['order'] as num?)?.toInt() ?? 0,
        roleName: json['roleName'] as String?,
        avatarUrl: json['avatarUrl'] as String?,
        lastUsedAt: json['lastUsedAt'] is num
            ? DateTime.fromMillisecondsSinceEpoch(
                (json['lastUsedAt'] as num).toInt(),
              )
            : null,
      );

  static Uint8List hexToBytes(String hex) {
    final s = hex.replaceAll(RegExp(r'\s'), '');
    final out = Uint8List(s.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  static String bytesToHex(List<int> bytes) {
    const digits = '0123456789abcdef';
    final out = StringBuffer();
    for (final b in bytes) {
      out.write(digits[(b >> 4) & 0x0f]);
      out.write(digits[b & 0x0f]);
    }
    return out.toString();
  }

  static String encodeList(List<Account> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());

  static List<Account> decodeList(String raw) {
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => Account.fromJson(e as Map<String, dynamic>)).toList();
  }
}
