# Android watcher crash investigation — 13 November 2026

## Finding

The current root Android project (`pubspec.yaml`: **1.0.13+15**, target SDK **36**) was still vulnerable. Before this change, `ForegroundAppWatcherService.onCreate()` called `startForeground()` unconditionally at line 163. The reported line 153 belongs to an older build; the same unsafe lifecycle operation remained present.

Android can accept a service launch request and subsequently refuse its foreground promotion. The boot receiver's `try/catch` surrounded only the launch request, not the later service lifecycle callback. MainActivity also reported success immediately after requesting a start. Consequently, a promotion refusal escaped `onCreate()` and terminated the process. Catching only the caller-side exception was not a fix.

The supplied stack establishes this mechanism but does not identify which broadcast/user action initiated each of the 72 historical events. Attribution of those individual events requires Crashlytics breadcrumbs/device details; no claim is made that all events came from one receiver.

## Complete start/restart trace

| Entry point | Previous behavior / restriction | New behavior |
| --- | --- | --- |
| Flutter `AndroidAppLockService.startEnforcement()` → `startWatcher` method channel → MainActivity | Called by serialized reconciliation during initialization, resume, lock selection/settings changes, unlock/expiry changes, and state refresh callbacks. Async work and the periodic expiry timer can outlive the activity's foreground state. No visibility guard; immediate success before promotion. | A new service is requested only while MainActivity is resumed. An already running watcher is accepted. Otherwise return `watcherUnavailable`; reconciliation on resume or Retry provides recovery. |
| `BootReceiver`: `LOCKED_BOOT_COMPLETED`, `BOOT_COMPLETED`, `MY_PACKAGE_REPLACED` | Direct foreground start when `PrefBridge.shouldRunWatcher` is true. These broadcasts have exemptions; the declared `specialUse` type is not a boot-prohibited type. Exemptions do not justify ignoring runtime refusal. | Preserve direct start, safely handle launch and promotion refusal. |
| `BootReceiver`: `USER_UNLOCKED` | Unconditional foreground start despite this broadcast not providing its own foreground-start exemption. | No new service start. If monitoring is needed and absent, show recovery notification. Normal boot broadcasts still start monitoring. |
| `BootReceiver`: custom `RETRY_START_WATCHER` | Up to three retries using inexact `AlarmManager.set(RTC_WAKEUP)` after 15 seconds. The original boot exemption does not carry over to a later inexact alarm; it is not a user-requested exact-alarm exemption. | Remove alarm scheduling. A legacy alarm already scheduled by an older build can only offer recovery, never restart the service. |
| `hideWatcherOverlay` → `requestHideOverlay()` | Used `startForegroundService` solely to deliver an overlay-hide command, creating/promoting the service if absent. | Operate directly on the live service on the main thread; no-op when absent. No service creation. |
| System `START_STICKY` restart / null intent | Recreated service entered the same unguarded `onCreate()` promotion. Sticky foreground restarts themselves are permitted by Android. | Keep sticky restarts after successful promotion. If promotion fails, stop immediately and return `START_NOT_STICKY` if a start callback arrives. |
| Foreground promotion | One `startForeground()` call, in `onCreate()`. | Same immediate call, guarded against expected lifecycle/security/type failures; polling begins only after success. |
| WorkManager / jobs / other schedulers | No application Worker, WorkManager enqueue, JobService, service PendingIntent, task-removal restart, or additional watcher start site found. WorkManager's initializer exists in the merged dependency manifest, but no watcher work is scheduled. The Flutter expiry timer and receiver alarm are accounted for above. | No WorkManager fallback or new background scheduler added. |

The repository also contains a nested `ChessUnlock` gitlink/check-out. The root `android/app/build.gradle.kts` points Flutter at the root project (`../..`); this investigation and fix target that current project, not the nested copy.

## Refusal and recovery behavior

