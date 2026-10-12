/// 对照 naiwa-release:
/// `app/src/main/java/com/sharkking/assistant/core/InjectScripts.kt`
///
/// 含油猴兼容层、vh 修正、用户脚本 loader（正文走 HTTP，不塞 Binder）。
class InjectScripts {
  InjectScripts._();

  /// 登录请求体替换：把发往登录接口的 POST body 换成当前账号 bin。
  /// iOS WKWebView 可能在 pageStarted→finished 间丢 window 状态，故用 sessionStorage 兜底。
  static const xhrIntercept = r'''
(function(){
    function b64ToBuf(b64){
        if (!b64) return null;
        try {
            var bin = atob(b64);
            var u = new Uint8Array(bin.length);
            for (var i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i);
            return u.buffer;
        } catch (e) { return null; }
    }
    function restoreFromStorage(){
        try {
            var b64 = sessionStorage.getItem('__xyzwBinB64');
            var url = sessionStorage.getItem('__xyzwBinUrl');
            if (url && !window.__xyzwBinUrl) window.__xyzwBinUrl = url;
            if (b64 && !window.__activeBinBuf) {
                var buf = b64ToBuf(b64);
                if (buf) {
                    window.__activeBinBuf = buf;
                    console.log('[咸强之王] BIN从sessionStorage恢复', buf.byteLength);
                }
            }
        } catch (e) {}
    }
    restoreFromStorage();
    if(window.__xhrIntercepted) {
        restoreFromStorage();
        return;
    }
    window.__xhrIntercepted = true;
    var _open = XMLHttpRequest.prototype.open;
    var _send = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.open = function(m, u){
        this._m = m; this._u = u;
        this._isTarget = (m === 'POST' &&
            /hortorgames\.com\/login\/(authuser|serverlist)/.test(String(u||'')));
        return _open.apply(this, arguments);
    };
    function loadBinSync(){
        if (window.__activeBinBuf) return window.__activeBinBuf;
        restoreFromStorage();
        if (window.__activeBinBuf) return window.__activeBinBuf;
        var url = window.__xyzwBinUrl;
        if (!url) return null;
        try {
            var x = new XMLHttpRequest();
            x.open('GET', url, false);
            x.overrideMimeType('text/plain; charset=x-user-defined');
            x.send(null);
            if (x.status !== 200 || !x.responseText) {
                console.warn('[咸强之王] BIN同步拉取失败 status='+x.status+' url='+url);
                return null;
            }
            var s = x.responseText;
            var u = new Uint8Array(s.length);
            for (var i = 0; i < s.length; i++) u[i] = s.charCodeAt(i) & 0xff;
            window.__activeBinBuf = u.buffer;
            return u.buffer;
        } catch (e) {
            console.warn('[咸强之王] BIN同步拉取异常', e && e.message || e);
            return null;
        }
    }
    XMLHttpRequest.prototype.send = function(b){
        if (this._isTarget) {
            var buf = window.__activeBinBuf || loadBinSync();
            if (buf) {
                console.log('[咸强之王] 拦截XHR:', this._u, 'binBytes='+(buf.byteLength||0));
                return _send.call(this, buf);
            }
            console.error('[咸强之王] 登录请求未替换BIN（缓冲为空）', this._u);
        }
        return _send.apply(this, arguments);
    };
    // iOS WKWebView 上部分路径会走 fetch
    try {
      var _fetch = window.fetch;
      if (typeof _fetch === 'function' && !_fetch.__xyzwLoginHook) {
        var hooked = function(input, init){
          var url = (typeof input === 'string') ? input : (input && input.url) || '';
          var method = ((init && init.method) || (input && input.method) || 'GET').toUpperCase();
          var isTarget = method === 'POST' &&
            /hortorgames\.com\/login\/(authuser|serverlist)/.test(String(url||''));
          if (!isTarget) return _fetch.apply(this, arguments);
          var buf = window.__activeBinBuf || loadBinSync();
          if (!buf) {
            console.error('[咸强之王] fetch登录未替换BIN', url);
            return _fetch.apply(this, arguments);
          }
          console.log('[咸强之王] 拦截fetch:', url, 'binBytes='+buf.byteLength);
          var next = Object.assign({}, init || {}, { method: 'POST', body: buf });
          return _fetch.call(this, input, next);
        };
        hooked.__xyzwLoginHook = true;
        window.fetch = hooked;
      }
    } catch (e) {}
    console.log('[咸强之王] XHR拦截已启动');
})();
''';

  /// 盐场/蟠桃「点人」回归对照（和光/逆苍澜真因）：
  /// 1) 本地域被出站钩子假 200 吞掉  2) manifest 的 isLast/force* 被钉死导致活动 bundle 不拉
  /// 本壳无 outbound-hide / bin-login 钉 isLast，但仍记录这些字段与相关流量，便于真机对照。
  static const pvpDiagWatch = r'''
(function(){
  if (window.__xyzwPvpDiag) return;
  window.__xyzwPvpDiag = true;
  function post(obj){
    try {
      if (window.XyzwBridge && window.XyzwBridge.postMessage) {
        window.XyzwBridge.postMessage(JSON.stringify(obj));
      }
    } catch (e) {}
  }
  function log(){
    try {
      var args = Array.prototype.slice.call(arguments);
      console.log.apply(console, ['[咸强之王][PVP_DIAG]'].concat(args));
      post({ type: 'pvpDiag', level: 'I', message: args.map(String).join(' ') });
    } catch (e) {}
  }
  function warn(){
    try {
      var args = Array.prototype.slice.call(arguments);
      console.warn.apply(console, ['[咸强之王][PVP_DIAG]'].concat(args));
      post({ type: 'pvpDiag', level: 'W', message: args.map(String).join(' ') });
    } catch (e) {}
  }
  function isLocalFakeHost(host){
    host = String(host || '').toLowerCase();
    if (!host) return false;
    if (host === 'localhost' || host === '127.0.0.1' || host === '::1') return true;
    if (host === 'local' || host === 'game.local' || host === 'ncl.local') return true;
    if (/\.game\.local$/i.test(host) || /\.local$/i.test(host)) return true;
    return false;
  }
  function interestingUrl(u){
    var s = String(u || '').toLowerCase();
    return /manifest|authuser|serverlist|salt|yanchang|peach|pantao|legion|pvp|battle|match|activity|miniGame|bundle/i.test(s);
  }
  function summarizeManifest(obj){
    if (!obj || typeof obj !== 'object') return { parse: false };
    // 线上 Login_ManifestResp 形如 {cmd,body:{isLast,battleVersion,bundleVers,...}}
    var root = obj;
    var data = obj.body || obj.data || obj.rawData || obj;
    var bv = data && data.bundleVers;
    var codeVersion = '';
    try {
      if (typeof bv === 'string') bv = JSON.parse(bv);
      if (bv && typeof bv === 'object') codeVersion = bv.codeVersion || '';
    } catch (e0) {}
    var out = {
      parse: true,
      isLast: data && data.isLast,
      root_isLast: root.isLast,
      forceUpdate: data && data.forceUpdate,
      forceVer: data && data.forceVer,
      latestVer: data && data.latestVer,
      battleVersion: data && data.battleVersion,
      codeVersion: codeVersion,
      localCODE_VERSION: (typeof CODE_VERSION !== 'undefined' ? String(CODE_VERSION) : ''),
      dataBundleVer: (data && data.dataBundleVer) || '',
      dataVers: (data && data.dataVers) || '',
      serverUrl: (data && data.serverUrl) || '',
      bundleVersType: typeof (data && data.bundleVers)
    };
    out.codeMatch = !!(out.codeVersion && out.localCODE_VERSION && out.codeVersion === out.localCODE_VERSION);
    // 和光回归：客户端钉 isLast + 清空 latestVer 会让活动 bundle 不拉（服务端自带 isLast=true 正常）
    out.risk_pinIsLast = (out.isLast === true && out.latestVer === '');
    out.risk_emptyLatest = (out.latestVer === '' || out.latestVer === null);
    out.risk_codeMismatch = !!(out.codeVersion && out.localCODE_VERSION && !out.codeMatch);
    return out;
  }
  function inspectBody(url, text, tag){
    var s = String(text || '');
    if (!s) return;
    var low = String(url || '').toLowerCase();
    if (low.indexOf('manifest') >= 0 || /"isLast"\s*:/.test(s)) {
      try {
        var json = JSON.parse(s);
        var sum = summarizeManifest(json);
        log(tag, 'manifest', JSON.stringify(sum), 'url='+String(url).slice(0,160));
        if (sum.risk_pinIsLast && sum.risk_emptyLatest) {
          warn(tag, 'SUSPECT_MANIFEST_PIN isLast+emptyLatest（对照和光点人回归）');
        }
        post({ type: 'pvpDiag', level: 'D', event: 'manifest', summary: sum, url: String(url).slice(0,200) });
      } catch (e) {
        warn(tag, 'manifest非JSON', s.slice(0,120));
      }
    }
  }
  // —— fetch：记录本地域/比赛相关流量，绝不吞响应 ——
  try {
    var _fetch = window.fetch;
    if (typeof _fetch === 'function' && !_fetch.__xyzwPvpWrapped) {
      var wrapped = function(input, init){
        var url = '';
        var method = 'GET';
        try {
          url = (typeof input === 'string') ? input : (input && input.url) || '';
          method = ((init && init.method) || (input && input.method) || 'GET').toUpperCase();
        } catch (e) {}
        var host = '';
        try { host = new URL(String(url), location.href).hostname; } catch (e2) {}
        if (isLocalFakeHost(host)) {
          log('fetch-local-bypass', method, host, String(url).slice(0,160));
        } else if (interestingUrl(url)) {
          log('fetch', method, String(url).slice(0,180));
        }
        return _fetch.apply(this, arguments).then(function(res){
          try {
            if (interestingUrl(url) || /manifest/i.test(url)) {
              var clone = res.clone();
              clone.text().then(function(t){ inspectBody(url, t, 'fetch'); }).catch(function(){});
            }
          } catch (e3) {}
          return res;
        });
      };
      wrapped.__xyzwPvpWrapped = true;
      window.fetch = wrapped;
    }
  } catch (e) {}
  // —— XHR：同上 ——
  try {
    var XP = XMLHttpRequest && XMLHttpRequest.prototype;
    if (XP && XP.open && !XP.__xyzwPvpXhr) {
      XP.__xyzwPvpXhr = true;
      var _open = XP.open;
      var _send = XP.send;
      XP.open = function(method, url){
        this.__xyzwPvpUrl = String(url || '');
        this.__xyzwPvpMethod = String(method || 'GET');
        return _open.apply(this, arguments);
      };
      XP.send = function(){
        var xhr = this;
        var url = xhr.__xyzwPvpUrl || '';
        var method = (xhr.__xyzwPvpMethod || 'GET').toUpperCase();
        var host = '';
        try { host = new URL(url, location.href).hostname; } catch (e) {}
        if (isLocalFakeHost(host)) {
          log('xhr-local-bypass', method, host, url.slice(0,160));
        } else if (interestingUrl(url)) {
          log('xhr', method, url.slice(0,180));
        }
        if (interestingUrl(url) || /manifest/i.test(url)) {
          xhr.addEventListener('load', function(){
            try { inspectBody(url, xhr.responseText, 'xhr'); } catch (e2) {}
          });
        }
        return _send.apply(this, arguments);
      };
    }
  } catch (e) {}
  // 页面 origin / 本地域提示（对照：iOS 127.0.0.1 vs 自定义 scheme）
  try {
    log('origin', String(location.origin||''), 'href='+String(location.href||'').slice(0,160));
    if (isLocalFakeHost(location.hostname)) {
      log('page-on-local-fake-host', location.hostname, '（本地域流量必须直通，不可假200）');
    }
  } catch (e) {}
  console.log('[咸强之王][PVP_DIAG] 盐场/蟠桃诊断已启动');
})();
''';

