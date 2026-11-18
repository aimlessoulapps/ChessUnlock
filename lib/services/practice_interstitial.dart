import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ad_units.dart';

/// Persisted frequency cap. A missed opportunity is carried to the next solved
/// practice transition, never shown later in an active puzzle or on resume.
class PracticeAdCounter {
  PracticeAdCounter(this.prefs);
  final SharedPreferences prefs;
  static const countKey = 'ads.practice.completed.v1';
  static const shownKey = 'ads.practice.lastShown.v1';
  int get count => prefs.getInt(countKey) ?? 0;
  Future<void> completed() async {
    await prefs.setInt(countKey, (count + 1).clamp(0, 5));
  }

  bool due(DateTime now) {
    final last = prefs.getInt(shownKey);
    return count >= 5 &&
        (last == null ||
            now.millisecondsSinceEpoch - last >=
                const Duration(minutes: 10).inMilliseconds);
  }

  Future<void> displayed(DateTime now) async {
    await prefs.setInt(shownKey, now.millisecondsSinceEpoch);
    await prefs.setInt(countKey, 0);
  }
}

class PracticeInterstitial with WidgetsBindingObserver {
  PracticeInterstitial(this.prefsFuture, {required this.allowed}) {
    WidgetsBinding.instance.addObserver(this);
  }
  final Future<SharedPreferences> prefsFuture;
  final bool Function() allowed;
  InterstitialAd? _ad;
  DateTime? _loadedAt;
  bool _loading = false, _disposed = false, _showing = false;
  bool _resumed = true;
  int _generation = 0;
  Timer? _retry;
  bool get _eligible => !_disposed && allowed() && AdUnits.supported;
  void sync() {
    if (!_eligible) {
      _generation++;
      _loading = false;
      _retry?.cancel();
      _retry = null;
      _ad?.dispose();
      _ad = null;
      return;
    }
    preload();
  }

  void preload() {
    if (!_eligible || !_resumed || _showing || _loading || _retry != null) {
      return;
    }
    if (_ad != null &&
        DateTime.now().difference(_loadedAt!) < const Duration(minutes: 55)) {
      return;
    }
    _ad?.dispose();
    _ad = null;
    _loading = true;
    final generation = ++_generation;
    void failed() {
      if (_disposed || generation != _generation) return;
      _loading = false;
      if (_eligible && _resumed) {
        _retry = Timer(const Duration(minutes: 1), () {
          _retry = null;
          preload();
        });
      }
    }

    unawaited(InterstitialAd.load(
      adUnitId: AdUnits.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          if (!_eligible || generation != _generation) {
            ad.dispose();
            return;
          }
          _loading = false;
          _ad = ad;
          _loadedAt = DateTime.now();
        },
        onAdFailedToLoad: (_) => failed(),
      ),
    ).catchError((Object _) => failed()));
  }

  Future<void> recordCompletion() async {
    if (!_eligible) return;
    final prefs = await prefsFuture;
    if (_eligible) await PracticeAdCounter(prefs).completed();
  }

  Future<void> atTransition({required bool Function() safe}) async {
    final prefs = await prefsFuture;
    final counter = PracticeAdCounter(prefs);
    if (!_eligible ||
        !_resumed ||
        _showing ||
        !safe() ||
        !counter.due(DateTime.now())) {
      return;
    }
    final ad = _ad;
    if (ad == null ||
        DateTime.now().difference(_loadedAt!) >= const Duration(minutes: 55)) {
      preload();
      return;
    }
    _ad = null;
    _showing = true;
    final done = Completer<void>();
    void finish() {
      ad.dispose();
      _showing = false;
      if (!done.isCompleted) done.complete();
      preload();
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) {
        unawaited(counter.displayed(DateTime.now()).catchError((Object _) {}));
      },
      onAdDismissedFullScreenContent: (_) => finish(),
      onAdFailedToShowFullScreenContent: (_, __) => finish(),
    );
    try {
      await ad.show();
    } catch (_) {
      finish();
    }
    await done.future;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    if (_resumed) {
      sync();
    } else {
      _retry?.cancel();
      _retry = null;
    }
  }

  void dispose() {
    _disposed = true;
    sync();
    WidgetsBinding.instance.removeObserver(this);
  }
}
