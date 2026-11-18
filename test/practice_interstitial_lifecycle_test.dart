import 'package:chessUnlock/services/practice_interstitial.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// Use the SDK's own wire codec to exercise real load/show callbacks.
import 'package:google_mobile_ads/src/ad_instance_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('$platform interstitial eligibility, dismissal and stale loads',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      SharedPreferences.setMockInitialValues({PracticeAdCounter.countKey: 5});
      final prefs = await SharedPreferences.getInstance();
      final codec = StandardMethodCodec(AdMessageCodec());
      final calls = <MethodCall>[];
      const name = 'plugins.flutter.io/google_mobile_ads';
      tester.binding.defaultBinaryMessenger.setMockMessageHandler(name,
          (data) async {
        calls.add(codec.decodeMethodCall(data));
        return codec.encodeSuccessEnvelope(null);
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMessageHandler(name, null));
      Future<void> event(int id, String event) async {
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
            name,
            codec.encodeMethodCall(
                MethodCall('onAdEvent', {'adId': id, 'eventName': event})),
            (_) {});
        await tester.pump();
      }

      var allowed = true;
      final service =
          PracticeInterstitial(Future.value(prefs), allowed: () => allowed);
      service.sync();
      service.sync();
      await tester.pump();
      expect(
          calls.where((c) => c.method == 'loadInterstitialAd'), hasLength(1));
      final id = calls
          .firstWhere((c) => c.method == 'loadInterstitialAd')
          .arguments['adId'] as int;
      await event(id, 'onAdLoaded');
      await service.atTransition(safe: () => false);
      expect(calls.where((c) => c.method == 'showAdWithoutView'), isEmpty);
      final transition = service.atTransition(safe: () => true);
      await tester.pump();
      expect(calls.where((c) => c.method == 'showAdWithoutView'), hasLength(1));
      await event(
          id,
          platform == TargetPlatform.iOS
              ? 'adWillPresentFullScreenContent'
              : 'onAdShowedFullScreenContent');
      expect(prefs.getInt(PracticeAdCounter.shownKey), isNotNull);
      await event(
          id,
          platform == TargetPlatform.iOS
              ? 'adDidDismissFullScreenContent'
              : 'onAdDismissedFullScreenContent');
      await transition;
      expect(prefs.getInt(PracticeAdCounter.countKey), 0);
      final nextId = calls
          .lastWhere((c) => c.method == 'loadInterstitialAd')
          .arguments['adId'] as int;
      allowed = false;
      service.sync();
      await event(nextId, 'onAdLoaded');
      await service.recordCompletion();
      await service.atTransition(safe: () => true);
      expect(prefs.getInt(PracticeAdCounter.countKey), 0);
      expect(calls.where((c) => c.method == 'showAdWithoutView'), hasLength(1));
      service.dispose();
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