  /// 盐场/蟠桃「客户端数据异常」修复 + 强化快照日志。
  /// 真机若仍失败，导出日志搜：PVP_SNAP / PVP_VER / CHECK_PVP / C_Battle_Tips
  static const pvpVersionGuard = r'''
(function(){
  if (window.__xyzwPvpVerGuard) return;
  window.__xyzwPvpVerGuard = true;
  var _patchFlags = {
    hsdkCheckSwitches: false,
    consoleCheckGameVer: false,
    consoleIsLowerProp: false,
    checkPvpBattle: false,
    isH5: false,
    codeSynced: false,
    hortorCheckSwitch: false,
    hortorMapForce: false,
    showTipHook: false
  };
  var _lastSnapJson = '';
  var _checkPvpHits = 0;
  var _showTipHits = 0;
  // 游戏 HortorSwitch 用字符串开关名（日志：开关RejectLowVersionPvP true）
  var FORCE_OFF = { RejectLowVersionPvP: 1 };
  var FORCE_ON = { FixYanChangClickEvent: 1 };
  function post(obj){
    try {
      if (window.XyzwBridge && window.XyzwBridge.postMessage) {
        window.XyzwBridge.postMessage(JSON.stringify(obj));
      }
    } catch (e) {}
  }
  function log(){
    try {
      var args = Array.prototype.slice.call(arguments);
      console.log.apply(console, ['[咸强之王][PVP_VER]'].concat(args));
      post({ type: 'pvpDiag', level: 'I', message: 'PVP_VER ' + args.map(String).join(' ') });
    } catch (e) {}
  }
  function warn(){
    try {
      var args = Array.prototype.slice.call(arguments);
      console.warn.apply(console, ['[咸强之王][PVP_VER]'].concat(args));
      post({ type: 'pvpDiag', level: 'W', message: 'PVP_VER ' + args.map(String).join(' ') });
    } catch (e) {}
  }
  function tryRequire(name){
    try {
      if (typeof window.__require === 'function') return window.__require(name);
    } catch (e) {}
    return null;
  }
  function readPlatform(){
    var out = { ok: false };
    try {
      var PM = tryRequire('PlatformManager');
      var inst = PM && (PM.PlatformManager && PM.PlatformManager.instance || PM.instance);
      if (!inst) return out;
      out.ok = true;
      try { out.isH5 = !!inst.isH5; } catch (e0) { out.isH5 = 'err'; }
      try { out.isNative = !!inst.isNative; } catch (e1) { out.isNative = 'err'; }
      try { out.isDev = !!inst.isDev; } catch (e2) { out.isDev = 'err'; }
      try { out.isWechatFamiliy = !!inst.isWechatFamiliy; } catch (e3) {}
      try {
        if (typeof inst.CHECK_SWITCH === 'function') {
          // 枚举值未知时尝试常见写法；失败不抛
          out.checkSwitchFn = true;
        }
      } catch (e4) {}
    } catch (e) {}
    return out;
  }
  function readConsole(){
    var out = { ok: false };
    try {
      var CM = tryRequire('ConsoleManager');
      var inst = CM && (CM.ConsoleManager && CM.ConsoleManager.instance || CM.instance);
      if (!inst) return out;
      out.ok = true;
      try { out.isLowerVersion = !!inst.isLowerVersion; } catch (e0) { out.isLowerVersion = 'err'; }
      try { out._isLowerVersion = !!inst._isLowerVersion; } catch (e1) {}
      out.checkGameVerPatched = !!(inst.checkGameVer && inst.checkGameVer.__xyzwPatched);
    } catch (e) {}
    return out;
  }
  function readBattle(){
    var out = { ok: false };
    try {
      var BU = tryRequire('BattleUIManager');
      if (!BU) return out;
      out.ok = true;
      out.hasCheck = typeof BU.CHECK_PVP_BATTLE_VERSION === 'function';
      out.checkPatched = !!(BU.CHECK_PVP_BATTLE_VERSION && BU.CHECK_PVP_BATTLE_VERSION.__xyzwPatched);
      try {
        if (typeof BU.GET_BATTLE_VERSION === 'function') out.battleVerFn = String(BU.GET_BATTLE_VERSION());
      } catch (e0) {}
    } catch (e) {}
    return out;
  }
  function readRole(){
    var out = {};
    try {
      var SD = tryRequire('ServerData');
      var R = SD && SD.ROLE;
      if (R) {
        out.roleId = R.roleId || R.id || 0;
        out.serverId = R.serverId || R.realServerId || 0;
        out.roleName = R.name || '';
      }
    } catch (e) {}
    return out;
  }
  function snapshot(reason){
    var snap = {
      reason: reason || '',
      ts: Date.now(),
      localCODE_VERSION: (typeof CODE_VERSION !== 'undefined' ? String(CODE_VERSION) : ''),
      windowCODE_VERSION: (window.CODE_VERSION != null ? String(window.CODE_VERSION) : ''),
      gameVersion: (typeof GAME_VERSION !== 'undefined' ? String(GAME_VERSION) : ''),
      remoteCodeVersion: '',
      remoteCommit: '',
      manifestIsLast: window.__xyzwManifestIsLast,
      manifestBattleVersion: window.__xyzwManifestBattleVersion,
      switchRejectStore: (window.__switchStore && window.__switchStore.RejectLowVersionPvP),
      switchRejectGame: null,
      switchFixYanChang: null,
      patches: _patchFlags,
      checkPvpHits: _checkPvpHits,
      showTipHits: _showTipHits,
      platform: readPlatform(),
      consoleMgr: readConsole(),
      battle: readBattle(),
      role: readRole()
    };
    try {
      var bv = window._CCSettings && window._CCSettings.bundleVers;
      if (bv) {
        snap.remoteCodeVersion = bv.codeVersion || '';
        snap.remoteCommit = bv.COMMIT_ID || '';
      }
    } catch (e0) {}
    try {
      var PM = tryRequire('PlatformManager');
      var pinst = PM && (PM.PlatformManager && PM.PlatformManager.instance || PM.instance);
      if (pinst && typeof pinst.checkSwitch === 'function') {
        try { snap.switchRejectGame = !!pinst.checkSwitch('RejectLowVersionPvP'); } catch (eR) {}
        try { snap.switchFixYanChang = !!pinst.checkSwitch('FixYanChangClickEvent'); } catch (eF) {}
      }
      if (PM && typeof PM.CHECK_SWITCH === 'function') {
        try { snap.switchRejectExport = !!PM.CHECK_SWITCH('RejectLowVersionPvP'); } catch (eE) {}
      }
    } catch (e1) {}
    snap.codeMatch = !snap.remoteCodeVersion || !snap.localCODE_VERSION ||
      (snap.remoteCodeVersion === snap.localCODE_VERSION);
    snap.risk_lower = !!(snap.consoleMgr && snap.consoleMgr.isLowerVersion);
    snap.risk_rejectOn = !!snap.switchRejectGame;
    snap.risk_yanChangOff = (snap.switchFixYanChang === false);
    var json = '';
    try { json = JSON.stringify(snap); } catch (e2) { json = String(snap); }
    // 相同内容不刷屏；reason 含 force/check/tip 时必打
    var force = /force|check|tip|anomaly|warn|SHOW_TIP/i.test(String(reason || ''));
    if (!force && json === _lastSnapJson) return snap;
    _lastSnapJson = json;
    console.log('[咸强之王][PVP_SNAP]', reason, json);
    post({ type: 'pvpSnapshot', reason: String(reason || ''), snap: snap });
    if (snap.risk_lower || snap.risk_rejectOn || snap.risk_yanChangOff || !snap.codeMatch) {
      warn('风险位', 'isLower='+snap.risk_lower, 'rejectOn='+snap.risk_rejectOn,
        'yanChangOff='+snap.risk_yanChangOff, 'codeMatch='+snap.codeMatch,
        'local='+snap.localCODE_VERSION, 'remote='+snap.remoteCodeVersion);
    }
    return snap;
  }
  function forceKey(name){
    var k = String(name || '');
    if (FORCE_OFF[k] || /RejectLowVersionPvP/i.test(k)) return false;
    if (FORCE_ON[k] || /FixYanChangClickEvent/i.test(k)) return true;
    return null;
  }
  function forceMap(map){
    if (!map || typeof map.set !== 'function') return false;
    try {
      map.set('RejectLowVersionPvP', false);
      map.set('FixYanChangClickEvent', true);
      // 若 key 是枚举数字，按已有 key 名扫一遍
      try {
        if (typeof map.forEach === 'function') {
          map.forEach(function(val, key){
            var k2 = String(key);
            if (/RejectLowVersionPvP/i.test(k2)) map.set(key, false);
            if (/FixYanChangClickEvent/i.test(k2)) map.set(key, true);
          });
        }
      } catch (eF) {}
      if (!map.set.__xyzwPvpPatched) {
        var oldSet = map.set.bind(map);
        var setWrap = function(key, val){
          var forced = forceKey(key);
          if (forced !== null) val = forced;
          return oldSet(key, val);
        };
        setWrap.__xyzwPvpPatched = true;
        map.set = setWrap;
      }
      return true;
    } catch (e) { return false; }
  }
  function patchHortorSwitches(){
    // 关键：游戏 CHECK_SWITCH → PlatformManager.checkSwitch
    // 优先读 this._config，否则读 _platform(HortorSwitch)._switchResult
    // HSDK.__switchStore 改了没用（今晚日志已证实：仍打印 开关RejectLowVersionPvP true）
    try {
      var PM = tryRequire('PlatformManager');
      var inst = PM && (PM.PlatformManager && PM.PlatformManager.instance || PM.instance);
      if (inst) {
        // 先改 _config（优先级最高）
        if (forceMap(inst._config)) {
          _patchFlags.hortorMapForce = true;
          if (!_patchFlags.hortorCheckSwitch) log('forced PlatformManager._config Reject=false YanChang=true');
        }
        if (typeof inst.checkSwitch === 'function' && !inst.checkSwitch.__xyzwPvpPatched) {
          var orig = inst.checkSwitch.bind(inst);
          var wrapped = function(id, defv){
            var key = (id == null) ? '' : String(id);
            var forced = forceKey(key);
            if (forced !== null) return forced;
            return orig(id, defv);
          };
          wrapped.__xyzwPvpPatched = true;
          inst.checkSwitch = wrapped;
          _patchFlags.hortorCheckSwitch = true;
          log('patched PlatformManager.checkSwitch');
        }
        // 深入 _platform 上的 HortorSwitch
        try {
          var plat = inst._platform;
          if (plat) {
            if (forceMap(plat._switchResult)) {
              _patchFlags.hortorMapForce = true;
              log('forced _platform._switchResult');
            }
            if (typeof plat.checkSwitch === 'function' && !plat.checkSwitch.__xyzwPvpPatched) {
              var op = plat.checkSwitch.bind(plat);
              var wp = function(id, defv){
                var key = (id == null) ? '' : String(id);
                var forced = forceKey(key);
                if (forced !== null) return forced;
                return op(id, defv);
              };
              wp.__xyzwPvpPatched = true;
              plat.checkSwitch = wp;
              log('patched _platform.checkSwitch');
            }
            for (var pk in plat) {
              try {
                var pv = plat[pk];
                if (pv && pv._switchResult && forceMap(pv._switchResult)) {
                  _patchFlags.hortorMapForce = true;
                }
              } catch (eP) {}
            }
          }
        } catch (ePlat) {}
      }
      if (PM && typeof PM.CHECK_SWITCH === 'function' && !PM.CHECK_SWITCH.__xyzwPvpPatched) {
        var orig2 = PM.CHECK_SWITCH;
        var wrapped2 = function(id, defv){
          var key = (id == null) ? '' : String(id);
          var forced = forceKey(key);
          if (forced !== null) return forced;
          return orig2(id, defv);
        };
        wrapped2.__xyzwPvpPatched = true;
        PM.CHECK_SWITCH = wrapped2;
        log('patched CHECK_SWITCH export');
      }
    } catch (e0) {}
    try {
      var HS = tryRequire('HortorSwitch');
      var hInst = HS && (HS.HortorSwitch && HS.HortorSwitch.instance);
      if (hInst && forceMap(hInst._switchResult)) {
        _patchFlags.hortorMapForce = true;
        log('forced HortorSwitch.instance map');
      }
    } catch (e3) {}
  }
  function hookShowTip(){
    try {
      // 多模块导出 SHOW_TIP；尽量钩常见名
      var names = ['UIHelper', 'TipManager', 'MessageManager'];
      for (var i = 0; i < names.length; i++) {
        var mod = tryRequire(names[i]);
        if (!mod) continue;
        var fn = mod.SHOW_TIP || (mod.default && mod.default.SHOW_TIP);
        if (typeof fn !== 'function' || fn.__xyzwTipPatched) continue;
        var orig = fn;
        var wrapped = function(msg){
          try {
            _showTipHits++;
            var s = (msg == null) ? '' : String(msg);
            log('SHOW_TIP', s.slice(0, 200));
            snapshot('SHOW_TIP:'+s.slice(0,80));
            post({ type: 'pvpDiag', level: 'W', event: 'SHOW_TIP', message: s.slice(0, 300) });
            // 盐场异常文案：记录后吞掉，避免只弹窗无日志
            if (/客户端数据异常|官方最新客户端|C_Battle_Tips|版本过低/.test(s)) {
              warn('拦截异常提示', s.slice(0, 120));
              post({
                type: 'clientAnomaly',
                kind: 'SHOW_TIP',
                key: '客户端数据异常',
                text: s.slice(0, 500),
                critical: true,
                fingerprint: { via: 'SHOW_TIP', pvp: true }
              });
              return;
            }
          } catch (e0) {}
          return orig.apply(this, arguments);
        };
        wrapped.__xyzwTipPatched = true;
        if (mod.SHOW_TIP) mod.SHOW_TIP = wrapped;
        if (mod.default && mod.default.SHOW_TIP) mod.default.SHOW_TIP = wrapped;
        _patchFlags.showTipHook = true;
        log('patched SHOW_TIP via', names[i]);
      }
    } catch (e) {}
    // 全局兜底：监听 fgui / 常见 tip 通道较难；再钩 console 已有
  }
  // 暴露给异常侦测：弹窗时附带快照
  window.__xyzwPvpSnapshot = function(reason){ return snapshot(reason || 'external'); };
  function forceRejectOff(){
    try {
      if (!window.__switchStore || typeof window.__switchStore !== 'object') {
        window.__switchStore = {};
      }
      var prev = window.__switchStore.RejectLowVersionPvP;
      window.__switchStore.RejectLowVersionPvP = 0;
      if (prev) log('force RejectLowVersionPvP', prev, '→ 0');
    } catch (e) {}
    try {
      var h = window.HSDK;
      if (h && typeof h.checkSwitches === 'function' && !h.checkSwitches.__xyzwPvpPatched) {
        var orig = h.checkSwitches.bind(h);
        var wrapped = function(args){
          var ret = orig(args);
          try {
            if (ret && typeof ret.then === 'function') {
              return ret.then(function(data){
                if (data && typeof data === 'object') data.RejectLowVersionPvP = 0;
                return data;
              });
            }
            if (ret && typeof ret === 'object') ret.RejectLowVersionPvP = 0;
          } catch (e2) {}
          return ret;
        };
        wrapped.__xyzwPvpPatched = true;
        h.checkSwitches = wrapped;
        _patchFlags.hsdkCheckSwitches = true;
        log('patched HSDK.checkSwitches');
      }
    } catch (e3) {}
  }
  function syncCodeVersion(){
    try {
      var remote = null;
      if (window._CCSettings && window._CCSettings.bundleVers && window._CCSettings.bundleVers.codeVersion) {
        remote = String(window._CCSettings.bundleVers.codeVersion);
      }
      if (remote) {
        if (typeof CODE_VERSION !== 'undefined') {
          try { CODE_VERSION = remote; } catch (e0) {}
        }
        try { window.CODE_VERSION = remote; } catch (e1) {}
        try { if (typeof globalThis !== 'undefined') globalThis.CODE_VERSION = remote; } catch (e2) {}
        if (!_patchFlags.codeSynced) {
          _patchFlags.codeSynced = true;
          log('sync CODE_VERSION', remote);
        }
      }
    } catch (e) {}
  }
  function markLastVersion(){
    var ok = false;
    try {
      var CM = tryRequire('ConsoleManager');
      var inst = CM && (CM.ConsoleManager && CM.ConsoleManager.instance || CM.instance);
      if (inst) {
        inst._isLowerVersion = false;
        if (typeof inst.checkGameVer === 'function' && !inst.checkGameVer.__xyzwPatched) {
          var old = inst.checkGameVer.bind(inst);
          var wrapped = function(){
            inst._isLowerVersion = false;
            try { old(); } catch (e5) {}
            inst._isLowerVersion = false;
            snapshot('after_checkGameVer');
          };
          wrapped.__xyzwPatched = true;
          inst.checkGameVer = wrapped;
          _patchFlags.consoleCheckGameVer = true;
          log('patched ConsoleManager.checkGameVer');
        }
        try {
          Object.defineProperty(inst, 'isLowerVersion', {
            configurable: true,
            enumerable: true,
            get: function(){ return false; },
            set: function(){}
          });
          _patchFlags.consoleIsLowerProp = true;
        } catch (eProp) {}
        ok = true;
      }
    } catch (e6) {}
    try {
      var BU = tryRequire('BattleUIManager');
      if (BU && typeof BU.CHECK_PVP_BATTLE_VERSION === 'function' && !BU.CHECK_PVP_BATTLE_VERSION.__xyzwPatched) {
        var wrappedCheck = function(battleType, showTip){
          _checkPvpHits++;
          var snap = snapshot('CHECK_PVP type='+battleType+' showTip='+showTip);
          // 不调用原函数，避免 SHOW_TIP；始终放行并记日志
          log('CHECK_PVP_BATTLE_VERSION bypass', 'type='+battleType, 'showTip='+showTip,
            'hits='+_checkPvpHits, 'isLower='+(snap.consoleMgr && snap.consoleMgr.isLowerVersion),
            'reject='+snap.switchReject);
          post({
            type: 'pvpDiag',
            level: 'W',
            event: 'CHECK_PVP',
            message: 'bypass type='+battleType+' showTip='+showTip+' hits='+_checkPvpHits,
            summary: snap
          });
          return true;
        };
        wrappedCheck.__xyzwPatched = true;
        BU.CHECK_PVP_BATTLE_VERSION = wrappedCheck;
        _patchFlags.checkPvpBattle = true;
        log('patched CHECK_PVP_BATTLE_VERSION → log+bypass');
        ok = true;
      }
    } catch (e7) {}
    return ok;
  }
  function softIsH5(){
    try {
      var PM = tryRequire('PlatformManager');
      var inst = PM && (PM.PlatformManager && PM.PlatformManager.instance || PM.instance);
      if (!inst) return;
      try {
        Object.defineProperty(inst, 'isH5', {
          configurable: true,
          enumerable: true,
          get: function(){ return true; },
          set: function(){}
        });
        if (!_patchFlags.isH5) {
          _patchFlags.isH5 = true;
          log('PlatformManager.isH5 forced true');
        }
      } catch (e1) {
        try {
          inst.isH5 = true;
          if (!_patchFlags.isH5) { _patchFlags.isH5 = true; log('PlatformManager.isH5 assigned true'); }
        } catch (e2) {}
      }
    } catch (e) {}
  }
  // 监听游戏自己打的开关/版本日志，立刻改 HortorSwitch 并出快照
  try {
    var _w = console.warn;
    if (typeof _w === 'function' && !_w.__xyzwPvpWarnHook) {
      var hw = function(){
        try {
          var text = Array.prototype.slice.call(arguments).map(String).join(' ');
          if (/RejectLowVersionPvP|FixYanChangClickEvent|isLast,\s*codeVersion|BATTLE_VERSION|GameVersionMisMatch|RemoteCodeMisMatch|CODE_GameVer_Lower|C_Battle_Tips/i.test(text)) {
            patchHortorSwitches();
            snapshot('warn:'+text.slice(0,120));
          }
        } catch (e0) {}
        return _w.apply(console, arguments);
      };
      hw.__xyzwPvpWarnHook = true;
      console.warn = hw;
    }
  } catch (eW) {}
  function tick(n){
    forceRejectOff();
    syncCodeVersion();
    softIsH5();
    markLastVersion();
    patchHortorSwitches();
    if (n === 3 || n === 10 || n === 25) hookShowTip();
    if (n === 0 || n === 5 || n === 15 || n === 30 || n % 20 === 0) {
      snapshot('tick_'+n);
    }
    if (n < 120) setTimeout(function(){ tick(n + 1); }, n < 20 ? 500 : 2000);
  }
  forceRejectOff();
  snapshot('boot');
  setTimeout(function(){ tick(0); }, 0);
  // 进盐场前用户可能停留较久：每 3 分钟补一张
  setInterval(function(){ snapshot('heartbeat_3m'); }, 180000);
  console.log('[咸强之王][PVP_VER] 盐场版本守卫+快照已启动 搜PVP_SNAP');
})();
''';

