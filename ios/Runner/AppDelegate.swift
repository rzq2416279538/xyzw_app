import Flutter
import Photos
import UIKit
import WebKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var gameKeepAliveTask: UIBackgroundTaskIdentifier = .invalid

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 不再主动 Bonjour 扫描「本地网络设备」；外网权限由 Dart 侧 HTTPS 预检即可。
    // 键盘弹出时禁止 WKWebView 顶白/滚动挤压（游戏画面保持不动）
    let center = NotificationCenter.default
    center.addObserver(
      self,
      selector: #selector(onKeyboardAffectWebView),
      name: UIResponder.keyboardWillChangeFrameNotification,
      object: nil
    )
    center.addObserver(
      self,
      selector: #selector(onKeyboardAffectWebView),
      name: UIResponder.keyboardWillShowNotification,
      object: nil
    )
    center.addObserver(
      self,
      selector: #selector(onKeyboardAffectWebView),
      name: UIResponder.keyboardDidShowNotification,
      object: nil
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  @objc private func onKeyboardAffectWebView() {
    guard let root = window ?? UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .flatMap({ $0.windows })
      .first(where: { $0.isKeyWindow })
    else { return }
    hardenWebViews(in: root)
  }

  /// 关掉 WKWebView 随键盘调整 inset / 滚动，避免大块白屏。
  private func hardenWebViews(in view: UIView) {
    if let web = view as? WKWebView {
      let scroll = web.scrollView
      scroll.isScrollEnabled = false
      scroll.bounces = false
      scroll.alwaysBounceVertical = false
      scroll.keyboardDismissMode = .none
      if #available(iOS 11.0, *) {
        scroll.contentInsetAdjustmentBehavior = .never
      }
      scroll.contentInset = .zero
      scroll.scrollIndicatorInsets = .zero
      if scroll.contentOffset != .zero {
        scroll.setContentOffset(.zero, animated: false)
      }
    }
    for child in view.subviews {
      hardenWebViews(in: child)
    }
  }

  /// 对照拟沧澜：整 App 仅竖屏。键盘弹出时系统/WebView 也不得切横屏。
  override func application(
    _ application: UIApplication,
    supportedInterfaceOrientationsFor window: UIWindow?
  ) -> UIInterfaceOrientationMask {
    return .portrait
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "XyzwBackground") else {
      return
    }
    let messenger = registrar.messenger()

    let bg = FlutterMethodChannel(name: "xyzw/background", binaryMessenger: messenger)
    bg.setMethodCallHandler { [weak self] call, result in
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

    let media = FlutterMethodChannel(name: "xyzw/media", binaryMessenger: messenger)
    media.setMethodCallHandler { call, result in
      switch call.method {
      case "saveImageBase64":
        Self.saveImageBase64(call.arguments, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func saveImageBase64(_ arguments: Any?, result: @escaping FlutterResult) {
    guard
      let args = arguments as? [String: Any],
      let b64 = args["base64"] as? String
    else {
      result(FlutterError(code: "bad_args", message: "base64 required", details: nil))
      return
    }
    var raw = b64.trimmingCharacters(in: .whitespacesAndNewlines)
    if raw.hasPrefix("data:"), let range = raw.range(of: "base64,") {
      raw = String(raw[range.upperBound...])
    }
    guard let data = Data(base64Encoded: raw, options: .ignoreUnknownCharacters),
          let image = UIImage(data: data)
    else {
      result(FlutterError(code: "bad_image", message: "decode failed", details: nil))
      return
    }

    let write: () -> Void = {
      PHPhotoLibrary.shared().performChanges({
        PHAssetChangeRequest.creationRequestForAsset(from: image)
      }) { ok, error in
        DispatchQueue.main.async {
          if ok {
            result(true)
          } else {
            result(
              FlutterError(
                code: "save_failed",
                message: error?.localizedDescription ?? "unknown",
                details: nil
              )
            )
          }
        }
      }
    }

    if #available(iOS 14, *) {
      PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
        if status == .authorized || status == .limited {
          write()
        } else {
          DispatchQueue.main.async {
            result(FlutterError(code: "denied", message: "photo add denied", details: nil))
          }
        }
      }
    } else {
      PHPhotoLibrary.requestAuthorization { status in
        if status == .authorized {
          write()
        } else {
          DispatchQueue.main.async {
            result(FlutterError(code: "denied", message: "photo denied", details: nil))
          }
        }
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
