import Flutter
import UIKit
import AppTrackingTransparency

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    ScreenTimeBridge.register(with: engineBridge.applicationRegistrar)
    let channel = FlutterMethodChannel(
      name: "chessunlock/ad_tracking",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "waitUntilActive":
        self?.whenReadyForConsent { result(nil) }
      case "requestTrackingAuthorization":
        self?.requestTrackingAuthorization(result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // UMP can present ATT itself when an IDFA message is published. If it did
  // not, request it here after UMP finishes; never prompt twice after a decision.
  private func requestTrackingAuthorization(_ result: @escaping FlutterResult) {
    whenReadyForConsent {
      guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else {
        result(Int(ATTrackingManager.trackingAuthorizationStatus.rawValue))
        return
      }
      ATTrackingManager.requestTrackingAuthorization { [weak self] status in
        DispatchQueue.main.async {
          if status == .notDetermined {
            // An interruption/another system permission can dismiss ATT without
            // a decision. Wait for the active app and retry instead of loading ads.
            self?.requestTrackingAuthorization(result)
          } else {
            result(Int(status.rawValue))
          }
        }
      }
    }
  }

  private func whenReadyForConsent(_ completion: @escaping () -> Void) {
    // Allow the preceding UMP/system dialog's dismissal to finish. This also
    // works with Flutter's scene lifecycle, without AppDelegate activation hooks.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
      guard let self = self else { return }
      let activeScene = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .first { $0.activationState == .foregroundActive }
      guard UIApplication.shared.applicationState == .active,
            let root = activeScene?.windows.first(where: { $0.isKeyWindow })?.rootViewController,
            root.presentedViewController == nil else {
        self.whenReadyForConsent(completion)
        return
      }
      completion()
    }
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    ScreenTimeBridge.reconcileOnAppActivation()
  }
}
