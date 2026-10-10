# 咸强之王

Flutter 游戏辅助壳：在手机上管理多个角色，通过本地 WebView 加载游戏前端，完成登录注入与用户脚本挂载。

## 项目是什么

面向「咸鱼之王」类网页/壳端玩法的 **多账号启动器**。  
不重新实现游戏逻辑，而是：

1. 在本地展开游戏 renderer，用 HTTP 提供静态资源  
2. 用 WebView 打开游戏页（避免 `file://` 限制）  
3. 把当前角色的登录 BIN 交给页面，拦截登录请求完成进服  
4. 按需加载用户导入的油猴脚本  

目标是：**列表管号 → 一点进游戏 → 脚本可选启用**，体验接近常见原生壳，但用 Flutter 跨端实现（当前以 Android 为主）。

## 已实现能力

- **角色管理**：导入角色（扫码 / 手机号 / `.bin`），列表展示头像、昵称、最近使用  
- **进游戏**：本地 HTTP + WebView；BIN 以文件方式提供给页面，经 XHR 拦截完成登录  
- **多会话**：同一进程内可保留多个已进入账号，切换时尽量不销毁 WebView  
- **脚本管理**：仅外部导入 `.js`；支持单个开关与全部开关；进游戏时以 `<script src>` 挂载  
- **跨域代理**：脚本跨域请求经应用内桥转发，减轻浏览器 CORS 限制  
- **日志导出**：便于排查进服、脚本、头像抓取等问题  
- **资源预热与缓存**：首页预拉关键引擎文件；带 hash 的静态资源使用较长缓存策略  

## 技术路线

| 层级 | 方案 |
| --- | --- |
| UI | Flutter（偏 iOS 风格实色界面） |
| 游戏容器 | `webview_flutter`（Android Hybrid Composition） |
| 资源服务 | Dart `HttpServer`，独立 isolate 读盘，根目录为本地 renderer 缓存 |
| 登录 | 角色 BIN → 本地路径 `/__xyzw/bin/...` → 页面拉取；XHR 拦截登录接口 body |
| 脚本 | GM 兼容垫片 + `userscripts/` 文件发布；跨域走 `XyzwBridge` |
| 数据 | 本机持久化账号与脚本元数据（不含正版游戏大资源入库） |

主要代码位置：

- `lib/ui/`：首页、导入、脚本、游戏页  
- `lib/core/local_http_server.dart`：本地静态服务  
- `lib/core/inject_scripts.dart`：注入与兼容脚本  
- `lib/core/script_cache.dart` / `renderer_cache.dart`：脚本发布与 renderer 缓存  
- `lib/data/`：账号、脚本存储  
- `assets/renderer/`：入口页与 SDK 模拟层（完整引擎资源需本机自备，默认不进 Git）  

实现思路对齐常见原生壳（本地 HTTP + WebView + 注入），用 Flutter 重做壳层与账号流程。

## 使用说明

### 环境

- 已安装 Flutter 稳定版  
- Android SDK / 真机或模拟器（推荐真机）  

### 游戏资源

仓库只带入口与模拟层（如 `index.html`、`hsdk-mock.js`、`patch.js` 等）。  
完整 Cocos 引擎与资源文件需自行放到应用可写的 renderer 目录，或开发期放入 `assets/renderer/`（正版资源已被 `.gitignore` 忽略）。  
文件名需与 `index.html` 中的引用一致。

### 运行

```bash
flutter pub get
flutter run
# 或
flutter build apk --release
```

### 基本流程

1. 首次启动会检查 renderer 是否就绪  
2. 「导入角色」加入账号  
3. 点账号 → 启动 / 进入游戏  
4. 需要脚本时在「脚本管理」导入 `.js` 并开启  

进游戏后地址应为 `http://localhost:<端口>/`。

## 说明

- 本项目为个人学习与自用辅助壳，不包含、也不分发游戏正版客户端资源  
- 请遵守游戏与平台相关规定；账号与第三方脚本风险自负  
