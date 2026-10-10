import Flutter
import Network
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var localNetBrowser: NWBrowser?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 尽早触发 iOS「本地网络」系统弹窗，避免导入角色时才弹出导致 DNS/请求失败
    triggerLocalNetworkPermissionPrompt()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  /// Bonjour 浏览会弹出本地网络授权；短暂浏览后停止即可。
  private func triggerLocalNetworkPermissionPrompt() {
    let params = NWParameters()
    params.includePeerToPeer = true
    let browser = NWBrowser(for: .bonjour(type: "_http._tcp", domain: nil), using: params)
    browser.stateUpdateHandler = { _, _ in }
    browser.browseResultsChangedHandler = { _, _ in }
    browser.start(queue: .main)
    localNetBrowser = browser
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
      self?.localNetBrowser?.cancel()
      self?.localNetBrowser = nil
    }
  }
}
