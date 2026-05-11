import 'package:shared_preferences/shared_preferences.dart';

class StatsSnapshot {
  final int solved;
  final int bestRating;
  final int firstTry;

  const StatsSnapshot({
    required this.solved,
    required this.bestRating,
    required this.firstTry,
  });
}

class StatsRepository {
  StatsRepository(this._prefsFuture);

  final Future<SharedPreferences> _prefsFuture;

  static const _kStatSolved = "stats.solved";
  static const _kStatBestRating = "stats.bestRating";
  static const _kStatFirstTry = "stats.firstTrySolved";

  Future<StatsSnapshot> load() async {
    final prefs = await _prefsFuture;
    return StatsSnapshot(
      solved: prefs.getInt(_kStatSolved) ?? 0,
      bestRating: prefs.getInt(_kStatBestRating) ?? 0,
      firstTry: prefs.getInt(_kStatFirstTry) ?? 0,
    );
  }

  Future<void> save(StatsSnapshot stats) async {
    final prefs = await _prefsFuture;
    await prefs.setInt(_kStatSolved, stats.solved);
    await prefs.setInt(_kStatBestRating, stats.bestRating);
    await prefs.setInt(_kStatFirstTry, stats.firstTry);
  }
}
