# AdMob build-mode safeguards

All five placements now share a compiler-mode-only policy in `lib/services/ad_unit_configuration.dart`; `lib/services/ad_units.dart` adapts Android/iOS platform selection. Rewarded Hint/Skip in `lib/main.dart` uses that same policy. Native/interstitial callers and their lifecycles are unchanged.

| Mode | Native, interstitial, rewarded |
| --- | --- |
| Debug | Official Google test units |
| Profile | Official Google test units |
| Release | Existing real units for the selected platform |

Official rewarded test units:
- Android: `ca-app-pub-3940256099942544/5224354917`
- iOS: `ca-app-pub-3940256099942544/1712485313`

Existing production rewarded units are preserved:
- Android: `ca-app-pub-8108010703558411/1847579539`
- iOS: `ca-app-pub-8108010703558411/5800977815`

Home, Puzzle, Settings and Practice Interstitial production IDs and both platform App IDs are unchanged. No test-device configuration was added. Premium suppression, consent, preloading/retries, placements and reward delivery are unchanged. The obsolete iOS diagnostic requiring an override was removed because the default production ID is valid configuration.

## Release safeguard

There is no longer any code that consumes `CHESSUNLOCK_TEST_ADS`, `CHESSUNLOCK_REWARDED_AD_UNIT_ID`, `CHESSUNLOCK_ANDROID_REWARDED_AD_UNIT_ID`, or `CHESSUNLOCK_IOS_REWARDED_AD_UNIT_ID`. Passing any of those flags does not change the units, including in release builds. This policy executes without assertions and cannot be disabled by those application flags. It derives mode from the same `dart.vm.product`/`dart.vm.profile` compiler constants used by Flutter.

Use debug or profile builds to test ads. The former release QA test flag is no longer supported. This safeguard governs app code and build flags, not test-device/app-mode settings managed separately in the AdMob console.

## Repeatable regression checks

- `flutter test --no-pub` includes `test/ad_units_test.dart`: exact ID checks and Flutter platform-adapter coverage.
- `powershell -File tool/check_ad_unit_modes.ps1 -Dart <path-to-dart.exe>` runs `test/ad_unit_mode_probe.dart` under actual debug/profile/release compiler constants, first with no overrides, then with conflicting test overrides and conflicting live overrides. Every run checks all 10 platform/placement combinations.
- The script also compiles and executes an AOT product-mode probe with `CHESSUNLOCK_TEST_ADS=true` and Google test rewarded overrides, verifying production IDs with assertions removed and tree shaking enabled. Outputs stay under `build/ad-unit-checks`.

Official test IDs: https://developers.google.com/admob/flutter/rewarded, https://developers.google.com/admob/flutter/native/platforms, https://developers.google.com/admob/flutter/interstitial
