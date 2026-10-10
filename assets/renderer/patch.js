// ====== 解密后的 patch.js 混淆代码（完整版）======
// 来源: patch_decoded.js + 复制补丁_decoded.js 整合
// 解密自: base64 + XOR("LDIH2HK5") + Caesar(-3) + Unicode转义 + XOR数值 + 字符串反转

// ----- 字符串索引辅助函数 -----
function wrapyWswPxhD(i) {
  return strJstSlHlf[i];
}

// ----- 字符串常量表 -----
const strJstSlHlf = [
  "0",
  "[Patch] define called for:",
  "[Patch] require called for:",
  "[Patch] Error executing module factory for:",
  "undefined",
  "loadAny",
  "loadBundle",
  "function",
  "",
  "function(){}",
  "[Patch] 检测到尝试禁用 ",
  ", 已拦截并保持原始功能",
  "[Patch] cc.assetManager (loadAny, loadBundle) 已保护",
  "_updateRenderData",
  "[Patch] RenderFlow._updateRenderData 已保护",
];

// ----- wx 模拟 -----
window.wx = {
  getSystemInfo() {},
  getStorageInfo() {},
  onShow(callback) {
    setTimeout(() => {
      callback({ scene: wrapyWswPxhD(0), query: {}, shareTicket: [] });
    }, 1000);
  },
  onHide(callback) {},
};

// ----- HSDK 基础模拟 -----
window.HSDK = {
  onLogin(data) {
    setTimeout(() => {
      data.listener({ userSdk: { isNewUser: false } });
    }, 1000);
  },
  reportLoginState() {},
  onAddictionQuit() {},
  getGsSetting() {
    return {};
  },
};

// ----- TGA / Hortor SDK Mock -----
var tgaMock = { track() {}, tga: null };
tgaMock.tga = tgaMock; // 自引用
window.__HORTOR_SDK__ = { tga: tgaMock };

console.log("[patch.js] SDK Mock initialized");
// 注意：不要再写 window._hsdkInit = 1 / checkUpdate = 1。
// 新版 CDN launcher（日志 platformTagTime 2025-07）会把「真值」当成
// 「已初始化、跳过挂载 _hortor_callOnLoad」→ HotUpdate 0ms 结束 → LoadingError /
// 「正在加载平台」。实测 12s 后仍 callOnLoad=undefined、signaled=false。
// 真正的 SDK 就绪由 hsdk-mock 在检测到 _hortor_callOnLoad 后发信号。

// ----- define() 模拟（用于 Cocos 模块系统）-----
window.define = function (name, func) {
  console.log(wrapyWswPxhD(1), name);
  var module = { exports: {} };
  for (var dcBzsvBpOy = 0; dcBzsvBpOy < 0; dcBzsvBpOy++) {} // 空循环(混淆用)
  var require =
    window.require ||
    function (path) {
      console.warn(wrapyWswPxhD(2), path);
      return {};
    };
  try {
    func(require, module, module.exports);
  } catch (e) {
    console.error(wrapyWswPxhD(3), name, e);
  }
};

// ----- 保护 cc.assetManager.loadAny/loadBundle 不被篡改 -----
(function () {
  var protectAttempts = 0;
  function protectAssetManager() {
    protectAttempts++;
    if (typeof cc === wrapyWswPxhD(4) || !cc.assetManager) {
      if (protectAttempts < 18) setTimeout(protectAssetManager, 200);
      return;
    }
    var methodsToProtect = [wrapyWswPxhD(5), wrapyWswPxhD(6)]; // "loadAny", "loadBundle"
    methodsToProtect.forEach(function (methodName) {
      var originalMethod = cc.assetManager[methodName];
      if (!originalMethod) return;
      Object.defineProperty(cc.assetManager, methodName, {
        get: function () {
          return originalMethod;
        },
        set: function (value) {
          if (
            typeof value === wrapyWswPxhD(7) &&
            value.toString().replace(/\s/g, "") === "function(){}"
          ) {
            console.warn(wrapyWswPxhD(10) + methodName + wrapyWswPxhD(11));
            return;
          }
          originalMethod = value;
        },
        configurable: true,
        enumerable: true,
      });
    });
    console.log(wrapyWswPxhD(12));
  }
  setTimeout(protectAssetManager, 100);
})();

