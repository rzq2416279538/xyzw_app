'use strict'
const gt =
  typeof globalThis === 'object' ? globalThis : typeof window === 'object' ? window : global
gt.PLATFORM = 'h5'
gt.SUB_PLATFORM = ''
gt.ENV = 'Prod'
gt.APPID = 'wx0840558555a454ed'
gt.APPID = ''
gt.CDN = 'https://xxz-xyzw-res.hortorgames.com'
gt.SERVER = 'https://xxz-xyzw.hortorgames.com'
gt.GAME_NAME = '咸鱼之王'
gt.GAME_ID = 'xyzw_mix'
// 能进盐场的网页端报 1.90.2-h5web，登录清单 codeVersion 也是 1.90.2。
// 活动包哈希另从 0.32.0-android 清单合并，不要把资源包号 2.48.2 写回这里。
gt.GAME_VERSION = '1.90.2-h5web'
gt.CODE_VERSION = '1.90.2'
gt.COMMIT_ID = ''
gt.CONFIG_COMMIT_ID = ''
gt.RESOURCES_COMMIT_ID = ''
gt.DOWNLOAD_URL = ''
gt.CDNS = ['https://xxz-xyzw-res.hortorgames.com', 'https://xxz-xyzw-alires.hortorgames.com']
gt.VERSION_POSTFIX = ''
gt.BATTLE_OSS_URL = 'https://xxz-xyzw-service-battle.hortorgames.com'
