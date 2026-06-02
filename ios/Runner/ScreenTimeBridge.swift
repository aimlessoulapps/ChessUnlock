import FamilyControls
import Flutter
import ManagedSettings
import SwiftUI
import UIKit

private let familyActivitySelectionStoreKey = "ios.familyActivitySelection.v1"

final class ScreenTimeBridge: NSObject {
  private static let channelName = "chesslock/screen_time"
  private static let selectionPreviewViewType =
    "chesslock/screen_time_selection_preview"
  private static var sharedBridge: ScreenTimeBridge?

  private let channel: FlutterMethodChannel
  private let store = ManagedSettingsStore()
  private var pendingPickerResult: FlutterResult?
  private var pendingPreviewResult: FlutterResult?

  static func register(with registrar: FlutterApplicationRegistrar) {
    sharedBridge = ScreenTimeBridge(binaryMessenger: registrar.messenger())
    registrar.register(
      ScreenTimeSelectionPreviewViewFactory(),
      withId: selectionPreviewViewType
    )
  }

  private init(binaryMessenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: binaryMessenger
    )
    super.init()
    channel.setMethodCallHandler(handle)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isAvailable":
      result([
        "available": isScreenTimeApiAvailable,
        "minimumIosVersion": "15.2",
      ])
    case "authorizationStatus":
      authorizationStatus(result)
    case "requestAuthorization":
      requestAuthorization(result)
    case "presentFamilyActivityPicker":
      presentFamilyActivityPicker(result)
    case "selectionMetadata":
      selectionMetadata(result)
    case "presentSelectionPreview":
      presentSelectionPreview(result)
    case "syncLockState":
      syncLockState(call.arguments, result)
    case "applyShields":
      applyShields(result)
    case "clearShields":
      clearShields(result)
    case "startEnforcement":
      startEnforcement(result)
    case "stopEnforcement":
      stopEnforcement(result)
    case "unlockFor":
      unlockFor(call.arguments, result)
    case "relockNow":
      relockNow(result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private var isScreenTimeApiAvailable: Bool {
    if #available(iOS 15.2, *) {
      return true
    }
    return false
  }

  private func authorizationStatus(_ result: @escaping FlutterResult) {
    guard #available(iOS 15.2, *) else {
      result(statusPayload(status: "unavailable"))
      return
    }

