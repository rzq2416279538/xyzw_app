import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// 用 Foundation Bonjour 触发「本地网络」授权（避免 Network.NWBrowser 在 CI Xcode 上编译失败）
  private var bonjourBrowser: NetServiceBrowser?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    triggerLocalNetworkPermissionPrompt()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  private func triggerLocalNetworkPermissionPrompt() {
    let browser = NetServiceBrowser()
    browser.searchForServices(ofType: "_http._tcp.", inDomain: "local.")
    bonjourBrowser = browser
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
      self?.bonjourBrowser?.stop()
      self?.bonjourBrowser = nil
    }
  }
}
