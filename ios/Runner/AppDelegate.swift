import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var gameKeepAliveTask: UIBackgroundTaskIdentifier = .invalid

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 不再主动 Bonjour 扫描「本地网络设备」；外网权限由 Dart 侧 HTTPS 预检即可。
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "XyzwBackground") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "xyzw/background",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "begin":
        self?.beginGameKeepAlive()
        result(true)
      case "end":
        self?.endGameKeepAlive()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// 游戏仍在前台页时切到其他 App：申请短时后台，尽量保活网络。
  private func beginGameKeepAlive() {
    endGameKeepAlive()
    gameKeepAliveTask = UIApplication.shared.beginBackgroundTask(withName: "xyzw-game-keepalive") { [weak self] in
      self?.endGameKeepAlive()
    }
  }

  private func endGameKeepAlive() {
    if gameKeepAliveTask != .invalid {
      UIApplication.shared.endBackgroundTask(gameKeepAliveTask)
      gameKeepAliveTask = .invalid
    }
  }
}
