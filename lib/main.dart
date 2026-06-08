import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:firebase_core/firebase_core.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:advanced_chess_board/chess_board_controller.dart';
import 'package:chess/chess.dart' as ch;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' hide Uint8List;
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'services/app_lock/app_lock_service.dart';
import 'services/analytics_service.dart';
import 'services/crashlytics_service.dart';
import 'services/lock_state_controller.dart';
import 'services/puzzle_queue_service.dart';
import 'services/stats_repository.dart';
import 'ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final firebaseReady = await _initializeFirebaseIfConfigured();
  if (firebaseReady) {
    AppCrashlytics.initializeErrorHandling();
    AppCrashlytics.logAppOpened();
    AppCrashlytics.runDebugCrashTestIfRequested();
  }
  final openPuzzleOnStart =
      await createAppLockService().consumeOpenPuzzleRequest();
  runApp(MyApp(initialTab: openPuzzleOnStart ? 1 : 0));
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_initializeMobileAds());
  });
}

Future<bool> _initializeFirebaseIfConfigured() async {
  final FirebaseOptions options;
  try {
    options = DefaultFirebaseOptions.currentPlatform;
  } on UnsupportedError catch (error) {
    debugPrint("[firebase][init] Firebase not configured: $error");
    return false;
  }

  await Firebase.initializeApp(options: options);
  return true;
}

Future<void> _initializeMobileAds() async {
  if (kIsWeb ||
      (defaultTargetPlatform != TargetPlatform.android &&
          defaultTargetPlatform != TargetPlatform.iOS)) {
    return;
  }

  try {
    final status = await MobileAds.instance.initialize();
    final adapters = status.adapterStatuses.entries
        .map(
          (entry) => "${entry.key}:"
              "${entry.value.state.name}/"
              "${entry.value.latency}s/"
              "${entry.value.description}",
        )
        .join("; ");
    debugPrint(
      "[ads][init] Mobile Ads initialized; "
      "platform=${defaultTargetPlatform.name} "
      "adapters=${adapters.isEmpty ? "none" : adapters}",
    );
  } catch (error) {
    debugPrint("[ads][init] Mobile Ads initialization failed: $error");
    // Ads are optional; app startup should never depend on ad initialization.
  }
}

class MyApp extends StatefulWidget {
  final int initialTab;

  const MyApp({
    super.key,
    this.initialTab = 0,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static const _kThemeMode = "themeMode"; // system/dark/light
  late final Future<SharedPreferences> _prefsFuture =
      SharedPreferences.getInstance();
  AppThemeMode _mode = AppThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await _prefsFuture;
    final raw = (prefs.getString(_kThemeMode) ?? "system").toLowerCase();
    final mode = switch (raw) {
      "dark" => AppThemeMode.dark,
      "light" => AppThemeMode.light,
      _ => AppThemeMode.system,
    };
    if (!mounted) return;
    if (mode != _mode) {
      setState(() => _mode = mode);
    }
  }

  Future<void> _setTheme(AppThemeMode mode) async {
    final prefs = await _prefsFuture;
    await prefs.setString(
      _kThemeMode,
      switch (mode) {
        AppThemeMode.dark => "dark",
        AppThemeMode.light => "light",
        AppThemeMode.system => "system",
      },
    );
    if (!mounted) return;
    setState(() => _mode = mode);
  }

  ThemeMode get _themeMode => switch (_mode) {
        AppThemeMode.dark => ThemeMode.dark,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.system => ThemeMode.system,
      };

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "ChessUnlock",
      debugShowCheckedModeBanner: false,
      theme: _buildAppTheme(Brightness.light),
      darkTheme: _buildAppTheme(Brightness.dark),
      themeMode: _themeMode,
      home: ChessUnlockShell(
        initialTab: widget.initialTab,
        themeMode: _mode,
        onThemeModeChanged: _setTheme,
      ),
    );
  }
}

ThemeData _buildAppTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: dark ? const Color(0xFF43D66E) : const Color(0xFF16A34A),
    onPrimary: dark ? const Color(0xFF06110A) : Colors.white,
    secondary: dark ? const Color(0xFF74E59A) : const Color(0xFF22C55E),
    onSecondary: dark ? const Color(0xFF06110A) : Colors.white,
    error: dark ? const Color(0xFFFFB4AB) : const Color(0xFFBA1A1A),
    onError: dark ? const Color(0xFF690005) : Colors.white,
    surface: dark ? const Color(0xFF0B0F0D) : const Color(0xFFF7FAF8),
    onSurface: dark ? const Color(0xFFF4F7F5) : const Color(0xFF101513),
    surfaceContainerLowest:
        dark ? const Color(0xFF080B09) : const Color(0xFFFFFFFF),
    surfaceContainerLow:
        dark ? const Color(0xFF101411) : const Color(0xFFFFFFFF),
    surfaceContainer: dark ? const Color(0xFF151A17) : const Color(0xFFFFFFFF),
    surfaceContainerHigh:
        dark ? const Color(0xFF171D19) : const Color(0xFFF0F6F2),
    surfaceContainerHighest:
        dark ? const Color(0xFF1E2420) : const Color(0xFFEEF5F0),
    onSurfaceVariant: dark ? const Color(0xFF8F9B94) : const Color(0xFF647067),
    outline: dark ? const Color(0xFF536157) : const Color(0xFFB8C3BA),
    outlineVariant: dark ? const Color(0xFF27342C) : const Color(0xFFD7E2D9),
    inverseSurface: dark ? const Color(0xFFF4F7F5) : const Color(0xFF1B1F1C),
    onInverseSurface: dark ? const Color(0xFF101513) : const Color(0xFFF4F7F5),
    inversePrimary: dark ? const Color(0xFF16A34A) : const Color(0xFF43D66E),
    shadow: Colors.black,
    scrim: Colors.black,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
  );
  final textTheme = _safeScaleTextTheme(base.textTheme, 0.94).apply(
    bodyColor: scheme.onSurface,
    displayColor: scheme.onSurface,
  );
  return base.copyWith(
    textTheme: textTheme,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge?.copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w800,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: dark ? scheme.surfaceContainerHighest : scheme.onSurface,
      contentTextStyle: TextStyle(
        color: dark ? scheme.onSurface : scheme.surface,
        fontWeight: FontWeight.w600,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        disabledBackgroundColor: scheme.surfaceContainerHighest,
        disabledForegroundColor: scheme.onSurfaceVariant.withOpacity(0.65),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: scheme.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      indicatorColor: scheme.primary.withOpacity(dark ? 0.18 : 0.12),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withOpacity(dark ? 0.45 : 0.7),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: scheme.outlineVariant.withOpacity(0.7)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: scheme.outlineVariant.withOpacity(0.7)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: scheme.primary.withOpacity(0.85)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? scheme.onPrimary
            : scheme.onSurfaceVariant,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? scheme.primary
            : scheme.surfaceContainerHighest,
      ),
    ),
  );
}

TextTheme _safeScaleTextTheme(TextTheme t, double factor) {
  TextStyle? scale(TextStyle? s) {
    if (s == null) return null;
    final fs = s.fontSize;
    if (fs == null) return s;
    return s.copyWith(fontSize: fs * factor);
  }

  return t.copyWith(
    displayLarge: scale(t.displayLarge),
    displayMedium: scale(t.displayMedium),
    displaySmall: scale(t.displaySmall),
    headlineLarge: scale(t.headlineLarge),
    headlineMedium: scale(t.headlineMedium),
    headlineSmall: scale(t.headlineSmall),
    titleLarge: scale(t.titleLarge),
    titleMedium: scale(t.titleMedium),
    titleSmall: scale(t.titleSmall),
    bodyLarge: scale(t.bodyLarge),
    bodyMedium: scale(t.bodyMedium),
    bodySmall: scale(t.bodySmall),
    labelLarge: scale(t.labelLarge),
    labelMedium: scale(t.labelMedium),
    labelSmall: scale(t.labelSmall),
  );
}

///
/// ChessUnlockShell = app logic + state + platform calls
/// UI widgets live in ui.dart
///
class ChessUnlockShell extends StatefulWidget {
  final int initialTab;
  final AppThemeMode themeMode;
  final Future<void> Function(AppThemeMode mode) onThemeModeChanged;

