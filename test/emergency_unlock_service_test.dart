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
}
