# Subscription integration and release checks

Implemented in the root Flutter app; the nested `ChessUnlock/` Git checkout is unchanged.

## Changed files

- `lib/services/revenuecat_client.dart`: RevenueCat SDK boundary, supplied Apple/Google public keys, platform validation, one-time configuration, existing anonymous identity retained.
- `lib/services/premium_access_service.dart`: active `premium` entitlement, listener/startup/resume refresh, expiry and offline bounds, real monthly offering/price, purchase/restore handling, legacy manual flags removed, six duration options and migration.
- `lib/services/emergency_unlock_service.dart`: one free/three Premium daily uses, shared persisted counts, serialized reservations and native Android quota reads.
- `lib/main.dart`: service wiring, paywall, runtime duration/difficulty checks, native entitlement expiry sync, emergency access for free users, ad gates.
- `lib/ui.dart`: five-step onboarding with three source choices, read-only Premium status, localized monthly price and working paywall buttons. Existing wheel, sheet and paywall layout retained.
- `lib/services/app_lock/app_lock_service.dart`: forwards the verified entitlement's validity bound to Android.
- Android `MainActivity.kt`, `PrefBridge.kt`, `ForegroundAppWatcherService.kt`: shared quota reservation/read methods, merge persisted usage without resetting on plan changes, expired cached Premium becomes free, daily overlay refresh.
- `ios/Runner.xcodeproj/project.pbxproj`: enables In-App Purchase capability. Application IDs, signing, Screen Time targets and relock implementation unchanged.
- Tests: `premium_access_service_test.dart`, `paywall_screen_test.dart`, `unlock_flow_test.dart`, new `emergency_unlock_service_test.dart`, `onboarding_flow_test.dart`, `support/fake_revenuecat.dart`.

## Configuration

The supplied `appl_` and `goog_` public SDK keys are configured. `purchases_flutter` was already installed at stable 10.4.0 and remains compatible with this project; no unrelated dependency upgrades were made.

The app uses RevenueCat's **current offering**, its **monthly package**, a **P1M** store subscription, and entitlement **premium**. It reads product IDs and localized prices from that offering; no real product ID or price is invented or hardcoded. Optional build override: `--dart-define=REVENUECAT_OFFERING_ID=<your-existing-offering-id>`. Public-key build overrides are `REVENUECAT_APPLE_PUBLIC_KEY` and `REVENUECAT_GOOGLE_PUBLIC_KEY`. Wrong-platform, secret and Test Store keys are rejected in every build mode. Test Store entitlements are rejected too. Apple/Google sandbox purchases using the real store integrations remain supported.

Dashboard configuration could not be inspected here. Verify these existing settings; do not change prices or recreate products:

1. Both public keys belong to the intended RevenueCat project and its corresponding App Store / Play Store apps.
2. Both real monthly store products are attached to entitlement `premium`.
3. The current offering has a monthly package with the correct Apple product and Google subscription/base plan. The products/base plan are active and available to the tester's storefront.
4. App Store Connect agreements, tax/banking, subscription metadata and RevenueCat App Store credentials are complete. Google Play service account/store credentials, billing product, base plan and tester access are complete.
5. Use the appropriate store sandbox/testing accounts with these public keys; do not switch release configuration to RevenueCat Test Store.

There is no existing app login to migrate. RevenueCat retains its generated anonymous identity; Restore Purchases uses the signed-in store account. Cross-platform identity sharing would require a future account feature and was not added.

## Validation

- `flutter pub get`: passed.
- `flutter test`: **40 passed**, including all six durations through Android/iOS method-channel mocks, free restrictions, Premium Hint/Skip countdowns, rewarded dialogs, emergency quota changes and midnight reset, onboarding, purchase/restore/error states, cached entitlement bounds, and resume refresh. Native store transactions and native relock scheduling are mocked in these tests.
- Analysis of all changed Dart files and tests: **No issues found**.
- Repository-wide `flutter analyze`: no new findings from this change. Existing repository findings remain: four errors in the nested Git checkout's `ChessUnlock/test/widget_test.dart` (`package:chesslock` imports and consequent undefined symbols), plus existing informational lints. The active app has three existing collection-literal suggestions in `puzzle_queue_service.dart`; the root package name also has an existing lint.
- Android debug APK: built successfully at `build/app/outputs/flutter-apk/app-debug.apk`.
- Android release bundle: `flutter build appbundle --release` passed using the existing signing configuration. Output: `build/app/outputs/bundle/release/app-release.aab` (48.7 MB). Nothing was published.
- iOS static compatibility: existing Swift Package Manager integration registers PurchasesFlutterPlugin; app deployment target 15.2 exceeds the plugin's iOS 13 minimum. In-App Purchase capability enabled. Native iOS compilation cannot run on this Windows host; `flutter build ios --no-codesign` is unavailable here.
- No real-device purchase, refund, Screen Time relock, or Android overlay testing was performed.

The 60-minute option remains available to free users, following the explicit free limit in the requirements despite the conflicting �1 hr � Premium� label. Restricted choices are 120 and 180 minutes. Removed onboarding survey pages had no persisted page index; existing completion state remains valid and old survey answers do not drive navigation.