  /// 比赛/踢线常见「客户端数据异常」侦测：抓弹窗、toast、console，并上报指纹便于对照。
  static const clientAnomalyWatch = r'''
(function(){
  if (window.__xyzwClientWatch) return;
  window.__xyzwClientWatch = true;
  var KEYS = [
    '客户端数据异常', '官方最新客户端', '请使用官方',
    '版本过低', '强制更新', '登录失效', '异地登录',
    '连接已断开', '重新登录', '账号在其他', '被踢',
    'RejectLowVersionPvP', 'GameVersionMisMatch', 'RemoteCodeMisMatch',
    'C_Battle_Tips_1', 'CODE_GameVer_Lower', 'isLowerVersion',
    'client data', 'illegal client', 'official client'
  ];
  function hit(text){
    var s = String(text || '');
    if (!s) return null;
    // 忽略我们自己的诊断日志，避免假阳性淹没真弹窗
    if (s.indexOf('[咸强之王]') >= 0) return null;
    for (var i = 0; i < KEYS.length; i++) {
      if (s.indexOf(KEYS[i]) >= 0) return KEYS[i];
    }
    return null;
  }
  function fingerprint(){
    var out = {};
    try {
      out.href = String(location.href || '');
      out.ua = String(navigator.userAgent || '').slice(0, 220);
      out.platform = String(navigator.platform || '');
      out.lang = String(navigator.language || '');
      out.dpr = window.devicePixelRatio || 1;
      out.inner = (window.innerWidth||0) + 'x' + (window.innerHeight||0);
      out.vis = document.visibilityState;
      out.hidden = !!document.hidden;
      out.hasBuf = !!(window.__activeBinBuf && window.__activeBinBuf.byteLength);
      out.binBytes = window.__activeBinBuf && window.__activeBinBuf.byteLength || 0;
      out.xhrHook = !!window.__xhrIntercepted;
      out.hsdk = typeof window.HSDK;
      out.hsdkCanLogin = !!(window.HSDK && window.HSDK.canLogin);
      out._hsdkInit = !!window._hsdkInit;
      out.isH5 = !!(window.HSDK && window.HSDK.isH5);
      try {
        if (window.HSDK && typeof window.HSDK.getSystemInfo === 'function') {
          out.sys = window.HSDK.getSystemInfo();
        } else if (window.HSDK && window.HSDK.system && typeof window.HSDK.system.getSystemInfo === 'function') {
          out.sys = window.HSDK.system.getSystemInfo();
        }
      } catch (e1) {}
      try {
        if (window.HSDK && typeof window.HSDK.getPlatform === 'function') {
          out.sdkPlatform = window.HSDK.getPlatform();
        }
      } catch (e2) {}
      try {
        var req = window.__require;
        if (typeof req === 'function') {
          var SD = req('ServerData');
          var R = SD && SD.ROLE;
          if (R) {
            out.roleId = R.roleId || R.id || 0;
            out.serverId = R.serverId || R.realServerId || 0;
            out.roleName = R.name || '';
          }
        }
      } catch (e3) {}
      // 盐场关键字段：失败时对照 PVP_SNAP
      try {
        out.CODE_VERSION = (typeof CODE_VERSION !== 'undefined' ? String(CODE_VERSION) : '');
        out.remoteCodeVersion = (window._CCSettings && window._CCSettings.bundleVers && window._CCSettings.bundleVers.codeVersion) || '';
        out.manifestIsLast = window.__xyzwManifestIsLast;
        out.manifestBattleVersion = window.__xyzwManifestBattleVersion;
        out.switchReject = window.__switchStore && window.__switchStore.RejectLowVersionPvP;
        out.codeMatch = !!(out.CODE_VERSION && out.remoteCodeVersion && out.CODE_VERSION === out.remoteCodeVersion);
      } catch (e4) {}
      out.ts = Date.now();
    } catch (e) {
      out.err = String(e && e.message || e);
    }
    return out;
  }
  var _repCount = 0;
  var _repWindow = 0;
  var _reporting = false;
  function report(kind, text, extra){
    try {
      var href = String(location.href || '');
      // about:blank / 丢弃中的页不要报，否则会递归刷爆日志卡死主线程
      if (href.indexOf('about:') === 0) return;
      var raw = String(text || '');
      if (raw.indexOf('[CLIENT_ANOMALY]') >= 0 || raw.indexOf('CLIENT_ANOMALY') >= 0) return;
      if (raw.indexOf('[咸强之王]') >= 0 && kind.indexOf('console') === 0) return;
      if (_reporting) return;
      var now = Date.now();
      if (now - _repWindow > 3000) { _repWindow = now; _repCount = 0; }
      // 真弹窗关键字放宽限额；噪音类仍限流
      var key = hit(text);
      var critical = key && /客户端数据异常|官方最新|C_Battle|GameVersionMisMatch|CODE_GameVer|isLowerVersion/.test(key+raw);
      if (_repCount >= (critical ? 20 : 8)) return;
      if (!key && kind !== 'fingerprint') return;
      _repCount++;
      _reporting = true;
      var fp = fingerprint();
      try {
        if (critical && typeof window.__xyzwPvpSnapshot === 'function') {
          fp.pvpSnap = window.__xyzwPvpSnapshot('anomaly:'+key);
        }
      } catch (eSnap) {}
      var payload = {
        type: 'clientAnomaly',
        kind: kind,
        key: key || '',
        text: raw.slice(0, 800),
        fingerprint: fp,
        extra: extra || null,
        critical: !!critical
      };
      // 禁止再用 console.error，否则会再次命中 wrapConsole → 死循环
      try {
        if (window.XyzwBridge && window.XyzwBridge.postMessage) {
          window.XyzwBridge.postMessage(JSON.stringify(payload));
        }
      } catch (e) {}
    } catch (e2) {
    } finally {
      _reporting = false;
    }
  }
  function wrapConsole(name){
    try {
      var orig = console[name];
      if (typeof orig !== 'function' || orig.__xyzwWrapped) return;
      var wrapped = function(){
        try {
          var args = Array.prototype.slice.call(arguments);
          var text = args.map(function(a){
            try { return typeof a === 'string' ? a : JSON.stringify(a); }
            catch (e) { return String(a); }
          }).join(' ');
          if (hit(text)) report('console.'+name, text);
        } catch (e) {}
        return orig.apply(console, arguments);
      };
      wrapped.__xyzwWrapped = true;
      console[name] = wrapped;
    } catch (e) {}
  }
  ['log','warn','error','info','debug'].forEach(wrapConsole);
  try {
    var _alert = window.alert;
    window.alert = function(msg){
      report('alert', msg);
      return _alert.apply(this, arguments);
    };
  } catch (e) {}
  try {
    var _confirm = window.confirm;
    window.confirm = function(msg){
      report('confirm', msg);
      return _confirm.apply(this, arguments);
    };
  } catch (e) {}
  // DOM 文案（弹窗/toast）
  try {
    var mo = new MutationObserver(function(muts){
      for (var i = 0; i < muts.length; i++) {
        var nodes = muts[i].addedNodes || [];
        for (var j = 0; j < nodes.length; j++) {
          var n = nodes[j];
          if (!n || n.nodeType !== 1) continue;
          var t = (n.innerText || n.textContent || '').trim();
          if (t && t.length < 800 && hit(t)) report('dom', t);
        }
      }
    });
    mo.observe(document.documentElement, { childList: true, subtree: true });
  } catch (e) {}
  // 前后台
  document.addEventListener('visibilitychange', function(){
    console.log('[咸强之王][lifecycle] visibility='+document.visibilityState+' hidden='+document.hidden);
  });
  window.addEventListener('pagehide', function(){
    console.log('[咸强之王][lifecycle] pagehide');
  });
  window.addEventListener('pageshow', function(ev){
    console.log('[咸强之王][lifecycle] pageshow persisted='+!!(ev&&ev.persisted));
  });
  // 启动后落一份指纹基线，比赛异常时可对照
  setTimeout(function(){ report('fingerprint', 'baseline'); }, 3500);
  console.log('[咸强之王] 客户端异常侦测已启动');
})();
''';

  /// 应用内切号时，阻止 Page Visibility / Cocos 把后台会话暂停。
  /// （切到别的 App 仍受 iOS 进程挂起限制；回前台由 [foregroundResume] 触发 onShow/重连。）
  static const visibilityKeepAlive = r'''
(function(){
  if (window.__xyzwVisKeep) return;
  window.__xyzwVisKeep = true;
  function freezeVis(){
    try {
      var props = ['hidden','webkitHidden','mozHidden','msHidden'];
      props.forEach(function(p){
        try {
          Object.defineProperty(document, p, { configurable: true, get: function(){ return false; }});
        } catch (e) {}
      });
      try {
        Object.defineProperty(document, 'visibilityState', {
          configurable: true,
          get: function(){ return 'visible'; }
        });
      } catch (e2) {}
    } catch (e) {}
  }
  freezeVis();
  function eat(e){
    try { e.stopImmediatePropagation(); e.preventDefault(); } catch (err) {}
  }
  ['visibilitychange','webkitvisibilitychange','mozvisibilitychange',
   'msvisibilitychange','qbrowserVisibilityChange','pagehide','freeze'].forEach(function(n){
    window.addEventListener(n, eat, true);
    document.addEventListener(n, eat, true);
  });
  function keepCocos(){
    try {
      var g = window.cc && cc.game;
      if (g && typeof g.resume === 'function') {
        if (typeof g.isPaused === 'function' ? g.isPaused() : false) {
          g.resume();
          console.log('[咸强之王][keepalive] cc.game.resume');
        }
      }
    } catch (e) {}
  }
  function hookPause(){
    try {
      var g = window.cc && cc.game;
      if (!g || g.__xyzwPauseHook || typeof g.pause !== 'function') return !!g && !!g.__xyzwPauseHook;
      var _pause = g.pause.bind(g);
      g.pause = function(){
        console.log('[咸强之王][keepalive] 忽略 cc.game.pause（保活后台活动）');
        try { freezeVis(); } catch (e) {}
        setTimeout(keepCocos, 0);
      };
      g.__xyzwPauseHook = true;
      g.__xyzwOrigPause = _pause;
      return true;
    } catch (e) { return false; }
  }
  if (!hookPause()) {
    var n = 0;
    var iv = setInterval(function(){
      if (hookPause() || ++n > 160) clearInterval(iv);
    }, 400);
  }
  setInterval(function(){
    freezeVis();
    keepCocos();
  }, 4000);
  console.log('[咸强之王][keepalive] 可见性冻结已安装');
})();
''';

