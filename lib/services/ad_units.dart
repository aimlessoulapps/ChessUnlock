import 'package:flutter/foundation.dart';
import 'ad_unit_configuration.dart';
export 'ad_unit_configuration.dart' show NativePlacement;

/// Flutter platform adapter for the compiler-mode-only ad configuration.
class AdUnits {
  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  static bool get _ios => defaultTargetPlatform == TargetPlatform.iOS;
  static const testAds = AdUnitConfiguration.testAds;
  static String native(NativePlacement placement) =>
      AdUnitConfiguration.native(placement, ios: _ios);
  static String get interstitial => AdUnitConfiguration.interstitial(ios: _ios);
  static String get rewarded => AdUnitConfiguration.rewarded(ios: _ios);
}
