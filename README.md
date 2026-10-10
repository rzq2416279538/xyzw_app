# 咸强之王

面向 **iOS** 的 Flutter 游戏辅助壳：管理多个角色，通过本地 WebView（WKWebView）加载游戏前端，完成登录注入与用户脚本挂载。

> **定位**：本仓库以 **iOS 真机体验** 为第一目标；Android 可作对照与备用，后续功能与优化均优先服务 iOS。

仓库：[rzq2416279538/xyzw_app](https://github.com/rzq2416279538/xyzw_app)

## 项目是什么

面向「咸鱼之王」类网页/壳端玩法的 **多账号启动器**。  
不重新实现游戏逻辑，而是：

1. 在本地展开游戏 renderer，用 HTTP 提供静态资源（iOS 使用 `127.0.0.1`）  
2. 用 WebView 打开游戏页（避免 `file://` 限制）  
3. 把当前角色的登录 BIN 注入页面，拦截登录请求完成进服  
4. 按需加载用户导入的油猴脚本  

目标是：**列表管号 → 一点进游戏 → 脚本可选启用**，在 iPhone 上尽量流畅、稳定。

## 已实现能力

- **角色管理**：导入角色（扫码 / 手机号 / `.bin`），列表展示头像、昵称、最近使用  
- **进游戏**：本地 HTTP + WKWebView；BIN 优先由 Dart 注入二进制缓冲（兼容 iOS）  
- **多会话**：同一进程内可保留多个已进入账号，切换时尽量不销毁 WebView  
- **脚本管理**：外部导入 `.js`；支持单个 / 全部开关；以 `<script src>` 挂载  
- **跨域代理**：脚本跨域请求经应用内桥转发  
- **诊断日志**：内存环形缓冲 + iOS Documents 落盘；首页可导出，便于真机反馈问题  

## 技术路线（iOS 优先）

| 层级 | 方案 |
| --- | --- |
| UI | Flutter（Cupertino / 实色界面，减少毛玻璃与重动画） |
| 游戏容器 | `webview_flutter` → iOS **WKWebView** |
| 资源服务 | Dart `HttpServer`（isolate）；iOS 基址 `http://127.0.0.1` |
| 登录 | BIN 文件暂存 + **base64 注入缓冲** + XHR/fetch 拦截 |
| 脚本 | GM 垫片 + `userscripts/`；跨域走 `XyzwBridge` |
| 构建 | GitHub Actions 打未签名 IPA，本机自签安装调试 |

主要代码：`lib/ui/`、`lib/core/`、`lib/data/`、`assets/renderer/`（完整引擎资源需本机自备，默认不进 Git）。

## 使用说明

### 环境

- Flutter 稳定版  
- **iOS**：较新 Xcode / CI 出包后自签安装到 iPhone  
- Android：可选，仅作参考验证  

### 游戏资源

仓库含入口与 SDK 模拟层。完整 Cocos 资源需自行放入应用缓存或开发期 `assets/renderer/`（正版资源 `.gitignore` 忽略）。文件名需与 `index.html` 引用一致。

### 运行 / 出包

```bash
flutter pub get
# iOS（需 macOS + Xcode）
flutter run -d <iphone>
# 或使用仓库 Actions：iOS Unsigned IPA
```

### 基本流程（iOS）

1. **首次打开**：若弹出「本地网络 / 无线局域网」请点 **允许**（启动时会主动触发，勿等到导入时再点）  
2. 检查 renderer 就绪  
3. 导入角色  
4. 点账号 → 启动 / 进入  
5. 需要时在「脚本管理」导入并开启脚本  

### 反馈问题（iOS）

1. 复现后点首页 **导出日志**  
2. 日志在「文件」App → 我的 iPhone → 咸强之王（`咸强之王-日志-*.txt` / `xyzw_latest.log`），并已复制到剪贴板  
3. 将日志发给开发者；优先搜索 `[DIAG]`、`拦截XHR`、`BIN`、`roleId`  

## 无自有服务器时的「在线更新」

库存 iOS **不能**像安卓那样静默覆盖安装（无企业签 / MDM / 越狱时）。没有自己的后台也能用这些免费托管：

| 方案 | 要不要服务器 | 体验 | 说明 |
| --- | --- | --- | --- |
| **GitHub Releases** | 否（用 GitHub） | 手动下 IPA → 自签安装 | Actions 产物挂 Release；改版只发新包 |
| **SideStore / AltStore 源** | 否（源 JSON 可放 GitHub Pages） | 手机里点更新 | 适合长期自用；需电脑/VPN 刷新签名 |
| **TestFlight** | 否（Apple 托管） | 接近自动更新 | 需 **99 美元/年** Apple 开发者账号 |
| **Diawi / Installonair 等** | 否（第三方托管） | 扫码安装 | 链接有时效；仍要签名有效 |

推荐路径（无服务器、无付费账号）：

1. Actions 打未签名 IPA → 上传到 **GitHub Release**  
2. 本机自签安装；有 SideStore 时可加一个 **AltStore 源**（一个 JSON，托管在 GitHub Pages）方便以后点更新  
3. 后续可在 App 内加「检查更新」：读 GitHub 上的 `version.json`（仍零服务器）

**结论**：没有后台也能「在线发版」；真正「打开 App 自动装上新版本」在未越狱 iOS 上做不到，除非 TestFlight / 企业签 / 系统级安装渠道。

## 说明

- 个人学习与自用辅助壳，不分发游戏正版客户端资源  
- 请遵守游戏与平台规定；账号与第三方脚本风险自负  
