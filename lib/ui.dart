import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:advanced_chess_board/advanced_chess_board.dart';
import 'package:advanced_chess_board/chess_board_controller.dart';
import 'package:advanced_chess_board/models/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' hide Uint8List;
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
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
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
  const BannerAdSlot({super.key, this.height = 60, this.active = true});

  @override
  State<BannerAdSlot> createState() => _BannerAdSlotState();
}

class _BannerAdSlotState extends State<BannerAdSlot>
    with WidgetsBindingObserver {
  static const _testBannerAdUnitId = "ca-app-pub-3940256099942544/6300978111";
  static const _initialRetryDelay = Duration(seconds: 30);
  static const _maxRetryDelay = Duration(minutes: 5);
  static const _refreshCooldown = Duration(minutes: 1);

  BannerAd? _bannerAd;
  BannerAd? _loadingBannerAd;
  bool _loaded = false;
  bool _loading = false;
  bool _appResumed = true;
  DateTime? _lastLoadStartedAt;
  DateTime? _nextRetryAt;
  Duration _retryDelay = _initialRetryDelay;
  Timer? _retryTimer;

  bool get _adsSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool get _hasLoadedBanner => _loaded && _bannerAd != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.active) {
      _ensureBannerAdLoaded();
    }
  }

  @override
  void didUpdateWidget(covariant BannerAdSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active) {
      _cancelRetryTimer();
      return;
    }
    if (!oldWidget.active) {
      _ensureBannerAdLoaded(refreshLoadedAd: true);
    } else if (!_hasLoadedBanner) {
      _ensureBannerAdLoaded();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _appResumed = true;
      if (widget.active) {
        _ensureBannerAdLoaded(refreshLoadedAd: true);
      }
    } else {
      _appResumed = false;
      _cancelRetryTimer();
    }
  }

  void _ensureBannerAdLoaded({bool refreshLoadedAd = false}) {
    if (!_adsSupported || !widget.active || !_appResumed || _loading) {
      return;
    }

    if (_hasLoadedBanner) {
      if (refreshLoadedAd && _canRefreshLoadedBanner) {
        _disposeLoadedBanner(afterFrame: true);
        if (mounted) setState(() {});
      } else {
        return;
      }
    }

    final nextRetryAt = _nextRetryAt;
    if (nextRetryAt != null) {
      final remaining = nextRetryAt.difference(DateTime.now());
      if (remaining > Duration.zero) {
        _scheduleRetry(remaining);
        return;
      }
    }

    _loadBannerAd();
  }

  bool get _canRefreshLoadedBanner {
    final lastLoadStartedAt = _lastLoadStartedAt;
    if (lastLoadStartedAt == null) return true;
    return DateTime.now().difference(lastLoadStartedAt) >= _refreshCooldown;
  }

  void _scheduleRetry(Duration delay) {
    if (!_adsSupported ||
        !widget.active ||
        !_appResumed ||
        _hasLoadedBanner ||
        _loading) {
      return;
    }
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      if (!mounted) return;
      _ensureBannerAdLoaded();
    });
  }

  void _cancelRetryTimer() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void _loadBannerAd() {
    if (!_adsSupported || !_appResumed || _loading || _hasLoadedBanner) return;

    _cancelRetryTimer();
    _loading = true;
    _lastLoadStartedAt = DateTime.now();
    _nextRetryAt = null;

    final ad = BannerAd(
      adUnitId: _testBannerAdUnitId,
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          _loadingBannerAd = null;
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _bannerAd = ad as BannerAd;
            _loaded = true;
            _loading = false;
            _nextRetryAt = null;
            _retryDelay = _initialRetryDelay;
          });
        },
        onAdFailedToLoad: (ad, error) {
          _loadingBannerAd = null;
          ad.dispose();
          if (!mounted) return;
          setState(() {
            _bannerAd = null;
            _loaded = false;
            _loading = false;
          });
          final delayBeforeNextAttempt = _retryDelay;
          _nextRetryAt = DateTime.now().add(delayBeforeNextAttempt);
          _scheduleRetry(delayBeforeNextAttempt);
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
    _loadingBannerAd?.dispose();
    _disposeLoadedBanner();
    super.dispose();
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

// =========================
// HOME TAB
// =========================
class HomeTab extends StatelessWidget {
  final bool active;
  final bool lockEnabled;
  final bool indefiniteUnlock;
  final Duration unlockRemaining;
  final Set<String> lockedPackages;

  final String difficulty;
  final bool solved;

  final int statSolved;
  final int statBestRating;
  final double accuracyPct;

  final Map<String, Uint8List> iconsByPkg;

  final VoidCallback onEditLockedApps;
  final VoidCallback onBreakTime;
  final VoidCallback onOpenDifficulty;

  const HomeTab({
    super.key,
    required this.active,
    required this.lockEnabled,
    required this.indefiniteUnlock,
    required this.unlockRemaining,
    required this.lockedPackages,
    required this.difficulty,
    required this.solved,
    required this.statSolved,
    required this.statBestRating,
    required this.accuracyPct,
    required this.iconsByPkg,
    required this.onEditLockedApps,
    required this.onBreakTime,
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

    final lockedList = lockedPackages.toList()..sort();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Text(
            "Lock Mode",
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 8),
              children: [
                BannerAdSlot(height: 54, active: active),
                const SizedBox(height: 8),
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
                            "${lockedPackages.length}",
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
                      if (lockedPackages.isEmpty)
                        Text(
                          "No apps selected yet.",
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
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
              onPressed: onBreakTime,
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
                      solved
                          ? "Choose unlock time"
                          : "Solve puzzle to unlock apps",
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
          const SizedBox(height: 2),
          Text(
            "Puzzle",
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          BannerAdSlot(height: 54, active: active),
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
                final reservedHeight = 132.0 +
                    (puzzle != null ? 28.0 : 0.0) +
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
                    child: Center(
                      child: Column(
                        children: [
                          if (puzzle != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
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
                                            fontWeight: FontWeight.w600,
                                          ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 9, vertical: 4),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                          color: cs.outlineVariant
                                              .withOpacity(0.5)),
                                      color: cs.surfaceContainerHighest
                                          .withOpacity(0.35),
                                    ),
                                    child: Text(
                                      "Rating ${puzzle!.rating}",
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                              fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                ],
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
          const SizedBox(height: 2),
          // ✅ Your change: Settings title first (like other tabs)
          Text(
            "Settings",
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          BannerAdSlot(height: 54, active: active),
          const SizedBox(height: 8),

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

class LaunchableApp {
  final String packageName;
  final String appName;
  final Uint8List? iconBytes;

  const LaunchableApp({
    required this.packageName,
    required this.appName,
    required this.iconBytes,
  });
}

class AppSelectionPage extends StatefulWidget {
  final Set<String> selected;
  final bool editingDisabled;
  final FetchLaunchableApps fetchApps;

  const AppSelectionPage({
    super.key,
    required this.selected,
    required this.editingDisabled,
    required this.fetchApps,
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

  @override
  void initState() {
    super.initState();
    _selected = {...widget.selected};
    _loadApps();

    _searchCtrl.addListener(() {
      final q = _searchCtrl.text.trim().toLowerCase();
      setState(() {
        if (q.isEmpty) {
          _filtered = _apps;
        } else {
          _filtered = _apps
              .where((a) =>
                  a.appName.toLowerCase().contains(q) ||
                  a.packageName.toLowerCase().contains(q))
              .toList();
        }
      });
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadApps() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final raw = await widget.fetchApps();
      if (!mounted) return;

      final list = raw
          .map((m) {
            final pkg = (m["packageName"] ?? "").toString();
            final name = (m["appName"] ?? "").toString();
            final b64 = (m["iconPngBase64"] ?? "").toString();
            final bytes = decodeIconPngBase64(b64);
            return LaunchableApp(
              packageName: pkg,
              appName: name,
              iconBytes: bytes,
            );
          })
          .where((a) => a.packageName.isNotEmpty)
          .toList();

      setState(() {
        _apps = list;
        _filtered = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = "Failed to load apps: $e";
        _loading = false;
      });
    }
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
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest.withOpacity(0.55),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: cs.outlineVariant.withOpacity(0.45)),
                          ),
                          child: const Text("Editing disabled."),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: "Search apps…",
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        itemCount: _filtered.length,
                        separatorBuilder: (_, __) => Divider(
                            height: 1,
                            color: cs.outlineVariant.withOpacity(0.35)),
                        itemBuilder: (context, i) {
                          final app = _filtered[i];
                          final pkg = app.packageName;
                          final checked = _selected.contains(pkg);

                          return CheckboxListTile(
                            value: checked,
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
                            title: Text(app.appName),
                            subtitle: Text(pkg,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            secondary: CircleAvatar(
                              backgroundColor:
                                  cs.surfaceContainerHighest.withOpacity(0.55),
                              child: (app.iconBytes != null &&
                                      app.iconBytes!.isNotEmpty)
                                  ? ClipOval(
                                      child: Image.memory(
                                        app.iconBytes!,
                                        width: 26,
                                        height: 26,
                                        fit: BoxFit.contain,
                                      ),
                                    )
                                  : Text(
                                      _initials(app.appName),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800),
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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.55),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
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
        shape: BoxShape.circle,
        color: cs.surfaceContainerHighest.withOpacity(0.55),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
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
        color: cs.surfaceContainerHighest.withOpacity(0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
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
                color: cs.surfaceContainerHighest.withOpacity(0.35),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
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
