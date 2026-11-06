import 'support/fake_revenuecat.dart';
import 'dart:convert';
import 'dart:async';

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

class _ControlledPuzzleQueue extends PuzzleQueueService {
  _ControlledPuzzleQueue()
      : super(SharedPreferences.getInstance(),
            difficultyOptions: ['normal', 'harder']);
  final requests = <(String, Completer<ChessPuzzle?>)>[];
  @override
  Future<void> loadFromPrefs() async {}
  @override
  Future<ChessPuzzle?> nextPuzzle(String difficulty) {
    final result = Completer<ChessPuzzle?>();
    requests.add((difficulty, result));
    return result.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const android = MethodChannel('chesslock/system');
  const ios = MethodChannel('chesslock/screen_time');
  final calls = <MethodCall>[];
  var failScheduling = false;
  Completer<Map<String, Object>>? heldSelection;
  late FakeRevenueCatClient client;

  setUp(() {
    calls.clear();
    failScheduling = false;
    heldSelection = null;
    client = FakeRevenueCatClient();
    for (final channel in [android, ios]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'getEmergencyUnlockUsage':
            final prefs = await SharedPreferences.getInstance();
            return {
              'dayKey': DateTime.now().toIso8601String().split('T').first,
              'count': prefs.getInt('premium.emergencyUnlock.count.v1') ?? 0,
            };
          case 'reserveEmergencyUnlockUse':
            final prefs = await SharedPreferences.getInstance();
            final count = prefs.getInt('premium.emergencyUnlock.count.v1') ?? 0;
            final limit =
                client.info.entitlements.active.containsKey('premium') ? 3 : 1;
            if (count >= limit) return false;
            await prefs.setInt('premium.emergencyUnlock.count.v1', count + 1);
            return true;
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
            final waiting = heldSelection;
            heldSelection = null;
            if (waiting != null) return waiting.future;
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
      {bool premium = false,
      int? savedMinutes,
      PuzzleQueueService? queue}) async {
    debugDefaultTargetPlatformOverride = platform;
    client.info = customer(premium: premium);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'onboardingComplete': true,
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
        puzzleQueue: queue,
        premiumAccess: PremiumAccessService(SharedPreferences.getInstance(),
            client: client),
        themeMode: AppThemeMode.system,
        onThemeModeChanged: (_) async {},
      ),
    ));
    await pumpFrames(tester);
  }

