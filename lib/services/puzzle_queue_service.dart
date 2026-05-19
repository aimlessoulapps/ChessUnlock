import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:chess/chess.dart' as ch;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../ui.dart' show ChessPuzzle, titleCase;

const String startingFen =
    "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";

class PuzzleQueueService {
  PuzzleQueueService(
    this._prefsFuture, {
    required List<String> difficultyOptions,
    this.queueTarget = 10,
    this.queueRefillWhenBelow = 3,
    this.seenCap = 80,
  })  : difficultyOptions = List.unmodifiable(difficultyOptions),
        _queueByDiff = {
          for (final d in difficultyOptions) d: <ChessPuzzle>[],
        },
        _seenIdsByDiff = {
          for (final d in difficultyOptions) d: LinkedHashSet<String>(),
        };

  final Future<SharedPreferences> _prefsFuture;
  final List<String> difficultyOptions;
  final int queueTarget;
  final int queueRefillWhenBelow;
  final int seenCap;

  final Map<String, List<ChessPuzzle>> _queueByDiff;
  final Map<String, LinkedHashSet<String>> _seenIdsByDiff;
  final Set<String> _refillingDiffs = <String>{};

  String _queueKey(String diff) => "queue.$diff";
  String _seenKey(String diff) => "seen.$diff";
  String _lastPuzzleKey(String diff) => "cache.lastPuzzleJson.$diff";

  Future<void> loadFromPrefs() async {
    final prefs = await _prefsFuture;

    for (final diff in difficultyOptions) {
      final rawQ = prefs.getString(_queueKey(diff));
      if (rawQ != null && rawQ.trim().isNotEmpty) {
        try {
          final arr = jsonDecode(rawQ);
          if (arr is List) {
            final list = <ChessPuzzle>[];
            for (final item in arr) {
              if (item is Map) {
                final p = _puzzleFromMap(
                  Map<String, dynamic>.from(item),
                );
                if (p != null) list.add(p);
              }
            }
            _queueByDiff[diff] = list;
          }
        } catch (_) {}
      }

      final seen = prefs.getStringList(_seenKey(diff)) ?? <String>[];
      final set = LinkedHashSet<String>();
      for (final s in seen) {
        if (s.trim().isNotEmpty) set.add(s.trim());
      }
      _seenIdsByDiff[diff] = set;
    }
  }

  Future<ChessPuzzle?> nextPuzzle(String diff) async {
    final q = _queueByDiff[diff] ??= <ChessPuzzle>[];
    if (q.isNotEmpty) {
      final next = q.removeAt(0);
      await _persistQueue(diff);
      await _cacheLastPuzzleForDiff(diff, next);
      _maybeKickRefill(diff);
      return next;
    }

    final cached = await _loadLastPuzzleForDiff(diff);
    if (cached != null) {
      _maybeKickRefill(diff);
      return cached;
    }

    final fetched = await _fetchOneWithRetry(diff);
    if (fetched != null) {
      await _cacheLastPuzzleForDiff(diff, fetched);
      _markSeen(diff, fetched.id);
      await _persistSeen(diff);
      _maybeKickRefill(diff);
      return fetched;
    }

    return null;
  }

  void _maybeKickRefill(String diff) {
    final q = _queueByDiff[diff] ??= <ChessPuzzle>[];
    if (q.length < queueRefillWhenBelow) {
      unawaited(refillIfNeeded(diff).catchError((_) {}));
    }
  }

  Future<void> refillIfNeeded(String diff) async {
    final q = _queueByDiff[diff] ??= <ChessPuzzle>[];
    if (q.length >= queueTarget) return;
    if (_refillingDiffs.contains(diff)) return;

    _refillingDiffs.add(diff);
    try {
      int attempts = 0;
      var changed = false;
      ChessPuzzle? lastAdded;
      while (q.length < queueTarget && attempts < 20) {
        attempts++;

        final p = await _fetchOneWithRetry(diff);
        if (p == null) break;

        final seen = _seenIdsByDiff[diff] ??= LinkedHashSet<String>();
        if (seen.contains(p.id)) {
          continue;
        }

        q.add(p);
        _markSeen(diff, p.id);
        changed = true;
        lastAdded = p;
      }

      if (changed) {
        await _persistQueue(diff);
        await _persistSeen(diff);
        await _cacheLastPuzzleForDiff(diff, lastAdded!);
      }
    } finally {
      _refillingDiffs.remove(diff);
    }
  }

