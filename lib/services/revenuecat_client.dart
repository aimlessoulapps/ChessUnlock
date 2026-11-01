import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// Store boundary kept injectable for purchase/entitlement tests.
abstract class RevenueCatClient {
  Future<void> configure();
  Future<CustomerInfo> customerInfo();
  Future<Offerings> offerings();
  Future<CustomerInfo> purchase(Package package);
  Future<CustomerInfo> restore();
  void addListener(void Function(CustomerInfo) listener);
  void removeListener(void Function(CustomerInfo) listener);
}

class StoreRevenueCatClient implements RevenueCatClient {
  static Future<void>? _configuration;
  static const appleKey = String.fromEnvironment('REVENUECAT_APPLE_PUBLIC_KEY',
      defaultValue: 'appl_jXUQjrrjjGZgiKalKqIfsLggTep');
  static const googleKey = String.fromEnvironment(
      'REVENUECAT_GOOGLE_PUBLIC_KEY',
      defaultValue: 'goog_YeCcpxzPneKwkVevqpQjEGurtPN');

  static bool isValidPublicKey(String key, TargetPlatform platform) {
    final prefix = switch (platform) {
      TargetPlatform.iOS => 'appl_',
      TargetPlatform.android => 'goog_',
      _ => null,
    };
    return prefix != null &&
        key.startsWith(prefix) &&
        RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(key) &&
        key.length > prefix.length;
  }

  @override
  Future<void> configure() => _configuration ??= _configure();

  Future<void> _configure() async {
    final key =
        defaultTargetPlatform == TargetPlatform.iOS ? appleKey : googleKey;
    // This check applies in release too. Test Store and secret keys are rejected.
    if (kIsWeb || !isValidPublicKey(key, defaultTargetPlatform)) {
      throw StateError(
          'A platform-specific RevenueCat public SDK key is required.');
    }
    try {
      if (!await Purchases.isConfigured) {
        final configuration = PurchasesConfiguration(key)
          ..entitlementVerificationMode =
              EntitlementVerificationMode.informational;
        // No new login: retain RevenueCat's persisted anonymous app user ID.
        await Purchases.configure(configuration);
      }
    } catch (_) {
      _configuration = null;
      rethrow;
    }
  }

  @override
  Future<CustomerInfo> customerInfo() => Purchases.getCustomerInfo();
  @override
  Future<Offerings> offerings() => Purchases.getOfferings();
  @override
  Future<CustomerInfo> purchase(Package package) async =>
      (await Purchases.purchase(PurchaseParams.package(package))).customerInfo;
  @override
  Future<CustomerInfo> restore() => Purchases.restorePurchases();
  @override
  void addListener(void Function(CustomerInfo) listener) =>
      Purchases.addCustomerInfoUpdateListener(listener);
  @override
  void removeListener(void Function(CustomerInfo) listener) =>
      Purchases.removeCustomerInfoUpdateListener(listener);
}
