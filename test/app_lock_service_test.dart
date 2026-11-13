import 'dart:async';

import 'package:chessUnlock/services/ad_consent_service.dart';
import 'package:chessUnlock/services/app_lock/app_lock_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const snapshot = AppLockStateSnapshot(
    lockedAppIds: {'test.app'},
    lockEnabled: false,
    indefiniteUnlock: false,
    unlockUntilMs: 123,
    premiumActive: true,
    premiumValidUntilMs: 456,
  );

  for (final openPicker in [false, true]) {
    test('iOS Screen Time waits for consent; picker=$openPicker', () async {
      const channel = MethodChannel('test.screen_time.consent');
      final consent = _PendingAdConsent();
      final previous = AdConsentService.instance;
      AdConsentService.instance = consent;
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return {'available': true, 'status': 'approved', 'completed': true};
      });
      addTearDown(() {
        AdConsentService.instance = previous;
        consent.dispose();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      final service = IosScreenTimeAppLockService(channel: channel);
      final pending = openPicker
          ? service.openNativeAppPicker()
          : service.requestInitialPermissionSetup();
      await consent.started.future;
      expect(calls, ['isAvailable']);
      consent.completed.complete();
      await pending;
      expect(calls, contains('requestAuthorization'));
      expect(calls.contains('presentFamilyActivityPicker'), openPicker);
    });
  }

  test('iOS receives verified entitlement expiry with unlock state', () async {
    const channel = MethodChannel('test.screen_time');
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      received = call;
      return {'success': true};
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await IosScreenTimeAppLockService(channel: channel).syncLockState(snapshot);
    expect(received?.arguments['premiumActive'], isTrue);
    expect(received?.arguments['premiumValidUntilMs'], 456);
    expect(received?.arguments['manualLockPause'], isFalse);
  });

  test('Android sync rejection propagates to unlock rollback', () async {
    const channel = MethodChannel('test.android');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getOwnPackageName') return 'own.app';
      throw PlatformException(code: 'unlockDurationNotAllowed');
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await expectLater(
        AndroidAppLockService(channel: channel).syncLockState(snapshot),
        throwsA(isA<PlatformException>()));
  });
  test('Android enforcement failures are surfaced instead of reporting success',
      () async {
    const channel = MethodChannel('test.android.enforcement');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'foregroundServiceNotAllowed');
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final service = AndroidAppLockService(channel: channel);
    for (final action in [
      service.startEnforcement,
      service.hideActiveBlocker,
      service.stopEnforcement
    ]) {
      await expectLater(action(), throwsA(isA<PlatformException>()));
    }
  });
}

class _PendingAdConsent extends AdConsentService {
  final started = Completer<void>();
  final completed = Completer<void>();

  @override
  Future<void> initialize() {
    if (!started.isCompleted) started.complete();
    return completed.future;
  }
}
