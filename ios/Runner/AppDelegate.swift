import Flutter
import UIKit
import GoogleMobileAds
import google_mobile_ads
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
    FLTGoogleMobileAdsPlugin.registerNativeAdFactory(
      engineBridge.pluginRegistry, factoryId: "chessunlockNative", nativeAdFactory: ChessNativeAdFactory())
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

// Programmatic views keep factory registration and assets in the Runner target.
final class ChessNativeAdFactory: NSObject, FLTNativeAdFactory {
  func createNativeAd(_ nativeAd: NativeAd, customOptions: [AnyHashable: Any]? = nil) -> NativeAdView? {
    let medium = customOptions?["medium"] as? Bool ?? false
    let dark = customOptions?["dark"] as? Bool ?? false
    let root = NativeAdView()
    root.backgroundColor = dark ? UIColor(white: 0.15, alpha: 1) : UIColor(white: 0.96, alpha: 1)
    func label(_ text: String?, _ size: CGFloat) -> UILabel {
      let view = UILabel()
      view.text = text
      view.font = .systemFont(ofSize: size)
      view.textColor = dark ? .white : .black
      return view
    }
    func pin(_ view: UIView) {
      view.translatesAutoresizingMaskIntoConstraints = false
      root.addSubview(view)
    }
    let headline = label(nativeAd.headline, medium ? 16 : 12)
    headline.numberOfLines = 2
    let attribution = label("Ad", 12)
    attribution.font = .boldSystemFont(ofSize: 12)
    attribution.textColor = .black
    attribution.backgroundColor = UIColor(red: 1, green: 0.82, blue: 0.31, alpha: 1)
    attribution.textAlignment = .center
    attribution.widthAnchor.constraint(equalToConstant: 24).isActive = true
    attribution.heightAnchor.constraint(greaterThanOrEqualToConstant: 18).isActive = true
    let advertiser = label(nativeAd.advertiser ?? nativeAd.store, 10)
    let details = UIStackView(arrangedSubviews: [attribution, advertiser])
    details.spacing = 5
    attribution.setContentHuggingPriority(.required, for: .horizontal)
    let text = UIStackView(arrangedSubviews: [headline, details])
    text.axis = .vertical
    text.spacing = 2
    pin(text)
    let icon = UIImageView(image: nativeAd.icon?.image)
    icon.contentMode = .scaleAspectFit
    pin(icon)
    root.iconView = icon
    let iconWidth: CGFloat = nativeAd.icon?.image == nil ? 0 : 36
    NSLayoutConstraint.activate([
      icon.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
      icon.centerYAnchor.constraint(equalTo: text.centerYAnchor),
      icon.widthAnchor.constraint(equalToConstant: iconWidth),
      icon.heightAnchor.constraint(equalToConstant: 36)
    ])
    let cta = UIButton(type: .system)
    cta.setTitle(nativeAd.callToAction, for: .normal)
    cta.titleLabel?.font = .systemFont(ofSize: 11, weight: .semibold)
    cta.titleLabel?.numberOfLines = 2
    cta.backgroundColor = dark ? UIColor.darkGray : UIColor.white
    cta.isHidden = nativeAd.callToAction == nil
    cta.isUserInteractionEnabled = false // Google handles native-ad clicks.
    pin(cta)
    NSLayoutConstraint.activate([
      text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: iconWidth == 0 ? 0 : 6),
      text.trailingAnchor.constraint(equalTo: cta.leadingAnchor, constant: -6),
      text.centerYAnchor.constraint(equalTo: root.topAnchor, constant: medium ? 190 : 27),
      cta.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
      cta.widthAnchor.constraint(equalToConstant: 88),
      cta.heightAnchor.constraint(equalToConstant: 44),
      cta.centerYAnchor.constraint(equalTo: text.centerYAnchor)
    ])
    root.headlineView = headline
    root.callToActionView = cta
    if nativeAd.advertiser != nil { root.advertiserView = advertiser }
    else { root.storeView = advertiser }
    if medium {
      let media = MediaView()
      media.contentMode = .scaleAspectFit
      pin(media)
      NSLayoutConstraint.activate([
        media.leadingAnchor.constraint(equalTo: root.leadingAnchor),
        media.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        media.topAnchor.constraint(equalTo: root.topAnchor),
        media.heightAnchor.constraint(equalToConstant: 140)
      ])
      root.mediaView = media
      media.mediaContent = nativeAd.mediaContent
    }
    root.nativeAd = nativeAd
    return root
  }
}