RevenueCat owns the CustomerInfo disk cache. The app does not persist a Premium boolean; existing manual flags are deleted. In-memory fallback is bounded by the entitlement expiry and three days from CustomerInfo's request date. A failed fetch cannot create access. Renewal cancellation does not revoke paid access. Refunds are reflected when updated CustomerInfo arrives (startup/resume/listener/periodic refresh), not while the device is disconnected. See [RevenueCat CustomerInfo](https://www.revenuecat.com/docs/customers/customer-info) and [caching behavior](https://www.revenuecat.com/docs/test-and-launch/debugging/caching).

## Manual testing: both platforms

1. Fresh-install or clear app data using a store account without an active subscription. Complete onboarding: Welcome -> source question (only Social media, Google/Ai, Other) -> Small puzzles -> platform permission -> Choose apps. Confirm actual app selection and permissions still work. Upgrade an existing install and confirm completed onboarding stays completed and the app selections/stats remain.
2. Solve a puzzle and open Choose unlock time. Confirm the same vertical wheel, highlight, sizing, buttons and animations with 15, 30, 45, 60, 120, 180 minutes. Free users can start the first four. Scroll across 120/180: no paywall. Press Start: paywall opens. Dismiss: last valid free selection remains and no unlock starts. Check legacy saved values such as 75/105/135/165 migrate downward to an allowed duration within current access.
3. Open Get Premium. Confirm displayed price exactly matches the store sheet's localized recurring monthly price. Cancel checkout: no Premium. Complete checkout: Premium appears immediately, banners/rewarded ads disappear, difficulty selection works, and Hint/Skip each retain the 30-second wait. Dismiss/reopen the paywall and restart the app to verify status persists through RevenueCat.
4. Restore with an active subscription: Premium is restored. Restore without one: show no active subscription, grant nothing. Try offline restore/purchase and unavailable products: clear failure/retry state, no accidental access. For a previously verified unexpired subscriber, restart briefly offline and confirm SDK cached access; a fresh free offline install must remain free.
5. Use accelerated sandbox renewals to cancel auto-renewal: access remains until expiry. Let the entitlement expire, then background/resume: ads/free difficulty/60-minute cap return. Test a sandbox refund/revocation and resume after RevenueCat records it. Test pending payment/Ask to Buy: no access until approval; after approval and an SDK refresh, Premium appears.
6. As free, use one emergency unlock: one minute only, then relock and zero uses left. Restart: still zero. Upgrade after using one: two uses remain. Use more, downgrade/expire: do not erase used count; re-upgrade the same day must not reset it. Cross local midnight: free gets one/Premium three. Try rapid repeated taps and confirm only one reservation. An already-unlocked app must not consume another home emergency use.
7. As Premium, run each 15/30/45/60/120/180-minute duration to its actual expiry. Verify unlock and relock while foregrounded, backgrounded, with the app terminated/restarted, and across local midnight. Check saved expiry is not extended by reopening. Repeat free 60 minutes. Keep the existing one-minute emergency duration.
8. Verify accuracy warning below 80%, puzzle ratings/statistics, Firebase Analytics/Crashlytics, and free rewarded Hint/Skip remain functional. Verify all tabs have no banner for Premium; no interstitial implementation exists in this checkout to modify.

## Android-specific steps

1. Build `flutter build appbundle --release` with the existing upload signing configuration. Upload through your normal internal-testing process (not performed here).
2. Add the Google account as a Play license tester and internal tester, opt in, and install from the Play testing link. Confirm Google Play checkout uses the intended monthly subscription/base plan.
3. For pending payment, use Play's test payment method that delays/declines completion, then the method that approves completion. Check pending never grants Premium and approval does.
4. Grant Usage Access, overlay and notification permissions. Select a distracting app. Verify overlay blocks it, puzzle success unlocks it, and native watcher relocks after each duration, restart and device reboot.
5. Use emergency from the overlay, then open ChessUnlock: home must show the same remaining count. Use home emergency and return to the overlay: counts must agree. Test Premium expiry while only the overlay is running; quota drops to free without resetting usage.

## iOS-specific steps (Mac + physical device)

1. Run `flutter pub get`, then `flutter build ios --no-codesign` on macOS. Open `ios/Runner.xcworkspace`, resolve Swift packages, build Runner and both Screen Time extensions, and run Xcode tests. Use your existing signing and approved Family Controls/App Group capabilities. Do not change bundle IDs or signing teams.
2. Archive/upload through your normal TestFlight process or run a sandbox build on device. Use a sandbox Apple account/TestFlight tester. Keep the real `appl_` public key; disable any local StoreKit fixture when validating RevenueCat's real App Store products.
3. Test subscribe, cancel, restore, accelerated expiration and sandbox revocation; test Ask to Buy/deferred authorization where the Apple test environment permits it.
4. Authorize Screen Time and select apps with FamilyActivityPicker. Confirm ManagedSettings shields and DeviceActivity relock for all six durations while the app is backgrounded/terminated and after restart. Check emergency's existing one-minute scheduling on the oldest supported iOS and current iOS; a scheduling failure must restore shields, not leave an indefinite unlock.
