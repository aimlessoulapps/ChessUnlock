import 'package:chessUnlock/services/revenuecat_client.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

CustomerInfo customer(
    {bool premium = false,
    bool willRenew = true,
    DateTime? expiry,
    DateTime? requestedAt,
    Store store = Store.playStore,
    VerificationResult verification = VerificationResult.verified}) {
  final now = DateTime.now().toUtc().toIso8601String();
  final entitlement = EntitlementInfo(
      'premium', premium, willRenew, now, now, 'fixture.monthly', true,
      store: store,
      verification: verification,
      expirationDate: (expiry ?? DateTime.now().add(const Duration(days: 30)))
          .toUtc()
          .toIso8601String());
  return CustomerInfo(
      EntitlementInfos(
          {'premium': entitlement}, {if (premium) 'premium': entitlement},
          verification: verification),
      const {},
      const [],
      const [],
      const [],
      now,
      'fixture-user',
      const {},
      (requestedAt ?? DateTime.now()).toUtc().toIso8601String());
}

const monthly = Package(
    'fixture-monthly',
    PackageType.monthly,
    StoreProduct(
        'fixture.monthly', 'Monthly', 'Premium', 4.99, 'LOCAL 4.99', 'USD',
        subscriptionPeriod: 'P1M'),
    PresentedOfferingContext('fixture', null, null));

class FakeRevenueCatClient implements RevenueCatClient {
  CustomerInfo info = customer();
  CustomerInfo? purchaseInfo;
  CustomerInfo? restoreInfo;
  Object? purchaseError;
  Object? refreshError;
  Object? offeringError;
  int configurations = 0;
  int refreshes = 0;
  int purchases = 0;
  int restores = 0;
  Package? purchasedPackage;
  bool available = true;
  final listeners = <void Function(CustomerInfo)>[];
  @override
  Future<void> configure() async {
    configurations++;
  }

  @override
  Future<CustomerInfo> customerInfo() async {
    refreshes++;
    if (refreshError != null) throw refreshError!;
    return info;
  }

  @override
  Future<Offerings> offerings() async {
    if (offeringError != null) throw offeringError!;
    const offering =
        Offering('fixture', 'Fixture', {}, [monthly], monthly: monthly);
    return Offerings(available ? {'fixture': offering} : {},
        current: available ? offering : null);
  }

  @override
  Future<CustomerInfo> purchase(Package package) async {
    purchases++;
    purchasedPackage = package;
    if (purchaseError != null) throw purchaseError!;
    return info = purchaseInfo ?? customer(premium: true);
  }

  @override
  Future<CustomerInfo> restore() async {
    restores++;
    if (purchaseError != null) throw purchaseError!;
    return info = restoreInfo ?? info;
  }

  void emit(CustomerInfo update) {
    info = update;
    for (final listener in List.of(listeners)) {
      listener(update);
    }
  }

  @override
  void addListener(void Function(CustomerInfo) listener) =>
      listeners.add(listener);
  @override
  void removeListener(void Function(CustomerInfo) listener) =>
      listeners.remove(listener);
}
