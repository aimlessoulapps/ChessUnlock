import FamilyControls
import Flutter
import SwiftUI
import UIKit

final class ScreenTimeBridge: NSObject {
  private static let channelName = "chesslock/screen_time"
  private static var sharedBridge: ScreenTimeBridge?

  private let channel: FlutterMethodChannel
  private var pendingPickerResult: FlutterResult?

  static func register(with messenger: FlutterBinaryMessenger) {
    sharedBridge = ScreenTimeBridge(binaryMessenger: messenger)
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
        "minimumIosVersion": "15.0",
      ])
    case "authorizationStatus":
      authorizationStatus(result)
    case "requestAuthorization":
      requestAuthorization(result)
    case "presentFamilyActivityPicker":
      presentFamilyActivityPicker(result)
    case "selectionMetadata":
      selectionMetadata(result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private var isScreenTimeApiAvailable: Bool {
    if #available(iOS 15.0, *) {
      return true
    }
    return false
  }

  private func authorizationStatus(_ result: @escaping FlutterResult) {
    guard #available(iOS 15.0, *) else {
      result(statusPayload(status: "unavailable"))
      return
    }

    Task { @MainActor in
      result(statusPayload(status: familyAuthorizationStatusName()))
    }
  }

  private func requestAuthorization(_ result: @escaping FlutterResult) {
    guard #available(iOS 15.0, *) else {
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
        result(statusPayload(status: familyAuthorizationStatusName()))
      } catch {
        result(
          FlutterError(
            code: "authorizationFailed",
            message: error.localizedDescription,
            details: nil
          )
        )
      }
    }
  }

  private func presentFamilyActivityPicker(_ result: @escaping FlutterResult) {
    guard #available(iOS 15.0, *) else {
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
    guard #available(iOS 15.0, *) else {
      result(selectionPayload(completed: false, errorMessage: "Screen Time setup isn't available."))
      return
    }

    Task { @MainActor in
      result(selectionPayload(completed: true, selection: loadSelection(), errorMessage: nil))
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
}

@available(iOS 15.0, *)
private extension ScreenTimeBridge {
  private var selectionStoreKey: String {
    "ios.familyActivitySelection.v1"
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
    let result = pendingPickerResult
    pendingPickerResult = nil

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
}

@available(iOS 15.0, *)
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
