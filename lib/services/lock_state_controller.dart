import 'package:shared_preferences/shared_preferences.dart';

class LockStateController {
  LockStateController(this._prefsFuture);

  final Future<SharedPreferences> _prefsFuture;

  static const _kUnlockUntilMs = "unlockUntilMs";
  static const _kIndefUnlock = "indefUnlock";
  static const _kLockedPackages = "lockedPackages";
  static const _kLockEnabledPersist = "lockEnabled";

  DateTime? unlockedUntil;
  bool indefiniteUnlock = false;
  bool lockEnabled = true;
  Set<String> lockedPackages = {};

  bool get isUnlocked {
    if (indefiniteUnlock) return true;
    final until = unlockedUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  Duration get unlockRemaining {
    if (indefiniteUnlock) return const Duration(days: 3650);
    final until = unlockedUntil;
    if (until == null) return Duration.zero;
    final d = until.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  Future<void> load() async {
    final prefs = await _prefsFuture;

    final untilMs = prefs.getInt(_kUnlockUntilMs) ?? 0;
    indefiniteUnlock = prefs.getBool(_kIndefUnlock) ?? false;
    unlockedUntil =
        untilMs > 0 ? DateTime.fromMillisecondsSinceEpoch(untilMs) : null;
    lockEnabled = !isUnlocked;
    lockedPackages =
        (prefs.getStringList(_kLockedPackages) ?? <String>[]).toSet();

    await saveLockEnabled();
  }

  Future<void> saveUnlockState() async {
    final prefs = await _prefsFuture;
    await prefs.setBool(_kIndefUnlock, indefiniteUnlock);
    await prefs.setInt(
      _kUnlockUntilMs,
      unlockedUntil?.millisecondsSinceEpoch ?? 0,
    );
  }

  Future<void> saveLockEnabled() async {
    final prefs = await _prefsFuture;
    await prefs.setBool(_kLockEnabledPersist, lockEnabled);
  }

  Future<void> saveLockedPackages() async {
    final prefs = await _prefsFuture;
    await prefs.setStringList(
      _kLockedPackages,
      lockedPackages.toList()..sort(),
    );
  }
}
