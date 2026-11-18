import 'package:chessUnlock/services/ad_consent_service.dart';
import 'package:chessUnlock/services/ad_units.dart';
import 'package:chessUnlock/services/native_ad_cache.dart';
import 'package:chessUnlock/widgets/native_ad_slot.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:google_mobile_ads/src/ad_instance_manager.dart';
import 'support/fake_ad_consent.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('$platform tab changes reuse ads without duplicate attachments',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      final old = AdConsentService.instance;
      final consent = FakeAdConsentService();
      AdConsentService.instance = consent;
      final codec = StandardMethodCodec(AdMessageCodec());
      const channel = 'plugins.flutter.io/google_mobile_ads';
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMessageHandler(channel,
          (data) async {
        calls.add(codec.decodeMethodCall(data));
        return codec.encodeSuccessEnvelope(null);
      });
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform_views,
          (call) async => call.method == 'create'
              ? 1
              : call.method == 'resize'
                  ? {
                      'width': call.arguments['width'],
                      'height': call.arguments['height']
                    }
                  : null);
      Future<void> render(int tab,
          {bool enabled = true, bool dark = false}) async {
        await tester.pumpWidget(MaterialApp(
            theme: dark ? ThemeData.dark() : ThemeData.light(),
            home: Scaffold(
                body: NativeAdScope(
                    enabled: enabled,
                    child: IndexedStack(index: tab, children: [
                      for (final placement in NativePlacement.values)
                        Column(children: [
                          NativeAdSlot(
                              placement: placement,
                              active: tab == placement.index)
                        ]),
                    ])))));
        await tester.pump();
      }

      await render(0);
      final loads = calls.where((c) => c.method == 'loadNativeAd').toList();
      expect(loads, hasLength(3));
      for (final load in loads) {
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
            channel,
            codec.encodeMethodCall(MethodCall('onAdEvent',
                {'adId': load.arguments['adId'], 'eventName': 'onAdLoaded'})),
            (_) {});
      }
      await tester.pump();
      await tester.pump();
      final original = tester.widget<AdWidget>(find.byType(AdWidget)).ad;
      for (final tab in [1, 2, 0, 2, 1, 0]) {
        await render(tab);
        expect(find.byType(AdWidget), findsOneWidget);
        expect(calls.where((c) => c.method == 'loadNativeAd'), hasLength(3));
        expect(calls.where((c) => c.method == 'disposeAd'), isEmpty);
        expect(tester.takeException(), isNull);
      }
      expect(tester.widget<AdWidget>(find.byType(AdWidget)).ad, same(original));
      await render(0, dark: true);
      await tester.pumpAndSettle();
      expect(find.byType(AdWidget, skipOffstage: false), findsNothing);
      final refreshed =
          calls.where((c) => c.method == 'loadNativeAd').skip(3).toList();
      expect(refreshed, hasLength(3));
      expect(calls.where((c) => c.method == 'disposeAd'), hasLength(3));
      for (final load in refreshed) {
        expect(load.arguments['customOptions']['dark'], true);
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
            channel,
            codec.encodeMethodCall(MethodCall('onAdEvent',
                {'adId': load.arguments['adId'], 'eventName': 'onAdLoaded'})),
            (_) {});
      }
      await tester.pump();
      await tester.pump();
      expect(find.byType(AdWidget), findsOneWidget);
      await render(0, enabled: false, dark: true);

      expect(find.byType(AdWidget, skipOffstage: false), findsNothing);
      expect(calls.where((c) => c.method == 'disposeAd'), hasLength(6));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      AdConsentService.instance = old;
      consent.dispose();
      tester.binding.defaultBinaryMessenger
          .setMockMessageHandler(channel, null);
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform_views, null);
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
