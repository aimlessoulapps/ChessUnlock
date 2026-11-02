import 'package:chessUnlock/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
