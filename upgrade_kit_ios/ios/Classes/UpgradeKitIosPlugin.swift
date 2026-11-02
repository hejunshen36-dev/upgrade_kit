import Flutter
import UIKit

public class UpgradeKitIosPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "upgrade_kit", binaryMessenger: registrar.messenger())
    let instance = UpgradeKitIosPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getIosAppVersion":
      guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            !version.isEmpty else {
        result(FlutterError(code: "version-unavailable", message: "Unable to read the current app version.", details: nil))
        return
      }
      result(version)
    case "openStore":
      openStore(call, result: result)
    case "checkAppUpdate", "showUpdateDialog", "installApk":
      result(FlutterError(
        code: "unsupported",
        message: "\(call.method) is not supported on iOS.",
        details: nil
      ))
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func openStore(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let arguments = call.arguments as? [String: Any],
      let target = arguments["target"] as? String,
      !target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      result("failed")
      return
    }

    let appID = target.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      appID.unicodeScalars.allSatisfy(CharacterSet.decimalDigits.contains),
      let storeURL = URL(string: "itms-apps://itunes.apple.com/app/id\(appID)"),
      let webURL = URL(string: "https://apps.apple.com/app/id\(appID)")
    else {
      result("failed")
      return
    }

    DispatchQueue.main.async {
      UIApplication.shared.open(storeURL, options: [:]) { opened in
        guard !opened else {
          result("launched")
          return
        }
        UIApplication.shared.open(webURL, options: [:]) { fallbackOpened in
          result(fallbackOpened ? "launched" : "failed")
        }
      }
    }
  }
}