  Map<String, dynamic> _puzzleToMap(ChessPuzzle p) => {
        "id": p.id,
        "rating": p.rating,
        "type": p.type,
        "fen": p.fen,
        "solutionUci": p.solutionUci,
      };

  ChessPuzzle? _puzzleFromMap(Map<String, dynamic> m) {
    try {
      final id = (m["id"] ?? "unknown").toString();
      final rating = (m["rating"] is int)
          ? (m["rating"] as int)
          : int.tryParse((m["rating"] ?? "0").toString()) ?? 0;
      final type = (m["type"] ?? "Tactics").toString();
      final fen = (m["fen"] ?? startingFen).toString();

      final solRaw = m["solutionUci"];
      final solution = (solRaw is List)
          ? solRaw.map((e) => e.toString()).toList()
          : <String>[];

      if (solution.isEmpty) return null;

      return ChessPuzzle(
        id: id,
        rating: rating,
        type: type,
        fen: fen,
        solutionUci: solution,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _persistQueue(String diff) async {
    final prefs = await _prefsFuture;
    final q = _queueByDiff[diff] ?? <ChessPuzzle>[];
    final arr = q.map(_puzzleToMap).toList();
    await prefs.setString(_queueKey(diff), jsonEncode(arr));
  }

  Future<void> _persistSeen(String diff) async {
    final prefs = await _prefsFuture;
    final set = _seenIdsByDiff[diff] ?? LinkedHashSet<String>();
    await prefs.setStringList(_seenKey(diff), set.toList());
  }

  Future<void> _cacheLastPuzzleForDiff(String diff, ChessPuzzle puzzle) async {
    final prefs = await _prefsFuture;
    await prefs.setString(
        _lastPuzzleKey(diff), jsonEncode(_puzzleToMap(puzzle)));
  }

  Future<ChessPuzzle?> _loadLastPuzzleForDiff(String diff) async {
    try {
      final prefs = await _prefsFuture;
      final raw = prefs.getString(_lastPuzzleKey(diff));
      if (raw == null || raw.trim().isEmpty) return null;
      final m = jsonDecode(raw);
      if (m is Map) {
        return _puzzleFromMap(
          Map<String, dynamic>.from(m),
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  void _markSeen(String diff, String id) {
    final set = _seenIdsByDiff[diff] ??= LinkedHashSet<String>();
    if (set.contains(id)) return;
    set.add(id);
    while (set.length > seenCap) {
      set.remove(set.first);
    }
  }

  bool _shouldRetryStatus(int code) =>
      code == 429 || code == 500 || code == 502 || code == 503 || code == 504;

  Duration _retryDelay(int attempt, int? statusCode) {
    if (statusCode == 429) return const Duration(seconds: 60);
    const steps = [1, 2, 4, 8];
    final s = steps[attempt.clamp(0, steps.length - 1)];
    final jitterMs = Random().nextInt(250);
    return Duration(seconds: s, milliseconds: jitterMs);
  }

  Future<ChessPuzzle?> _fetchOnePuzzleFromLichess(String diff) async {
    final uri = Uri.parse("https://lichess.org/api/puzzle/next")
        .replace(queryParameters: {"difficulty": diff});

    final res = await http.get(
      uri,
      headers: const {
        "Accept": "application/json",
        "User-Agent": "ChessUnlock/1.0",
      },
    ).timeout(const Duration(seconds: 15));

    if (res.statusCode != 200) {
      throw HttpException("HTTP ${res.statusCode}", uri: uri);
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final puzzle = data["puzzle"] as Map<String, dynamic>;
    final game = data["game"] as Map<String, dynamic>;

    final id = (puzzle["id"] ?? "unknown").toString();
    final rating = (puzzle["rating"] is int) ? puzzle["rating"] as int : 0;

    final themes = (puzzle["themes"] is List)
        ? (puzzle["themes"] as List).map((e) => e.toString()).toList()
        : <String>[];
    final type = themes.isNotEmpty ? themes.first : "Tactics";

    final solution =
        (puzzle["solution"] as List).map((e) => e.toString()).toList();
    final initialPly =
        (puzzle["initialPly"] is int) ? puzzle["initialPly"] as int : 0;

    final pgnMoves = (game["pgn"] ?? "").toString().trim();
    if (pgnMoves.isEmpty || solution.isEmpty) {
      throw Exception("Bad payload");
    }

    final fenPlusOne = _fenFromPgnAtPly(pgnMoves, initialPly + 1);
    final fenExact = _fenFromPgnAtPly(pgnMoves, initialPly);
    final startFen =
        _isUciLegalFromFen(fenPlusOne, solution.first) ? fenPlusOne : fenExact;

    return ChessPuzzle(
      id: id,
      rating: rating,
      type: titleCase(type),
      fen: startFen,
      solutionUci: solution,
    );
  }

  Future<ChessPuzzle?> _fetchOneWithRetry(String diff) async {
    for (int attempt = 0; attempt < 4; attempt++) {
      try {
        return await _fetchOnePuzzleFromLichess(diff);
      } on HttpException catch (e) {
        final msg = e.message;
        final m = RegExp(r"HTTP\s+(\d+)").firstMatch(msg);
        final code = m != null ? int.tryParse(m.group(1) ?? "") : null;

        if (code != null && _shouldRetryStatus(code) && attempt < 3) {
          await Future.delayed(_retryDelay(attempt, code));
          continue;
        }
        break;
      } on TimeoutException {
        if (attempt < 3) {
          await Future.delayed(_retryDelay(attempt, null));
          continue;
        }
        break;
      } on SocketException {
        if (attempt < 3) {
          await Future.delayed(_retryDelay(attempt, null));
          continue;
        }
        break;
      } catch (_) {
        if (attempt < 3) {
          await Future.delayed(_retryDelay(attempt, null));
          continue;
        }
        break;
      }
    }
    return null;
  }

  String _fenFromPgnAtPly(String sanList, int plyCount) {
    final tokens = _extractSanTokens(sanList);
    final game = ch.Chess();

    final limit = plyCount.clamp(0, tokens.length);
    for (int i = 0; i < limit; i++) {
      if (!_safeMoveSan(game, tokens[i])) {
        throw Exception("Bad SAN at ply ${i + 1}");
      }
    }
    return game.fen;
  }

  bool _safeMoveSan(ch.Chess game, String san) {
    try {
      final dynamic result = game.move(san);
      return result != null;
    } catch (_) {
      return false;
    }
  }

  List<String> _extractSanTokens(String text) {
    final raw = text
        .replaceAll(RegExp(r"\{[^}]*\}"), " ")
        .replaceAll(RegExp(r"\([^)]*\)"), " ")
        .replaceAll(RegExp(r"\$\d+"), " ")
        .replaceAll(RegExp(r"1-0|0-1|1/2-1/2|\*"), " ")
        .split(RegExp(r"\s+"))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final out = <String>[];
    for (final t in raw) {
      if (RegExp(r"^\d+\.{1,3}$").hasMatch(t)) continue;
      out.add(t);
    }
    return out;
  }

  bool _isUciLegalFromFen(String fen, String uci) {
    try {
      final game = ch.Chess.fromFEN(fen);
      return _applyUci(game, uci);
    } catch (_) {
      return false;
    }
  }

  bool _applyUci(ch.Chess game, String uci) {
    if (uci.length < 4) return false;
    final from = uci.substring(0, 2);
    final to = uci.substring(2, 4);
    final promo = (uci.length >= 5) ? uci[4].toLowerCase() : null;

    try {
      final dynamic result = game.move({
        'from': from,
        'to': to,
        if (promo != null) 'promotion': promo,
      });
      return result != null;
    } catch (_) {
      return false;
    }
  }
}
