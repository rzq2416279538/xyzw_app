(function () {
  "use strict";

  // ==========================================================================
  // HSDK Mock —— 浏览器端 Hortor SDK 模拟层
  // ==========================================================================
  // 用途：
  //   在本地浏览器环境中模拟 HSDK（Hortor SDK）的行为，使咸鱼之王 H5 游戏
  //   能够脱离微信/抖音等原生容器，在普通浏览器（localhost / file://）中运行。
  //
  // 核心功能：
  //   1. 模拟 HSDK 的门面方法（init / login / dialogLogin / checkSwitches 等）
  //   2. 从 COMB 平台获取加密规则并完成登录认证
  //   3. 预获取游戏开关配置（开关 API），失败时使用本地降级数据
  //   4. XOR 加密（与 334 SDK 一致，支持 transCode 变换 + 偏移量加密）
  //   5. 补齐 bootstrap 能力（剪贴板、wx mock、TGA 埋点、信号通知等）
  //
  // 加载顺序依赖：
  //   patch.js → hsdk-bootstrap.js（创建 window.HSDK 基础门面）
  //   → hsdk-mock.js（增强并覆盖 HSDK 方法，添加真实网络请求）
  //
  // 注意：
  //   本文件使用 ES5 语法（var / function 表达式），以兼容 Cocos 引擎
  //   和可能的老版本浏览器环境（如 Android WebView）。
  // ==========================================================================

  // ==================== 配置 ====================
  var COMB_HOST = "https://comb-platform.hortorgames.com";
  var deviceUniqueId =
    localStorage.getItem("_hsdk_deviceId") || generateDeviceId();

  function generateDeviceId() {
    var id = Math.random().toString(36).slice(-8);
    localStorage.setItem("_hsdk_deviceId", id);
    return id;
  }

  // ==========================================================================
  // COMB_SDK_INFO —— 统一数据源
  // 说明：
  //   所有 API 请求参数都从这里读取，而非分散在各方法中硬编码。
  //   修改此处即可影响加密规则、登录检查、开关配置等所有接口。
  //   可根据实际用户数据替换这些值。
  // ==========================================================================
  var COMB_SDK_INFO = {
    isAuth: true, // 是否已授权
    hasUserInfo: true, // 是否有用户信息
    userId: "oIRDe5bWa0nkmDXLSjraq6ezZryo", // 微信 openId / 用户 ID
    uniqueId: "ecde11731468a9a3f1cd77304c160e79", // 设备唯一标识
    channel: "hortor", // 渠道号
    origChannel: "trafficScheme", // 原始渠道
    h_shareCode: "cf7dbb56ff64271f25d7059c7c5df7a3", // 分享码
    sex: 0, // 性别（0=未知）
    isNewUser: false, // 是否新用户
    createdAt: 1664117205, // 创建时间戳
    alias: "xyzwprod_entry", // 别名
    masterUniqueId: "ecde11731468a9a3f1cd77304c160e79", // 主设备 ID
    gameId: "xyzwprod", // 游戏 ID（登录/开关 API 使用）
    cryptGameId: "xyzw_mix", // 加密规则 API 使用的 gameId（与主 gameId 不同）
  };

  // 获取完整的 combSdkInfo（含动态字段，如 window._charName）
  // 返回：Object - 合并了 COMB_SDK_INFO 和运行时动态字段的完整信息对象
  function getCombSdkInfo() {
    var info = {};
    for (var key in COMB_SDK_INFO) {
      if (COMB_SDK_INFO.hasOwnProperty(key)) {
        info[key] = COMB_SDK_INFO[key];
      }
    }
    var charName = window._charName || "";
    if (charName) {
      info.name = charName;
    }
    return info;
  }

  // ==========================================================================
  // CryptoModule —— XOR 加密模块
  // 说明：
  //   实现与 334 SDK 完全一致的加密流程，用于对登录请求体进行加密。
  //   加密流程（6步）：
  //     1. Base64 编码原始 JSON → 2. transCode 递归交换 codeBook
  //     → 3. getKey 按间隔提取密钥 → 4. 计算初始偏移量
  //     → 5. XOR 逐字节加密 → 6. 再次 Base64 编码
  // ==========================================================================
  var CryptoModule = {
    /**
     * 将字符串转换为字节数组（按 charCode 逐个转换）
     * 每个字符取其 Unicode 码点（0-255 范围），依次存入数组。
     * @param {string} str - 待转换的字符串
     * @returns {number[]} 字节数组，每个元素为字符对应的 Unicode 码点
     */
    stringToBytes: function (str) {
      var bytes = [];
      for (var i = 0; i < str.length; i++) {
        bytes.push(str.charCodeAt(i));
      }
      return bytes;
    },

    /**
     * 将字节数组还原为字符串（Latin1/二进制安全）
     * 逐字节取低 8 位通过 fromCharCode 拼接，避免 apply 参数超限问题。
     * @param {number[]} bytes - 字节数组
     * @returns {string} 还原后的字符串
     */
    bytesToString: function (bytes) {
      // 避免apply参数超限，使用逐字符拼接
      var str = "";
      for (var i = 0; i < bytes.length; i++) {
        str += String.fromCharCode(bytes[i] & 0xff);
      }
      return str;
    },

    /**
     * Base64 编码（用于 UTF-8 文本）
     * 通过 encodeURIComponent 将 UTF-8 字符串转为百分号编码，再 unescape 为 Latin1 字符串后 btoa。
     * 与 334 SDK 的 Ed() 函数保持一致。
     * @param {string} str - 待编码的 UTF-8 字符串
     * @returns {string} Base64 编码后的字符串
     */
    base64Encode: function (str) {
      try {
        return btoa(unescape(encodeURIComponent(str)));
      } catch (e) {
        console.error("[HSDK-Mock] Base64 encode error:", e);
        return this.base64EncodeBytes(str);
      }
    },

    /**
     * Base64 编码（用于二进制/字节数据）
     * XOR 加密后的结果必须用此函数。逐 3 字节为一组编码为 4 个 Base64 字符，
     * 最后一组不足 3 字节时通过 slice + padding 修正。与 334 SDK 的 Td() 函数完全一致。
     * @param {string} str - 待编码的二进制安全字符串（每个字符视为一个字节）
     * @returns {string} Base64 编码后的字符串
     */
    base64EncodeBytes: function (str) {
      var b64 =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
      var result = "";
      var i = 0;
      var len = str.length;
      var leftover = len % 3; // 末尾不满3字节的余数

      while (i < len) {
        var byte1 = str.charCodeAt(i++) & 0xff;
        var byte2 = i < len ? str.charCodeAt(i++) & 0xff : 0;
        var byte3 = i < len ? str.charCodeAt(i++) & 0xff : 0;

        var triple = (byte1 << 16) | (byte2 << 8) | byte3;

        result += b64[(triple >> 18) & 63];
        result += b64[(triple >> 12) & 63];
        result += b64[(triple >> 6) & 63];
        result += b64[63 & triple];
      }

      // 修正末尾padding（与334 SDK完全一致）
      if (leftover) {
        result = result.slice(0, leftover - 3) + "===".substring(leftover);
      }

      return result;
    },

    /**
     * 从 codeBook 中按 keySkip 间隔提取密钥
     * 每隔 keySkip 个字符取一个字符，拼接为新字符串作为 XOR 密钥。
     * @param {string} codeBook - 经过 transCode 变换后的字符表
     * @param {number} keySkip - 取样间隔，必须大于 0
     * @returns {string} 提取出的密钥字符串
     */
    getKey: function (codeBook, keySkip) {
      if (!codeBook || keySkip <= 0) {
        return codeBook;
      }
      var result = "";
      var count = Math.floor(codeBook.length / keySkip);
      for (var i = 0; i < count; i++) {
        result += codeBook[i * keySkip];
      }
      return result;
    },

    /**
     * 取字符串右半部分
     * 若字符串长度为奇数则返回 null（与 334 SDK 行为一致）。
     * @param {string} str - 输入字符串
     * @returns {string|null} 右半部分子串；长度为奇数时返回 null
     */
    rightSide: function (str) {
      if (str.length % 2 != 0) {
        return null;
      }
      return str.substring(str.length / 2, str.length);
    },

    /**
     * 取字符串左半部分
     * 若字符串长度为奇数则返回 null（与 334 SDK 行为一致）。
     * @param {string} str - 输入字符串
     * @returns {string|null} 左半部分子串；长度为奇数时返回 null
     */
    leftSide: function (str) {
      if (str.length % 2 != 0) {
        return null;
      }
      return str.substring(0, str.length / 2);
    },

    /**
     * 递归交换字符串左右两半（与 334 SDK 完全一致）
     * 每次将字符串分为左右两半，交换顺序后递归处理，实现多轮混淆。
     * @param {string} str - 原始字符串（通常为 codeBook）
     * @param {number} swapTimes - 递归交换次数
     * @returns {string} 经过 swapTimes 轮交换后的字符串
     */
    transCode: function (str, swapTimes) {
      if (swapTimes > 0) {
        swapTimes--;
        var right = this.rightSide(str);
        var left = this.leftSide(str);
        return (
          this.transCode(right, swapTimes) + this.transCode(left, swapTimes)
        );
      }
      return str;
    },

    /**
     * XOR 加密/解密核心（字节级操作）
     * 将 data 与 key 逐字节异或，offset 在 key 长度内循环复位。
     * XOR 是对称算法，加密和解密使用同一函数。
     * @param {string} data - 待处理的数据字符串
     * @param {string} key - 密钥字符串
     * @param {number} offset - 密钥起始偏移量
     * @returns {string} 异或处理后的字符串
     */
    crypto: function (data, key, offset) {
      if (!data || !key) {
        return data;
      }
      var result = [];
      var keyBytes = this.stringToBytes(key);
      var dataBytes = this.stringToBytes(data);

      for (var i = 0; i < dataBytes.length; i++) {
        if (offset >= keyBytes.length) {
          offset = 0;
        }
        result.push(dataBytes[i] ^ keyBytes[offset]);
        offset++;
      }

      return this.bytesToString(result);
    },

    /**
     * 完整加密流程（与 334 SDK 完全一致）
     * 步骤：
     *   1. transCode — 对 codeBook 进行递归交换混淆
     *   2. getKey — 从混淆后的 codeBook 中按间隔提取密钥
     *   3. 计算初始偏移量 — 密钥长度右移 keyOffset 位
     *   4. crypto — 与密钥逐字节异或，完成加密
     * @param {string} data - 待加密的明文字符串
     * @param {string} codeBook - 字符表/码本
     * @param {number} swapTimes - transCode 递归交换次数
     * @param {number} keySkip - 密钥提取间隔
     * @param {number} keyOffset - 密钥长度右移位数（用于计算初始偏移）
     * @returns {string} 加密后的字符串
     */
    encode: function (data, codeBook, swapTimes, keySkip, keyOffset) {
      // 步骤1: transCode变换（递归交换）
      var transCode = this.transCode(codeBook, swapTimes);

      // 步骤2: 获取密钥
      var key = this.getKey(transCode, keySkip);

      // 步骤3: 计算初始偏移量
      var offset = key.length >> keyOffset;

      // 步骤4: XOR加密
      return this.crypto(data, key, offset);
    },
  };

  // ==========================================================================
  // NetworkModule —— 网络请求模块
  // 说明：
  //   封装 fetch API，提供 GET / POST（文本）/ POST（JSON）三种请求方式。
  //   自动解析 JSON 响应，GET 请求失败时保留原始文本供调试。
  // ==========================================================================
  var NetworkModule = {
    /**
     * 发送 GET 请求并返回解析后的 JSON 数据
     * 自动解析 JSON 响应，若解析失败则保留原始文本前缀作为 _rawText 字段供调试。
     * @param {string} url - 请求目标 URL
     * @returns {Promise<Object>} 解析后的 JSON 对象；若解析失败则返回包含 _rawText 字段的对象
     */
    get: function (url) {
      console.log("[HSDK-Mock] GET Request:", url);

      return new Promise(function (resolve, reject) {
        fetch(url, {
          method: "GET",
          headers: {
            Accept: "application/json",
            "Content-Type": "application/json",
          },
          credentials: "include",
        })
          .then(function (response) {
            console.log("[HSDK-Mock] GET Response Status:", response.status);
            return response.text().then(function (text) {
              console.log(
                "[HSDK-Mock] GET Response Body:",
                text.substring(0, 500),
              );
              // 尝试解析 JSON，若失败则保留原始文本供调试
              try {
                return JSON.parse(text);
              } catch (e) {
                return { _rawText: text.substring(0, 1000) };
              }
            });
          })
          .then(function (data) {
            console.log("[HSDK-Mock] GET Response Data:", data);
            resolve(data);
          })
          .catch(function (error) {
            console.error("[HSDK-Mock] GET Error:", error);
            reject(error);
          });
      });
    },

    /**
     * 发送 POST 请求（请求体为纯文本格式）
     * 设置 Content-Type 为 text/plain，适用于发送加密后的文本数据。
     * @param {string} url - 请求目标 URL
     * @param {string} data - 请求体文本内容
     * @returns {Promise<Object>} 解析后的 JSON 响应对象
     */
    postText: function (url, data) {
      console.log("[HSDK-Mock] POST Text Request:");
      console.log("[HSDK-Mock] URL:", url);
      console.log("[HSDK-Mock] Data:", data ? data.substring(0, 200) : "empty");

      return new Promise(function (resolve, reject) {
        fetch(url, {
          method: "POST",
          headers: {
            Accept: "application/json",
            "Content-Type": "text/plain",
          },
          body: data,
          credentials: "include",
        })
          .then(function (response) {
            console.log("[HSDK-Mock] POST Response Status:", response.status);
            return response.json();
          })
          .then(function (data) {
            console.log("[HSDK-Mock] POST Response Data:", data);
            resolve(data);
          })
          .catch(function (error) {
            console.error("[HSDK-Mock] POST Error:", error);
            reject(error);
          });
      });
    },

    /**
     * 发送 POST 请求（请求体为 JSON 格式）
     * 自动将 data 对象序列化为 JSON 字符串，设置 Content-Type 为 application/json;charset=UTF-8。
     * @param {string} url - 请求目标 URL
     * @param {Object} data - 待序列化的 JavaScript 对象
     * @returns {Promise<Object>} 解析后的 JSON 响应对象
     */
    postJson: function (url, data) {
      return new Promise(function (resolve, reject) {
        fetch(url, {
          method: "POST",
          headers: {
            Accept: "application/json",
            "Content-Type": "application/json;charset=UTF-8",
          },
          body: JSON.stringify(data),
          credentials: "include",
        })
          .then(function (response) {
            return response.json();
          })
          .then(function (data) {
            resolve(data);
          })
          .catch(function (error) {
            reject(error);
          });
      });
    },
  };

  // ==========================================================================
  // SystemModule —— 系统信息模块
  // 说明：
  //   提供浏览器环境信息（系统类型、平台、屏幕尺寸等）。
  //   readBrowserSystemInfo() 通过 User-Agent 实时解析真实系统信息，
  //   而非使用硬编码值。
  /**
   * 通过 User-Agent 实时解析浏览器系统信息
   * 从 navigator.userAgent 中解析操作系统类型及版本号，返回包含系统、平台、屏幕尺寸等信息的对象。
   * @returns {Object} 包含 system、platform、model、brand、screenHeight、screenWidth、hortorSDKVersion 的系统信息对象
   */
  function readBrowserSystemInfo() {
    var nav = window.navigator || {};
    var ua = nav.userAgent || "";
    var platform = nav.platform || "";
    var os = "H5 Browser";
    if (/android/i.test(ua))
      os = "Android " + (ua.match(/Android\s+([\d.]+)/i) || [])[1];
    else if (/iphone|ipad|ipod/i.test(ua)) os = "iOS";
    else if (/mac/i.test(platform)) os = "Mac OS";
    else if (/win/i.test(platform)) os = "Windows";
    return {
      system: os || ua || "H5 Browser",
      platform: platform,
      model: platform,
      brand: nav.vendor || "browser",
      screenHeight: (window.screen && window.screen.height) || 0,
      screenWidth: (window.screen && window.screen.width) || 0,
      hortorSDKVersion: "browser",
    };
  }

  var SystemModule = {
    /**
     * 获取完整的系统信息
     * 调用 readBrowserSystemInfo() 读取浏览器环境信息，并补充 SDKVersion、pixelRatio 等游戏框架所需字段。
     * @returns {Object} 包含 SDKVersion、brand、model、system、version、screenHeight/Width、pixelRatio、benchmarkLevel、hortorSDKVersion 的系统信息对象
     */
    getSystemInfo: function () {
      var sys = readBrowserSystemInfo();
      return {
        SDKVersion: "3.16.1",
        brand: sys.brand,
        model: sys.model,
        system: sys.system,
        version: "3.16.1",
        screenHeight: window.screen.height,
        screenWidth: window.screen.width,
        pixelRatio: window.devicePixelRatio || 1,
        benchmarkLevel: 1,
        hortorSDKVersion: "1.10.15",
      };
    },

    /**
     * 获取模拟的平台标识
     * 返回固定值 "android"，用于模拟 Android 平台的运行环境标识。
     * @returns {string} 固定返回 "android"
     */
    getPlatform: function () {
      return "android";
    },

    /**
     * 判断当前环境是否为 iOS 平台
     * 在浏览器模拟环境中固定返回 false，因为模拟环境始终模拟 Android。
     * @returns {boolean} 固定返回 false
     */
    isIOS: function () {
      return false;
    },
  };

  // ==========================================================================
  // 默认开关数据（API 降级使用）
  // 说明：
  //   DEFAULT_SWITCH_DATA —— 开关数值数组（182 个），按顺序对应 SWITCH_NAME_LIST。
  //   SWITCH_NAME_LIST   —— 开关名称列表（182 个），与服务端约定顺序一致。
  //   getDefaultSwitchData() —— 将两个数组合并为 { 开关名: 开关值 } 的字典，
  //                            当 API 请求失败时作为降级数据使用。
  // 开关值含义：
  //   1  = 启用（打开）   0 = 禁用（关闭）
  //   -1 = 未定义/默认值
  // ==========================================================================
  var DEFAULT_SWITCH_DATA = [
    1, 0, 0, 1, 1, 0, -1, -1, 1, 1, 1, -1, -1, -1, -1, 1, 0, -1, 1, -1, 0, 1, 1,
    -1, -1, -1, -1, 1, 1, 1, -1, -1, 1, 1, -1, 1, 1, -1, 1, 1, 1, 1, -1, 1, 1,
    -1, -1, 1, 1, -1, -1, -1, -1, -1, 1, -1, 0, -1, 1, -1, -1, -1, -1, -1, 1, 1,
    -1, 1, -1, -1, 0, -1, 1, 0, 1, -1, -1, 1, -1, 1, -1, 1, 1, 1, -1, 0, 1, 0,
    1, -1, 1, 1, 1, 1, 1, 1, -1, -1, 1, 1, -1, 1, -1, 1, -1, 0, -1, -1, 1, 0, 1,
    1, 1, -1, -1, -1, -1, 1, -1, -1, -1, -1, 1, 0, 1, -1, 1, 1, 1, -1, 1, -1, 1,
    1, 1, -1, -1, 1, 1, -1, 0, -1, 1, 1, -1, 1, -1, 1, 1, 1, 1, -1, 1, -1, -1,
    -1, -1, -1, -1, 1, 1, 1, -1, 0, 1, 1, -1, -1, -1, -1, 1, -1, -1, -1, -1, 1,
    -1, 1, 1, -1, -1, -1,
  ];
  // 完整的开关名称列表（与服务端约定顺序一致）
  var SWITCH_NAME_LIST = [
    "AuditSwitch",
    "Whitelist",
    "CheckAudit",
    "GuideSwitch",
    "PaySwitch",
    "PlayVideo",
    "UIAutoDispose",
    "FirstLoadingSwitch",
    "CDNSwitch",
    "UserAgreement",
    "PrivacyPolicy",
    "Subscribe",
    "AddDesktop",
    "ColorSign",
    "LogOut",
    "ServerConfig",
    "ForcedUpdate",
    "ClearCacheSlient",
    "ChatWorldSwitch",
    "ConfigEncBin",
    "BattleLog",
    "VerifyAutoContinue",
    "FguiTexLoader",
    "RefluxSwitch",
    "AnimateList",
    "OpenBoxBatch",
    "BattleTimer",
    "LegionRankSwitch",
    "LegionBetRewardSwitch",
    "DailySpecialSwitch",
    "LxgTest",
    "LegionBetRedSwitch",
    "LxgTest2",
    "MiniGame",
    "ServerTransfer",
    "LegionWarMapPreload",
    "GlobalMouseWheelEnabled",
    "ListBatch",
    "UseIdBattle",
    "StudioGamesSwitch",
    "SkySwitch",
    "UnifyTime",
    "LoadLocalConfig",
    "AutoDisposeV2",
    "ClientDVCDN",
    "ConfigEncBinAudit7",
    "miniGameTga",
    "AutoReleaseSound",
    "AutoReleaseMusic",
    "RestartGame",
    "IOSTTNotice",
    "ChargeNoDelay",
    "FirstLoginReqData",
    "BattleVisible",
    "QuickFire",
    "StepStart",
    "OpenWebMiniGame",
    "SkipXYZW",
    "PixelSwitch",
    "SpineEmptyContent",
    "StillUseCdnV2",
    "PKRoomRobot",
    "DisabledSwitchRole",
    "PayCloseTip",
    "FixWebSocket",
    "TryGotoLegionWar",
    "StillUseAllCfg",
    "NewResolveDataVer",
    "UnifyPayLock",
    "PostRollbackResult",
    "PostRollbackLog",
    "CloseTouchFix",
    "FasterLoadHelpText",
    "CloseGListItemFix",
    "nightmareFrameReciprocation",
    "NetworkWaiting",
    "SkipRemoveFace",
    "ConfigModifyVerify",
    "ForcePostBattleLog",
    "PartLoad",
    "AllLoaderOpen",
    "CrossDayTask",
    "LWDayReconnectTask",
    "OtherLoginCheckTask",
    "LeagueWarReplay",
    "LegionWarReplay",
    "OssMars",
    "OssAli",
    "camp:switch",
    "MergeBinOpen",
    "FasterSubPage",
    "ControllerSubPage",
    "FasterUIStates",
    "RemoteQRCode",
    "ReTryBackReward",
    "LXG_TEST3",
    "LXG_TEST4",
    "CloseGameCircle",
    "O4eMsgCache",
    "ShowModePolish",
    "MergeBundleOpen",
    "ModuleMixUI",
    "Mosquito",
    "FixSkinError",
    "BattleLevelTest",
    "ObjectPoolOpen",
    "BattleDetailLog",
    "FuncFrameRunOnce",
    "LongTipsText",
    "ShowSurvey",
    "LegionWarMapMapping",
    "GameServerOpen",
    "ForceRename",
    "ForceRenameWX",
    "ByteDanceAuditPay",
    "ByteDanceDiamodPay",
    "TestUnLockPervious",
    "MoonWarReplay",
    "CrossDayClaimReward",
    "CheckDangerOrder",
    "CheckWindowsWX",
    "DebugGame",
    "SimplifyProtocol",
    "PolishMemory",
    "FixLoader3D",
    "LWNetTestTask",
    "FixLWLastTime",
    "FixTaskMgr",
    "HeadIconRemindSwitch",
    "FollowGiftSwitch",
    "DisposeBattleUITask",
    "NotDelayStartPushLevel",
    "OpenWxBusinessReport",
    "PolishSeasonMemory",
    "SeasonPushLevel",
    "PolishProxyDispose",
    "PolishMidEndDevice",
    "PolishHighEndDevice",
    "IOSGC",
    "IOSDisposeUI",
    "BattleSpineRealTime",
    "BattleSpineAllRealTime",
    "FixLandscapeDragBug",
    "ReportDeviceInfo",
    "BattleBug",
    "EnableFrameList",
    "AsyncDecodeConfig",
    "LocalPushLevel",
    "FixSkeletonErr",
    "RealDeleteAccount",
    "CloseBetPanel",
    "CloseBlockWord",
    "Receipt",
    "CloseQuickLevel",
    "UseQuickLevelResult",
    "NewConfig",
    "NotFixWsMaskFlag",
    "PostLevelRollBackData",
    "CLOSE_IOSPAYFAILTIPS",
    "ChangeBattlePassRewardDyamic",
    "HighFPS",
    "UseDressingRoomV2",
    "WXClosePrivacyPolicy",
    "LPWarReplay",
    "CloseBattleCustom",
    "PlaybackDiagnostics",
    "evoTower",
    "OpenMobxErrorBoundary",
    "EvoTowerOptimize",
    "CloseOtherLogin",
    "CloseCheckEquipments",
    "CloseLoginCheckItemsData",
    "CloseRefluxSelectServer",
    "CloseRFTask",
    "CloseTeamListCheckMatchTeamType",
    "HideTroopsBuilding",
    "SeasonOutReplay",
    "PolishBadCalls",
    "RejectLowVersionPvP",
    "IgnoreApexTips",
    "IgnoreApexSupportInTime",
    "FixYanChangClickEvent",
  ];
  function getDefaultSwitchData() {
    var data = {};
    for (var i = 0; i < SWITCH_NAME_LIST.length; i++) {
      data[SWITCH_NAME_LIST[i]] =
        i < DEFAULT_SWITCH_DATA.length ? DEFAULT_SWITCH_DATA[i] : 1;
    }
    return data;
  }

  // ==========================================================================
  // HSDK —— Hortor SDK 门面对象
  // 说明：
  //   这是核心模拟对象，实现了 HSDK 所有关键方法。
  //   方法将复制到 window.HSDK 上（见"完善 window.HSDK"节）。
  //
  // 登录流程：
  //   dialogLogin() / login()
  //     → init()（轻量初始化，不阻塞）
  //     → _fetchCryptRule()（获取加密规则 + codeBook）
  //     → _loginCheck()（XOR 加密请求体，发送登录检查）
  //     → 返回 userSdk
  //
  // 开关流程：
  //   checkSwitches(switchIdList)
  //     → 从 window.__switchStore（预请求数据）中按名称取开关值
  //     → 返回 { 开关名: 值 } 字典
  // ==========================================================================
  var HSDK = {
    config: {},
    canLogin: false,
    canGetSwitch: false,
    deviceId: deviceUniqueId,
    cryptRule: null,
    codeBook: null,
    userSdk: null,
    initPromise: null,

    /**
     * setVibrate —— 震动（浏览器环境为空操作）
     */
    setVibrate: function () {},

    /**
     * SDK 初始化（轻量版，不阻塞游戏启动）
     * 立即 resolve 返回默认 userSdk，避免阻塞游戏主流程加载。
     * 将传入的 options 合并到内部 config，并标记 canLogin / canGetSwitch 为 true。
     * @param {Object} options - 初始化配置对象
     * @param {string} options.gameId - 游戏 ID
     * @returns {Promise<{userSdk: Object, gameId: string, subGameId: string}>} 返回包含默认 userSdk 和 gameId 的 Promise
     */
    init: function (options) {
      console.log("[HSDK-Mock] init called with options:", options);

      this.config = Object.assign({}, options);
      this.config.combGameId = options.gameId;
      this.canLogin = true;
      this.canGetSwitch = true;
      this.userSdk = { isNewUser: false };

      console.log(
        "[HSDK-Mock] init: lightweight bootstrap, resolving immediately",
      );

      // 立即resolve，不阻塞游戏加载
      return Promise.resolve({
        userSdk: this.userSdk,
        gameId: this.config.subGameId || options.gameId,
        subGameId: this.config.subGameId || options.gameId,
      });
    },

    /**
     * 真正的登录初始化（在用户点击登录时调用，会触发网络请求）
     * 依次执行：获取加密规则（_fetchCryptRule）→ 登录检查（_loginCheck），
     * 成功后在 window._hortor_callOnLoad 中通知游戏加载器。
     * @param {Object} options - 登录初始化配置对象
     * @param {string} [options.gameId] - 游戏 ID
     * @returns {Promise<{userSdk: Object, gameId: string, subGameId: string}>} 返回包含 userSdk 和 gameId 的 Promise
     */
    realInit: function (options) {
      console.log("[HSDK-Mock] ========== HSDK REAL INIT START ==========");
      console.log("[HSDK-Mock] realInit called with options:", options);

      this.config = Object.assign({}, this.config, options);
      this.config.combGameId = options.gameId || this.config.combGameId;

      var self = this;
      return new Promise(function (resolve, reject) {
        console.log("[HSDK-Mock] Step 1: Fetching crypt rule...");
        self
          ._fetchCryptRule()
          .then(function (cryptData) {
            console.log("[HSDK-Mock] Step 1: Crypt rule received");

            if (
              !cryptData ||
              !cryptData.data ||
              !cryptData.data.cryptRule ||
              !cryptData.data.cryptRule.codeBook
            ) {
              // 构建详细错误信息：包含完整的服务端响应以便排查
              var responseSummary = JSON.stringify(cryptData).substring(0, 300);
              var errMsg = !cryptData
                ? "cryptData is empty"
                : !cryptData.data
                  ? "No data field. Response: " + responseSummary
                  : "No codeBook. Response: " + responseSummary;
              console.error("[HSDK-Mock] Crypt rule fetch failed:", errMsg);
              reject(new Error(errMsg));
              return;
            }

            self.cryptRule = cryptData.data.cryptRule || {};
            self.codeBook = self.cryptRule.codeBook;
            self.config.subGameId = cryptData.data.subGameId || options.gameId;
            self.config.gameId = self.config.subGameId;

            console.log("[HSDK-Mock] codeBook length:", self.codeBook.length);
            console.log(
              "[HSDK-Mock] =============================================================",
            );

            self.canLogin = true;
            self.canGetSwitch = true;

            console.log("[HSDK-Mock] Step 2: Sending login check...");
            self
              ._loginCheck()
              .then(function (loginResult) {
                console.log(
                  "[HSDK-Mock] Step 2: Login check result:",
                  loginResult,
                );

                if (window._hortor_callOnLoad) {
                  window._hortor_callOnLoad(false, true);
                }

                console.log(
                  "[HSDK-Mock] ========== HSDK REAL INIT SUCCESS ==========",
                );
                resolve({
                  userSdk: self.userSdk || { isNewUser: false },
                  gameId: self.config.gameId,
                  subGameId: self.config.subGameId,
                });
              })
              .catch(function (err) {
                console.error("[HSDK-Mock] Step 2: Login check failed:", err);
                reject(err);
              });
          })
          .catch(function (error) {
            console.error(
              "[HSDK-Mock] SDK real init failed:",
              (error && error.message) || error,
            );
            reject(error);
          });
      });
    },

    /**
     * 获取加密规则
     * 向 COMB 平台发起 GET 请求，获取 cryptRule（含 codeBook），
     * 用于后续登录请求体的 XOR 加密。
     * @returns {Promise<Object>} 返回包含 cryptRule 和 codeBook 等数据的响应对象
     */
    _fetchCryptRule: function () {
      var version = this.config.gameVersion || "";
      var url =
        COMB_HOST +
        "/comb-login-server/api/v1/login/crypt/mix" +
        "?combGameId=" +
        COMB_SDK_INFO.cryptGameId +
        "&gameTp=minigame" +
        "&system=" +
        SystemModule.getPlatform() +
        "&version=" +
        version +
        "&deviceUniqueId=" +
        COMB_SDK_INFO.uniqueId;

      console.log("[HSDK-Mock] Fetching crypt rule from:", url);
      return NetworkModule.get(url);
    },

    /**
     * 登录检查
     * 向 COMB 平台发送 XOR 加密的登录请求体，完成登录认证。
     * 内部使用 CryptoModule 对 JSON 请求体进行 6 步加密（Base64 → transCode → getKey → 偏移量 → XOR → Base64）。
     * @returns {Promise<{success: boolean, userSdk?: Object, error?: Object}>} 返回登录结果，success 为 true 时包含 userSdk
     */
    _loginCheck: function () {
      var self = this;

      return new Promise(function (resolve, reject) {
        // 构建请求URL（使用 COMB_SDK_INFO 统一数据源）
        var url =
          COMB_HOST +
          "/comb-login-server/api/v1/login/check" +
          "?gameId=" +
          COMB_SDK_INFO.gameId +
          "&gameTp=minigame" +
          "&system=" +
          SystemModule.getPlatform() +
          "&version=" +
          self.config.gameVersion +
          "&deviceUniqueId=" +
          COMB_SDK_INFO.uniqueId +
          "&loginTag=code" +
          "&cryptVersion=1.1.0";

        console.log("[HSDK-Mock] ========== LOGIN CHECK ==========");
        console.log("[HSDK-Mock] Login Check URL:", url);

        // 构建请求体（与334 SDK完全一致）
        var timestamp = Math.floor(Date.now() / 1000);

        // ==================== combSdkInfo（使用模块级统一数据源） ====================
        var combSdkInfo = getCombSdkInfo();

        // ==================== combUser（动态，从bin文件注入） ====================
        var injectedCombUser = window._combUserInfo || null;
        var combUser;
        if (injectedCombUser) {
          // 如果注入的是 JSON 字符串，先反序列化为对象
          if (typeof injectedCombUser === "string") {
            try {
              injectedCombUser = JSON.parse(injectedCombUser);
              console.log("[HSDK-Mock] combUser JSON字符串已解析为对象");
            } catch (e) {
              console.error("[HSDK-Mock] combUser JSON解析失败:", e);
            }
          }

          if (
            typeof injectedCombUser === "object" &&
            injectedCombUser.encryptCombUser &&
            injectedCombUser.sign
          ) {
            combUser = {
              encryptCombUser: injectedCombUser.encryptCombUser,
              timestamp:
                injectedCombUser.timestamp || Math.floor(Date.now() / 1000),
              sign: injectedCombUser.sign,
            };
            console.log("[HSDK-Mock] 使用注入的 combUser:", combUser);
          } else {
            combUser = injectedCombUser;
            console.warn("[HSDK-Mock] combUser 数据不完整，登录可能失败");
          }
        }

        // ==================== requestBodyInfo ====================
        var requestBody = {
          gameId: COMB_SDK_INFO.gameId,
          gameTp: "minigame",
          timestamp: timestamp,
          loginInfo: {
            combSdkInfo: combSdkInfo,
            combUser: combUser,
            envCombSdkInfo: null,
            requestBodyInfo: {
              gameTp: "minigame",
              origGameId: "",
              origUniqueId: "",
              version: "1.10.15",
              gameId: COMB_SDK_INFO.gameId,
              channel: COMB_SDK_INFO.channel,
              origChannel: "",
              query: "",
              queryRaw: "{}",
              shareConfigId: "",
              activityId: "",
              h_shareCode: "",
              boxCode: "",
              isWeak: true,
              forceAuth: false,
              sysInfo:
                '{"SDKVersion":"3.16.1","brand":"microsoft","model":"microsoft","system":"Windows 10 x64","version":"4.1.9.62","screenHeight":634,"screenWidth":356,"pixelRatio":1,"benchmarkLevel":-1,"hortorSDKVersion":"1.10.15"}',
              scene: 1256,
              rawData:
                '{"scene":1256,"query":{"referrerInfo":{}},"shareTicket":"c345a933-eaaa-4d95-a430-eef3011a696c","referrerInfo":{},"custom":{"channel":"hortor","origChannel":"","shareConfigId":"","activityId":"","h_shareCode":"","pageQuery":"","boxCode":""},"hideDuration":0,"coldStart":true}',
            },
          },
        };

        console.log("[HSDK-Mock] Login Check Request Body:", requestBody);

        // 加密请求体
        var jsonStr = JSON.stringify(requestBody);
        var encryptedData = jsonStr; // 默认使用明文

        console.log(
          "[HSDK-Mock] CodeBook:",
          self.codeBook
            ? "present (" + self.codeBook.length + " chars)"
            : "missing",
        );
        console.log("[HSDK-Mock] CryptRule:", JSON.stringify(self.cryptRule));
        console.log("[HSDK-Mock] Raw JSON:", jsonStr);
        console.log("[HSDK-Mock] Raw JSON length:", jsonStr.length);

        // 获取加密参数
        var swapTimes = self.cryptRule ? self.cryptRule.swapTimes || 0 : 0;
        var keySkip = self.cryptRule ? self.cryptRule.keySkip || 0 : 0;
        var keyOffset = self.cryptRule ? self.cryptRule.keyOffset || 0 : 0;
        console.log(
          "[HSDK-Mock] Encryption params - swapTimes:",
          swapTimes,
          ", keySkip:",
          keySkip,
          ", keyOffset:",
          keyOffset,
        );

        if (self.codeBook && self.codeBook.length > 0) {
          try {
            console.log(
              "[HSDK-Mock] ==================== ENCRYPTION START ====================",
            );
            console.log(
              "[HSDK-Mock] Params - swapTimes:",
              swapTimes,
              ", keySkip:",
              keySkip,
              ", keyOffset:",
              keyOffset,
            );
            console.log("[HSDK-Mock] CodeBook length:", self.codeBook.length);
            console.log(
              "[HSDK-Mock] CodeBook first 100 chars:",
              self.codeBook.substring(0, 100),
            );
            console.log(
              "[HSDK-Mock] CodeBook last 50 chars:",
              self.codeBook.substring(self.codeBook.length - 50),
            );

            // 步骤1: Base64编码原始JSON
            var base64Data = CryptoModule.base64Encode(jsonStr);
            console.log(
              "[HSDK-Mock] Step 1 - Base64 encoded length:",
              base64Data.length,
            );
            console.log(
              "[HSDK-Mock] Step 1 - Base64 first 60 chars:",
              base64Data.substring(0, 60),
            );
            console.log(
              "[HSDK-Mock] Step 1 - Base64 last 30 chars:",
              base64Data.substring(base64Data.length - 30),
            );

            // 步骤2: transCode变换
            var transCodeResult = CryptoModule.transCode(
              self.codeBook,
              swapTimes,
            );
            console.log(
              "[HSDK-Mock] Step 2 - transCode result length:",
              transCodeResult.length,
            );
            console.log(
              "[HSDK-Mock] Step 2 - transCode first 60 chars:",
              transCodeResult.substring(0, 60),
            );

            // 步骤3: 获取密钥
            var key = CryptoModule.getKey(transCodeResult, keySkip);
            console.log("[HSDK-Mock] Step 3 - key length:", key.length);
            console.log(
              "[HSDK-Mock] Step 3 - key first 30 chars:",
              key.substring(0, 30),
            );

            // 步骤4: 计算初始偏移量
            var offset = key.length >> keyOffset;
            console.log("[HSDK-Mock] Step 4 - initial offset:", offset);

            // 步骤5: XOR加密
            var encryptedRaw = CryptoModule.crypto(base64Data, key, offset);
            console.log(
              "[HSDK-Mock] Step 5 - After XOR length:",
              encryptedRaw.length,
            );
            console.log(
              "[HSDK-Mock] Step 5 - XOR first 60 chars:",
              encryptedRaw.substring(0, 60),
            );

            // 步骤6: 再次Base64编码（服务器期望base64格式）
            // ★ 关键：XOR结果是二进制数据，必须用base64EncodeBytes逐字节编码！
            encryptedData = CryptoModule.base64EncodeBytes(encryptedRaw);
            console.log(
              "[HSDK-Mock] Step 6 - Final encrypted (base64) length:",
              encryptedData.length,
            );
            console.log(
              "[HSDK-Mock] Step 6 - Final encrypted first 60 chars:",
              encryptedData.substring(0, 60),
            );
            console.log(
              "[HSDK-Mock] Step 6 - Encrypted starts with LZ:",
              encryptedData.startsWith("LZ"),
            );
            console.log(
              "[HSDK-Mock] ==================== ENCRYPTION END ====================",
            );
          } catch (e) {
            console.error("[HSDK-Mock] XOR加密失败:", e);
            console.error("[HSDK-Mock] 错误堆栈:", e.stack);
            reject(new Error("XOR加密失败: " + ((e && e.message) || e)));
            return;
          }
        } else {
          // codeBook 缺失不应该出现（init 已拦截），此处为防御性代码
          console.error(
            "[HSDK-Mock] 严重错误：_loginCheck 被调用但 codeBook 为空",
          );
          reject(new Error("缺少加密密钥(codeBook)，无法发送登录请求"));
          return;
        }

        console.log("[HSDK-Mock] Sending login check to:", url);
        console.log("[HSDK-Mock] Request body:", requestBody);

        NetworkModule.postText(url, encryptedData)
          .then(function (response) {
            console.log("[HSDK-Mock] Login check response:", response);

            if (response && response.meta && response.meta.errCode === 0) {
              self.userSdk = response.data && response.data.userSdk;
              resolve({
                success: true,
                userSdk: self.userSdk,
              });
            } else {
              resolve({
                success: false,
                error: response && response.meta,
              });
            }
          })
          .catch(function (error) {
            console.error("[HSDK-Mock] Login check error:", error);
            reject(error);
          });
      });
    },

    /**
     * 获取 SDK 配置
     * 返回当前 HSDK 的内部 config 对象。
     * @returns {Object} 当前 HSDK 配置对象
     */
    sdkConfig: function () {
      return this.config || {};
    },

    /**
     * 登录回调注册
     * 注册登录状态监听器，在延迟 100ms 后通过 listener 回调返回 userSdk。
     * @param {Object} data - 回调配置对象
     * @param {Function} data.listener - 登录成功后的回调函数，接收 { userSdk } 作为参数
     */
    onLogin: function (data) {
      console.log("[HSDK-Mock] onLogin called:", data);

      var self = this;
      setTimeout(function () {
        if (data && data.listener) {
          data.listener({
            userSdk: self.userSdk || {
              isNewUser: false,
              gameId: self.config.gameId,
            },
          });
        }
      }, 100);
    },

    /**
     * 登录（触发网络请求）
     * 已完成初始化时直接调用 _loginCheck 发送登录请求；
     * 未初始化时先调用 realInit 获取加密规则，再执行登录检查。
     * @returns {Promise<Object>} 返回包含 userSdk 等信息的 Promise
     */
    login: function () {
      console.log("[HSDK-Mock] login called");

      var self = this;
      return new Promise(function (resolve, reject) {
        if (!self.codeBook) {
          // 未初始化，先 realInit 再发请求
          self
            .realInit(self.config)
            .then(function () {
              self
                ._loginCheck()
                .then(function (result) {
                  console.log("[HSDK-Mock] login success:", result);
                  self.userSdk = result.userSdk || {
                    isNewUser: false,
                    gameId: self.config.gameId,
                  };
                  resolve(self.userSdk);
                })
                .catch(function (err) {
                  console.error("[HSDK-Mock] login failed:", err);
                  reject(err);
                });
            })
            .catch(function (err) {
              console.error("[HSDK-Mock] login init failed:", err);
              reject(err);
            });
          return;
        }

        // 已有加密规则，直接发登录请求
        self
          ._loginCheck()
          .then(function (result) {
            console.log("[HSDK-Mock] login success:", result);
            self.userSdk = result.userSdk || {
              isNewUser: false,
              gameId: self.config.gameId,
            };
            resolve(self.userSdk);
          })
          .catch(function (err) {
            console.error("[HSDK-Mock] login failed:", err);
            reject(err);
          });
      });
    },

    /**
     * 弹窗登录（dialogLogin）
     * 支持两种回调风格：
     *   1. 参数为对象：{ success: fn, fail: fn, complete: fn }
     *   2. 无参数 / 参数非对象：返回 Promise
     * 若 config 中缺少必要参数，自动使用 COMB_SDK_INFO 统一数据初始化。
     * @param {Object|void} [args] - 回调配置对象或空
     * @param {Function} [args.success] - 登录成功回调
     * @param {Function} [args.fail] - 登录失败回调
     * @param {Function} [args.complete] - 登录完成回调
     * @returns {Promise<Object>} 返回包含 userSdk 等信息的 Promise
     */
    dialogLogin: function (args) {
      console.log("[HSDK-Mock] dialogLogin called:", args);

      var self = this;

      // 如果 config 中缺少必要参数，使用 COMB_SDK_INFO 统一数据
      if (!self.config.combGameId && !self.config.gameId) {
        var detectedGameId = COMB_SDK_INFO.gameId;
        var detectedVersion =
          (typeof globalThis !== "undefined" && globalThis.GAME_VERSION) || "";
        console.log(
          "[HSDK-Mock] Config empty, auto-initializing with gameId:",
          detectedGameId,
          "version:",
          detectedVersion,
        );
        self.init({ gameId: detectedGameId, gameVersion: detectedVersion });
      }

      var doLogin = function () {
        if (self.codeBook) {
          return self._loginCheck();
        }
        return self.realInit(self.config).then(function () {
          return self._loginCheck();
        });
      };

      var promise = doLogin()
        .then(function (result) {
          console.log("[HSDK-Mock] dialogLogin success:", result);
          self.userSdk = result.userSdk || {
            isNewUser: false,
            gameId: COMB_SDK_INFO.gameId,
          };
          if (args && typeof args.success === "function") {
            args.success(self.userSdk);
          }
          if (args && typeof args.complete === "function") {
            args.complete(self.userSdk);
          }
          return self.userSdk;
        })
        .catch(function (err) {
          console.error("[HSDK-Mock] dialogLogin failed:", err);
          if (args && typeof args.fail === "function") {
            args.fail(err);
          }
          if (args && typeof args.complete === "function") {
            args.complete({ errMsg: err.message });
          }
          throw err;
        });

      return promise;
    },

    /**
     * 上报登录状态
     * 向控制台输出登录状态日志，当前为模拟实现，无实际网络请求。
     */
    reportLoginState: function () {
      console.log("[HSDK-Mock] reportLoginState called");
    },

    /**
     * 防沉迷退出
     * 模拟防沉迷系统强制退出操作，当前仅输出日志。
     */
    onAddictionQuit: function () {
      console.log("[HSDK-Mock] onAddictionQuit called");
    },

    /**
     * 获取 GS 设置
     * 模拟获取游戏 GS（Game Service）配置，当前返回空对象。
     * @returns {Object} 空的 GS 配置对象
     */
    getGsSetting: function () {
      console.log("[HSDK-Mock] getGsSetting called");
      return {};
    },

    /**
     * 分享
     * 模拟分享功能，直接返回成功结果。
     * @param {Object} [options] - 分享配置参数
     * @returns {Promise<{success: boolean}>} 返回分享结果 Promise
     */
    share: function (options) {
      console.log("[HSDK-Mock] share called:", options);
      return Promise.resolve({ success: true });
    },

    /**
     * 显示分享菜单
     * 模拟显示分享菜单操作，当前仅输出日志。
     * @param {Object} [options] - 分享菜单配置参数
     */
    showShareMenu: function (options) {
      console.log("[HSDK-Mock] showShareMenu called:", options);
    },

    /**
     * 更新分享菜单
     * 模拟更新分享菜单配置，当前仅输出日志。
     * @param {Object} [options] - 分享菜单更新参数
     */
    updateShareMenu: function (options) {
      console.log("[HSDK-Mock] updateShareMenu called:", options);
    },

    /**
     * 获取用户信息
     * 返回当前用户的 deviceId 和 gameId 信息。
     * @returns {{uniqueId: string, gameId: string}} 包含 uniqueId 和 gameId 的用户信息对象
     */
    getUserInfo: function () {
      console.log("[HSDK-Mock] getUserInfo called");
      return {
        uniqueId: this.deviceId,
        gameId: this.config.gameId,
      };
    },

    /**
     * 支付
     * 模拟支付功能，在 H5 环境中始终返回拒绝（Pay not supported）。
     * @param {Object} [options] - 支付参数
     * @returns {Promise<never>} 返回拒绝的 Promise，提示 H5 不支持支付
     */
    pay: function (options) {
      console.log("[HSDK-Mock] pay called:", options);
      return Promise.reject({ errMsg: "Pay not supported in H5" });
    },

    /**
     * 显示广告
     * 模拟广告展示功能，在 H5 环境中始终返回拒绝（Ad not supported）。
     * @param {Object} [options] - 广告参数
     * @returns {Promise<never>} 返回拒绝的 Promise，提示 H5 不支持广告
     */
    showAd: function (options) {
      console.log("[HSDK-Mock] showAd called:", options);
      return Promise.reject({ errMsg: "Ad not supported in H5" });
    },

    /**
     * 事件上报
     * 向控制台输出事件名称和附加数据，当前为模拟实现，无实际网络请求。
     * @param {string} eventName - 事件名称
     * @param {*} [data] - 事件附加数据
     */
    trackEvent: function (eventName, data) {
      console.log("[HSDK-Mock] trackEvent:", eventName, data);
    },

    /**
     * 获取设备信息
     * 返回当前浏览器模拟的设备信息，包含 deviceUniqueId、gameId、sysInfo 等。
     * @returns {Promise<{deviceUniqueId: string, gameId: string, gameTp: string, uniqueId: string, sysInfo: Object}>} 返回设备信息对象的 Promise
     */
    getDeviceInfo: function () {
      console.log("[HSDK-Mock] getDeviceInfo called");
      return Promise.resolve({
        deviceUniqueId: COMB_SDK_INFO.uniqueId,
        gameId: COMB_SDK_INFO.gameId,
        gameTp: "minigame",
        uniqueId: COMB_SDK_INFO.uniqueId,
        sysInfo: {
          deviceSystem: "Android 13.4",
          deviceModel: "xiaomi",
          deviceBrand: "android",
          deviceVersion: "",
          hortorSDKVersion: "1.10.15",
          deviceName: "",
        },
      });
    },

    /**
     * 获取通知公告信息
     * 模拟获取通知公告列表，当前返回空数组。
     * @returns {Promise<Array>} 返回空数组的 Promise
     */
    getNoticeInfo: function () {
      console.log("[HSDK-Mock] getNoticeInfo called");
      return Promise.resolve([]);
    },
    /**
     * 获取通知公告
     * 模拟获取通知公告数据，当前返回空数组。
     * 与 getNoticeInfo 功能类似，是另一种通知查询接口。
     * @returns {Promise<Array>} 返回空数组的 Promise
     */
    getNotice: function () {
      console.log("[HSDK-Mock] getNotice called");
      return Promise.resolve([]);
    },

    /**
     * 获取网络类型
     * 通过 navigator.connection 获取当前浏览器网络类型，
     * 无法获取时默认返回 "wifi"。
     * @returns {Promise<{networkType: string}>} 返回包含 networkType 的 Promise
     */
    getNetworkType: function () {
      console.log("[HSDK-Mock] getNetworkType called");
      var conn = window.navigator && window.navigator.connection;
      return Promise.resolve({
        networkType: (conn && conn.effectiveType) || "wifi",
      });
    },

    /**
     * 获取启动参数
     * 从当前页面 URL 的查询参数中解析并返回启动参数对象。
     * @returns {Object} 包含 URL 查询参数的键值对对象
     */
    getHTLauchOptions: function () {
      console.log("[HSDK-Mock] getHTLauchOptions called");
      var params = {};
      try {
        new URLSearchParams(window.location.search).forEach(function (v, k) {
          params[k] = v;
        });
      } catch (e) {}
      return params;
    },

    /**
     * 获取实名信息
     * 模拟获取用户实名认证信息，返回已认证且为成年人的状态。
     * @returns {Promise<{verified: boolean, adult: boolean}>} 返回包含 verified 和 adult 字段的 Promise
     */
    getRealNameInfo: function () {
      console.log("[HSDK-Mock] getRealNameInfo called");
      return Promise.resolve({ verified: true, adult: true });
    },

    /**
     * 获取协议文本
     * 模拟获取用户协议和隐私政策文本，当前返回空文本。
     * @returns {Promise<{userPolicyText: string, privacyPolicyText: string}>} 返回包含协议文本的 Promise
     */
    getProtocolText: function () {
      console.log("[HSDK-Mock] getProtocolText called");
      return Promise.resolve({
        userPolicyText: "",
        privacyPolicyText: "",
      });
    },

    /**
     * 设置游戏用户信息
     * 模拟设置游戏用户信息，当前仅输出日志并返回空 Promise。
     * @returns {Promise<void>} 返回空 Promise
     */
    setGameUserInfo: function () {
      console.log("[HSDK-Mock] setGameUserInfo called");
      return Promise.resolve();
    },

    /**
     * 弱登录
     * 模拟弱登录流程，直接返回默认的 userSdk。
     * @param {Object} [options] - 弱登录配置参数
     * @returns {Promise<{userSdk: {isNewUser: boolean}}>} 返回包含默认 userSdk 的 Promise
     */
    weakLogin: function (options) {
      console.log("[HSDK-Mock] weakLogin called:", options);
      return Promise.resolve({ userSdk: { isNewUser: false } });
    },

    /**
     * @description 获取电量信息
     * @returns {{ level: number, isCharging: boolean }}
     */
    getBattery: function () {
      console.log("[HSDK-Mock] getBattery called");
      return { level: 1, isCharging: true };
    },

    /**
     * 登出
     * 模拟用户登出操作，当前仅输出日志并返回空 Promise。
     * @returns {Promise<void>} 返回空 Promise
     */
    logout: function () {
      console.log("[HSDK-Mock] logout called");
      return Promise.resolve();
    },

    /**
     * 游戏埋点
     * 向控制台输出游戏埋点事件名称和自定义数据，当前为模拟实现。
     * @param {Object} data - 埋点数据对象
     * @param {string} data.eventName - 事件名称
     * @param {*} [data.customData] - 事件自定义数据
     */
    gameTrack: function (data) {
      if (data && data.eventName) {
        console.log("[HSDK-Mock] gameTrack:", data.eventName, data.customData);
      }
    },

    /**
     * 显示加载提示
     * 模拟显示加载中的提示界面，当前仅输出日志。
     */
    showLoading: function () {
      console.log("[HSDK-Mock] showLoading called");
    },
    /**
     * 隐藏加载提示
     * 模拟隐藏加载中的提示界面，当前仅输出日志。
     */
    hideLoading: function () {
      console.log("[HSDK-Mock] hideLoading called");
    },

    /**
     * 检查开关状态
     * 从 window.__switchStore（预获取的开关数据）中按 switchIdList 中的名称取值，
     * 支持回调风格（args.listener）和 Promise 风格。
     * @param {Object|Array} args - 开关查询参数或 switchIdList 数组
     * @param {Array} [args.switchIdList] - 需要查询的开关名称列表
     * @param {Function} [args.listener] - 查询完成后的回调函数
     * @returns {Promise<Object>} 返回 { 开关名: 开关值 } 键值对对象的 Promise
     */
    checkSwitches: function (args) {
      console.log("[HSDK-Mock] checkSwitches called:", args);

      var store = window.__switchStore || {};
      var data = {};

      if (args && Array.isArray(args.switchIdList)) {
        for (var i = 0; i < args.switchIdList.length; i++) {
          var item = args.switchIdList[i];
          var key =
            typeof item === "string" || typeof item === "number"
              ? String(item)
              : item && item.switchId != null
                ? String(item.switchId)
                : "";
          if (key) {
            data[key] = store.hasOwnProperty(key) ? store[key] : -1;
          }
        }
      }
      // 与预取一致：比赛低版本拒绝开关对本壳始终关闭
      if (data.hasOwnProperty("RejectLowVersionPvP")) {
        data.RejectLowVersionPvP = 0;
      }

      console.log("[HSDK-Mock] checkSwitches data:", data);

      // 支持回调风格
      if (args && typeof args.listener === "function") {
        args.listener(data);
      }

      return Promise.resolve(data);
    },
  };

  // ==================== TGA埋点模块 ====================
  var TGAMock = {
    /**
     * 初始化 TGA 埋点模块
     * 空实现，仅输出调试日志，用于在浏览器环境中模拟 TGA 的初始化行为。
     * @returns {void}
     */
    init: function () {
      console.log("[TGA-Mock] init called");
    },
    /**
     * 上报 TGA 埋点事件
     * 空实现，仅输出事件名称和数据到控制台，用于调试目的。
     * @param {string} eventName - 事件名称
     * @param {Object} data - 事件附带的数据
     * @returns {void}
     */
    track: function (eventName, data) {
      console.log("[TGA-Mock] track:", eventName, data);
    },
    /**
     * TGA 快捷事件上报
     * 空实现，仅输出调试日志，用于模拟 TGA 的快捷埋点方法。
     * @returns {void}
     */
    quick: function () {
      console.log("[TGA-Mock] quick called");
    },
    /**
     * TGA 登录事件上报
     * 空实现，仅输出调试日志，用于模拟 TGA 的登录事件追踪。
     * @returns {void}
     */
    login: function () {
      console.log("[TGA-Mock] login called");
    },
    /**
     * 启用 TGA 埋点追踪
     * 空实现，仅输出调试日志，用于模拟启用追踪的行为。
     * @returns {void}
     */
    enableTracking: function () {
      console.log("[TGA-Mock] enableTracking called");
    },
    /**
     * 退出 TGA 埋点追踪
     * 空实现，仅输出调试日志，用于模拟退出追踪、停止数据上报的行为。
     * @returns {void}
     */
    optOutTracking: function () {
      console.log("[TGA-Mock] optOutTracking called");
    },
    tga: null,
  };
  TGAMock.tga = TGAMock;

  // ==========================================================================
  // 相册：chooseImage / saveImage（须在「完善 window.HSDK」之前挂到 HSDK 上，
  // 才能进入 functionNames / _mockFns 保护，避免 turnpass 盖成空实现）
  // PlatformH5：i.chooseImage(cb,{imageSize}) / i.saveImage(cb,{base64})
  // ==========================================================================
  window.__xyzwMediaCb = window.__xyzwMediaCb || {};
  window.__xyzwMediaPayload = window.__xyzwMediaPayload || {};
  window.__xyzwMediaDone = function (id, result) {
    try {
      var cb = window.__xyzwMediaCb[id];
      delete window.__xyzwMediaCb[id];
      if (typeof cb === "function") cb(result || { errCode: -1 });
    } catch (e) {
      console.warn("[HSDK-Mock] mediaDone", e);
    }
  };
  function postMedia(action, id, extra) {
    try {
      if (window.XyzwBridge && window.XyzwBridge.postMessage) {
        var payload = { type: "media", action: action, id: String(id) };
        if (extra) {
          for (var k in extra) {
            if (Object.prototype.hasOwnProperty.call(extra, k)) {
              payload[k] = extra[k];
            }
          }
        }
        window.XyzwBridge.postMessage(JSON.stringify(payload));
        return true;
      }
    } catch (e) {}
    return false;
  }
  function xyzwChooseImage(callback, options) {
    var id = "c" + Date.now() + "_" + Math.floor(Math.random() * 1e6);
    window.__xyzwMediaCb[id] =
      typeof callback === "function" ? callback : function () {};
    var imageSize =
      options && options.imageSize != null
        ? options.imageSize
        : typeof callback !== "function" && callback
          ? callback
          : null;
    if (typeof callback !== "function" && options == null && callback) {
      imageSize = callback.imageSize || callback;
    }
    console.warn("[HSDK-Mock] chooseImage", id, imageSize);
    if (
      !postMedia("chooseImage", id, {
        imageSize: imageSize || [512, 512],
      })
    ) {
      window.__xyzwMediaDone(id, {
        errCode: -1,
        errMsg: "no bridge",
        base64s: [],
      });
    }
  }
  xyzwChooseImage.__xyzwMedia = true;
  function xyzwSaveImage(callback, options) {
    var id = "s" + Date.now() + "_" + Math.floor(Math.random() * 1e6);
    window.__xyzwMediaCb[id] =
      typeof callback === "function" ? callback : function () {};
    var base64 = "";
    if (options && options.base64 != null) base64 = String(options.base64);
    else if (callback && typeof callback === "object" && callback.base64 != null) {
      base64 = String(callback.base64);
    }
    // 大图不塞进 JSChannel，暂存后由 Flutter 回读
    window.__xyzwMediaPayload[id] = base64;
    console.warn("[HSDK-Mock] saveImage", id, "len=" + base64.length);
    if (!postMedia("saveImage", id, { hasPayload: true })) {
      delete window.__xyzwMediaPayload[id];
      window.__xyzwMediaDone(id, { errCode: -1, errMsg: "no bridge" });
    }
  }
  xyzwSaveImage.__xyzwMedia = true;
  HSDK.chooseImage = xyzwChooseImage;
  HSDK.saveImage = xyzwSaveImage;

  // ==================== 完善 window.HSDK ====================
  // 直接增强现有的 window.HSDK 对象（由 patch.js 创建），而不是替换它。
  // 这样可以确保任何早期缓存的 HSDK 引用也能获取到新方法。
  (function () {
    // 确保 target 存在
    if (typeof window.HSDK !== "object" || !window.HSDK) {
      window.HSDK = {};
    }
    var target = window.HSDK;

    // ===== 复制所有 mock 函数到现有 HSDK 对象 =====
    // 为什么需要复制而不是直接替换 window.HSDK？
    //   因为 game 中可能已通过早期代码缓存了旧的 HSDK 引用，
    //   直接替换对象会影响这些引用。此处逐个复制方法到现有对象上，
    //   确保新旧引用都能访问到新方法。
    var functionNames = [
      "init",
      "realInit",
      "sdkConfig",
      "onLogin",
      "login",
      "setVibrate",

      "dialogLogin",
      "reportLoginState",
      "onAddictionQuit",
      "getGsSetting",
      "getDeviceInfo",
      "getNoticeInfo",
      "getNotice",
      "getNetworkType",
      "getHTLauchOptions",
      "getRealNameInfo",
      "getProtocolText",
      "setGameUserInfo",
      "weakLogin",
      "getBattery",
      "logout",
      "gameTrack",
      "showLoading",
      "hideLoading",
      "checkSwitches",
      "share",
      "showShareMenu",
      "updateShareMenu",
      "getUserInfo",
      "pay",
      "showAd",
      "trackEvent",
      "_fetchCryptRule",
      "_loginCheck",
      // 相册：PlatformH5 → i.chooseImage / i.saveImage（须纳入保护，防 turnpass 盖掉）
      "chooseImage",
      "saveImage",
    ];

    for (var i = 0; i < functionNames.length; i++) {
      var fnName = functionNames[i];
      if (typeof HSDK[fnName] === "function") {
        target[fnName] = HSDK[fnName];
      }
    }

    // ===== 复制数据属性 =====
    target.config = {};
    target.canLogin = true;
    target.canGetSwitch = true;
    target.deviceId = deviceUniqueId;
    target.cryptRule = null;
    target.codeBook = null;
    target.userSdk = null;
    target.initPromise = null;

    console.log(
      "[HSDK-Mock] dialogLogin available:",
      typeof target.dialogLogin === "function",
    );
    console.log(
      "[HSDK-Mock] HSDK 已增强，共复制",
      functionNames.length,
      "个方法",
    );

    // ===== 保护 HSDK 不被后续代码覆盖 =====
    // 保留同一个对象引用，但阻止被完全替换。
    // 注意：绝不能用「整对象合并」覆盖已有 mock 方法——
    // 旧版 HSDK.turnpass 若写入会把 init/dialogLogin 换成原生实现，WebView 里必挂。
    var _protected = target;
    var _mockFns = {};
    for (var mi = 0; mi < functionNames.length; mi++) {
      var mn = functionNames[mi];
      if (typeof _protected[mn] === "function") {
        _mockFns[mn] = _protected[mn];
      }
    }
    function restoreMockFns(reason) {
      var n = 0;
      for (var k in _mockFns) {
        if (_mockFns.hasOwnProperty(k) && _protected[k] !== _mockFns[k]) {
          _protected[k] = _mockFns[k];
          n++;
        }
      }
      if (n) console.log("[HSDK-Mock] 已恢复 mock 方法", n, reason || "");
    }
    Object.defineProperty(window, "HSDK", {
      get: function () {
        return _protected;
      },
      set: function (value) {
        if (value && typeof value === "object" && value !== _protected) {
          for (var key in value) {
            if (!value.hasOwnProperty(key)) continue;
            // 已有 mock 函数：不覆盖
            if (typeof _mockFns[key] === "function") continue;
            _protected[key] = value[key];
          }
          restoreMockFns("after-assign");
          console.log(
            "[HSDK-Mock] 外部尝试覆盖 HSDK，已合并非 mock 属性",
            Object.keys(value).length,
          );
        }
      },
      configurable: false,
      enumerable: true,
    });

    // turnpass / launcher 可能直接改 HSDK.xxx=，定时再钉一次 mock
    var _restoreTicks = 0;
    var _restoreIv = setInterval(function () {
      restoreMockFns("tick");
      if (++_restoreTicks > 40) clearInterval(_restoreIv);
    }, 500);

    console.log("[HSDK-Mock] HSDK 已保护，防止被外部覆盖");
  })();

  // ==========================================================================
  // Bootstrap 能力补齐
  // 说明：
  //   以下代码补齐了原本由 hsdk-bootstrap.js 提供的附加功能：
  //   - URL 登录参数读取（用于从 URL 中传入 userId/uid）
  //   - window.wx 基础模拟（避免游戏检查 wx 环境时报错）
  //   - 剪贴板功能（setClipboard / setClipboardData）
  //   - HSDK 平台标志位（isMT / isAlipay / isOverseaH5 等）
  //   - EventType / LogType 常量
  //   - window.__HORTOR_SDK__ 别名
  //   - signalSdkReady()：通知游戏加载器继续执行
  // ==========================================================================

  // --- URL 登录参数读取 ---
  /**
   * 从当前页面 URL 查询参数中提取登录凭据
   * 遍历 URL 查询参数，将其转换为键值对对象，用于模拟登录时从 URL 中传入 userId/uid 等参数。
   * @returns {Object} 包含所有 URL 查询参数的键值对对象
   */
  function readUrlLoginParams() {
    var params = {};
    try {
      new URLSearchParams(window.location.search).forEach(
        function (value, key) {
          params[key] = value;
        },
      );
    } catch (e) {}
    return params;
  }

  // window.wx mock（bootstrap 兼容）
  if (!window.wx) {
    window.wx = {
      getSystemInfo: function () {},
      getStorageInfo: function () {},
      onShow: function (callback) {
        window.setTimeout(function () {
          callback({ scene: "0", query: {}, shareTicket: [] });
        }, 168);
      },
      onHide: function () {},
    };
  }

  /**
   * 标准化剪贴板文本内容
   * 处理多种输入格式（字符串、包含 text 字段的对象、JSON 字符串等），统一提取并返回纯文本内容。
   * @param {*} value - 待标准化的输入值，可以是字符串、对象或 JSON 字符串
   * @returns {string} 提取出的纯文本字符串，无效输入返回空字符串
   */
  function normalizeClipboardText(value) {
    if (value === undefined || value === null) return "";
    if (typeof value === "string") {
      try {
        var parsed = JSON.parse(value);
        if (
          parsed &&
          typeof parsed === "object" &&
          Object.prototype.hasOwnProperty.call(parsed, "text")
        ) {
          var text = parsed.text;
          return text === undefined || text === null ? "" : String(text);
        }
      } catch (e) {}
      return value;
    }
    if (typeof value === "object") {
      if (Object.prototype.hasOwnProperty.call(value, "text")) {
        var inner = value.text;
        return inner === undefined || inner === null ? "" : String(inner);
      }
      try {
        return JSON.stringify(value);
      } catch (e2) {
        return String(value);
      }
    }
    return String(value);
  }

  /**
   * 复制文本到系统剪贴板
   * 优先使用 navigator.clipboard.writeText API，不支持时降级为创建隐藏 textarea 元素通过 execCommand('copy') 实现。
   * @param {*} text - 待复制的内容，支持字符串、对象或 JSON 字符串格式
   * @returns {void}
   */
  function copyToClipboard(text) {
    var payload = normalizeClipboardText(text);
    if (!payload) return;

    function fallbackCopy() {
      var area = document.createElement("textarea");
      area.value = payload;
      area.style.position = "fixed";
      area.style.left = "-9999px";
      area.style.top = "0";
      document.body.appendChild(area);
      area.focus();
      area.select();
      try {
        document.execCommand("copy");
      } catch (e) {}
      document.body.removeChild(area);
    }

    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(payload).catch(fallbackCopy);
    } else {
      fallbackCopy();
    }
  }

  /**
   * 为目标对象绑定 setClipboard / setClipboardData 剪贴板方法
   * 为 window、window.wx 或 __HORTOR_SDK__ 等对象添加剪贴板能力，避免游戏检查剪贴板 API 时报错。
   * @param {Object} target - 要绑定的目标对象（如 window、window.wx 等）
   * @returns {void}
   */
  function bindSetClipboard(target) {
    if (!target || typeof target.setClipboard === "function") return;
    target.setClipboard = function (options) {
      var text =
        options && (options.text || options.data) != null
          ? options.text || options.data
          : options;
      copyToClipboard(text);
      return Promise.resolve({ errMsg: "setClipboard:ok", data: text });
    };
    target.setClipboardData = function (options) {
      return target.setClipboard(options);
    };
  }

  bindSetClipboard(window);
  bindSetClipboard(window.wx);

  /**
   * 为目标对象绑定 setVibrate 震动方法（浏览器环境为空操作）
   * 游戏内部通过 HSDK.setVibrate(HSDK.VibrateType.Short/Long) 触发设备震动，
   * 浏览器中无震动 API，因此实现为空函数，避免 "HSDK.setVibrate is not a function" 报错。
   * @param {Object} target - 要绑定的目标对象（如 window.HSDK、window.wx 等）
   * @returns {void}
   */
  function bindSetVibrate(target) {
    if (!target || typeof target.setVibrate === "function") return;
    target.setVibrate = function (vibrateType) {
      // 浏览器环境不支持震动，静默忽略
    };
  }
  bindSetVibrate(window.HSDK);
  bindSetVibrate(window.wx);

  // 相册 API：再钉到 HSDK / wx / __HORTOR_SDK__（PlatformH5 抓的是后者）
  function bindMediaApis(target) {
    if (!target) return;
    if (typeof target.chooseImage !== "function" || !target.chooseImage.__xyzwMedia) {
      target.chooseImage = xyzwChooseImage;
    }
    if (typeof target.saveImage !== "function" || !target.saveImage.__xyzwMedia) {
      target.saveImage = xyzwSaveImage;
    }
  }
  function rebindMediaAll() {
    bindMediaApis(window.HSDK);
    bindMediaApis(window.wx);
    bindMediaApis(window.__HORTOR_SDK__);
  }
  // 注意：__HORTOR_SDK__ 赋值在下文；此处先钉 HSDK，稍后与定时器再钉别名
  rebindMediaAll();
  setTimeout(rebindMediaAll, 0);
  setTimeout(rebindMediaAll, 1500);
  setTimeout(rebindMediaAll, 5000);

  // HSDK 标志位与常量
  var hsdk = window.HSDK || {};
  hsdk.isMT = false;
  hsdk.isAlipay = /Alipay/i.test(
    (window.navigator && window.navigator.userAgent) || "",
  );
  hsdk.isOverseaH5 = false;
  hsdk.isOverseaH5TianYou = false;
  hsdk.isOverseaH5QingCi = false;
  hsdk.ApmPostArea = hsdk.ApmPostArea || { Default: 0 };
  hsdk.VibrateType = hsdk.VibrateType || { Short: 0, Long: 1 };
  hsdk.EventType = hsdk.EventType || { Track: "track" };
  hsdk.LogType = hsdk.LogType || { TGA: "tga" };

  // __HORTOR_SDK__ 别名：PlatformH5 在模块加载时会抓取
  // `var i = window.__HORTOR_SDK__`，随后用 `i.tga.track(...)` 打点。
  // 若此处把 patch.js 的 `{ tga }` 整对象覆盖成无 tga 的 HSDK，
  // HotUpdate 会在 TGA Option 打点时抛错 → LoadingError / 正在加载平台。
  if (typeof window.HSDK === "object" && window.HSDK) {
    window.HSDK.tga = TGAMock;
  }
  window.__HORTOR_SDK__ = window.HSDK;
  if (window.__HORTOR_SDK__) {
    window.__HORTOR_SDK__.tga = TGAMock;
  }
  window.TGA = TGAMock;
  bindSetClipboard(window.__HORTOR_SDK__);
  rebindMediaAll();

  /**
   * 发送 SDK 就绪信号，通知游戏加载器继续执行。
   *
   * 对照实测：launcher（CDN）远晚于 hsdk-mock 加载。原实现只等 60×50ms≈3s，
   * 信号往往在 `_hortor_callOnLoad` 出现前就放弃 → HotUpdate 后 LoadingError /
   * 「正在加载平台」。改为：挂钩赋值 + 长时间轮询，直到成功或 120s。
   */
  window.__sdkReadySignaled = false;
  function fireSdkReady(reason) {
    if (typeof window._hortor_callOnLoad !== "function") return false;
    try {
      window._hortor_callOnLoad(false, true);
      if (!window.__sdkReadySignaled) {
        window.__sdkReadySignaled = true;
        console.log("[HSDK-Mock] _hortor_callOnLoad(false,true) OK via", reason);
      }
      return true;
    } catch (e) {
      console.warn("[HSDK-Mock] _hortor_callOnLoad failed", e);
      return false;
    }
  }

  function signalSdkReady(attempt) {
    if (fireSdkReady("poll#" + (attempt || 0))) return;
    if ((attempt || 0) >= 2400) {
      // 120s
      console.warn("[HSDK-Mock] _hortor_callOnLoad 等待超时(120s)");
      return;
    }
    window.setTimeout(function () {
      signalSdkReady((attempt || 0) + 1);
    }, 50);
  }

  // 不在这里 Object.defineProperty(_hortor_callOnLoad)：
  // 会干扰 launcher 自己挂载回调（错误还可能被 compat 的 onerror 吞掉）。
  // 只做轮询；launcher 挂上后立即 fire。
  setTimeout(function () {
    signalSdkReady(0);
  }, 0);

  // ==========================================================================
  // 预获取开关配置
  // 说明：
  //   在脚本加载完成后立即发起网络请求，从 COMB 平台获取游戏开关配置。
  //   请求结果存入 window.__switchStore，供 checkSwitches() 方法查询。
  //   请求失败时使用 getDefaultSwitchData() 提供的降级数据。
  //
  // 为什么在文件末尾执行？
  //   确保此时所有变量（COMB_HOST、COMB_SDK_INFO、SWITCH_NAME_LIST 等）
  //   都已完成定义，避免引用未定义的变量。
  // ==========================================================================
  (function () {
    var url =
      COMB_HOST + "/comb-custom-switch-server/api/v1/switch/multi/status";
    console.log("[HSDK-Mock] Pre-fetching switches from:", url);
    fetch(url, {
      headers: {
        accept: "*/*",
        "accept-language": "zh-CN,zh;q=0.9",
        "content-type": "application/json",
        "sec-ch-ua":
          '"Google Chrome";v="149", "Chromium";v="149", "Not)A;Brand";v="24"',
        "sec-ch-ua-mobile": "?1",
        "sec-ch-ua-platform": '"Android"',
        "sec-fetch-dest": "empty",
        "sec-fetch-mode": "cors",
        "sec-fetch-site": "cross-site",
      },
      body: JSON.stringify({
        gameId: COMB_SDK_INFO.gameId,
        nickName: "",
        gameTp: "minigame",
        platform: "minigame",
        gameVersion: "2.35.1-3135a24bb68a 130a-wx",
        uniqueId: COMB_SDK_INFO.uniqueId,
        channel: COMB_SDK_INFO.channel,
        openId: COMB_SDK_INFO.userId,
        scene: 1001,
        defCustomParams: {
          audit: 0,
          pingtai: 5,
          opingtai: "",
          gameVersion: 11902,
          os: "Android",
        },
        switchIdList: SWITCH_NAME_LIST,
      }),
      method: "POST",
    })
      .then(function (res) {
        return res.json();
      })
      .then(function (response) {
        var data = {};
        if (
          response &&
          response.meta &&
          response.meta.errCode === 0 &&
          Array.isArray(response.data)
        ) {
          for (var i = 0; i < response.data.length; i++) {
            data[SWITCH_NAME_LIST[i]] = response.data[i];
          }
        } else {
          data = getDefaultSwitchData();
        }
        // 盐场/蟠桃：服务端常开 RejectLowVersionPvP；壳端版本比对易误伤，强制关闭
        data.RejectLowVersionPvP = 0;
        window.__switchStore = data;
        console.log("[HSDK-Mock] Switch data stored (RejectLowVersionPvP forced off)");
      })
      .catch(function (err) {
        console.error("[HSDK-Mock] Pre-fetch switches failed:", err);
        var fallback = getDefaultSwitchData();
        fallback.RejectLowVersionPvP = 0;
        window.__switchStore = fallback;
      });
  })();
})();
