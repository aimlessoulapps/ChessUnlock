import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PremiumAccessService extends ChangeNotifier {
  PremiumAccessService(this._prefsFuture);

  final Future<SharedPreferences> _prefsFuture;

  static const premiumEnabledPrefsKey = "premium.enabled";
  static const developerOverridePrefsKey = premiumEnabledPrefsKey;
  static const _legacyDeveloperOverridePrefsKey = "premium.developerOverride";
  static const freeUnlockMinutes = 60;
  static const premiumUnlockMinutes = 180;
  static const defaultUnlockMinutes = 15;
  static const unlockDurationPrefsKey = "unlockDurationMinutes";
  static const unlockMinuteOptions = <int>[
    15,
    30,
    45,
    60,
    75,
    90,
    105,
    120,
    135,
    150,
    165,
    180,
  ];
  static const premiumPuzzleActionDelay = Duration(seconds: 30);

  bool _isPremium = false;
  bool _manualPremiumEnabled = false;

  bool get isPremium => _isPremium;
  bool get premiumEnabled => _manualPremiumEnabled;
  bool get developerPremiumOverride => _manualPremiumEnabled;

  bool canUnlockForMinutes(int minutes) =>
      unlockMinuteOptions.contains(minutes) &&
      minutes <= (_isPremium ? premiumUnlockMinutes : freeUnlockMinutes);

  int normalizeUnlockMinutes(int? minutes) {
    final limit = _isPremium ? premiumUnlockMinutes : freeUnlockMinutes;
    final clamped =
        (minutes ?? defaultUnlockMinutes).clamp(defaultUnlockMinutes, limit);
    return unlockMinuteOptions.lastWhere((option) => option <= clamped);
  }

  Future<int> loadUnlockMinutes() async {
    final prefs = await _prefsFuture;
    final minutes =
        normalizeUnlockMinutes(prefs.getInt(unlockDurationPrefsKey));
    await prefs.setInt(unlockDurationPrefsKey, minutes);
    return minutes;
  }

  Future<void> saveUnlockMinutes(int minutes) async {
    if (!canUnlockForMinutes(minutes)) {
      throw ArgumentError.value(
          minutes, "minutes", "Unlock duration not allowed");
    }
    final prefs = await _prefsFuture;
    await prefs.setInt(unlockDurationPrefsKey, minutes);
  }

  static String formatUnlockMinutes(int minutes) {
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    if (hours == 0) return "$remainder min";
    return remainder == 0 ? "$hours hr" : "$hours hr $remainder min";
  }

  Future<void> refreshPremiumStatus() async {
    final prefs = await _prefsFuture;
    final manualPremiumEnabled = prefs.getBool(premiumEnabledPrefsKey) ??
        prefs.getBool(_legacyDeveloperOverridePrefsKey) ??
        false;
    final storeEntitlementActive = await _loadStoreEntitlementStatus();
    final nextIsPremium = storeEntitlementActive || manualPremiumEnabled;
    final changed = _isPremium != nextIsPremium ||
        _manualPremiumEnabled != manualPremiumEnabled;

    _isPremium = nextIsPremium;
    _manualPremiumEnabled = manualPremiumEnabled;

    _debugPremium(
      "active=$_isPremium source=${_premiumSourceLabel(
        storeEntitlementActive: storeEntitlementActive,
        manualPremiumEnabled: manualPremiumEnabled,
      )}",
    );

    if (changed) notifyListeners();
  }

  Future<void> setPremiumEnabled(bool value) async {
    final prefs = await _prefsFuture;
    await prefs.setBool(premiumEnabledPrefsKey, value);
    await prefs.setBool(_legacyDeveloperOverridePrefsKey, value);
    await refreshPremiumStatus();
  }

  Future<void> setDeveloperPremiumOverride(bool value) async {
    await setPremiumEnabled(value);
  }

  Future<bool> _loadStoreEntitlementStatus() async {
    return false;
  }

  String _premiumSourceLabel({
    required bool storeEntitlementActive,
    required bool manualPremiumEnabled,
  }) {
    if (storeEntitlementActive) return "store_entitlement";
    if (manualPremiumEnabled) return "manual_toggle";
    return "none";
  }

  void _debugPremium(String message) {
    if (!kDebugMode) return;
    debugPrint("[premium] $message");
  }
}
