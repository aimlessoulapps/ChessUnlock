import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PremiumAccessService extends ChangeNotifier {
  PremiumAccessService(this._prefsFuture);

  final Future<SharedPreferences> _prefsFuture;

  static const premiumEnabledPrefsKey = "premium.enabled";
  static const developerOverridePrefsKey = premiumEnabledPrefsKey;
  static const _legacyDeveloperOverridePrefsKey = "premium.developerOverride";
  static const freeUnlockMinutes = 15;
  static const premiumUnlockMinutes = 30;
  static const premiumPuzzleActionDelay = Duration(seconds: 30);

  bool _isPremium = false;
  bool _manualPremiumEnabled = false;

  bool get isPremium => _isPremium;
  bool get premiumEnabled => _manualPremiumEnabled;
  bool get developerPremiumOverride => _manualPremiumEnabled;

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
