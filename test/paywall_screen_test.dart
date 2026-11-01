import 'package:chessUnlock/services/premium_access_service.dart';
import 'package:chessUnlock/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/fake_revenuecat.dart';

void main() {
  testWidgets(
      'paywall preserves benefits, shows store price and purchases/restores',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final client = FakeRevenueCatClient();
    final access =
        PremiumAccessService(SharedPreferences.getInstance(), client: client);
    await access.loadOffering();
    await tester.pumpWidget(MaterialApp(home: PaywallScreen(access: access)));
    expect(find.text('ChessUnlock Premium'), findsOneWidget);
    expect(find.text('Unlock apps for up to 180 minutes'), findsOneWidget);
    expect(find.text('3 emergency 1-minute unlocks per day'), findsOneWidget);
    expect(find.text('LOCAL 4.99 / month'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
    await tester.ensureVisible(find.text('Continue / Subscribe Monthly'));
    await tester.tap(find.text('Continue / Subscribe Monthly'));
    await tester.pumpAndSettle();
    expect(access.isPremium, isTrue);
    expect(client.purchases, 1);
    expect(find.text('Premium active'), findsOneWidget);
    await tester.ensureVisible(find.text('Restore Purchases'));
    await tester.tap(find.text('Restore Purchases'));
    await tester.pumpAndSettle();
    expect(client.restores, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    access.dispose();
  });
}
