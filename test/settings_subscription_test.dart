import 'package:chessUnlock/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('settings keeps Premium entry without separate management option',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var purchases = 0;
    for (final premium in [true, false]) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SettingsTab(
        active: false,
        prewarmBanner: false,
        adsDisabled: true,
        lockEnabled: true,
        indefiniteUnlock: false,
        unlockRemaining: Duration.zero,
        isPremium: premium,
        difficulty: 'normal',
        themeMode: AppThemeMode.system,
        onThemeModeChanged: (_) async {},
        onLockToggle: (_) async {},
        onOpenDifficulty: () async {},
        onOpenPremium: () => purchases++,
        onPrivacyPolicy: () async {},
        onFeedback: () async {},
      ))));
      expect(find.text('Premium details'), findsNothing);
      expect(find.text('Rate the app'), findsNothing);
      expect(find.text('Manage Subscription'), findsNothing);
      await tester.tap(find.text(
          premium ? 'ChessUnlock Premium active' : 'Get ChessUnlock Premium'));
    }
    expect(purchases, 2);
  });
}