    Task { @MainActor in
      let status = familyAuthorizationStatusName()
      debugLog("authorization status=\(status)")
      result(statusPayload(status: status))
    }
  }

  private func requestAuthorization(_ result: @escaping FlutterResult) {
    guard #available(iOS 15.2, *) else {
      result(statusPayload(status: "unavailable"))
      return
    }

    Task { @MainActor in
      do {
        if #available(iOS 16.0, *) {
          try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        } else {
          try await requestChildAuthorization()
        }
        let status = familyAuthorizationStatusName()
        debugLog("authorization request completed; status=\(status)")
        result(statusPayload(status: status))
      } catch {
        debugLog("authorization request failed; error=\(error.localizedDescription)")
        result(
          FlutterError(
            code: "authorizationFailed",
            message: "Family Controls authorization failed: \(error.localizedDescription). Check the Family Controls entitlement and provisioning profile.",
            details: nil
          )
        )
      }
    }
  }

  private func presentFamilyActivityPicker(_ result: @escaping FlutterResult) {
    guard #available(iOS 15.2, *) else {
      result(selectionPayload(completed: false, errorMessage: "Screen Time setup isn't available."))
      return
    }

    Task { @MainActor in
      guard familyAuthorizationStatusName() == "approved" else {
        result(selectionPayload(completed: false, errorMessage: "Screen Time permission is required."))
        return
      }

      guard pendingPickerResult == nil else {
        result(
          FlutterError(
            code: "pickerAlreadyPresented",
            message: "The Screen Time app picker is already open.",
            details: nil
          )
        )
        return
      }

      guard let presenter = activeViewController() else {
        result(
          FlutterError(
            code: "missingPresenter",
            message: "Unable to present the Screen Time app picker.",
            details: nil
          )
        )
        return
      }

      pendingPickerResult = result
      let initialSelection = loadSelection()
      debugLog(
        "presenting activity picker; apps=\(initialSelection.applicationTokens.count) categories=\(initialSelection.categoryTokens.count) webDomains=\(initialSelection.webDomainTokens.count)"
      )
      let view = FamilyActivityPickerSheet(
        initialSelection: initialSelection,
        onCancel: { [weak self] in
          self?.finishPicker(completed: false, selection: nil, errorMessage: nil)
        },
        onDone: { [weak self] selection in
          self?.saveSelection(selection)
          self?.finishPicker(completed: true, selection: selection, errorMessage: nil)
        }
      )
      let hostingController = UIHostingController(rootView: view)
      hostingController.isModalInPresentation = true
      presenter.present(hostingController, animated: true)
    }
  }

  private func selectionMetadata(_ result: @escaping FlutterResult) {
    guard #available(iOS 15.2, *) else {
      result(selectionPayload(completed: false, errorMessage: "Screen Time setup isn't available."))
      return
    }

    Task { @MainActor in
      let selection = loadSelection()
      debugLog(
        "selection metadata; apps=\(selection.applicationTokens.count) categories=\(selection.categoryTokens.count) webDomains=\(selection.webDomainTokens.count)"
      )
      result(selectionPayload(completed: true, selection: selection, errorMessage: nil))
    }
  }

  private func presentSelectionPreview(_ result: @escaping FlutterResult) {
    guard #available(iOS 15.2, *) else {
      result(selectionPayload(completed: false, errorMessage: "Screen Time setup isn't available."))
      return
    }

    Task { @MainActor in
      guard familyAuthorizationStatusName() == "approved" else {
        result(selectionPayload(completed: false, errorMessage: "Screen Time permission is required."))
        return
      }

      guard pendingPreviewResult == nil else {
        result(
          FlutterError(
            code: "previewAlreadyPresented",
            message: "The selected Screen Time apps preview is already open.",
            details: nil
          )
        )
        return
      }

      let selection = loadSelection()
      guard selectionTotalCount(selection) > 0 else {
        result(selectionPayload(completed: false, selection: selection, errorMessage: "No Screen Time apps selected."))
        return
      }

      guard let presenter = activeViewController() else {
        result(
          FlutterError(
            code: "missingPresenter",
            message: "Unable to show selected Screen Time apps.",
            details: nil
          )
        )
        return
      }

      pendingPreviewResult = result
      debugLog(
        "presenting selection preview; apps=\(selection.applicationTokens.count) categories=\(selection.categoryTokens.count) webDomains=\(selection.webDomainTokens.count)"
      )
      let view = FamilyActivitySelectionPreviewSheet(
        selection: selection,
        onDone: { [weak self] in
          self?.finishPreview(selection: selection)
        }
      )
      presenter.present(UIHostingController(rootView: view), animated: true)
    }
  }

  private func syncLockState(_ arguments: Any?, _ result: @escaping FlutterResult) {
    guard #available(iOS 15.2, *) else {
      result(operationPayload(success: false, action: "syncLockState", code: "unavailable", errorMessage: "Screen Time setup isn't available."))
      return
    }

    Task { @MainActor in
      let payload = arguments as? [String: Any] ?? [:]
      let lockEnabled = payload["lockEnabled"] as? Bool ?? false
      let indefiniteUnlock = payload["indefiniteUnlock"] as? Bool ?? false
      let unlockUntilMs = int64Value(from: payload["unlockUntilMs"]) ?? 0

      saveRuntimeState(
        lockEnabled: lockEnabled,
        indefiniteUnlock: indefiniteUnlock,
        unlockUntilMs: unlockUntilMs
      )
      debugLog(
        "sync lock state; lockEnabled=\(lockEnabled) indefiniteUnlock=\(indefiniteUnlock) unlockUntilMs=\(unlockUntilMs)"
      )

      if lockEnabled {
        result(applySelectionShields(action: "syncLockState"))
      } else {
        clearShieldSettings()
        result(operationPayload(success: true, action: "syncLockState", shielded: false))
      }
    }
  }

  private func applyShields(_ result: @escaping FlutterResult) {
    guard #available(iOS 15.2, *) else {
      result(operationPayload(success: false, action: "applyShields", code: "unavailable", errorMessage: "Screen Time setup isn't available."))
      return
    }

    Task { @MainActor in
      result(applySelectionShields(action: "applyShields"))
    }
  }

  private func clearShields(_ result: @escaping FlutterResult) {
    guard #available(iOS 15.2, *) else {
      result(operationPayload(success: false, action: "clearShields", code: "unavailable", errorMessage: "Screen Time setup isn't available."))
      return
    }

    Task { @MainActor in
      clearShieldSettings()
      result(operationPayload(success: true, action: "clearShields", shielded: false))
    }
  }

  private func startEnforcement(_ result: @escaping FlutterResult) {
    guard #available(iOS 15.2, *) else {
      result(operationPayload(success: false, action: "startEnforcement", code: "unavailable", errorMessage: "Screen Time setup isn't available."))
      return
    }

    Task { @MainActor in
      debugLog("start enforcement requested")
      saveRuntimeState(lockEnabled: true, indefiniteUnlock: false, unlockUntilMs: 0)
      result(applySelectionShields(action: "startEnforcement"))
    }
  }

  private func stopEnforcement(_ result: @escaping FlutterResult) {
    guard #available(iOS 15.2, *) else {
      result(operationPayload(success: false, action: "stopEnforcement", code: "unavailable", errorMessage: "Screen Time setup isn't available."))
      return
    }

    Task { @MainActor in
      debugLog("stop enforcement requested")
      clearShieldSettings()
      result(operationPayload(success: true, action: "stopEnforcement", shielded: false))
    }
  }

  private func unlockFor(_ arguments: Any?, _ result: @escaping FlutterResult) {
    guard #available(iOS 15.2, *) else {
      result(operationPayload(success: false, action: "unlockFor", code: "unavailable", errorMessage: "Screen Time setup isn't available."))
      return
    }

    Task { @MainActor in
      let payload = arguments as? [String: Any] ?? [:]
      let indefiniteUnlock = payload["indefinite"] as? Bool ?? false
      let unlockUntilMs = int64Value(from: payload["unlockUntilMs"]) ?? 0
      saveRuntimeState(
        lockEnabled: false,
        indefiniteUnlock: indefiniteUnlock,
        unlockUntilMs: unlockUntilMs
      )
      debugLog(
        "unlockFor requested; indefinite=\(indefiniteUnlock) unlockUntilMs=\(unlockUntilMs)"
      )
      clearShieldSettings()
      result(operationPayload(success: true, action: "unlockFor", shielded: false))
    }
  }

  private func relockNow(_ result: @escaping FlutterResult) {
    guard #available(iOS 15.2, *) else {
      result(operationPayload(success: false, action: "relockNow", code: "unavailable", errorMessage: "Screen Time setup isn't available."))
      return
    }

    Task { @MainActor in
      debugLog("relockNow requested")
      saveRuntimeState(lockEnabled: true, indefiniteUnlock: false, unlockUntilMs: 0)
      result(applySelectionShields(action: "relockNow"))
    }
  }

  private func statusPayload(status: String) -> [String: Any] {
    [
      "available": isScreenTimeApiAvailable,
      "status": status,
    ]
  }

  private func activeViewController() -> UIViewController? {
    let activeScene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    let window = activeScene?.windows.first { $0.isKeyWindow }
      ?? UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap(\.windows)
        .first { $0.isKeyWindow }
    return topViewController(from: window?.rootViewController)
  }

  private func topViewController(from root: UIViewController?) -> UIViewController? {
    if let nav = root as? UINavigationController {
      return topViewController(from: nav.visibleViewController)
    }
    if let tab = root as? UITabBarController {
      return topViewController(from: tab.selectedViewController)
    }
    if let presented = root?.presentedViewController {
      return topViewController(from: presented)
    }
    return root
  }

  private func debugLog(_ message: String) {
    print("[screen-time][ios] \(message)")
  }
}

