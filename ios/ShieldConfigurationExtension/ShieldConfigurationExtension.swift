import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
  private let title = ShieldConfiguration.Label(
    text: "This app is Restricted",
    color: .label
  )
  private let subtitle = ShieldConfiguration.Label(
    text: "Solve a chess puzzle in ChessUnlock to use this app.",
    color: .secondaryLabel
  )
  private let primaryButtonLabel = ShieldConfiguration.Label(
    text: "Open ChessUnlock",
    color: .white
  )
  private let primaryButtonBackgroundColor = UIColor(
    red: 0.263,
    green: 0.839,
    blue: 0.431,
    alpha: 1.0
  )

  override func configuration(
    shielding application: Application
  ) -> ShieldConfiguration {
    configuration()
  }

  override func configuration(
    shielding application: Application,
    in category: ActivityCategory
  ) -> ShieldConfiguration {
    configuration()
  }

  override func configuration(
    shielding webDomain: WebDomain
  ) -> ShieldConfiguration {
    configuration()
  }

  override func configuration(
    shielding webDomain: WebDomain,
    in category: ActivityCategory
  ) -> ShieldConfiguration {
    configuration()
  }

  private func configuration() -> ShieldConfiguration {
    ShieldConfiguration(
      backgroundBlurStyle: .systemMaterial,
      backgroundColor: .systemBackground,
      icon: appIcon(),
      title: title,
      subtitle: subtitle,
      primaryButtonLabel: primaryButtonLabel,
      primaryButtonBackgroundColor: primaryButtonBackgroundColor
    )
  }

  private func appIcon() -> UIImage? {
    UIImage(named: "AppIcon")
  }
}
