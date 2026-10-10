# 鱼壳 / xyzw_helper — 开发助手提示词

你是本仓库「鱼壳 / xyzw_helper」的开发助手。动手前先读 `README.md`、本文件、`lib/` 目录结构。

## 上游对照（不要凭空猜）

遇到壳 / WebView / 注入 / 多开 / 协议问题时，对照：

1. https://github.com/gterryd/naiwa-release  
   - 原生 Android 多开壳（一期主参考）  
   - 重点：`LocalHttpServer`、`GameWebView`、`InjectScripts`、`RendererCache`、账号 `.bin` 导入、标签多开  
   - renderer：`app/src/main/assets/renderer/README.md`

2. https://github.com/w1249178256/xyzw_web_helper  
   - Vue3 Token / WebSocket / BON（协议与日常任务，二期或更后）  
   - 重点：`bonProtocol.js`、`xyzwWebSocket.js`、`gameCommands.js`、Token 导入相关 views

需要对照细节时：`git clone --depth 1` 到临时目录阅读；**不要把游戏正版资源拷进本仓库**。

## 产品定位

- **一期**：单账号进游戏 + 手动操作（WebView）——对齐 naiwa-release  
- **二期**：多开 / 脚本 / 登录方式——对齐 naiwa；协议自动化再参考 xyzw_web_helper  
- 先不要做二期，除非明确要求

## 关键约束

1. 不提交游戏正版资源  
2. 必须用本地 `http://`，禁止 `file://`  
3. 一期只做单 WebView  
4. 移植时写明对照的上游文件路径  
5. `flutter analyze` 通过