  const ChessUnlockShell({
    super.key,
    this.initialTab = 0,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  @override
  State<ChessUnlockShell> createState() => _ChessUnlockShellState();
}

class _ChessUnlockShellState extends State<ChessUnlockShell>
    with WidgetsBindingObserver {
  late final Future<SharedPreferences> _prefsFuture =
      SharedPreferences.getInstance();
  late final LockStateController _lockState;
  late final StatsRepository _statsRepository;
  late final PuzzleQueueService _puzzleQueue;
  late final AppLockService _appLock;
  bool _unsupportedAppLockMessageShown = false;
  NativeAppSelectionResult? _appLockSelectionSummary;
  bool _returnHomeAfterEditPuzzleSolve = false;
  int _appLockSelectionPreviewRevision = 0;

  DateTime? get _unlockedUntil => _lockState.unlockedUntil;
  set _unlockedUntil(DateTime? value) => _lockState.unlockedUntil = value;

  bool get _indefiniteUnlock => _lockState.indefiniteUnlock;
  set _indefiniteUnlock(bool value) => _lockState.indefiniteUnlock = value;

  bool get _lockEnabled => _lockState.lockEnabled;
  set _lockEnabled(bool value) => _lockState.lockEnabled = value;

  Set<String> get _lockedPackages => _lockState.lockedPackages;
  set _lockedPackages(Set<String> value) => _lockState.lockedPackages = value;

  int get _lockedSelectionCount =>
      _appLockSelectionSummary?.totalCount ?? _lockedPackages.length;

  List<String> get _lockedSelectionSummaryLines =>
      _appLockSelectionSummary?.summaryLines ?? const <String>[];

  bool get _hasAnyLockedSelection => _lockedSelectionCount > 0;

  // Board
  final ChessBoardController _boardController = ChessBoardController();
  bool _suppressBoardListener = false;

  // Puzzle
  ChessPuzzle? _puzzle;
  ch.Chess? _engine;

  int _progressIndex = 0;
  bool _solved = false;
  bool _unlockAvailable = false;
  bool _extraPuzzleMode = false;
  bool _puzzleSolvedChoiceShown = false;
  bool _puzzleSolvedDialogShowing = false;
  bool _needsFreshPuzzleOnNextOpen = false;

  bool _loadingPuzzle = false;
  String? _loadError;

  // confirmed position
  String _positionFen = startingFen;

  // pending user move
  String? _pendingUserFen;

  // auto-check
  bool _isChecking = false;
  Timer? _autoCheckTimer;
  Timer? _checkTimeout;
  int _checkToken = 0;

  Timer? _ticker;
  bool _syncExpiryInFlight = false;
  String? _lastTickerUiSnapshot;

  // orientation
  bool _userPlaysBlack = false;

  // Difficulty
  static const List<String> _difficultyOptions = [
    "easiest",
    "easier",
    "normal",
    "harder",
    "hardest",
  ];
  String _difficulty = "normal";

  // Shared prefs keys
  static const _kDifficulty = "puzzleDifficulty";
  static const _kOnboardingComplete = "onboardingComplete";
  static const _kOnboardingAnswers = "onboardingAnswers.v1";
  static const _kLockedAppIconCache = "lockedAppIconCache.v1";
  static const Duration _kLaunchableAppsCacheTtl = Duration(minutes: 10);

  bool _onboardingDialogQueued = false;

  int _statSolved = 0;
  int _statBestRating = 0;
  int _statFirstTry = 0;

  // attempts per puzzle
  int _attemptsThisPuzzle = 0;

  // =========================
  // Hint + Skip ads
  // =========================
  static const String _androidDefaultRewardedAdUnitId =
      "ca-app-pub-8108010703558411/1847579539";
  static const String _iosDefaultRewardedAdUnitId =
      "ca-app-pub-8108010703558411/5800977815";
  static const String _configuredRewardedAdUnitId = String.fromEnvironment(
    "CHESSUNLOCK_REWARDED_AD_UNIT_ID",
  );
  static const String _configuredAndroidRewardedAdUnitId =
      String.fromEnvironment(
    "CHESSUNLOCK_ANDROID_REWARDED_AD_UNIT_ID",
  );
  static const String _configuredIosRewardedAdUnitId = String.fromEnvironment(
    "CHESSUNLOCK_IOS_REWARDED_AD_UNIT_ID",
  );
  static const Duration _rewardedInitialRetryDelay = Duration(seconds: 30);
  static const Duration _rewardedMaxRetryDelay = Duration(minutes: 5);

  RewardedAd? _rewardedAd;
  Future<RewardedAd?>? _rewardedAdLoadFuture;
  LoadAdError? _lastRewardedAdLoadError;
  AdError? _lastRewardedAdShowError;
  DateTime? _nextRewardedRetryAt;
  Duration _rewardedRetryDelay = _rewardedInitialRetryDelay;
  Timer? _rewardedRetryTimer;
  bool _rewardedAdShowing = false;
  bool _rewardedActionInProgress = false;
  bool _rewardedDialogShowing = false;
  bool _loggedInvalidRewardedAdUnitId = false;
  bool _loggedRewardedConfiguration = false;

  // Blink hint overlay
  String? _hintFromSquare;
  bool _hintBlinkOn = false;
  Timer? _hintBlinkTimer;

  // Tabs
  late int _tab; // 0 Home, 1 Puzzle, 2 Settings

  // Icons cache
  Map<String, Uint8List> _iconsByPkg = {};
  Map<String, String> _iconBase64ByPkg = {};
  Future<void>? _lockedIconCacheLoadFuture;
  bool _lockedIconPrefetchScheduled = false;
  bool _lockedIconPrefetchInFlight = false;
  List<Map<String, dynamic>>? _launchableAppsCache;
  DateTime? _launchableAppsCacheAt;
  Future<List<Map<String, dynamic>>>? _launchableAppsLoadFuture;
  bool _launchableAppsPrefetchScheduled = false;

  // =========================
  // ✅ NEW: local queues per difficulty
  // =========================
  // =========================
  // Lifecycle
  // =========================
  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab.clamp(0, 2).toInt();
    _logScreenViewedForTab(_tab);
    _lockState = LockStateController(_prefsFuture);
    _statsRepository = StatsRepository(_prefsFuture);
    _puzzleQueue = PuzzleQueueService(
      _prefsFuture,
      difficultyOptions: _difficultyOptions,
    );
    _appLock = createAppLockService();
    WidgetsBinding.instance.addObserver(this);

    _boardController.addListener(_onBoardChanged);

    _init();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _preloadRewardedAd();
      _scheduleLaunchableAppsPrefetch(reason: "startup");
    });

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _queueExpirySync();
      if (_shouldRebuildForTicker()) {
        setState(() {});
      }
    });
  }

  Future<void> _init() async {
    await _loadPrefs();
    if (!mounted) return;

    await _loadQueuesFromPrefs(); // ✅ load stored queues
    if (!mounted) return;
    final puzzleLoad = _showNextPuzzleForCurrentDifficulty(
      reason: "init",
    ).catchError((Object error, StackTrace stackTrace) {
      if (mounted) _snack("Puzzle load failed.");
    });
    await _ensureAppLockReadyIfNeeded();
    await _openPuzzleFromOverlayRequestIfNeeded();
    await _maybeShowFirstLaunchOnboarding();

    // ✅ Show a puzzle instantly if queue has one, otherwise cached, otherwise network.
    await puzzleLoad;
    _scheduleDeferredLockedIconPrefetch();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _autoCheckTimer?.cancel();
    _checkTimeout?.cancel();
    _hintBlinkTimer?.cancel();
    _disposeRewardedAd();
    _cancelRewardedRetryTimer();
    _boardController.removeListener(_onBoardChanged);
    _boardController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        _queueExpirySync();
      }
      unawaited(_ensureAppLockReadyIfNeeded());
      unawaited(_openPuzzleFromOverlayRequestIfNeeded());
      _scheduleLaunchableAppsPrefetch(reason: "app_resumed");
    }
  }

  // =========================
  // Helpers
  // =========================
  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _openPuzzleFromOverlayRequestIfNeeded() async {
    final openPuzzle = await _appLock.consumeOpenPuzzleRequest();
    if (!mounted || !openPuzzle) return;
    _goPuzzle();
  }

  Future<void> _maybeShowFirstLaunchOnboarding() async {
    final prefs = await _prefsFuture;

    if (_hasAnyLockedSelection) {
      if (prefs.getBool(_kOnboardingComplete) != true) {
        await prefs.setBool(_kOnboardingComplete, true);
      }
      return;
    }

    if (prefs.getBool(_kOnboardingComplete) == true ||
        _onboardingDialogQueued) {
      return;
    }

    _onboardingDialogQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_showFirstLaunchOnboardingFlow());
    });
  }

  Future<void> _completeOnboarding() async {
    final prefs = await _prefsFuture;
    await prefs.setBool(_kOnboardingComplete, true);
  }

  Future<void> _saveOnboardingAnswer(String key, String answer) async {
    final prefs = await _prefsFuture;
    final raw = prefs.getString(_kOnboardingAnswers);
    final answers = <String, String>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            answers[entry.key.toString()] = entry.value.toString();
          }
        }
      } catch (_) {}
    }

    answers[key] = answer;
    await prefs.setString(_kOnboardingAnswers, jsonEncode(answers));

    if (key == "source" ||
        key == "distraction" ||
        key == "goal" ||
        key == "strictness") {
      AppAnalytics.onboardingAnswer(question: key, answer: answer);
    }
  }

  Future<NativeAppSelectionResult?> _refreshAppLockSelectionSummary({
    bool notify = true,
  }) async {
    final summary = await _appLock.getSelectionSummary();
    if (!mounted) return summary;

    if (_sameSelectionSummary(_appLockSelectionSummary, summary)) {
      return summary;
    }

    _appLockSelectionSummary = summary;
    if (notify) {
      setState(() {});
    }
    return summary;
  }

  bool _sameSelectionSummary(
    NativeAppSelectionResult? a,
    NativeAppSelectionResult? b,
  ) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return a == null && b == null;
    return a.applicationCount == b.applicationCount &&
        a.categoryCount == b.categoryCount &&
        a.webDomainCount == b.webDomainCount &&
        a.includeEntireCategory == b.includeEntireCategory;
  }

  Future<void> _showFirstLaunchOnboardingFlow() async {
    if (!mounted) return;

    if (_hasAnyLockedSelection) {
      await _completeOnboarding();
      return;
    }

    AppAnalytics.onboardingScreenViewed();
    AppAnalytics.onboardingStarted();
    final chooseApps = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => OnboardingFlow(
          onAnswerSelected: _saveOnboardingAnswer,
          onPermissionContinue: _runOnboardingPermissionSetup,
        ),
      ),
    );

    if (!mounted || chooseApps != true) return;

    AppAnalytics.onboardingChooseAppsButtonTapped();
    await _completeOnboarding();
    AppAnalytics.onboardingCompleted();
    if (!mounted) return;
    await _openAppPicker(requireSolved: false);
  }

  Future<void> _runOnboardingPermissionSetup() async {
    if (!_appLock.isSupported) {
      _snack(_appLock.unsupportedMessage);
      return;
    }

    await _appLock.requestInitialPermissionSetup();
  }

  bool get _isUnlocked => _lockState.isUnlocked;

  Duration get _unlockRemaining => _lockState.unlockRemaining;

  String _tickerUiSnapshot() {
    final parts = <String>["tab:$_tab"];

    final unlockCountdownVisible =
        (_tab == 0 || _tab == 2) && !_lockEnabled && !_indefiniteUnlock;
    if (unlockCountdownVisible) {
      parts.add("unlock:${_unlockRemaining.inSeconds}");
    }

    return parts.join("|");
  }

  bool _shouldRebuildForTicker() {
    final snapshot = _tickerUiSnapshot();
    if (snapshot == _lastTickerUiSnapshot) return false;
    _lastTickerUiSnapshot = snapshot;
    return true;
  }

  void _queueExpirySync() {
    if (_syncExpiryInFlight) return;
    _syncExpiryInFlight = true;
    unawaited(
      _syncExpiry().catchError((Object error, StackTrace stackTrace) {
        if (mounted) {
          _snack("Couldn't update lock state. Please try again.");
        }
      }).whenComplete(() => _syncExpiryInFlight = false),
    );
  }

  void _debugUnlock(String message) {
    debugPrint("[unlock] $message");
  }

  bool get _isBlackToMove => _isBlackToMoveFromFen(_positionFen);

  bool get _canUnlockApps => _unlockAvailable || _solved;

  String get _sideToMoveLabel {
    if (_loadingPuzzle && _canUnlockApps) return "Loading next puzzle…";
    if (_solved) return "Puzzle solved";
    return _isBlackToMove ? "Black to move" : "White to move";
  }

  bool _isBlackToMoveFromFen(String fen) {
    final parts = fen.split(" ");
    return parts.length >= 2 && parts[1] == "b";
  }

  double get _accuracyPct {
    if (_statSolved <= 0) return 0;
    return (_statFirstTry / _statSolved) * 100.0;
  }

  // compare only first 4 fields of FEN (stable across libs)
  String _fenKey4(String fen) {
    final parts = fen.split(' ');
    if (parts.length < 4) return fen.trim();
    return parts.take(4).join(' ');
  }

  // =========================
  // Launchable apps + icons
  // =========================
  bool get _shouldCacheLaunchableApps =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      _appLock.isSupported &&
      !_appLock.usesNativeAppPicker;

  Future<List<Map<String, dynamic>>> _getLaunchableAppsRaw() {
    return _getLaunchableAppsCached(reason: "picker_open");
  }

  bool get _hasFreshLaunchableAppsCache {
    final cachedAt = _launchableAppsCacheAt;
    return _launchableAppsCache != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _kLaunchableAppsCacheTtl;
  }

  Future<List<Map<String, dynamic>>> _getLaunchableAppsCached({
    required String reason,
    bool forceRefresh = false,
  }) async {
    if (!_shouldCacheLaunchableApps) {
      return _appLock.getLockableApps();
    }

    final cached = _launchableAppsCache;
    if (!forceRefresh && cached != null) {
      final fresh = _hasFreshLaunchableAppsCache;
      _debugAppList(
        "cache ${fresh ? "hit" : "stale_hit"}; "
        "reason=$reason count=${cached.length}",
      );
      if (!fresh) {
        _scheduleLaunchableAppsPrefetch(reason: "stale_$reason");
      }
      return _copyLaunchableApps(cached);
    }

    final inFlight = _launchableAppsLoadFuture;
    if (inFlight != null) {
      _debugAppList("join in-flight request; reason=$reason");
      final apps = await inFlight;
      return _copyLaunchableApps(apps);
    }

    final stopwatch = Stopwatch()..start();
    _debugAppList(
      "cache miss; reason=$reason forceRefresh=$forceRefresh",
    );

    final future = _loadLaunchableAppsFromPlatform(reason: reason);
    _launchableAppsLoadFuture = future;
    try {
      final apps = await future;
      _launchableAppsCache = _copyLaunchableApps(apps);
      _launchableAppsCacheAt = DateTime.now();
      _debugAppList(
        "cache stored; reason=$reason count=${apps.length} "
        "durationMs=${stopwatch.elapsedMilliseconds}",
      );
      return _copyLaunchableApps(apps);
    } finally {
      if (identical(_launchableAppsLoadFuture, future)) {
        _launchableAppsLoadFuture = null;
      }
    }
  }

  Future<List<Map<String, dynamic>>> _loadLaunchableAppsFromPlatform({
    required String reason,
  }) async {
    final stopwatch = Stopwatch()..start();
    _debugAppList("platform request start; reason=$reason");
    final apps = await _appLock.getLockableApps();
    _debugAppList(
      "platform request end; reason=$reason count=${apps.length} "
      "durationMs=${stopwatch.elapsedMilliseconds}",
    );
    return apps;
  }

  void _scheduleLaunchableAppsPrefetch({required String reason}) {
    if (!_shouldCacheLaunchableApps ||
        _launchableAppsPrefetchScheduled ||
        _launchableAppsLoadFuture != null ||
        _hasFreshLaunchableAppsCache) {
      return;
    }

    _launchableAppsPrefetchScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _launchableAppsPrefetchScheduled = false;
      if (!mounted || !_shouldCacheLaunchableApps) return;
      unawaited(
        _getLaunchableAppsCached(
          reason: "prefetch_$reason",
          forceRefresh: true,
        ).catchError((Object error, StackTrace stackTrace) {
          _debugAppList("prefetch failed; reason=$reason error=$error");
          return <Map<String, dynamic>>[];
        }),
      );
    });
  }

  List<Map<String, dynamic>> _copyLaunchableApps(
    List<Map<String, dynamic>> apps,
  ) {
    return [
      for (final app in apps) Map<String, dynamic>.from(app),
    ];
  }

  void _debugAppList(String message) {
    if (!kDebugMode) return;
    debugPrint("[app-list] $message");
  }

  Future<List<Map<String, dynamic>>> _getLockedAppIconsRaw(
    Set<String> packages,
  ) =>
      _appLock.getLockableAppIcons(packages);

  Future<Set<String>> _sanitizeLockedPackages(Set<String> packages) async {
    return _appLock.sanitizeLockedAppIds(packages);
  }

  Future<void> _removeOwnPackageFromLockedAppsIfPresent() async {
    final sanitized = await _sanitizeLockedPackages(_lockedPackages);
    if (setEquals(sanitized, _lockedPackages)) return;

    _lockedPackages = sanitized;
    await _saveLockedPackages();
  }

  void _scheduleDeferredLockedIconPrefetch() {
    if (_lockedPackages.isEmpty ||
        _lockedIconPrefetchScheduled ||
        _lockedIconPrefetchInFlight) {
      return;
    }

    _lockedIconPrefetchScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _lockedIconPrefetchScheduled = false;
      if (!mounted) return;
      unawaited(_prefetchLockedAppIcons());
    });
  }

  Future<void> _prefetchLockedAppIcons() async {
    if (_lockedIconPrefetchInFlight || _lockedPackages.isEmpty) return;
    _lockedIconPrefetchInFlight = true;

    try {
      final cacheLoad = _lockedIconCacheLoadFuture;
      if (cacheLoad != null) {
        await cacheLoad.catchError((_) {});
      }
      if (!mounted) return;

      final lockedPackages = {..._lockedPackages};
      final missingPackages =
          lockedPackages.where((pkg) => !_iconsByPkg.containsKey(pkg)).toSet();
      if (missingPackages.isEmpty) return;

      final list = await _getLockedAppIconsRaw(missingPackages);
      final map = <String, Uint8List>{};
      final base64ByPkg = <String, String>{};

      for (final m in list) {
        final pkg = (m["packageName"] ?? "").toString();
        if (!missingPackages.contains(pkg)) continue;
        final b64 = (m["iconPngBase64"] ?? "").toString();
        if (pkg.isEmpty || b64.isEmpty) continue;
        final bytes = decodeIconPngBase64(b64);
        if (bytes == null) continue;
        map[pkg] = bytes;
        base64ByPkg[pkg] = b64;
      }

      if (!mounted) return;
      if (map.isNotEmpty) {
        _iconBase64ByPkg = {..._iconBase64ByPkg, ...base64ByPkg};
        unawaited(_persistLockedAppIconCache(lockedPackages));
        setState(() => _iconsByPkg = {..._iconsByPkg, ...map});
      }
    } catch (_) {
      // ignore
    } finally {
      _lockedIconPrefetchInFlight = false;
    }
  }

  void _restoreCachedLockedAppIconsInBackground() {
    if (_lockedIconCacheLoadFuture != null) return;
    _lockedIconCacheLoadFuture = _restoreCachedLockedAppIcons();
    unawaited(_lockedIconCacheLoadFuture!.catchError((_) {}));
  }

  Future<void> _restoreCachedLockedAppIcons() async {
    try {
      final prefs = await _prefsFuture;
      final raw = prefs.getString(_kLockedAppIconCache);
      if (raw == null || raw.trim().isEmpty) return;

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;

      final lockedPackages = {..._lockedPackages};
      if (lockedPackages.isEmpty) return;

      final restoredBase64 = <String, String>{};
      final restoredIcons = <String, Uint8List>{};

      for (final entry in decoded.entries) {
        final pkg = entry.key.toString().trim();
        final b64 = entry.value?.toString().trim() ?? "";
        if (pkg.isEmpty || b64.isEmpty) continue;

        final bytes = decodeIconPngBase64(b64);
        if (bytes == null) continue;

        restoredBase64[pkg] = b64;
        if (lockedPackages.contains(pkg)) {
          restoredIcons[pkg] = bytes;
        }
      }

      if (!mounted) return;
      _iconBase64ByPkg = restoredBase64;
      if (restoredIcons.isNotEmpty) {
        setState(() => _iconsByPkg = {..._iconsByPkg, ...restoredIcons});
      }
    } catch (_) {
      // ignore corrupt or old cache data; initials remain the fallback.
    }
  }

  Future<void> _persistLockedAppIconCache(Set<String> lockedPackages) async {
    try {
      final cache = <String, String>{
        for (final entry in _iconBase64ByPkg.entries)
          if (lockedPackages.contains(entry.key) &&
              entry.value.trim().isNotEmpty)
            entry.key: entry.value,
      };

      final prefs = await _prefsFuture;
      if (cache.isEmpty) {
        await prefs.remove(_kLockedAppIconCache);
      } else {
        await prefs.setString(_kLockedAppIconCache, jsonEncode(cache));
      }
    } catch (_) {
      // Icon cache is best-effort only.
    }
  }

  void _retainLockedAppIcons(Set<String> lockedPackages) {
    _iconsByPkg = {
      for (final entry in _iconsByPkg.entries)
        if (lockedPackages.contains(entry.key)) entry.key: entry.value,
    };
    _iconBase64ByPkg.removeWhere((pkg, _) => !lockedPackages.contains(pkg));
  }

  // =========================
  // Prefs
  // =========================
  Future<void> _loadPrefs() async {
    await _lockState.load();
    await _removeOwnPackageFromLockedAppsIfPresent();
    _restoreCachedLockedAppIconsInBackground();
    final prefs = await _prefsFuture;

    final savedDiff = prefs.getString(_kDifficulty);
    if (savedDiff != null && _difficultyOptions.contains(savedDiff)) {
      _difficulty = savedDiff;
    }

    final stats = await _statsRepository.load();
    _statSolved = stats.solved;
    _statBestRating = stats.bestRating;
    _statFirstTry = stats.firstTry;

    if (mounted) setState(() {});
  }

  Future<void> _saveUnlockState() => _lockState.saveUnlockState();

  Future<void> _saveDifficulty() async {
    final prefs = await _prefsFuture;
    await prefs.setString(_kDifficulty, _difficulty);
  }

  Future<void> _saveLockedPackages() => _lockState.saveLockedPackages();

  Future<void> _saveLockEnabledPersist() => _lockState.saveLockEnabled();

  Future<void> _saveStats() => _statsRepository.save(
        StatsSnapshot(
          solved: _statSolved,
          bestRating: _statBestRating,
          firstTry: _statFirstTry,
        ),
      );

  // =========================
  // Puzzle queue
  // =========================
  Future<void> _loadQueuesFromPrefs() => _puzzleQueue.loadFromPrefs();

  // =========================
  // Get next puzzle (queue -> cached -> network)
  // =========================
  Future<void> _showNextPuzzleForCurrentDifficulty(
      {required String reason}) async {
    if (!mounted) return;
    final diff = _difficulty;
    final isExtraPuzzle = _extraPuzzleMode || reason == "extra";
    final hadPuzzleAlready = _puzzle != null;

    _clearHintHighlight(notify: false);
    setState(() {
      _loadingPuzzle = true;
      _loadError = null;
    });

    final next = await _puzzleQueue.nextPuzzle(diff);
    if (!mounted) return;

    if (next != null) {
      _loadPuzzle(next, isNewPuzzle: true);
      if (isExtraPuzzle) {
        AppCrashlytics.logPuzzleStarted(
          puzzleType: "practice_puzzle",
          difficulty: diff,
        );
        AppAnalytics.practicePuzzleStarted(
          difficulty: diff,
        );
      } else {
        AppCrashlytics.logPuzzleStarted(
          puzzleType: "locked_app_puzzle",
          difficulty: diff,
        );
        AppAnalytics.lockedAppPuzzleStarted(
          difficulty: diff,
        );
      }
      setState(() {
        _loadingPuzzle = false;
        _loadError = null;
      });
      return;
    }

    setState(() {
      _loadingPuzzle = false;
      _loadError = "Puzzle load failed: HTTP 500 / network error";

      if (!hadPuzzleAlready) {
        _puzzle = null;
        _engine = null;
        _solved = false;
        _progressIndex = 0;
        _positionFen = startingFen;
        _setBoardFen(_positionFen);
      }
    });

    _snack("Puzzle load failed.");
  }

  // =========================
  // Platform app locking
  // =========================
  Future<void> _syncAppLockStateToNative() async {
    await _appLock.syncLockState(
      AppLockStateSnapshot(
        lockedAppIds: await _sanitizeLockedPackages(_lockedPackages),
        lockEnabled: _lockEnabled,
        indefiniteUnlock: _indefiniteUnlock,
        unlockUntilMs: _unlockedUntil?.millisecondsSinceEpoch ?? 0,
      ),
    );
  }

  Future<void> _ensureAppLockReadyIfNeeded() async {
    await _syncAppLockStateToNative();

    final selectionSummary = await _refreshAppLockSelectionSummary();
    final hasConfiguredLocks = selectionSummary?.hasSelection ??
        await _appLock.hasConfiguredLocks(_lockedPackages);

    if (!hasConfiguredLocks) {
      await _appLock.stopEnforcement();
      return;
    }

    if (!_appLock.isSupported) {
      await _appLock.stopEnforcement();
      if (!_unsupportedAppLockMessageShown && mounted) {
        _unsupportedAppLockMessageShown = true;
        _snack(_appLock.unsupportedMessage);
      }
      return;
    }

    final permissionStatus = await _appLock.checkPermissions(
      requiresOverlay: _lockEnabled,
    );
    if (!mounted) return;

    if (permissionStatus.issue == AppLockPermissionIssue.usageAccessRequired) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text("Enable Usage Access"),
          content: const Text(
            "ChessUnlock needs Usage Access to detect when a locked app is opened.\n\n"
            "Without it, app locking won’t work.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Not now"),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _appLock.openUsageAccessSettings();
              },
              child: const Text("Open Settings"),
            ),
          ],
        ),
      );
      await _appLock.stopEnforcement();
      return;
    }

    if (permissionStatus.issue ==
        AppLockPermissionIssue.overlayPermissionRequired) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text("Enable Display Over Other Apps"),
          content: const Text(
            "ChessUnlock needs permission to show the lock overlay above other apps.\n\n"
            "Open Settings → enable “Display over other apps” for ChessUnlock.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Not now"),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _appLock.openOverlaySettings();
              },
              child: const Text("Open Settings"),
            ),
          ],
        ),
      );
      await _appLock.stopEnforcement();
      return;
    }

    if (permissionStatus.issue ==
        AppLockPermissionIssue.screenTimeAuthorizationRequired) {
      _snack("Screen Time permission is required.");
      await _appLock.stopEnforcement();
      return;
    }

    if (permissionStatus.issue == AppLockPermissionIssue.unsupported) {
      _snack(_appLock.unsupportedMessage);
      await _appLock.stopEnforcement();
      return;
    }

    final hasTimedUnlock = !_indefiniteUnlock && _unlockedUntil != null;
    final shouldRunWatcher =
        hasConfiguredLocks && (_lockEnabled || hasTimedUnlock);

    if (shouldRunWatcher) {
      await _appLock.requestNotificationPermissionIfNeeded();
      if (!mounted) return;

      if (_lockEnabled) {
        await _appLock.startEnforcement();
      } else {
        await _appLock.hideActiveBlocker();
      }
    } else {
      await _appLock.stopEnforcement();
    }
  }

  // =========================
  // Unlock state / expiry
  // =========================
  Future<bool> _syncLockStateToStorageAndWatcher({
    required bool includeUnlockState,
  }) async {
    try {
      if (includeUnlockState) {
        await _saveUnlockState();
      }
      await _saveLockEnabledPersist();
      if (!mounted) return false;
      await _ensureAppLockReadyIfNeeded();
      return true;
    } catch (_) {
      if (mounted) {
        _snack("Couldn't save lock state. Please try again.");
      }
      return false;
    }
  }

  void _queuePuzzleRefresh(String reason) {
    if (!mounted) return;
    unawaited(
      _showNextPuzzleForCurrentDifficulty(reason: reason).catchError(
        (Object error, StackTrace stackTrace) {
          if (mounted) _snack("Puzzle load failed.");
        },
      ),
    );
  }

  void _clearCurrentPuzzleForFreshLoad() {
    _autoCheckTimer?.cancel();
    _checkTimeout?.cancel();
    _clearHintHighlight(notify: false);
    _checkToken++;

    _puzzle = null;
    _engine = null;
    _progressIndex = 0;
    _solved = false;
    _isChecking = false;
    _pendingUserFen = null;
    _puzzleSolvedChoiceShown = false;
    _puzzleSolvedDialogShowing = false;
    _loadError = null;

    _positionFen = startingFen;
    _setBoardFen(_positionFen);
  }

  void _prepareFreshPuzzleOnNextOpen() {
    _needsFreshPuzzleOnNextOpen = true;
    if (_solved) {
      _clearCurrentPuzzleForFreshLoad();
      if (mounted) setState(() {});
    }
  }

  void _ensureFreshPuzzleWhenOpeningPuzzleTab() {
    if (!mounted || _loadingPuzzle || _puzzleSolvedDialogShowing) return;
    if (!_needsFreshPuzzleOnNextOpen && !_solved) return;

    if (_solved) {
      _clearCurrentPuzzleForFreshLoad();
      if (mounted) setState(() {});
    }

    _queuePuzzleRefresh(_extraPuzzleMode ? "extra" : "freshopen");
  }

  void _resetSolvedUnlockFlow() {
    _unlockAvailable = false;
    _extraPuzzleMode = false;
    _puzzleSolvedChoiceShown = false;
    _puzzleSolvedDialogShowing = false;
  }

  Future<void> _syncExpiry() async {
    if (_indefiniteUnlock) {
      if (_lockEnabled) {
        _lockEnabled = false;
        if (mounted) setState(() {});
        await _syncLockStateToStorageAndWatcher(includeUnlockState: false);
      }
      return;
    }

    final until = _unlockedUntil;
    if (until != null && DateTime.now().isAfter(until)) {
      _debugUnlock(
        "real unlock expiry reached; expiryMs=${until.millisecondsSinceEpoch} "
        "nowMs=${DateTime.now().millisecondsSinceEpoch}",
      );
      final saved = await _relockNow(resetPuzzle: true);
      if (mounted && saved) {
        AppAnalytics.unlockExpired();
        _snack("Locked again. Solve to unlock apps.");
      }
      return;
    }

    final shouldBeLockOn = !_isUnlocked;
    if (_lockEnabled != shouldBeLockOn) {
      _lockEnabled = shouldBeLockOn;
      if (mounted) setState(() {});
      await _syncLockStateToStorageAndWatcher(includeUnlockState: false);
    }
  }

  Future<bool> _relockNow({required bool resetPuzzle}) async {
    _indefiniteUnlock = false;
    _unlockedUntil = null;
    _lockEnabled = true;
    _resetSolvedUnlockFlow();
    if (mounted) setState(() {});

    final saved =
        await _syncLockStateToStorageAndWatcher(includeUnlockState: true);

    if (saved) {
      try {
        await _appLock.relockNow();
        _debugUnlock("relock/apply shield completed from relockNow");
      } catch (error) {
        _debugUnlock(
          "relock/apply shield failed from relockNow; error=$error",
        );
        rethrow;
      }
    }

    if (resetPuzzle) {
      _queuePuzzleRefresh("relock");
    }
    if (mounted) setState(() {});
    return saved;
  }

  Future<bool> _unlockForMinutes(int? minutes) async {
    if (minutes == null) {
      _indefiniteUnlock = true;
      _unlockedUntil = null;
    } else {
      _indefiniteUnlock = false;
      _unlockedUntil = DateTime.now().add(Duration(minutes: minutes));
      _debugUnlock(
        "unlock duration selected; minutes=$minutes "
        "realExpiryMs=${_unlockedUntil!.millisecondsSinceEpoch}",
      );
    }

    _lockEnabled = false;
    _resetSolvedUnlockFlow();
    if (mounted) setState(() {});

    final saved =
        await _syncLockStateToStorageAndWatcher(includeUnlockState: true);

    if (saved) {
      await _appLock.unlockFor(
        minutes == null ? null : Duration(minutes: minutes),
      );
    }

    _queuePuzzleRefresh("unlock");
    if (mounted) setState(() {});
    return saved;
  }

  Future<bool> _unlockFor24h() async {
    _indefiniteUnlock = false;
    _unlockedUntil = DateTime.now().add(const Duration(hours: 24));
    _lockEnabled = false;
    _resetSolvedUnlockFlow();
    if (mounted) setState(() {});

    final saved =
        await _syncLockStateToStorageAndWatcher(includeUnlockState: true);

    if (saved) {
      await _appLock.unlockFor(const Duration(hours: 24));
    }

    _queuePuzzleRefresh("unlock24h");
    if (mounted) setState(() {});
    return saved;
  }

  // =========================
  // Board / logic
  // =========================
  void _loadPuzzle(ChessPuzzle puzzle, {required bool isNewPuzzle}) {
    _autoCheckTimer?.cancel();
    _checkTimeout?.cancel();
    _clearHintHighlight(notify: false);
    _checkToken++;

    final engine = ch.Chess.fromFEN(puzzle.fen);

    _puzzle = puzzle;
    _engine = engine;
    _progressIndex = 0;
    _solved = false;
    _isChecking = false;
    _pendingUserFen = null;

    _positionFen = engine.fen;
    _setBoardFen(_positionFen);

    _userPlaysBlack = _isBlackToMoveFromFen(puzzle.fen);

    if (isNewPuzzle) {
      _attemptsThisPuzzle = 0;
      _puzzleSolvedChoiceShown = false;
      _puzzleSolvedDialogShowing = false;
      _needsFreshPuzzleOnNextOpen = false;
    }

    _preloadRewardedAd();

    setState(() {});
  }

  void _setBoardFen(String fen) {
    _suppressBoardListener = true;
    _boardController.loadGameFromFEN(fen);
    Future.microtask(() => _suppressBoardListener = false);
  }

  void _onBoardChanged() {
    if (!mounted) return;
    if (_suppressBoardListener) return;
    if (_puzzle == null || _solved || _isChecking) return;
    if (!_canUserMove) return;

    final currentFen = _boardController.fen;
    if (currentFen == _positionFen) return;

    _clearHintHighlight(notify: false);
    _pendingUserFen = currentFen;
    _startChecking();
    _scheduleAutoCheck();
  }

  bool get _canUserMove =>
      _puzzle != null && !_solved && !_isChecking && (_progressIndex % 2 == 0);

  void _startChecking() {
    _checkTimeout?.cancel();
    _checkToken++;
    final token = _checkToken;

    setState(() => _isChecking = true);

    _checkTimeout = Timer(const Duration(seconds: 2), () {
      if (!mounted || token != _checkToken) return;
      _isChecking = false;
      _pendingUserFen = null;
      _setBoardFen(_positionFen);
      setState(() {});
      _snack("Check timed out.");
    });
  }

  void _stopChecking() {
    _checkTimeout?.cancel();
    if (!mounted) return;
    setState(() => _isChecking = false);
  }

  void _scheduleAutoCheck() {
    _autoCheckTimer?.cancel();
    _autoCheckTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _confirmUserMoveAgainstSolution();
    });
  }

  void _confirmUserMoveAgainstSolution() {
    final puzzle = _puzzle;
    final engine = _engine;
    if (puzzle == null || engine == null || _solved) {
      _stopChecking();
      return;
    }

    final pendingFen = _pendingUserFen;
    if (pendingFen == null) {
      _stopChecking();
      return;
    }

    if (!(_progressIndex % 2 == 0)) {
      _stopChecking();
      _pendingUserFen = null;
      _setBoardFen(_positionFen);
      return;
    }

    if (_progressIndex >= puzzle.solutionUci.length) {
      _markPuzzleSolved(puzzle, recordStats: false);
      _stopChecking();
      setState(() {});
      _handlePuzzleSolved();
      return;
    }

    final test = ch.Chess.fromFEN(engine.fen);
    final expectedUci = puzzle.solutionUci[_progressIndex];

    if (!_applyUci(test, expectedUci)) {
      _stopChecking();
      _snack("Internal error. New puzzle.");
      _queuePuzzleRefresh("internalerror");
      return;
    }

    if (_fenKey4(pendingFen) != _fenKey4(test.fen)) {
      _stopChecking();
      _attemptsThisPuzzle += 1;
      _snack("Wrong ❌");
      _loadPuzzle(puzzle, isNewPuzzle: false);
      return;
    }

    if (!_applyUci(engine, expectedUci)) {
      _stopChecking();
      _snack("Internal error. New puzzle.");
      _queuePuzzleRefresh("internalerror2");
      return;
    }

    _progressIndex++;
    _positionFen = engine.fen;
    _pendingUserFen = null;

    if (_progressIndex >= puzzle.solutionUci.length) {
      _setBoardFen(_positionFen);
      _markPuzzleSolved(puzzle, recordStats: true);
      _stopChecking();
      setState(() {});
      _handlePuzzleSolved();
      return;
    }

    final replyUci = puzzle.solutionUci[_progressIndex];
    final replyToken = _checkToken;
    final replyProgressIndex = _progressIndex;
    Future.delayed(const Duration(milliseconds: 250), () {
      if (!mounted ||
          replyToken != _checkToken ||
          !identical(_puzzle, puzzle) ||
          !identical(_engine, engine) ||
          _progressIndex != replyProgressIndex) {
        return;
      }

      if (!_applyUci(engine, replyUci)) {
        _stopChecking();
        _snack("Internal error. New puzzle.");
        _queuePuzzleRefresh("internalerror3");
        return;
      }

      _progressIndex++;
      _positionFen = engine.fen;
      _setBoardFen(_positionFen);

      if (_progressIndex >= puzzle.solutionUci.length) {
        _markPuzzleSolved(puzzle, recordStats: true);
      }

      _stopChecking();
      setState(() {});
      if (_solved) {
        _handlePuzzleSolved();
      }
    });
  }

  void _recordSolved(int rating) {
    _statSolved += 1;
    _statBestRating = max(_statBestRating, rating);
    if (_attemptsThisPuzzle == 0) _statFirstTry += 1;
    unawaited(
      _saveStats().catchError((Object error, StackTrace stackTrace) {
        if (mounted) _snack("Couldn't save stats.");
      }),
    );
  }

  void _markPuzzleSolved(ChessPuzzle puzzle, {required bool recordStats}) {
    final wasSolved = _solved;
    _solved = true;
    _unlockAvailable = true;
    if (!wasSolved) {
      if (_extraPuzzleMode) {
        AppCrashlytics.logPuzzleSolved(
          puzzleType: "practice_puzzle",
          difficulty: _difficulty,
        );
        AppAnalytics.practicePuzzleSolved(
          difficulty: _difficulty,
        );
      } else {
        AppCrashlytics.logPuzzleSolved(
          puzzleType: "locked_app_puzzle",
          difficulty: _difficulty,
        );
        AppAnalytics.lockedAppPuzzleSolved(
          difficulty: _difficulty,
        );
      }
    }
    if (recordStats) {
      _recordSolved(puzzle.rating);
    }
  }

  void _handlePuzzleSolved() {
    if (!mounted) return;

    if (_extraPuzzleMode) {
      _snack("Solved. Loading next puzzle…");
      unawaited(_loadExtraPuzzle());
      return;
    }

    if (_returnHomeAfterEditPuzzleSolve) {
      _returnHomeAfterEditPuzzleSolve = false;
      _puzzleSolvedChoiceShown = true;
      _extraPuzzleMode = false;
      _goHome();
      _scheduleLaunchableAppsPrefetch(reason: "edit_puzzle_solved");
      _snack("Puzzle solved. You can edit locked apps now.");
      return;
    }

    if (_puzzleSolvedChoiceShown || _puzzleSolvedDialogShowing) {
      if (!_puzzleSolvedDialogShowing) {
        _snack("Puzzle solved");
      }
      return;
    }
    _puzzleSolvedChoiceShown = true;
    unawaited(_showPuzzleSolvedDialog());
  }

  Future<void> _loadExtraPuzzle() async {
    try {
      await _showNextPuzzleForCurrentDifficulty(reason: "extra");
    } catch (_) {
      if (mounted) _snack("Puzzle load failed.");
    }
  }

  Future<void> _showPuzzleSolvedDialog() async {
    if (_puzzleSolvedDialogShowing || !mounted) return;
    _puzzleSolvedDialogShowing = true;
    AppAnalytics.puzzleSolvedPopupShown();

    final choice = await showDialog<_PuzzleSolvedChoice>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Puzzle solved"),
        content: const Text(
          "You can now unlock your apps for some time but we encourage you "
          "to solve more puzzles to improve your chess faster.",
        ),
        actions: [
          TextButton(
            onPressed: () {
              AppAnalytics.puzzleSolvedUnlockAppsTapped();
              Navigator.pop(ctx, _PuzzleSolvedChoice.unlockApps);
            },
            child: const Text("Unlock apps"),
          ),
          FilledButton(
            onPressed: () {
              AppAnalytics.solveMorePuzzlesTapped();
              AppAnalytics.puzzleSolvedSolveMoreTapped();
              Navigator.pop(ctx, _PuzzleSolvedChoice.solveMore);
            },
            child: const Text("Solve more puzzles"),
          ),
        ],
      ),
    );

    if (!mounted) return;
    _puzzleSolvedDialogShowing = false;

    if (choice == _PuzzleSolvedChoice.solveMore) {
      setState(() => _extraPuzzleMode = true);
      await _loadExtraPuzzle();
    } else if (choice == _PuzzleSolvedChoice.unlockApps) {
      AppAnalytics.unlockAppsButtonTapped();
      _extraPuzzleMode = false;
      _prepareFreshPuzzleOnNextOpen();
      _goHome();
    }
  }

  // =========================
  // Hint/Skip ads
  // =========================
  String get _rewardedAdUnitId {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final configuredIos = _configuredIosRewardedAdUnitId.trim();
      if (configuredIos.isNotEmpty) {
        return configuredIos;
      }

      final configured = _configuredRewardedAdUnitId.trim();
      if (configured.isNotEmpty) {
        return configured;
      }

      return _iosDefaultRewardedAdUnitId;
    }

    final configuredAndroid = _configuredAndroidRewardedAdUnitId.trim();
    if (configuredAndroid.isNotEmpty) {
      return configuredAndroid;
    }

    final configured = _configuredRewardedAdUnitId.trim();
    if (configured.isNotEmpty) {
      return configured;
    }

    return _androidDefaultRewardedAdUnitId;
  }

  String get _rewardedAdUnitSource {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      if (_configuredIosRewardedAdUnitId.trim().isNotEmpty) {
        return "ios-dart-define";
      }
      if (_configuredRewardedAdUnitId.trim().isNotEmpty) {
        return "shared-dart-define";
      }
      return "ios-default";
    }

    if (defaultTargetPlatform == TargetPlatform.android &&
        _configuredAndroidRewardedAdUnitId.trim().isNotEmpty) {
      return "android-dart-define";
    }
    if (_configuredRewardedAdUnitId.trim().isNotEmpty) {
      return "shared-dart-define";
    }
    return "android-default";
  }

  String get _rewardedPlatformLabel {
    if (defaultTargetPlatform == TargetPlatform.iOS) return "ios";
    if (defaultTargetPlatform == TargetPlatform.android) return "android";
    return defaultTargetPlatform.name;
  }

  bool get _hasUsableRewardedAdUnitId => _isValidAdUnitId(_rewardedAdUnitId);

  bool _isValidAdUnitId(String value) =>
      value.startsWith("ca-app-pub-") && value.contains("/");

  bool get _rewardedPlatformSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool get _rewardedPuzzleActionAvailable =>
      _puzzle != null &&
      !_solved &&
      !_loadingPuzzle &&
      !_isChecking &&
      !_rewardedActionInProgress &&
      !_rewardedDialogShowing &&
      !_rewardedAdShowing;

  bool get _hintAvailable => _rewardedPuzzleActionAvailable;

  bool get _skipAvailable => _rewardedPuzzleActionAvailable;

  Future<void> _onHintPressed() async {
    if (!_hintAvailable) return;
    AppAnalytics.hintButtonTapped();
    await _showRewardedActionDialog(
      action: _RewardedPuzzleAction.hint,
      title: "Get a hint",
      message: "Need a little help?\n\n"
          "Watching an ad will show which piece to move.\n\n"
          "We added this ad so you don’t take hints too quickly. Solving the puzzle yourself is what actually improves your chess.",
      onRewardEarned: _grantHintReward,
    );
  }

  Future<void> _onSkipPressed() async {
    if (!_skipAvailable) return;
    AppAnalytics.skipButtonTapped();
    await _showRewardedActionDialog(
      action: _RewardedPuzzleAction.skip,
      title: "Skip puzzle",
      message: "Want to skip this puzzle?\n\n"
          "Watching an ad will load a new puzzle.\n\n"
          "We added this ad to encourage you to try a little harder before skipping. That effort is what helps you get better at chess.",
      onRewardEarned: _grantSkipReward,
    );
  }

  Future<void> _showRewardedActionDialog({
    required _RewardedPuzzleAction action,
    required String title,
    required String message,
    required VoidCallback onRewardEarned,
  }) async {
    if (_rewardedDialogShowing) return;
    _rewardedDialogShowing = true;
    if (mounted) setState(() {});

    var watchBusy = false;
    String? errorText;

    try {
      _logRewardedDialogShown(action);
      final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => StatefulBuilder(
              builder: (ctx, setDialogState) => AlertDialog(
                title: Text(title),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(message),
                    if (errorText != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        errorText!,
                        style: TextStyle(
                          color: Theme.of(ctx).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      _logRewardedDialogCancelTapped(action);
                      Navigator.pop(ctx, false);
                    },
                    child: const Text("Cancel"),
                  ),
                  FilledButton(
                    onPressed: watchBusy
                        ? null
                        : () async {
                            _logRewardedDialogWatchAdTapped(action);
                            setDialogState(() {
                              watchBusy = true;
                              errorText = null;
                            });

                            final ready = await _prepareRewardedAdForWatch();
                            if (!mounted || !ctx.mounted) return;

                            if (!ready) {
                              _logRewardedAdFailed(
                                action,
                                adResult: "not_available",
                              );
                              setDialogState(() {
                                watchBusy = false;
                                errorText = _rewardedAdUnavailableMessage(
                                  _lastRewardedAdLoadError,
                                  showError: _lastRewardedAdShowError,
                                );
                              });
                              return;
                            }

                            Navigator.pop(ctx, true);
                          },
                    child: watchBusy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text("Watch"),
                  ),
                ],
              ),
            ),
          ) ??
          false;

      if (!confirmed || !mounted) return;

      setState(() => _rewardedActionInProgress = true);
      final result = await _showRewardedAd(
        action: action,
        onRewardEarned: onRewardEarned,
      );
      if (!mounted) return;
      setState(() => _rewardedActionInProgress = false);

      switch (result) {
        case _RewardedAdResult.completed:
        case _RewardedAdResult.dismissedAfterReward:
          return;
        case _RewardedAdResult.dismissedBeforeReward:
          _logRewardedAdFailed(action, adResult: "cancelled");
          return;
        case _RewardedAdResult.unavailable:
          _logRewardedAdFailed(action, adResult: "not_available");
          _snack(
            _rewardedAdUnavailableMessage(
              _lastRewardedAdLoadError,
              showError: _lastRewardedAdShowError,
            ),
          );
        case _RewardedAdResult.failedToShow:
          _logRewardedAdFailed(action, adResult: "failed");
          _snack(
            _rewardedAdUnavailableMessage(
              _lastRewardedAdLoadError,
              showError: _lastRewardedAdShowError,
            ),
          );
      }
    } finally {
      _rewardedDialogShowing = false;
      if (mounted) setState(() {});
    }
  }

  void _grantHintReward() {
    AppAnalytics.hintRewardedAdCompleted();
    final puzzle = _puzzle;
    if (puzzle == null) return;
    if (_progressIndex >= puzzle.solutionUci.length) return;

    final uci = puzzle.solutionUci[_progressIndex];
    if (uci.length < 4) return;

    _blinkHintFromSquare(uci.substring(0, 2));
  }

  void _grantSkipReward() {
    AppAnalytics.skipRewardedAdCompleted();
    AppAnalytics.puzzleSkippedAfterAd();
    _snack("Skipped. New puzzle.");
    _queuePuzzleRefresh("skip");
  }

  void _logRewardedDialogShown(_RewardedPuzzleAction action) {
    switch (action) {
      case _RewardedPuzzleAction.hint:
        AppAnalytics.hintDialogShown();
      case _RewardedPuzzleAction.skip:
        AppAnalytics.skipDialogShown();
    }
  }

  void _logRewardedDialogWatchAdTapped(_RewardedPuzzleAction action) {
    switch (action) {
      case _RewardedPuzzleAction.hint:
        AppAnalytics.hintDialogWatchAdTapped();
      case _RewardedPuzzleAction.skip:
        AppAnalytics.skipDialogWatchAdTapped();
    }
  }

  void _logRewardedDialogCancelTapped(_RewardedPuzzleAction action) {
    switch (action) {
      case _RewardedPuzzleAction.hint:
        AppAnalytics.hintDialogCancelTapped();
      case _RewardedPuzzleAction.skip:
        AppAnalytics.skipDialogCancelTapped();
    }
  }

  void _logRewardedAdFailed(
    _RewardedPuzzleAction action, {
    required String adResult,
  }) {
    switch (action) {
      case _RewardedPuzzleAction.hint:
        AppAnalytics.hintRewardedAdFailed(adResult);
      case _RewardedPuzzleAction.skip:
        AppAnalytics.skipRewardedAdFailed(adResult);
    }
  }

  Future<bool> _prepareRewardedAdForWatch() async {
    final ad = _rewardedAd ?? await _loadRewardedAd(reason: "watch_button");
    if (ad == null) {
      _debugRewarded(
        "rewarded watch unavailable; "
        "lastLoadError=${_describeRewardedLoadError(_lastRewardedAdLoadError)} "
        "lastShowError=${_describeRewardedAdError(_lastRewardedAdShowError)}",
      );
    }
    return ad != null;
  }

  Future<RewardedAd?> _loadRewardedAd({
    required String reason,
    bool ignoreRetryDelay = false,
  }) {
    if (!_rewardedPlatformSupported) {
      _debugRewarded("rewarded load skipped; unsupported platform");
      _lastRewardedAdLoadError = null;
      return Future.value(null);
    }

    _debugRewardedConfigurationIfNeeded();

    if (!_hasUsableRewardedAdUnitId) {
      _debugInvalidRewardedAdUnitId();
      _lastRewardedAdLoadError = null;
      return Future.value(null);
    }

    final cachedAd = _rewardedAd;
    if (cachedAd != null) {
      _debugRewarded(
        "rewarded load skipped; ad already loaded "
        "reason=$reason adUnitId=$_rewardedAdUnitId",
      );
      return Future.value(cachedAd);
    }

    final inFlight = _rewardedAdLoadFuture;
    if (inFlight != null) {
      _debugRewarded(
        "rewarded load skipped; request already in flight "
        "reason=$reason adUnitId=$_rewardedAdUnitId",
      );
      return inFlight;
    }

    final nextRetryAt = _nextRewardedRetryAt;
    if (!ignoreRetryDelay && nextRetryAt != null) {
      final remaining = nextRetryAt.difference(DateTime.now());
      if (remaining > Duration.zero) {
        _scheduleRewardedRetry(remaining, reason: "retry_wait:$reason");
        _debugRewarded(
          "rewarded load skipped; retry backoff active for "
          "${remaining.inSeconds}s adUnitId=$_rewardedAdUnitId",
        );
        return Future.value(null);
      }
    }

    final completer = Completer<RewardedAd?>();
    _rewardedAdLoadFuture = completer.future;
    _cancelRewardedRetryTimer();
    _nextRewardedRetryAt = null;
    _lastRewardedAdShowError = null;

    _debugRewarded(
      "rewarded load started; platform=$_rewardedPlatformLabel "
      "source=$_rewardedAdUnitSource reason=$reason "
      "adUnitId=$_rewardedAdUnitId",
    );

    RewardedAd.load(
      adUnitId: _rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          if (!mounted) {
            _rewardedAdLoadFuture = null;
            ad.dispose();
            if (!completer.isCompleted) completer.complete(null);
            return;
          }
          _rewardedAd = ad;
          _lastRewardedAdLoadError = null;
          _lastRewardedAdShowError = null;
          _rewardedAdLoadFuture = null;
          _nextRewardedRetryAt = null;
          _rewardedRetryDelay = _rewardedInitialRetryDelay;
          _debugRewarded(
            "rewarded loaded; adUnitId=$_rewardedAdUnitId "
            "responseInfo=${ad.responseInfo}",
          );
          if (!completer.isCompleted) completer.complete(ad);
          if (mounted) setState(() {});
        },
        onAdFailedToLoad: (error) {
          _lastRewardedAdLoadError = error;
          _rewardedAdLoadFuture = null;
          _debugRewardedLoadError("rewarded failed to load", error);
          if (!completer.isCompleted) completer.complete(null);
          if (mounted) setState(() {});
          final delayBeforeNextAttempt = _rewardedRetryDelay;
          _nextRewardedRetryAt = DateTime.now().add(delayBeforeNextAttempt);
          _scheduleRewardedRetry(
            delayBeforeNextAttempt,
            reason: "load_failed",
          );
          final nextRetrySeconds = _rewardedRetryDelay.inSeconds * 2;
          final cappedRetrySeconds =
              nextRetrySeconds > _rewardedMaxRetryDelay.inSeconds
                  ? _rewardedMaxRetryDelay.inSeconds
                  : nextRetrySeconds;
          _rewardedRetryDelay = Duration(seconds: cappedRetrySeconds);
        },
      ),
    );

    return completer.future;
  }

  void _preloadRewardedAd() {
    if (!_rewardedPlatformSupported) return;
    _debugRewardedConfigurationIfNeeded();
    if (!_hasUsableRewardedAdUnitId) {
      _debugInvalidRewardedAdUnitId();
      return;
    }
    if (_rewardedAd != null || _rewardedAdLoadFuture != null) {
      _debugRewarded(
        "rewarded preload skipped; ad already loaded/loading "
        "adUnitId=$_rewardedAdUnitId",
      );
      return;
    }
    if (_rewardedRetryTimer != null) {
      _debugRewarded(
        "rewarded preload skipped; retry already scheduled "
        "adUnitId=$_rewardedAdUnitId",
      );
      return;
    }
    unawaited(_loadRewardedAd(reason: "preload"));
  }

  Future<_RewardedAdResult> _showRewardedAd({
    required _RewardedPuzzleAction action,
    required VoidCallback onRewardEarned,
  }) async {
    final ad = _rewardedAd ?? await _loadRewardedAd(reason: "show");
    if (ad == null) {
      _debugRewarded(
        "rewarded show unavailable before presentation; "
        "action=${_rewardedActionLogName(action)} "
        "lastLoadError=${_describeRewardedLoadError(_lastRewardedAdLoadError)}",
      );
      _preloadRewardedAd();
      return _RewardedAdResult.unavailable;
    }

    _rewardedAd = null;
    _lastRewardedAdLoadError = null;
    _lastRewardedAdShowError = null;

    if (mounted) {
      setState(() => _rewardedAdShowing = true);
    } else {
      _rewardedAdShowing = true;
    }

    final completer = Completer<_RewardedAdResult>();
    var rewardEarned = false;

    void finish(_RewardedAdResult result) {
      if (!completer.isCompleted) {
        completer.complete(result);
      }
      _rewardedAdShowing = false;
      if (mounted) setState(() {});
      _preloadRewardedAd();
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        _debugRewarded(
          "rewarded showed; action=${_rewardedActionLogName(action)} "
          "adUnitId=$_rewardedAdUnitId responseInfo=${ad.responseInfo}",
        );
      },
      onAdDismissedFullScreenContent: (ad) {
        _debugRewarded(
          "rewarded dismissed; action=${_rewardedActionLogName(action)} "
          "rewardEarned=$rewardEarned adUnitId=$_rewardedAdUnitId "
          "responseInfo=${ad.responseInfo}",
        );
        ad.dispose();
        finish(
          rewardEarned
              ? _RewardedAdResult.dismissedAfterReward
              : _RewardedAdResult.dismissedBeforeReward,
        );
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        _lastRewardedAdShowError = error;
        _debugRewardedAdError(
          "rewarded failed to show; action=${_rewardedActionLogName(action)}",
          error,
          responseInfo: ad.responseInfo,
        );
        ad.dispose();
        finish(_RewardedAdResult.failedToShow);
      },
    );

    try {
      ad.show(
        onUserEarnedReward: (ad, reward) {
          if (rewardEarned) return;
          rewardEarned = true;
          _debugRewarded(
            "rewarded earned; action=${_rewardedActionLogName(action)} "
            "type=${reward.type} amount=${reward.amount} "
            "adUnitId=$_rewardedAdUnitId responseInfo=${ad.responseInfo}",
          );
          onRewardEarned();
          _preloadRewardedAd();
          if (!completer.isCompleted) {
            completer.complete(_RewardedAdResult.completed);
          }
        },
      );
    } catch (error) {
      _debugRewarded(
        "rewarded show threw; action=${_rewardedActionLogName(action)} "
        "adUnitId=$_rewardedAdUnitId error=$error",
      );
      ad.dispose();
      finish(_RewardedAdResult.failedToShow);
    }

    return completer.future;
  }

  void _disposeRewardedAd() {
    _rewardedAd?.dispose();
    _rewardedAd = null;
    _rewardedAdLoadFuture = null;
    _cancelRewardedRetryTimer();
    _nextRewardedRetryAt = null;
  }

  void _scheduleRewardedRetry(Duration delay, {required String reason}) {
    if (!mounted ||
        !_rewardedPlatformSupported ||
        !_hasUsableRewardedAdUnitId ||
        _rewardedAd != null ||
        _rewardedAdLoadFuture != null) {
      _debugRewarded(
        "rewarded retry skipped; reason=$reason adUnitId=$_rewardedAdUnitId",
      );
      return;
    }

    if (_rewardedRetryTimer != null) {
      _debugRewarded(
        "rewarded retry skipped; retry already scheduled "
        "reason=$reason adUnitId=$_rewardedAdUnitId",
      );
      return;
    }

    _debugRewarded(
      "rewarded retry scheduled in ${delay.inSeconds}s; "
      "reason=$reason adUnitId=$_rewardedAdUnitId",
    );
    _rewardedRetryTimer = Timer(delay, () {
      _rewardedRetryTimer = null;
      if (!mounted) return;
      unawaited(
        _loadRewardedAd(
          reason: "retry_timer",
          ignoreRetryDelay: true,
        ),
      );
    });
  }

  void _cancelRewardedRetryTimer() {
    _rewardedRetryTimer?.cancel();
    _rewardedRetryTimer = null;
  }

  void _debugInvalidRewardedAdUnitId() {
    if (_loggedInvalidRewardedAdUnitId) return;
    _loggedInvalidRewardedAdUnitId = true;
    _debugRewarded(
      "rewarded ad unit id is missing or invalid; use an ad unit id like "
      "ca-app-pub-.../... and not the app id ca-app-pub-...~...",
    );
  }

  void _debugRewardedConfigurationIfNeeded() {
    if (_loggedRewardedConfiguration) return;
    _loggedRewardedConfiguration = true;

    _debugRewarded(
      "rewarded configuration; platform=$_rewardedPlatformLabel "
      "source=$_rewardedAdUnitSource release=$kReleaseMode "
      "adUnitId=$_rewardedAdUnitId",
    );

    if (defaultTargetPlatform == TargetPlatform.iOS &&
        kReleaseMode &&
        _configuredIosRewardedAdUnitId.trim().isEmpty &&
        _configuredRewardedAdUnitId.trim().isEmpty) {
      _debugRewarded(
        "release iOS is using the default iOS rewarded ad unit id. "
        "Pass "
        "CHESSUNLOCK_IOS_REWARDED_AD_UNIT_ID.",
      );
    }
  }

  String _rewardedActionLogName(_RewardedPuzzleAction action) {
    switch (action) {
      case _RewardedPuzzleAction.hint:
        return "hint";
      case _RewardedPuzzleAction.skip:
        return "skip";
    }
  }

  void _debugRewarded(String message) {
    debugPrint("[ads][rewarded] $message");
  }

  void _debugRewardedLoadError(String prefix, LoadAdError error) {
    _debugRewarded(
      "$prefix; adUnitId=$_rewardedAdUnitId "
      "error.code=${error.code} "
      "error.domain=${error.domain} "
      "error.message=${error.message} "
      "error.responseInfo=${error.responseInfo}",
    );
  }

  void _debugRewardedAdError(
    String prefix,
    AdError error, {
    ResponseInfo? responseInfo,
  }) {
    _debugRewarded(
      "$prefix; adUnitId=$_rewardedAdUnitId "
      "error.code=${error.code} "
      "error.domain=${error.domain} "
      "error.message=${error.message} "
      "error.responseInfo=$responseInfo",
    );
  }

  String _describeRewardedLoadError(LoadAdError? error) {
    if (error == null) return "none";
    return "code=${error.code}, domain=${error.domain}, "
        "message=${error.message}, responseInfo=${error.responseInfo}";
  }

  String _describeRewardedAdError(AdError? error) {
    if (error == null) return "none";
    return "code=${error.code}, domain=${error.domain}, "
        "message=${error.message}";
  }

  String _rewardedAdUnavailableMessage(
    LoadAdError? loadError, {
    AdError? showError,
  }) {
    final AdError? error = loadError ?? showError;
    if (error == null) {
      if (defaultTargetPlatform == TargetPlatform.iOS &&
          kReleaseMode &&
          _configuredIosRewardedAdUnitId.trim().isEmpty &&
          _configuredRewardedAdUnitId.trim().isEmpty) {
        return "Ad setup is incomplete for iOS.";
      }
      return "Ad is not ready yet. Please try again in a moment.";
    }

    final message = error.message.toLowerCase();
    final domain = error.domain.toLowerCase();

    if (error.code == 2 ||
        message.contains("network") ||
        domain.contains("network")) {
      return "Ad could not load because of a network issue. Please try again.";
    }

    if (error.code == 3 ||
        message.contains("no fill") ||
        message.contains("no ad")) {
      return "No ad is available right now. Please try again later.";
    }

    if (error.code == 1 ||
        message.contains("invalid") ||
        message.contains("ad unit") ||
        message.contains("application identifier") ||
        message.contains("consent")) {
      return defaultTargetPlatform == TargetPlatform.iOS
          ? "Ad setup is incomplete for iOS."
          : "Ad setup needs attention.";
    }

    return "Ad could not load right now. Please try again later.";
  }

  void _blinkHintFromSquare(String fromSquare) {
    _hintBlinkTimer?.cancel();
    _hintBlinkTimer = null;
    _hintFromSquare = fromSquare;
    _hintBlinkOn = true;
    if (mounted) setState(() {});
  }

  void _clearHintHighlight({required bool notify}) {
    _hintBlinkTimer?.cancel();
    _hintBlinkTimer = null;

    final hadHint = _hintFromSquare != null || _hintBlinkOn;
    _hintFromSquare = null;
    _hintBlinkOn = false;

    if (notify && hadHint && mounted) {
      setState(() {});
    }
  }

  // =========================
  // Chess helpers
  // =========================
  bool _applyUci(ch.Chess game, String uci) {
    if (uci.length < 4) return false;
    final from = uci.substring(0, 2);
    final to = uci.substring(2, 4);
    final promo = (uci.length >= 5) ? uci[4].toLowerCase() : null;

    try {
      final dynamic result = game.move({
        'from': from,
        'to': to,
        if (promo != null) 'promotion': promo,
      });
      return result != null;
    } catch (_) {
      return false;
    }
  }

  // =========================
  // UI actions (break picker etc.)
  // =========================
  Future<void> _openUnlockAppsFlow() async {
    AppAnalytics.unlockAppsButtonTapped();
    _extraPuzzleMode = false;
    _goHome();
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    await _showBreakTimePicker();
  }

  void _openPracticePuzzleFromHome() {
    AppAnalytics.solveMorePuzzlesTapped();
    _extraPuzzleMode = true;
    _goPuzzle();
  }

  Widget _bottomSheetBody(BuildContext ctx, Widget child) {
    final padding = MediaQuery.of(ctx).padding;
    final insets = MediaQuery.of(ctx).viewInsets;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: max(16, padding.bottom) + insets.bottom,
        ),
        child: SingleChildScrollView(child: child),
      ),
    );
  }

  Future<void> _showBreakTimePicker() async {
    if (!_canUnlockApps) {
      _snack("Solve the puzzle first.");
      _goPuzzle();
      return;
    }

    if (_lockEnabled == false && _indefiniteUnlock) {
      _snack("Lock is off indefinitely. Turn it ON in Settings.");
      _goSettings();
      return;
    }

    const minUnlockMinutes = 1;
    const maxUnlockMinutes = 15;
    var selected = 10.clamp(minUnlockMinutes, maxUnlockMinutes).toInt();

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;

        return _bottomSheetBody(
          ctx,
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              OverflowBar(
                alignment: MainAxisAlignment.spaceBetween,
                overflowAlignment: OverflowBarAlignment.end,
                spacing: 8,
                overflowSpacing: 8,
                children: [
                  Text(
                    "Choose unlock time",
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("Cancel"),
                  ),
                  FilledButton(
                    onPressed: () async {
                      AppAnalytics.unlockDurationSelected(selected);
                      Navigator.pop(ctx);
                      final saved = await _unlockForMinutes(selected);
                      if (!mounted) return;
                      if (saved) {
                        AppAnalytics.unlockStarted(selected);
                        _snack("Apps unlocked for $selected minutes.");
                      }
                    },
                    child: const Text("Start"),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(18),
                  border:
                      Border.all(color: cs.outlineVariant.withOpacity(0.45)),
                ),
                height: 180,
                child: _UnlockDurationWheelPicker(
                  minMinutes: minUnlockMinutes,
                  maxMinutes: maxUnlockMinutes,
                  initialMinutes: selected,
                  onChanged: (minutes) => selected = minutes,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "How long should your locked apps stay open?",
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );
  }

  Future<bool> _confirmRelock() async {
    return (await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Turn lock on?"),
            content: const Text("You’ll need to solve again to unlock apps."),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("Cancel"),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text("Turn on"),
              ),
            ],
          ),
        )) ??
        false;
  }

  Future<void> _onLockToggleFromSettings(bool nextValue) async {
    if (nextValue == true) {
      if (_isUnlocked) {
        final ok = await _confirmRelock();
        if (!ok) return;
      }
      final saved = await _relockNow(resetPuzzle: true);
      if (!mounted) return;
      if (saved) {
        AppAnalytics.lockStatusChanged(true);
        AppAnalytics.appLockResumed();
        _snack("Lock ON");
      }
      return;
    }

    if (!_canUnlockApps) {
      _snack("Solve the puzzle first.");
      _goPuzzle();
      return;
    }

    await _showDisableOptionsSheet();
  }

  Future<void> _showDisableOptionsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;

        return _bottomSheetBody(
          ctx,
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      "Turn lock off",
                      style: Theme.of(ctx).textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(Icons.warning_amber_rounded, color: cs.error),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                "You’ll have to manually turn it back on in Settings.",
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              ActionTile(
                title: "Turn off for 24 hours",
                subtitle: "Auto re-locks after 24h",
                icon: Icons.schedule_rounded,
                onTap: () async {
                  Navigator.pop(ctx);
                  final saved = await _unlockFor24h();
                  if (!mounted) return;
                  if (saved) {
                    AppAnalytics.lockStatusChanged(false);
                    AppAnalytics.appLockPaused(unlockDurationMinutes: 1440);
                    _snack("Unlocked for 24 hours.");
                  }
                },
              ),
              const SizedBox(height: 8),
              ActionTile(
                title: "Turn off until I turn it back on",
                subtitle: "No auto re-lock",
                icon: Icons.power_settings_new_rounded,
                onTap: () async {
                  Navigator.pop(ctx);
                  final ok = await showDialog<bool>(
                        context: context,
                        builder: (d) => AlertDialog(
                          title: const Text("Turn off indefinitely?"),
                          content: const Text(
                            "Apps won’t be locked until you manually turn Lock ON again.",
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(d, false),
                              child: const Text("Cancel"),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(d, true),
                              child: const Text("Turn off"),
                            ),
                          ],
                        ),
                      ) ??
                      false;
                  if (!mounted || !ok) return;
                  final saved = await _unlockForMinutes(null);
                  if (!mounted) return;
                  if (saved) {
                    AppAnalytics.lockStatusChanged(false);
                    AppAnalytics.appLockPaused();
                    _snack("Lock turned off.");
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openDifficultyPicker() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return _bottomSheetBody(
          ctx,
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              OverflowBar(
                alignment: MainAxisAlignment.spaceBetween,
                overflowAlignment: OverflowBarAlignment.end,
                spacing: 8,
                overflowSpacing: 8,
                children: [
                  Text(
                    "Puzzle difficulty",
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("Close"),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ..._difficultyOptions.map((d) {
                final isSel = d == _difficulty;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(getDifficultyDisplayName(d)),
                  trailing: isSel ? const Icon(Icons.check_rounded) : null,
                  onTap: () => Navigator.pop(ctx, d),
                );
              }),
            ],
          ),
        );
      },
    );

    if (!mounted || selected == null) return;
    final previousDifficulty = _difficulty;
    setState(() => _difficulty = selected);
    await _saveDifficulty();
    if (selected != previousDifficulty) {
      AppAnalytics.puzzleDifficultyChanged(selected);
    }
    await _showNextPuzzleForCurrentDifficulty(reason: "difficulty");
  }

  Future<void> _openAppPicker({bool requireSolved = true}) async {
    if (!_appLock.isSupported) {
      _snack(_appLock.unsupportedMessage);
      return;
    }

    final selectionSummary = await _refreshAppLockSelectionSummary(
      notify: false,
    );
    final editingExistingLocks = selectionSummary?.hasSelection ??
        await _appLock.hasConfiguredLocks(_lockedPackages);
    if (requireSolved && editingExistingLocks && !_canUnlockApps) {
      _returnHomeAfterEditPuzzleSolve = true;
      _snack("Solve a puzzle to edit locked apps.");
      _goPuzzle();
      return;
    }

    if (_appLock.usesNativeAppPicker) {
      await _openNativeAppPicker();
      return;
    }

    _scheduleLaunchableAppsPrefetch(reason: "before_picker");

    final selected = await _sanitizeLockedPackages(_lockedPackages);
    if (!mounted) return;

    final updated = await Navigator.push<Set<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => AppSelectionPage(
          selected: selected,
          editingDisabled: false,
          fetchApps: _getLaunchableAppsRaw,
          fetchIcons: _getLockedAppIconsRaw,
        ),
      ),
    );

    if (!mounted || updated == null) return;

    final sanitized = await _sanitizeLockedPackages(updated);
    if (!mounted) return;

    setState(() {
      _lockedPackages = sanitized;
      _retainLockedAppIcons(sanitized);
    });
    unawaited(_persistLockedAppIconCache(sanitized));
    await _saveLockedPackages();
    AppAnalytics.lockedAppsSelectionSaved(sanitized.length);
    await _completeOnboarding();
    await _ensureAppLockReadyIfNeeded();
    _scheduleDeferredLockedIconPrefetch();
    _snack("Apps locked.");
  }

  Future<void> _openNativeAppPicker() async {
    final result = await _appLock.openNativeAppPicker();
    if (!mounted || result == null) return;

    final errorMessage = result.errorMessage;
    if (!result.completed) {
      if (errorMessage != null && errorMessage.isNotEmpty) {
        _snack(errorMessage);
      }
      return;
    }

    setState(() {
      _appLockSelectionSummary = result;
      _appLockSelectionPreviewRevision++;
    });

    AppAnalytics.lockedAppsSelectionSaved(result.totalCount);
    await _completeOnboarding();
    await _ensureAppLockReadyIfNeeded();
    if (!mounted) return;

    if (result.totalCount == 0) {
      _snack("No apps selected.");
    } else {
      _snack("Apps locked.");
    }
  }

  static const String _privacyPolicyUrl =
      "https://aimlessoulapps.github.io/chessunlock-legal/";
  static const String _feedbackEmail = "aimlessoul.apps@gmail.com";

  Future<void> _onPrivacyPolicy() async {
    AppAnalytics.privacyPolicyTapped();
    try {
      final uri = Uri.parse(_privacyPolicyUrl);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) _snack("Couldn’t open Privacy Policy.");
    } catch (_) {
      _snack("Couldn’t open Privacy Policy.");
    }
  }

  Future<void> _onRateApp() async {
    AppAnalytics.rateAppTapped();
    // ✅ Correct logic: until the app exists on Play, there’s nothing to open.
    // Later (after Internal/Closed testing upload), we can wire this to Play
    // or use the official in-app review flow.
    _snack("Rating will be available after ChessUnlock is on Google Play.");
  }

  Future<void> _onFeedback() async {
    AppAnalytics.feedbackOpened();

    final uri = Uri(
      scheme: "mailto",
      path: _feedbackEmail,
      queryParameters: const {
        "subject": "ChessUnlock Feedback",
        "body": "We value your feedback.\n"
            "Please let us know what we can improve.",
      },
    );

    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        _snack("Couldn't open email app. Please email $_feedbackEmail.");
      }
    } catch (_) {
      _snack("Couldn't open email app. Please email $_feedbackEmail.");
    }
  }

  Future<void> _onThemeModeChangedFromSettings(AppThemeMode mode) async {
    final changed = mode != widget.themeMode;
    await widget.onThemeModeChanged(mode);
    if (changed) {
      AppAnalytics.themeChanged(
        switch (mode) {
          AppThemeMode.dark => "dark",
          AppThemeMode.light => "light",
          AppThemeMode.system => "system",
        },
      );
    }
  }

  void _selectTab(int index) {
    final previousTab = _tab;
    if (_tab == 1 && index != 1) {
      _extraPuzzleMode = false;
    }
    setState(() => _tab = index);
    if (index != previousTab) {
      _logScreenViewedForTab(index);
    }
    if (index == 1 && previousTab != 1) {
      _ensureFreshPuzzleWhenOpeningPuzzleTab();
    }
  }

  void _goHome() => _selectTab(0);
  void _goPuzzle() => _selectTab(1);
  void _goSettings() => _selectTab(2);

  void _logScreenViewedForTab(int index) {
    switch (index) {
      case 0:
        AppAnalytics.homeScreenViewed();
      case 1:
        AppAnalytics.puzzleScreenViewed();
      case 2:
        AppAnalytics.settingsScreenViewed();
    }
  }

  // =========================
  // UI
  // =========================
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final timedUnlockActive =
        !_lockEnabled && !_indefiniteUnlock && _unlockRemaining > Duration.zero;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: IndexedStack(
          index: _tab,
          children: [
            HomeTab(
              active: _tab == 0,
              lockEnabled: _lockEnabled,
              indefiniteUnlock: _indefiniteUnlock,
              unlockRemaining: _unlockRemaining,
              lockedPackages: _lockedPackages,
              lockedSelectionCount: _lockedSelectionCount,
              lockedSelectionSummaryLines: _lockedSelectionSummaryLines,
              lockedSelectionPreviewRevision: _appLockSelectionPreviewRevision,
              difficulty: _difficulty,
              solved: _canUnlockApps,
              timedUnlockActive: timedUnlockActive,
              statSolved: _statSolved,
              statBestRating: _statBestRating,
              accuracyPct: _accuracyPct,
              iconsByPkg: _iconsByPkg,
              onEditLockedApps: () {
                AppAnalytics.editLockedAppsTapped();
                unawaited(_openAppPicker());
              },
              showNativeSelectionPreview: _appLock.usesNativeAppPicker,
              onBreakTime: () {
                if (!_canUnlockApps) {
                  AppAnalytics.solvePuzzleToUnlockTapped();
                }
                unawaited(_showBreakTimePicker());
              },
              onSolveMorePuzzles: _openPracticePuzzleFromHome,
              onOpenDifficulty: () {
                _goSettings();
                _snack("Change difficulty in Settings.");
              },
            ),
            PuzzleTab(
              active: _tab == 1,
              puzzle: _puzzle,
              loading: _loadingPuzzle,
              loadError: _loadError,
              sideToMoveLabel: _sideToMoveLabel,
              solved: _solved,
              canUnlockApps: _canUnlockApps,
              canUserMove: _canUserMove,
              userPlaysBlack: _userPlaysBlack,
              isChecking: _isChecking,
              hintEnabled: _hintAvailable,
              onHint: _onHintPressed,
              skipEnabled: _skipAvailable,
              onSkip: _onSkipPressed,
              onUnlockApps: () {
                unawaited(_openUnlockAppsFlow());
              },
              hintFromSquare: _hintFromSquare,
              hintBlinkOn: _hintBlinkOn,
              boardController: _boardController,
            ),
            SettingsTab(
              active: _tab == 2,
              lockEnabled: _lockEnabled,
              indefiniteUnlock: _indefiniteUnlock,
              unlockRemaining: _unlockRemaining,
              difficulty: _difficulty,
              themeMode: widget.themeMode,
              onThemeModeChanged: _onThemeModeChangedFromSettings,
              onLockToggle: _onLockToggleFromSettings,
              onOpenDifficulty: _openDifficultyPicker,
              onPrivacyPolicy: _onPrivacyPolicy,
              onFeedback: _onFeedback,
              onRateApp: _onRateApp,
            ),
          ],
        ),
      ),
      bottomNavigationBar: PremiumNavBar(
        index: _tab,
        onChanged: _selectTab,
      ),
    );
  }
}

