import 'package:chessUnlock/services/premium_access_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
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
