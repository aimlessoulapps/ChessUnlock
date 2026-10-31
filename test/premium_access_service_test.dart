import 'package:chessUnlock/services/premium_access_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test("unlock choices enforce access and normalize saved selections",
      () async {
    final prefs = await SharedPreferences.getInstance();
    final service = PremiumAccessService(Future.value(prefs));
    addTearDown(service.dispose);
    await service.refreshPremiumStatus();
    expect(await service.loadUnlockMinutes(), 15);
    expect(PremiumAccessService.unlockMinuteOptions,
        [15, 30, 45, 60, 75, 90, 105, 120, 135, 150, 165, 180]);

    for (final minutes in PremiumAccessService.unlockMinuteOptions) {
      expect(service.canUnlockForMinutes(minutes), minutes <= 60);
    }
    for (final minutes in [-1, 0, 1, 14, 16, 61, 181, 1440]) {
      expect(service.canUnlockForMinutes(minutes), isFalse);
    }
    await service.saveUnlockMinutes(45);
    expect(await service.loadUnlockMinutes(), 45);
    await expectLater(service.saveUnlockMinutes(75), throwsArgumentError);
    expect(await service.loadUnlockMinutes(), 45);

    for (final entry
        in {0: 15, 10: 15, 29: 15, 59: 45, 60: 60, 180: 60}.entries) {
      await prefs.setInt(
          PremiumAccessService.unlockDurationPrefsKey, entry.key);
      expect(await service.loadUnlockMinutes(), entry.value);
      expect(prefs.getInt(PremiumAccessService.unlockDurationPrefsKey),
          entry.value);
    }

    await service.setPremiumEnabled(true);
    for (final minutes in PremiumAccessService.unlockMinuteOptions) {
      expect(service.canUnlockForMinutes(minutes), isTrue);
    }
    await service.saveUnlockMinutes(180);
    final restored = PremiumAccessService(Future.value(prefs));
    addTearDown(restored.dispose);
    await restored.refreshPremiumStatus();
    expect(await restored.loadUnlockMinutes(), 180);
    await prefs.setInt(PremiumAccessService.unlockDurationPrefsKey, 999);
    expect(await restored.loadUnlockMinutes(), 180);
    await restored.setPremiumEnabled(false);
    expect(await restored.loadUnlockMinutes(), 60);
  });

  test("developer premium override persists", () async {
    final prefsFuture = SharedPreferences.getInstance();
    final service = PremiumAccessService(prefsFuture);

    await service.refreshPremiumStatus();
    expect(service.isPremium, isFalse);
    expect(service.developerPremiumOverride, isFalse);

    await service.setDeveloperPremiumOverride(true);
    expect(service.isPremium, isTrue);
    expect(service.developerPremiumOverride, isTrue);

    final restoredService = PremiumAccessService(prefsFuture);
    await restoredService.refreshPremiumStatus();
    expect(restoredService.isPremium, isTrue);
    expect(restoredService.developerPremiumOverride, isTrue);

    await restoredService.setDeveloperPremiumOverride(false);
    expect(restoredService.isPremium, isFalse);
    expect(restoredService.developerPremiumOverride, isFalse);

    final prefs = await prefsFuture;
    expect(
      prefs.getBool(PremiumAccessService.developerOverridePrefsKey),
      isFalse,
    );

    service.dispose();
    restoredService.dispose();
  });
}
