import 'package:chessUnlock/ui.dart';
import 'package:chessUnlock/services/ad_consent_service.dart';
import 'support/fake_ad_consent.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AdConsentService previousConsent;
  late FakeAdConsentService consent;
  setUp(() {
    previousConsent = AdConsentService.instance;
    consent = FakeAdConsentService();
    AdConsentService.instance = consent;
  });
  tearDown(() {
    AdConsentService.instance = previousConsent;
    consent.dispose();
  });

  testWidgets('native waits for consent and collapses until loaded',
      (tester) async {
    consent.allowed = false;
    final calls = <String>[];
    const channel = MethodChannel('plugins.flutter.io/google_mobile_ads');
    tester.binding.defaultBinaryMessenger.setMockMessageHandler(channel.name,
        (message) async {
      calls.add(const StandardMessageCodec().readValue(ReadBuffer(message!))
          as String);
      return const StandardMethodCodec().encodeSuccessEnvelope(null);
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMessageHandler(channel.name, null));
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: ScreenAdHeader(
      title: 'Puzzle',
      active: true,
      screenName: 'puzzle',
    ))));
    await tester.pump();
    final before = tester.getRect(find.byType(NativeAdSlot));
    expect(calls.where((call) => call == 'loadNativeAd'), isEmpty);
    consent.setAllowed(true);
    await tester.pump();
    expect(calls, contains('loadNativeAd'));
    expect(tester.getRect(find.byType(NativeAdSlot)), before);
    calls.clear();
    consent.setAllowed(false);
    await tester.pump(const Duration(minutes: 2));
    expect(calls.where((call) => call == 'loadNativeAd'), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final screen in ['puzzle']) {
    for (final size in [const Size(320, 568), const Size(430, 932)]) {
      testWidgets(
          '$screen collapses unloaded ads through Premium transitions at $size',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final calls = <String>[];
        const channel = MethodChannel('plugins.flutter.io/google_mobile_ads');
        tester.binding.defaultBinaryMessenger
            .setMockMessageHandler(channel.name, (message) async {
          calls.add(const StandardMessageCodec().readValue(ReadBuffer(message!))
              as String);
          return const StandardMethodCodec().encodeSuccessEnvelope(null);
        });
        addTearDown(() => tester.binding.defaultBinaryMessenger
            .setMockMessageHandler(channel.name, null));
        Offset? position;
        for (final premium in [true, false, true, false, true]) {
          calls.clear();
          await tester.pumpWidget(MaterialApp(
              home: Scaffold(
                  body: SafeArea(
            minimum: const EdgeInsets.only(top: 24),
            child: Column(children: [
              ScreenAdHeader(
                  title: screen,
                  active: true,
                  prewarmBanner: true,
                  adsDisabled: premium,
                  screenName: screen),
              const SizedBox(key: ValueKey('content'), height: 100, width: 100),
            ]),
          ))));
          await tester.pump();
          final current =
              tester.getTopLeft(find.byKey(const ValueKey('content')));
          position ??= current;
          expect(current, position);
          if (premium) {
            expect(find.byType(NativeAdSlot), findsNothing);
            expect(
                calls.where((call) => call.contains('loadNativeAd')), isEmpty);
            await tester.pump(const Duration(minutes: 6));
            expect(
                calls.where((call) => call.contains('loadNativeAd')), isEmpty);
          } else {
            expect(find.byType(NativeAdSlot), findsOneWidget);
            expect(calls, contains('loadNativeAd'));
          }
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
  for (final size in [const Size(320, 568), const Size(430, 932)]) {
    testWidgets('Settings header has no ad for free users at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(
              body: ScreenAdHeader(
                  title: 'Settings',
                  active: true,
                  adsDisabled: false,
                  screenName: 'settings'))));
      expect(find.text('Settings'), findsOneWidget);
      expect(find.byType(NativeAdSlot), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets("premium hides banner ad slots", (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ScreenAdHeader(
            title: "Puzzle",
            active: true,
            adsDisabled: true,
            screenName: "puzzle",
          ),
        ),
      ),
    );

    expect(find.text("Puzzle"), findsOneWidget);
    expect(find.byType(NativeAdSlot), findsNothing);
  });

  testWidgets("free mode keeps banner ad slots", (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ScreenAdHeader(
            title: "Puzzle",
            active: false,
            adsDisabled: false,
            screenName: "puzzle",
          ),
        ),
      ),
    );

    expect(find.text("Puzzle"), findsOneWidget);
    expect(find.byType(NativeAdSlot), findsOneWidget);
  });
}
