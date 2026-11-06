import 'dart:convert';

import 'package:chess/chess.dart' as chess;
import 'package:chessUnlock/services/puzzle_queue_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('corrupt FEN and illegal solution moves are discarded from saved queues',
      () async {
    Map<String, Object> puzzle(String id, String fen, List<String> moves) => {
          'id': id,
          'fen': fen,
          'solutionUci': moves,
        };
    SharedPreferences.setMockInitialValues({
      'queue.normal': jsonEncode([
        puzzle('bad-fen', 'invalid', ['e2e4']),
        puzzle('illegal-first', startingFen, ['e2e5']),
        puzzle('illegal-reply', startingFen, ['e2e4', 'e7e4']),
        puzzle('valid', startingFen, ['e2e4', 'e7e5', 'g1f3']),
      ]),
    });
    final service = PuzzleQueueService(SharedPreferences.getInstance(),
        difficultyOptions: ['normal'], queueRefillWhenBelow: 0);
    await service.loadFromPrefs();
    expect((await service.nextPuzzle('normal'))?.id, 'valid');
  });

  test('network puzzle selects the position where the solution is legal',
      () async {
    SharedPreferences.setMockInitialValues({});
    final service = PuzzleQueueService(SharedPreferences.getInstance(),
        difficultyOptions: ['normal'], queueRefillWhenBelow: 0);
    final result = await http.runWithClient(
        () => service.nextPuzzle('normal'),
        () => MockClient((_) async => http.Response(
            jsonEncode({
              'puzzle': {
                'id': 'ply',
                'initialPly': 1,
                'solution': ['e7e5']
              },
              'game': {'pgn': 'e4 e5'},
            }),
            200)));
    final expected = chess.Chess()..move('e4');
    expect(result?.fen, expected.fen);
    expect(result?.solutionUci, ['e7e5']);
  });

  test('non-retryable network failure returns null for retry UI', () async {
    SharedPreferences.setMockInitialValues({});
    final service = PuzzleQueueService(SharedPreferences.getInstance(),
        difficultyOptions: ['normal']);
    var requests = 0;
    final result = await http.runWithClient(
        () => service.nextPuzzle('normal'),
        () => MockClient((_) async {
              requests++;
              return http.Response('unavailable', 403);
            }));
    expect(result, isNull);
    expect(requests, 1);
  });
}
