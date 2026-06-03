import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';

class AppAnalytics {
  static final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  static const String _homeScreen = "HomeScreen";
  static const String _puzzleScreen = "PuzzleScreen";
  static const String _settingsScreen = "SettingsScreen";
  static const String _onboardingScreen = "OnboardingScreen";

  static void homeScreenViewed() =>
      _screenViewed("home_screen_viewed", _homeScreen);

  static void puzzleScreenViewed() =>
      _screenViewed("puzzle_screen_viewed", _puzzleScreen);

  static void settingsScreenViewed() =>
      _screenViewed("settings_screen_viewed", _settingsScreen);

  static void onboardingScreenViewed() => _log(
        "onboarding_screen_viewed",
        parameters: _screenParameters(_onboardingScreen),
      );

  static void onboardingStarted() => _log(
        "onboarding_started",
        parameters: _screenParameters(_onboardingScreen),
      );

  static void onboardingCompleted() => _log(
        "onboarding_completed",
        parameters: _screenParameters(_onboardingScreen),
      );

  static void onboardingAnswer({
    required String question,
    required String answer,
  }) =>
      _log(
        "onboarding_answer_$question",
        parameters: {
          ..._screenParameters(_onboardingScreen),
          "answer": answer,
        },
      );

  static void onboardingChooseAppsButtonTapped() => _log(
        "onboarding_choose_apps_button_tapped",
        parameters: _screenParameters(_onboardingScreen),
      );

  static void onboardingLaterButtonTapped() => _log(
        "onboarding_later_button_tapped",
        parameters: _screenParameters(_onboardingScreen),
      );

  static void editLockedAppsTapped() => _log(
        "edit_locked_apps_tapped",
        parameters: _screenParameters(_homeScreen),
      );

  static void solvePuzzleToUnlockTapped() => _log(
        "solve_puzzle_to_unlock_tapped",
        parameters: _screenParameters(_homeScreen),
      );

  static void lockedAppsSelectionSaved(int lockedAppCount) => _log(
        "locked_apps_selection_saved",
        parameters: {
          ..._screenParameters(_homeScreen),
          "locked_app_count": lockedAppCount,
        },
      );

  static void lockedAppPuzzleStarted({required String difficulty}) => _log(
        "locked_app_puzzle_started",
        parameters: _puzzleParameters(
          difficulty: difficulty,
          puzzleType: "locked_app_puzzle",
        ),
      );

  static void lockedAppPuzzleSolved({required String difficulty}) => _log(
        "locked_app_puzzle_solved",
        parameters: _puzzleParameters(
          difficulty: difficulty,
          puzzleType: "locked_app_puzzle",
        ),
      );

  static void practicePuzzleStarted({required String difficulty}) => _log(
        "practice_puzzle_started",
        parameters: _puzzleParameters(
          difficulty: difficulty,
          puzzleType: "practice_puzzle",
        ),
      );

  static void practicePuzzleSolved({required String difficulty}) => _log(
        "practice_puzzle_solved",
        parameters: _puzzleParameters(
          difficulty: difficulty,
          puzzleType: "practice_puzzle",
        ),
      );

  static void puzzleSolvedPopupShown() => _log(
        "puzzle_solved_popup_shown",
        parameters: _screenParameters(_puzzleScreen),
      );

  static void unlockAppsButtonTapped() => _log(
        "unlock_apps_button_tapped",
        parameters: _screenParameters(_puzzleScreen),
      );

  static void puzzleSolvedUnlockAppsTapped() => _log(
        "puzzle_solved_unlock_apps_tapped",
        parameters: _screenParameters(_puzzleScreen),
      );

  static void solveMorePuzzlesTapped() => _log(
        "solve_more_puzzles_tapped",
        parameters: _screenParameters(_puzzleScreen),
      );

  static void puzzleSolvedSolveMoreTapped() => _log(
        "puzzle_solved_solve_more_tapped",
        parameters: _screenParameters(_puzzleScreen),
      );

  static void unlockDurationSelected(int minutes) => _log(
        "unlock_duration_selected",
        parameters: {
          ..._screenParameters(_homeScreen),
          "unlock_duration_minutes": minutes,
        },
      );

  static void unlockStarted(int minutes) => _log(
        "unlock_started",
        parameters: {
          ..._screenParameters(_homeScreen),
          "unlock_duration_minutes": minutes,
        },
      );

  static void unlockExpired() => _log("unlock_expired");

  static void hintButtonTapped() => _log(
        "hint_button_tapped",
        parameters: _screenParameters(_puzzleScreen),
      );

  static void hintDialogShown() => _log(
        "hint_dialog_shown",
        parameters: _screenParameters(_puzzleScreen),
      );

  static void hintDialogWatchAdTapped() => _log(
        "hint_dialog_watch_ad_tapped",
        parameters: _screenParameters(_puzzleScreen),
      );