// ----- 保护 cc.RenderFlow._updateRenderData 不被篡改 -----
(function () {
  var protectAttempts = 0;
  function protectRenderFlow() {
    protectAttempts++;
    if (typeof cc === wrapyWswPxhD(4) || !cc.RenderFlow) {
      if (protectAttempts < 16) setTimeout(protectRenderFlow, 150);
      return;
    }
    var origUpdateRenderData = cc.RenderFlow.prototype._updateRenderData;
    if (!origUpdateRenderData) return;
    Object.defineProperty(cc.RenderFlow.prototype, wrapyWswPxhD(13), {
      get: function () {
        return origUpdateRenderData;
      },
      set: function (v) {
        if (
          typeof v === wrapyWswPxhD(7) &&
          v.toString().replace(/\s/g, "") === "function(){}"
        ) {
          console.warn(
            "[Patch] 阻止恶意代码覆盖 cc.RenderFlow.prototype._updateRenderData",
          );
          return;
        }
        origUpdateRenderData = v;
      },
      configurable: false,
    });
    console.log(wrapyWswPxhD(14));
  }
  setTimeout(protectRenderFlow, 100);
})();

// ----- 剪贴板功能 (setClipboard) -----
// (function() {
//   // 提取文本内容（支持字符串/对象/JSON）
//   function extractText(v) {
//     if (v === undefined || v === null) return '';
//     if (typeof v === "string") {
//       try {
//         var obj = JSON.parse(v);
//         if (obj && typeof obj === "object" && Object.prototype.hasOwnProperty.call(obj, "text")) {
//           var t = obj.text;
//           return t === undefined || t === null ? '' : String(t);
//         }
//       } catch (_) {}
//       return v;
//     }
//     if (typeof v === "object") {
//       if (Object.prototype.hasOwnProperty.call(v, "text")) {
//         var t = v.text;
//         return t === undefined || t === null ? '' : String(t);
//       }
//       try { return JSON.stringify(v); }
//       catch (_) { return String(v); }
//     }
//     return String(v);
//   }

//   // 复制主函数
//   function setClipboard(t) {
//     if (!t) return;
//     console.log("执行复制:", t);
//     var text = extractText(t);

//     // fallback: 使用 textarea
//     function fallbackCopy(text) {
//       var textarea = document.createElement("textarea");
//       textarea.value = text;
//       textarea.style.position = "fixed";
//       textarea.style.left = "-9999px";
//       textarea.style.top = "0";
//       document.body.appendChild(textarea);
//       textarea.focus();
//       textarea.select();

//       // iOS 处理
//       if (navigator.userAgent.match(new RegExp('ipad|iphone', 'i'))) {
//         var range = document.createRange();
//         range.selectNodeContents(textarea);
//         var selection = window.getSelection();
//         selection.removeAllRanges();
//         selection.addRange(range);
//         textarea.setSelectionRange(0, 999999);
//       }

//       try {
//         var success = document.execCommand("copy");
//         var status = success ? "successful" : "unsuccessful";
//         console.log("Fallback copy command was " + status);
//         if (success && window.wx && window.wx.showToast) {
//           window.wx.showToast({ title: "复制成功" });
//         }
//       } catch (err) {
//         console.error("Fallback copy error", err);
//       }
//       document.body.removeChild(textarea);
//     }

//     // 优先使用 Async Clipboard API
//     if (navigator.clipboard && navigator.clipboard.writeText) {
//       navigator.clipboard.writeText(text).then(
//         function() {
//           console.log("Async: Copying to clipboard was successful!");
//           if (window.wx && window.wx.showToast) {
//             window.wx.showToast({ title: '复制成功' });
//           }
//         },
//         function(err) {
//           console.error("Async: Could not copy text: ", err);
//           fallbackCopy(text);
//         }
//       );
//     } else {
//       fallbackCopy(text);
//     }
//   }

//   // 注册到各 SDK 对象
//   if (typeof window.setClipboard !== "function") window.setClipboard = setClipboard;
//   if (window.wx && typeof wx.setClipboard !== "function") wx.setClipboard = setClipboard;
//   if (window.HSDK && typeof HSDK.setClipboard !== "function") HSDK.setClipboard = setClipboard;
//   if (window.__HORTOR_SDK__ && typeof __HORTOR_SDK__.setClipboard !== "function") __HORTOR_SDK__.setClipboard = setClipboard;
// })();
