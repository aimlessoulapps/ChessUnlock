import 'package:chessUnlock/services/analytics_service.dart';
import 'package:firebase_core/firebase_core.dart';
// Use Firebase's bundled test helper without adding a dependency.
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  testWidgets('onboarding analytics sends source labels without free text',
      (tester) async {
    const channel = BasicMessageChannel<Object?>(
      'dev.flutter.pigeon.firebase_analytics_platform_interface.FirebaseAnalyticsHostApi.logEvent',
      StandardMessageCodec(),
    );
    final events = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(
      channel,
      (message) async {
        events.add((message as List).single);
        return <Object?>[null];
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(channel, null));

    for (final entry in {
      'Social media': 'Social media',
      'Google/Ai': 'Google/Ai',
      'Other': 'Other',
      'Other: private@example.com': 'Other',
      'Other: first line\nprivate details': 'Other',
      'unprefixed private details': 'Other',
    }.entries) {
      AppAnalytics.onboardingAnswer(question: 'source', answer: entry.key);
      await tester.pump();
      expect(events.removeAt(0), {
        'eventName': 'onboarding_answer_source',
        'parameters': {
          'screen_name': 'OnboardingScreen',
          'answer': entry.value,
        },
      });
      expect(events, isEmpty);
    }
  });
}
