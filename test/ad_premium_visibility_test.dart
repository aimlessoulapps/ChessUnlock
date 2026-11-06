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

  testWidgets('free banner waits for consent without changing its slot',
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
      title: 'Home',
      active: true,
      screenName: 'home',
    ))));
    await tester.pump();
    final before = tester.getRect(find.byType(BannerAdSlot));
    expect(calls.where((call) => call == 'loadBannerAd'), isEmpty);
    consent.setAllowed(true);
    await tester.pump();
    expect(calls, contains('loadBannerAd'));
    expect(tester.getRect(find.byType(BannerAdSlot)), before);
    calls.clear();
    consent.setAllowed(false);
    await tester.pump(const Duration(minutes: 2));
    expect(calls.where((call) => call == 'loadBannerAd'), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final screen in ['home', 'puzzle', 'settings']) {
    for (final size in [const Size(320, 568), const Size(430, 932)]) {
      testWidgets(
          '$screen reserves identical space through Premium transitions at $size',
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
            expect(find.byType(BannerAdSlot), findsNothing);
            expect(
                calls.where((call) => call.contains('loadBannerAd')), isEmpty);
            await tester.pump(const Duration(minutes: 6));
            expect(
                calls.where((call) => call.contains('loadBannerAd')), isEmpty);
          } else {
            expect(find.byType(BannerAdSlot), findsOneWidget);
            expect(calls, contains('loadBannerAd'));
          }
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
  testWidgets("premium hides banner ad slots", (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ScreenAdHeader(
            title: "Settings",
            active: true,
            adsDisabled: true,
            screenName: "settings",
          ),
        ),
      ),
    );

    expect(find.text("Settings"), findsOneWidget);
    expect(find.byType(BannerAdSlot), findsNothing);
  });

  testWidgets("free mode keeps banner ad slots", (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ScreenAdHeader(
            title: "Settings",
            active: false,
            adsDisabled: false,
            screenName: "settings",
          ),
        ),
      ),
    );

    expect(find.text("Settings"), findsOneWidget);
    expect(find.byType(BannerAdSlot), findsOneWidget);
  });
}
