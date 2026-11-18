import 'package:chessUnlock/services/native_ad_cache.dart';
import 'package:chessUnlock/services/ad_consent_service.dart';
import 'package:chessUnlock/services/ad_units.dart';
import 'package:chessUnlock/widgets/native_ad_slot.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/src/ad_instance_manager.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart' show AdWidget;
import 'support/fake_ad_consent.dart';
import 'package:chessUnlock/ui.dart'
    show
        HomeTab,
        SettingsTab,
        AppThemeMode,
        ScreenAdHeader,
        GlassCard,
        SettingsRow,
        PremiumNavBar,
        EmergencyUnlockButton;

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final dark in [false, true]) {
      for (final size in [
        const Size(320, 568),
        const Size(390, 844),
        const Size(430, 932)
      ]) {
        for (final placement in NativePlacement.values) {
          testWidgets('$platform $placement dark=$dark native at $size',
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
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
            addTearDown(() {
              AdConsentService.instance = old;
              consent.dispose();
              debugDefaultTargetPlatformOverride = null;
              tester.view.resetPadding();
              tester.view.resetPhysicalSize();
              tester.view.resetDevicePixelRatio();
              tester.binding.defaultBinaryMessenger
                  .setMockMessageHandler(channel, null);
              tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
                  SystemChannels.platform_views, null);
            });
            await tester.pumpWidget(MaterialApp(
                theme: dark ? ThemeData.dark() : ThemeData.light(),
                home: Scaffold(
                    bottomNavigationBar:
                        PremiumNavBar(index: 0, onChanged: (_) {}),
                    body: SafeArea(
                        child: placement == NativePlacement.home
                            ? HomeTab(
                                active: true,
                                prewarmBanner: false,
                                adsDisabled: false,
                                lockEnabled: true,
                                indefiniteUnlock: false,
                                unlockRemaining: Duration.zero,
                                lockedPackages: const {},
                                lockedSelectionCount: 0,
                                lockedSelectionSummaryLines: const [],
                                lockedSelectionPreviewRevision: 0,
                                difficulty: 'normal',
                                solved: false,
                                timedUnlockActive: false,
                                statSolved: 100,
                                statBestRating: 900,
                                accuracyPct: 80,
                                iconsByPkg: const {},
                                emergencyUnlockRemaining: 3,
                                emergencyUnlockActiveRemaining: Duration.zero,
                                emergencyUnlockBusy: false,
                                onEmergencyUnlock: () {},
                                onEditLockedApps: () {},
                                showNativeSelectionPreview: false,
                                onBreakTime: () {},
                                onSolveMorePuzzles: () {},
                                onOpenDifficulty: () {},
                              )
                            : placement == NativePlacement.settings
                                ? NativeAdScope(
                                    enabled: true,
                                    child: SettingsTab(
                                      active: true,
                                      prewarmBanner: false,
                                      adsDisabled: false,
                                      lockEnabled: true,
                                      indefiniteUnlock: false,
                                      unlockRemaining: Duration.zero,
                                      isPremium: false,
                                      difficulty: 'normal',
                                      themeMode: AppThemeMode.system,
                                      onThemeModeChanged: (_) async {},
                                      onLockToggle: (_) async {},
                                      onOpenDifficulty: () async {},
                                      onOpenPremium: () {},
                                      onPrivacyPolicy: () async {},
                                      onTermsOfUse: () async {},
                                      onFeedback: () async {},
                                    ))
                                : Column(children: [
                                    NativeAdSlot(
                                        placement: placement, active: true)
                                  ])))));
            await tester.pump();
            if (placement == NativePlacement.home) {
              expect(tester.getCenter(find.byType(EmergencyUnlockButton)).dx,
                  closeTo(size.width / 2, 0.1));
              expect(find.text('0 selected'), findsOneWidget);
              await tester.drag(find.byType(ListView), const Offset(0, -500));
              await tester.pumpAndSettle();
            }
            if (placement == NativePlacement.settings) {
              expect(
                  find.descendant(
                      of: find.byType(ScreenAdHeader),
                      matching: find.byType(NativeAdSlot)),
                  findsNothing);
            }
            if (placement != NativePlacement.settings) {
              expect(tester.getSize(find.byType(NativeAdSlot)).height, 0);
            }
            final buttonBefore = placement == NativePlacement.home
                ? tester.getRect(find.byType(FilledButton))
                : null;
            final load = calls
                .where((call) => call.method == 'loadNativeAd')
                .toList()[placement == NativePlacement.settings ? 2 : 0];
            expect(load.arguments['customOptions']['dark'], dark);
            expect(load.arguments['customOptions']['medium'],
                placement != NativePlacement.puzzle);
            await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
                channel,
                codec.encodeMethodCall(MethodCall('onAdEvent', {
                  'adId': load.arguments['adId'],
                  'eventName': 'onAdLoaded'
                })),
                (_) {});
            await tester.pump();
            await tester.pump();
            if (placement == NativePlacement.settings) {
              // On tall phones, show the next section without scrolling,
              // even with a loaded medium ad and system safe-area insets.
              if (size.height >= 932) {
                final appearance = tester.getRect(find.text('Appearance'));
                expect(
                    appearance.bottom,
                    lessThanOrEqualTo(
                        tester.getRect(find.byType(ListView)).bottom));
                expect(tester.getRect(find.byType(NativeAdSlot)).bottom,
                    lessThanOrEqualTo(appearance.top));
              }
              await tester.scrollUntilVisible(find.byType(NativeAdSlot), 150);
              await tester.pumpAndSettle();
            }
            expect(tester.getSize(find.byType(NativeAdSlot)).height,
                placement != NativePlacement.puzzle ? 256 : 54);
            if (buttonBefore != null) {
              await tester.ensureVisible(find.byType(NativeAdSlot));
              await tester.pumpAndSettle();
              expect(tester.getRect(find.byType(NativeAdSlot)).bottom,
                  lessThanOrEqualTo(buttonBefore.top));
              expect(tester.getRect(find.byType(FilledButton)), buttonBefore);
            }
            if (placement == NativePlacement.settings) {
              await tester.ensureVisible(find.byType(NativeAdSlot));
              await tester.pumpAndSettle();
              expect(find.byType(NativeAdSlot), findsOneWidget);
              final adRect = tester.getRect(find.byType(NativeAdSlot));
              final list = tester.widget<ListView>(find.byType(ListView));
              final children =
                  (list.childrenDelegate as SliverChildListDelegate).children;
              final difficultyIndex = children.indexWhere((child) =>
                  child is GlassCard &&
                  child.child is SettingsRow &&
                  (child.child as SettingsRow).title == 'Difficulty');
              final adIndex =
                  children.indexWhere((child) => child is NativeAdSlot);
              final appearanceIndex = children.indexWhere(
                  (child) => child is Text && child.data == 'Appearance');
              expect(difficultyIndex, greaterThanOrEqualTo(0));
              expect(adIndex, greaterThan(difficultyIndex));
              expect(adIndex, lessThan(appearanceIndex));
              expect(
                  adRect.bottom,
                  lessThanOrEqualTo(
                      tester.getTopLeft(find.text('Appearance')).dy));
              expect(
                  adRect.top,
                  greaterThanOrEqualTo(
                      tester.getRect(find.byType(ScreenAdHeader)).bottom));
              expect(
                  adRect.bottom,
                  lessThanOrEqualTo(
                      tester.getRect(find.byType(PremiumNavBar)).top));
            }
            expect(tester.takeException(), isNull);
            consent.setAllowed(false);
            await tester.pump();
            expect(find.byType(AdWidget), findsNothing);
            if (find.byType(NativeAdSlot).evaluate().isNotEmpty) {
              expect(tester.getSize(find.byType(NativeAdSlot)).height, 0);
            }
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
            debugDefaultTargetPlatformOverride = null;
          });
        }
      }
    }
  }
}
