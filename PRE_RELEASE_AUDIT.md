# ChessUnlock final pre-release audit

Audit date: 5 November 2026. Scope: Flutter app/services and local chess-board package, Android watcher/overlay/bridges/boot behavior, iOS Screen Time bridge and extensions, subscriptions, ads, persistence, tests and release configuration. This is a source audit and local validation, not device/store certification.

## Release assessment

The 45-minute Free puzzle-break limit is implemented. Do not treat the update as fully release-cleared until the outstanding store/UI checks and signed/device verification below are complete.

Per the owner's explicit clarification, **Settings → Turn off for 24 hours / indefinitely remains available to everyone**. These are explicit manual pauses, separate from the six puzzle-break durations. Existing running deadlines and existing indefinite pauses remain intact. The limit is not intended to make this voluntary blocking app tamper-proof against Settings pauses, permission revocation, force-stop, data deletion or a modified/rooted device.

## CRITICAL

- **Confirmed local release blocker — Android upload signing unavailable.** `flutter build appbundle --release` stops because `android/key.properties` is missing. Restore the existing upload-key configuration through the normal secure process. No replacement key was created and no release-signing safeguard was bypassed. This is an environment prerequisite, not a regression from the duration change.
- **Confirmed omission; store-review risk — subscription terms.** `lib/ui.dart`, `PaywallScreen`, displays monthly price, benefits, cancellation and restore, but no Terms of Use or Privacy Policy links. Settings has a privacy-policy link; no Terms of Use entry was found. Supply the approved terms URL and verify app/store metadata before submitting subscriptions. Adding terms or changing this UI was deferred because it requires an approved legal destination and changes the existing design. [Apple subscription guidance](https://developer.apple.com/app-store/subscriptions/).
- **Not verified — distribution signing and store configuration.** Production-looking platform public RevenueCat keys, entitlement `premium`, app identifiers and Firebase identities were preserved. Prefix checks and local tests cannot establish dashboard ownership, live offering/product mapping, Family Controls distribution approval or provisioning for Runner and both extensions. Existing user-reported purchase tests were not repeated on a store/device in this audit.

## HIGH

- **Confirmed code limitation; device reproduction pending — Android watcher restart detection.** `ForegroundAppWatcherService.getForegroundPackage()` initially looks back only ten seconds and otherwise relies on an in-memory package. Restarting the service while the same blocked app has already been foreground longer than that can leave no package to block until another activity transition. Recommended: reconstruct initial foreground state from a bounded wider history, then test lock screen, launcher, split-screen and OEM behavior before changing detection semantics.
- **Confirmed missing integration; impact depends on audience/configuration — ad consent.** Banner and rewarded requests use `AdRequest()` without an app-level UMP consent refresh or `canRequestAds()` gate. Review AdMob privacy-message configuration and supported regions; add a shared consent gate and required privacy-options entry point as a separately reviewed UI change. This audit does not determine legal compliance. [Google Flutter UMP guidance](https://developers.google.com/admob/flutter/privacy).
- **Confirmed timing dependency — wall-clock changes.** Unlock deadlines and entitlement validity use wall-clock time; emergency quotas use the local calendar date. Manual clock/timezone changes can alter remaining time or reset quota dates. A monotonic deadline anchor plus a defined reboot/time-change policy needs a broader persistence/native design and device testing.
- **Possible race — overlapping lifecycle/native synchronization.** `_ensureAppLockReadyIfNeeded()` can be started by resume, entitlement changes and emergency usage notifications. Its asynchronous permission/selection checks can overlap an unlock/relock. Puzzle loading likewise has no request-generation guard against an older request completing after a difficulty change. Recommend serialized/versioned lock operations and generation-tagged puzzle loads with controlled delayed-response tests. No observed device failure is claimed.
- **Confirmed error-path limitations — failed manual pause / emergency grant.** `_unlockFor24h()` does not share the ordinary-break rollback path if the final native call throws. Emergency quota is reserved before scheduling, and an iOS scheduling failure can consume a use without granting a break. Recommend a shared grant/rollback transaction, preserving quota concurrency protection; deferred rather than restructuring the working lock flow.
- **Device validation required — short iOS relocking.** The existing one-minute emergency/resume path backdates the DeviceActivity schedule start to meet its minimum interval without extending the end. The source preserves the real deadline, but background/terminated callback delivery must be validated on supported iOS versions. Apple documents a fifteen-minute minimum monitoring interval; this is not proof the existing workaround fails. [Apple monitoring interval documentation](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/monitoringerror/intervaltooshort).

## LOW

- iOS shield says “Open ChessUnlock”, but this repository contains a ShieldConfiguration extension and no ShieldAction extension/launch handling. Verify actual button behavior; adjust wording or implement a supported interaction separately.
- Self-management uses individual Family Controls authorization on iOS 16+, but the iOS 15.2–15.x fallback requests child authorization. Validate the older-OS onboarding promise against intended users.
- Some ad/puzzle/unlock diagnostic logging still runs in release; Screen Time bridge/monitor debug logging was gated in this patch. Review remaining response diagnostics and the final archive privacy report, including direct native UserDefaults usage.
- Duplicate iOS Firebase plist resources contain matching project/app identities. Cleanup is optional, not a release fix.
- Four pre-existing analyzer infos remain: three `prefer_collection_literals` notices and the package-name style notice. Package identity was not renamed. Native dependency/deprecation warnings were not addressed with upgrades.
- Offline fallback can reuse a cached puzzle; repeated solves may contribute to statistics. Long retry backoff, especially HTTP 429, can leave first-load UI waiting. These existing product behaviors were not redesigned.

## FIXED

| Files | Change |
| --- | --- |
| `lib/services/premium_access_service.dart` | Free maximum 60 → 45; all six options unchanged; normalization migrates saved 60/120/180 Free choices; save permission checked after awaiting preferences. |
| `lib/main.dart` | Normalize saved selection after resolved startup/resume entitlement and entitlement transitions; actual unlock rechecks RevenueCat and opens existing paywall for newly disallowed durations; guard concurrent ordinary unlock grants; preserve active deadlines; explicitly identify the unchanged Settings pause path; correct chess move success check. |
| `lib/services/app_lock/app_lock_service.dart` | Include entitlement expiry and explicit Settings-pause marker in native snapshots; propagate Android state-sync failures for rollback; suppress Screen Time diagnostic output outside debug. |
| `android/app/src/main/kotlin/com/aimlessoul/chessunlock/MainActivity.kt`, `android/app/src/main/kotlin/com/aimlessoul/chessunlock/PrefBridge.kt` | Reject new over-limit Free break state at the native boundary; retain existing absolute deadlines, verified Premium and explicit Settings pauses; return validation errors through the method channel. |
| `ios/Runner/ScreenTimeBridge.swift` | Native Free-limit validation with the same preservation rules; persist entitlement expiry for the native unlock call; expired/zero timed unlock requests relock instead of clearing shields; gate bridge debug logging. |
| `ios/DeviceActivityMonitorExtension/DeviceActivityMonitorExtension.swift` | Gate monitor debug logging. No schedule/expiry changes. |
| `lib/services/puzzle_queue_service.dart` | Respect `chess.move()` returning `false`; validate saved/network FEN and the complete legal solution; reject malformed puzzles instead of admitting an unusable board. |
| `android/app/build.gradle.kts` | Permit debug configuration without an upload signing key (`findByName`); existing mandatory release-key checks remain. |
| `ios/Runner.xcodeproj/project.pbxproj` | Both extensions inherit generated Flutter build name/number in Debug, Release and Profile instead of hardcoded `1.0 (1)`. Runner version and identifiers unchanged; pre-existing project edits preserved. |

No dependency upgrades, RevenueCat key/product changes, UI layout changes or additional Premium benefits were introduced. The wheel, six choices, animation, Start-only gating and ad-slot layout code remain unchanged.

Tests added/updated: `test/premium_access_service_test.dart`, `test/unlock_flow_test.dart`, new `test/app_lock_service_test.dart`, new `test/puzzle_queue_service_test.dart`. Coverage includes all Free/Premium durations, migration, entitlement loss while selecting and during unlock refresh, deadline preservation through downgrade/resume, unchanged free Settings pauses, native payload/error propagation, invalid cached solutions, network position selection and nonretryable network failure. Existing tests cover purchase/restore/cancel/pending/error, management URLs, ad-slot geometry on small/large screens, onboarding, accuracy warnings and emergency quotas.

## VALIDATION

- Baseline `flutter test`: **53 passed**.
- Updated `flutter test`: **73 passed** (20 additional tests). Native channels/stores/ad SDK behavior are mocked in these tests; this is not native device execution.
- Baseline and final `flutter analyze`: **0 errors, 0 warnings, 4 pre-existing infos**. CLI exits nonzero for the infos; no new analyzer issue.
- `git diff --check`: passed.
- Xcode project plist syntax: passed (`plutil -lint`).
- Android release AAB: **blocked by missing `android/key.properties`**, before compilation.
- Android debug: **passed**, `JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' ./gradlew assembleDebug`; 289 tasks, 4m21s. Kotlin/native app compilation completed. APK: `build/app/outputs/flutter-apk/app-debug.apk`.
- iOS unsigned release: **passed**, `flutter build ios --release --no-codesign`; final rebuild 78.5s, 44.9 MB. Runner and both embedded extensions were inspected and all report **1.0.12 (13)**. Output: `build/ios/iphoneos/Runner.app`. No signing/export/upload was attempted.
- The extension-version mismatch was confirmed in the first compiled app and corrected in the final build. All six extension configurations inherit Flutter version values.
- Validation logs: `/tmp/chessunlock-baseline-tests.log`, `/tmp/chessunlock-final-tests.log`, `/tmp/chessunlock-final-analyze.log`, `/tmp/chessunlock-android-build.log`, `/tmp/chessunlock-android-debug-build.log`, `/tmp/chessunlock-ios-final-build.log`.

## MANUAL TESTS before release

1. Upgrade an installed Free account with saved 60 minutes: next selection is 45. Repeat while an old 60-minute break is active: its original deadline remains unchanged. Restart during it.
2. Free: 15/30/45 start successfully; scrolling through 60/120/180 never opens paywall; Start on each opens the existing paywall without granting time. Premium: all six work. Repeat expiry/refund while picker is open and just before Start.
3. Confirm both Settings lock-off choices remain usable for Free and Premium, and manual relock works.
4. Android: actual 45-minute and one-minute expiry while backgrounded, screen locked and app process killed; reboot before expiry; service restart while staying inside a blocked app; permission revocation/regrant; battery restrictions/OEM behavior; split screen; overlay opens the puzzle; quota shared between overlay and Home.
5. iOS: shielding apps/categories/websites, actual expiry while app is backgrounded/terminated and phone is locked, resume near expiry, one-minute emergency relock, scheduling failure, authorization removal/regrant, and shield-button behavior. Check distribution Family Controls entitlement and App Group on archive and extensions.
6. Store builds: purchase, restore, cancel-but-still-paid, pending purchase, refund, renewal, billing grace/hold, expiry, offline restart and offline-cache boundary; localized monthly price and both Manage Subscription destinations. Confirm no ad requests for Premium in actual SDK logs/network instrumentation. RevenueCat documents cached CustomerInfo and an offline grace window; cache refresh is not a synchronous fresh-network guarantee. [RevenueCat caching](https://www.revenuecat.com/docs/test-and-launch/debugging/caching).
7. Emergency limits: 1 Free / 3 Premium across overlay/Home, restart, midnight, downgrade and native scheduling errors. Test clock/timezone changes explicitly.
8. UI: small phone, large phone/tablet, landscape, large accessibility text and purchase-sheet return; Home/Puzzle/Settings banner alignment; no-fill/offline ads; Hint/Skip; promotion/castling/en-passant and multi-move puzzles; repeated network retry and rapid difficulty changes.
9. Final signed archive/AAB: approved upload identity, unique version/build number versus both stores, privacy/terms links and subscription disclosures, AdMob consent, privacy manifests/store privacy declarations, Firebase Crashlytics symbols. No physical-device, signed-store, upload or review validation was performed here.
