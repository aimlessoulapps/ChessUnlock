import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PremiumAccessService extends ChangeNotifier {
  PremiumAccessService(this._prefsFuture);

  final Future<SharedPreferences> _prefsFuture;

  static const developerOverridePrefsKey = "premium.developerOverride";

  bool _isPremium = false;
  bool _developerPremiumOverride = false;

  bool get isPremium => _isPremium;
  bool get developerPremiumOverride => kDebugMode && _developerPremiumOverride;

  Future<void> refreshPremiumStatus() async {
    final prefs = await _prefsFuture;
    final developerOverride = kDebugMode
        ? (prefs.getBool(developerOverridePrefsKey) ?? false)
        : false;
    final storeEntitlementActive = await _loadStoreEntitlementStatus();
    final nextIsPremium = storeEntitlementActive || developerOverride;
    final changed = _isPremium != nextIsPremium ||
        _developerPremiumOverride != developerOverride;

    _isPremium = nextIsPremium;
    _developerPremiumOverride = developerOverride;

    _debugPremium(
      "active=$_isPremium source=${_premiumSourceLabel(
        storeEntitlementActive: storeEntitlementActive,
        developerOverride: developerOverride,
      )}",
    );

    if (changed) notifyListeners();
  }

  Future<void> setDeveloperPremiumOverride(bool value) async {
    if (!kDebugMode) {
      _debugPremium("developer override ignored outside debug builds");
      return;
    }

    final prefs = await _prefsFuture;
    await prefs.setBool(developerOverridePrefsKey, value);
    await refreshPremiumStatus();
  }

  Future<bool> _loadStoreEntitlementStatus() async {
    return false;
  }

  String _premiumSourceLabel({
    required bool storeEntitlementActive,
    required bool developerOverride,
  }) {
    if (storeEntitlementActive) return "store_entitlement";
    if (developerOverride) return "developer_override";
    return "none";
  }

  void _debugPremium(String message) {
    if (!kDebugMode) return;
    debugPrint("[premium] $message");
  }
}
