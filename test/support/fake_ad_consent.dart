import 'package:chessUnlock/services/ad_consent_service.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class FakeConsentInformation extends ConsentInformation {
  bool allowed = false;
  bool requiredPrivacy = false;
  bool updateFails = false;
  int updates = 0;

  @override
  void requestConsentInfoUpdate(
      ConsentRequestParameters params,
      OnConsentInfoUpdateSuccessListener success,
      OnConsentInfoUpdateFailureListener failure) {
    updates++;
    if (updateFails) {
      failure(FormError(errorCode: 1, message: 'offline'));
    } else {
      success();
    }
  }

  @override
  Future<bool> canRequestAds() async => allowed;
  @override
  Future<PrivacyOptionsRequirementStatus>
      getPrivacyOptionsRequirementStatus() async => requiredPrivacy
          ? PrivacyOptionsRequirementStatus.required
          : PrivacyOptionsRequirementStatus.notRequired;
  @override
  Future<ConsentStatus> getConsentStatus() async =>
      allowed ? ConsentStatus.obtained : ConsentStatus.required;
  @override
  Future<bool> isConsentFormAvailable() async => true;
  @override
  Future<void> reset() async {}
}

class FakeAdConsentService extends AdConsentService {
  bool allowed = true;
  bool privacyRequired = false;
  @override
  bool get canRequestAds => allowed;
  @override
  bool get privacyOptionsRequired => privacyRequired;
  void setAllowed(bool value) {
    allowed = value;
    notifyListeners();
  }
}
