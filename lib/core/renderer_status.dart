import 'dart:io';

/// 检查一期进游戏所需的关键文件是否齐全。
/// 文件名对照 naiwa-release `assets/renderer/index.html` 当前引用。
class RendererStatus {
  RendererStatus({
    required this.root,
    required this.missing,
    required this.present,
  });

  final Directory root;
  final List<String> missing;
  final List<String> present;

  bool get isReady => missing.isEmpty;

  /// index.html 中硬编码引用 + 入库 SDK 文件
  static const requiredRelativePaths = [
    'index.html',
    'patch.js',
    'cocos-bundle-patch.js',
    'hsdk-mock.js',
    'naiwa-uifix.css',
    'src/settings.da7ef.js',
    'game-defines.a175e.js',
    'main.2a00e.js',
    'cocos2d-js-min.a5841.js',
    'style-mobile.1777a.css',
  ];

  static Future<RendererStatus> inspect(Directory root) async {
    final missing = <String>[];
    final present = <String>[];
    for (final rel in requiredRelativePaths) {
      final local = rel.replaceAll('/', Platform.pathSeparator);
      final f = File('${root.path}${Platform.pathSeparator}$local');
      if (await f.exists()) {
        present.add(rel);
      } else {
        missing.add(rel);
      }
    }
    return RendererStatus(root: root, missing: missing, present: present);
  }

  String describe() {
    if (isReady) {
      return 'renderer 资源就绪（${present.length} 个关键文件）';
    }
    final buf = StringBuffer()
      ..writeln('缺少游戏前端资源，无法加载 index.html 完整运行。')
      ..writeln()
      ..writeln('缓存目录：')
      ..writeln(root.path)
      ..writeln()
      ..writeln('已具备：')
      ..writeln(present.isEmpty ? '（无）' : present.map((e) => '  ✓ $e').join('\n'))
      ..writeln()
      ..writeln('仍缺少：')
      ..writeln(missing.map((e) => '  ✗ $e').join('\n'))
      ..writeln()
      ..writeln('请从官方客户端提取上述文件（及 assets/ 等依赖）放入缓存目录，')
      ..writeln('或开发期放入 assets/renderer/ 后清缓存重装。')
      ..writeln('详见 assets/renderer/README.md 与 docs/DEV_PROMPT.md。')
      ..writeln('对照：https://github.com/gterryd/naiwa-release/blob/main/app/src/main/assets/renderer/README.md');
    return buf.toString();
  }
}
