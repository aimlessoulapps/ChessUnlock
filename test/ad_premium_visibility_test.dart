import 'package:chessUnlock/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets("premium hides banner ad slots", (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ScreenAdHeader(
            title: "Settings",
            active: true,
            adsDisabled: true,
            screenName: "settings",
          ),
        ),
      ),
    );

    expect(find.text("Settings"), findsOneWidget);
    expect(find.byType(BannerAdSlot), findsNothing);
  });

  testWidgets("free mode keeps banner ad slots", (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ScreenAdHeader(
            title: "Settings",
            active: false,
            adsDisabled: false,
            screenName: "settings",
          ),
        ),
      ),
    );

    expect(find.text("Settings"), findsOneWidget);
    expect(find.byType(BannerAdSlot), findsOneWidget);
  });
}
