import 'dart:convert';

import 'package:chesslock/main.dart';
import 'package:chesslock/services/puzzle_queue_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const systemChannel = MethodChannel('chesslock/system');

  Map<String, Object> puzzle(String id) => {
        'id': id,
        'rating': 900,
        'type': 'Tactics',
        'fen': startingFen,
        'solutionUci': ['e2e4'],
      };

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'themeMode': 'system',
      'puzzleDifficulty': 'normal',
      'lockedPackages': <String>[],
      'indefUnlock': false,
      'unlockUntilMs': 0,
      'lockEnabled': true,
      'queue.normal': jsonEncode([
        puzzle('smoke-1'),
        puzzle('smoke-2'),
        puzzle('smoke-3'),
        puzzle('smoke-4'),
      ]),
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(systemChannel, (call) async {
      switch (call.method) {
        case 'getLaunchableApps':
          return <Map<String, Object>>[];
        case 'hasUsageAccess':
        case 'hasOverlayPermission':
        case 'hasNotificationPermission':
          return true;
        case 'syncWatcherState':
        case 'requestNotificationPermission':
        case 'startWatcher':
        case 'hideWatcherOverlay':
        case 'stopWatcher':
          return null;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(systemChannel, null);
  });

  testWidgets('ChessUnlock renders the home screen', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MyApp());
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('Lock Mode'), findsOneWidget);
    expect(find.text('Locked apps'), findsOneWidget);
    expect(find.text('Solve puzzle to unlock apps'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
