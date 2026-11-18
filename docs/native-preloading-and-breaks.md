# Native preloading, Home layout, and break-duration improvements

## Changes

- `lib/services/native_ad_cache.dart` adds a shell-owned cache for Home, Puzzle and Settings. Once consent/SDK initialization and Premium status permit ads, it requests one native ad per placement, including hidden tabs and Home's offscreen list item. Tab changes detach/reuse the same ad rather than load again.
- `lib/widgets/native_ad_slot.dart` uses the shared cache, with exclusive placement ownership and ad identity keys to prevent duplicate attachments. A standalone slot owns a single-placement cache for isolated usage/tests.
- Native ads refresh after 55 minutes. Resume checks actual age; backgrounding pauses refresh/retry timers without discarding fresh ads. Failed loads retry after one foreground minute. Theme changes replace themed creatives. Premium activation or consent revocation invalidates pending callbacks and removes all cached ads. Disposal occurs after a scheduled detach frame.
- `lib/main.dart` installs the cache scope and opens the existing Premium paywall when a locked wheel row is tapped. The existing Start-button entitlement check remains in place.
- `lib/ui.dart` centers a compact Emergency Unlock button between Locked Apps and Edit. The count remains visible below Locked Apps. The medium native placement remains below the card, within the existing scrollable area; Solve and bottom navigation remain fixed outside it. Small screens can scroll the whole ad into view without overlap or reducing its size.
- `lib/services/premium_access_service.dart` allows 5, 10, 15 and 30 minutes for Free users; 45, 60, 120 and 180 require Premium. The default remains 15 minutes. A saved Free selection of 45 minutes migrates to 30; active unlock timestamps are not changed.
- `android/app/src/main/kotlin/com/aimlessoul/chessunlock/PrefBridge.kt` and `ios/Runner/ScreenTimeBridge.swift` enforce the 30-minute cap for new Free break grants while preserving existing legacy/paid deadlines on reconciliation.

Subscriptions, reviewer access, rewarded ads, practice interstitial rules and manual Settings lock-pause behavior remain intact.

## Tests and checks

- Flutter regression suite: 149 passed, including duration migration, 5/10-minute Free grants, 45-minute paywall taps, Premium options, consent/cache lifecycle, and existing locking/reviewer/subscription/interstitial tests.
- Two additional navigation tests passed on Android/iOS configurations: repeated tabs reuse identical ads, no duplicate attachments/reloads, theme replacement, and Premium disposal.
- Native-layout coverage uses mocked platform views on both platforms, both themes, and 320x568 / 430x932 viewports. Home checks confirm the emergency button is centered and the complete ad can be scrolled above the fixed Solve button.
- Android `:app:testDebugUnitTest`: 18 passed on API 31/35 configurations (6 new break-policy cases and 12 existing watcher cases).
- Android debug APK built successfully: `build/app/outputs/flutter-apk/app-debug.apk`.
- Active-project analysis (`flutter analyze --no-pub lib test`) has no errors or warnings, only three pre-existing collection-style notices in `puzzle_queue_service.dart`.
- `git diff --check` passes.

Test changes: `test/native_ad_cache_test.dart`, `test/native_ad_navigation_test.dart`, `test/native_ad_layout_test.dart`, `test/premium_access_service_test.dart`, `test/unlock_flow_test.dart`, and `android/app/src/test/kotlin/com/aimlessoul/chessunlock/BreakDurationPolicyTest.kt`.

## Remaining release checks

This Windows host cannot compile iOS. Build and run Runner on macOS/Xcode, including a legacy 45-minute session across upgrade/resume. On actual Android and iOS devices, inspect image/video ads, AdChoices and click targets through repeated tab navigation, background/resume, theme changes and Premium activation. Flutter platform-view mocks do not render actual native assets. Debug/profile builds now use test units for native, interstitial, and rewarded ads; release always uses production units regardless of legacy QA flags. Nothing was published, uploaded or deployed.

Cache-expiration guidance: https://developers.google.com/admob/android/native and https://developers.google.com/admob/ios/native
