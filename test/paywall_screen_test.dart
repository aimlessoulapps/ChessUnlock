import 'package:chessUnlock/services/premium_access_service.dart';
import 'package:chessUnlock/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/fake_revenuecat.dart';

class _RecordingPremiumAccess extends PremiumAccessService {
  _RecordingPremiumAccess(FakeRevenueCatClient client)
      : super(SharedPreferences.getInstance(), client: client);

  int managementOpens = 0;

  @override
  Future<bool> manageSubscription({Future<bool> Function(Uri)? openUrl}) async {
    managementOpens++;
    return true;
  }
}

void main() {
  testWidgets('paywall exposes privacy policy and handles launch failure',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final access = _RecordingPremiumAccess(FakeRevenueCatClient());
    final urls = <String>[];
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'launch') urls.add(call.arguments['url'] as String);
      return false;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(MaterialApp(home: PaywallScreen(access: access)));
    expect(find.textContaining('Renews automatically'), findsOneWidget);
    await tester.ensureVisible(find.text('Privacy Policy'));
    await tester.tap(find.text('Privacy Policy'));
    await tester.pumpAndSettle();
    expect(urls, ['https://aimlessoulapps.github.io/chessunlock-legal/']);
    expect(find.text("Couldn't open Privacy Policy. Please try again."),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    access.dispose();
  });

  testWidgets(
      'paywall preserves benefits, shows store price and purchases/restores',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final client = FakeRevenueCatClient();
    final access = _RecordingPremiumAccess(client);
    await access.loadOffering();
    await tester.pumpWidget(MaterialApp(home: PaywallScreen(access: access)));
    expect(find.text('ChessUnlock Premium'), findsOneWidget);
    expect(find.text('Unlock apps for up to 180 minutes'), findsOneWidget);
    expect(find.text('3 emergency 1-minute unlocks per day'), findsOneWidget);
    expect(find.text('LOCAL 4.99 / month'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
    expect(find.text('Manage Subscription'), findsNothing);
    final buttonRect = tester.getRect(find.byType(FilledButton));
    await tester.ensureVisible(find.text('Continue / Subscribe Monthly'));
    await tester.tap(find.text('Continue / Subscribe Monthly'));
    await tester.pumpAndSettle();
    expect(access.isPremium, isTrue);
    expect(client.purchases, 1);
    expect(find.text('Premium active'), findsOneWidget);
    expect(find.text('Manage Subscription'), findsOneWidget);
    expect(find.text('Continue / Subscribe Monthly'), findsNothing);
    expect(find.byType(FilledButton), findsOneWidget);
    expect(tester.getRect(find.byType(FilledButton)), buttonRect);
    expect(find.byType(OutlinedButton), findsOneWidget);
    // Management must remain available even when offerings cannot be loaded.
    client.available = false;
    await access.loadOffering();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage Subscription'));
    await tester.pumpAndSettle();
    expect(access.managementOpens, 1);
    expect(client.purchases, 1);
    await tester.ensureVisible(find.text('Restore Purchases'));
    await tester.tap(find.text('Restore Purchases'));
    await tester.pumpAndSettle();
    expect(client.restores, 1);
    client.available = true;
    await access.loadOffering();
    client.emit(customer());
    await tester.pumpAndSettle();
    expect(find.text('Manage Subscription'), findsNothing);
    expect(find.text('Continue / Subscribe Monthly'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
    access.dispose();
  });
}