- Caller-side start and service-side promotion handle `IllegalStateException` (including Android's `ForegroundServiceStartNotAllowedException` and foreground-service-type exceptions), `SecurityException`, and `IllegalArgumentException`. Unexpected runtime bugs are not blanket-swallowed.
- Failed promotion calls `stopSelf()` before any polling or overlay work starts. It never reports running and never requests a sticky restart. An eventual `onStartCommand()` returns failure and `START_NOT_STICKY`.
- MainActivity waits for a `ResultReceiver` acknowledgement of actual promotion. A missing acknowledgement has an eight-second failure timeout that stops the service and offers recovery. Intentional stop invalidates live status and removes monitoring callbacks immediately.
- A separate notification says **App locking is not running** and opens MainActivity directly. There is no background retry loop. Successful startup or intentional stop clears it.
- If notification permission or its channel is disabled, Android may hide that notification. Opening the app reconciles monitoring again; a failed start displays a persistent in-app banner with **Retry**, including when notifications are unavailable. The banner clears after successful startup or intentional disablement.
- Running-service access uses a weak reference and is cleared during shutdown, not a persisted boolean that could survive process death and falsely claim monitoring is active.

Android 15+ does not grant a blanket background-start exemption just because overlay permission is held: a visible overlay is required for that exemption. This fix does not rely on it or manufacture an overlay to bypass restrictions. See [Android background-start restrictions](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start) and [Service sticky-restart documentation](https://developer.android.com/reference/android/app/Service#START_STICKY).

## Functionality and scope

Selected-app persistence, usage-event polling, foreground-app confirmation, overlay contents/actions, chess puzzle requirements, timed relocking, and unlock rules are unchanged. They continue after successful startup. When Android refuses monitoring, app locking is unavailable until recovery succeeds; the app now tells the user rather than crashing or claiming startup succeeded.

No Premium, RevenueCat, AdMob, Firebase, iOS implementation, production dependency version, release version, or production manifest changes were made. The only new dependencies are JUnit and Robolectric for local tests. No upload, publishing, or submission was performed.

## Files changed

- `android/app/src/main/kotlin/com/aimlessoul/chessunlock/ForegroundAppWatcherService.kt`: guarded launch/promotion, acknowledgement, live status, safe shutdown, hide without start.
- `android/app/src/main/kotlin/com/aimlessoul/chessunlock/BootReceiver.kt`: exempt broadcasts only; remove inexact retries.
- `android/app/src/main/kotlin/com/aimlessoul/chessunlock/MainActivity.kt`: resumed-activity gate and actual-start acknowledgement/timeout.
- `android/app/src/main/kotlin/com/aimlessoul/chessunlock/WatcherRecovery.kt`: recovery notification.
- `lib/main.dart`: persistent failure banner and retry/clear behavior.
- `android/app/build.gradle.kts`: test-only dependencies.
- `android/app/src/test/kotlin/com/aimlessoul/chessunlock/WatcherLifecycleTest.kt`: native regression tests.
- `test/unlock_flow_test.dart`: refusal/retry UI regression.
- `ANDROID_WATCHER_CRASH_FIX.md`: this report.

## Validation and release-device checks

- Native regression suite: **12 passing cases** on Robolectric API 31 and 35, including the existing foreground-state transition checks. Tests use an isolated application without the merged third-party receiver manifest; the merged production manifest is covered by the Android build/lint checks.
- `flutter test test/unlock_flow_test.dart test/widget_test.dart`: **51 passed**.
- `flutter analyze lib/main.dart test/unlock_flow_test.dart`: **no issues**.
- Android Kotlin compilation and debug APK assembly: **passed**.
- Android `lintDebug`: **blocked by three pre-existing errors**: unguarded API-26 `AdaptiveIconDrawable` in MainActivity (minimum API 24), and two `PropertyEscape` errors in local SDK/Flutter paths. These lines were not changed. Existing warnings also remain. No new lifecycle errors were reported.
- `git diff --check`: passed.

Before production release, test on physical devices/emulators running Android 12, 14, 15, and 16 (including a restrictive OEM):

1. Enable usage/overlay permissions, select a locked app, background ChessUnlock, confirm the overlay blocks it and solving a puzzle grants the intended break; confirm relocking at expiry.
2. Race Home/Settings/notification-permission UI against startup. Force background launch and foreground-promotion refusal. Confirm no fatal exception, no foreground-start timeout crash, no orphan watcher/polling, and no misleading running notification.
3. Tap the recovery notification / Retry and verify confirmed startup and overlay blocking. Repeat with notification permission denied and channel disabled.
4. Reboot before and after first unlock; update an installed build; verify exempt starts. Deliver an old retry alarm and USER_UNLOCKED while stopped: neither may start a new service.
5. Kill the process to exercise genuine sticky recreation and null intents; separately force-stop/user-stop it and verify recovery only after the user reopens the app. Test rapid stop/start and permission revocation.

Robolectric injects denial at the service boundary; it does not prove device ActivityManager/OEM behavior. No physical-device end-to-end test was performed in this session.
