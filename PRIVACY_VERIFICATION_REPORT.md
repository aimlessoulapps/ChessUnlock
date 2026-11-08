# ChessUnlock privacy verification report

Reviewed: **November 9, 2026 (Asia/Calcutta)**. Project: `C:\Users\sawan\ChessUnlock`. Root app version: **1.0.12+13**.

## Outcome and publication status

`privacy_policy_updated.html` is a complete HTML policy ready for review, with the published page's design preserved. **It is not cleared for publication as a final internationally compliant notice.** It accurately discloses known limitations rather than claiming controls that do not exist. A privacy policy cannot remedy missing implementation or business procedures.

The developer confirmed during this review that the intended minimum age can be **3+**, and answered **no** to having configured Firebase retention/deletion procedures and regional EEA/UK and US-state UMP messages. These are developer statements, not independently inspected console settings. They materially change the earlier policy's children's-privacy and consent claims. The HTML explicitly reflects them. A content age rating is not a privacy-consent age or evidence of children's compliance.

Publication prerequisites:

1. Resolve the intended child-inclusive audience and its implications for data collection, advertisements, parental notices/consent, retention, and store declarations. Current source has no age screening, child mode, or verifiable parental consent for SDK processing.
2. Configure and verify the applicable AdMob privacy messages for both app IDs. A UMP integration alone does not establish that legally required messages are published or effective.
3. Establish an appropriate legal basis for each processing purpose, including startup analytics and diagnostics; assess regional consent requirements and actual behavior before consent.
4. Establish retention settings and workable access/deletion procedures, including how to locate pseudonymous SDK records. Confirm support-mail retention and transaction-record handling.
5. Confirm controller identity/contact details beyond the supplied developer name if required, applicable representatives/grievance contacts, service agreements, transfer safeguards, and jurisdiction-specific notice obligations. These cannot be inferred from code.

The task authorized documentation only. No app changes, dependency changes, commits, publishing, or fixes were performed. The policy is not a claim that the app is lawful for ages 3+, that all UMP choices work in production, or that all regional notice requirements have been satisfied.

## 1. Scope, evidence, and limits

Reviewed root `lib/` services and their UI/call sites; Android main manifest, build configuration and native Kotlin app-locking/telemetry code; iOS Runner configuration, ScreenTime bridge, both extensions and entitlements; dependency lockfiles, installed plugin source where relevant, existing Android generated metadata, and existing consent tests. Searches covered collection controls, identifiers, network requests, permissions, storage, tracking, and age-related configuration. The local `advanced_chess_board` library has no network or analytics calls found in its Dart library sources.

The nested `ChessUnlock/` directory contains a different app snapshot (`name: chesslock`, version 1.0.7+8, no RevenueCat dependency in its pubspec). The root project is the reviewed product: root Android Gradle points Flutter at `../..`, root pubspec points at root `packages/advanced_chess_board`, and root package configuration resolves current plugins. Nested copies and package examples are not treated as active root mobile app behavior. Confirm that the shipped builds actually originate from this root project.

Evidence categories used below:

- **Code-confirmed:** source invokes a function, stores a value, or declares a capability. This does not prove successful delivery of every event.
- **SDK-documented:** official provider documentation describes collection/defaults. Actual runtime behavior can depend on platform, consent, versions, and console settings.
- **Developer-confirmed:** statements supplied in this conversation; console was not accessed.
- **Unverified:** deployed binary behavior, network payloads, dashboard settings, operational processes, or legal applicability not independently observed.

No build or Flutter test was run: those tools can update generated/dependency files. Existing tests were read, not reported as newly passing. No on-device consent exercise, traffic capture, console inspection, receipt validation, deletion exercise, or App Store archive review occurred.

### Dependency evidence

| Component | Root resolved/configured version | Evidence / qualification |
|---|---|---|
| Firebase Core | 4.9.0 | `pubspec.lock`, `.dart_tool/package_config.json` |
| Firebase Analytics | 12.4.1 | Same; Android native Analytics 23.2.0 in existing release dependency report |
| Firebase Crashlytics | 5.2.2 | Same; Android native Crashlytics 20.0.6 in existing report |
| Google Mobile Ads Flutter | 8.0.0 | Same; installed plugin Android Gradle requests Ads 25.1.0 and UMP 4.0.0; existing Android release report agrees |
| RevenueCat Flutter | 10.4.0 | Same; installed plugin requests hybrid common 18.18.0; existing Android report lists Purchases 10.11.0 |
| Shared Preferences | 2.5.4 | `pubspec.lock` |
| Android Firebase BoM | 34.13.0 | `android/app/build.gradle.kts` |
| Existing iOS Swift package pins | Firebase/GoogleAppMeasurement 12.15.0; Ads 13.12.0; UMP 3.1.0; Purchases 5.80.0; hybrid common 18.18.0 | `ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved` and Xcode-project counterpart; pins are not proof of shipped linkage |

