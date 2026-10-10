window._CCSettings = {
  platform: 'web-mobile',
  groupList: ['default', 'ui', 'player', 'enemy'],
  collisionMatrix: [
    [false],
    [false, false],
    [false, false, false, true],
    [false, false, true, false]
  ],
  hasResourcesBundle: false,
  hasStartSceneBundle: false,
  remoteBundles: [],
  subpackages: [],
  launchScene: 'db://assets/launcher/scenes/Launcher.fire',
  orientation: 'portrait',
  // 对照「鸟哥之王 Pro」assets/www：使用其 HSDK.turnpass.min.js（无 hash）
  // HSDK 方法仍由 hsdk-mock 保护，避免被 turnpass 覆盖
  jsList: ['assets/launcher/common/libs/platform/hortor/HSDK.turnpass.min.js'],
  bundleVers: {
    // 对照 Pro：internal 资源带 a0340 后缀
    internal: 'a0340',
  }
}
