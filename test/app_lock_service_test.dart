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