  /// 收集 wx.onShow/onHide，供 Flutter 回前台时主动触发（游戏常在 onShow 里重连）。
  static const appLifecycleBridge = r'''
(function(){
  if (window.__xyzwLifeBridge) return;
  window.__xyzwLifeBridge = true;
  var shows = [];
  var hides = [];
  function wrapWx(){
    try {
      var wx = window.wx || (window.wx = {});
      if (wx.__xyzwShowWrapped) return;
      var prevShow = wx.onShow;
      var prevHide = wx.onHide;
      wx.onShow = function(cb){
        if (typeof cb === 'function') shows.push(cb);
        if (typeof prevShow === 'function') {
          try { prevShow.call(wx, cb); } catch (e) {}
        }
      };
      wx.onHide = function(cb){
        if (typeof cb === 'function') hides.push(cb);
        if (typeof prevHide === 'function') {
          try { prevHide.call(wx, cb); } catch (e) {}
        }
      };
      wx.__xyzwShowWrapped = true;
    } catch (e) {}
  }
  wrapWx();
  var n = 0;
  var iv = setInterval(function(){
    wrapWx();
    if (++n > 80) clearInterval(iv);
  }, 200);
  window.__xyzwFireShow = function(){
    console.log('[咸强之王][lifecycle] fire onShow n='+shows.length);
    var payload = { scene: '0', query: {}, shareTicket: [] };
    shows.slice().forEach(function(cb){
      try { cb(payload); } catch (e) {}
    });
  };
  window.__xyzwFireHide = function(){
    console.log('[咸强之王][lifecycle] fire onHide n='+hides.length);
    hides.slice().forEach(function(cb){
      try { cb(); } catch (e) {}
    });
  };
})();
''';

  /// Flutter App 从后台回到游戏页：恢复 Cocos + 触发 onShow + 尝试网络重连。
  static const foregroundResume = r'''
(function(){
  try {
    if (typeof window.__xyzwFireShow === 'function') window.__xyzwFireShow();
  } catch (e0) {}
  try {
    if (window.cc && cc.game && typeof cc.game.resume === 'function') cc.game.resume();
    if (window.cc && cc.director && typeof cc.director.resume === 'function') cc.director.resume();
  } catch (e1) {}
  try { window.dispatchEvent(new Event('online')); } catch (e2) {}
  try {
    var cands = [window.Network, window.network, window.g_network, window.net, window.GameNet];
    for (var i = 0; i < cands.length; i++) {
      var n = cands[i];
      if (!n) continue;
      if (typeof n.reconnect === 'function') { n.reconnect(); console.log('[咸强之王][lifecycle] reconnect', i); }
      else if (typeof n.reConnect === 'function') { n.reConnect(); }
      else if (typeof n.connect === 'function') { n.connect(); }
    }
  } catch (e3) {}
  console.log('[咸强之王][lifecycle] foregroundResume done');
})();
''';

  /// 全局错误吞噬 + 安全剪贴板 + execCommand 兜底
  static const compat = r'''

(function(){
    if(window.__compatInstalled) return;
    window.__compatInstalled = true;

    window.onerror = function(msg, src, line, col, err){
        console.warn('[咸强之王] onerror', msg, src, line, col, err && err.stack);
        return true;
    };
    window.addEventListener('error', function(e){
        console.warn('[咸强之王] error-event', e && e.message, e && e.filename, e && e.lineno);
        e.preventDefault(); e.stopPropagation();
    }, true);
    window.addEventListener('unhandledrejection', function(e){
        console.warn('[咸强之王] unhandledrejection', e && e.reason);
        e.preventDefault(); e.stopPropagation();
    }, true);

    var _cb = '';
    window.setClipboard = function(t){
        if (t === undefined || t === null) return;
        var text = (typeof t === 'object') ? (t.text || JSON.stringify(t)) : String(t);
        _cb = text;
        try {
            if (navigator.clipboard && navigator.clipboard.writeText) {
                navigator.clipboard.writeText(text);
            }
        } catch(e) {}
    };

    try {
        var _ec = document.execCommand;
        document.execCommand = function(cmd){
            if (cmd === 'copy') {
                try {
                    _cb = window.getSelection ? window.getSelection().toString() : '';
                } catch(e) {}
                return true;
            }
            if (cmd === 'paste') return true;
            return _ec.apply(this, arguments);
        };
    } catch(e) {}

    document.addEventListener('copy', function(e){ e.stopPropagation(); }, true);

    // 禁止网页全屏：否则 Android WebView 会 push 全屏页盖住 Flutter 顶部栏
    try {
      var noopFs = function(){ return Promise.resolve(); };
      var elProto = Element.prototype;
      elProto.requestFullscreen = noopFs;
      elProto.webkitRequestFullscreen = noopFs;
      elProto.webkitRequestFullScreen = noopFs;
      elProto.mozRequestFullScreen = noopFs;
      elProto.msRequestFullscreen = noopFs;
      if (document.exitFullscreen) document.exitFullscreen = noopFs;
    } catch(e) {}

    // 限制 DPR，减轻 Cocos WebGL 压力（模拟器/高分屏更明显）
    try {
      var _dpr = window.devicePixelRatio || 1;
      var _cap = Math.min(1.5, _dpr);
      if (_cap < _dpr) {
        Object.defineProperty(window, 'devicePixelRatio', {
          configurable: true,
          get: function(){ return _cap; }
        });
      }
    } catch(e) {}

    console.log('[咸强之王] 兼容脚本已注入');
})();
''';

  /// HotUpdate 阶段诊断：确认仍走 hsdk-mock，而非被旧 turnpass 盖掉
  static const hsdkProbe = r'''
(function(){
  function probe(tag){
    try {
      var h = window.HSDK;
      console.log('[咸强之王] HSDK probe '+tag+
        ' init='+(typeof (h&&h.init))+
        ' dialogLogin='+(typeof (h&&h.dialogLogin))+
        ' canLogin='+(h&&h.canLogin)+
        ' _hsdkInit='+window._hsdkInit+
        ' checkUpdate='+window.checkUpdate+
        ' callOnLoad='+(typeof window._hortor_callOnLoad)+
        ' signaled='+!!window.__sdkReadySignaled);
    } catch(e) { console.warn('[咸强之王] HSDK probe fail', e); }
  }
  probe('early');
  setTimeout(function(){ probe('2s'); }, 2000);
  setTimeout(function(){ probe('5s'); }, 5000);
  setTimeout(function(){ probe('12s'); }, 12000);
})();
''';

  /// launcher 挂载较晚：页面完成后持续补打 SDK 就绪信号（对照 Pro 可运行壳）
  static const lateSdkReady = r'''
(function(){
  if (window.__yukeLateSdk) return;
  window.__yukeLateSdk = true;
  var n = 0;
  var iv = setInterval(function(){
    n++;
    if (typeof window._hortor_callOnLoad === 'function') {
      try {
        window._hortor_callOnLoad(false, true);
        console.log('[咸强之王] lateSdkReady fired #'+n);
      } catch(e) {}
      // 多打几次，避免 HotUpdate 尚未订阅
      if (n > 30) clearInterval(iv);
    }
    if (n > 600) clearInterval(iv);
  }, 200);
})();
''';

  /// 把选中账号的 bin 写成 HTTP 地址，页面按需拉取（备用）。
  static String activateBinUrl(String url, String label) {
    final safeUrl = url.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
    final safeLabel = label.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
    return '''
(function(){
    window.__xyzwBinUrl = '$safeUrl';
    try { sessionStorage.setItem('__xyzwBinUrl', window.__xyzwBinUrl); } catch (e0) {}
    try {
      var x = new XMLHttpRequest();
      x.open('GET', window.__xyzwBinUrl, true);
      x.responseType = 'arraybuffer';
      x.onload = function(){
        if (x.status === 200 && x.response) {
          window.__activeBinBuf = x.response;
          console.log('[咸强之王] BIN异步拉取成功', x.response.byteLength);
        } else {
          console.warn('[咸强之王] BIN异步拉取失败', x.status, window.__xyzwBinUrl);
        }
      };
      x.onerror = function(){ console.warn('[咸强之王] BIN异步拉取网络错误', window.__xyzwBinUrl); };
      x.send();
    } catch (e) { console.warn('[咸强之王] BIN异步拉取异常', e); }
    console.log('[咸强之王] 已注入BIN地址:', '$safeLabel', window.__xyzwBinUrl);
})();
''';
  }

  /// iOS 优先：由 Dart 注入 base64，不依赖 WKWebView 同步 XHR。
  static String activateBinBase64(String base64, String label) {
    final safeLabel = label.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
    // 分段，避免单次 evaluateJavascript 过长
    const chunk = 240000;
    final parts = <String>[];
    for (var i = 0; i < base64.length; i += chunk) {
      final end = (i + chunk < base64.length) ? i + chunk : base64.length;
      parts.add(base64.substring(i, end));
    }
    final buf = StringBuffer()
      ..writeln('(function(){')
      ..writeln("window.__xyzwBinB64Parts=[];");
    for (final p in parts) {
      final safe = p.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
      buf.writeln("window.__xyzwBinB64Parts.push('$safe');");
    }
    buf.writeln('''
try {
  var b64 = window.__xyzwBinB64Parts.join('');
  window.__xyzwBinB64Parts = null;
  try { sessionStorage.setItem('__xyzwBinB64', b64); } catch (e0) {}
  var bin = atob(b64);
  var u = new Uint8Array(bin.length);
  for (var i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i);
  window.__activeBinBuf = u.buffer;
  console.log('[咸强之王] 已注入BIN缓冲', u.length, '$safeLabel');
} catch (e) {
  console.error('[咸强之王] BIN base64注入失败', e && e.message || e);
}
})();
''');
    return buf.toString();
  }

  /// 浅底 + 延后收起 Flutter 加载层，避免 canvas 仍黑时就露出黑屏。
  static const gameReadyWatch = r'''
(function(){
  if (window.__xyzwReadyWatch) return;
  window.__xyzwReadyWatch = true;
  try {
    var s = document.createElement('style');
    s.id = 'xyzw-boot-style';
    s.textContent = 'html,body,#GameCanvas,#splash{background:#F2F2F7!important;}';
    (document.head || document.documentElement).appendChild(s);
  } catch (e) {}
  var n = 0;
  var t = setInterval(function(){
    n++;
    var c = document.getElementById('GameCanvas') || document.querySelector('canvas');
    var sized = c && (c.width || 0) > 8 && (c.height || 0) > 8;
    var sdk = !!(window.__sdkReadySignaled || window._hsdkInit ||
      (window.HSDK && window.HSDK.canLogin));
    // 至少等约 2.5s，且 canvas 已尺寸化或 SDK 就绪，再收起壳加载层
    var ok = sized && (sdk || n >= 25);
    if (ok || n >= 180) {
      clearInterval(t);
      try {
        var st = document.getElementById('xyzw-boot-style');
        if (st && st.parentNode) st.parentNode.removeChild(st);
      } catch (e) {}
      try {
        if (window.XyzwBridge && window.XyzwBridge.postMessage) {
          XyzwBridge.postMessage(JSON.stringify({ type: 'gameReady' }));
        }
      } catch (e) {}
    }
  }, 100);
})();
''';