  PuzzleTab puzzleTab(WidgetTester tester) =>
      tester.widget<PuzzleTab>(find.byType(PuzzleTab, skipOffstage: false));

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final size in [const Size(320, 568), const Size(430, 932)]) {
      testWidgets(
          '$platform all tab positions survive subscription changes at $size',
          (tester) async {
        const adsChannel = 'plugins.flutter.io/google_mobile_ads';
        final adCalls = <String>[];
        tester.binding.defaultBinaryMessenger.setMockMessageHandler(adsChannel,
            (message) async {
          adCalls.add(const StandardMessageCodec()
              .readValue(ReadBuffer(message!)) as String);
          return const StandardMethodCodec().encodeSuccessEnvelope(null);
        });
        addTearDown(() => tester.binding.defaultBinaryMessenger
            .setMockMessageHandler(adsChannel, null));
        await launch(tester, platform, premium: true);
        tester.view.physicalSize = size;
        await pumpFrames(tester);
        List<Rect> positions() => [
              for (final type in [
                ScreenAdHeader,
                BoardWithHintOverlay,
                HintSkipButton
              ])
                for (final element
                    in find.byType(type, skipOffstage: false).evaluate())
                  tester.getRect(find.byElementPredicate(
                      (candidate) => candidate == element,
                      skipOffstage: false)),
              for (final tab in [HomeTab, SettingsTab])
                tester.getRect(find
                    .descendant(
                      of: find.byType(tab, skipOffstage: false),
                      matching: find.byType(ListView, skipOffstage: false),
                      skipOffstage: false,
                    )
                    .first),
            ];
        final baseline = positions();
        expect(baseline.length, 8);
        for (final premium in [false, true, false, true]) {
          adCalls.clear();
          client.emit(customer(premium: premium));
          await pumpFrames(tester);
          expect(positions(), baseline);
          if (premium) {
            expect(
                find.byType(BannerAdSlot, skipOffstage: false), findsNothing);
            expect(adCalls.where((call) => call == 'loadBannerAd'), isEmpty);
          }
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }

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
    expect(wheel.childDelegate.estimatedChildCount, 6);
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
      await launch(tester, platform, savedMinutes: 60);
      await openWheel(tester);
      final wheel =
          tester.widget<CupertinoPicker>(find.byType(CupertinoPicker));
      expect(wheel.scrollController!.selectedItem, 2);
      expect(find.text('Premium unlocks up to 3 hours.'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      for (final minutes in [60, 120, 180]) {
        await select(tester, minutes);
        expect(find.byType(PaywallScreen), findsNothing);
        await tester.tap(find.text('Start'));
        await pumpFrames(tester);
        expect(find.byType(PaywallScreen), findsOneWidget);
        expect(prefs.getInt('unlockUntilMs') ?? 0, 0);
        await tester.ensureVisible(find.text('Not now'));
        await tester.tap(find.text('Not now'));
        await pumpFrames(tester);
        expect(wheel.scrollController!.selectedItem, 2);
        expect(prefs.getInt(PremiumAccessService.unlockDurationPrefsKey), 45);
      }
      await select(tester, 45);
      await tester.tap(find.text('Start'));
      await pumpFrames(tester);
      final expiry = prefs.getInt('unlockUntilMs')!;
      expect(expiry - DateTime.now().millisecondsSinceEpoch,
          closeTo(const Duration(minutes: 45).inMilliseconds, 5000));
      expect(prefs.getInt(PremiumAccessService.unlockDurationPrefsKey), 45);
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
        expect(unlock.arguments['durationMs'], 45 * 60 * 1000);
        expect(unlock.arguments['unlockUntilMs'], expiry);
      }
      final restored = LockStateController(Future.value(prefs));
      await restored.load();
      expect(restored.isUnlocked, isTrue);
      expect(restored.unlockedUntil!.millisecondsSinceEpoch, expiry);
      await disposeApp(tester);
    });

    for (final minutes in [15, 30]) {
      testWidgets('$platform free accepts $minutes minutes', (tester) async {
        await launch(tester, platform);
        await openWheel(tester);
        await select(tester, minutes);
        await tester.tap(find.text('Start'));
        await pumpFrames(tester);
        final prefs = await SharedPreferences.getInstance();
        expect(find.byType(PaywallScreen), findsNothing);
        expect(
            prefs.getInt(PremiumAccessService.unlockDurationPrefsKey), minutes);
        expect(
            prefs.getInt('unlockUntilMs')! -
                DateTime.now().millisecondsSinceEpoch,
            closeTo(Duration(minutes: minutes).inMilliseconds, 5000));
        await disposeApp(tester);
      });
    }

    for (final indefinite in [false, true]) {
      testWidgets(
          '$platform free Settings pause remains available indefinite=$indefinite',
          (tester) async {
        await launch(tester, platform);
        await openWheel(tester);
        await tester.tap(find.text('Cancel'));
        await pumpFrames(tester);
        final settings = tester
            .widget<SettingsTab>(find.byType(SettingsTab, skipOffstage: false));
        settings.onLockToggle(false);
        await pumpFrames(tester);
        await tester.tap(find.text(indefinite
            ? 'Turn off until I turn it back on'
            : 'Turn off for 24 hours'));
        await pumpFrames(tester);
        if (indefinite) {
          await tester.tap(find.text('Turn off'));
          await pumpFrames(tester);
        }
        expect(find.byType(PaywallScreen), findsNothing);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('indefUnlock'), indefinite);
        if (!indefinite) {
          expect(
              prefs.getInt('unlockUntilMs')! -
                  DateTime.now().millisecondsSinceEpoch,
              closeTo(const Duration(hours: 24).inMilliseconds, 5000));
        }
        final method = platform == TargetPlatform.android
            ? 'syncWatcherState'
            : 'syncLockState';
        expect(
            calls.where((call) =>
                call.method == method &&
                call.arguments['manualLockPause'] == true),
            isNotEmpty);
        await disposeApp(tester);
      });
    }

    testWidgets('$platform unlock refresh rejects newly expired Premium',
        (tester) async {
      await launch(tester, platform, premium: true, savedMinutes: 60);
      await openWheel(tester);
      client.info =
          customer(); // No listener: discovered by the actual unlock path.
      await tester.tap(find.text('Start'));
      await pumpFrames(tester);
      expect(find.byType(PaywallScreen), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('unlockUntilMs') ?? 0, 0);
      await disposeApp(tester);
    });

    testWidgets('$platform entitlement expires while wheel is open',
        (tester) async {
      await launch(tester, platform, premium: true, savedMinutes: 60);
      await openWheel(tester);
      await select(tester, 60);
      client.emit(customer());
      await pumpFrames(tester);
      expect(find.byType(PaywallScreen), findsNothing);
      await tester.tap(find.text('Start'));
      await pumpFrames(tester);
      expect(find.byType(PaywallScreen), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('unlockUntilMs') ?? 0, 0);
      expect(prefs.getInt(PremiumAccessService.unlockDurationPrefsKey), 45);
      await disposeApp(tester);
    });

    testWidgets('$platform active paid deadline survives expiry and resume',
        (tester) async {
      await launch(tester, platform, premium: true, savedMinutes: 180);
      await openWheel(tester);
      await tester.tap(find.text('Start'));
      await pumpFrames(tester);
      final prefs = await SharedPreferences.getInstance();
      final deadline = prefs.getInt('unlockUntilMs');
      client.emit(customer());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pumpFrames(tester);
      expect(prefs.getInt('unlockUntilMs'), deadline);
      expect(prefs.getInt(PremiumAccessService.unlockDurationPrefsKey), 45);
      await disposeApp(tester);
    });

    for (final minutes in PremiumAccessService.unlockMinuteOptions) {
      testWidgets('$platform premium accepts $minutes minutes', (tester) async {
        await launch(tester, platform, premium: true);
        await openWheel(tester);
        final wheel =
            tester.widget<CupertinoPicker>(find.byType(CupertinoPicker));
        expect(wheel.scrollController!.selectedItem, 0);
        await select(tester, minutes);
        await tester.tap(find.text('Start'));
        await pumpFrames(tester);
        expect(find.byType(PaywallScreen), findsNothing);
        final prefs = await SharedPreferences.getInstance();
        expect(
            prefs.getInt(PremiumAccessService.unlockDurationPrefsKey), minutes);
        expect(
            prefs.getInt('unlockUntilMs')! -
                DateTime.now().millisecondsSinceEpoch,
            closeTo(Duration(minutes: minutes).inMilliseconds, 5000));
        if (platform == TargetPlatform.iOS) {
          final unlock = calls.lastWhere((c) => c.method == 'unlockFor');
          expect(unlock.arguments['durationMs'], minutes * 60 * 1000);
        }
        await disposeApp(tester);
      });
    }

    for (final premium in [false, true]) {
      testWidgets(
          '$platform emergency quota and one-minute unlock premium=$premium',
          (tester) async {
        await launch(tester, platform, premium: premium);
        HomeTab home() =>
            tester.widget<HomeTab>(find.byType(HomeTab, skipOffstage: false));
        expect(home().emergencyUnlockRemaining, premium ? 3 : 1);
        home().onEmergencyUnlock();
        await pumpFrames(tester);
        expect(find.byType(PaywallScreen), findsNothing);
        expect(home().emergencyUnlockRemaining, premium ? 2 : 0);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt('premium.emergencyUnlock.count.v1'), 1);
        expect(
            prefs.getInt('unlockUntilMs')! -
                DateTime.now().millisecondsSinceEpoch,
            closeTo(60000, 5000));
        if (platform == TargetPlatform.iOS) {
          expect(
              calls
                  .lastWhere((c) => c.method == 'unlockFor')
                  .arguments['durationMs'],
              60000);
        }
        home().onEmergencyUnlock();
        await pumpFrames(tester);
        expect(prefs.getInt('premium.emergencyUnlock.count.v1'), 1);
        client.emit(customer(premium: !premium));
        await pumpFrames(tester);
        expect(home().emergencyUnlockRemaining, premium ? 0 : 2);
        await disposeApp(tester);
      });
    }

    testWidgets(
        '$platform resume refresh revokes premium and restores ad gates',
        (tester) async {
      await launch(tester, platform, premium: true);
      expect(puzzleTab(tester).adsDisabled, isTrue);
      final previousRefreshes = client.refreshes;
      client.info = customer();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pumpFrames(tester);
      expect(client.refreshes, greaterThan(previousRefreshes));
      expect(puzzleTab(tester).adsDisabled, isFalse);
      expect(puzzleTab(tester).hintStatusLabel, '(with ad)');
      expect(
          tester
              .widget<HomeTab>(find.byType(HomeTab, skipOffstage: false))
              .emergencyUnlockRemaining,
          1);
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

  testWidgets('older puzzle response cannot replace the selected difficulty',
      (tester) async {
    final queue = _ControlledPuzzleQueue();
    await launch(tester, TargetPlatform.iOS, premium: true, queue: queue);
    expect(queue.requests.first.$1, 'normal');
    tester
        .widget<SettingsTab>(find.byType(SettingsTab, skipOffstage: false))
        .onOpenDifficulty();
    await pumpFrames(tester);
    await tester.tap(find.text(getDifficultyDisplayName('harder')).last);
    await pumpFrames(tester);
    expect(queue.requests.last.$1, 'harder');
    ChessPuzzle puzzle(String id) => ChessPuzzle(
        id: id,
        rating: 900,
        type: 'Tactics',
        fen: startingFen,
        solutionUci: ['e2e4']);
    queue.requests.last.$2.complete(puzzle('new-difficulty'));
    await pumpFrames(tester);
    queue.requests.first.$2.complete(puzzle('stale-response'));
    await pumpFrames(tester);
    expect(puzzleTab(tester).puzzle?.id, 'new-difficulty');
    expect(puzzleTab(tester).loading, isFalse);
    await disposeApp(tester);
  });

  testWidgets('thrown puzzle load clears the spinner and shows retry guidance',
      (tester) async {
    final queue = _ControlledPuzzleQueue();
    await launch(tester, TargetPlatform.iOS, queue: queue);
    queue.requests.single.$2.completeError(StateError('storage unavailable'));
    await pumpFrames(tester);
    expect(puzzleTab(tester).loading, isFalse);
    expect(puzzleTab(tester).loadError, contains('try again'));
    expect(tester.takeException(), isNull);
    await disposeApp(tester);
  });

  testWidgets('stale iOS reconciliation cannot relock a new break',
      (tester) async {
    await launch(tester, TargetPlatform.iOS);
    await openWheel(tester);
    final pending = Completer<Map<String, Object>>();
    heldSelection = pending;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await pumpFrames(tester);
    calls.clear();
    await tester.tap(find.text('Start'));
    await pumpFrames(tester);
    expect(calls.where((call) => call.method == 'unlockFor'), isEmpty);
    pending.complete({'applicationCount': 1});
    await pumpFrames(tester);
    expect(calls.where((call) => call.method == 'startEnforcement'), isEmpty);
    expect(calls.where((call) => call.method == 'unlockFor'), hasLength(1));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('lockEnabled'), isFalse);
    expect(prefs.getInt('unlockUntilMs'),
        greaterThan(DateTime.now().millisecondsSinceEpoch));
    await disposeApp(tester);
  });

  testWidgets('failed iOS emergency grant relocks and refunds quota for retry',
      (tester) async {
    await launch(tester, TargetPlatform.iOS);
    failScheduling = true;
    tester
        .widget<HomeTab>(find.byType(HomeTab, skipOffstage: false))
        .onEmergencyUnlock();
    await pumpFrames(tester);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('lockEnabled'), isTrue);
    expect(prefs.getInt('unlockUntilMs'), 0);
    expect(prefs.getInt('premium.emergencyUnlock.count.v1'), 0);
    failScheduling = false;
    tester
        .widget<HomeTab>(find.byType(HomeTab, skipOffstage: false))
        .onEmergencyUnlock();
    await pumpFrames(tester);
    expect(prefs.getInt('premium.emergencyUnlock.count.v1'), 1);
    expect(prefs.getBool('lockEnabled'), isFalse);
    await disposeApp(tester);
  });

  testWidgets('failed iOS 24-hour pause rolls back persisted state',
      (tester) async {
    await launch(tester, TargetPlatform.iOS);
    await openWheel(tester);
    await tester.tap(find.text('Cancel'));
    await pumpFrames(tester);
    tester
        .widget<SettingsTab>(find.byType(SettingsTab, skipOffstage: false))
        .onLockToggle(false);
    await pumpFrames(tester);
    failScheduling = true;
    await tester.tap(find.text('Turn off for 24 hours'));
    await pumpFrames(tester);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('lockEnabled'), isTrue);
    expect(prefs.getBool('indefUnlock'), isFalse);
    expect(prefs.getInt('unlockUntilMs'), 0);
    expect(tester.takeException(), isNull);
    await disposeApp(tester);
  });

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
