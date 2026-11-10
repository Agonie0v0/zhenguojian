import Flutter
import UIKit
import DuanjuCore
import CFNetwork
import Network

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let networkMonitor = NWPathMonitor()
  private var networkType = "unknown"
  private var savedBrightness: CGFloat?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    ZgjEnsureCoreLinked()
    networkMonitor.pathUpdateHandler = { [weak self] path in
      let type = path.status != .satisfied ? "unknown"
        : path.usesInterfaceType(.cellular) ? "mobile" : "wifi"
      DispatchQueue.main.async { self?.networkType = type }
    }
    networkMonitor.start(queue: DispatchQueue(label: "zhenguojian.network"))
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DeviceSettings") {
      let channel = FlutterMethodChannel(name: "duanju/device", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self else { result(nil); return }
        switch call.method {
        case "networkType":
          result(self.networkType)
          return
        case "screenBrightness":
          result(Double(UIScreen.main.brightness))
          return
        case "setScreenBrightness":
          guard let arguments = call.arguments as? [String: Any],
                let value = arguments["value"] as? Double, value.isFinite else {
            result(FlutterError(code: "invalid_brightness", message: "Invalid brightness", details: nil))
            return
          }
          if self.savedBrightness == nil { self.savedBrightness = UIScreen.main.brightness }
          UIScreen.main.brightness = CGFloat(min(1, max(0.05, value)))
          result(true)
          return
        case "resetScreenBrightness":
          self.restoreBrightness()
          result(true)
          return
        default:
          break
        }
        guard call.method == "systemProxy" else {
          result(FlutterMethodNotImplemented)
          return
        }
        let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] ?? [:]
        func address(_ prefix: String) -> String {
          guard (settings["\(prefix)Enable"] as? NSNumber)?.boolValue == true,
                let host = settings["\(prefix)Proxy"] as? String,
                let port = settings["\(prefix)Port"] as? NSNumber,
                !host.isEmpty, port.intValue > 0 else { return "" }
          let name = host.contains(":") ? "[\(host)]" : host
          return "http://\(name):\(port.intValue)"
        }
        let http = address("HTTP")
        let https = address("HTTPS")
        result(["http": http, "https": https.isEmpty ? http : https,
                "bypass": settings["ExceptionsList"] as? [String] ?? [],
                "pac": (settings["ProxyAutoConfigEnable"] as? NSNumber)?.boolValue == true])
      }
    }
  }

  private func restoreBrightness() {
    if let brightness = savedBrightness { UIScreen.main.brightness = brightness }
    savedBrightness = nil
  }

  override func applicationWillResignActive(_ application: UIApplication) {
    restoreBrightness()
    super.applicationWillResignActive(application)
  }
}
