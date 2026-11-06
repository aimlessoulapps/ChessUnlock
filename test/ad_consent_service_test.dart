import 'package:chessUnlock/services/ad_consent_service.dart';
import 'package:flutter/foundation.dart';
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
}
