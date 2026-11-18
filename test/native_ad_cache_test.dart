import 'package:chessUnlock/services/ad_consent_service.dart';
import 'package:chessUnlock/services/ad_units.dart';
import 'package:chessUnlock/services/native_ad_cache.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/src/ad_instance_manager.dart';
import 'support/fake_ad_consent.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
        '$platform preloads once, retains ads, expires, and revokes safely',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      final previous = AdConsentService.instance;
      final consent = FakeAdConsentService()..allowed = false;
      AdConsentService.instance = consent;
      final codec = StandardMethodCodec(AdMessageCodec());
      const name = 'plugins.flutter.io/google_mobile_ads';
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMessageHandler(name,
          (data) async {
        calls.add(codec.decodeMethodCall(data));
        return codec.encodeSuccessEnvelope(null);
      });
      var now = DateTime(2026, 11, 18);
      final cache = NativeAdCache(
          enabled: true, brightness: Brightness.light, now: () => now);
      List<MethodCall> loads() =>
          calls.where((c) => c.method == 'loadNativeAd').toList();
      Future<void> loaded(MethodCall load) async {
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
            name,
            codec.encodeMethodCall(MethodCall('onAdEvent',
                {'adId': load.arguments['adId'], 'eventName': 'onAdLoaded'})),
            (_) {});
        await tester.pump();
      }

      expect(loads(), isEmpty);
      consent.setAllowed(true);
      await tester.pump();
      expect(loads(), hasLength(3));
      for (final load in loads()) {
        await loaded(load);
      }
      final ads = [for (final p in NativePlacement.values) cache.adFor(p)];
      expect(ads, everyElement(isNotNull));
      final owner = Object();
      expect(cache.claim(NativePlacement.home, owner), isTrue);
      expect(cache.claim(NativePlacement.home, Object()), isFalse);
      cache.release(NativePlacement.home, owner);
      expect(cache.claim(NativePlacement.home, Object()), isTrue);
      cache.didChangeAppLifecycleState(AppLifecycleState.paused);
      cache.didChangeAppLifecycleState(AppLifecycleState.resumed);
      cache.configure(enabled: true, brightness: Brightness.light);
      await tester.pump();
      expect(loads(), hasLength(3));
      expect([for (final p in NativePlacement.values) cache.adFor(p)], ads);
      cache.didChangeAppLifecycleState(AppLifecycleState.paused);
      now = now.add(const Duration(minutes: 56));
      cache.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(loads(), hasLength(6));
      expect(calls.where((c) => c.method == 'disposeAd'), hasLength(3));
      // Premium arrives while replacement loads are still pending.
      cache.configure(enabled: false, brightness: Brightness.light);
      for (final load in loads().skip(3)) {
        await loaded(load);
      }
      expect([for (final p in NativePlacement.values) cache.adFor(p)],
          everyElement(isNull));
      await tester.pump(const Duration(minutes: 2));
      expect(loads(), hasLength(6));
      cache.configure(enabled: true, brightness: Brightness.light);
      await tester.pump();
      expect(loads(), hasLength(9));
      consent.setAllowed(false);
      await tester.pump();
      cache.dispose();
      await tester.pump();
      AdConsentService.instance = previous;
      consent.dispose();
      tester.binding.defaultBinaryMessenger.setMockMessageHandler(name, null);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('$platform load failures retry only in foreground',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      final previous = AdConsentService.instance;
      final consent = FakeAdConsentService();
      AdConsentService.instance = consent;
      final codec = StandardMethodCodec(AdMessageCodec());
      const name = 'plugins.flutter.io/google_mobile_ads';
      var requests = 0;
      tester.binding.defaultBinaryMessenger.setMockMessageHandler(name,
          (data) async {
        final call = codec.decodeMethodCall(data);
        if (call.method == 'loadNativeAd') {
          requests++;
          return codec.encodeErrorEnvelope(code: 'loadFailed');
        }
        return codec.encodeSuccessEnvelope(null);
      });
      final cache = NativeAdCache(enabled: true, brightness: Brightness.light);
      await tester.pump();
      expect(requests, 3);
      await tester.pump(const Duration(seconds: 59));
      expect(requests, 3);
      await tester.pump(const Duration(seconds: 1));
      expect(requests, 6);
      cache.didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pump(const Duration(minutes: 2));
      expect(requests, 6);
      cache.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(requests, 9);
      cache.dispose();
      await tester.pump();
      AdConsentService.instance = previous;
      consent.dispose();
      tester.binding.defaultBinaryMessenger.setMockMessageHandler(name, null);
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
