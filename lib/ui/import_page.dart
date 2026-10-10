import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../data/account_store.dart';
import '../data/role_avatar_cache.dart';
import '../importer/import_controller.dart';
import 'app_theme.dart';
import 'ios_chrome.dart';
import 'net_avatar.dart';

enum _ImportTab { scan, sms, bin }

/// 对照 naiwa-release `ui/ImportScreen.kt` + 鸟哥之王 Pro `qrcode.html`
class ImportPage extends StatefulWidget {
  const ImportPage({super.key, required this.store});

  final AccountStore store;

  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  late final ImportController _vm;
  _ImportTab _tab = _ImportTab.scan;
  var _imported = 0;

  @override
  void initState() {
    super.initState();
    _vm = ImportController()..addListener(_onVm);
  }

  @override
  void dispose() {
    _vm.removeListener(_onVm);
    _vm.dispose();
    super.dispose();
  }

  void _onVm() {
    if (mounted) setState(() {});
  }

  Future<void> _importSelected() async {
    final bins = _vm.buildSelected();
    for (final b in bins) {
      final avatar = b.role.primaryAvatar;
      if (avatar != null &&
          avatar.startsWith('http') &&
          b.role.roleId > 0) {
        await RoleAvatarCache.put(b.role.roleId, avatar);
      }
      await widget.store.addFromBin(
        b.fileName,
        b.bytes,
        roleName: b.role.name,
        avatarUrl: avatar,
      );
    }
    setState(() {
      _imported = bins.length;
    });
    _vm.reset();
  }

  Future<void> _pickBinQuery() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null || bytes.isEmpty) {
      _vm.message = '文件读取失败';
      setState(() {});
      return;
    }
    await _vm.queryFromBin(bytes);
  }

  @override
  Widget build(BuildContext context) {
    return SoftBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: GlassAppBar(
          title: const Text('导入角色'),
          leading: IosIconButton(
            icon: CupertinoIcons.back,
            color: AppTheme.blue,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        body: Padding(
          padding: EdgeInsets.only(
            top: MediaQuery.paddingOf(context).top + kToolbarHeight,
          ),
          child: _vm.stage == ImportStage.picking
              ? _RolePicker(
                  vm: _vm,
                  onImport: _importSelected,
                  onCancel: _vm.reset,
                )
              : _imported > 0
                  ? _DoneCard(
                      count: _imported,
                      onContinue: () => setState(() => _imported = 0),
                      onFinish: () => Navigator.of(context).maybePop(),
                    )
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                          child: SizedBox(
                            width: double.infinity,
                            child: CupertinoSlidingSegmentedControl<_ImportTab>(
                              groupValue: _tab,
                              backgroundColor:
                                  AppTheme.fill.withValues(alpha: 0.12),
                              thumbColor: Colors.white.withValues(alpha: 0.92),
                              children: const {
                                _ImportTab.scan: Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: Text('微信扫码', style: TextStyle(fontSize: 13)),
                                ),
                                _ImportTab.sms: Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: Text('手机号', style: TextStyle(fontSize: 13)),
                                ),
                                _ImportTab.bin: Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: Text('bin 文件', style: TextStyle(fontSize: 13)),
                                ),
                              },
                              onValueChanged: (v) {
                                if (v == null) return;
                                setState(() {
                                  _tab = v;
                                  _vm.reset();
                                });
                              },
                            ),
                          ),
                        ),
                        if (_vm.message.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                _vm.message,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.blue,
                                ),
                              ),
                            ),
                          ),
                        Expanded(
                          child: switch (_tab) {
                            _ImportTab.scan => _ScanPane(vm: _vm),
                            _ImportTab.sms => _SmsPane(vm: _vm),
                            _ImportTab.bin => _BinPane(
                                vm: _vm,
                                onQuery: _pickBinQuery,
                              ),
                          },
                        ),
                      ],
                    ),
        ),
      ),
    );
  }
}

