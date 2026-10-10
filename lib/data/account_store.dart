import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'account.dart';

/// 对照 naiwa-release `data/AppStore.kt` 的账号增删与持久化（一期精简版）。
class AccountStore extends ChangeNotifier {
  AccountStore();

  static const _prefsKey = 'accounts_v1';
  static const _uuid = Uuid();

  final List<Account> _accounts = [];
  List<Account> get accounts => List.unmodifiable(_accounts);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    _accounts.clear();
    if (raw != null && raw.isNotEmpty) {
      _accounts.addAll(Account.decodeList(raw));
    }
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, Account.encodeList(_accounts));
  }

  Future<Account> addFromBin(
    String name,
    List<int> bytes, {
    String? roleName,
    String? avatarUrl,
  }) async {
    final item = Account(
      id: _uuid.v4(),
      name: name,
      binHex: Account.bytesToHex(bytes),
      order: (_accounts.isEmpty
              ? 0
              : _accounts.map((e) => e.order).reduce((a, b) => a > b ? a : b)) +
          1,
      lastUsedAt: null,
      roleName: roleName,
      avatarUrl: avatarUrl,
    );
    _accounts.add(item);
    await _save();
    notifyListeners();
    return item;
  }

  Future<void> remove(String id) async {
    _accounts.removeWhere((e) => e.id == id);
    await _save();
    notifyListeners();
  }

  Future<void> touchLastUsed(String id) async {
    final i = _accounts.indexWhere((e) => e.id == id);
    if (i < 0) return;
    _accounts[i] = _accounts[i].copyWith(lastUsedAt: DateTime.now());
    await _save();
    notifyListeners();
  }

  Future<void> updateProfile(
    String id, {
    String? roleName,
    String? avatarUrl,
  }) async {
    final i = _accounts.indexWhere((e) => e.id == id);
    if (i < 0) return;
    final cur = _accounts[i];
    final next = cur.copyWith(
      roleName: roleName?.trim().isEmpty == true ? cur.roleName : roleName,
      avatarUrl: avatarUrl?.trim().isEmpty == true ? cur.avatarUrl : avatarUrl,
    );
    if (next.roleName == cur.roleName && next.avatarUrl == cur.avatarUrl) {
      return;
    }
    _accounts[i] = next;
    await _save();
    notifyListeners();
  }

  Account? byId(String id) {
    for (final a in _accounts) {
      if (a.id == id) return a;
    }
    return null;
  }
}
