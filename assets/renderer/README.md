# renderer 目录说明

对照上游：
https://github.com/gterryd/naiwa-release/blob/main/app/src/main/assets/renderer/README.md

这里放游戏前端运行所需的文件。仓库里只保留本项目和 SDK 模拟层相关部分，
**游戏客户端本体不在仓库内**，版权归原开发商，需要你自己准备。

## 仓库内已包含

| 文件 | 说明 |
| --- | --- |
| `index.html` | 页面入口 |
| `hsdk-mock.js` | Hortor SDK 浏览器端模拟层 |
| `patch.js` | 运行期补丁 |
| `cocos-bundle-patch.js` | Cocos bundle 远程加载补丁 |
| `naiwa-uifix.css` | 修正 body flex 布局 |

首次启动时会复制到应用缓存目录（见 `RendererCache`），由 `LocalHttpServer` 以 `http://127.0.0.1` 提供。

## 游戏本体（本地开发）

关键引擎文件可从 [xyzw_web_helper](https://github.com/w1249178256/xyzw_web_helper) 的 `public/game/` 拷到本目录（**不入库**，见根目录 `.gitignore`）：

```
cocos2d-js-min.a5841.js
main.2a00e.js
game-defines.a175e.js
src/settings.da7ef.js
style-mobile.1777a.css
assets/ …
```

**不要覆盖本目录的壳补丁**（对照 [naiwa-release](https://github.com/gterryd/naiwa-release)）：

| 保留（naiwa） | 勿用 web_helper 覆盖 |
| --- | --- |
| `patch.js` | web 版含反调试/完整性校验，WebView 调试下会进 LoadingError |
| `hsdk-mock.js` | Android 壳登录模拟 |
| `cocos-bundle-patch.js` | `.jsc` XXTEA 远程加载 |
| `naiwa-uifix.css` / `index.html` | 壳入口加载顺序 |

可运行对照：「鸟哥之王 Pro」APK 的 `assets/www/`（`HSDK.turnpass.min.js`、`internal` 的 `a0340` 资源、`favicon`）。  
Pro 包内 **不含** `patch.js`/`main.js`（运行时另有来源），故壳补丁仍用 naiwa 的 `patch.js` + `hsdk-mock.js`。

`_hortor_callOnLoad` 必须在 CDN launcher 挂载后再发 SDK 就绪信号，否则 HotUpdate → LoadingError。

首次启动会复制到应用 Support 下的 `renderer/`（`RendererCache` stamp `.copied_v7`）。

文件名 hash 必须与 `index.html` 引用一致。缺少关键文件时 App 会显示占位说明。
