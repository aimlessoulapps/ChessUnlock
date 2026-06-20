import 'package:chessUnlock/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets("paywall shows premium copy and placeholder actions",
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PaywallScreen(
          isPremium: false,
          developerPremiumOverride: false,
        ),
      ),
    );

    expect(find.text("ChessUnlock Premium"), findsOneWidget);
    expect(find.text("More control. No ads. Longer unlocks."), findsOneWidget);
    expect(find.text("Unlock apps for up to 30 minutes"), findsOneWidget);
    expect(find.text("Emergency 1-minute unlock"), findsOneWidget);
    expect(find.text("No ads"), findsOneWidget);
    expect(
      find.text("Hint and skip without ads, with a short 30-second wait"),
      findsOneWidget,
    );
    expect(find.text("Support ChessUnlock development"), findsOneWidget);
    expect(find.text("Monthly subscription. Cancel anytime."), findsOneWidget);
    expect(find.text("Continue / Subscribe Monthly"), findsOneWidget);
    expect(find.text("Restore Purchase"), findsOneWidget);
    expect(find.text("Not now"), findsOneWidget);

    await tester.ensureVisible(find.text("Continue / Subscribe Monthly"));
    await tester.tap(find.text("Continue / Subscribe Monthly"));
    await tester.pump();
    expect(find.text("Subscription setup coming soon"), findsOneWidget);
  });
}
