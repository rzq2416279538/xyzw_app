/// 对照 naiwa-release `importer/XyEndpoints.kt`
abstract final class XyEndpoints {
  static const wxAppId = 'wxfb0d5667e5cb1c44';
  static const bundleId = 'com.hortor.games.xyzw';
  static const wxScope =
      'snsapi_base,snsapi_userinfo,snsapi_friend,snsapi_message';
  static const signPrint =
      'E6:F7:FE:A9:EC:8E:24:D0:4F:2A:32:50:28:78:E1:C5:5E:70:81:13';

  static const hortorSdkVersion = '4.2.1-cn-release';
  static const cryptVersion = '1.1.0';
  static const iosVersion = '0.33.0';
  static const iosSdkVersion = '1.9.3';

  static String qrConnect() =>
      'https://open.weixin.qq.com/connect/app/qrconnect'
      '?appid=$wxAppId&bundleid=$bundleId&scope=$wxScope&state=weixin';

  static String qrImage(String uuid) =>
      'https://open.weixin.qq.com/connect/qrcode/$uuid';

  static String qrPoll(String uuid) =>
      'https://long.open.weixin.qq.com/connect/l/qrconnect'
      '?uuid=$uuid&f=url&_=${DateTime.now().millisecondsSinceEpoch}';

  static String serverList() =>
      'https://xxz-xyzw.hortorgames.com/login/serverlist?_seq=3';

  static String smsCode() =>
      'https://ucenter-app-server.hortorgames.com/ucenter-app-server/api/v1/login/verify/code';

  static String cryptMix(String deviceId) =>
      'https://comb-platform.hortorgames.com/comb-login-server/api/v1/login/crypt/mix'
      '?combGameId=xyzw_mix&deviceUniqueId=$deviceId&gameTp=app'
      '&packageName=$bundleId&system=ios&version=$iosVersion';

  static String combLoginApp(String deviceId, {String version = iosVersion}) =>
      'https://comb-platform.hortorgames.com/comb-login-server/api/v1/login'
      '?gameId=xyzwapp&gameTp=app&system=ios&cryptVersion=$cryptVersion'
      '&version=$version&deviceUniqueId=$deviceId'
      '&timestamp=${DateTime.now().millisecondsSinceEpoch}';

  static const uaMinigame =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/107.0.0.0 Safari/537.36 '
      'MicroMessenger/6.8.0(0x16080000) NetType/WIFI MiniProgramEnv/Mac '
      'MacWechat/WMPF MacWechat/3.8.7(0x13080710) XWEB/1191';

  static const refererMinigame =
      'https://appservice.qq.com/1112173744/1.66.5/page-frame.html';

  static const uaWxAndroid =
      'Mozilla/5.0 (Linux; Android 7.0; Mi-4c Build/NRD90M; wv) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Version/4.0 Chrome/53.0.2785.49 Mobile MQQBrowser/6.2 '
      'TBS/043632 Safari/537.36 MicroMessenger/6.6.1.1220(0x26060135) NetType/WIFI '
      'Language/zh_CN miniProgram';

  static const uaIos =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148';

  static const uaApp =
      'Mozilla/5.0 (Linux; Android 10; 23116PN5BC Build/HUAWEIJNY-AL10; wv) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/74.0.3729.186 '
      'Mobile Safari/537.36';
}

enum WxScanState {
  confirmed(405, '已确认授权'),
  scanned(404, '已扫码，等待确认'),
  waiting(408, '等待扫码'),
  expired(402, '二维码已过期'),
  rejected(403, '已取消授权'),
  unknown(-1, '未知状态');

  const WxScanState(this.code, this.label);
  final int code;
  final String label;

  static WxScanState of(int code) {
    for (final s in WxScanState.values) {
      if (s.code == code) return s;
    }
    return WxScanState.unknown;
  }
}
