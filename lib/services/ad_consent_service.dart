import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// A single launch-time UMP update gates every ad placement. Never store our
/// own consent bool: UMP owns consent persistence and offline eligibility.
class AdConsentService extends ChangeNotifier {
  static const _trackingChannel = MethodChannel('chessunlock/ad_tracking');

  AdConsentService({
    ConsentInformation? information,
    Future<void> Function()? showRequiredForm,
    Future<void> Function()? showPrivacyForm,
    Future<void> Function()? initializeAds,
  })  : _information = information ?? ConsentInformation.instance,
        _showRequiredForm = showRequiredForm ??
            (() => ConsentForm.loadAndShowConsentFormIfRequired((_) {})),
        _showPrivacyForm = showPrivacyForm ??
            (() async {
              FormError? failure;
              await ConsentForm.showPrivacyOptionsForm(
                  (error) => failure = error);
              if (failure != null) throw StateError(failure!.message);
            }),
        _initializeAds = initializeAds ??
            (() async {
              await MobileAds.instance.initialize();
            });

  static AdConsentService instance = AdConsentService();
  final ConsentInformation _information;
  final Future<void> Function() _showRequiredForm;
  final Future<void> Function() _showPrivacyForm;
  final Future<void> Function() _initializeAds;
  Future<void>? _initialization;
  bool _canRequestAds = false;
  bool _privacyOptionsRequired = false;
  bool _adsInitialized = false;
  bool _showingPrivacy = false;

  bool get canRequestAds => _canRequestAds;
  bool get privacyOptionsRequired => _privacyOptionsRequired;

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }
    try {
      final updated = Completer<bool>();
      _information.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () {
          if (!updated.isCompleted) updated.complete(true);
        },
        (_) {
          if (!updated.isCompleted) updated.complete(false);
        },
      );
      if (await updated.future) {
        if (_isIOS) {
          await _trackingChannel.invokeMethod<void>('waitUntilActive');
        }
        await _showRequiredForm();
      }
    } catch (_) {
      // An update/form failure must not block app startup. UMP may still
      // authorize ads from a previous session; ask it rather than guessing.
    }
    await _refreshEligibility();
  }

  Future<void> _refreshEligibility() async {
    var allowed = false;
    try {
      _privacyOptionsRequired =
          await _information.getPrivacyOptionsRequirementStatus() ==
              PrivacyOptionsRequirementStatus.required;
      allowed = await _information.canRequestAds();
      if (allowed && _isIOS) {
        // UMP may already have shown ATT. Native code requests only if still
        // undetermined, after the app is active and the UMP form has dismissed.
        // Denied/restricted are valid outcomes: Google omits IDFA and can still
        // serve eligible nontracking ads. ATT is NOT an ad-eligibility boolean.
        await _trackingChannel
            .invokeMethod<int>('requestTrackingAuthorization');
      }
      if (allowed && !_adsInitialized) {
        await _initializeAds();
        _adsInitialized = true;
      }
    } catch (_) {
      allowed = false;
    }
    _canRequestAds = allowed;
    notifyListeners();
  }

  Future<bool> showPrivacyOptions() async {
    if (_showingPrivacy || !_privacyOptionsRequired) return false;
    _showingPrivacy = true;
    _canRequestAds = false;
    notifyListeners();
    var succeeded = true;
    try {
      if (_isIOS) await _trackingChannel.invokeMethod<void>('waitUntilActive');
      await _showPrivacyForm();
    } catch (_) {
      succeeded = false;
    } finally {
      await _refreshEligibility();
      _showingPrivacy = false;
    }
    return succeeded;
  }

  bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
}
