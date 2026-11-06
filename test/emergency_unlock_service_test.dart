import 'package:chessUnlock/services/emergency_unlock_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'shared daily quota survives restart and plan changes, resets at midnight',
      () async {
    SharedPreferences.setMockInitialValues({});
    var premium = false;
    var now = DateTime(2026, 11, 1, 23, 59);
    EmergencyUnlockService create() =>
        EmergencyUnlockService(SharedPreferences.getInstance(),
            isPremium: () => premium, now: () => now);
    final service = create();
    addTearDown(service.dispose);
    await service.refreshUsage();
    expect(service.remainingToday, 1);
    expect(await service.recordUseIfAvailable(), isTrue);
    expect(await service.recordUseIfAvailable(), isFalse);
    premium = true;
    expect(service.remainingToday, 2);
    final restarted = create();
    addTearDown(restarted.dispose);
    await restarted.refreshUsage();
    expect(restarted.usedToday, 1);
    expect(await restarted.recordUseIfAvailable(), isTrue);
    premium = false;
    await restarted.refreshUsage();
    expect(restarted.usedToday, 2);
    expect(restarted.remainingToday, 0);
    premium = true;
    expect(restarted.remainingToday, 1);
    expect(await restarted.recordUseIfAvailable(), isTrue);
    expect(await restarted.recordUseIfAvailable(), isFalse);
    now = DateTime(2026, 11, 2);
    await restarted.refreshUsage();
    expect(restarted.usedToday, 0);
    expect(restarted.remainingToday, 3);
    premium = false;
    expect(restarted.remainingToday, 1);
    final results = await Future.wait(
        [restarted.recordUseIfAvailable(), restarted.recordUseIfAvailable()]);
    expect(results.where((value) => value).length, 1);
  });
  test(
      'failed iOS reservation refunds once and committed use cannot be refunded',
      () async {
    SharedPreferences.setMockInitialValues({});
    final service = EmergencyUnlockService(SharedPreferences.getInstance(),
        isPremium: () => false);
    addTearDown(service.dispose);
    expect(await service.recordUseIfAvailable(refundable: true), isTrue);
    expect(service.remainingToday, 0);
    expect(await service.recordUseIfAvailable(refundable: true), isFalse);
    await service.refundFailedUse();
    await service.refundFailedUse();
    expect(service.remainingToday, 1);
    expect(await service.recordUseIfAvailable(refundable: true), isTrue);
    service.completeUse();
    await service.refundFailedUse();
    expect(service.remainingToday, 0);
  });

  test('refund does not erase another use or a new day', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var now = DateTime(2026, 11, 5, 23, 59);
    final service = EmergencyUnlockService(Future.value(prefs),
        isPremium: () => true, now: () => now);
    addTearDown(service.dispose);
    await service.recordUseIfAvailable(refundable: true);
    await prefs.setInt(EmergencyUnlockService.countPrefsKey, 2);
    await service.refundFailedUse();
    expect(service.usedToday, 2);
    await service.recordUseIfAvailable(refundable: true);
    now = DateTime(2026, 11, 6);
    await service.refundFailedUse();
    expect(service.usedToday, 0);
  });
}