  /// 进游戏后从运行时抓角色名/头像，经 `XyzwBridge` 回传；带详细日志。
  static const roleBridge = r'''
(function(){
  if (window.__xyzwRoleBridge) return;
  window.__xyzwRoleBridge = true;
  var last = '';
  var dumpOnce = false;
  var tries = 0;
  function post(obj){
    try {
      if (window.XyzwBridge && window.XyzwBridge.postMessage) {
        window.XyzwBridge.postMessage(JSON.stringify(obj));
      }
    } catch (e) {}
  }
  function log(msg){
    console.log('[咸强之王][avatar] ' + msg);
    post({ type: 'roleLog', message: String(msg) });
  }
  function resolveSkinUrl(skinId){
    try {
      var Configs = window.__require && window.__require('Configs');
      var AC = Configs && Configs.AvatarConf;
      if (!AC) return '';
      var conf = (typeof AC.getById === 'function') ? AC.getById(skinId) : AC[String(skinId)];
      if (!conf) return '';
      var path = conf.smallHeadIcon || conf.headIcon || '';
      if (!path) return '';
      var cc = window.cc;
      var am = cc && (cc.assetManager || (cc.AssetManager && cc.AssetManager.instance));
      var bundles = am && am.bundles;
      if (!bundles) return '';
      var hitName = '', hit = null;
      var pick = function(name, bundle){
        try {
          var cfg = bundle && (bundle._config || bundle.config);
          var map = cfg && cfg.paths && cfg.paths._map;
          if (!map) return false;
          var entries = (typeof map.get === 'function') ? map.get(path) : map[path];
          if (!entries || !entries.length) return false;
          for (var i = 0; i < entries.length; i++) {
            var e = entries[i];
            if (e && e.nativeVer && e.uuid) { hitName = name; hit = e; return true; }
          }
        } catch (err) {}
        return false;
      };
      if (typeof bundles.forEach === 'function') {
        bundles.forEach(function(b, name){ if (!hit) pick(name, b); });
      } else {
        for (var name in bundles) { if (pick(name, bundles[name])) break; }
      }
      if (!hit) return '';
      return 'https://xxz-xyzw-res.hortorgames.com/remote/' + hitName + '/native/' +
        hit.uuid.slice(0, 2) + '/' + hit.uuid + '.' + hit.nativeVer + '.png';
    } catch (e) { return ''; }
  }
  function marsFace(roleId, headImg){
    if (headImg === undefined || headImg === null || headImg === '' || headImg === 0) return '';
    var s = String(headImg).trim();
    if (!s || s === 'null') return '';
    if (s.indexOf('http://') === 0 || s.indexOf('https://') === 0) {
      if (s.indexOf('xxz-xyzw-res.hortorgames.com') >= 0 && s.indexOf('xxz-xyzw-head-img') >= 0) {
        s = s.replace('xxz-xyzw-res.hortorgames.com', 'mars-face.hortorgames.com');
      }
      return s;
    }
    if (s.indexOf('xxz-xyzw-head-img') >= 0 || s.indexOf('mars-face') >= 0) {
      if (s.charAt(0) !== '/') s = '/' + s;
      return 'https://mars-face.hortorgames.com' + s;
    }
    if (!roleId) return '';
    var ver = Number(s);
    if (!isFinite(ver) || ver <= 0) return '';
    if (ver > 20000000000) ver = Math.floor(ver / 1000);
    return 'https://mars-face.hortorgames.com/xxz-xyzw-head-img/release/' +
      roleId + '/' + ver + '.jpg';
  }
  function digRole(){
    var out = { role: null, from: '' };
    try {
      var req = window.__require;
      if (typeof req === 'function') {
        try {
          var SD = req('ServerData');
          if (SD && SD.ROLE) { out.role = SD.ROLE; out.from = 'ServerData.ROLE'; return out; }
        } catch (e1) {}
        try {
          var Player = req('Player');
          var p = Player && (Player.instance || Player.Instance || Player);
          if (p && (p.role || p.ROLE || p.roleInfo)) {
            out.role = p.role || p.ROLE || (p.roleInfo && (p.roleInfo.role || p.roleInfo));
            out.from = 'Player';
            if (out.role) return out;
          }
        } catch (e2) {}
      }
    } catch (e) {}
    var g = window.g_player || window.player || window.__ROLE__;
    if (g) { out.role = g.role || g; out.from = 'window'; }
    return out;
  }
  function dumpRole(role, from){
    if (dumpOnce || !role) return;
    dumpOnce = true;
    try {
      var keys = Object.keys(role).slice(0, 50).join(',');
      var head = role.headImg;
      var headType = (head === null || head === undefined) ? 'null' : typeof head;
      log('ROLE from=' + from +
        ' roleId=' + (role.roleId || role.id || 0) +
        ' name=' + (role.name || '') +
        ' headImg=' + head + '(' + headType + ')' +
        ' lordSkinId=' + (role.lordSkinId || 0) +
        ' keys=' + keys);
    } catch (e) {
      log('dumpRole err ' + e);
    }
  }
  function pick(){
    tries++;
    try {
      var dug = digRole();
      var ROLE = dug.role;
      var name = null, avatar = null, skin = 0, roleId = 0, rawHead = null;
      if (ROLE) {
        dumpRole(ROLE, dug.from);
        if (ROLE.name) name = String(ROLE.name);
        roleId = Number(ROLE.roleId || ROLE.id || 0) || 0;
        skin = Number(ROLE.lordSkinId || 0) || 0;
        rawHead = ROLE.headImg;
        if (rawHead === undefined || rawHead === null || rawHead === '') {
          rawHead = ROLE.headimg || ROLE.headUrl || ROLE.avatar || ROLE.headImgUrl || null;
        }
        avatar = marsFace(roleId, rawHead) || '';
        if (!avatar && skin) avatar = resolveSkinUrl(skin) || '';
      } else if (tries <= 3 || tries % 10 === 0) {
        log('ROLE 尚未就绪 try=' + tries +
          ' __require=' + (typeof window.__require) +
          ' cc=' + !!(window.cc));
      }
      if (!name) {
        var cands = [window.__ROLE_NAME__, window.roleName, window.nickName, window.playerName];
        for (var i = 0; i < cands.length; i++) {
          if (typeof cands[i] === 'string' && cands[i].trim()) { name = cands[i].trim(); break; }
        }
      }
      if (!avatar) {
        avatar = window.__ROLE_AVATAR__ || window.roleAvatar || window.headUrl || null;
      }
      if (!name && !roleId) return;
      // 没有真头像就回传空，Flutter 侧继续用本地默认头
      var payload = {
        type: 'role',
        name: name || '',
        avatar: avatar || '',
        roleId: roleId || 0,
        headImgRaw: (rawHead === undefined || rawHead === null) ? '' : String(rawHead),
        lordSkinId: skin || 0,
        from: dug.from || ''
      };
      var text = JSON.stringify(payload);
      if (text === last) return;
      last = text;
      post(payload);
      log('bridge name=' + payload.name + ' roleId=' + payload.roleId +
        ' headRaw=' + payload.headImgRaw + ' avatar=' + payload.avatar);
    } catch (e) {
      log('pick err ' + e);
    }
  }
  log('roleBridge 已安装');
  var n = 0;
  var timer = setInterval(function(){
    n++;
    pick();
    if (n >= 8) {
      clearInterval(timer);
      timer = setInterval(pick, 12000);
    }
  }, 2500);
  setTimeout(pick, 1200);
})();
''';

