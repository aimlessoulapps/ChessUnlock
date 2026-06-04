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

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
  private let store = ManagedSettingsStore()
  private var defaults: UserDefaults {
    UserDefaults(suiteName: screenTimeAppGroupIdentifier) ?? .standard
  }

  override func intervalDidEnd(for activity: DeviceActivityName) {
    super.intervalDidEnd(for: activity)
    guard activity == .chessUnlockRelock else {
      return
    }
    relockIfExpired()
  }

  private func relockIfExpired() {
    let indefiniteUnlock = defaults.bool(forKey: screenTimeIndefiniteUnlockStoreKey)
    let unlockUntilMs = Int64(defaults.integer(forKey: screenTimeUnlockUntilStoreKey))
    guard !indefiniteUnlock, unlockUntilMs > 0 else {
      return
    }

    let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
    guard unlockUntilMs <= nowMs else {
      return
    }

    defaults.set(true, forKey: screenTimeLockEnabledStoreKey)
    defaults.set(false, forKey: screenTimeIndefiniteUnlockStoreKey)
    defaults.set(0, forKey: screenTimeUnlockUntilStoreKey)
    applySavedSelectionShields()
  }

  private func applySavedSelectionShields() {
    guard let data = defaults.data(forKey: familyActivitySelectionStoreKey),
          let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
      clearShieldSettings()
      return
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
  }

  private func clearShieldSettings() {
    store.shield.applications = nil
    store.shield.applicationCategories = nil
    store.shield.webDomains = nil
    store.shield.webDomainCategories = nil
  }
}