  static void hintDialogCancelTapped() => _log(
        "hint_dialog_cancel_tapped",
        parameters: _adParameters("cancelled"),
      );

  static void hintRewardedAdCompleted() => _log(
        "hint_rewarded_ad_completed",
        parameters: _adParameters("completed"),
      );

  static void hintRewardedAdFailed(String adResult) => _log(
        "hint_rewarded_ad_failed",
        parameters: _adParameters(adResult),
      );

  static void skipButtonTapped() => _log(
        "skip_button_tapped",
        parameters: _screenParameters(_puzzleScreen),
      );

  static void skipDialogShown() => _log(
        "skip_dialog_shown",
        parameters: _screenParameters(_puzzleScreen),
      );

  static void skipDialogWatchAdTapped() => _log(
        "skip_dialog_watch_ad_tapped",
        parameters: _screenParameters(_puzzleScreen),
      );

  static void skipDialogCancelTapped() => _log(
        "skip_dialog_cancel_tapped",
        parameters: _adParameters("cancelled"),
      );

  static void skipRewardedAdCompleted() => _log(
        "skip_rewarded_ad_completed",
        parameters: _adParameters("completed"),
      );

  static void skipRewardedAdFailed(String adResult) => _log(
        "skip_rewarded_ad_failed",
        parameters: _adParameters(adResult),
      );

  static void puzzleSkippedAfterAd() => _log(
        "puzzle_skipped_after_ad",
        parameters: _adParameters("completed"),
      );

  static void puzzleDifficultyChanged(String difficulty) => _log(
        "puzzle_difficulty_changed",
        parameters: {
          ..._screenParameters(_settingsScreen),
          ..._difficultyParameters(difficulty),
        },
      );

  static void lockStatusChanged(bool lockEnabled) => _log(
        "lock_status_changed",
        parameters: {
          ..._screenParameters(_settingsScreen),
          "lock_enabled": lockEnabled,
        },
      );

  static void appLockPaused({int? unlockDurationMinutes}) => _log(
        "app_lock_paused",
        parameters: {
          ..._screenParameters(_settingsScreen),
          "lock_enabled": false,
          if (unlockDurationMinutes != null)
            "unlock_duration_minutes": unlockDurationMinutes,
        },
      );

  static void appLockResumed() => _log(
        "app_lock_resumed",
        parameters: {
          ..._screenParameters(_settingsScreen),
          "lock_enabled": true,
        },
      );

  static void themeChanged(String themeMode) => _log(
        "theme_changed",
        parameters: {
          ..._screenParameters(_settingsScreen),
          "theme_mode": themeMode,
        },
      );

  static void privacyPolicyTapped() => _log(
        "privacy_policy_tapped",
        parameters: _screenParameters(_settingsScreen),
      );

  static void rateAppTapped() => _log(
        "rate_app_tapped",
        parameters: _screenParameters(_settingsScreen),
      );

  static void feedbackOpened() => _log(
        "feedback_opened",
        parameters: _screenParameters(_settingsScreen),
      );

  static void _screenViewed(String eventName, String screenName) {
    _log(eventName, parameters: _screenParameters(screenName));
    unawaited(_logScreenViewSafely(screenName));
  }

  static void _log(
    String name, {
    Map<String, Object>? parameters,
  }) {
    unawaited(_logSafely(name, parameters));
  }

  static Future<void> _logSafely(
    String name,
    Map<String, Object>? parameters,
  ) async {
    try {
      await _analytics.logEvent(name: name, parameters: parameters);
    } catch (_) {
      // Analytics must never affect app behavior.
    }
  }

  static Future<void> _logScreenViewSafely(String screenName) async {
    try {
      await _analytics.logScreenView(
        screenName: screenName,
        screenClass: screenName,
      );
    } catch (_) {
      // Analytics must never affect app behavior.
    }
  }

  static Map<String, Object> _screenParameters(String screenName) => {
        "screen_name": screenName,
      };

  static Map<String, Object> _puzzleParameters({
    required String difficulty,
    required String puzzleType,
  }) =>
      {
        ..._screenParameters(_puzzleScreen),
        "puzzle_type": puzzleType,
        ..._difficultyParameters(difficulty),
      };

  static Map<String, Object> _difficultyParameters(String difficulty) => {
        "difficulty_name": difficulty,
        "difficulty_rating": _difficultyRating(difficulty),
      };

  static Map<String, Object> _adParameters(String adResult) => {
        ..._screenParameters(_puzzleScreen),
        "ad_result": adResult,
      };

  static int _difficultyRating(String difficulty) {
    return switch (difficulty.toLowerCase()) {
      "easiest" => 900,
      "easier" => 1200,
      "normal" => 1500,
      "harder" => 1800,
      "hardest" => 2100,
      _ => 0,
    };
  }
}