@available(iOS 15.2, *)
private extension ScreenTimeBridge {
  private var selectionStoreKey: String {
    familyActivitySelectionStoreKey
  }

  private var lockEnabledStoreKey: String {
    "ios.screenTime.lockEnabled.v1"
  }

  private var indefiniteUnlockStoreKey: String {
    "ios.screenTime.indefiniteUnlock.v1"
  }

  private var unlockUntilStoreKey: String {
    "ios.screenTime.unlockUntilMs.v1"
  }

  @MainActor
  func familyAuthorizationStatusName() -> String {
    switch AuthorizationCenter.shared.authorizationStatus {
    case .notDetermined:
      return "notDetermined"
    case .denied:
      return "denied"
    case .approved:
      return "approved"
    @unknown default:
      return "unknown"
    }
  }

  func requestChildAuthorization() async throws {
    try await withCheckedThrowingContinuation { continuation in
      AuthorizationCenter.shared.requestAuthorization { result in
        switch result {
        case .success:
          continuation.resume()
        case .failure(let error):
          continuation.resume(throwing: error)
        }
      }
    }
  }

  func loadSelection() -> FamilyActivitySelection {
    guard let data = UserDefaults.standard.data(forKey: selectionStoreKey),
          let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
      return FamilyActivitySelection()
    }
    return selection
  }

  func saveSelection(_ selection: FamilyActivitySelection) {
    guard let data = try? JSONEncoder().encode(selection) else {
      return
    }
    UserDefaults.standard.set(data, forKey: selectionStoreKey)
  }

  func saveRuntimeState(
    lockEnabled: Bool,
    indefiniteUnlock: Bool,
    unlockUntilMs: Int64
  ) {
    UserDefaults.standard.set(lockEnabled, forKey: lockEnabledStoreKey)
    UserDefaults.standard.set(indefiniteUnlock, forKey: indefiniteUnlockStoreKey)
    UserDefaults.standard.set(unlockUntilMs, forKey: unlockUntilStoreKey)
  }

  func int64Value(from value: Any?) -> Int64? {
    if let number = value as? NSNumber {
      return number.int64Value
    }
    if let intValue = value as? Int {
      return Int64(intValue)
    }
    if let int64Value = value as? Int64 {
      return int64Value
    }
    if let doubleValue = value as? Double {
      return Int64(doubleValue)
    }
    if let stringValue = value as? String {
      return Int64(stringValue)
    }
    return nil
  }

  @MainActor
  func applySelectionShields(action: String) -> [String: Any] {
    guard familyAuthorizationStatusName() == "approved" else {
      clearShieldSettings()
      debugLog("shield \(action) failed; authorization required")
      return operationPayload(
        success: false,
        action: action,
        code: "authorizationRequired",
        errorMessage: "Screen Time permission is required."
      )
    }

    let selection = loadSelection()
    guard selectionTotalCount(selection) > 0 else {
      clearShieldSettings()
      debugLog("shield \(action) no-op; empty selection")
      return operationPayload(
        success: true,
        action: action,
        selection: selection,
        shielded: false,
        message: "No Screen Time apps selected."
      )
    }

    store.shield.applications = selection.applicationTokens.isEmpty
      ? nil
      : selection.applicationTokens
    store.shield.webDomains = selection.webDomainTokens.isEmpty
      ? nil
      : selection.webDomainTokens

    if selection.categoryTokens.isEmpty {
      store.shield.applicationCategories = nil
      store.shield.webDomainCategories = nil
    } else {
      store.shield.applicationCategories =
        ManagedSettings.ShieldSettings.ActivityCategoryPolicy<ManagedSettings.Application>
          .specific(selection.categoryTokens)
      store.shield.webDomainCategories =
        ManagedSettings.ShieldSettings.ActivityCategoryPolicy<ManagedSettings.WebDomain>
        .specific(selection.categoryTokens)
    }

    debugLog(
      "shield \(action) applied; apps=\(selection.applicationTokens.count) categories=\(selection.categoryTokens.count) webDomains=\(selection.webDomainTokens.count)"
    )
    return operationPayload(
      success: true,
      action: action,
      selection: selection,
      shielded: true
    )
  }

  @MainActor
  func clearShieldSettings() {
    store.shield.applications = nil
    store.shield.applicationCategories = nil
    store.shield.webDomains = nil
    store.shield.webDomainCategories = nil
    debugLog("shield settings cleared")
  }

  @MainActor
  func finishPicker(
    completed: Bool,
    selection: FamilyActivitySelection?,
    errorMessage: String?
  ) {
    let payload = selectionPayload(
      completed: completed,
      selection: selection,
      errorMessage: errorMessage
    )
    if let selection {
      debugLog(
        "picker finished; completed=\(completed) apps=\(selection.applicationTokens.count) categories=\(selection.categoryTokens.count) webDomains=\(selection.webDomainTokens.count)"
      )
    } else {
      debugLog("picker finished; completed=\(completed)")
    }
    let result = pendingPickerResult
    pendingPickerResult = nil

    activeViewController()?.dismiss(animated: true) {
      result?(payload)
    }
  }

  @MainActor
  func finishPreview(selection: FamilyActivitySelection) {
    let payload = selectionPayload(
      completed: true,
      selection: selection,
      errorMessage: nil
    )
    debugLog(
      "selection preview dismissed; apps=\(selection.applicationTokens.count) categories=\(selection.categoryTokens.count) webDomains=\(selection.webDomainTokens.count)"
    )
    let result = pendingPreviewResult
    pendingPreviewResult = nil

    activeViewController()?.dismiss(animated: true) {
      result?(payload)
    }
  }

  func selectionPayload(
    completed: Bool,
    selection: FamilyActivitySelection? = nil,
    errorMessage: String? = nil
  ) -> [String: Any] {
    let currentSelection = selection ?? FamilyActivitySelection()
    var payload: [String: Any] = [
      "completed": completed,
      "applicationCount": currentSelection.applicationTokens.count,
      "categoryCount": currentSelection.categoryTokens.count,
      "webDomainCount": currentSelection.webDomainTokens.count,
      "includeEntireCategory": currentSelection.includeEntireCategory,
    ]
    if let errorMessage {
      payload["errorMessage"] = errorMessage
    }
    return payload
  }

  func operationPayload(
    success: Bool,
    action: String,
    selection: FamilyActivitySelection? = nil,
    shielded: Bool = false,
    message: String? = nil,
    code: String? = nil,
    errorMessage: String? = nil
  ) -> [String: Any] {
    let currentSelection = selection ?? loadSelection()
    var payload = selectionPayload(completed: true, selection: currentSelection)
    payload["success"] = success
    payload["action"] = action
    payload["shielded"] = shielded
    if let message {
      payload["message"] = message
    }
    if let code {
      payload["code"] = code
    }
    if let errorMessage {
      payload["errorMessage"] = errorMessage
    }
    return payload
  }

  func selectionTotalCount(_ selection: FamilyActivitySelection) -> Int {
    selection.applicationTokens.count
      + selection.categoryTokens.count
      + selection.webDomainTokens.count
  }
}

