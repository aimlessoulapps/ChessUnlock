import 'package:chessUnlock/services/premium_access_service.dart';
import 'package:chessUnlock/services/revenuecat_client.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/fake_revenuecat.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeRevenueCatClient client;
  late PremiumAccessService service;
  setUp(() {
    SharedPreferences.setMockInitialValues(
        {'premium.enabled': true, 'premium.developerOverride': true});
    client = FakeRevenueCatClient();
    service =
        PremiumAccessService(SharedPreferences.getInstance(), client: client);
  });
  tearDown(() => service.dispose());

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test('subscription management uses RevenueCat then $platform fallback',
        () async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final fallback = platform == TargetPlatform.android
          ? 'https://play.google.com/store/account/subscriptions'
          : 'https://apps.apple.com/account/subscriptions';
      const managed = 'https://example.com/manage';
      client.info =
          customer(premium: true, willRenew: false, managementURL: managed);
      final opened = <String>[];
      expect(
          await service.manageSubscription(openUrl: (uri) async {
            opened.add(uri.toString());
            return true;
          }),
          isTrue);
      expect(opened, [managed]);
      expect(service.isPremium, isTrue);
      opened.clear();
      expect(
          await service.manageSubscription(openUrl: (uri) async {
            opened.add(uri.toString());
            if (uri.toString() == managed) throw Exception('launch failed');
            return true;
          }),
          isTrue);
      expect(opened, [managed, fallback]);
      client.info = customer();
      opened.clear();
      expect(
          await service.manageSubscription(openUrl: (uri) async {
            opened.add(uri.toString());
            return false;
          }),
          isFalse);
      expect(opened, [fallback]);
      expect(service.isPremium, isFalse);
    });
  }

  test('six options, defaults, permissions and saved duration migration',
      () async {
    await service.refreshPremiumStatus();
    final prefs = await SharedPreferences.getInstance();
    expect(service.isPremium, isFalse);
    expect(prefs.containsKey('premium.enabled'), isFalse);
    expect(prefs.containsKey('premium.developerOverride'), isFalse);
    expect(
        PremiumAccessService.unlockMinuteOptions, [15, 30, 45, 60, 120, 180]);
    expect(await service.loadUnlockMinutes(), 15);
    for (final minutes in PremiumAccessService.unlockMinuteOptions) {
      expect(service.canUnlockForMinutes(minutes), minutes <= 60);
    }
    await expectLater(service.saveUnlockMinutes(120), throwsArgumentError);
    for (final entry
        in {0: 15, 29: 15, 59: 45, 75: 60, 105: 60, 165: 60, 999: 60}.entries) {
      await prefs.setInt(
          PremiumAccessService.unlockDurationPrefsKey, entry.key);
      expect(await service.loadUnlockMinutes(), entry.value);
    }
    client.emit(customer(premium: true));
    for (final minutes in PremiumAccessService.unlockMinuteOptions) {
      expect(service.canUnlockForMinutes(minutes), isTrue);
    }
    for (final entry
        in {75: 60, 105: 60, 135: 120, 165: 120, 999: 180}.entries) {
      await prefs.setInt(
          PremiumAccessService.unlockDurationPrefsKey, entry.key);
      expect(await service.loadUnlockMinutes(), entry.value);
    }
    expect(service.canUnlockForMinutes(1440), isFalse);
    expect(PremiumAccessService.formatUnlockMinutes(60), '1 hr');
    expect(PremiumAccessService.formatUnlockMinutes(120), '2 hrs');
    expect(PremiumAccessService.formatUnlockMinutes(180), '3 hrs');
  });

  test('single configuration, real package price, purchase and restore',
      () async {
    await Future.wait([service.refreshPremiumStatus(), service.loadOffering()]);
    await service.refreshPremiumStatus();
    expect(client.configurations, 1);
    expect(client.listeners.length, 1);
    expect(service.monthlyPrice, 'LOCAL 4.99');
    expect(await service.subscribe(), 'Premium is now active.');
    expect(client.purchasedPackage, monthly);
    expect(service.isPremium, isTrue);
    client.emit(customer());
    expect(service.isPremium, isFalse);
    client.restoreInfo = customer(premium: true);
    expect(await service.restorePurchases(), 'Premium purchases restored.');
    expect(service.isPremium, isTrue);
    client.restoreInfo = customer();
    expect(await service.restorePurchases(), contains('No active'));
    expect(service.isPremium, isFalse);
  });

  test('cancellation, pending, errors and missing offering never grant access',
      () async {
    await service.loadOffering();
    for (final code in [
      PurchasesErrorCode.purchaseCancelledError,
      PurchasesErrorCode.paymentPendingError,
      PurchasesErrorCode.storeProblemError
    ]) {
      client.purchaseError = PlatformException(code: code.index.toString());
      final message = await service.subscribe();
      expect(
          message,
          contains(code == PurchasesErrorCode.purchaseCancelledError
              ? 'cancelled'
              : code == PurchasesErrorCode.paymentPendingError
                  ? 'pending'
                  : 'failed'));
      expect(service.isPremium, isFalse);
      expect(service.busy, isFalse);
    }
    client.available = false;
    await service.loadOffering();
    expect(service.monthlyPackage, isNull);
    expect(await service.subscribe(), contains('unavailable'));
    client.offeringError = Exception('offline');
    await service.loadOffering();
    expect(service.storeMessage, contains('connection'));
  });

  test('cancelled renewal retains access, expiry/refund/listener revoke it',
      () async {
    client.info = customer(premium: true, willRenew: false);
    await service.refreshPremiumStatus();
    expect(service.isPremium, isTrue);
    client.refreshError = Exception('offline');
    await service.refreshPremiumStatus();
    expect(service.isPremium, isTrue);
    client.emit(customer());
    expect(service.isPremium, isFalse);
    client.emit(customer(
        premium: true,
        expiry: DateTime.now().subtract(const Duration(seconds: 1))));
    expect(service.isPremium, isFalse);
    client
        .emit(customer(premium: true, verification: VerificationResult.failed));
    expect(service.isPremium, isFalse);
    client.emit(customer(premium: true, store: Store.testStore));
    expect(service.isPremium, isFalse);
    client.emit(customer(
        premium: true,
        requestedAt: DateTime.now().subtract(const Duration(days: 4))));
    expect(service.isPremium, isFalse);
  });

  test('offline startup only grants access from valid SDK CustomerInfo',
      () async {
    client.refreshError = Exception('offline');
    await service.refreshPremiumStatus();
    expect(service.isPremium, isFalse);
    client.refreshError = null;
    client.info = customer(premium: true);
    await service.refreshPremiumStatus();
    expect(service.isPremium, isTrue);
    client.info = customer();
    await service.refreshPremiumStatus();
    expect(service.isPremium, isFalse);
  });

  test('release and debug accept only the correct public platform keys', () {
    expect(
        StoreRevenueCatClient.isValidPublicKey(
            StoreRevenueCatClient.appleKey, TargetPlatform.iOS),
        isTrue);
    expect(
        StoreRevenueCatClient.isValidPublicKey(
            StoreRevenueCatClient.googleKey, TargetPlatform.android),
        isTrue);
    for (final key in [
      '',
      'test_invalid',
      'sk_secret',
      StoreRevenueCatClient.appleKey
    ]) {
      expect(
          StoreRevenueCatClient.isValidPublicKey(key, TargetPlatform.android),
          isFalse);
    }
  });
}
