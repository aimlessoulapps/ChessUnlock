import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'ad_consent_service.dart';
import 'ad_units.dart';

/// One ad per placement, owned by the shell rather than by a tab's platform view.
class NativeAdCache extends ChangeNotifier with WidgetsBindingObserver {
  NativeAdCache(
      {required bool enabled,
      required Brightness brightness,
      this.placements = NativePlacement.values,
      DateTime Function()? now})
      : _enabled = enabled,
        _brightness = brightness,
        _now = now ?? DateTime.now {
    _consent = AdConsentService.instance;
    _consent.addListener(_sync);
    WidgetsBinding.instance.addObserver(this);
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _sync();
  }
  static const maxAge = Duration(minutes: 55);
  final Iterable<NativePlacement> placements;
  final DateTime Function() _now;
  late final AdConsentService _consent;
  final _entries = <NativePlacement, _Entry>{};
  final _owners = <NativePlacement, Object>{};
  bool _enabled, _disposed = false, _foreground = true;
  Brightness _brightness;
  bool get _eligible =>
      !_disposed && _enabled && AdUnits.supported && _consent.canRequestAds;

  NativeAd? adFor(NativePlacement placement) {
    final entry = _entries[placement];
    return _eligible &&
            entry?.loadedAt != null &&
            _now().difference(entry!.loadedAt!) < maxAge
        ? entry.ad
        : null;
  }

  bool claim(NativePlacement placement, Object owner) {
    if (_owners[placement] != null && !identical(_owners[placement], owner)) {
      return false;
    }
    _owners[placement] = owner;
    return true;
  }

  void release(NativePlacement placement, Object owner) {
    if (identical(_owners[placement], owner)) _owners.remove(placement);
  }

  void configure({required bool enabled, required Brightness brightness}) {
    if (_enabled == enabled && _brightness == brightness) return;
    _enabled = enabled;
    if (_brightness != brightness) {
      _brightness = brightness;
      _clear();
      notifyListeners();
    }
    _sync();
  }

  void _retire(_Entry entry) {
    entry.timer?.cancel();
    final ad = entry.ad;
    // Let every AdWidget detach before disposing its native platform resources.
    if (ad != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => ad.dispose());
    }
    WidgetsBinding.instance.scheduleFrame();
  }

  void _clear() {
    for (final entry in _entries.values) {
      _retire(entry);
    }
    _entries.clear();
  }

  void _sync() {
    if (!_eligible) {
      _clear();
      if (!_disposed) notifyListeners();
      return;
    }
    if (!_foreground) return;
    for (final placement in placements) {
      final entry = _entries[placement];
      if (entry?.loadedAt != null &&
          _now().difference(entry!.loadedAt!) >= maxAge) {
        _entries.remove(placement);
        _retire(entry);
        notifyListeners();
      }
      _load(placement);
      final current = _entries[placement];
      if (current?.loadedAt != null && current!.timer == null) {
        _scheduleExpiry(placement, current);
      }
    }
  }

  void _scheduleExpiry(NativePlacement placement, _Entry entry) {
    entry.timer = Timer(maxAge - _now().difference(entry.loadedAt!), () {
      if (!identical(_entries[placement], entry)) return;
      _entries.remove(placement);
      _retire(entry);
      notifyListeners();
      if (_foreground) _load(placement);
    });
  }

  void _load(NativePlacement placement) {
    if (!_eligible || !_foreground || _entries.containsKey(placement)) return;
    final entry = _Entry();
    _entries[placement] = entry;
    bool current() => _eligible && identical(_entries[placement], entry);
    void failed() {
      if (!current()) return;
      entry.ad?.dispose();
      entry.ad = null;
      notifyListeners();
      if (_foreground) {
        entry.timer = Timer(const Duration(minutes: 1), () {
          if (!identical(_entries[placement], entry)) return;
          _entries.remove(placement);
          _load(placement);
        });
      } else {
        _entries.remove(placement);
      }
    }

    final ad = NativeAd(
      adUnitId: AdUnits.native(placement),
      factoryId: 'chessunlockNative',
      customOptions: {
        'medium': placement.usesMediaLayout,
        'dark': _brightness == Brightness.dark
      },
      request: const AdRequest(),
      nativeAdOptions: NativeAdOptions(
          mediaAspectRatio: MediaAspectRatio.landscape,
          videoOptions: VideoOptions(startMuted: true)),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (!current()) {
            ad.dispose();
            return;
          }
          entry.loadedAt = _now();
          if (_foreground) _scheduleExpiry(placement, entry);
          notifyListeners();
        },
        onAdFailedToLoad: (ad, _) {
          if (current()) {
            failed();
          } else {
            ad.dispose();
          }
        },
      ),
    );
    entry.ad = ad;
    unawaited(ad.load().catchError((Object _) => failed()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _sync();
    } else {
      for (final placement in _entries.keys.toList()) {
        final entry = _entries[placement]!;
        entry.timer?.cancel();
        entry.timer = null;
        if (entry.ad == null) _entries.remove(placement);
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _consent.removeListener(_sync);
    WidgetsBinding.instance.removeObserver(this);
    _clear();
    _owners.clear();
    super.dispose();
  }
}

class _Entry {
  NativeAd? ad;
  DateTime? loadedAt;
  Timer? timer;
}

class NativeAdScope extends StatefulWidget {
  const NativeAdScope({super.key, required this.enabled, required this.child});
  final bool enabled;
  final Widget child;
  static NativeAdCache? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_NativeAdProvider>()?.cache;
  @override
  State<NativeAdScope> createState() => _NativeAdScopeState();
}

class _NativeAdScopeState extends State<NativeAdScope> {
  NativeAdCache? _cache;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configure();
  }

  @override
  void didUpdateWidget(covariant NativeAdScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    _configure();
  }

  void _configure() {
    final brightness = Theme.of(context).brightness;
    _cache ??= NativeAdCache(enabled: widget.enabled, brightness: brightness);
    _cache!.configure(enabled: widget.enabled, brightness: brightness);
  }

  @override
  void dispose() {
    _cache!.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _NativeAdProvider(cache: _cache!, child: widget.child);
}

class _NativeAdProvider extends InheritedWidget {
  const _NativeAdProvider({required this.cache, required super.child});
  final NativeAdCache cache;
  @override
  bool updateShouldNotify(_NativeAdProvider oldWidget) =>
      oldWidget.cache != cache;
}
