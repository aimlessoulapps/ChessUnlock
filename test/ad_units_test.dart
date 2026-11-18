import 'package:chessUnlock/services/ad_unit_configuration.dart';
import 'package:chessUnlock/services/ad_units.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'ad_unit_mode_probe.dart' as probe;

void main() {
  test('compiler mode matches Flutter and every placement uses the expected ID',
      () {
    const mode = kReleaseMode
        ? 'release'
        : kProfileMode
            ? 'profile'
            : 'debug';
    probe.main([mode]);
    expect(AdUnits.testAds, !kReleaseMode);
  });
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test('$platform Flutter adapter uses compiler-selected IDs for all formats',
        () {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final ios = platform == TargetPlatform.iOS;
      expect(AdUnits.supported, isTrue);
      for (final placement in NativePlacement.values) {
        expect(AdUnits.native(placement),
            AdUnitConfiguration.native(placement, ios: ios));
      }
      expect(AdUnits.interstitial, AdUnitConfiguration.interstitial(ios: ios));
      expect(AdUnits.rewarded, AdUnitConfiguration.rewarded(ios: ios));
    });
  }
}
