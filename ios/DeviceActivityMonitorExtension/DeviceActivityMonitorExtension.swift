import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

private let screenTimeAppGroupIdentifier = "group.com.aimlessoul.chessunlock"
private let familyActivitySelectionStoreKey = "ios.familyActivitySelection.v1"
private let screenTimeLockEnabledStoreKey = "ios.screenTime.lockEnabled.v1"
private let screenTimeIndefiniteUnlockStoreKey = "ios.screenTime.indefiniteUnlock.v1"
private let screenTimeUnlockUntilStoreKey = "ios.screenTime.unlockUntilMs.v1"

extension DeviceActivityName {
  static let chessUnlockRelock = Self("ChessUnlockRelock")
}

extension DeviceActivityEvent.Name {
  static let chessUnlockRelockThreshold = Self("ChessUnlockRelockThreshold")
}

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
  private let store = ManagedSettingsStore()
  private var defaults: UserDefaults {
    UserDefaults(suiteName: screenTimeAppGroupIdentifier) ?? .standard
  }

  override func eventDidReachThreshold(
    _ event: DeviceActivityEvent.Name,
    activity: DeviceActivityName
  ) {
    super.eventDidReachThreshold(event, activity: activity)
    guard activity == .chessUnlockRelock,
          event == .chessUnlockRelockThreshold else {
      return
    }
    debugLog("eventDidReachThreshold fired; event=\(event.rawValue)")
    relockFromMonitor(action: "eventDidReachThreshold", requireExpired: false)
  }

  override func intervalDidEnd(for activity: DeviceActivityName) {
    super.intervalDidEnd(for: activity)
    guard activity == .chessUnlockRelock else {
      return
    }
    debugLog("intervalDidEnd fired")
    relockFromMonitor(action: "intervalDidEnd", requireExpired: true)
  }

  private func relockFromMonitor(action: String, requireExpired: Bool) {
    let indefiniteUnlock = defaults.bool(forKey: screenTimeIndefiniteUnlockStoreKey)
    let unlockUntilMs = Int64(defaults.integer(forKey: screenTimeUnlockUntilStoreKey))
    guard !indefiniteUnlock, unlockUntilMs > 0 else {
      debugLog(
        "\(action) skipped; indefiniteUnlock=\(indefiniteUnlock) unlockUntilMs=\(unlockUntilMs)"
      )
      return
    }

    let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
    guard !requireExpired || unlockUntilMs <= nowMs else {
      debugLog(
        "\(action) skipped; unlock not expired yet unlockUntilMs=\(unlockUntilMs) nowMs=\(nowMs)"
      )
      return
    }

    defaults.set(true, forKey: screenTimeLockEnabledStoreKey)
    defaults.set(false, forKey: screenTimeIndefiniteUnlockStoreKey)
    defaults.set(0, forKey: screenTimeUnlockUntilStoreKey)
    let applied = applySavedSelectionShields(action: action)
    debugLog("\(action) relock completed; shieldApplied=\(applied)")
  }

  @discardableResult
  private func applySavedSelectionShields(action: String) -> Bool {
    guard let data = defaults.data(forKey: familyActivitySelectionStoreKey),
          let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
      debugLog("\(action) failed to load App Group selection")
      clearShieldSettings()
      return false
    }

    debugLog(
      "\(action) loaded App Group selection; apps=\(selection.applicationTokens.count) categories=\(selection.categoryTokens.count) webDomains=\(selection.webDomainTokens.count)"
    )
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
    return true
  }

  private func clearShieldSettings() {
    store.shield.applications = nil
    store.shield.applicationCategories = nil
    store.shield.webDomains = nil
    store.shield.webDomainCategories = nil
  }

  private func debugLog(_ message: String) {
    print("[screen-time][monitor] \(message)")
  }
}