  /// 油猴（Tampermonkey）兼容层。对照 naiwa `GM_SHIM`。
  /// `GM_xmlhttpRequest` 经 `XyzwBridge` 转到 Dart 发请求，才能跨域。
  static const gmShim = r'''
(function(){
    if(window.__gmShimInstalled) return;
    window.__gmShimInstalled = true;
    if (!window.unsafeWindow) window.unsafeWindow = window;

    // 只解除 body 的 flex，避免脚本面板被当成 flex item 挤下去。
    // 不要再全局抬 z-index / pointer-events，否则会盖住画布导致点不到游戏，并打乱脚本自带布局。
    if (!window.__xyzwUiFixCss) {
        window.__xyzwUiFixCss = true;
        var uiCss = document.createElement('style');
        uiCss.setAttribute('data-xyzw', 'uifix');
        uiCss.textContent = [
            'body{display:block!important;}',
            '#GameCanvas,#Cocos2dGameContainer{position:absolute!important;left:0;top:0;z-index:1!important;pointer-events:auto!important;}'
        ].join('');
        (document.head || document.documentElement).appendChild(uiCss);
    }

    var PREFIX = '__gm_';
    if (!window.GM_setValue) window.GM_setValue = function(k, v){
        try { localStorage.setItem(PREFIX + k, JSON.stringify(v)); } catch(e) {}
    };
    if (!window.GM_getValue) window.GM_getValue = function(k, def){
        try {
            var s = localStorage.getItem(PREFIX + k);
            return s === null ? def : JSON.parse(s);
        } catch(e) { return def; }
    };
    if (!window.GM_deleteValue) window.GM_deleteValue = function(k){
        try { localStorage.removeItem(PREFIX + k); } catch(e) {}
    };
    if (!window.GM_listValues) window.GM_listValues = function(){
        var out = [];
        try {
            for (var i = 0; i < localStorage.length; i++) {
                var k = localStorage.key(i);
                if (k && k.indexOf(PREFIX) === 0) out.push(k.slice(PREFIX.length));
            }
        } catch(e) {}
        return out;
    };
    if (!window.GM_addStyle) window.GM_addStyle = function(css){
        var s = document.createElement('style');
        s.textContent = css;
        (document.head || document.documentElement).appendChild(s);
        return s;
    };

    var pending = {};
    var seq = 0;
    window.__gmResolve = function(id, json){
        var cb = pending[id];
        if (!cb) return;
        delete pending[id];
        var res;
        try { res = JSON.parse(json); } catch(e) { res = { status: 0, error: 'bad response' }; }
        res.readyState = 4;
        res.response = res.responseText;
        try {
            if (res.error || !res.status) {
                cb.onerror && cb.onerror(res);
            } else {
                cb.onload && cb.onload(res);
            }
            cb.onreadystatechange && cb.onreadystatechange(res);
        } catch(e) {
            console.warn('[咸强之王] 脚本请求回调异常: ' + (e && e.message));
        }
    };

    function gmxhr(opts){
        opts = opts || {};
        var id = 'gm' + (++seq) + '_' + Date.now();
        pending[id] = opts;
        var payload = {
            url: opts.url,
            method: (opts.method || 'GET').toUpperCase(),
            headers: opts.headers || {},
            data: (opts.data === undefined || opts.data === null) ? null : String(opts.data),
            timeout: opts.timeout || 20000
        };
        try {
            if (window.XyzwBridge && window.XyzwBridge.postMessage) {
                window.XyzwBridge.postMessage(JSON.stringify({
                    type: 'gm',
                    id: id,
                    payload: payload
                }));
            } else {
                throw new Error('no bridge');
            }
        } catch(e) {
            delete pending[id];
            try {
                var x = new XMLHttpRequest();
                x.open(payload.method, payload.url, true);
                Object.keys(payload.headers).forEach(function(k){
                    try { x.setRequestHeader(k, payload.headers[k]); } catch(e2) {}
                });
                x.onload = function(){
                    opts.onload && opts.onload({
                        status: x.status, statusText: x.statusText,
                        responseText: x.responseText, response: x.responseText,
                        responseHeaders: x.getAllResponseHeaders(), readyState: 4
                    });
                };
                x.onerror = function(){ opts.onerror && opts.onerror({ status: 0, error: 'network' }); };
                x.send(payload.data);
            } catch(e3) {
                opts.onerror && opts.onerror({ status: 0, error: String(e3 && e3.message) });
            }
        }
        return { abort: function(){ delete pending[id]; } };
    }
    if (!window.GM_xmlhttpRequest) window.GM_xmlhttpRequest = gmxhr;

    if (!window.GM) {
        window.GM = {
            xmlHttpRequest: gmxhr,
            setValue: function(k, v){ return Promise.resolve(window.GM_setValue(k, v)); },
            getValue: function(k, d){ return Promise.resolve(window.GM_getValue(k, d)); },
            deleteValue: function(k){ return Promise.resolve(window.GM_deleteValue(k)); },
            addStyle: function(c){ return Promise.resolve(window.GM_addStyle(c)); },
            setClipboard: function(t){ return Promise.resolve(window.GM_setClipboard(t)); }
        };
    }
    if (!window.GM_setClipboard) window.GM_setClipboard = function(text){
        try {
            if (navigator.clipboard && navigator.clipboard.writeText) {
                navigator.clipboard.writeText(String(text));
            }
        } catch(e) {}
        try { window.setClipboard && window.setClipboard(String(text)); } catch(e) {}
    };
    if (!window.GM_openInTab) window.GM_openInTab = function(url){
        console.log('[咸强之王] GM_openInTab 已忽略: ' + url);
        return { close: function(){}, closed: false };
    };
    if (!window.GM_notification) window.GM_notification = function(o){
        var text = (o && (o.text || o.title)) || String(o);
        console.log('[咸强之王] 脚本通知: ' + text);
    };
    if (!window.GM_registerMenuCommand) window.GM_registerMenuCommand = function(name){
        console.log('[咸强之王] 脚本菜单项(未挂载): ' + name);
        return name;
    };
    if (!window.GM_unregisterMenuCommand) window.GM_unregisterMenuCommand = function(){};
    if (!window.GM_download) window.GM_download = function(o){
        var url = (o && o.url) || o;
        var name = (o && o.name) || 'download';
        console.warn('[咸强之王][media] GM_download', String(url).slice(0, 80), name);
        // blob/data 图片：转相册保存（脚本常把「保存成功」绑在 onload）
        function fail(err){
          console.warn('[咸强之王][media] GM_download fail', err);
          if (o && o.onerror) try { o.onerror({ error: String(err || 'fail') }); } catch (e0) {}
        }
        function ok(){
          console.warn('[咸强之王][media] GM_download saved');
          if (o && o.onload) try { o.onload(); } catch (e1) {}
        }
        function saveDataUrl(dataUrl){
          if (!window.__xyzwMediaDone || !window.XyzwBridge) return fail('no media bridge');
          var id = 'g' + Date.now() + '_' + Math.floor(Math.random() * 1e6);
          var base64 = String(dataUrl).replace(/^data:image\/[a-zA-Z0-9+.-]+;base64,/, '');
          window.__xyzwMediaCb = window.__xyzwMediaCb || {};
          window.__xyzwMediaCb[id] = function(r){
            if (r && r.errCode === 0) ok(); else fail(r && r.errMsg);
          };
          var chunkSize = 120000;
          var total = Math.max(1, Math.ceil(base64.length / chunkSize) || 1);
          for (var i = 0; i < total; i++) {
            try {
              window.XyzwBridge.postMessage(JSON.stringify({
                type: 'media', action: 'saveImage', id: id,
                chunk: i, total: total,
                data: base64.slice(i * chunkSize, (i + 1) * chunkSize),
                payloadLen: base64.length,
                from: 'GM_download'
              }));
            } catch (e2) { return fail(e2); }
          }
        }
        try {
          if (typeof url === 'string' && url.indexOf('data:image') === 0) {
            saveDataUrl(url); return;
          }
          if (typeof url === 'string' && url.indexOf('blob:') === 0) {
            fetch(url).then(function(res){ return res.blob(); }).then(function(blob){
              var reader = new FileReader();
              reader.onload = function(){ saveDataUrl(String(reader.result || '')); };
              reader.onerror = function(){ fail('read blob'); };
              reader.readAsDataURL(blob);
            }).catch(fail);
            return;
          }
        } catch (e3) { return fail(e3); }
        console.log('[咸强之王] 脚本请求下载(非图片已忽略): ' + String(url).slice(0, 120));
        if (o && o.onerror) o.onerror({ error: 'not_supported' });
    };
    if (!window.GM_getResourceText) window.GM_getResourceText = function(){ return ''; };
    if (!window.GM_getResourceURL) window.GM_getResourceURL = function(){ return ''; };
    if (!window.GM_log) window.GM_log = function(){ console.log.apply(console, arguments); };
    if (!window.exportFunction) window.exportFunction = function(fn){ return fn; };
    if (!window.cloneInto) window.cloneInto = function(obj){ return obj; };
    // 对齐 Tampermonkey: GM_addElement(tag, attrs) / GM_addElement(parent, tag, attrs)
    // 旧实现一律挂到 head，悬浮窗/弹层会不可见。
    if (!window.GM_addElement) window.GM_addElement = function(a, b, c){
        var parent, tag, attrs;
        if (typeof a === 'string') {
            tag = a;
            attrs = b || {};
            parent = document.body || document.documentElement;
        } else {
            parent = a || document.body || document.documentElement;
            tag = b;
            attrs = c || {};
        }
        var el = document.createElement(tag || 'div');
        Object.keys(attrs || {}).forEach(function(k){
            var v = attrs[k];
            if (k === 'textContent') el.textContent = v;
            else if (k === 'innerHTML') el.innerHTML = v;
            else if (k === 'class' || k === 'className') el.className = v;
            else if (k === 'style' && v && typeof v === 'object') {
                Object.keys(v).forEach(function(sk){ el.style[sk] = v[sk]; });
            } else if (k === 'style') {
                el.setAttribute('style', String(v));
            } else if (k.indexOf('on') === 0 && typeof v === 'function') {
                el.addEventListener(k.slice(2).toLowerCase(), v);
            } else if (v != null) {
                el.setAttribute(k, String(v));
            }
        });
        parent.appendChild(el);
        return el;
    };
    if (!window.GM_info) window.GM_info = {
        scriptHandler: 'Tampermonkey',
        version: '5.3.0',
        isIncognito: false,
        scriptWillUpdate: false,
        script: {
            name: 'userscript',
            namespace: 'xyzw',
            description: '',
            version: '1.0',
            excludes: [],
            includes: ['*://*/*'],
            matches: ['*://*/*'],
            resources: {},
            'run-at': 'document-start',
            grant: [
                'unsafeWindow', 'GM_xmlhttpRequest', 'GM_setValue', 'GM_getValue',
                'GM_deleteValue', 'GM_listValues', 'GM_addStyle', 'GM_download',
                'GM_openInTab', 'GM_notification', 'GM_registerMenuCommand',
                'GM_addElement', 'GM.setValue', 'GM.getValue', 'GM.xmlHttpRequest'
            ]
        }
    };
    function __xyzwScriptMsg(msg){
        console.log('[咸强之王] ' + msg);
        try {
            if (window.XyzwBridge && window.XyzwBridge.postMessage) {
                window.XyzwBridge.postMessage(JSON.stringify({ type: 'scriptStatus', message: msg }));
            }
        } catch (e) {}
    }
    __xyzwScriptMsg('页面地址 ' + String(location.href || ''));

    // 跨域 fetch/XHR 走 Dart 桥（对齐油猴）。外部脚本用 fetch 打
    // http://47.108.20.10/api/device-auth/free/verify，在 localhost 下会被 CORS 拦死，
    // 表现就是脚本已执行但版本更新/悬浮窗永远不出现。
    function __xyzwNeedProxy(url){
        try {
            var u = new URL(String(url || ''), location.href);
            if (u.protocol !== 'http:' && u.protocol !== 'https:') return false;
            var h = String(u.hostname || '').toLowerCase();
            // 本地域 / 伪域必须直通（对照和光：吞掉 game.local 会导致盐场/蟠桃点不了人）
            if (h === 'localhost' || h === '127.0.0.1' || h === '::1') return false;
            if (h === 'local' || h === 'game.local' || h === 'ncl.local') return false;
            if (/\.game\.local$/i.test(h) || /\.local$/i.test(h)) return false;
            // 游戏 CDN/API 本身可跨域，保持原生以免拖慢资源加载
            if (/(^|\.)hortorgames\.com$/i.test(h)) return false;
            if (/(^|\.)mars-face\.hortorgames\.com$/i.test(h)) return false;
            return true;
        } catch (e) { return false; }
    }
    function __xyzwHeadersToObject(h){
        var out = {};
        if (!h) return out;
        try {
            if (typeof Headers !== 'undefined' && h instanceof Headers) {
                h.forEach(function(v, k){ out[k] = v; });
                return out;
            }
        } catch (e) {}
        if (typeof h === 'object') {
            Object.keys(h).forEach(function(k){ out[k] = h[k]; });
        }
        return out;
    }
    function __xyzwBridgeFetch(url, method, headers, body){
        return new Promise(function(resolve, reject){
            try {
                window.GM_xmlhttpRequest({
                    url: String(url),
                    method: String(method || 'GET').toUpperCase(),
                    headers: headers || {},
                    data: body == null ? null : String(body),
                    timeout: 30000,
                    onload: function(res){
                        resolve(res || {});
                    },
                    onerror: function(res){
                        reject(new TypeError((res && res.error) || 'Failed to fetch'));
                    }
                });
            } catch (e) { reject(e); }
        });
    }
    try {
        if (window.fetch && !window.__xyzwFetchHooked) {
            window.__xyzwFetchHooked = true;
            var _fetch = window.fetch.bind(window);
            window.fetch = function(input, init){
                init = init || {};
                var u = '';
                var method = 'GET';
                var headers = {};
                var body = null;
                try {
                    if (typeof input === 'string') {
                        u = input;
                    } else if (input && typeof input === 'object') {
                        u = input.url || '';
                        method = input.method || method;
                        headers = __xyzwHeadersToObject(input.headers);
                    }
                } catch (e) {}
                if (init.method) method = init.method;
                if (init.headers) {
                    var h2 = __xyzwHeadersToObject(init.headers);
                    Object.keys(h2).forEach(function(k){ headers[k] = h2[k]; });
                }
                if (init.body !== undefined) body = init.body;
                if (!__xyzwNeedProxy(u)) return _fetch(input, init);
                __xyzwScriptMsg('proxy-fetch ' + method + ' ' + String(u).slice(0, 160));
                if (body != null && typeof body !== 'string') {
                    try { body = JSON.stringify(body); } catch (e) { body = String(body); }
                }
                return __xyzwBridgeFetch(u, method, headers, body).then(function(res){
                    var status = Number(res.status || 0);
                    var text = String(res.responseText || '');
                    if (!status) throw new TypeError(res.error || 'Failed to fetch');
                    var headerInit = {};
                    try {
                        String(res.responseHeaders || '').split(/\r?\n/).forEach(function(line){
                            var i = line.indexOf(':');
                            if (i > 0) headerInit[line.slice(0, i).trim().toLowerCase()] = line.slice(i + 1).trim();
                        });
                    } catch (e) {}
                    if (!headerInit['content-type']) {
                        headerInit['content-type'] = 'application/json;charset=utf-8';
                    }
                    __xyzwScriptMsg('proxy-fetch 完成 ' + status + ' ' + text.slice(0, 220));
                    // 不用 new Response：部分 WebView 对 Response 构造/流读取不兼容，脚本 await res.json() 会挂死
                    var hdr = headerInit;
                    var resp = {
                        ok: status >= 200 && status < 300,
                        status: status,
                        statusText: String(res.statusText || 'OK'),
                        url: String(u),
                        redirected: false,
                        headers: {
                            get: function(name){
                                return hdr[String(name || '').toLowerCase()] || null;
                            },
                            has: function(name){
                                return !!hdr[String(name || '').toLowerCase()];
                            },
                            forEach: function(cb){
                                Object.keys(hdr).forEach(function(k){ cb(hdr[k], k); });
                            }
                        },
                        text: function(){ return Promise.resolve(text); },
                        json: function(){
                            return Promise.resolve().then(function(){ return JSON.parse(text || 'null'); });
                        },
                        arrayBuffer: function(){
                            var enc = new TextEncoder();
                            return Promise.resolve(enc.encode(text).buffer);
                        },
                        blob: function(){
                            return Promise.resolve(new Blob([text], { type: hdr['content-type'] || 'text/plain' }));
                        },
                        clone: function(){ return resp; }
                    };
                    return resp;
                });
            };
        }
        // 第三方脚本域名的 XHR 也走桥；游戏 hortorgames 资源仍走原生。
        var XP = XMLHttpRequest && XMLHttpRequest.prototype;
        if (XP && XP.open && !XP.__xyzwXhrProxied) {
            XP.__xyzwXhrProxied = true;
            var _open = XP.open;
            var _send = XP.send;
            var _setHeader = XP.setRequestHeader;
            XP.open = function(method, url){
                this.__xyzwUrl = String(url || '');
                this.__xyzwMethod = String(method || 'GET');
                this.__xyzwHeaders = {};
                this.__xyzwProxy = __xyzwNeedProxy(this.__xyzwUrl);
                if (!this.__xyzwProxy) return _open.apply(this, arguments);
                this.__xyzwArgs = arguments;
                return undefined;
            };
            XP.setRequestHeader = function(k, v){
                if (this.__xyzwProxy) {
                    this.__xyzwHeaders[k] = v;
                    return;
                }
                return _setHeader.apply(this, arguments);
            };
            XP.send = function(body){
                var xhr = this;
                if (!xhr.__xyzwProxy) return _send.apply(this, arguments);
                __xyzwScriptMsg('proxy-xhr ' + xhr.__xyzwMethod + ' ' + String(xhr.__xyzwUrl).slice(0, 160));
                __xyzwBridgeFetch(xhr.__xyzwUrl, xhr.__xyzwMethod, xhr.__xyzwHeaders, body).then(function(res){
                    var status = res.status || 0;
                    var text = res.responseText || '';
                    var headers = res.responseHeaders || '';
                    try {
                        Object.defineProperty(xhr, 'readyState', { configurable: true, get: function(){ return 4; } });
                        Object.defineProperty(xhr, 'status', { configurable: true, get: function(){ return status; } });
                        Object.defineProperty(xhr, 'statusText', { configurable: true, get: function(){ return res.statusText || ''; } });
                        Object.defineProperty(xhr, 'responseText', { configurable: true, get: function(){ return text; } });
                        Object.defineProperty(xhr, 'response', { configurable: true, get: function(){ return text; } });
                        xhr.getAllResponseHeaders = function(){ return headers; };
                        xhr.getResponseHeader = function(name){
                            var re = new RegExp('^' + String(name) + ':\\s*(.*)$', 'im');
                            var m = String(headers).match(re);
                            return m ? m[1] : null;
                        };
                    } catch (e) {}
                    if (typeof xhr.onreadystatechange === 'function') try { xhr.onreadystatechange(); } catch (e) {}
                    if (status > 0 && typeof xhr.onload === 'function') try { xhr.onload(); } catch (e) {}
                    if (!status && typeof xhr.onerror === 'function') try { xhr.onerror(); } catch (e) {}
                }).catch(function(){
                    if (typeof xhr.onerror === 'function') try { xhr.onerror(); } catch (e) {}
                });
            };
        }
    } catch (e) {
        __xyzwScriptMsg('跨域代理安装失败 ' + (e && e.message));
    }
    window.addEventListener('error', function(ev){
        var file = String(ev.filename || '');
        if (file.indexOf('userscripts/') < 0 && file.indexOf('xyzw-gm-shim') < 0) return;
        __xyzwScriptMsg('脚本异常 ' + (ev.message || '') + ' @' + file.split('/').pop());
    });
    window.addEventListener('unhandledrejection', function(ev){
        var r = ev && ev.reason;
        var msg = (r && (r.message || r.stack)) || String(r);
        if (!msg) return;
        __xyzwScriptMsg('脚本Promise异常 ' + String(msg).slice(0, 240));
    });

    (function(){
        function alias(){
            var R = window.ROLE;
            if (!R || typeof R !== 'object') return false;
            if (R.id != null && R.id !== '') return true;
            var rid = R.roleId != null ? R.roleId : R.userId;
            if (rid == null || rid === '') return false;
            try {
                Object.defineProperty(R, 'id', {
                    get: function(){ return this.roleId != null ? this.roleId : this.userId; },
                    configurable: true
                });
                console.log('[咸强之王] 已补 ROLE.id = ' + rid);
                return true;
            } catch(e) { try { R.id = rid; return true; } catch(e2) { return false; } }
        }
        if (alias()) return;
        var t = 0;
        var iv = setInterval(function(){
            if (alias() || ++t > 240) clearInterval(iv);
        }, 500);
    })();

    console.log('[咸强之王] 油猴兼容层已注入');
})();
''';

  static const vhFix = r'''
(function(){
    if(window.__vhFixInstalled) return;
    window.__vhFixInstalled = true;
    var probe = document.createElement('div');
    probe.style.cssText = 'position:fixed;left:-9999px;top:0;width:1px;height:100vh;';
    (document.body || document.documentElement).appendChild(probe);
    var vh100 = probe.getBoundingClientRect().height;
    probe.parentNode && probe.parentNode.removeChild(probe);
    var real = window.innerHeight || document.documentElement.clientHeight;
    if (vh100 > real * 0.5) {
        console.log('[咸强之王] vh 正常(100vh=' + vh100.toFixed(0) + 'px)');
        return;
    }
    function toPx(css){
        return css.replace(/(-?[\d.]+)vh/g, function(_, n){
            return (parseFloat(n) * real / 100).toFixed(1) + 'px';
        });
    }
    var PROPS = ['max-height','min-height','height','top','bottom','padding-bottom','margin-bottom'];
    function patchSheet(sheet){
        var rules;
        try { rules = sheet.cssRules; } catch(e) { return 0; }
        if (!rules) return 0;
        var n = 0;
        for (var i = 0; i < rules.length; i++) {
            var r = rules[i];
            if (r.cssRules) { n += patchSheet(r); continue; }
            if (!r.style) continue;
            for (var p = 0; p < PROPS.length; p++) {
                var v = r.style.getPropertyValue(PROPS[p]);
                if (!v || v.indexOf('vh') < 0) continue;
                r.style.setProperty(PROPS[p], toPx(v), r.style.getPropertyPriority(PROPS[p]));
                n++;
            }
        }
        return n;
    }
    function patchAll(){
        var total = 0;
        for (var i = 0; i < document.styleSheets.length; i++) {
            total += patchSheet(document.styleSheets[i]);
        }
        document.querySelectorAll('[style*="vh"]').forEach(function(el){
            var s = el.getAttribute('style');
            if (s && /[\d.]vh/.test(s)) { el.setAttribute('style', toPx(s)); total++; }
        });
        return total;
    }
    console.log('[咸强之王] vh 替换 ' + patchAll() + ' 处');
    new MutationObserver(function(muts){
        var need = false;
        muts.forEach(function(m){
            Array.prototype.slice.call(m.addedNodes).forEach(function(n){
                if (n.nodeType === 1 && (n.tagName === 'STYLE' || n.tagName === 'LINK')) need = true;
            });
        });
        if (need) patchAll();
    }).observe(document.documentElement, { childList: true, subtree: true });
})();
''';

  static const canvasGuard = r'''
(function(){
    if(window.__canvasGuardInstalled) return;
    window.__canvasGuardInstalled = true;
    setInterval(function(){
        var canvas = document.getElementById('GameCanvas');
        if (!canvas) return;
        if (window.getComputedStyle(canvas).pointerEvents === 'none') {
            canvas.style.pointerEvents = 'auto';
        }
    }, 5000);
})();
''';

