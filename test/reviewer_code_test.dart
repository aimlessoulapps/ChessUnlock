import 'package:chessUnlock/services/premium_access_service.dart';
import 'package:chessUnlock/services/emergency_unlock_service.dart';
import 'package:chessUnlock/ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/fake_revenuecat.dart';

const code = '8SNLQP-GDKJLE-686ST2-S494WB';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeRevenueCatClient client;
  late PremiumAccessService access;
  var accessDisposed = false;
  setUp(() async {
    accessDisposed = false;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    client = FakeRevenueCatClient();
    await SharedPreferences.getInstance();
    access =
        PremiumAccessService(SharedPreferences.getInstance(), client: client);
  });
  tearDown(() {
    if (!accessDisposed) access.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  test('invalid code changes neither preferences nor subscription access',
      () async {
    await access.refreshPremiumStatus();
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    expect(await access.redeemCode('incorrect'), contains('Incorrect'));
    expect(access.isPremium, isFalse);
    expect(prefs.getKeys(), keys);
    client.emit(customer(premium: true));
    expect(await access.redeemCode(''), contains('Incorrect'));
    expect(access.isPremium, isTrue);
    expect(access.hasLocalOverride, isFalse);
  });

  test('code works offline, survives restart and disable persists', () async {
    expect(await access.redeemCode(code), contains('Code redeemed'));
    expect(client.configurations, 0); // Redemption never contacts RevenueCat.
    expect(access.canUnlockForMinutes(180), isTrue);
    expect(access.premiumValidUntilMs,
        greaterThan(DateTime.now().millisecondsSinceEpoch));
    final emergency = EmergencyUnlockService(SharedPreferences.getInstance(),
        isPremium: () => access.isPremium);
    expect(emergency.dailyLimit, 3);
    access.dispose();
    client.refreshError = Exception('offline');
    access =
        PremiumAccessService(SharedPreferences.getInstance(), client: client);
    await access.refreshPremiumStatus();
    expect(access.hasLocalOverride, isTrue);
    expect(access.isPremium, isTrue);
    await access.disableLocalOverride();
    expect(access.isPremium, isFalse);
    expect(emergency.dailyLimit, 1);
    expect(access.premiumValidUntilMs, 0);
    access.dispose();
    access =
        PremiumAccessService(SharedPreferences.getInstance(), client: client);
    await access.refreshPremiumStatus();
    expect(access.isPremium, isFalse);
  });

  test('restore reports subscription state; disable preserves paid access',
      () async {
    await access.redeemCode(code);
    expect(await access.restorePurchases(), contains('No active'));
    expect(access.isPremium, isTrue);
    client.restoreInfo = customer(premium: true);
    expect(await access.restorePurchases(), 'Premium purchases restored.');
    await access.disableLocalOverride();
    expect(access.hasLocalOverride, isFalse);
    expect(access.hasSubscriptionPremium, isTrue);
    expect(access.isPremium, isTrue);
    client.emit(customer());
    expect(access.isPremium, isFalse);
    expect(client.restores, 2);
    expect(client.purchases, 0);
  });

  test('subscription revocation does not remove code access', () async {
    await access.refreshPremiumStatus();
    client.emit(customer(premium: true));
    await access.redeemCode(code);
    client.emit(customer());
    expect(access.isPremium, isTrue);
    await access.disableLocalOverride();
    expect(access.isPremium, isFalse);
  });

  testWidgets('Android dialog validates, redeems, hides ads and disables',
      (tester) async {
    access.dispose();
    access =
        PremiumAccessService(SharedPreferences.getInstance(), client: client);
    await access.refreshPremiumStatus();
    await tester.pumpWidget(MaterialApp(
        home: ListenableBuilder(
      listenable: access,
      builder: (context, _) => Column(children: [
        ScreenAdHeader(
            title: 'Test',
            active: false,
            adsDisabled: access.isPremium,
            screenName: 'test'),
        Expanded(child: PaywallScreen(access: access)),
      ]),
    )));
    expect(find.byType(NativeAdSlot), findsOneWidget);
    for (final value in ['wrong', code]) {
      await tester.ensureVisible(find.text('Redeem Code'));
      await tester.tap(find.text('Redeem Code'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), value);
      await tester.tap(find.text('Redeem'));
      await tester.pumpAndSettle();
      if (value == 'wrong') {
        expect(find.text('Incorrect access code. Please try again.'),
            findsOneWidget);
        expect(access.isPremium, isFalse);
      }
    }
    expect(access.isPremium, isTrue);
    expect(find.byType(NativeAdSlot), findsNothing);
    expect(find.text('Premium active (code)'), findsOneWidget);
    await tester.ensureVisible(find.text('Disable code access'));
    await tester.tap(find.text('Disable code access'));
    await tester.pumpAndSettle();
    expect(access.isPremium, isFalse);
    expect(find.byType(NativeAdSlot), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    access.dispose();
    accessDisposed = true;
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('iOS ignores persisted override and has no redemption UI',
      (tester) async {
    await tester.runAsync(() => access.redeemCode(code));
    access.dispose();
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    access =
        PremiumAccessService(SharedPreferences.getInstance(), client: client);
    await access.refreshPremiumStatus();
    expect(await access.redeemCode(code), contains('unavailable'));
    expect(await access.disableLocalOverride(), contains('unavailable'));
    expect(access.isPremium, isFalse);
    await tester.pumpWidget(MaterialApp(home: PaywallScreen(access: access)));
    expect(find.text('Redeem Code'), findsNothing);
    expect(find.text('Disable code access'), findsNothing);
    client.emit(customer(premium: true));
    await tester.pump();
    expect(access.isPremium, isTrue);
    expect(find.text('Manage Subscription'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    access.dispose();
    accessDisposed = true;
    debugDefaultTargetPlatformOverride = null;
  });
}