@available(iOS 15.2, *)
private struct FamilyActivityPickerSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var selection: FamilyActivitySelection

  let onCancel: () -> Void
  let onDone: (FamilyActivitySelection) -> Void

  init(
    initialSelection: FamilyActivitySelection,
    onCancel: @escaping () -> Void,
    onDone: @escaping (FamilyActivitySelection) -> Void
  ) {
    _selection = State(initialValue: initialSelection)
    self.onCancel = onCancel
    self.onDone = onDone
  }

  var body: some View {
    NavigationView {
      FamilyActivityPicker(selection: $selection)
        .navigationTitle("Choose Apps")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
              onCancel()
            }
          }
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") {
              onDone(selection)
            }
          }
        }
    }
  }
}

@available(iOS 15.2, *)
private struct FamilyActivitySelectionPreviewSheet: View {
  let selection: FamilyActivitySelection
  let onDone: () -> Void

  private var applicationTokens: [ApplicationToken] {
    Array(selection.applicationTokens)
  }

  private var categoryTokens: [ActivityCategoryToken] {
    Array(selection.categoryTokens)
  }

  private var webDomainTokens: [WebDomainToken] {
    Array(selection.webDomainTokens)
  }

  var body: some View {
    NavigationView {
      List {
        if !applicationTokens.isEmpty {
          Section("Apps") {
            ForEach(applicationTokens, id: \.self) { token in
              Label(token)
            }
          }
        }

        if !categoryTokens.isEmpty {
          Section("Categories") {
            ForEach(categoryTokens, id: \.self) { token in
              Label(token)
            }
            if selection.includeEntireCategory {
              Text("Entire selected categories are restricted.")
                .font(.footnote)
                .foregroundColor(.secondary)
            }
          }
        }

        if !webDomainTokens.isEmpty {
          Section("Web Domains") {
            ForEach(webDomainTokens, id: \.self) { token in
              Label(token)
            }
          }
        }
      }
      .navigationTitle("Selected Apps")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") {
            onDone()
          }
        }
      }
    }
  }
}

