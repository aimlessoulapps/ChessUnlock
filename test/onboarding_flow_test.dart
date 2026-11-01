import 'package:chessUnlock/ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
        '$platform five onboarding steps retain permission and app selection',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final answers = <String, String>{};
      var permissions = 0;
      var completed = false;
      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => TextButton(
                  onPressed: () async {
                    completed = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                                builder: (_) => OnboardingFlow(
                                      onAnswerSelected: (key, answer) async {
                                        answers[key] = answer;
                                      },
                                      onPermissionContinue: () async {
                                        permissions++;
                                      },
                                    ))) ??
                        false;
                  },
                  child: const Text('Open')))));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();
      for (final source in ['Social media', 'Google/Ai', 'Other']) {
        expect(find.text(source), findsOneWidget);
      }
      for (final removed in ['Meta ads', 'Reddit', 'ChatGPT / AI search']) {
        expect(find.text(removed), findsNothing);
      }
      await tester.tap(find.text('Google/Ai'));
      await tester.pumpAndSettle();
      expect(answers, {'source': 'Google/Ai'});
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Small puzzles, real progress'), findsOneWidget);
      expect(find.text('Which apps distract you the most?'), findsNothing);
      expect(find.text('What is your main goal?'), findsNothing);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(
          find.text(platform == TargetPlatform.iOS
              ? 'Enable Screen Time Permission'
              : 'Enable Usage Access'),
          findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(permissions, 1);
      expect(find.text('Choose apps'), findsOneWidget);
      await tester.tap(find.text('Choose apps'));
      await tester.pumpAndSettle();
      expect(completed, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
