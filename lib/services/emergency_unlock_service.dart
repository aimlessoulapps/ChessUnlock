import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EmergencyUnlockService extends ChangeNotifier {
  EmergencyUnlockService(
    this._prefsFuture, {
    required bool Function() isPremium,
    DateTime Function()? now,
    this.useAndroidQuota = false,
  })  : _isPremium = isPremium,
        _now = now ?? DateTime.now;

  final Future<SharedPreferences> _prefsFuture;

  final bool Function() _isPremium;
  final DateTime Function() _now;
  final bool useAndroidQuota;
  bool _recording = false;
  (String, int)? _pendingUse;
  static const _channel = MethodChannel('chesslock/system');
  int get dailyLimit => _isPremium() ? 3 : 1;
  static const int unlockMinutes = 1;
  static const dayKeyPrefsKey = "premium.emergencyUnlock.dayKey.v1";
  static const countPrefsKey = "premium.emergencyUnlock.count.v1";

  String _dayKey = '';
  int _usedToday = 0;

  String get dayKey => _dayKey;
  int get usedToday => _usedToday;
  int get remainingToday => (dailyLimit - _usedToday).clamp(0, dailyLimit);
  bool get hasUsesRemaining => remainingToday > 0;

  Future<void> refreshUsage() async {
    if (useAndroidQuota) {
      final usage = await _channel
          .invokeMapMethod<String, dynamic>('getEmergencyUnlockUsage');
      if (usage != null) {
        final nextDay = usage['dayKey'] as String;
        final nextCount = (usage['count'] as num).toInt().clamp(0, 3);
        final changed = _dayKey != nextDay || _usedToday != nextCount;
        _dayKey = nextDay;
        _usedToday = nextCount;
        if (changed) notifyListeners();
        return;
      }
    }
    final prefs = await _prefsFuture;
    // Android's overlay writes the same quota while Flutter is backgrounded.
    if (useAndroidQuota) await prefs.reload();
    final today = _todayKey();
    final storedDay = prefs.getString(dayKeyPrefsKey);
    final storedCount = prefs.getInt(countPrefsKey) ?? 0;

    final nextDay = storedDay == today ? storedDay! : today;
    final nextCount = storedDay == today ? storedCount.clamp(0, 3) : 0;
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

  Future<bool> recordUseIfAvailable({bool refundable = false}) async {
    if (_recording || _pendingUse != null) return false;
    _recording = true;
    try {
      if (useAndroidQuota) {
        final recorded =
            await _channel.invokeMethod<bool>('reserveEmergencyUnlockUse') ??
                false;
        await refreshUsage();
        return recorded;
      }
      await refreshUsage();
      if (!hasUsesRemaining) {
        _debugEmergency("use denied; daily limit reached used=$_usedToday");
        return false;
      }

      final prefs = await _prefsFuture;
      _usedToday += 1;
      await prefs.setString(dayKeyPrefsKey, _dayKey);
      await prefs.setInt(countPrefsKey, _usedToday);
      if (refundable) _pendingUse = (_dayKey, _usedToday);
      _debugEmergency("use recorded; day=$_dayKey used=$_usedToday");
      notifyListeners();
      return true;
    } finally {
      _recording = false;
    }
  }

  void completeUse() => _pendingUse = null;

  /// Refund only this instance's uncommitted iOS reservation after the caller
  /// has confirmed relocking. Never erase a concurrent use or a new day's quota.
  Future<void> refundFailedUse() async {
    final reservation = _pendingUse;
    _pendingUse = null;
    if (reservation == null || useAndroidQuota) return;
    final prefs = await _prefsFuture;
    if (_todayKey() == reservation.$1 &&
        prefs.getString(dayKeyPrefsKey) == reservation.$1 &&
        prefs.getInt(countPrefsKey) == reservation.$2) {
      await prefs.setInt(countPrefsKey, reservation.$2 - 1);
    }
    await refreshUsage();
  }

  String _todayKey() {
    final now = _now();
    final month = now.month.toString().padLeft(2, "0");
    final day = now.day.toString().padLeft(2, "0");
    return "${now.year}-$month-$day";
  }

  void _debugEmergency(String message) {
    if (!kDebugMode) return;
    debugPrint("[premium][emergency] $message");
  }
}
