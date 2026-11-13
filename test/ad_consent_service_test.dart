import 'dart:async';

import 'package:chessUnlock/services/ad_consent_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_ad_consent.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('one UMP update gates ads until form completion and SDK initialization',
      () async {
    final info = FakeConsentInformation();
    var initialized = 0;
    late AdConsentService service;
    service = AdConsentService(
        information: info,
        showRequiredForm: () async {
          expect(service.canRequestAds, isFalse);
          info.allowed = true;
        },
        initializeAds: () async {
          initialized++;
        });
    addTearDown(service.dispose);
    expect(service.canRequestAds, isFalse);
    await Future.wait([service.initialize(), service.initialize()]);
    expect(info.updates, 1);
    expect(initialized, 1);
    expect(service.canRequestAds, isTrue);
  });

  for (final allowed in [false, true]) {
    test('offline update uses UMP eligibility: allowed=$allowed', () async {
      final info = FakeConsentInformation()
        ..updateFails = true
        ..allowed = allowed;
      var forms = 0;
      final service = AdConsentService(
          information: info,
          showRequiredForm: () async {
            forms++;
          },
          initializeAds: () async {});
      addTearDown(service.dispose);
      await service.initialize();
      expect(forms, 0);
      expect(service.canRequestAds, allowed);
    });
  }

  test('privacy options suspend ads and honor changed consent', () async {
    final info = FakeConsentInformation()
      ..allowed = true
      ..requiredPrivacy = true;
    late AdConsentService service;
    service = AdConsentService(
        information: info,
        showRequiredForm: () async {},
        initializeAds: () async {},
        showPrivacyForm: () async {
          expect(service.canRequestAds, isFalse);
          info.allowed = false;
        });
    addTearDown(service.dispose);
    await service.initialize();
    expect(service.privacyOptionsRequired, isTrue);
    expect(await service.showPrivacyOptions(), isTrue);
    expect(service.canRequestAds, isFalse);
  });

  test('SDK initialization failure leaves all ad requests disabled', () async {
    final info = FakeConsentInformation()..allowed = true;
    final service = AdConsentService(
        information: info,
        showRequiredForm: () async {},
        initializeAds: () async => throw StateError('SDK unavailable'));
    addTearDown(service.dispose);
    await service.initialize();
    expect(service.canRequestAds, isFalse);
  });

  group('iOS ATT', () {
    const channel = MethodChannel('chessunlock/ad_tracking');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    for (final status
        in {'authorized': 3, 'denied': 2, 'restricted': 1}.entries) {
      test('${status.key} preserves UMP-eligible ads, only after ATT completes',
          () async {
        final events = <String>[];
        final decision = Completer<int>();
        final requested = Completer<void>();
        messenger.setMockMethodCallHandler(channel, (call) async {
          events.add(call.method);
          if (call.method == 'requestTrackingAuthorization') {
            requested.complete();
            return decision.future;
          }
          return null;
        });
        final info = FakeConsentInformation()..allowed = true;
        final service = AdConsentService(
          information: info,
          showRequiredForm: () async => events.add('UMP form dismissed'),
          initializeAds: () async => events.add('initialize ads'),
        );
        addTearDown(service.dispose);
        final initialization = service.initialize();
        await requested.future;
        expect(service.canRequestAds, isFalse);
        expect(events, [
          'waitUntilActive',
          'UMP form dismissed',
          'requestTrackingAuthorization',
        ]);
        decision.complete(status.value);
        await initialization;
        expect(events.last, 'initialize ads');
        expect(service.canRequestAds, isTrue);
        await service.initialize();
        expect(info.updates, 1);
      });
    }

    test('ATT never overrides a UMP refusal to request ads', () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return null;
      });
      final service = AdConsentService(
        information: FakeConsentInformation(),
        showRequiredForm: () async {},
        initializeAds: () async => fail('UMP blocks SDK initialization'),
      );
      addTearDown(service.dispose);
      await service.initialize();
      expect(calls, ['waitUntilActive']);
      expect(service.canRequestAds, isFalse);
    });

    test('offline cached UMP consent still waits for ATT, denial permits ads',
        () async {
      var attRequests = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'requestTrackingAuthorization') attRequests++;
        return 2;
      });
      final service = AdConsentService(
        information: FakeConsentInformation()
          ..allowed = true
          ..updateFails = true,
        showRequiredForm: () async => fail('No form on failed UMP update'),
        initializeAds: () async {},
      );
      addTearDown(service.dispose);
      await service.initialize();
      expect(attRequests, 1);
      expect(service.canRequestAds, isTrue);
    });

    test('native bridge failure does not start ads before ATT is resolved',
        () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'requestTrackingAuthorization') {
          throw PlatformException(code: 'unavailable');
        }
        return null;
      });
      final service = AdConsentService(
        information: FakeConsentInformation()..allowed = true,
        showRequiredForm: () async {},
        initializeAds: () async => fail('ATT has not completed'),
      );
      addTearDown(service.dispose);
      await service.initialize();
      expect(service.canRequestAds, isFalse);
    });

    test('privacy options remain available after ATT denial', () async {
      messenger.setMockMethodCallHandler(
          channel,
          (call) async =>
              call.method == 'requestTrackingAuthorization' ? 2 : null);
      final info = FakeConsentInformation()
        ..allowed = true
        ..requiredPrivacy = true;
      late AdConsentService service;
      service = AdConsentService(
        information: info,
        showRequiredForm: () async {},
        initializeAds: () async {},
        showPrivacyForm: () async {
          expect(service.canRequestAds, isFalse);
          info.allowed = false;
        },
      );
      addTearDown(service.dispose);
      await service.initialize();
      expect(service.canRequestAds, isTrue);
      expect(await service.showPrivacyOptions(), isTrue);
      expect(service.canRequestAds, isFalse);
    });
  });
}
