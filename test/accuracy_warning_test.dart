import 'package:chessUnlock/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'accuracy warning updates at 79, 80, 81 and excludes missing stats',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<void> render(double accuracy, {int solved = 100}) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: HomeTab(
            active: false,
            prewarmBanner: false,
            adsDisabled: true,
            lockEnabled: true,
            indefiniteUnlock: false,
            unlockRemaining: Duration.zero,
            lockedPackages: const {},
            lockedSelectionCount: 0,
            lockedSelectionSummaryLines: const [],
            lockedSelectionPreviewRevision: 0,
            difficulty: 'normal',
            solved: false,
            timedUnlockActive: false,
            statSolved: solved,
            statBestRating: 900,
            accuracyPct: accuracy,
            iconsByPkg: const {},
            emergencyUnlockRemaining: 3,
            emergencyUnlockActiveRemaining: Duration.zero,
            emergencyUnlockBusy: false,
            onEmergencyUnlock: () {},
            onEditLockedApps: () {},
            showNativeSelectionPreview: false,
            onBreakTime: () {},
            onSolveMorePuzzles: () {},
            onOpenDifficulty: () {},
          ),
        ),
      ));
    }

    for (final accuracy in [
      79.0,
      80.0,
      81.0,
      79.0,
      double.nan,
      double.infinity
    ]) {
      await render(accuracy);
      final warning = accuracy.isFinite && accuracy < 80;
      expect(find.byKey(const ValueKey('accuracyWarningDot')),
          warning ? findsOneWidget : findsNothing);
      final text = tester.widget<Text>(
          find.text('${accuracy.isFinite ? accuracy.round() : 0}%'));
      expect(text.style?.color, warning ? Colors.red : isNot(Colors.red));
    }
    await render(0, solved: 0);
    expect(find.byKey(const ValueKey('accuracyWarningDot')), findsNothing);
  });
}
