import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EmergencyUnlockService extends ChangeNotifier {
  EmergencyUnlockService(this._prefsFuture);

  final Future<SharedPreferences> _prefsFuture;

  static const int dailyLimit = 3;
  static const int unlockMinutes = 1;
  static const dayKeyPrefsKey = "premium.emergencyUnlock.dayKey.v1";
  static const countPrefsKey = "premium.emergencyUnlock.count.v1";

  String _dayKey = _todayKey();
  int _usedToday = 0;

  String get dayKey => _dayKey;
  int get usedToday => _usedToday;
  int get remainingToday => (dailyLimit - _usedToday).clamp(0, dailyLimit);
  bool get hasUsesRemaining => remainingToday > 0;

  Future<void> refreshUsage() async {
    final prefs = await _prefsFuture;
    final today = _todayKey();
    final storedDay = prefs.getString(dayKeyPrefsKey);
    final storedCount = prefs.getInt(countPrefsKey) ?? 0;

    final nextDay = storedDay == today ? storedDay! : today;
    final nextCount = storedDay == today ? storedCount.clamp(0, dailyLimit) : 0;
    final changed = _dayKey != nextDay || _usedToday != nextCount;

    _dayKey = nextDay;
    _usedToday = nextCount;

    if (storedDay != today) {
      await prefs.setString(dayKeyPrefsKey, today);
      await prefs.setInt(countPrefsKey, 0);
      _debugEmergency("daily usage reset; day=$today");
    }

    if (changed) notifyListeners();
  }

  Future<bool> recordUseIfAvailable() async {
    await refreshUsage();
    if (!hasUsesRemaining) {
      _debugEmergency("use denied; daily limit reached used=$_usedToday");
      return false;
    }

    final prefs = await _prefsFuture;
    _usedToday += 1;
    await prefs.setString(dayKeyPrefsKey, _dayKey);
    await prefs.setInt(countPrefsKey, _usedToday);
    _debugEmergency("use recorded; day=$_dayKey used=$_usedToday");
    notifyListeners();
    return true;
  }

  static String _todayKey() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, "0");
    final day = now.day.toString().padLeft(2, "0");
    return "${now.year}-$month-$day";
  }

  void _debugEmergency(String message) {
    if (!kDebugMode) return;
    debugPrint("[premium][emergency] $message");
  }
}