class _UnlockDurationWheelPicker extends StatelessWidget {
  const _UnlockDurationWheelPicker({
    required this.minMinutes,
    required this.maxMinutes,
    required this.initialMinutes,
    required this.onChanged,
  });

  final int minMinutes;
  final int maxMinutes;
  final int initialMinutes;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final initialItem = (initialMinutes - minMinutes)
        .clamp(
          0,
          maxMinutes - minMinutes,
        )
        .toInt();

    return CupertinoTheme(
      data: CupertinoThemeData(
        brightness: Theme.of(context).brightness,
        textTheme: CupertinoTextThemeData(
          pickerTextStyle: TextStyle(
            color: cs.onSurface,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      child: CupertinoPicker(
        itemExtent: 42,
        magnification: 1.08,
        squeeze: 1.15,
        useMagnifier: true,
        scrollController: FixedExtentScrollController(
          initialItem: initialItem,
        ),
        onSelectedItemChanged: (i) => onChanged(minMinutes + i),
        children: List.generate(
          maxMinutes - minMinutes + 1,
          (i) => Center(child: Text("${minMinutes + i} min")),
        ),
      ),
    );
  }
}

enum _RewardedAdResult {
  completed,
  dismissedAfterReward,
  dismissedBeforeReward,
  unavailable,
  failedToShow,
}

enum _RewardedPuzzleAction {
  hint,
  skip,
}

enum _PuzzleSolvedChoice {
  solveMore,
  unlockApps,
}
