import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:firebase_core/firebase_core.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:advanced_chess_board/chess_board_controller.dart';
import 'package:chess/chess.dart' as ch;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' hide Uint8List;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' hide Uint8List;
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'services/analytics_service.dart';
import 'services/crashlytics_service.dart';
import 'services/lock_state_controller.dart';
import 'services/puzzle_queue_service.dart';
import 'services/stats_repository.dart';
import 'ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  AppCrashlytics.initializeErrorHandling();
  AppCrashlytics.logAppOpened();
  AppCrashlytics.runDebugCrashTestIfRequested();
  await _initializeMobileAds();
  final openPuzzleOnStart = await _consumeOpenPuzzleRequest();
  runApp(MyApp(initialTab: openPuzzleOnStart ? 1 : 0));
}

Future<void> _initializeMobileAds() async {
  if (kIsWeb ||
      (defaultTargetPlatform != TargetPlatform.android &&
          defaultTargetPlatform != TargetPlatform.iOS)) {
    return;
  }

  try {
    final status = await MobileAds.instance.initialize();
    debugPrint("[ads][init] Mobile Ads initialized: $status");
  } catch (error) {
    debugPrint("[ads][init] Mobile Ads initialization failed: $error");
    // Ads are optional; app startup should never depend on ad initialization.
  }
}

// Android native channel
const MethodChannel _platform = MethodChannel("chesslock/system");

