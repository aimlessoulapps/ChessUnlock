import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:advanced_chess_board/advanced_chess_board.dart';
import 'package:advanced_chess_board/chess_board_controller.dart';
import 'package:advanced_chess_board/models/enums.dart';
import 'package:flutter/foundation.dart' hide Uint8List;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class ChessPuzzle {
  final String id;
  final int rating;
  final String type;
  final String fen;
  final List<String> solutionUci;

  const ChessPuzzle({
    required this.id,
    required this.rating,
    required this.type,
    required this.fen,
    required this.solutionUci,
  });
}

/// Theme modes shared with main.dart
enum AppThemeMode { system, dark, light }

String titleCase(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String getDifficultyDisplayName(String difficulty) {
  return switch (difficulty.toLowerCase()) {
    "easiest" => "Easiest (900)",
    "easier" => "Easier (1200)",
    "normal" => "Normal (1500)",
    "harder" => "Harder (1800)",
    "hardest" => "Hardest (2100)",
    _ => titleCase(difficulty),
  };
}

const int _maxIconPngBytes = 512 * 1024;

Uint8List? decodeIconPngBase64(String b64) {
  final normalized = b64.trim();
  if (normalized.isEmpty) return null;

  final padding = normalized.endsWith("==")
      ? 2
      : normalized.endsWith("=")
          ? 1
          : 0;
  final estimatedBytes = max(0, ((normalized.length * 3) ~/ 4) - padding);
  if (estimatedBytes > _maxIconPngBytes) return null;

  try {
    final bytes = base64Decode(normalized);
    if (bytes.length > _maxIconPngBytes) return null;
    return bytes;
  } catch (_) {
    return null;
  }
}

String formatRemaining(Duration d) {
  var secs = d.inSeconds;
  if (secs < 0) secs = 0;

  if (secs >= 3600) {
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    return "${h}h ${m}m";
  } else {
    final m = secs ~/ 60;
    final s = secs % 60;
    return "${m}m ${s.toString().padLeft(2, '0')}s";
  }
}

// =========================
// Bottom nav
// =========================
class PremiumNavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;

  const PremiumNavBar({
    super.key,
    required this.index,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
        child: Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withOpacity(0.72),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
            boxShadow: [
              BoxShadow(
                blurRadius: 18,
                spreadRadius: 0,
                color: Colors.black.withOpacity(
                    Theme.of(context).brightness == Brightness.dark
                        ? 0.35
                        : 0.10),
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: NavigationBar(
            height: 58,
            selectedIndex: index,
            onDestinationSelected: onChanged,
            backgroundColor: Colors.transparent,
            elevation: 0,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.grid_view_rounded),
                selectedIcon: Icon(Icons.grid_view_rounded),
                label: "Home",
              ),
              NavigationDestination(
                icon: Icon(Icons.extension_rounded),
                selectedIcon: Icon(Icons.extension_rounded),
                label: "Puzzle",
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_rounded),
                selectedIcon: Icon(Icons.settings_rounded),
                label: "Settings",
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =========================
// Banner ad slot
// =========================
class BannerAdSlot extends StatefulWidget {
  final double height;
  final bool active;
  final String screenName;

  const BannerAdSlot({
    super.key,
    this.height = 60,
    this.active = true,
    required this.screenName,
  });

  @override
  State<BannerAdSlot> createState() => _BannerAdSlotState();
}

class _BannerAdSlotState extends State<BannerAdSlot>
    with WidgetsBindingObserver {
  static const _androidDefaultBannerAdUnitId =
      "ca-app-pub-8108010703558411/9765598008";
  static const _iosDefaultBannerAdUnitId =
      "ca-app-pub-8108010703558411/5013979522";
  static const _configuredBannerAdUnitId = String.fromEnvironment(
    "CHESSUNLOCK_BANNER_AD_UNIT_ID",
  );
  static const _initialRetryDelay = Duration(seconds: 30);
  static const _maxRetryDelay = Duration(minutes: 5);
  static const _activeCheckInterval = Duration(seconds: 60);

  BannerAd? _bannerAd;
  BannerAd? _loadingBannerAd;
  bool _loaded = false;
  bool _loading = false;
  bool _appResumed = true;
  DateTime? _nextRetryAt;
  Duration _retryDelay = _initialRetryDelay;
  Timer? _retryTimer;
  Timer? _activeCheckTimer;
  bool _loggedInvalidBannerAdUnitId = false;
  bool _loggedBannerConfiguration = false;

  bool get _adsSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  String get _bannerAdUnitId {
    final configured = _configuredBannerAdUnitId.trim();
    if (configured.isNotEmpty) {
      return configured;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return _iosDefaultBannerAdUnitId;
    }
    return _androidDefaultBannerAdUnitId;
  }

  String get _bannerAdUnitSource {
    if (_configuredBannerAdUnitId.trim().isNotEmpty) {
      return "dart-define";
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return "ios-default";
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return "android-default";
    }
    return "unsupported-default";
  }

  String get _bannerPlatformLabel {
    if (kIsWeb) return "web";
    return defaultTargetPlatform.name;
  }

  bool get _hasUsableBannerAdUnitId => _isValidAdUnitId(_bannerAdUnitId);

  bool _isValidAdUnitId(String value) =>
      value.startsWith("ca-app-pub-") && value.contains("/");

  bool get _hasLoadedBanner => _loaded && _bannerAd != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _debugBannerConfigurationIfNeeded();
      _debugBannerVisibility("init");
      _syncActiveBannerState(reason: "init");
    });
  }

  @override
  void didUpdateWidget(covariant BannerAdSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _debugBannerVisibility("active_changed");
      });
      _syncActiveBannerState(
        reason: widget.active ? "screen_visible" : "screen_hidden",
      );
      return;
    }

    if (widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _debugBannerVisibility("widget_update");
      });
      _syncActiveBannerState(reason: "widget_update");
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _appResumed = true;
      _debugBanner("app resumed and banner checked");
      _syncActiveBannerState(reason: "app_resumed");
    } else {
      _appResumed = false;
      _debugBanner("app paused; banner timers cancelled");
      _cancelRetryTimer();
      _stopActiveCheckTimer();
    }
  }

  void _syncActiveBannerState({required String reason}) {
    if (!_adsSupported || !widget.active || !_appResumed) {
      _stopActiveCheckTimer();
      if (!widget.active || !_appResumed) {
        _cancelRetryTimer();
      }
      return;
    }

    _startActiveCheckTimer();
    _ensureBannerAdLoaded(reason: reason);
  }

  void _ensureBannerAdLoaded({required String reason}) {
    if (!_adsSupported || !widget.active || !_appResumed) return;

    _debugBannerConfigurationIfNeeded();

    if (!_hasUsableBannerAdUnitId) {
      _debugInvalidBannerAdUnitId();
      return;
    }

    if (_hasLoadedBanner) {
      _debugBanner(
        "banner retry skipped because an ad is already loaded; "
        "reason=$reason adUnitId=$_bannerAdUnitId",
      );
      return;
    }

    if (_loading) {
      _debugBanner(
        "banner retry skipped because an ad is already loading; "
        "reason=$reason adUnitId=$_bannerAdUnitId",
      );
      return;
    }

    final nextRetryAt = _nextRetryAt;
    if (nextRetryAt != null) {
      final remaining = nextRetryAt.difference(DateTime.now());
      if (remaining > Duration.zero) {
        _scheduleRetry(remaining, reason: "retry_wait:$reason");
        return;
      }
    }

    _loadBannerAd(reason: reason);
  }

  void _startActiveCheckTimer() {
    if (_activeCheckTimer != null) return;
    _activeCheckTimer = Timer.periodic(_activeCheckInterval, (_) {
      if (!mounted) return;
      _debugBanner(
        "banner refresh/check timer tick; adUnitId=$_bannerAdUnitId",
      );
      _ensureBannerAdLoaded(reason: "active_check_timer");
    });
  }

  void _stopActiveCheckTimer() {
    _activeCheckTimer?.cancel();
    _activeCheckTimer = null;
  }

  void _scheduleRetry(Duration delay, {required String reason}) {
    if (!_adsSupported ||
        !widget.active ||
        !_appResumed ||
        _hasLoadedBanner ||
        _loading) {
      _debugBanner(
        "banner retry skipped because an ad is already loaded/loading "
        "or screen is inactive; reason=$reason adUnitId=$_bannerAdUnitId",
      );
      return;
    }
    if (_retryTimer != null) return;

    _debugBanner(
      "banner retry scheduled in ${delay.inSeconds}s; "
      "reason=$reason adUnitId=$_bannerAdUnitId",
    );
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      if (!mounted) return;
      _ensureBannerAdLoaded(reason: "retry_timer");
    });
  }

  void _cancelRetryTimer() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void _loadBannerAd({required String reason}) {
    if (!_adsSupported || !_appResumed || _loading || _hasLoadedBanner) return;
    if (!_hasUsableBannerAdUnitId) {
      _debugInvalidBannerAdUnitId();
      return;
    }

    _cancelRetryTimer();
    _loading = true;
    _nextRetryAt = null;

    _debugBanner(
      "banner load started; platform=$_bannerPlatformLabel "
      "source=$_bannerAdUnitSource reason=$reason "
      "adUnitId=$_bannerAdUnitId",
    );
    final ad = BannerAd(
      adUnitId: _bannerAdUnitId,
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (_loadingBannerAd == ad) {
            _loadingBannerAd = null;
          }
          if (!mounted) {
            ad.dispose();
            return;
          }
          _debugBanner(
            "banner loaded; platform=$_bannerPlatformLabel "
            "source=$_bannerAdUnitSource adUnitId=$_bannerAdUnitId "
            "responseInfo=${ad.responseInfo}",
          );
          setState(() {
            _bannerAd = ad as BannerAd;
            _loaded = true;
            _loading = false;
            _nextRetryAt = null;
            _retryDelay = _initialRetryDelay;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _debugBannerVisibility("loaded");
          });
        },
        onAdFailedToLoad: (ad, error) {
          if (_loadingBannerAd == ad) {
            _loadingBannerAd = null;
          }
          ad.dispose();
          _debugBannerLoadError("banner failed", error);
          if (!mounted) return;
          setState(() {
            _bannerAd = null;
            _loaded = false;
            _loading = false;
          });
          final delayBeforeNextAttempt = _retryDelay;
          _nextRetryAt = DateTime.now().add(delayBeforeNextAttempt);
          _scheduleRetry(delayBeforeNextAttempt, reason: "load_failed");
          final nextRetrySeconds = _retryDelay.inSeconds * 2;
          final cappedRetrySeconds = nextRetrySeconds > _maxRetryDelay.inSeconds
              ? _maxRetryDelay.inSeconds
              : nextRetrySeconds;
          _retryDelay = Duration(
            seconds: cappedRetrySeconds,
          );
        },
      ),
    );

    _loadingBannerAd = ad;
    ad.load();
  }

  void _disposeLoadedBanner({bool afterFrame = false}) {
    final ad = _bannerAd;
    _bannerAd = null;
    _loaded = false;
    if (ad == null) return;
    if (afterFrame && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => ad.dispose());
    } else {
      ad.dispose();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelRetryTimer();
    _stopActiveCheckTimer();
    _loadingBannerAd?.dispose();
    _disposeLoadedBanner();
    super.dispose();
  }

  void _debugInvalidBannerAdUnitId() {
    if (_loggedInvalidBannerAdUnitId) return;
    _loggedInvalidBannerAdUnitId = true;
    _debugBanner(
      "banner ad unit id is missing or invalid; use an ad unit id like "
      "ca-app-pub-.../... and not the app id ca-app-pub-...~...",
    );
  }

  void _debugBannerConfigurationIfNeeded() {
    if (_loggedBannerConfiguration) return;
    _loggedBannerConfiguration = true;
    _debugBanner(
      "banner configuration; platform=$_bannerPlatformLabel "
      "source=$_bannerAdUnitSource adUnitId=$_bannerAdUnitId "
      "supported=$_adsSupported",
    );
  }

  void _debugBannerVisibility(String reason) {
    final renderSize = context.size;
    _debugBanner(
      "banner visibility; reason=$reason active=${widget.active} "
      "appResumed=$_appResumed loaded=$_loaded "
      "height=${widget.height} nonZeroHeight=${widget.height > 0} "
      "renderSize=$renderSize",
    );
  }

  void _debugBanner(String message) {
    debugPrint("[ads][banner][${widget.screenName}] $message");
  }

  void _debugBannerLoadError(String prefix, LoadAdError error) {
    _debugBanner(
      "$prefix; platform=$_bannerPlatformLabel "
      "source=$_bannerAdUnitSource adUnitId=$_bannerAdUnitId "
      "error.code=${error.code} "
      "error.domain=${error.domain} "
      "error.message=${error.message} "
      "error.responseInfo=${error.responseInfo}",
    );
  }

  @override
  Widget build(BuildContext context) {
    final ad = _bannerAd;
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: _loaded && ad != null
          ? Center(
              child: SizedBox(
                width: ad.size.width.toDouble(),
                height: ad.size.height.toDouble(),
                child: AdWidget(ad: ad),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

class ScreenAdHeader extends StatelessWidget {
  final String title;
  final bool active;
  final String screenName;

  const ScreenAdHeader({
    super.key,
    required this.title,
    required this.active,
    required this.screenName,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 2),
        Text(
          title,
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        BannerAdSlot(
          height: 54,
          active: active,
          screenName: screenName,
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// =========================
// HOME TAB
// =========================
typedef OnboardingAnswerSelected = Future<void> Function(
  String key,
  String answer,
);

class OnboardingFlow extends StatefulWidget {
  final OnboardingAnswerSelected onAnswerSelected;
  final Future<void> Function() onPermissionContinue;

  const OnboardingFlow({
    super.key,
    required this.onAnswerSelected,
    required this.onPermissionContinue,
  });

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  final PageController _pageController = PageController();
  final Map<String, String> _answers = {};
  int _page = 0;
  bool _busy = false;

  static const _pages = 8;

  bool get _isQuestionPage => _questionKeyForPage(_page) != null;

  bool get _canContinue {
    final key = _questionKeyForPage(_page);
    return key == null || _answers.containsKey(key);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_busy || !_canContinue) return;

    if (_page == 6) {
      setState(() => _busy = true);
      await widget.onPermissionContinue();
      if (!mounted) return;
      setState(() => _busy = false);
    }

    if (_page == _pages - 1) {
      Navigator.pop(context, true);
      return;
    }

    await _pageController.animateToPage(
      _page + 1,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _back() async {
    if (_busy || _page == 0) return;
    await _pageController.animateToPage(
      _page - 1,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _selectAnswer(String key, String answer) async {
    setState(() => _answers[key] = answer);
    await widget.onAnswerSelected(key, answer);
  }

  String? _questionKeyForPage(int page) {
    return switch (page) {
      1 => "source",
      2 => "distraction",
      3 => "goal",
      4 => "strictness",
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF0B0F0D);
    const card = Color(0xFF151A17);
    const secondaryCard = Color(0xFF1E2420);
    const green = Color(0xFF43D66E);
    const text = Color(0xFFF4F7F5);
    const muted = Color(0xFF8F9B94);

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
            child: Column(
              children: [
                Row(
                  children: [
                    if (_page > 0)
                      IconButton(
                        onPressed: _busy ? null : _back,
                        icon: const Icon(Icons.arrow_back_rounded),
                        color: text,
                        tooltip: "Back",
                      )
                    else
                      const SizedBox(width: 48, height: 48),
                    Expanded(
                      child: _OnboardingProgress(
                        page: _page,
                        pages: _pages,
                        color: green,
                        trackColor: secondaryCard,
                      ),
                    ),
                    const SizedBox(width: 48, height: 48),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    onPageChanged: (page) => setState(() => _page = page),
                    children: [
                      _OnboardingCopyPage(
                        icon: Icons.lock_open_rounded,
                        title: "Welcome to ChessUnlock",
                        body:
                            "Turn distractions into chess progress. Lock distracting apps and unlock them by solving a puzzle.",
                        textColor: text,
                        mutedColor: muted,
                        accentColor: green,
                      ),
                      _QuestionPage(
                        question: "Where did you hear about ChessUnlock?",
                        options: const [
                          "App Store / Play Store",
                          "YouTube",
                          "Instagram",
                          "Reddit",
                          "Friend",
                          "Search",
                          "Other",
                        ],
                        selected: _answers["source"],
                        onSelected: (answer) => _selectAnswer("source", answer),
                        textColor: text,
                        mutedColor: muted,
                        cardColor: card,
                        selectedColor: green,
                      ),
                      _QuestionPage(
                        question: "What pulls your attention most often?",
                        options: const [
                          "Instagram",
                          "YouTube",
                          "YouTube Shorts",
                          "Reddit",
                          "Discord",
                          "Snapchat",
                          "X / Twitter",
                          "WhatsApp",
                          "Other",
                        ],
                        selected: _answers["distraction"],
                        onSelected: (answer) =>
                            _selectAnswer("distraction", answer),
                        textColor: text,
                        mutedColor: muted,
                        cardColor: card,
                        selectedColor: green,
                      ),
                      _QuestionPage(
                        question: "What is your main goal?",
                        options: const [
                          "Reduce screen time",
                          "Improve chess",
                          "Improve focus",
                          "Build discipline",
                          "Study or work better",
                          "Stop automatic scrolling",
                        ],
                        selected: _answers["goal"],
                        onSelected: (answer) => _selectAnswer("goal", answer),
                        textColor: text,
                        mutedColor: muted,
                        cardColor: card,
                        selectedColor: green,
                      ),
                      _QuestionPage(
                        question: "How strict should ChessUnlock feel?",
                        options: const [
                          "Gentle",
                          "Balanced",
                          "Strict",
                        ],
                        selected: _answers["strictness"],
                        onSelected: (answer) =>
                            _selectAnswer("strictness", answer),
                        textColor: text,
                        mutedColor: muted,
                        cardColor: card,
                        selectedColor: green,
                      ),
                      _OnboardingCopyPage(
                        icon: Icons.psychology_alt_rounded,
                        title: "Small puzzles. Real progress.",
                        body:
                            "Solving chess puzzles consistently can build pattern recognition, calculation, and better decision-making. ChessUnlock helps turn every distraction into a small chess habit.",
                        textColor: text,
                        mutedColor: muted,
                        accentColor: green,
                      ),
                      _OnboardingCopyPage(
                        icon: defaultTargetPlatform == TargetPlatform.iOS
                            ? Icons.ios_share_rounded
                            : Icons.security_rounded,
                        title: defaultTargetPlatform == TargetPlatform.iOS
                            ? "Why we need Screen Time permission"
                            : "Enable App Lock Permissions",
                        body: defaultTargetPlatform == TargetPlatform.iOS
                            ? "ChessUnlock needs Screen Time permission so it can let you choose distracting apps and lock them until you solve a chess puzzle. Your selected apps are used for the locking feature, not to spy on your personal content."
                            : "ChessUnlock needs Usage Access and overlay permission to detect locked apps and show the puzzle screen when you open them.",
                        textColor: text,
                        mutedColor: muted,
                        accentColor: green,
                      ),
                      _OnboardingCopyPage(
                        icon: Icons.check_circle_rounded,
                        title: "You're ready.",
                        body:
                            "Now choose the apps you want ChessUnlock to protect. First-time setup does not require solving a puzzle.",
                        textColor: text,
                        mutedColor: muted,
                        accentColor: green,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy || (_isQuestionPage && !_canContinue)
                      ? null
                      : _next,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                    backgroundColor: green,
                    foregroundColor: const Color(0xFF06110A),
                    disabledBackgroundColor: secondaryCard,
                    disabledForegroundColor: muted,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Color(0xFF06110A),
                          ),
                        )
                      : Text(
                          switch (_page) {
                            0 => "Get started",
                            6 => "Continue",
                            7 => "Choose apps",
                            _ => "Continue",
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingProgress extends StatelessWidget {
  final int page;
  final int pages;
  final Color color;
  final Color trackColor;

  const _OnboardingProgress({
    required this.page,
    required this.pages,
    required this.color,
    required this.trackColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < pages; i++)
          Expanded(
            child: Container(
              height: 4,
              margin: EdgeInsets.only(right: i == pages - 1 ? 0 : 6),
              decoration: BoxDecoration(
                color: i <= page ? color : trackColor,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
      ],
    );
  }
}

class _OnboardingCopyPage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Color textColor;
  final Color mutedColor;
  final Color accentColor;

  const _OnboardingCopyPage({
    required this.icon,
    required this.title,
    required this.body,
    required this.textColor,
    required this.mutedColor,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: accentColor.withOpacity(0.28)),
                  boxShadow: [
                    BoxShadow(
                      color: accentColor.withOpacity(0.16),
                      blurRadius: 34,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ),
                child: Icon(icon, color: accentColor, size: 34),
              ),
              const SizedBox(height: 28),
              Text(
                title,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: textColor,
                      fontWeight: FontWeight.w900,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              Text(
                body,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: mutedColor,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuestionPage extends StatelessWidget {
  final String question;
  final List<String> options;
  final String? selected;
  final ValueChanged<String> onSelected;
  final Color textColor;
  final Color mutedColor;
  final Color cardColor;
  final Color selectedColor;

  const _QuestionPage({
    required this.question,
    required this.options,
    required this.selected,
    required this.onSelected,
    required this.textColor,
    required this.mutedColor,
    required this.cardColor,
    required this.selectedColor,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                question,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: textColor,
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 22),
              ...options.map((option) {
                final isSelected = selected == option;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    onTap: () => onSelected(option),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 15,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? selectedColor.withOpacity(0.14)
                            : cardColor,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? selectedColor.withOpacity(0.8)
                              : Colors.white.withOpacity(0.08),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.22),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              option,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    color: textColor,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                          Icon(
                            isSelected
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded,
                            color: isSelected ? selectedColor : mutedColor,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeTab extends StatelessWidget {
  final bool active;
  final bool lockEnabled;
  final bool indefiniteUnlock;
  final Duration unlockRemaining;
  final Set<String> lockedPackages;
  final int lockedSelectionCount;
  final List<String> lockedSelectionSummaryLines;
  final int lockedSelectionPreviewRevision;

  final String difficulty;
  final bool solved;
  final bool timedUnlockActive;

  final int statSolved;
  final int statBestRating;
  final double accuracyPct;

  final Map<String, Uint8List> iconsByPkg;

  final VoidCallback onEditLockedApps;
  final bool showNativeSelectionPreview;
  final VoidCallback onBreakTime;
  final VoidCallback onSolveMorePuzzles;
  final VoidCallback onOpenDifficulty;

  const HomeTab({
    super.key,
    required this.active,
    required this.lockEnabled,
    required this.indefiniteUnlock,
    required this.unlockRemaining,
    required this.lockedPackages,
    required this.lockedSelectionCount,
    required this.lockedSelectionSummaryLines,
    required this.lockedSelectionPreviewRevision,
    required this.difficulty,
    required this.solved,
    required this.timedUnlockActive,
    required this.statSolved,
    required this.statBestRating,
    required this.accuracyPct,
    required this.iconsByPkg,
    required this.onEditLockedApps,
    required this.showNativeSelectionPreview,
    required this.onBreakTime,
    required this.onSolveMorePuzzles,
    required this.onOpenDifficulty,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isActive = lockEnabled;

    final statusText = isActive ? "Active" : "Inactive";

    final countdownText = isActive
        ? null
        : (indefiniteUnlock
            ? "Turn Lock ON in Settings"
            : "Apps will be locked in: ${formatRemaining(unlockRemaining)}");
    final primaryAction = timedUnlockActive ? onSolveMorePuzzles : onBreakTime;
    final primaryActionLabel = timedUnlockActive
        ? "Solve more puzzles"
        : solved
            ? "Choose unlock time"
            : "Solve puzzle to unlock apps";

    final lockedList = lockedPackages.toList()..sort();
    final hasAndroidLockedApps = lockedPackages.isNotEmpty;
    final showNativeLockedPreview = showNativeSelectionPreview &&
        !hasAndroidLockedApps &&
        lockedSelectionCount > 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenAdHeader(
            title: "Lock Mode",
            active: active,
            screenName: "home",
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 8),
              children: [
                GlassCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StatusDot(active: isActive),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  "Status",
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                ),
                                const Spacer(),
                                Pill(text: statusText, active: isActive),
                              ],
                            ),
                            if (countdownText != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                countdownText,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: cs.onSurface,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                            const SizedBox(height: 6),
                            InkWell(
                              onTap: onOpenDifficulty,
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    Icon(Icons.tune_rounded,
                                        size: 18, color: cs.onSurfaceVariant),
                                    const SizedBox(width: 8),
                                    Text(
                                      "Difficulty",
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                              color: cs.onSurfaceVariant),
                                    ),
                                    const Spacer(),
                                    Flexible(
                                      child: Text(
                                        getDifficultyDisplayName(difficulty),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                                fontWeight: FontWeight.w700),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(Icons.chevron_right_rounded,
                                        color: cs.onSurfaceVariant),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Your stats",
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: StatChip(
                              label: "Solved",
                              value: "$statSolved",
                              icon: Icons.check_circle_rounded,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: StatChip(
                              label: "Best",
                              value:
                                  statBestRating > 0 ? "$statBestRating" : "—",
                              icon: Icons.star_rounded,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: StatChip(
                              label: "Accuracy",
                              value:
                                  "${accuracyPct.isNaN ? 0 : accuracyPct.round()}%",
                              icon: Icons.insights_rounded,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            "Locked apps",
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                          ),
                          const Spacer(),
                          Text(
                            "$lockedSelectionCount",
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: onEditLockedApps,
                            child: const Text("Edit"),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (lockedSelectionCount == 0)
                        Text(
                          "No apps selected yet.",
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                        )
                      else if (showNativeLockedPreview)
                        IosLockedSelectionPreview(
                          selectionCount: lockedSelectionCount,
                          summaryLines: lockedSelectionSummaryLines,
                          revision: lockedSelectionPreviewRevision,
                        )
                      else
                        LayoutBuilder(
                          builder: (context, constraints) {
                            const pill = 38.0;
                            const gap = 7.0;

                            final maxPills =
                                ((constraints.maxWidth + gap) / (pill + gap))
                                    .floor()
                                    .clamp(1, 50);

                            final total = lockedList.length;

                            List<String> showPkgs;
                            int overflow;

                            if (total <= maxPills) {
                              showPkgs = lockedList;
                              overflow = 0;
                            } else {
                              final take = max(0, maxPills - 1);
                              showPkgs = lockedList.take(take).toList();
                              overflow = total - take;
                            }

                            return Row(
                              children: [
                                for (int i = 0; i < showPkgs.length; i++)
                                  Padding(
                                    padding: EdgeInsets.only(
                                      right: (i == showPkgs.length - 1 &&
                                              overflow == 0)
                                          ? 0
                                          : gap,
                                    ),
                                    child: AppIconPill(
                                      iconBytes: iconsByPkg[showPkgs[i]],
                                      fallbackText:
                                          _initialsFromPackage(showPkgs[i]),
                                    ),
                                  ),
                                if (overflow > 0)
                                  AppIconPill(
                                    iconBytes: null,
                                    fallbackText: "+$overflow",
                                  ),
                              ],
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: primaryAction,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.timer_rounded),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      primaryActionLabel,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  String _initialsFromPackage(String pkg) {
    final short = pkg.split('.').last;
    if (short.isEmpty) return "?";
    return short.length <= 2
        ? short.toUpperCase()
        : short.substring(0, 2).toUpperCase();
  }
}

class IosLockedSelectionPreview extends StatelessWidget {
  static const String _viewType = "chesslock/screen_time_selection_preview";

  final int selectionCount;
  final List<String> summaryLines;
  final int revision;

  const IosLockedSelectionPreview({
    super.key,
    required this.selectionCount,
    required this.summaryLines,
    required this.revision,
  });

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return NativeSelectionFallbackSummary(summaryLines: summaryLines);
    }

    return SizedBox(
      height: 46,
      width: double.infinity,
      child: UiKitView(
        key: ValueKey("$_viewType-$selectionCount-$revision"),
        viewType: _viewType,
        creationParams: <String, Object?>{
          "expectedCount": selectionCount,
          "revision": revision,
        },
        creationParamsCodec: const StandardMessageCodec(),
      ),
    );
  }
}

class NativeSelectionFallbackSummary extends StatelessWidget {
  final List<String> summaryLines;

  const NativeSelectionFallbackSummary({
    super.key,
    required this.summaryLines,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lines = summaryLines.isEmpty
        ? const <String>["Screen Time selections saved"]
        : summaryLines;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final line in lines)
              Container(
                constraints: const BoxConstraints(minHeight: 34),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: cs.secondaryContainer.withOpacity(0.55),
                  border: Border.all(
                    color: cs.outlineVariant.withOpacity(0.45),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.verified_user_rounded,
                      size: 16,
                      color: cs.onSecondaryContainer,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      line,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSecondaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// =========================
// PUZZLE TAB
// =========================
class PuzzleTab extends StatelessWidget {
  final bool active;
  final ChessPuzzle? puzzle;
  final bool loading;
  final String? loadError;

  final String sideToMoveLabel;
  final bool solved;
  final bool canUnlockApps;
  final bool canUserMove;
  final bool userPlaysBlack;
  final bool isChecking;

  // Hint/Skip
  final bool hintEnabled;
  final VoidCallback onHint;

  final bool skipEnabled;
  final VoidCallback onSkip;
  final VoidCallback onUnlockApps;

  final String? hintFromSquare;
  final bool hintBlinkOn;

  final ChessBoardController boardController;

  const PuzzleTab({
    super.key,
    required this.active,
    required this.puzzle,
    required this.loading,
    required this.loadError,
    required this.sideToMoveLabel,
    required this.solved,
    required this.canUnlockApps,
    required this.canUserMove,
    required this.userPlaysBlack,
    required this.isChecking,
    required this.hintEnabled,
    required this.onHint,
    required this.skipEnabled,
    required this.onSkip,
    required this.onUnlockApps,
    required this.hintFromSquare,
    required this.hintBlinkOn,
    required this.boardController,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenAdHeader(
            title: "Puzzle",
            active: active,
            screenName: "puzzle",
          ),
          if (loadError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(loadError!, style: TextStyle(color: cs.error)),
            ),
          const SizedBox(height: 6),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxBoardWidth = min(constraints.maxWidth, 460.0);
                final minBoard = min(maxBoardWidth, 160.0);
                final statusExtra =
                    puzzle != null && !canUserMove && !solved ? 22.0 : 0.0;
                final reservedHeight = 126.0 +
                    (puzzle != null ? 48.0 : 0.0) +
                    (loading ? 40.0 : 0.0) +
                    (canUnlockApps ? 42.0 : 0.0) +
                    statusExtra;
                final availableForBoard =
                    constraints.maxHeight - reservedHeight;
                final boardSize = min(
                  maxBoardWidth,
                  max(minBoard, availableForBoard),
                ).clamp(minBoard, maxBoardWidth).toDouble();

                return SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Column(
                        children: [
                          if (puzzle != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 9,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainerHighest
                                      .withOpacity(0.38),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: cs.outlineVariant.withOpacity(0.42),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        puzzle!.type,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              color: cs.onSurfaceVariant,
                                              fontWeight: FontWeight.w700,
                                            ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius:
                                            BorderRadius.circular(999),
                                        border: Border.all(
                                          color: cs.primary.withOpacity(0.22),
                                        ),
                                        color: cs.primary.withOpacity(0.10),
                                      ),
                                      child: Text(
                                        "Rating ${puzzle!.rating}",
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelMedium
                                            ?.copyWith(
                                              color: cs.primary,
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (loading)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 6),
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child:
                                    CircularProgressIndicator(strokeWidth: 3),
                              ),
                            ),
                          SizedBox.square(
                            dimension: boardSize,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: BoardWithHintOverlay(
                                userPlaysBlack: userPlaysBlack,
                                hintFromSquare: hintFromSquare,
                                hintBlinkOn: hintBlinkOn,
                                child: AdvancedChessBoard(
                                  controller: boardController,
                                  boardOrientation: userPlaysBlack
                                      ? PlayerColor.black
                                      : PlayerColor.white,
                                  enableMoves: canUserMove,
                                  highlightLastMove: false,
                                  lightSquareColor: const Color(0xFFE9E9E9),
                                  darkSquareColor: const Color(0xFF2D6B55),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            sideToMoveLabel,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (puzzle != null && !canUserMove && !solved) ...[
                            const SizedBox(height: 3),
                            Text(
                              isChecking ? "Checking…" : "Locked",
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: HintSkipButton(
                                  title: "Hint",
                                  enabled: hintEnabled,
                                  onTap: onHint,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: HintSkipButton(
                                  title: "Skip",
                                  enabled: skipEnabled,
                                  onTap: onSkip,
                                ),
                              ),
                            ],
                          ),
                          if (canUnlockApps) ...[
                            const SizedBox(height: 8),
                            FilledButton.icon(
                              onPressed: onUnlockApps,
                              style: FilledButton.styleFrom(
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                minimumSize: const Size(0, 38),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                              ),
                              icon:
                                  const Icon(Icons.lock_open_rounded, size: 18),
                              label: const Text("Unlock apps"),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class BoardWithHintOverlay extends StatelessWidget {
  final Widget child;
  final bool userPlaysBlack;
  final String? hintFromSquare;
  final bool hintBlinkOn;

  const BoardWithHintOverlay({
    super.key,
    required this.child,
    required this.userPlaysBlack,
    required this.hintFromSquare,
    required this.hintBlinkOn,
  });

  @override
  Widget build(BuildContext context) {
    if (hintFromSquare == null || !hintBlinkOn) return child;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = min(constraints.maxWidth, constraints.maxHeight);
        final sq = size / 8.0;

        final pos = _squareToOffset(hintFromSquare!, sq, userPlaysBlack);
        if (pos == null) return child;

        return Stack(
          children: [
            Positioned.fill(child: child),
            Positioned(
              left: pos.dx,
              top: pos.dy,
              width: sq,
              height: sq,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.45),
                    border: Border.all(
                      color: Colors.amber.withOpacity(0.9),
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Offset? _squareToOffset(String sqName, double sqSize, bool flip) {
    if (sqName.length != 2) return null;
    final fileChar = sqName[0].toLowerCase();
    final rankChar = sqName[1];

    final file = "abcdefgh".indexOf(fileChar);
    final rank = int.tryParse(rankChar);
    if (file < 0 || rank == null || rank < 1 || rank > 8) return null;

    final x0 = file;
    final y0 = rank - 1;

    final x = flip ? (7 - x0) : x0;
    final y = flip ? y0 : (7 - y0);

    return Offset(x * sqSize, y * sqSize);
  }
}

class HintSkipButton extends StatelessWidget {
  final String title;
  final bool enabled;
  final VoidCallback onTap;

  const HintSkipButton({
    super.key,
    required this.title,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final opacity = enabled ? 1.0 : 0.55;

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withOpacity(0.55),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
        ),
        child: Opacity(
          opacity: opacity,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  enabled ? "Tap to use" : "Please wait",
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =========================
// SETTINGS TAB
// =========================
class SettingsTab extends StatelessWidget {
  final bool active;
  final bool lockEnabled;
  final bool indefiniteUnlock;
  final Duration unlockRemaining;

  final String difficulty;

  final AppThemeMode themeMode;
  final Future<void> Function(AppThemeMode mode) onThemeModeChanged;
  final Future<void> Function(bool value) onLockToggle;
  final Future<void> Function() onOpenDifficulty;

  final Future<void> Function() onPrivacyPolicy;
  final Future<void> Function() onFeedback;
  final Future<void> Function() onRateApp;

  const SettingsTab({
    super.key,
    required this.active,
    required this.lockEnabled,
    required this.indefiniteUnlock,
    required this.unlockRemaining,
    required this.difficulty,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.onLockToggle,
    required this.onOpenDifficulty,
    required this.onPrivacyPolicy,
    required this.onFeedback,
    required this.onRateApp,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final statusLine = lockEnabled
        ? "Active"
        : (indefiniteUnlock
            ? "Off (manual)"
            : "Off (${formatRemaining(unlockRemaining)} left)");

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenAdHeader(
            title: "Settings",
            active: active,
            screenName: "settings",
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 28),
              children: [
                Text("Lock controls",
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 8),
                GlassCard(
                  child: SettingsRow(
                    icon: Icons.lock_rounded,
                    title: "Lock",
                    subtitle: "Status: $statusLine",
                    trailing: Switch(
                      value: lockEnabled,
                      onChanged: (v) => onLockToggle(v),
                    ),
                    onTap: () => onLockToggle(!lockEnabled),
                  ),
                ),
                const SizedBox(height: 12),
                Text("Puzzle settings",
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 8),
                GlassCard(
                  child: SettingsRow(
                    icon: Icons.extension_rounded,
                    title: "Difficulty",
                    subtitle: "Controls the next puzzle request",
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          getDifficultyDisplayName(difficulty),
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.chevron_right_rounded,
                            color: cs.onSurfaceVariant),
                      ],
                    ),
                    onTap: onOpenDifficulty,
                  ),
                ),
                const SizedBox(height: 12),
                Text("Appearance",
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 8),
                GlassCard(
                  child: SettingsRow(
                    icon: Icons.brightness_6_rounded,
                    title: "Theme",
                    subtitle: "Dark / Light / System",
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          switch (themeMode) {
                            AppThemeMode.dark => "Dark",
                            AppThemeMode.light => "Light",
                            AppThemeMode.system => "System",
                          },
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.chevron_right_rounded,
                            color: cs.onSurfaceVariant),
                      ],
                    ),
                    onTap: () async {
                      final selected = await showModalBottomSheet<AppThemeMode>(
                        context: context,
                        showDragHandle: true,
                        isScrollControlled: true,
                        builder: (ctx) {
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
                              child: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    OverflowBar(
                                      alignment: MainAxisAlignment.spaceBetween,
                                      overflowAlignment:
                                          OverflowBarAlignment.end,
                                      spacing: 8,
                                      overflowSpacing: 8,
                                      children: [
                                        Text("Theme",
                                            style: Theme.of(ctx)
                                                .textTheme
                                                .titleMedium),
                                        TextButton(
                                            onPressed: () => Navigator.pop(ctx),
                                            child: const Text("Close")),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    ...AppThemeMode.values.map((m) {
                                      final isSel = m == themeMode;
                                      final label = switch (m) {
                                        AppThemeMode.system => "System",
                                        AppThemeMode.dark => "Dark",
                                        AppThemeMode.light => "Light",
                                      };
                                      return ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        title: Text(label),
                                        trailing: isSel
                                            ? const Icon(Icons.check_rounded)
                                            : null,
                                        onTap: () => Navigator.pop(ctx, m),
                                      );
                                    }),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                      if (selected != null) {
                        await onThemeModeChanged(selected);
                      }
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Text("Support",
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 8),
                GlassCard(
                  child: Column(
                    children: [
                      SettingsRow(
                        icon: Icons.privacy_tip_rounded,
                        title: "Privacy Policy",
                        subtitle: "View our privacy policy",
                        trailing: Icon(Icons.chevron_right_rounded,
                            color: cs.onSurfaceVariant),
                        onTap: onPrivacyPolicy,
                      ),
                      Divider(
                          height: 8,
                          color: cs.outlineVariant.withValues(alpha: 0.35)),
                      SettingsRow(
                        icon: Icons.feedback_rounded,
                        title: "Feedback",
                        subtitle: "Send feedback by email",
                        trailing: Icon(Icons.chevron_right_rounded,
                            color: cs.onSurfaceVariant),
                        onTap: onFeedback,
                      ),
                      Divider(
                          height: 8,
                          color: cs.outlineVariant.withOpacity(0.35)),
                      SettingsRow(
                        icon: Icons.star_rate_rounded,
                        title: "Rate the app",
                        subtitle: "Leave a rating on the store",
                        trailing: Icon(Icons.chevron_right_rounded,
                            color: cs.onSurfaceVariant),
                        onTap: onRateApp,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =========================
// App picker
// =========================
typedef FetchLaunchableApps = Future<List<Map<String, dynamic>>> Function();
typedef FetchLaunchableAppIcons = Future<List<Map<String, dynamic>>> Function(
  Set<String> packageNames,
);

class LaunchableApp {
  final String packageName;
  final String appName;
  final Uint8List? iconBytes;

  const LaunchableApp({
    required this.packageName,
    required this.appName,
    required this.iconBytes,
  });

  LaunchableApp copyWith({
    Uint8List? iconBytes,
  }) {
    return LaunchableApp(
      packageName: packageName,
      appName: appName,
      iconBytes: iconBytes ?? this.iconBytes,
    );
  }
}

class AppSelectionPage extends StatefulWidget {
  final Set<String> selected;
  final bool editingDisabled;
  final FetchLaunchableApps fetchApps;
  final FetchLaunchableAppIcons? fetchIcons;

  const AppSelectionPage({
    super.key,
    required this.selected,
    required this.editingDisabled,
    required this.fetchApps,
    this.fetchIcons,
  });

  @override
  State<AppSelectionPage> createState() => _AppSelectionPageState();
}

class _AppSelectionPageState extends State<AppSelectionPage> {
  late Set<String> _selected;

  bool _loading = true;
  String? _error;

  final TextEditingController _searchCtrl = TextEditingController();
  List<LaunchableApp> _apps = [];
  List<LaunchableApp> _filtered = [];
  int _iconDecodeGeneration = 0;

  @override
  void initState() {
    super.initState();
    _selected = {...widget.selected};
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_loadApps());
    });

    _searchCtrl.addListener(() {
      setState(() {
        _applyCurrentFilter();
      });
    });
  }

  @override
  void dispose() {
    _iconDecodeGeneration++;
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadApps() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    final totalStopwatch = Stopwatch()..start();
    final fetchStopwatch = Stopwatch()..start();
    _debugAppPicker("load start");

    try {
      final raw = await widget.fetchApps();
      fetchStopwatch.stop();
      if (!mounted) return;

      final iconBase64ByPkg = <String, String>{};
      final list = raw
          .map((m) {
            final pkg = (m["packageName"] ?? "").toString();
            final name = (m["appName"] ?? "").toString();
            final b64 = (m["iconPngBase64"] ?? "").toString();
            if (pkg.isNotEmpty && b64.isNotEmpty) {
              iconBase64ByPkg[pkg] = b64;
            }
            return LaunchableApp(
              packageName: pkg,
              appName: name,
              iconBytes: null,
            );
          })
          .where((a) => a.packageName.isNotEmpty)
          .toList();

      _iconDecodeGeneration++;
      final generation = _iconDecodeGeneration;
      setState(() {
        _apps = list;
        _applyCurrentFilter();
        _loading = false;
      });
      _debugAppPicker(
        "rows visible; count=${list.length} "
        "fetchMs=${fetchStopwatch.elapsedMilliseconds} "
        "totalMs=${totalStopwatch.elapsedMilliseconds}",
      );

      unawaited(
        _loadIconsAfterRowsVisible(
          packages: [for (final app in list) app.packageName],
          fallbackIconBase64ByPkg: iconBase64ByPkg,
          generation: generation,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = "Failed to load apps: $e";
        _loading = false;
      });
      _debugAppPicker(
        "load failed; fetchMs=${fetchStopwatch.elapsedMilliseconds} error=$e",
      );
    }
  }

  void _applyCurrentFilter() {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) {
      _filtered = _apps;
      return;
    }

    _filtered = _apps
        .where((a) =>
            a.appName.toLowerCase().contains(q) ||
            a.packageName.toLowerCase().contains(q))
        .toList();
  }

  Future<void> _decodeIconsProgressively(
    Map<String, String> iconBase64ByPkg, {
    required int generation,
  }) async {
    if (iconBase64ByPkg.isEmpty) return;

    final stopwatch = Stopwatch()..start();
    const batchSize = 10;
    var decodedInBatch = <String, Uint8List>{};
    var processed = 0;

    for (final entry in iconBase64ByPkg.entries) {
      if (!mounted || generation != _iconDecodeGeneration) return;

      final bytes = decodeIconPngBase64(entry.value);
      if (bytes != null) {
        decodedInBatch[entry.key] = bytes;
      }
      processed++;

      if (processed % batchSize == 0) {
        _applyDecodedIcons(decodedInBatch, generation: generation);
        decodedInBatch = <String, Uint8List>{};
        await Future<void>.delayed(Duration.zero);
      }
    }

    _applyDecodedIcons(decodedInBatch, generation: generation);
    _debugAppPicker(
      "icons decoded; requested=${iconBase64ByPkg.length} "
      "durationMs=${stopwatch.elapsedMilliseconds}",
    );
  }

  Future<void> _loadIconsAfterRowsVisible({
    required List<String> packages,
    required Map<String, String> fallbackIconBase64ByPkg,
    required int generation,
  }) async {
    final fetchIcons = widget.fetchIcons;
    if (fetchIcons == null) {
      await _decodeIconsProgressively(
        fallbackIconBase64ByPkg,
        generation: generation,
      );
      return;
    }

    if (packages.isEmpty) return;

    final stopwatch = Stopwatch()..start();
    const batchSize = 30;
    var loaded = 0;
    _debugAppPicker("icon fetch start; packages=${packages.length}");

    for (var start = 0; start < packages.length; start += batchSize) {
      if (!mounted || generation != _iconDecodeGeneration) return;

      final end = min(start + batchSize, packages.length);
      final batch = packages.sublist(start, end).toSet();
      try {
        final rawIcons = await fetchIcons(batch);
        if (!mounted || generation != _iconDecodeGeneration) return;

        final iconBase64ByPkg = <String, String>{};
        for (final rawIcon in rawIcons) {
          final pkg = (rawIcon["packageName"] ?? "").toString();
          final b64 = (rawIcon["iconPngBase64"] ?? "").toString();
          if (pkg.isNotEmpty && b64.isNotEmpty) {
            iconBase64ByPkg[pkg] = b64;
          }
        }

        loaded += iconBase64ByPkg.length;
        await _decodeIconsProgressively(
          iconBase64ByPkg,
          generation: generation,
        );
      } catch (error) {
        _debugAppPicker(
          "icon fetch batch failed; start=$start count=${batch.length} "
          "error=$error",
        );
      }

      await Future<void>.delayed(Duration.zero);
    }

    _debugAppPicker(
      "icon fetch end; decoded=$loaded packages=${packages.length} "
      "durationMs=${stopwatch.elapsedMilliseconds}",
    );
  }

  void _applyDecodedIcons(
    Map<String, Uint8List> decodedIcons, {
    required int generation,
  }) {
    if (!mounted ||
        decodedIcons.isEmpty ||
        generation != _iconDecodeGeneration) {
      return;
    }

    setState(() {
      _apps = [
        for (final app in _apps)
          decodedIcons.containsKey(app.packageName)
              ? app.copyWith(iconBytes: decodedIcons[app.packageName])
              : app,
      ];
      _applyCurrentFilter();
    });
  }

  void _debugAppPicker(String message) {
    if (!kDebugMode) return;
    debugPrint("[app-list][picker] $message");
  }

  String _initials(String name) {
    final t = name.trim();
    if (t.isEmpty) return "?";
    final parts = t.split(RegExp(r"\s+")).where((x) => x.isNotEmpty).toList();
    if (parts.length == 1) {
      final s = parts.first;
      return s.length <= 2 ? s.toUpperCase() : s.substring(0, 2).toUpperCase();
    }
    final a = parts[0];
    final b = parts[1];
    return (a.isNotEmpty ? a[0] : "") + (b.isNotEmpty ? b[0] : "");
  }

  Future<void> _saveSelectedApps() async {
    if (widget.editingDisabled) {
      Navigator.pop(context);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Lock selected apps?"),
        content: const Text(
          "Opening these apps will require you to solve one chess puzzle.\n"
          "You can change this anytime by solving a puzzle.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Lock Apps"),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;
    Navigator.pop(context, _selected);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text("Locked apps (${_selected.length})"),
        actions: [
          TextButton(
            onPressed: _saveSelectedApps,
            child: const Text("Save"),
          )
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : Column(
                  children: [
                    if (widget.editingDisabled)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest.withOpacity(0.62),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: cs.outlineVariant.withOpacity(0.45)),
                          ),
                          child: const Text("Editing disabled."),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: "Search apps…",
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: _filtered.length,
                        itemBuilder: (context, i) {
                          final app = _filtered[i];
                          final pkg = app.packageName;
                          final checked = _selected.contains(pkg);

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Material(
                              color: cs.surfaceContainer.withOpacity(0.92),
                              borderRadius: BorderRadius.circular(20),
                              clipBehavior: Clip.antiAlias,
                              child: CheckboxListTile(
                                value: checked,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                checkboxShape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                onChanged: widget.editingDisabled
                                    ? null
                                    : (v) {
                                        setState(() {
                                          if (v == true) {
                                            _selected.add(pkg);
                                          } else {
                                            _selected.remove(pkg);
                                          }
                                        });
                                      },
                                title: Text(
                                  app.appName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                subtitle: Text(pkg,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                secondary: Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: cs.surfaceContainerHighest
                                        .withOpacity(0.65),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color:
                                          cs.outlineVariant.withOpacity(0.45),
                                    ),
                                  ),
                                  child: Center(
                                    child: (app.iconBytes != null &&
                                            app.iconBytes!.isNotEmpty)
                                        ? ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            child: Image.memory(
                                              app.iconBytes!,
                                              width: 28,
                                              height: 28,
                                              fit: BoxFit.contain,
                                            ),
                                          )
                                        : Text(
                                            _initials(app.appName),
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w900),
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}

// =========================
// Reusable UI pieces
// =========================
class GlassCard extends StatelessWidget {
  final Widget child;
  const GlassCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainer.withOpacity(dark ? 0.92 : 0.98),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: dark
              ? Colors.white.withOpacity(0.07)
              : cs.outlineVariant.withOpacity(0.8),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(dark ? 0.26 : 0.07),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }
}

class StatusDot extends StatelessWidget {
  final bool active;
  const StatusDot({super.key, required this.active});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = active ? cs.primary : cs.onSurfaceVariant.withOpacity(0.55);
    return Container(
      width: 12,
      height: 12,
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: c,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            blurRadius: 10,
            color: c.withOpacity(0.35),
          ),
        ],
      ),
    );
  }
}

class Pill extends StatelessWidget {
  final String text;
  final bool active;

  const Pill({super.key, required this.text, required this.active});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = active
        ? cs.primary.withOpacity(0.14)
        : cs.surfaceContainerHighest.withOpacity(0.35);
    final fg = active ? cs.primary : cs.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withOpacity(0.22)),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: fg,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class AppIconPill extends StatelessWidget {
  final Uint8List? iconBytes;
  final String fallbackText;

  const AppIconPill({
    super.key,
    required this.iconBytes,
    required this.fallbackText,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: cs.surfaceContainerHighest.withOpacity(0.7),
        border: Border.all(color: cs.primary.withOpacity(0.12)),
      ),
      child: Center(
        child: (iconBytes != null && iconBytes!.isNotEmpty)
            ? ClipOval(
                child: Image.memory(
                  iconBytes!,
                  width: 24,
                  height: 24,
                  fit: BoxFit.contain,
                ),
              )
            : Text(
                fallbackText.isEmpty ? "?" : fallbackText,
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
                textAlign: TextAlign.center,
              ),
      ),
    );
  }
}

class StatChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const StatChip({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.48),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.36)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 1),
                Text(value,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback onTap;

  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.primary.withOpacity(0.16)),
              ),
              child: Icon(icon, color: cs.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}

class ActionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const ActionTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withOpacity(0.40),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
        ),
        child: Row(
          children: [
            Icon(icon, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