  /// 键盘弹出：固定游戏视口 + 伪造 Cocos frameSize，避免宽>高触发横屏旋转。
  static const portraitLock = r'''
(function(){
  if (window.__xyzwPortraitLockV4) return;
  window.__xyzwPortraitLockV4 = true;
  var fixedW = Math.max(window.innerWidth || 0, document.documentElement.clientWidth || 0) || 390;
  var fixedH = Math.max(window.innerHeight || 0, document.documentElement.clientHeight || 0) || 844;
  if (fixedW > fixedH) {
    var tmp = fixedW; fixedW = fixedH; fixedH = tmp;
  }
  function patchCcView(){
    try {
      if (typeof cc === 'undefined' || !cc.view) return;
      if (cc.macro) {
        try { cc.view._orientation = cc.macro.ORIENTATION_PORTRAIT; } catch (e0) {}
      }
      try { cc.view._isRotated = false; } catch (e1) {}
      if (cc.view.__xyzwFramePatched) return;
      cc.view.__xyzwFramePatched = true;
      var _gfs = cc.view.getFrameSize && cc.view.getFrameSize.bind(cc.view);
      cc.view.getFrameSize = function(){
        if (typeof cc.size === 'function') return cc.size(fixedW, fixedH);
        return _gfs ? _gfs() : { width: fixedW, height: fixedH };
      };
      if (typeof cc.view.setFrameSize === 'function') {
        var _sfs = cc.view.setFrameSize.bind(cc.view);
        cc.view.setFrameSize = function(w, h){
          var ww = w || fixedW, hh = h || fixedH;
          if (hh < fixedH * 0.92 || ww > hh) {
            return _sfs(fixedW, fixedH);
          }
          return _sfs(ww, hh);
        };
      }
      try {
        if (cc.view._frameSize) {
          cc.view._frameSize.width = fixedW;
          cc.view._frameSize.height = fixedH;
        }
      } catch (e2) {}
    } catch (e3) {}
  }
  function applyFixed(){
    patchCcView();
    try {
      var ids = ['Cocos2dGameContainer', 'GameCanvas', 'GameDiv'];
      for (var i = 0; i < ids.length; i++) {
        var el = document.getElementById(ids[i]);
        if (!el || !el.style) continue;
        el.style.width = fixedW + 'px';
        el.style.height = fixedH + 'px';
        if (el.style.transform && /rotate\s*\(/i.test(el.style.transform)) {
          el.style.transform = el.style.transform.replace(/rotate\s*\([^)]*\)/ig, 'rotate(0deg)');
        }
      }
      if (document.body && document.body.style) {
        document.body.style.minHeight = fixedH + 'px';
      }
    } catch (e4) {}
  }
  applyFixed();
  window.addEventListener('resize', function(){
    var h = window.innerHeight || 0;
    var w = window.innerWidth || 0;
    if ((h > 0 && h < fixedH * 0.92) || (w > 0 && h > 0 && w > h)) {
      console.warn('[咸强之王][media] keyboard-resize inner=' + w + 'x' + h + ' keep=' + fixedW + 'x' + fixedH);
      applyFixed();
    }
  }, true);
  if (window.visualViewport) {
    window.visualViewport.addEventListener('resize', function(){
      var h = window.visualViewport.height || 0;
      if (h > 0 && h < fixedH * 0.92) applyFixed();
    });
  }
  // Cocos 晚加载时补丁
  var tries = 0;
  var timer = setInterval(function(){
    tries++;
    patchCcView();
    if ((typeof cc !== 'undefined' && cc.view && cc.view.__xyzwFramePatched) || tries > 40) {
      clearInterval(timer);
    }
  }, 500);
  console.log('[咸强之王][media] portraitLock v4 on', fixedW + 'x' + fixedH);
})();
''';

  /// 输入法：游戏画面不动；把系统 input 挂进键盘上方白条（可点「完成」）。
  /// 键盘收起后必须立刻拆掉白条，避免残留在屏幕底部。
  static const imeBridge = r'''
(function(){
  if (window.__xyzwImeBridgeV3) return;
  window.__xyzwImeBridgeV3 = true;
  var bar = null;
  var doneBtn = null;
  var activeEl = null;
  var saved = null;
  var pinTimer = null;
  var committing = false;
  var baseViewportH = 0;
  var sawKeyboard = false;
  var attachedAt = 0;

  function pinScroll(){
    try {
      if (window.scrollTo) window.scrollTo(0, 0);
      if (document.documentElement) document.documentElement.scrollTop = 0;
      if (document.body) document.body.scrollTop = 0;
    } catch (e0) {}
  }

  function layoutH(){
    return Math.max(
      window.innerHeight || 0,
      (document.documentElement && document.documentElement.clientHeight) || 0
    );
  }

  function visualH(){
    var vv = window.visualViewport;
    return (vv && vv.height > 0) ? vv.height : layoutH();
  }

  // 键盘是否仍抬起：视觉视口明显矮于布局高度
  function isKeyboardVisible(){
    var lh = layoutH();
    var vh = visualH();
    if (lh <= 0) return false;
    if (lh - vh >= 100) return true;
    if (baseViewportH > 0 && baseViewportH - vh >= 80) return true;
    return vh < lh * 0.86;
  }

  function commit(){
    if (committing) return;
    committing = true;
    var el = activeEl;
    console.warn('[咸强之王][media] ime commit', el && (el.value || '').slice(0, 40));
    try {
      if (el) {
        try {
          el.dispatchEvent(new Event('input', { bubbles: true }));
          el.dispatchEvent(new Event('change', { bubbles: true }));
        } catch (e1) {}
        try {
          el.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true }));
          el.dispatchEvent(new KeyboardEvent('keypress', { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true }));
          el.dispatchEvent(new KeyboardEvent('keyup', { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true }));
        } catch (e2) {}
        try { el.blur(); } catch (e3) {}
      }
    } finally {
      // 立刻拆条，避免等 focusout 时被 committing 挡掉
      detach(true);
      setTimeout(function(){ committing = false; }, 160);
    }
  }

  function ensureBar(){
    if (bar && bar.parentNode) return bar;
    bar = document.createElement('div');
    bar.id = '__xyzwImeBar';
    bar.setAttribute('data-xyzw-ime', '1');
    bar.style.cssText = [
      'position:fixed', 'left:0', 'width:100%', 'height:44px',
      'background:#ffffff', 'z-index:2147483646', 'display:none',
      'box-sizing:border-box', 'border-top:1px solid #d1d1d6',
      'pointer-events:auto', 'flex-direction:row', 'align-items:center',
      'padding:0 0 0 0'
    ].join(';');
    doneBtn = document.createElement('button');
    doneBtn.type = 'button';
    doneBtn.setAttribute('data-xyzw-ime', '1');
    doneBtn.textContent = '完成';
    doneBtn.style.cssText = [
      'flex:0 0 auto', 'position:relative', 'right:auto', 'top:auto',
      'height:32px', 'margin:0 8px 0 4px', 'padding:0 14px',
      'background:#34c759', 'color:#fff', 'border:none',
      'border-radius:6px', 'font-size:15px', 'font-weight:600',
      'line-height:32px', 'z-index:3', '-webkit-appearance:none'
    ].join(';');
    function onDone(e){
      try { e.preventDefault(); e.stopPropagation(); } catch (e4) {}
      commit();
    }
    doneBtn.addEventListener('touchend', onDone, {passive:false});
    doneBtn.addEventListener('mouseup', onDone);
    doneBtn.addEventListener('click', onDone);
    bar.appendChild(doneBtn);
    (document.documentElement || document.body).appendChild(bar);
    return bar;
  }

  function barTop(){
    var vv = window.visualViewport;
    if (vv && vv.height > 0) return Math.max(0, vv.offsetTop + vv.height - 44);
    return Math.max(0, (window.innerHeight || 0) - 44);
  }

  function styleInput(el){
    var s = el.style;
    s.setProperty('position', 'relative', 'important');
    s.setProperty('top', 'auto', 'important');
    s.setProperty('left', 'auto', 'important');
    s.setProperty('right', 'auto', 'important');
    s.setProperty('bottom', 'auto', 'important');
    s.setProperty('flex', '1 1 auto', 'important');
    s.setProperty('width', '100%', 'important');
    s.setProperty('max-width', 'none', 'important');
    s.setProperty('height', '44px', 'important');
    s.setProperty('min-height', '44px', 'important');
    s.setProperty('z-index', '1', 'important');
    s.setProperty('opacity', '1', 'important');
    s.setProperty('font-size', '16px', 'important');
    s.setProperty('line-height', '44px', 'important');
    s.setProperty('background', '#ffffff', 'important');
    s.setProperty('background-color', '#ffffff', 'important');
    s.setProperty('color', '#000000', 'important');
    s.setProperty('-webkit-text-fill-color', '#000000', 'important');
    s.setProperty('caret-color', '#007aff', 'important');
    s.setProperty('border', 'none', 'important');
    s.setProperty('border-radius', '0', 'important');
    s.setProperty('padding', '0 12px', 'important');
    s.setProperty('margin', '0', 'important');
    s.setProperty('transform', 'none', 'important');
    s.setProperty('-webkit-transform', 'none', 'important');
    s.setProperty('box-shadow', 'none', 'important');
    s.setProperty('outline', 'none', 'important');
    s.setProperty('display', 'block', 'important');
    s.setProperty('visibility', 'visible', 'important');
    s.setProperty('pointer-events', 'auto', 'important');
    try { el.removeAttribute('readonly'); } catch (e5) {}
  }

  function place(){
    if (!activeEl) return;
    var kb = isKeyboardVisible();
    if (kb) sawKeyboard = true;
    // 曾出现过键盘后又收起，或挂载过久仍无键盘 → 拆条（避免弹起动画阶段误拆）
    if (!kb && (sawKeyboard || (Date.now() - attachedAt > 900))) {
      console.warn('[咸强之王][media] ime keyboard gone → hide bar');
      try { if (document.activeElement === activeEl) activeEl.blur(); } catch (e6) {}
      detach(true);
      return;
    }
    ensureBar();
    var top = barTop();
    bar.style.display = 'flex';
    bar.style.top = top + 'px';
    bar.style.bottom = 'auto';
    if (activeEl.parentNode !== bar) {
      bar.insertBefore(activeEl, doneBtn);
    } else if (doneBtn && activeEl.nextSibling !== doneBtn) {
      bar.insertBefore(activeEl, doneBtn);
    }
    styleInput(activeEl);
    pinScroll();
  }

  function isEditable(el){
    if (!el || !el.tagName) return false;
    if (el.getAttribute && el.getAttribute('data-xyzw-ime') === '1') return false;
    var tag = el.tagName.toUpperCase();
    if (tag === 'TEXTAREA') return true;
    if (tag !== 'INPUT') return false;
    var type = String(el.type || 'text').toLowerCase();
    return type === 'text' || type === 'search' || type === 'tel' || type === 'url'
      || type === 'email' || type === 'password' || type === 'number' || type === '';
  }

  function attach(el){
    if (activeEl === el) { place(); return; }
    detach(true);
    activeEl = el;
    saved = {
      parent: el.parentNode,
      next: el.nextSibling,
      cssText: el.style.cssText
    };
    baseViewportH = Math.max(visualH(), layoutH());
    sawKeyboard = false;
    attachedAt = Date.now();
    ensureBar();
    try { bar.insertBefore(el, doneBtn); } catch (e7) {}
    bar.style.display = 'flex';
    place();
    try { el.focus(); } catch (e8) {}
    if (pinTimer) clearInterval(pinTimer);
    pinTimer = setInterval(place, 80);
    console.warn('[咸强之王][media] ime attach v3', el.tagName, el.type || '');
  }

  function restoreEl(el, info){
    if (!el || !info) return;
    try {
      if (info.parent && info.parent.isConnected !== false) {
        if (info.next && info.next.parentNode === info.parent) {
          info.parent.insertBefore(el, info.next);
        } else {
          info.parent.appendChild(el);
        }
      } else if (el.parentNode === bar) {
        try { bar.removeChild(el); } catch (e9) {}
      }
    } catch (e10) {}
    try { el.style.cssText = info.cssText || ''; } catch (e11) {}
  }

  function detach(restore){
    if (pinTimer) { clearInterval(pinTimer); pinTimer = null; }
    if (bar) {
      bar.style.display = 'none';
      bar.style.top = '-9999px';
    }
    var el = activeEl;
    var info = saved;
    activeEl = null;
    saved = null;
    baseViewportH = 0;
    sawKeyboard = false;
    attachedAt = 0;
    if (el && info) restoreEl(el, info);
  }

  document.addEventListener('focusin', function(e){
    var el = e.target;
    if (!isEditable(el)) return;
    attach(el);
  }, true);

  document.addEventListener('focusout', function(e){
    var el = e.target;
    if (el !== activeEl) return;
    setTimeout(function(){
      // 完成路径会自己 detach；这里兜底失焦/点空白
      if (!activeEl) return;
      if (document.activeElement === activeEl && isKeyboardVisible()) return;
      detach(true);
    }, 100);
  }, true);

  document.addEventListener('scroll', function(){
    if (activeEl) pinScroll();
  }, true);

  function onViewportChange(){
    if (!activeEl) {
      if (bar) bar.style.display = 'none';
      return;
    }
    place();
  }
  if (window.visualViewport) {
    window.visualViewport.addEventListener('resize', onViewportChange);
    window.visualViewport.addEventListener('scroll', onViewportChange);
  }
  window.addEventListener('resize', onViewportChange);

  console.log('[咸强之王][media] imeBridge v3 on');
})();
''';

