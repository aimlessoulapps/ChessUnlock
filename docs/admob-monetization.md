# AdMob monetization update

The active project is the repository root, not the nested `ChessUnlock/` copy.

## Placements and layout

IDs for native, interstitial, and rewarded Hint/Skip ads are centralized in `lib/services/ad_unit_configuration.dart`, with the Flutter platform adapter in `ad_units.dart`. Debug/profile builds always use Google test units; release builds always use the existing production units. Legacy `CHESSUNLOCK_TEST_ADS` and rewarded ad-unit overrides are ignored in every mode. Use debug/profile for test-ad QA. Rewarded loading, rewards, consent and Premium behavior are unchanged. See `ad-build-mode-safeguards.md` for regression checks.

Home has one 240 logical-pixel native view (plus 8 pixels spacing above/below), after Locked Apps in the existing content list. Its 140-pixel media view supports video and image assets. The old header banner and 54-pixel reservation are removed. The Solve button and bottom navigation stay outside the list. A compact emergency-unlock control is centered between Locked Apps and Edit, with the selection count below the label. Small displays scroll existing content when needed; ads and controls are never scaled down to fit.

Puzzle uses a 54-pixel compact native view at its header. Settings uses one 240-pixel medium native view in the scrolling list below Difficulty and above Appearance, with 8 pixels of vertical padding on each side; its header has no ad. Unloaded, failed, inactive, and Premium placements collapse. Compact views use headline, available icon, advertiser/store, Ad attribution and CTA; Home and Settings additionally have media. SDK-owned AdChoices and click handling are retained. Factories receive the Flutter theme and reload on theme changes.

## Native caching

The shell now preloads all three native placements after consent/SDK initialization and Premium resolution, retains them across tab changes, and refreshes at 55 minutes. See `native-preloading-and-breaks.md` for the follow-up implementation and validation.

## Interstitial behavior

Only the first successful, statistics-recorded solve in the existing voluntary practice mode contributes to the counter. Unlock puzzles, skips, duplicate completion callbacks and Premium completions do not increment it. Consent eligibility also gates counting. The counter saturates at five, so unavailable ads never create a backlog of multiple ads.

The count and last actual display timestamp use SharedPreferences. A display requires five completions and at least ten minutes since the previous display, including across restarts. The count resets only on the SDK display callback. If readiness, cooldown, lifecycle, navigation, consent or unlock checks fail, practice continues; eligibility is reconsidered only at a later completed-practice transition. No timer or resume callback displays ads. The cooldown starts on display, not load or dismissal.

Interstitials preload independently. Failed loads retry after one minute while eligible and foregrounded; ads older than 55 minutes are replaced. Premium/consent changes invalidate pending loads. The transition waits only for an already-ready ad's normal dismissal, never for an ad load. There are no custom close controls or minimum viewing duration.

## Files

- `lib/services/ad_units.dart`: production/test placement IDs.
- `lib/widgets/native_ad_slot.dart`: native loading, theme, consent, visibility and disposal.
- `lib/services/practice_interstitial.dart`: persistent cap and interstitial lifecycle.
- `lib/ui.dart`: native placements and removal of banners.
- `lib/main.dart`: practice transition integration and removal of banner prewarming.
- `android/app/src/main/kotlin/com/aimlessoul/chessunlock/ChessNativeAdFactory.kt`: native Android assets/layout.
- `android/app/src/main/kotlin/com/aimlessoul/chessunlock/MainActivity.kt`: factory registration and cleanup.
- `ios/Runner/AppDelegate.swift`: iOS factory and implicit-engine registration, in the existing Runner source target.
- `test/ad_premium_visibility_test.dart`, `test/unlock_flow_test.dart`, `test/reviewer_code_test.dart`: native replacements in existing assertions.
- `test/practice_interstitial_test.dart`, `test/practice_interstitial_lifecycle_test.dart`, `test/native_ad_layout_test.dart`: counter, SDK callbacks and layout coverage.

Pre-existing reviewer access edits in `premium_access_service.dart` and `ui.dart` were preserved. No subscription identities, prices, purchase/restore flows, app-locking implementations, or puzzle rules were changed.

## Validation and release checks

- Android debug APK builds at `build/app/outputs/flutter-apk/app-debug.apk`.
- Complete regression suite, including counter/callback and native layout tests: 121 passing.
- Twelve passing native layout tests cover Android/iOS, light/dark and a 320 x 568 viewport with mocked platform views. The Home cases also verify that loading the ad does not move the Solve button. These do not render or validate actual native creative assets.
- `flutter analyze --no-pub lib test`: no errors/warnings; three existing `prefer_collection_literals` notices in `puzzle_queue_service.dart`.
- Full repository analysis additionally encounters pre-existing broken imports/deprecations in the nested `ChessUnlock/` copy.
- iOS compilation is unavailable on this Windows host. On macOS, build Runner with the existing Flutter/Xcode setup and validate Swift factory compilation and scene-engine registration. No XIB, new target membership, or new app ID is needed.
- Before release, inspect real Google test image and video creatives on Android and iOS, including smaller phones, light/dark themes, text scaling, AdChoices, clicks, foreground/background, failed loads, fifth solve, cooldown, Premium/reviewer access and emergency unlocking. Use debug/profile builds for test-ad QA, including Hint/Skip. Release builds cannot opt into test units through Dart defines.
- No publishing, upload or deployment was performed. No product decision is required by the implementation; native-device QA and the iOS build remain release gates.

Implementation reference: https://developers.google.com/admob/flutter/native/platforms

Attribution badge sizing reference: https://support.google.com/admob/answer/6239795?hl=en