private final class ScreenTimeSelectionPreviewViewFactory: NSObject, FlutterPlatformViewFactory {
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?)
    -> FlutterPlatformView
  {
    ScreenTimeSelectionPreviewPlatformView(
      frame: frame,
      viewId: viewId,
      arguments: args
    )
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

private final class ScreenTimeSelectionPreviewPlatformView: NSObject, FlutterPlatformView {
  private let containerView: UIView
  private let hostingController: UIHostingController<FamilyActivityInlinePreview>

  init(frame: CGRect, viewId: Int64, arguments: Any?) {
    let selection = ScreenTimeSelectionPreviewPlatformView.loadSelection()
    let expectedCount = ScreenTimeSelectionPreviewPlatformView.intValue(
      from: (arguments as? [String: Any])?["expectedCount"]
    )
    let totalCount = selection.applicationTokens.count
      + selection.categoryTokens.count
      + selection.webDomainTokens.count

    containerView = UIView(frame: frame)
    hostingController = UIHostingController(
      rootView: FamilyActivityInlinePreview(
        selection: selection,
        expectedCount: expectedCount
      )
    )

    super.init()

    containerView.backgroundColor = .clear
    hostingController.view.backgroundColor = .clear
    hostingController.view.translatesAutoresizingMaskIntoConstraints = false
    containerView.addSubview(hostingController.view)
    NSLayoutConstraint.activate([
      hostingController.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
      hostingController.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
      hostingController.view.topAnchor.constraint(equalTo: containerView.topAnchor),
      hostingController.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
    ])

    print(
      "[screen-time][ios] inline preview render started; viewId=\(viewId) apps=\(selection.applicationTokens.count) categories=\(selection.categoryTokens.count) webDomains=\(selection.webDomainTokens.count)"
    )
    if totalCount == 0 && expectedCount > 0 {
      print("[screen-time][ios] inline preview fallback used; stored selection empty but Flutter expected \(expectedCount)")
    }
  }

  func view() -> UIView {
    containerView
  }

  private static func loadSelection() -> FamilyActivitySelection {
    guard let data = UserDefaults.standard.data(forKey: familyActivitySelectionStoreKey),
          let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
      return FamilyActivitySelection()
    }
    return selection
  }

  private static func intValue(from value: Any?) -> Int {
    if let number = value as? NSNumber {
      return number.intValue
    }
    if let intValue = value as? Int {
      return intValue
    }
    return 0
  }
}