class _DoneCard extends StatelessWidget {
  const _DoneCard({
    required this.count,
    required this.onContinue,
    required this.onFinish,
  });
  final int count;
  final VoidCallback onContinue;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: GlassCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(CupertinoIcons.checkmark_seal_fill,
                    color: AppTheme.green, size: 22),
                const SizedBox(width: 8),
                Text(
                  '已导入 $count 个角色',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '返回列表即可进入游戏。',
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: onContinue,
                  child: const Text('继续导入'),
                ),
                const SizedBox(width: 8),
                CupertinoButton.filled(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  onPressed: onFinish,
                  child: const Text('完成', style: TextStyle(fontSize: 15)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanPane extends StatelessWidget {
  const _ScanPane({required this.vm});
  final ImportController vm;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          GlassCard(
            child: Column(
              children: [
                if (vm.qrBytes != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 240,
                      height: 240,
                      color: Colors.white,
                      padding: const EdgeInsets.all(10),
                      child: Image.memory(vm.qrBytes!, fit: BoxFit.contain),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    vm.qrHint,
                    style: const TextStyle(fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  CupertinoButton(
                    onPressed: vm.startQrLogin,
                    child: const Text('刷新二维码'),
                  ),
                ] else ...[
                  const SizedBox(height: 28),
                  if (vm.busy)
                    const Column(
                      children: [
                        CupertinoActivityIndicator(),
                        SizedBox(height: 12),
                        Text('获取中...', style: TextStyle(fontSize: 14)),
                      ],
                    )
                  else
                    CupertinoButton.filled(
                      onPressed: vm.startQrLogin,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 10,
                      ),
                      child: const Text('获取二维码', style: TextStyle(fontSize: 15)),
                    ),
                  const SizedBox(height: 20),
                ],
              ],
            ),
          ),
          const Spacer(),
          const Text(
            '用微信扫描上方二维码。授权后会读取该账号下全部区服角色，并生成对应 bin。',
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _SmsPane extends StatelessWidget {
  const _SmsPane({required this.vm});
  final ImportController vm;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          GlassCard(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Column(
              children: [
                CupertinoTextField(
                  placeholder: '手机号',
                  keyboardType: TextInputType.phone,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.fill.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  onChanged: (v) {
                    final d = v.replaceAll(RegExp(r'\D'), '');
                    vm.mobile = d.length <= 11 ? d : d.substring(0, 11);
                  },
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: CupertinoTextField(
                        placeholder: '验证码',
                        keyboardType: TextInputType.number,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.fill.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        onChanged: (v) {
                          final d = v.replaceAll(RegExp(r'\D'), '');
                          vm.smsCode =
                              d.length <= 6 ? d : d.substring(0, 6);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      onPressed:
                          vm.countdown == 0 && !vm.busy ? vm.sendSms : null,
                      child: Text(
                        vm.countdown > 0 ? '${vm.countdown}s' : '发送验证码',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: CupertinoButton.filled(
                    onPressed: vm.busy ? null : vm.loginBySms,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: vm.busy
                        ? const CupertinoActivityIndicator(color: Colors.white)
                        : const Text('登录并查询区服', style: TextStyle(fontSize: 15)),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          const Text(
            '使用游戏绑定的手机号登录，读取该账号下全部区服角色。',
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _BinPane extends StatelessWidget {
  const _BinPane({
    required this.vm,
    required this.onQuery,
  });
  final ImportController vm;
  final VoidCallback onQuery;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CupertinoButton.filled(
                  onPressed: vm.busy ? null : onQuery,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: vm.busy
                      ? const CupertinoActivityIndicator(color: Colors.white)
                      : const Text('选择 bin，查询全服角色',
                          style: TextStyle(fontSize: 15)),
                ),
                const SizedBox(height: 8),
                const Text(
                  '读取文件里的登录凭据，查询该账号下全部区服角色后再勾选导入。',
                  style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RolePicker extends StatelessWidget {
  const _RolePicker({
    required this.vm,
    required this.onImport,
    required this.onCancel,
  });
  final ImportController vm;
  final VoidCallback onImport;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '已选 ${vm.selected.length}/${vm.roles.length}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                onPressed: () =>
                    vm.selectAll(vm.selected.length < vm.roles.length),
                child: Text(
                  vm.selected.length < vm.roles.length ? '全选' : '全不选',
                  style: const TextStyle(fontSize: 15),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            itemCount: vm.roles.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final role = vm.roles[i];
              final on = vm.selected.contains(i);
              return GlassCard(
                onTap: () => vm.toggle(i),
                padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
                child: Row(
                  children: [
                    Icon(
                      on
                          ? CupertinoIcons.checkmark_circle_fill
                          : CupertinoIcons.circle,
                      color: on ? AppTheme.blue : AppTheme.textSecondary,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    NetAvatar(
                      url: role.avatarUrl,
                      initial: role.name.isNotEmpty
                          ? role.name.characters.first
                          : '?',
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            role.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${role.zoneText} · 战力${role.powerText()} · ID${role.roleId}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Row(
            children: [
              Expanded(
                child: CupertinoButton(
                  color: AppTheme.fill.withValues(alpha: 0.12),
                  onPressed: onCancel,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: const Text(
                    '取消',
                    style: TextStyle(fontSize: 15, color: AppTheme.text),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: CupertinoButton.filled(
                  onPressed: vm.selected.isEmpty ? null : onImport,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    '导入 ${vm.selected.length} 个',
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