Existing Android dependency evidence: `android/app/build/intermediates/incremental/lintVitalAnalyzeRelease/release-artifact-dependencies.xml`. Existing merged manifest: `android/app/build/intermediates/merged_manifests/release/processReleaseManifest/AndroidManifest.xml`. These can be stale; no fresh build was made. `.flutter-plugins-dependencies` reports iOS Swift Package Manager disabled, while existing Swift package pins are present. The installed Ads podspec requests `Google-Mobile-Ads-SDK ~> 13.2.0`; the Swift pins alone must not be treated as a resolved CocoaPods/shipped version. No root `ios/Podfile.lock` was found in the file inventory.

Installed plugin files read under `C:/Users/sawan/AppData/Local/Pub/Cache/hosted/pub.dev/`: `google_mobile_ads-8.0.0/lib/src/ump/consent_form.dart`, its Android Gradle and iOS podspec, and `purchases_flutter-10.4.0` Gradle/podspec. Google's current Android Ads disclosure describes 25.5.0, newer than the observed 25.1.0. Its iOS disclosure describes 13.12.0. Current documentation is guidance, not version-specific runtime verification.

## 2. Data inventory: purposes, destinations, and evidence

| Data | Purpose and recipient | Evidence and finding |
|---|---|---|
| Android launchable-app package names, labels and icons | Local picker, selection display and overlays | `MainActivity.kt:getLaunchableApps/getLaunchableAppIcons`; `lib/main.dart:_loadLockedAppIconCache` and icon-cache writes; `app_lock_service.dart`. No upload of inventory/icons found. |
| Selected package names, lock status, unlock deadlines, pause state | Local app restriction and resumption | `lock_state_controller.dart`; `PrefBridge.kt:saveWatcherState`; `MainActivity.kt`; `BootReceiver.kt`. Some watcher state uses `createDeviceProtectedStorageContext()`, available for direct-boot operation. |
| Android usage events, package identifiers and transition times | Determine foreground app locally | `ForegroundAppWatcherService.kt:getForegroundPackage`; `ForegroundAppState.kt:queryStartMs` reads up to 24 hours on startup/recovery, then incremental windows. `UsageAccessUtil.kt` also implements a short event-window helper. No full usage-history upload found. This is broader access than simply receiving a single current-app name. |
| iOS opaque app/category/domain tokens, selection counts, authorization status, unlock timing and Premium validity | Local Screen Time selection/shields/relocking | `ios/Runner/ScreenTimeBridge.swift:saveSelection`, `saveRuntimeState`, `scheduleRelockMonitoring`; selection serialized into both App Group and standard defaults. `DeviceActivityMonitorExtension.swift` reads shared selections and responds to thresholds/schedule endings. `ShieldConfigurationExtension.swift` produces static shield UI. No token upload or content scraping found. [Apple selection-token documentation](https://developer.apple.com/documentation/familycontrols/familyactivityselection). |
| Theme, difficulty, onboarding completion and answers | Local setup/preferences; answers also go to Google Analytics | `lib/main.dart` keys `themeMode`, `puzzleDifficulty`, `onboardingComplete`, `onboardingAnswers.v1`; `_saveOnboardingAnswer`. Do not label all onboarding data local-only. |
| Solved count, best rating, first-try count | Local progress/accuracy display | `stats_repository.dart:load/save`, `lib/main.dart` stats handling. Individual puzzle-start/solve events and difficulty are separately transmitted. No upload of entire statistics database found. |
| Emergency-unlock day/count, package and expiry | Local quota and temporary access | `emergency_unlock_service.dart`; `PrefBridge.kt` emergency-unlock methods. Daily reset is not deletion of all SDK history. |
| Cached puzzles, FEN/solution, ratings/themes, last puzzle and seen IDs | Local play/cache/repetition avoidance | `puzzle_queue_service.dart` keys `queue.*`, `seen.*`, `cache.lastPuzzleJson.*`; default target 10 queued puzzles and seen cap 80 per difficulty. These are cache bounds, not personal-data retention promises. |
| Difficulty, `ChessUnlock/1.0` User-Agent, IP/connection metadata | Lichess puzzle delivery | `puzzle_queue_service.dart:272` `_fetchOnePuzzleFromLichess`, HTTPS GET `/api/puzzle/next?difficulty=...`, `Accept: application/json`. No bearer token, named account, moves, stats, or selected packages in request. Requests may begin at startup and during refill; not purely offline. [Lichess privacy](https://lichess.org/privacy). |
| App interactions, screen names, onboarding free text, counts, settings and ad results | Google/Firebase usage analytics and developer reporting | `analytics_service.dart`; `lib/main.dart` call sites; native `AnalyticsLogger.kt`. Event and parameter details below. |
| App-instance/advertising identifiers, device/app metadata, sessions, approximate geography and supported automatic purchase events | Google Analytics measurement | SDK-documented defaults; no explicit custom user ID/properties or collection/consent control found in app code. [Google Analytics disclosure](https://support.google.com/analytics/answer/11582702). Account-based Google Signals and Ads exports are optional console capabilities, not verified collection here. |
| Fatal Flutter/unhandled errors, stack traces, logs and SDK diagnostics/identifiers | Google Crashlytics diagnosis, developer dashboard | `crashlytics_service.dart`; `lib/main.dart:27–39`; native `CrashlyticsLogger.kt`. App-open, puzzle type/difficulty and overlay breadcrumbs; no explicit Crashlytics user identifier set. SDK can include Analytics breadcrumbs. [Firebase Android disclosure](https://firebase.google.com/docs/android/play-data-disclosure), [Firebase privacy](https://firebase.google.com/support/privacy). |
| Ad/network/device IDs, approximate location from IP, ad views/interactions and diagnostics | Google AdMob and participating providers: ads, measurement and fraud prevention | `ui.dart:BannerAdSlot`, `main.dart:_loadRewardedAd`, `AdRequest()` defaults; Android AD_ID permission; iOS GAD identifier/SKAdNetwork list. [Android Ads disclosure](https://developers.google.com/admob/android/privacy/play-data-disclosure), [iOS Ads disclosure](https://developers.google.com/admob/ios/privacy/data-disclosure). Do not infer GPS collection, every ad partner, or IDFA availability from SDK presence. |
| UMP consent information and SDK-persisted choices | Google consent messaging/eligibility | `ad_consent_service.dart` requests status and forms; default `ConsentRequestParameters()`. Provider network communication occurs before ad eligibility. Precise production request payload and server retention not captured. |
| Generated RevenueCat customer ID, receipts/tokens, product/transaction records, dates, store, entitlement, available renewal/cancellation/refund/billing/restore state | RevenueCat, stores and developer subscription reporting; activation/restoration/access control | `revenuecat_client.dart:configure/customerInfo/purchase/restore`; `premium_access_service.dart:_applyCustomerInfo`. No custom ID, contact attributes, attribution-ID collector or external login set. [RevenueCat customer IDs](https://www.revenuecat.com/docs/customers/user-ids), [CustomerInfo](https://www.revenuecat.com/docs/customers/customer-info). SDK initializes for nonbuyers too through startup status refresh. |
| Payment/account details supplied to the store | Apple/Google payment and recurring billing | App invokes RevenueCat store purchase flow, not a card form. App does not receive full card number/CVV/store password. [Apple privacy](https://www.apple.com/legal/privacy/), [Google privacy](https://policies.google.com/privacy). Store back-office records and notification configuration were not inspected. |
| Email address, message and voluntarily included attachments | Aimlessoul and email providers for support | `lib/main.dart:3613` `_onFeedback` constructs `mailto:` with generic subject/body only; no device logs auto-attached. `feedback_opened` logs the tap, not the email contents. Actual email mailbox retention is unverified. |

All Kotlin references above are under `android/app/src/main/kotlin/com/aimlessoul/chessunlock/`; Dart services are under `lib/services/` unless stated otherwise.

### Analytics event/parameter detail

`lib/services/analytics_service.dart` defines these custom event families (subject to their call sites and SDK delivery/validation):

- Screens: `home_screen_viewed`, `puzzle_screen_viewed`, `settings_screen_viewed`; explicit SDK screen-view calls as well.
- Onboarding: `onboarding_screen_viewed`, `onboarding_started`, `onboarding_completed`, `onboarding_answer_<question>`, `onboarding_choose_apps_button_tapped`, `onboarding_later_button_tapped`.
- Selection: `edit_locked_apps_tapped`, `solve_puzzle_to_unlock_tapped`, `locked_apps_selection_saved`.
- Puzzles: `locked_app_puzzle_started/solved`, `practice_puzzle_started/solved`, `puzzle_solved_popup_shown`, `unlock_apps_button_tapped`, `puzzle_solved_unlock_apps_tapped`, `solve_more_puzzles_tapped`, `puzzle_solved_solve_more_tapped`.
- Unlocks: `unlock_duration_selected`, `unlock_started`, `unlock_expired`.
- Hint and Skip: each has button, dialog, watch-ad, cancel, rewarded-completed and rewarded-failed events; also `puzzle_skipped_after_ad`.
- Settings/support: `puzzle_difficulty_changed`, `lock_status_changed`, `app_lock_paused`, `app_lock_resumed`, `theme_changed`, `privacy_policy_tapped`, `feedback_opened`.
- Native Android: `app_lock_overlay_shown`, `open_chessunlock_from_overlay_tapped`, with `screen_name=AppLockOverlay`.

Developer-specified parameters: `screen_name`, `answer`, `locked_app_count`, `puzzle_type`, `difficulty_name`, `difficulty_rating` (900/1200/1500/1800/2100), `unlock_duration_minutes`, `ad_result`, `lock_enabled`, and `theme_mode`. Explicit screen-view calls also supply `screenClass`. iOS selection-saving passes `result.totalCount`, so the parameter named `locked_app_count` can include categories/domains, not just applications (`lib/main.dart:3586`).

Current onboarding renders only the source question (`ui.dart:_questionKeyForPage`, `_sourceOptions`). The saving function also accepts legacy `distraction`, `goal`, and `strictness` keys; that capability does not establish current UI collection of those answers. “Other” combines a label and typed text. `TextField.onChanged` → `_setSourceOtherAnswer` → `_selectAnswer` → `_saveOnboardingAnswer` → `AppAnalytics.onboardingAnswer` passes updates to the SDK while typing (`ui.dart:687–704, 1073–1077`; `main.dart:799–822`). No app-level redaction or consent gate was found. SDK limits can reject/truncate data; they are not a privacy safeguard or proof nothing was transmitted. [Analytics event limits](https://support.google.com/analytics/answer/9267744).

No custom purchase/paywall/renewal/refund analytics events were found in this event service. Automatic SDK/store purchase measurement and RevenueCat reporting are separate. The policy corrects the old blanket reference to subscription-related analytics interactions accordingly.

### Crash reporting detail

`AppCrashlytics.initializeErrorHandling` installs Flutter fatal-error and platform-dispatcher handlers. The app logs `app_opened`, `puzzle_started type=... difficulty=...`, `puzzle_solved type=... difficulty=...`, and Android `overlay_shown`. Firebase documents crash/device metadata, installation identifiers, and Analytics breadcrumbs. This creates a possible path for onboarding answer data in breadcrumbs; it was not verified in a live crash report. Debug-only Screen Time console output is not evidence of remote logging; `debugLog` uses `#if DEBUG` and `print`.

No explicit opt-in or opt-out, `setUserIdentifier`, custom Crashlytics keys, or remote deletion API was found. A debug crash-test flag exists but is gated by debug mode. No assumption was made that optional Firebase Performance Monitoring, Authentication, Firestore, Cloud Messaging, or Remote Config are used just because Firebase/transitive components exist.

## 3. UMP implementation and privacy-choice access

Code-confirmed flow in `lib/services/ad_consent_service.dart`:

1. `main.dart:38–40` starts one UMP initialization after the first frame. Service caches initialization per process, so repeated calls do not duplicate launch work.
2. Calls `requestConsentInfoUpdate(ConsentRequestParameters())` on Android/iOS.
3. On update success, awaits `ConsentForm.loadAndShowConsentFormIfRequired`.
4. Checks `getPrivacyOptionsRequirementStatus()` and `canRequestAds()`; only initializes Mobile Ads when eligible. On update/form errors it queries UMP state rather than assuming permission. Cached prior-session eligibility can permit ads; eligibility errors close the app's gate.
5. Exposes Settings → Support → **Ad privacy choices** only when UMP returns `required`. `main.dart:3788` supplies the callback; `ui.dart:2417` displays the row. This row is not gated by Premium status.
6. Opening privacy options sets the ad-request flag false and notifies placements; after dismissal it refreshes eligibility. Banner and rewarded listeners dispose cached ads/retries when the flag is false (`ui.dart:_onConsentChanged`, `main.dart:736`). Form failures surface a retry message.
7. Banner/rewarded load callbacks recheck eligibility, and Premium disables placements. However UMP and eligible Mobile Ads initialization do not check Premium status; “ad-free” must not mean no SDK activity.

The installed 8.0.0 plugin's `consent_form.dart` awaits the native operation before invoking its dismissal callback, supporting the service's await usage. `test/ad_consent_service_test.dart` covers launch gating, cached eligibility on failures, privacy form gating, and initialization failure using fakes; `test/ad_premium_visibility_test.dart` addresses Premium visibility. These were inspected, not executed, and fakes cannot prove production consent behavior.

[Google UMP guidance](https://developers.google.com/admob/flutter/privacy) requires message configuration tied to the AdMob app ID as well as client integration. The developer says regional messages are **not configured**. Therefore required choices are **implemented conditionally in code but not verified available in production**. No claim is made that every region receives a form, that all vendors are configured, or that rejection stops all data collection. `canRequestAds()` is not synonymous with personalized-ad consent. Ads use default `AdRequest()`; no app-level forced non-personalized mode, child-directed flag, under-age flag, or max-ad-content rating was found.

## 4. Privacy concerns discovered (no implementation changes)

| Priority | Finding | Evidence and implication |
|---|---|---|
| Publication blocker | Developer-selected 3+ audience with no child-specific data controls | User confirmation; `ui.dart` onboarding asks source only; default UMP/ad requests; no age or parental-consent flow found. Do not claim “we do not knowingly collect children's information.” Analytics, identifiers and ads can operate for children. |
| Publication blocker | Regional UMP messages not configured per developer | Source cannot publish console messages. Review both Android/iOS app IDs and applicable EEA/UK/US messages before representing that required choices are available. |
| High | Unfiltered free text sent to Analytics during onboarding | Call chain above. Users can enter identifying information unintentionally. No evidence of actual personal text received, but the pathway is confirmed. Disclosure alone does not resolve SDK policy or lawful-processing issues. |
| High | Analytics/Crashlytics start independently of UMP | `main.dart:27–40`, native Firebase dependencies, no app calls to Analytics consent/collection controls. Android manifest and iOS Info.plist lack documented collection-disable defaults. No separate Settings toggle. Regional legal assessment and runtime verification needed. |
| High | Retention/deletion operations not established | Developer answer; no in-app deletion feature or SDK deletion calls. Email alone cannot reliably identify SDK records; RevenueCat anonymous ID is not exposed in a support/deletion screen. Do not promise automatic complete deletion after uninstall or a fixed response/deletion deadline. |
| Needs release verification | iOS tracking handling | No ATT request or `NSUserTrackingUsageDescription`; SKAdNetwork entries exist. UMP does not replace ATT. This is not proof of prohibited tracking: determine actual SDK/partner behavior and ensure it does not track without required permission. [Apple privacy/ATT guidance](https://developer.apple.com/app-store/user-privacy-and-data-use/). |
| Needs release verification | iOS configuration and shipped SDK collection | `GoogleService-Info.plist` includes `IS_ANALYTICS_ENABLED=false` and `IS_ADS_ENABLED=false`, but app explicitly includes/invokes Analytics and Ads; these are not a documented substitute for the collection controls in the main Info.plist/API. Multiple Firebase plist resources and dependency-resolution ambiguity exist. Verify production DebugView/traffic rather than treating these flags as proof of no collection. [Firebase collection controls](https://firebase.google.com/docs/analytics/configure-data-collection). |
| Needs operational confirmation | Backups and local storage guarantees | No explicit Android backup exclusions found in main/merged manifest. Device-protected preferences and iOS duplicated/App Group storage exist. Do not promise all local copies are encrypted by the app, excluded from backup, or immediately erased on uninstall. |

Children's assessment: the [FTC COPPA guidance](https://www.ftc.gov/business-guidance/resources/complying-coppa-frequently-asked-questions) explains that child-directed services and third-party identifiers can create obligations; its page notes the 2025 amended Rule should be consulted for current requirements. [Google Ads targeting guidance](https://developers.google.com/admob/flutter/targeting) describes child/under-age controls, but current documentation also includes newer APIs; use the installed-version API when implementing any future change. None were added here. Apple FamilyControls authorization on iOS 15 uses a child-authorization API, while iOS 16+ requests individual authorization (`ScreenTimeBridge.swift:140–150, 565`). That permission is not verifiable parental consent for ad/analytics processing.

## 5. Retention, deletion, legal rights and international processing

**Verified local behavior:** preferences/statistics persist; cache queues and seen IDs are bounded; emergency counters roll daily. No global retention timer or erase-all feature exists. A three-day bound in `premium_access_service.dart:_applyCustomerInfo` is an offline Premium validity bound, not RevenueCat retention or deletion.

**Provider behavior:** Firebase documents a Crashlytics retention process beginning after 90 days for certain crash data/identifiers; this is not a universal deletion deadline for all services, exports or backups. The HTML deliberately makes no fixed period promise. Analytics property's retention, reset-on-activity, exports, Google Signals, linked Ads, and sharing settings were not inspected. RevenueCat and store billing histories are not deleted merely by cancelling or uninstalling. [Firebase retention documentation](https://firebase.google.com/support/privacy), [RevenueCat CustomerInfo](https://www.revenuecat.com/docs/customers/customer-info).

**Developer confirmation:** no configured retention/deletion procedures. This does not mean zero provider defaults, unlimited retention, or that provider-side deletion is impossible. The HTML offers the supplied email as the request channel but states that no documented schedule exists. Establish record-location, verification, provider requests, exceptions, backups, and response handling before promising a working end-to-end deletion process.

**Rights:** HTML uses conditional rights language rather than claiming every law applies. [UK ICO notice guidance](https://ico.org.uk/for-organisations/uk-gdpr-guidance-and-resources/individual-rights/individual-rights/right-to-be-informed/) requires information such as legal basis, retention, recipients and transfer arrangements where applicable. The code cannot establish Aimlessoul's lawful basis or transfer safeguards. These remain publication gaps: no invented consent, contract, legitimate-interest assessment, EU/UK representative, DPO, or SCC execution is claimed.

[California Attorney General guidance](https://oag.ca.gov/privacy/ccpa) distinguishes sale/sharing and applicable consumer rights. The previous categorical “we do not sell” wording is not a verified legal classification of advertising disclosures. Business applicability, actual partners and opt-out signals remain unverified; the HTML avoids a blanket no-sale claim.

[India's MeitY DPDP Rules publication](https://www.meity.gov.in/documents/act-and-policies/digital-personal-data-protection-rules-2025-gDOxUjMtQWa?pageTitle=Digital-Personal-Data-Protection-Rules-2025%3B) and [MeitY 2025–26 annual report](https://www.meity.gov.in/static/uploads/2026/04/46face7d48c8f6a97030f713ad5fdab4.pdf) indicate phased implementation. Do not assume every provision or grievance route is operational on November 9, 2026. The HTML does not invent a universal age-of-consent rule or assert fully effective statutory rights for every Indian user. Confirm applicable commenced provisions for the release date and child-inclusive audience.

Provider policies demonstrate international operations, not Aimlessoul's executed contracts. Do not assert data residency, particular processors, contractual safeguards, compliance certifications, or guaranteed transfer mechanisms without verification.

## 6. Comparison with the existing published policy

Read the full live HTML at [the published policy](https://aimlessoulapps.github.io/chessunlock-legal/) on November 9, 2026. Web-tool retrieval failed initially; a successful read-only HTTPS request retrieved the page. No access to, clone of, or modification to the legal repository was needed. The retrieved page already displayed November 9, 2026. Its white background, system font, 900px centered layout, gray header/summary box, blue links, spacing and responsive viewport are preserved.

| Existing section/claim | Verification and treatment |
|---|---|
| Summary / what app does / Premium | Retained app restriction, puzzles, breaks, progress, stores and RevenueCat. Clarified that SDK activity continues with Premium and no ChessUnlock login is required. |
| No messages/contacts/photos/precise GPS access | Supported by app permission and code review; retained as feature behavior, not a claim of no personal information anywhere. |
| Local app lists, tokens, settings, statistics, onboarding, emergency state and subscriptions | Broadly accurate; expanded cache/direct-boot/App Group details. Corrected implication that onboarding answers remain exclusively local. |
| Exact selected-app lists/tokens not intentionally sent to own servers | No explicit upload found; clarified no locking-feature upload to named services and distinguished selection-count telemetry and backups. |
| Android foreground detection | Accurate purpose but incomplete scope; added usage-event lookback/recovery behavior. |
| iOS tokens/restrictions | Retained; expanded ManagedSettings/DeviceActivity and shared storage; did not equate Screen Time authorization with ad/analytics consent. |
| RevenueCat ID “may” be anonymous | Made precise: no custom ID is supplied, SDK-generated anonymous ID persists. It is pseudonymous/linkable service data, not proof of anonymization. |
| RevenueCat purchases, renewals, cancellations, refunds and restores | Retained as service/store records available through customer/subscription processing. App primarily consumes active entitlement/expiry; it does not implement its own billing or refund endpoint. |
| RevenueCat “diagnostic data” | Narrowed to service technical metadata; official store-disclosure guidance does not classify RevenueCat as collecting device crash diagnostics. Do not conflate it with Crashlytics. |
| Analytics event examples / subscription interactions | Retained actual event families; removed unsupported custom subscription-interaction implication; distinguished possible automatic purchase measurement. Added free text, automatic identifiers and absence of a switch. |
| Crash reports | Retained and expanded logs, identifiers, error content and possible Analytics breadcrumbs. |
| Ads and consent | Retained banner/rewarded functionality; added exact conditional Settings path, UMP eligibility mechanics, Premium initialization caveat and developer-confirmed missing regional configuration. Removed implication that all applicable privacy choices already work. |
| iOS tracking permissions “where applicable” | Replaced with actual absence of ATT request, with IDFA qualification. |
| Android/iOS permissions | Retained purposes; added billing and SDK merged capabilities. Distinguished entitlements/network capability from user prompts. Boot receiver is present, not hypothetical. |
| Lichess “if requests are made” | Confirmed actual GET path, headers, difficulty and local cache. Removed uncertainty about whether a network puzzle service exists. |
| Feedback | Retained optional correspondence; clarified external mail composer, no auto attachments, and separate feedback-open telemetry. |
| Third-party policies and international processing | Kept relevant working links; avoided assuming all advertising recipients are only processors or asserting verified safeguards. |
| “We do not sell personal information ourselves” | Removed blanket classification: ad disclosures can have broader legal meanings than a cash sale, and console/contract details are not verified. |
| Retention/deletion and privacy rights | Retained local-removal and subscription warnings, expanded backup/offloading limitations, no account deletion, identification difficulty and developer-confirmed absence of a schedule. Added conditional objection/portability/withdrawal/complaint and state rights without claiming universal coverage. |
| Children's privacy | Replaced vague “not designed to knowingly collect” language because developer now specifies a child-inclusive 3+ audience while SDK processing is not age-gated. Explicitly records missing protections; not publication clearance. |
| Security, changes, contact and identifiers | Retained measured security limitations, update date, Aimlessoul/email, Android package and iOS bundle ID. No absolute security/compliance claims. |

## 7. Information for future store disclosures

Use the final shipped binary and all active SDK/configuration settings. This is a preparation matrix, **not a completed or certified store form**. “No account” and “local app locking” do not mean “no data collected.”

| Data category | Apple App Privacy preparation | Google Play Data Safety preparation |
|---|---|---|
| SDK/app-instance/device/advertising identifiers | Evaluate Device ID and other identifier categories for Analytics/Ads/Crashlytics; IDFA access not established. Evaluate linked/tracking per SDK and actual use. | Device or other IDs for relevant SDKs. Do not treat generated IDs as outside disclosure. |
| App interactions and ad activity | Product interaction, advertising data and relevant usage categories; analytics and third-party advertising purposes where applicable. | App activity / app interactions; advertising/marketing and analytics, with fraud/security where documented. |
| IP-derived geography | Evaluate coarse location, not precise location merely because IP is processed. | Approximate location where SDK derives it; no GPS permission shown. |
| Crash reports and related metadata | Crash data and applicable performance/other diagnostics; app functionality and analytics purposes as supported. | Crash logs, diagnostics and applicable app-performance data. |
| Purchases and subscription history | RevenueCat says purchase history with app functionality and analytics. Its anonymous-ID guidance permits not-linked only if there is no way to identify the user; assess all actual integrations. | Purchase history is collected, not merely ephemeral. RevenueCat guidance lists functionality and analytics; determine sharing/service-provider exception using actual integrations. |
| Onboarding typed answer | Evaluate other user content/product interaction and any identifying content actually transmitted; cannot certify data is never identifying. | Evaluate other user-generated content and interaction data. Arbitrary text prevents a categorical claim that no personal text can be sent. |
| Optional support email/attachments | Evaluate customer support/contact/user-content categories and Apple's narrowly defined optional-disclosure exception; external mail alone does not settle every answer. | Determine whether the external email interaction is in scope and any applicable exception. Be consistent with support handling. |
| Exact app inventory, Screen Time tokens, local stats | No off-device upload path found for these local records. Separate telemetry counts/actions from selection contents. | On-device-only processing generally differs from off-device collection; evaluate backups and release SDKs before excluding categories. |

Official form guidance: [Firebase iOS](https://firebase.google.com/docs/ios/app-store-data-collection), [Firebase Android](https://firebase.google.com/docs/android/play-data-disclosure), [Google Analytics](https://support.google.com/analytics/answer/11582702), [AdMob iOS](https://developers.google.com/admob/ios/privacy/data-disclosure), [AdMob Android](https://developers.google.com/admob/android/privacy/play-data-disclosure), [RevenueCat Apple](https://www.revenuecat.com/docs/platform-resources/apple-platform-resources/apple-app-privacy), [RevenueCat Google Play](https://www.revenuecat.com/docs/platform-resources/google-platform-resources/google-plays-data-safety).

Additional decisions needed:

- Whether data is linked to identity and whether tracking occurs are separate Apple questions. Do not mark all data unlinked because there is no login, or no tracking solely because ATT is absent.
- The app's `ios/PrivacyInfo.xcprivacy` declares UserDefaults required-reason API use (`CA92.1`, `1C8F.1`); it is not a complete App Privacy declaration. Inspect the archived aggregate SDK manifests.
- For Play, evaluate collected/shared, ephemeral processing, required/optional and each purpose per category. Analytics/Crashlytics have no user switch. Ads may be avoidable through Premium/eligibility, but consent and SDK initialization still occur. Purchase records are required to support transactions; RevenueCat initialization is not limited to buyers.
- Provider-side TLS statements and the HTTPS puzzle endpoint do not alone verify every final-binary flow is encrypted. No traffic test occurred.
- Check actual third-party ad vendors/mediation, Analytics exports/Signals, RevenueCat integrations, store notification connections, and support workflow. No external attribution/mediation SDK integration was found in root app code; console capabilities are not inferred to be enabled.
- Do not claim a verified deletion mechanism, independent security review, child-directed certification, or Families/Kids compliance. Reconcile the intended 3+ audience with both stores' audience and advertising requirements.

## 8. Manual confirmations and remaining policy limitations

Already answered by developer: intended audience 3+; regional messages and Firebase retention/deletion procedures not configured. Outstanding: exact production distribution/build, whether any uninspected console defaults or account-level messages differ, legal controller/contact details, lawful bases, actual advertising recipients and international transfer arrangements, child-audience safeguards, provider retention/exports, support-mail schedule, and workable deletion/identity verification.

The HTML deliberately contains complete public-facing prose about the current limitations, not placeholder instructions. It does **not** invent the missing lawful bases, operational deletion promises or child safeguards. As a result, it should not be described as a complete compliance notice ready for unrestricted international publication. Once those decisions or configurations change, Sections 3.3, 5–8 and relevant store forms will need rechecking. No documentation wording can establish compliance by itself.

## 9. Artifact checks and change boundaries

Both requested filenames were absent before creation. Only `privacy_policy_updated.html` and this report were created. The HTML is self-contained, includes responsive viewport/CSS, uses the requested date/name/email, and contains no scripts, remote fonts, images or tracking resources. Third-party policy links were retrieved successfully during research (Apple's landing page loads its full policy dynamically; RevenueCat redirects its trailing-slash URL).

Initial Git status already showed `M pubspec.lock`. It was not changed by this task. Protected audit file `PRE_RELEASE_AUDIT.md` was not modified. Read-only pre-write SHA-256 values for final comparison:

- `pubspec.lock`: `BCF38E83517E5BE1EFC6D110D10861B1CC225F2C626F3D85171A60714EBBD9CB`
- `PRE_RELEASE_AUDIT.md`: `E6459DF6840A842AC2CF189BE2F3D9F403EF5A9EA7550823A828A8F3D4D94D4D`

No other output files, downloaded page copies, screenshots, test logs or build products were created by this task. No legal repository was modified, and nothing was committed, pushed or published.