Future<bool> _consumeOpenPuzzleRequest() async {
  try {
    return await _platform.invokeMethod<bool>("consumeOpenPuzzleRequest") ??
        false;
  } catch (_) {
    return false;
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
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await _prefsFuture;
    final raw = (prefs.getString(_kThemeMode) ?? "system").toLowerCase();
    _mode = switch (raw) {
      "dark" => AppThemeMode.dark,
      "light" => AppThemeMode.light,
      _ => AppThemeMode.system,
    };
    if (!mounted) return;
    setState(() => _loaded = true);
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
    const accent = Color(0xFF2FE6A8);

    final baseLight = ThemeData(
      useMaterial3: true,
      colorScheme:
          ColorScheme.fromSeed(seedColor: accent, brightness: Brightness.light),
    );

    final baseDark = ThemeData(
      useMaterial3: true,
      colorScheme:
          ColorScheme.fromSeed(seedColor: accent, brightness: Brightness.dark),
    );

    ThemeData polish(ThemeData t) {
      final tt = _safeScaleTextTheme(t.textTheme, 0.94);
      return t.copyWith(
        textTheme: tt,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
      );
    }

    return MaterialApp(
      title: "ChessUnlock",
      debugShowCheckedModeBanner: false,
      theme: polish(baseLight),
      darkTheme: polish(baseDark),
      themeMode: _themeMode,
      home: _loaded
          ? ChessLockShell(
              initialTab: widget.initialTab,
              themeMode: _mode,
              onThemeModeChanged: _setTheme,
            )
          : const SizedBox.shrink(),
    );
  }
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
/// ChessLockShell = app logic + state + platform calls
/// UI widgets live in ui.dart
///
class ChessLockShell extends StatefulWidget {
  final int initialTab;
  final AppThemeMode themeMode;
  final Future<void> Function(AppThemeMode mode) onThemeModeChanged;

  const ChessLockShell({
    super.key,
    this.initialTab = 0,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  @override
  State<ChessLockShell> createState() => _ChessLockShellState();
}

class _ChessLockShellState extends State<ChessLockShell>
    with WidgetsBindingObserver {
  late final Future<SharedPreferences> _prefsFuture =
      SharedPreferences.getInstance();
  late final LockStateController _lockState;
  late final StatsRepository _statsRepository;
  late final PuzzleQueueService _puzzleQueue;
  String? _ownPackageName;

  DateTime? get _unlockedUntil => _lockState.unlockedUntil;
  set _unlockedUntil(DateTime? value) => _lockState.unlockedUntil = value;

  bool get _indefiniteUnlock => _lockState.indefiniteUnlock;
  set _indefiniteUnlock(bool value) => _lockState.indefiniteUnlock = value;

  bool get _lockEnabled => _lockState.lockEnabled;
  set _lockEnabled(bool value) => _lockState.lockEnabled = value;

  Set<String> get _lockedPackages => _lockState.lockedPackages;
  set _lockedPackages(Set<String> value) => _lockState.lockedPackages = value;

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

  bool _onboardingDialogQueued = false;

  int _statSolved = 0;
  int _statBestRating = 0;
  int _statFirstTry = 0;

  // attempts per puzzle
  int _attemptsThisPuzzle = 0;

  // =========================
  // Hint + Skip ads
  // =========================
  static const String _testRewardedAdUnitId =
      "ca-app-pub-8108010703558411/1847579539";
  static const String _productionRewardedAdUnitId =
      "ca-app-pub-8108010703558411/1847579539";
  static const String _configuredRewardedAdUnitId = String.fromEnvironment(
    "CHESSUNLOCK_REWARDED_AD_UNIT_ID",
  );
  static const Duration _rewardedInitialRetryDelay = Duration(seconds: 30);
  static const Duration _rewardedMaxRetryDelay = Duration(minutes: 5);

  RewardedAd? _rewardedAd;
  Future<RewardedAd?>? _rewardedAdLoadFuture;
  LoadAdError? _lastRewardedAdLoadError;
  DateTime? _nextRewardedRetryAt;
  Duration _rewardedRetryDelay = _rewardedInitialRetryDelay;
  Timer? _rewardedRetryTimer;
  bool _rewardedAdShowing = false;
  bool _rewardedActionInProgress = false;
  bool _rewardedDialogShowing = false;
  bool _loggedInvalidRewardedAdUnitId = false;

  // Blink hint overlay
  String? _hintFromSquare;
  bool _hintBlinkOn = false;
  Timer? _hintBlinkTimer;

  // Tabs
  late int _tab; // 0 Home, 1 Puzzle, 2 Settings

  // Icons cache
  Map<String, Uint8List> _iconsByPkg = {};

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
    WidgetsBinding.instance.addObserver(this);

    _boardController.addListener(_onBoardChanged);

    _init();
    _preloadRewardedAd();

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
    await _prefetchIcons();
    await _ensureUsageAccessIfNeeded();
    await _openPuzzleFromOverlayRequestIfNeeded();
    await _maybeShowFirstLaunchOnboarding();

    // ✅ Show a puzzle instantly if queue has one, otherwise cached, otherwise network.
    await _showNextPuzzleForCurrentDifficulty(reason: "init");
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
      unawaited(_ensureUsageAccessIfNeeded());
      unawaited(_openPuzzleFromOverlayRequestIfNeeded());
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
    final openPuzzle = await _consumeOpenPuzzleRequest();
    if (!mounted || !openPuzzle) return;
    _goPuzzle();
  }

  Future<void> _maybeShowFirstLaunchOnboarding() async {
    final prefs = await _prefsFuture;

    if (_lockedPackages.isNotEmpty) {
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
      unawaited(_showFirstLaunchOnboardingDialog());
    });
  }

  Future<void> _completeOnboarding() async {
    final prefs = await _prefsFuture;
    await prefs.setBool(_kOnboardingComplete, true);
  }

  Future<void> _showFirstLaunchOnboardingDialog() async {
    if (!mounted) return;

    if (_lockedPackages.isNotEmpty) {
      await _completeOnboarding();
      return;
    }

    AppAnalytics.onboardingScreenViewed();
    final chooseApps = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Welcome to ChessLock"),
        content: const Text(
          "Pick any distracting apps you want to lock.\n"
          "You will need solve chess puzzle to use those apps.",
        ),
        actions: [
          TextButton(
            onPressed: () {
              AppAnalytics.onboardingLaterButtonTapped();
              Navigator.pop(ctx, false);
            },
            child: const Text("Later"),
          ),
          FilledButton(
            onPressed: () {
              AppAnalytics.onboardingChooseAppsButtonTapped();
              Navigator.pop(ctx, true);
            },
            child: const Text("Choose Apps"),
          ),
        ],
      ),
    );

    await _completeOnboarding();
    if (!mounted) return;

    if (chooseApps == true) {
      await _openAppPicker(requireSolved: false);
    }
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
  Future<List<Map<String, dynamic>>> _getLaunchableAppsRaw() async {
    final ownPackageName = await _getOwnPackageName();
    final raw =
        await _platform.invokeMethod<List<dynamic>>("getLaunchableApps");
    final list =
        (raw ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return list.where((m) {
      final pkg = (m["packageName"] ?? "").toString();
      return pkg.isNotEmpty && pkg != ownPackageName;
    }).toList();
  }

  Future<String?> _getOwnPackageName() async {
    final cached = _ownPackageName;
    if (cached != null && cached.isNotEmpty) return cached;

    try {
      final pkg =
          (await _platform.invokeMethod<String>("getOwnPackageName"))?.trim();
      if (pkg == null || pkg.isEmpty) return null;
      _ownPackageName = pkg;
      return pkg;
    } catch (_) {
      return null;
    }
  }

  Set<String> _withoutOwnPackage(
    Set<String> packages,
    String? ownPackageName,
  ) {
    return packages
        .map((pkg) => pkg.trim())
        .where((pkg) => pkg.isNotEmpty && pkg != ownPackageName)
        .toSet();
  }

  Future<Set<String>> _sanitizeLockedPackages(Set<String> packages) async {
    return _withoutOwnPackage(packages, await _getOwnPackageName());
  }

  Future<void> _removeOwnPackageFromLockedAppsIfPresent() async {
    final sanitized = await _sanitizeLockedPackages(_lockedPackages);
    if (setEquals(sanitized, _lockedPackages)) return;

    _lockedPackages = sanitized;
    await _saveLockedPackages();
  }

  Future<void> _prefetchIcons() async {
    try {
      final list = await _getLaunchableAppsRaw();
      final map = <String, Uint8List>{};

      for (final m in list) {
        final pkg = (m["packageName"] ?? "").toString();
        final b64 = (m["iconPngBase64"] ?? "").toString();
        if (pkg.isEmpty || b64.isEmpty) continue;
        final bytes = decodeIconPngBase64(b64);
        if (bytes != null) map[pkg] = bytes;
      }

      if (!mounted) return;
      setState(() => _iconsByPkg = map);
    } catch (_) {
      // ignore
    }
  }

  // =========================
  // Prefs
  // =========================
  Future<void> _loadPrefs() async {
    await _lockState.load();
    await _removeOwnPackageFromLockedAppsIfPresent();
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
  // Usage Access + watcher
  // =========================
  Future<bool> _checkUsageAccess() async {
    try {
      final granted = await _platform.invokeMethod<bool>("hasUsageAccess");
      return granted == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _openUsageAccessSettings() async {
    try {
      await _platform.invokeMethod("openUsageAccessSettings");
    } catch (_) {}
  }

  Future<bool> _checkOverlayPermission() async {
    try {
      final ok = await _platform.invokeMethod<bool>("hasOverlayPermission");
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _checkNotificationPermission() async {
    try {
      final ok =
          await _platform.invokeMethod<bool>("hasNotificationPermission");
      return ok == true;
    } catch (_) {
      return true;
    }
  }

  Future<void> _requestNotificationPermissionIfNeeded() async {
    try {
      final granted = await _checkNotificationPermission();
      if (!granted) {
        await _platform.invokeMethod("requestNotificationPermission");
      }
    } catch (_) {}
  }

  Future<void> _syncWatcherStateToNative() async {
    try {
      final lockedPackages =
          (await _sanitizeLockedPackages(_lockedPackages)).toList()..sort();
      await _platform.invokeMethod("syncWatcherState", {
        "lockedPackages": lockedPackages,
        "lockEnabled": _lockEnabled,
        "indefiniteUnlock": _indefiniteUnlock,
        "unlockUntilMs": _unlockedUntil?.millisecondsSinceEpoch ?? 0,
      });
    } catch (_) {}
  }

  Future<void> _openOverlaySettings() async {
    try {
      await _platform.invokeMethod("openOverlaySettings");
    } catch (_) {}
  }

  Future<void> _startWatcher() async {
    try {
      await _platform.invokeMethod("startWatcher");
    } catch (_) {}
  }

  Future<void> _hideWatcherOverlay() async {
    try {
      await _platform.invokeMethod("hideWatcherOverlay");
    } catch (_) {}
  }

  Future<void> _stopWatcher() async {
    try {
      await _platform.invokeMethod("stopWatcher");
    } catch (_) {}
  }

  Future<void> _ensureUsageAccessIfNeeded() async {
    await _syncWatcherStateToNative();

    if (_lockedPackages.isEmpty) {
      await _stopWatcher();
      return;
    }

    final usageGranted = await _checkUsageAccess();
    if (!mounted) return;

    if (!usageGranted) {
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
                await _openUsageAccessSettings();
              },
              child: const Text("Open Settings"),
            ),
          ],
        ),
      );
      await _stopWatcher();
      return;
    }

    if (_lockEnabled) {
      final overlayGranted = await _checkOverlayPermission();
      if (!mounted) return;
      if (!overlayGranted) {
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
                  await _openOverlaySettings();
                },
                child: const Text("Open Settings"),
              ),
            ],
          ),
        );
        await _stopWatcher();
        return;
      }
    }

    final hasTimedUnlock = !_indefiniteUnlock && _unlockedUntil != null;
    final shouldRunWatcher =
        _lockedPackages.isNotEmpty && (_lockEnabled || hasTimedUnlock);

    if (shouldRunWatcher) {
      await _requestNotificationPermissionIfNeeded();
      if (!mounted) return;

      if (_lockEnabled) {
        await _startWatcher();
      } else {
        await _hideWatcherOverlay();
      }
    } else {
      await _stopWatcher();
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
      await _ensureUsageAccessIfNeeded();
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
    }

    _lockEnabled = false;
    _resetSolvedUnlockFlow();
    if (mounted) setState(() {});

    final saved =
        await _syncLockStateToStorageAndWatcher(includeUnlockState: true);

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
      _goHome();
    }
  }

  // =========================
  // Hint/Skip ads
  // =========================
  String get _rewardedAdUnitId {
    final configured = _configuredRewardedAdUnitId.trim();
    if (configured.isNotEmpty) {
      return configured;
    }
    if (kReleaseMode) {
      return _productionRewardedAdUnitId;
    }
    return _testRewardedAdUnitId;
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
          _snack(_rewardedAdUnavailableMessage(_lastRewardedAdLoadError));
        case _RewardedAdResult.failedToShow:
          _logRewardedAdFailed(action, adResult: "failed");
          _snack(_rewardedAdUnavailableMessage(_lastRewardedAdLoadError));
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

    _debugRewarded(
      "rewarded load started; reason=$reason adUnitId=$_rewardedAdUnitId",
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
      _preloadRewardedAd();
      return _RewardedAdResult.unavailable;
    }

    _rewardedAd = null;
    _lastRewardedAdLoadError = null;

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

  String _rewardedAdUnavailableMessage(LoadAdError? error) {
    return "Ad is not available right now. Please check your internet and try again.";
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

    int selected = 10;

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
                child: CupertinoTheme(
                  data: CupertinoThemeData(
                    brightness: Theme.of(ctx).brightness,
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
                      initialItem: (selected - 1).clamp(0, 14),
                    ),
                    onSelectedItemChanged: (i) => selected = i + 1,
                    children: List.generate(
                      15,
                      (i) => Center(child: Text("${i + 1} min")),
                    ),
                  ),
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
    final editingExistingLocks = _lockedPackages.isNotEmpty;
    if (requireSolved && editingExistingLocks && !_canUnlockApps) {
      _snack("Solve a puzzle to edit locked apps.");
      _goPuzzle();
      return;
    }

    final selected = await _sanitizeLockedPackages(_lockedPackages);
    if (!mounted) return;

    final updated = await Navigator.push<Set<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => AppSelectionPage(
          selected: selected,
          editingDisabled: false,
          fetchApps: _getLaunchableAppsRaw,
        ),
      ),
    );

    if (!mounted || updated == null) return;

    final sanitized = await _sanitizeLockedPackages(updated);
    if (!mounted) return;

    setState(() => _lockedPackages = sanitized);
    await _saveLockedPackages();
    AppAnalytics.lockedAppsSelectionSaved(sanitized.length);
    await _completeOnboarding();
    await _ensureUsageAccessIfNeeded();
    await _prefetchIcons();
    _snack("Apps locked.");
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
