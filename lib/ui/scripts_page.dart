import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../data/script_store.dart';
import '../data/user_script.dart';
import 'app_theme.dart';
import 'ios_chrome.dart';

/// 脚本管理：仅外部导入，逐个开关 + 全部开关。
class ScriptsPage extends StatefulWidget {
  const ScriptsPage({super.key, required this.store});

  final ScriptStore store;

  @override
  State<ScriptsPage> createState() => _ScriptsPageState();
}

class _ScriptsPageState extends State<ScriptsPage> {
  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStore);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() => setState(() {});

  Future<void> _import() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['js'],
      allowMultiple: true,
      withData: false,
    );
    if (result == null) return;
    var n = 0;
    final sizes = <String>[];
    for (final f in result.files) {
      if (!f.name.toLowerCase().endsWith('.js')) continue;
      final path = f.path;
      if (path == null || path.isEmpty) continue;
      final file = File(path);
      if (!await file.exists()) continue;
      final raw = await file.readAsBytes();
      if (raw.isEmpty) continue;
      final code = utf8.decode(raw, allowMalformed: true);
      await widget.store.addScript(f.name, code, rawBytes: raw);
      sizes.add('${f.name} ${raw.length} 字节');
      n++;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          n > 0 ? '已导入 ${sizes.join('，')}' : '未选到有效的 .js 文件',
        ),
      ),
    );
  }

  Future<void> _confirmRemove(UserScript s) async {
    if (s.locked) return;
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('删除脚本'),
        content: Text('确定删除「${s.displayName}」？'),
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
    if (ok == true) await widget.store.remove(s.id);
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.store.scripts;
    final allOn = list.isNotEmpty && list.every((s) => s.enabled);
    return SoftBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: GlassAppBar(
          title: const Text('脚本管理'),
          leading: IosIconButton(
            icon: CupertinoIcons.back,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          actions: [
            IosIconButton(
              tooltip: '导入脚本',
              icon: CupertinoIcons.add_circled_solid,
              color: AppTheme.green,
              onPressed: _import,
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: Padding(
          padding: EdgeInsets.only(
            top: MediaQuery.paddingOf(context).top + kToolbarHeight,
          ),
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 10, 16, 8),
                child: Text(
                  '导入油猴 .js，开启后进入或刷新游戏时自动加载。可逐个开关，或用全部开关一次控制。',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: GlassCard(
                  padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '全部脚本',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      Text(
                        allOn ? '已全部开启' : '已全部关闭或未全开',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      CupertinoSwitch(
                        value: allOn,
                        activeTrackColor: AppTheme.green,
                        onChanged: list.isEmpty
                            ? null
                            : (v) => widget.store.setAllEnabled(v),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? const _Empty()
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                        itemCount: list.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final s = list[i];
                          return _ScriptCard(
                            script: s,
                            onToggle: (v) => widget.store.toggle(s.id, v),
                            onDelete: () => _confirmRemove(s),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.tray,
              size: 40,
              color: AppTheme.textSecondary,
            ),
            SizedBox(height: 12),
            Text(
              '暂无脚本',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 6),
            Text(
              '点右上角 + 导入 .js',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScriptCard extends StatelessWidget {
  const _ScriptCard({
    required this.script,
    required this.onToggle,
    this.onDelete,
  });

  final UserScript script;
  final ValueChanged<bool> onToggle;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onLongPress: onDelete,
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  script.displayName,
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
                  '${script.code.length} 字符${script.enabled ? ' · 已启用' : ''}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (onDelete != null)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: Size.zero,
              onPressed: onDelete,
              child: const Icon(
                CupertinoIcons.trash,
                size: 20,
                color: AppTheme.danger,
              ),
            ),
          CupertinoSwitch(
            value: script.enabled,
            activeTrackColor: AppTheme.green,
            onChanged: script.locked ? null : onToggle,
          ),
        ],
      ),
    );
  }
}
