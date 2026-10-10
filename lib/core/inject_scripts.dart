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
    var root = obj;
    var data = obj.data || obj.rawData || obj;
    var out = {
      parse: true,
      isLast: root.isLast,
      data_isLast: data && data.isLast,
      forceUpdate: root.forceUpdate != null ? root.forceUpdate : (data && data.forceUpdate),
      forceVer: root.forceVer != null ? root.forceVer : (data && data.forceVer),
      latestVer: root.latestVer != null ? root.latestVer : (data && data.latestVer),
      battleVersion: root.battleVersion != null ? root.battleVersion : (data && data.battleVersion),
      dataBundleVer: root.dataBundleVer || (data && data.dataBundleVer) || '',
      dataVers: root.dataVers || (data && data.dataVers) || '',
      serverUrl: root.serverUrl || (data && data.serverUrl) || '',
      bundleVersType: typeof (root.bundleVers != null ? root.bundleVers : (data && data.bundleVers))
    };
    // 和光回归：钉 isLast=true + 清空 latestVer 会让盐场/蟠桃活动 bundle 不拉
    out.risk_pinIsLast = (out.isLast === true || out.data_isLast === true);
    out.risk_emptyLatest = (out.latestVer === '' || out.latestVer === null);
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

  /// 比赛/踢线常见「客户端数据异常」侦测：抓弹窗、toast、console，并上报指纹便于对照。
  static const clientAnomalyWatch = r'''
(function(){
  if (window.__xyzwClientWatch) return;
  window.__xyzwClientWatch = true;
  var KEYS = [
    '客户端数据异常', '官方最新客户端', '请使用官方', '数据异常',
    '客户端异常', '版本过低', '强制更新', '登录失效', '异地登录',
    '连接已断开', '网络异常', '重新登录', '账号在其他', '被踢',
    '盐场', '蟠桃', '点不了', 'RejectLowVersionPvP', '低版本',
    'client data', 'illegal client', 'official client'
  ];
  function hit(text){
    var s = String(text || '');
    if (!s) return null;
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
      out.ts = Date.now();
    } catch (e) {
      out.err = String(e && e.message || e);
    }
    return out;
  }
  function report(kind, text, extra){
    var key = hit(text);
    if (!key && kind !== 'fingerprint') return;
    var payload = {
      type: 'clientAnomaly',
      kind: kind,
      key: key || '',
      text: String(text || '').slice(0, 500),
      fingerprint: fingerprint(),
      extra: extra || null
    };
    console.error('[咸强之王][CLIENT_ANOMALY]', kind, key, String(text||'').slice(0, 180));
    try {
      if (window.XyzwBridge && window.XyzwBridge.postMessage) {
        window.XyzwBridge.postMessage(JSON.stringify(payload));
      }
    } catch (e) {}
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
        console.log('[咸强之王] 脚本请求下载(已忽略): ' + String(url).slice(0, 120));
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
}
