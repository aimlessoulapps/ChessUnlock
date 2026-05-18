import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

class AppCrashlytics {
  static final FirebaseCrashlytics _crashlytics = FirebaseCrashlytics.instance;

  static void initializeErrorHandling() {
    final previousFlutterOnError = FlutterError.onError;

    FlutterError.onError = (details) {
      recordFlutterFatalError(details);
      if (previousFlutterOnError != null) {
        previousFlutterOnError(details);
      } else {
        FlutterError.presentError(details);
      }
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      recordFatalError(error, stack);
      return kReleaseMode;
    };
  }

  static void logAppOpened() => log("app_opened");

  static void logPuzzleStarted({
    required String puzzleType,
    required String difficulty,
  }) =>
      log("puzzle_started type=$puzzleType difficulty=$difficulty");

  static void logPuzzleSolved({
    required String puzzleType,
    required String difficulty,
  }) =>
      log("puzzle_solved type=$puzzleType difficulty=$difficulty");

  static void runDebugCrashTestIfRequested() {
    const requested = bool.fromEnvironment("CRASHLYTICS_TEST_CRASH");
    if (!kDebugMode || !requested) return;

    Future<void>.delayed(const Duration(seconds: 2), () {
      _crashlytics.crash();
    });
  }

  static void log(String message) {
    unawaited(_logSafely(message));
  }

  static void recordFlutterFatalError(FlutterErrorDetails details) {
    unawaited(_recordFlutterFatalErrorSafely(details));
  }

  static void recordFatalError(Object error, StackTrace stack) {
    unawaited(_recordErrorSafely(error, stack, fatal: true));
  }

  static Future<void> _logSafely(String message) async {
    try {
      await _crashlytics.log(message);
    } catch (_) {
      // Crash reporting must never affect app behavior.
    }
  }

  static Future<void> _recordFlutterFatalErrorSafely(
    FlutterErrorDetails details,
  ) async {
    try {
      await _crashlytics.recordFlutterFatalError(details);
    } catch (_) {
      // Crash reporting must never affect app behavior.
    }
  }

  static Future<void> _recordErrorSafely(
    Object error,
    StackTrace stack, {
    required bool fatal,
  }) async {
    try {
      await _crashlytics.recordError(error, stack, fatal: fatal);
    } catch (_) {
      // Crash reporting must never affect app behavior.
    }
  }
}
