import 'package:chessUnlock/services/practice_interstitial.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('five successes, persisted cooldown, and missed opportunities',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final counter = PracticeAdCounter(prefs);
    final now = DateTime(2026, 11, 18);
    for (var i = 0; i < 4; i++) {
      await counter.completed();
    }
    expect(counter.due(now), isFalse);
    await counter.completed();
    expect(counter.due(now), isTrue);
    // An unavailable ad does not reset the count.
    await counter.completed();
    expect(counter.count, 5);
    await counter.displayed(now);
    expect(counter.count, 0);
    for (var i = 0; i < 5; i++) {
      await counter.completed();
    }
    final restored = PracticeAdCounter(prefs);
    expect(restored.due(now.add(const Duration(minutes: 9, seconds: 59))),
        isFalse);
    expect(restored.due(now.add(const Duration(minutes: 10))), isTrue);
    expect(restored.due(now.subtract(const Duration(hours: 1))), isFalse);
  });
}