private struct FamilyActivityInlinePreview: View {
  let selection: FamilyActivitySelection
  let expectedCount: Int

  private var applicationTokens: [ApplicationToken] {
    Array(selection.applicationTokens)
  }

  private var categoryTokens: [ActivityCategoryToken] {
    Array(selection.categoryTokens)
  }

  private var webDomainTokens: [WebDomainToken] {
    Array(selection.webDomainTokens)
  }

  private var totalCount: Int {
    applicationTokens.count + categoryTokens.count + webDomainTokens.count
  }

  var body: some View {
    if totalCount == 0 {
      InlinePreviewFallbackText(expectedCount: expectedCount)
    } else {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 7) {
          ForEach(applicationTokens, id: \.self) { token in
            InlinePreviewTokenCard {
              Label(token)
            }
          }
          ForEach(categoryTokens, id: \.self) { token in
            InlinePreviewTokenCard {
              Label(token)
            }
          }
          ForEach(webDomainTokens, id: \.self) { token in
            InlinePreviewTokenCard {
              Label(token)
            }
          }
        }
        .padding(.vertical, 2)
        .padding(.trailing, 2)
      }
    }
  }
}

private struct InlinePreviewTokenCard<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    content
      .labelStyle(.iconOnly)
      .imageScale(.large)
      .frame(width: 42, height: 42)
      .background(Color(UIColor.secondarySystemBackground))
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(Color(UIColor.separator).opacity(0.35), lineWidth: 0.5)
      )
  }
}

private struct InlinePreviewFallbackText: View {
  let expectedCount: Int

  var body: some View {
    Text(fallbackText)
      .font(.subheadline.weight(.semibold))
      .foregroundColor(.secondary)
      .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
  }

  private var fallbackText: String {
    if expectedCount <= 0 {
      return "No apps selected yet."
    }
    if expectedCount == 1 {
      return "1 app selected"
    }
    return "\(expectedCount) selections saved"
  }
}
