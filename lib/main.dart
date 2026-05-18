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
import 'services/lock_state_controller.dart';
import 'services/puzzle_queue_service.dart';
import 'services/stats_repository.dart';
import 'ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await _initializeMobileAds();
  runApp(const MyApp());
}

Future<void> _initializeMobileAds() async {
  if (kIsWeb ||
      (defaultTargetPlatform != TargetPlatform.android &&
          defaultTargetPlatform != TargetPlatform.iOS)) {
    return;
  }

  try {
    await MobileAds.instance.initialize();
  } catch (_) {
    // Ads are optional; app startup should never depend on ad initialization.
  }
}

// Android native channel
const MethodChannel _platform = MethodChannel("chesslock/system");

class MyApp extends StatefulWidget {
  const MyApp({super.key});

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
  final AppThemeMode themeMode;
  final Future<void> Function(AppThemeMode mode) onThemeModeChanged;

  const ChessLockShell({
    super.key,
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

  bool _usageAccessGranted = false; // backend only
  bool _onboardingDialogQueued = false;

  int _statSolved = 0;
  int _statBestRating = 0;
  int _statFirstTry = 0;

  // attempts per puzzle
  int _attemptsThisPuzzle = 0;

  // =========================
  // Hint + Skip ads
  // =========================
  static const String _rewardedAdUnitId =
      "ca-app-pub-3940256099942544/5224354917";

  RewardedAd? _rewardedAd;
  Future<RewardedAd?>? _rewardedAdLoadFuture;
  LoadAdError? _lastRewardedAdLoadError;
  bool _rewardedAdShowing = false;
  bool _rewardedActionInProgress = false;

  // Blink hint overlay
  String? _hintFromSquare;
  bool _hintBlinkOn = false;
  Timer? _hintBlinkTimer;

  // Tabs
  int _tab = 0; // 0 Home, 1 Puzzle, 2 Settings

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
    _boardController.removeListener(_onBoardChanged);
    _boardController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // ignore: discarded_futures
      _ensureUsageAccessIfNeeded();
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
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Later"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
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
      final granted = await _checkUsageAccess();
      if (mounted) setState(() => _usageAccessGranted = granted);
      await _stopWatcher();
      return;
    }

    final usageGranted = await _checkUsageAccess();
    if (mounted) setState(() => _usageAccessGranted = usageGranted);
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
    _solved = true;
    _unlockAvailable = true;
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
            onPressed: () => Navigator.pop(ctx, _PuzzleSolvedChoice.unlockApps),
            child: const Text("Unlock apps"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _PuzzleSolvedChoice.solveMore),
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
      await _openUnlockAppsFlow();
    }
  }

  // =========================
  // Hint/Skip ads
  // =========================
  bool get _adsSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool get _rewardedPuzzleActionAvailable =>
      _puzzle != null &&
      !_solved &&
      !_loadingPuzzle &&
      !_isChecking &&
      !_rewardedActionInProgress &&
      !_rewardedAdShowing;

  bool get _hintAvailable => _rewardedPuzzleActionAvailable;

  bool get _skipAvailable => _rewardedPuzzleActionAvailable;

  Future<void> _onHintPressed() async {
    if (!_hintAvailable) return;
    await _showRewardedActionDialog(
      title: "Get a hint",
      message: "Need a little help?\n\n"
          "Watching an ad will show which piece to move.\n\n"
          "We added this ad so you don’t take hints too quickly. Solving the puzzle yourself is what actually improves your chess.",
      onRewardEarned: _grantHintReward,
    );
  }

  Future<void> _onSkipPressed() async {
    if (!_skipAvailable) return;
    await _showRewardedActionDialog(
      title: "Skip puzzle",
      message: "Want to skip this puzzle?\n\n"
          "Watching an ad will load a new puzzle.\n\n"
          "We added this ad to encourage you to try a little harder before skipping. That effort is what helps you get better at chess.",
      onRewardEarned: _grantSkipReward,
    );
  }

  Future<void> _showRewardedActionDialog({
    required String title,
    required String message,
    required VoidCallback onRewardEarned,
  }) async {
    var watchBusy = false;
    String? errorText;

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
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text("Cancel"),
                ),
                FilledButton(
                  onPressed: watchBusy
                      ? null
                      : () async {
                          setDialogState(() {
                            watchBusy = true;
                            errorText = null;
                          });

                          final ready = await _prepareRewardedAdForWatch();
                          if (!mounted || !ctx.mounted) return;

                          if (!ready) {
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
    final result = await _showRewardedAd(onRewardEarned: onRewardEarned);
    if (!mounted) return;
    setState(() => _rewardedActionInProgress = false);

    switch (result) {
      case _RewardedAdResult.completed:
      case _RewardedAdResult.dismissedAfterReward:
      case _RewardedAdResult.dismissedBeforeReward:
        return;
      case _RewardedAdResult.unavailable:
        _snack(_rewardedAdUnavailableMessage(_lastRewardedAdLoadError));
      case _RewardedAdResult.failedToShow:
        _snack("Ad not available right now. Please try again.");
    }
  }

  void _grantHintReward() {
    final puzzle = _puzzle;
    if (puzzle == null) return;
    if (_progressIndex >= puzzle.solutionUci.length) return;

    final uci = puzzle.solutionUci[_progressIndex];
    if (uci.length < 4) return;

    _blinkHintFromSquare(uci.substring(0, 2));
  }

  void _grantSkipReward() {
    _snack("Skipped. New puzzle.");
    _queuePuzzleRefresh("skip");
  }

  Future<bool> _prepareRewardedAdForWatch() async {
    final ad = _rewardedAd ?? await _loadRewardedAd();
    return ad != null;
  }

  Future<RewardedAd?> _loadRewardedAd() {
    if (!_adsSupported) {
      _lastRewardedAdLoadError = null;
      return Future.value(null);
    }

    final cachedAd = _rewardedAd;
    if (cachedAd != null) return Future.value(cachedAd);

    final inFlight = _rewardedAdLoadFuture;
    if (inFlight != null) return inFlight;

    final completer = Completer<RewardedAd?>();
    _rewardedAdLoadFuture = completer.future;

    RewardedAd.load(
      adUnitId: _rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _lastRewardedAdLoadError = null;
          _rewardedAdLoadFuture = null;
          if (!completer.isCompleted) completer.complete(ad);
          if (mounted) setState(() {});
        },
        onAdFailedToLoad: (error) {
          _lastRewardedAdLoadError = error;
          _rewardedAdLoadFuture = null;
          if (!completer.isCompleted) completer.complete(null);
          if (mounted) setState(() {});
        },
      ),
    );

    return completer.future;
  }

  void _preloadRewardedAd() {
    if (_rewardedAd != null || _rewardedAdLoadFuture != null) return;
    unawaited(_loadRewardedAd());
  }

  Future<_RewardedAdResult> _showRewardedAd({
    required VoidCallback onRewardEarned,
  }) async {
    final ad = _rewardedAd ?? await _loadRewardedAd();
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
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        finish(
          rewardEarned
              ? _RewardedAdResult.dismissedAfterReward
              : _RewardedAdResult.dismissedBeforeReward,
        );
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        finish(_RewardedAdResult.failedToShow);
      },
    );

    try {
      ad.show(
        onUserEarnedReward: (ad, reward) {
          if (rewardEarned) return;
          rewardEarned = true;
          onRewardEarned();
          if (!completer.isCompleted) {
            completer.complete(_RewardedAdResult.completed);
          }
        },
      );
    } catch (_) {
      ad.dispose();
      finish(_RewardedAdResult.failedToShow);
    }

    return completer.future;
  }

  void _disposeRewardedAd() {
    _rewardedAd?.dispose();
    _rewardedAd = null;
    _rewardedAdLoadFuture = null;
  }

  String _rewardedAdUnavailableMessage(LoadAdError? error) {
    final text = error?.message.toLowerCase() ?? "";
    if (text.contains("network") ||
        text.contains("internet") ||
        text.contains("offline") ||
        text.contains("timeout") ||
        text.contains("dns")) {
      return "Ad not available right now. Please check your internet and try again.";
    }
    return "Ad not available right now. Please try again.";
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
    _extraPuzzleMode = false;
    _goHome();
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    await _showBreakTimePicker();
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
                      Navigator.pop(ctx);
                      final saved = await _unlockForMinutes(selected);
                      if (!mounted) return;
                      if (saved) {
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
      if (saved) _snack("Lock ON");
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
                  if (saved) _snack("Unlocked for 24 hours.");
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
                  if (saved) _snack("Lock turned off.");
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
    setState(() => _difficulty = selected);
    await _saveDifficulty();
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
    await _completeOnboarding();
    await _ensureUsageAccessIfNeeded();
    await _prefetchIcons();
    _snack("Apps locked.");
  }

  static const String _privacyPolicyUrl =
      "https://aimlessoulapps.github.io/chessunlock-legal/";

  Future<void> _onPrivacyPolicy() async {
    try {
      final uri = Uri.parse(_privacyPolicyUrl);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) _snack("Couldn’t open Privacy Policy.");
    } catch (_) {
      _snack("Couldn’t open Privacy Policy.");
    }
  }

  Future<void> _onRateApp() async {
    // ✅ Correct logic: until the app exists on Play, there’s nothing to open.
    // Later (after Internal/Closed testing upload), we can wire this to Play
    // or use the official in-app review flow.
    _snack("Rating will be available after ChessUnlock is on Google Play.");
  }

  void _selectTab(int index) {
    if (_tab == 1 && index != 1) {
      _extraPuzzleMode = false;
    }
    setState(() => _tab = index);
  }

  void _goHome() => _selectTab(0);
  void _goPuzzle() => _selectTab(1);
  void _goSettings() => _selectTab(2);

  // =========================
  // UI
  // =========================
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

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
              statSolved: _statSolved,
              statBestRating: _statBestRating,
              accuracyPct: _accuracyPct,
              iconsByPkg: _iconsByPkg,
              onEditLockedApps: () {
                unawaited(_openAppPicker());
              },
              onBreakTime: _showBreakTimePicker,
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
              onThemeModeChanged: widget.onThemeModeChanged,
              onLockToggle: _onLockToggleFromSettings,
              onOpenDifficulty: _openDifficultyPicker,
              onPrivacyPolicy: _onPrivacyPolicy,
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

enum _PuzzleSolvedChoice {
  solveMore,
  unlockApps,
}
