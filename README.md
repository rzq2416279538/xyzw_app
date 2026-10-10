# 咸强之王

基于 Flutter 的游戏辅助壳：管理多个角色账号，在本地用 WebView 加载游戏前端，注入登录数据与用户脚本，方便多号切换与日常操作。

仓库：[rzq2416279538/xyzw_app](https://github.com/rzq2416279538/xyzw_app)

## 能做什么

- **角色管理**：导入角色（扫码 / 手机号 / `.bin`），列表展示头像、昵称、最近使用时间
- **一键进游戏**：本地 HTTP 提供游戏资源，WebView 加载；BIN 走本地文件注入，XHR 拦截完成登录
- **多会话**：已进入的账号可切换，不必每次从头加载（进程内保活）
- **脚本管理**：仅外部导入油猴脚本；支持全部开启 / 关闭，进游戏时以 `<script src>` 挂载
- **跨域代理**：脚本里的跨域请求经 Dart 桥转发，减少 CORS 限制
- **日志导出**：便于排查进游戏、脚本、头像等问题

## 技术结构（简要）

| 模块 | 说明 |
| --- | --- |
| `lib/ui/` | 首页、导入、脚本、游戏页 |
| `lib/core/local_http_server.dart` | 本地静态服务（独立 isolate） |
| `lib/core/inject_scripts.dart` | 兼容层、BIN、油猴垫片、角色桥 |
| `lib/core/script_cache.dart` | 用户脚本发布到 `userscripts/` |
| `lib/data/` | 账号与脚本持久化 |
| `assets/renderer/` | 游戏前端入口与 SDK 模拟层（正版引擎资源不入库） |
| `.github/workflows/ios-unsigned-ipa.yml` | GitHub Actions 打未签名 IPA，便于自签安装 |

## 环境要求

- Flutter 稳定版（建议与本机 `flutter doctor` 一致）
- **Android**：可直接 `flutter run` / 打 release APK
- **iOS**：需较新的 macOS + Xcode；本仓库提供 CI 未签名 IPA 流程，可用自签工具安装到自己的设备

## 本机准备

### 1. 游戏 renderer

仓库仅包含入口与模拟层（如 `index.html`、`hsdk-mock.js`、`patch.js` 等）。  
完整 Cocos 引擎与资源需自行放到应用缓存目录，或开发期放入 `assets/renderer/`（已被 `.gitignore` 忽略正版资源）。

文件名需与 `index.html` 中的引用一致。

### 2. 角色数据

通过 App 内「导入角色」获取区服登录用 `.bin`（或扫码 / 手机号流程）。账号数据保存在本机，勿提交到 Git。

## 运行

```bash
flutter pub get
flutter run          # Android 真机 / 模拟器
flutter build apk --release
```

## iOS 未签名包（GitHub Actions）

1. 将代码推送到本仓库  
2. GitHub → **Actions** → **iOS Unsigned IPA** → **Run workflow**  
3. 完成后下载 Artifact 中的 `咸强之王-unsigned.ipa`  
4. 使用自签工具 + 免费 Apple ID 安装到自己的 iPhone（证书约 7 天需重签）

## 使用提示

1. 资源未就绪时，首页会提示缺失项，请先补齐 renderer  
2. 导入角色后，点账号 → **启动 / 进入**  
3. 游戏地址应为 `http://localhost:<port>/`（不要用 `file://`）  
4. 脚本在「脚本管理」中导入 `.js` 并开启后，进入或刷新游戏生效  

## 说明

- 本项目为个人学习与自用辅助壳，不包含也不分发游戏正版客户端资源  
- 请遵守游戏与平台相关规定，账号与脚本风险自负  
