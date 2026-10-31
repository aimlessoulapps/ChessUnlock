import 'dart:convert';

import 'package:chessUnlock/main.dart';
import 'package:chessUnlock/services/lock_state_controller.dart';
import 'package:chessUnlock/services/premium_access_service.dart';
import 'package:chessUnlock/services/puzzle_queue_service.dart';
import 'package:chessUnlock/ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const android = MethodChannel('chesslock/system');
  const ios = MethodChannel('chesslock/screen_time');
  final calls = <MethodCall>[];
  var failScheduling = false;

  setUp(() {
    calls.clear();
    failScheduling = false;
    for (final channel in [android, ios]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'getOwnPackageName':
            return 'com.aimlessoul.chessunlock';
          case 'getLaunchableApps':
          case 'getLaunchableAppIcons':
            return <Map<String, Object>>[];
          case 'hasUsageAccess':
          case 'hasOverlayPermission':
          case 'hasNotificationPermission':
            return true;
          case 'consumeOpenPuzzleRequest':
          case 'consumeOpenPaywallRequest':
            return false;
          case 'isAvailable':
            return {'available': true};
          case 'authorizationStatus':
          case 'requestAuthorization':
            return {'status': 'approved'};
          case 'selectionMetadata':
            return {'applicationCount': 1};
          case 'unlockFor':
            if (failScheduling) {
              return {'success': false, 'code': 'relockSchedulingFailed'};
            }
            return {'success': true};
          default:
            return channel == ios ? {'success': true} : null;
        }
      });
    }
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    for (final channel in [android, ios]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  Future<void> pumpFrames(WidgetTester tester, [int count = 8]) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> launch(WidgetTester tester, TargetPlatform platform,
      {bool premium = false, int? savedMinutes}) async {
    debugDefaultTargetPlatformOverride = platform;
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'onboardingComplete': true,
      'premium.enabled': premium,
      'lockedPackages': ['test.locked.app'],
      if (savedMinutes != null)
        PremiumAccessService.unlockDurationPrefsKey: savedMinutes,
      'queue.normal': jsonEncode(List.generate(
          8,
          (i) => {
                'id': 'flow-$i',
                'rating': 900,
                'type': 'Tactics',
                'fen': startingFen,
                'solutionUci': ['e2e4'],
              })),
    });
    await tester.pumpWidget(MaterialApp(
      home: ChessUnlockShell(
        initialTab: 1,
        themeMode: AppThemeMode.system,
        onThemeModeChanged: (_) async {},
      ),
    ));
    await pumpFrames(tester);
  }

  PuzzleTab puzzleTab(WidgetTester tester) =>
      tester.widget<PuzzleTab>(find.byType(PuzzleTab, skipOffstage: false));

  Future<void> openWheel(WidgetTester tester) async {
    expect(puzzleTab(tester).boardController.makeMove(from: 'e2', to: 'e4'),
        isTrue);
    await pumpFrames(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Unlock apps'));
    await pumpFrames(tester);
    final home = tester.widget<HomeTab>(find.byType(HomeTab));
    expect(home.solved, isTrue);
    home.onBreakTime();
    await pumpFrames(tester);
    expect(find.byType(CupertinoPicker), findsOneWidget);
    final wheel = tester.widget<CupertinoPicker>(find.byType(CupertinoPicker));
    expect(wheel.childDelegate.estimatedChildCount, 12);
    expect(wheel.itemExtent, 42);
    expect(wheel.magnification, 1.08);
  }

  Future<void> select(WidgetTester tester, int minutes) async {
    final wheel = tester.widget<CupertinoPicker>(find.byType(CupertinoPicker));
    wheel.scrollController!
        .jumpToItem(PremiumAccessService.unlockMinuteOptions.indexOf(minutes));
    await pumpFrames(tester);
  }

  Future<void> disposeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    debugDefaultTargetPlatformOverride = null;
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
        '$platform free wheel gates only Start and restores free choice',
        (tester) async {
      await launch(tester, platform, savedMinutes: 45);
      await openWheel(tester);
      final wheel =
          tester.widget<CupertinoPicker>(find.byType(CupertinoPicker));
      expect(wheel.scrollController!.selectedItem, 2);
      expect(find.text('Premium unlocks up to 3 hours.'), findsOneWidget);
      await select(tester, 75);
      expect(find.byType(PaywallScreen), findsNothing);
      await tester.tap(find.text('Start'));
      await pumpFrames(tester);
      expect(find.byType(PaywallScreen), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('unlockUntilMs') ?? 0, 0);
      await tester.ensureVisible(find.text('Not now'));
      await tester.tap(find.text('Not now'));
      await pumpFrames(tester);
      expect(wheel.scrollController!.selectedItem, 2);
      expect(prefs.getInt(PremiumAccessService.unlockDurationPrefsKey), 45);
      await select(tester, 60);
      await tester.tap(find.text('Start'));
      await pumpFrames(tester);
      final expiry = prefs.getInt('unlockUntilMs')!;
      expect(expiry - DateTime.now().millisecondsSinceEpoch,
          closeTo(const Duration(minutes: 60).inMilliseconds, 5000));
      expect(prefs.getInt(PremiumAccessService.unlockDurationPrefsKey), 60);
      final syncName = platform == TargetPlatform.android
          ? 'syncWatcherState'
          : 'syncLockState';
      expect(
          calls
              .where((c) => c.method == syncName)
              .any((c) => c.arguments['unlockUntilMs'] == expiry),
          isTrue);
      if (platform == TargetPlatform.android) {
        expect(calls.where((c) => c.method == 'startWatcher'), isNotEmpty);
      } else {
        final unlock = calls.lastWhere((c) => c.method == 'unlockFor');
        expect(unlock.arguments['durationMs'], 60 * 60 * 1000);
        expect(unlock.arguments['unlockUntilMs'], expiry);
      }
      final restored = LockStateController(Future.value(prefs));
      await restored.load();
      expect(restored.isUnlocked, isTrue);
      expect(restored.unlockedUntil!.millisecondsSinceEpoch, expiry);
      await disposeApp(tester);
    });

    testWidgets('$platform premium accepts 180 minutes', (tester) async {
      await launch(tester, platform, premium: true);
      await openWheel(tester);
      final wheel =
          tester.widget<CupertinoPicker>(find.byType(CupertinoPicker));
      expect(wheel.scrollController!.selectedItem, 0);
      await select(tester, 180);
      await tester.tap(find.text('Start'));
      await pumpFrames(tester);
      expect(find.byType(PaywallScreen), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(PremiumAccessService.unlockDurationPrefsKey), 180);
      expect(
          prefs.getInt('unlockUntilMs')! -
              DateTime.now().millisecondsSinceEpoch,
          closeTo(const Duration(minutes: 180).inMilliseconds, 5000));
      if (platform == TargetPlatform.iOS) {
        final unlock = calls.lastWhere((c) => c.method == 'unlockFor');
        expect(unlock.arguments['durationMs'], 180 * 60 * 1000);
      }
      await disposeApp(tester);
    });

    testWidgets('$platform free Hint and Skip retain rewarded dialogs',
        (tester) async {
      await launch(tester, platform);
      expect(puzzleTab(tester).hintStatusLabel, '(with ad)');
      expect(puzzleTab(tester).skipStatusLabel, '(with ad)');
      final id = puzzleTab(tester).puzzle!.id;
      for (final hint in [true, false]) {
        final tab = puzzleTab(tester);
        (hint ? tab.onHint : tab.onSkip)();
        await pumpFrames(tester);
        expect(find.text(hint ? 'Get a hint' : 'Skip puzzle'), findsOneWidget);
        expect(find.text('Watch'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await pumpFrames(tester);
        expect(puzzleTab(tester).puzzle!.id, id);
        expect(puzzleTab(tester).hintFromSquare, isNull);
      }
      await disposeApp(tester);
    });

    testWidgets('$platform premium Hint and Skip retain 30 second waits',
        (tester) async {
      await launch(tester, platform, premium: true);
      expect(puzzleTab(tester).hintStatusLabel, 'Start wait');
      expect(puzzleTab(tester).skipStatusLabel, 'Start wait');
      puzzleTab(tester).onHint();
      puzzleTab(tester).onSkip();
      await tester.pump();
      expect(puzzleTab(tester).hintStatusLabel, startsWith('Wait '));
      expect(puzzleTab(tester).skipStatusLabel, startsWith('Wait '));
      await tester.pump(const Duration(seconds: 29));
      expect(puzzleTab(tester).hintStatusLabel, isNot('Ready'));
      await tester.pump(const Duration(seconds: 1));
      expect(puzzleTab(tester).hintStatusLabel, 'Ready');
      expect(puzzleTab(tester).skipStatusLabel, 'Ready');
      expect(find.text('Watch'), findsNothing);
      puzzleTab(tester).onHint();
      await tester.pump();
      expect(puzzleTab(tester).hintFromSquare, 'e2');
      expect(puzzleTab(tester).hintStatusLabel, 'Start wait');
      final id = puzzleTab(tester).puzzle!.id;
      puzzleTab(tester).onSkip();
      await pumpFrames(tester);
      expect(puzzleTab(tester).puzzle!.id, isNot(id));
      await disposeApp(tester);
    });
  }

  testWidgets('iOS scheduling failure restores locked persisted state',
      (tester) async {
    await launch(tester, TargetPlatform.iOS);
    await openWheel(tester);
    failScheduling = true;
    await tester.tap(find.text('Start'));
    await pumpFrames(tester);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('lockEnabled'), isTrue);
    expect(prefs.getInt('unlockUntilMs'), 0);
    expect(calls.any((c) => c.method == 'relockNow'), isTrue);
    await disposeApp(tester);
  });

  test('expired unlock restores as locked after restart', () async {
    SharedPreferences.setMockInitialValues({
      'unlockUntilMs': DateTime.now()
          .subtract(const Duration(seconds: 1))
          .millisecondsSinceEpoch,
      'lockEnabled': false,
    });
    final state = LockStateController(SharedPreferences.getInstance());
    await state.load();
    expect(state.isUnlocked, isFalse);
    expect(state.lockEnabled, isTrue);
  });
}
