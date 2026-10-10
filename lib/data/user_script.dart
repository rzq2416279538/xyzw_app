/// 对照 naiwa-release `data/Models.kt` 的 UserScript。
class UserScript {
  UserScript({
    required this.id,
    required this.name,
    required this.code,
    this.enabled = false,
    this.order = 0,
    this.locked = false,
    this.preset = false,
  });

  final String id;
  final String name;
  final String code;
  final bool enabled;
  final int order;
  final bool locked;
  final bool preset;

  String get displayName {
    final n = name.toLowerCase().endsWith('.js')
        ? name.substring(0, name.length - 3)
        : name;
    return n;
  }

  UserScript copyWith({
    String? name,
    String? code,
    bool? enabled,
    int? order,
    bool? locked,
    bool? preset,
  }) {
    return UserScript(
      id: id,
      name: name ?? this.name,
      code: code ?? this.code,
      enabled: enabled ?? this.enabled,
      order: order ?? this.order,
      locked: locked ?? this.locked,
      preset: preset ?? this.preset,
    );
  }

  Map<String, dynamic> toMeta() => {
        'id': id,
        'name': name,
        'enabled': enabled,
        'order': order,
        'locked': locked,
        'preset': preset,
      };

  factory UserScript.fromMeta(Map<String, dynamic> json, String code) =>
      UserScript(
        id: json['id'] as String,
        name: json['name'] as String,
        code: code,
        enabled: json['enabled'] as bool? ?? false,
        order: (json['order'] as num?)?.toInt() ?? 0,
        locked: json['locked'] as bool? ?? false,
        preset: json['preset'] as bool? ?? false,
      );
}