  /// 相册/换头像：锁定 HSDK/Platform；补 getClientVersion（否则 200ms 超时→版本太低）。
  static const mediaBridge = r'''
(function(){
  if (window.__xyzwMediaBridgePatchV4) return;
  window.__xyzwMediaBridgePatchV4 = true;
  window.__xyzwMediaCb = window.__xyzwMediaCb || {};
  // ChangeHeadImgConfirmDialog 需要两张图，且 .replace 剥离 dataURL 前缀
  function normalizeChooseResult(r){
    if (!r || !r.base64s || !r.base64s.length) return r;
    var list = r.base64s.slice();
    for (var i = 0; i < list.length; i++) {
      var s = String(list[i] || '');
      if (s && s.indexOf('data:') !== 0) {
        list[i] = 'data:image/jpeg;base64,' + s.replace(/^data:image\/[a-zA-Z0-9+.-]+;base64,/, '');
      }
    }
    if (list.length === 1) list.push(list[0]);
    r.base64s = list;
    return r;
  }
  window.__xyzwMediaDone = function(id, result){
    try {
      var cb = window.__xyzwMediaCb[id];
      delete window.__xyzwMediaCb[id];
      var out = result || { errCode: -1, base64s: [] };
      if (out.base64s) out = normalizeChooseResult(out);
      if (typeof cb === 'function') cb(out);
    } catch (e) {
      console.warn('[咸强之王][media] mediaDone', e);
    }
  };
  function postMedia(action, id, extra){
    try {
      if (window.XyzwBridge && window.XyzwBridge.postMessage) {
        var payload = { type: 'media', action: action, id: String(id) };
        if (extra) {
          for (var k in extra) {
            if (Object.prototype.hasOwnProperty.call(extra, k)) payload[k] = extra[k];
          }
        }
        window.XyzwBridge.postMessage(JSON.stringify(payload));
        return true;
      }
    } catch (e) {}
    return false;
  }
  function chooseImagePromise(imageSize){
    return new Promise(function(resolve){
      var id = 'c' + Date.now() + '_' + Math.floor(Math.random() * 1e6);
      window.__xyzwMediaCb[id] = function(r){
        console.warn('[咸强之王][media] chooseImage done', id, r && r.errCode, r && r.base64s && r.base64s.length);
        resolve(r || { errCode: -1, base64s: [] });
      };
      console.warn('[咸强之王][media] chooseImage', id, imageSize);
      if (!postMedia('chooseImage', id, { imageSize: imageSize || [512, 512] })) {
        window.__xyzwMediaDone(id, { errCode: -1, errMsg: 'no bridge', base64s: [] });
      }
    });
  }
  function saveImagePromise(opts){
    return new Promise(function(resolve, reject){
      var id = 's' + Date.now() + '_' + Math.floor(Math.random() * 1e6);
      var base64 = '';
      if (opts && opts.base64 != null) base64 = String(opts.base64);
      else if (opts && opts.imagePath != null) {
        base64 = String(opts.imagePath)
          .replace(/^data:image\/[a-zA-Z0-9+.-]+;base64,/, '');
      }
      window.__xyzwMediaCb[id] = function(r){
        console.warn('[咸强之王][media] saveImage done', id, r && r.errCode, r && r.errMsg);
        if (r && r.errCode === 0) resolve(r);
        else reject(r || { errCode: -1, errMsg: 'save fail' });
      };
      var chunkSize = 120000;
      var total = Math.max(1, Math.ceil(base64.length / chunkSize) || 1);
      console.warn('[咸强之王][media] saveImage', id, 'len=' + base64.length, 'chunks=' + total);
      for (var i = 0; i < total; i++) {
        var piece = base64.slice(i * chunkSize, (i + 1) * chunkSize);
        if (!postMedia('saveImage', id, {
          chunk: i,
          total: total,
          data: piece,
          payloadLen: base64.length
        })) {
          window.__xyzwMediaDone(id, { errCode: -1, errMsg: 'no bridge' });
          return;
        }
      }
    });
  }
  function hsdkChooseImage(callback, options){
    var imageSize = null;
    if (options && options.imageSize != null) imageSize = options.imageSize;
    else if (typeof callback !== 'function' && callback) imageSize = callback.imageSize || callback;
    chooseImagePromise(imageSize).then(function(r){
      if (typeof callback === 'function') callback(r);
    });
  }
  function hsdkSaveImage(callback, options){
    var opts = options;
    if ((!opts || (opts.base64 == null && opts.imagePath == null)) && callback && typeof callback === 'object') {
      opts = callback;
    }
    saveImagePromise(opts || {}).then(function(r){
      if (typeof callback === 'function') callback(r);
    }).catch(function(r){
      if (typeof callback === 'function') callback(r);
    });
  }
  // 换头像关键：PlatformH5.getClientVersion → i.getClientVersion(cb)，须 <200ms 回调
  function hsdkGetClientVersion(callback){
    var info = { errCode: 0, version: '4.2.1', clientVersion: '4.2.1', errMsg: 'getClientVersion:ok' };
    console.warn('[咸强之王][media] getClientVersion', info.version);
    if (typeof callback === 'function') {
      try { callback(info); } catch (e) {}
    }
    return Promise.resolve(info);
  }
  function getClientVersionPromise(){
    return hsdkGetClientVersion();
  }
  hsdkChooseImage.__xyzwMedia = true;
  hsdkSaveImage.__xyzwMedia = true;
  hsdkGetClientVersion.__xyzwMedia = true;
  function lockFn(obj, name, fn){
    if (!obj) return;
    try {
      Object.defineProperty(obj, name, {
        configurable: true,
        enumerable: true,
        get: function(){ return fn; },
        set: function(){}
      });
    } catch (e) {
      try { obj[name] = fn; } catch (e2) {}
    }
  }
  function tryRequire(name){
    try {
      if (typeof window.__require === 'function') return window.__require(name);
    } catch (e) {}
    return null;
  }
  function patchHsdk(){
    try {
      var targets = [window.HSDK, window.__HORTOR_SDK__, window.wx];
      for (var i = 0; i < targets.length; i++) {
        lockFn(targets[i], 'chooseImage', hsdkChooseImage);
        lockFn(targets[i], 'saveImage', hsdkSaveImage);
        lockFn(targets[i], 'getClientVersion', hsdkGetClientVersion);
      }
    } catch (e) {}
  }
  function patchPlatform(){
    try {
      var PM = tryRequire('PlatformManager');
      var inst = PM && (PM.PlatformManager && PM.PlatformManager.instance || PM.instance);
      if (!inst) return false;
      lockFn(inst, 'chooseImage', function(e){ return chooseImagePromise(e); });
      lockFn(inst, 'saveImage', function(e){ return saveImagePromise(e); });
      lockFn(inst, 'getClientVersion', function(){ return getClientVersionPromise(); });
      if (inst._platform) {
        lockFn(inst._platform, 'chooseImage', function(e){ return chooseImagePromise(e); });
        lockFn(inst._platform, 'saveImage', function(e){ return saveImagePromise(e); });
        lockFn(inst._platform, 'getClientVersion', function(){ return getClientVersionPromise(); });
      }
      try {
        var proto = Object.getPrototypeOf(inst);
        if (proto) {
          lockFn(proto, 'chooseImage', function(e){ return chooseImagePromise(e); });
          lockFn(proto, 'saveImage', function(e){ return saveImagePromise(e); });
          lockFn(proto, 'getClientVersion', function(){ return getClientVersionPromise(); });
        }
      } catch (e3) {}
      if (!window.__xyzwMediaPlatLogged) {
        window.__xyzwMediaPlatLogged = true;
        console.warn('[咸强之王][media] PlatformManager locked v3 isH5=' + !!inst.isH5);
      }
      return true;
    } catch (e) {
      return false;
    }
  }
  function tick(){
    patchHsdk();
    patchPlatform();
  }
  tick();
  setInterval(tick, 1000);
  console.warn('[咸强之王][media] bridge patch v3 installed');
})();
''';

  static String _jsStr(String s) =>
      "'${s.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll('\r', '').replaceAll('\n', r'\n')}'";

  /// 鸟哥之王 Pro：`__proClearScriptQueue` → 分段 `__proInjectOneScriptFromChunks` → `__proScriptsInjected` 里 `(0,eval)`。
  /// 外部脚本不走 `<script src>`，避免大文件二次请求失败，也避开 evaluateJavascript 约 1MB 的上限。
  static const scriptRunner = r'''
(function(){
  if (window.__proInjectOneScript) return;
  if (!window.unsafeWindow) window.unsafeWindow = window;
  window.__proScriptQueue = [];
  window.__proChunkBuf = {};
  window.__proClearScriptQueue = function(){
    window.__proScriptQueue = [];
    window.__proChunkBuf = {};
  };
  window.__proInjectOneScript = function(name, code){
    window.__proScriptQueue.push({ name: String(name || ''), code: String(code || '') });
  };
  window.__proInjectOneScriptFromChunks = function(id, index, total, chunk){
    var box = window.__proChunkBuf[id];
    if (!box) box = window.__proChunkBuf[id] = { name: id, total: total, parts: [] };
    box.parts[index] = String(chunk || '');
    var n = 0;
    for (var i = 0; i < box.total; i++) if (typeof box.parts[i] === 'string') n++;
    if (n !== box.total) return;
    var code = box.parts.join('');
    delete window.__proChunkBuf[id];
    var name = id.indexOf('\n') >= 0 ? id.slice(0, id.indexOf('\n')) : id;
    window.__proScriptQueue.push({ name: name, code: code });
  };
  window.__proScriptsInjected = function(){
    var q = window.__proScriptQueue || [];
    window.__proScriptQueue = [];
    var ok = 0, fail = 0;
    q.forEach(function(item){
      try {
        (0, eval)(item.code);
        ok++;
        console.log('[咸强之王] 脚本已执行 ' + item.name);
      } catch (e) {
        fail++;
        console.error('[咸强之王] 脚本执行失败 ' + item.name + ': ' + (e && e.message));
      }
    });
    var msg = '已执行脚本 ' + ok + '/' + (ok + fail) + (fail ? (' 失败' + fail) : '');
    console.log('[咸强之王] ' + msg);
    try {
      if (window.XyzwBridge && window.XyzwBridge.postMessage) {
        window.XyzwBridge.postMessage(JSON.stringify({ type: 'scriptStatus', message: msg }));
      }
    } catch (e) {}
  };
})();
''';

  static String jsQuote(String s) {
    final b = StringBuffer("'");
    for (final c in s.runes) {
      if (c == 0x5C) {
        b.write(r'\\');
      } else if (c == 0x27) {
        b.write(r"\'");
      } else if (c == 0x0A) {
        b.write(r'\n');
      } else if (c == 0x0D) {
        b.write(r'\r');
      } else if (c == 0x2028) {
        b.write(r'\u2028');
      } else if (c == 0x2029) {
        b.write(r'\u2029');
      } else if (c < 0x20) {
        b.write('\\u${c.toRadixString(16).padLeft(4, '0')}');
      } else {
        b.writeCharCode(c);
      }
    }
    b.write("'");
    return b.toString();
  }

  static String chunkCall(String id, int index, int total, String chunk) {
    return '(function(){try{window.__proInjectOneScriptFromChunks('
        '${jsQuote(id)},$index,$total,${jsQuote(chunk)});}'
        'catch(e){console.error("[咸强之王] 脚本分段失败",e);}})();';
  }

  /// 对照 naiwa GameWebView.injectUserScripts：等 `__require` 后按 src 串行加载。
  static String userScriptLoader(
    List<({String id, String name, String url})> published,
  ) {
    final entries = published
        .map(
          (e) =>
              '{id:${_jsStr(e.id)},name:${_jsStr(e.name)},url:${_jsStr(e.url)}}',
        )
        .join(',');
    return '''
(function(){
  var items = [$entries];
  window.__injectedScriptIds = window.__injectedScriptIds || {};
  window.__injectingScriptIds = window.__injectingScriptIds || {};
  var done = window.__injectedScriptIds;
  var loading = window.__injectingScriptIds;
  var live = {};
  items.forEach(function(it){ live[it.id] = 1; });
  var stale = 0;
  for (var k in done) { if (done[k] && !live[k]) stale++; }
  var pending = items.filter(function(it){ return !done[it.id] && !loading[it.id]; });
  function status(msg){
    try {
      if (window.XyzwBridge && window.XyzwBridge.postMessage) {
        window.XyzwBridge.postMessage(JSON.stringify({ type: 'scriptStatus', message: msg }));
      }
    } catch(e) {}
    console.log('[咸强之王] ' + msg);
  }
  if (pending.length === 0) {
    status(stale ? ('已关闭' + stale + '个，需刷新生效') : ('已全部注入 (' + items.length + ')'));
    return;
  }
  function runAll(){
    var ok = 0, fail = 0, i = 0;
    function report(){
      status('已注入 ' + ok + '/' + items.length +
        (fail ? (' 失败' + fail) : '') +
        (stale ? (' 关闭' + stale + '需刷新') : ''));
    }
    function next(){
      if (i >= pending.length) { report(); return; }
      var it = pending[i++];
      if (done[it.id] || loading[it.id]) { next(); return; }
      loading[it.id] = true;
      var el = document.createElement('script');
      el.type = 'text/javascript';
      el.async = false;
      el.src = it.url;
      el.onload = function(){
        done[it.id] = true;
        delete loading[it.id];
        ok++;
        status('已加载 ' + it.name);
        el.parentNode && el.parentNode.removeChild(el);
        next();
      };
      el.onerror = function(){
        fail++;
        delete loading[it.id];
        delete done[it.id];
        console.error('[咸强之王] 脚本加载失败: ' + it.name + ' <- ' + it.url);
        el.parentNode && el.parentNode.removeChild(el);
        next();
      };
      (document.head || document.documentElement).appendChild(el);
    }
    next();
  }
  runAll();
})();
''';
  }

  /// 把壳侧备份写回 localStorage，须在游戏读设置之前执行。
  static String restoreGamePrefs(Map<String, String> data) {
    final buf = StringBuffer('(function(){try{');
    var n = 0;
    for (final e in data.entries) {
      if (e.key.startsWith('__xyzw')) continue;
      n++;
      buf.writeln(
        'if(localStorage.getItem(${jsQuote(e.key)})===null)'
        'localStorage.setItem(${jsQuote(e.key)}, ${jsQuote(e.value)});',
      );
    }
    buf.writeln(
      "console.log('[咸强之王] 已恢复游戏设置 keys=$n');",
    );
    buf.writeln(
      '}catch(e){console.warn("[咸强之王] 恢复游戏设置失败",e);}})();',
    );
    return buf.toString();
  }

  /// 设置变更时回传到 Dart，杀进程后仍能还原。
  static const persistGamePrefs = r'''
(function(){
  if (window.__xyzwPrefsWatch) return;
  window.__xyzwPrefsWatch = true;
  var last = '';
  function dump(){
    try {
      var out = {};
      for (var i = 0; i < localStorage.length; i++) {
        var k = localStorage.key(i);
        if (!k || k.indexOf('__xyzw') === 0) continue;
        var v = localStorage.getItem(k);
        if (v == null || v.length > 200000) continue;
        out[k] = v;
      }
      var s = JSON.stringify(out);
      if (s === last) return;
      last = s;
      if (window.XyzwBridge && window.XyzwBridge.postMessage) {
        window.XyzwBridge.postMessage(JSON.stringify({ type: 'gamePrefs', data: out }));
      }
    } catch (e) {}
  }
  try {
    var proto = Storage.prototype;
    var _set = proto.setItem;
    proto.setItem = function(k, v){
      var r = _set.apply(this, arguments);
      try {
        if (String(k || '').indexOf('__xyzw') !== 0) {
          if (window.__xyzwPrefsDumpTimer) clearTimeout(window.__xyzwPrefsDumpTimer);
          window.__xyzwPrefsDumpTimer = setTimeout(dump, 500);
        }
      } catch (e) {}
      return r;
    };
  } catch (e) {}
  setInterval(dump, 12000);
  document.addEventListener('visibilitychange', dump);
  window.addEventListener('pagehide', dump);
  setTimeout(dump, 2000);
})();
''';
}
