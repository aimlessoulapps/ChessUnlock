import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'revenuecat_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class PremiumAccessService extends ChangeNotifier {
  PremiumAccessService(this._prefsFuture, {RevenueCatClient? client})
      : _client = client ?? StoreRevenueCatClient();

  final Future<SharedPreferences> _prefsFuture;

  static const freeUnlockMinutes = 45;
  static const premiumUnlockMinutes = 180;
  static const defaultUnlockMinutes = 15;
  static const unlockDurationPrefsKey = "unlockDurationMinutes";
  static const unlockMinuteOptions = <int>[
    15,
    30,
    45,
    60,
    120,
    180,
  ];
  static const premiumPuzzleActionDelay = Duration(seconds: 30);

  final RevenueCatClient _client;
  static const entitlementIdentifier = 'premium';
  static const offeringIdentifier =
      String.fromEnvironment('REVENUECAT_OFFERING_ID');
  bool _isPremium = false;
  bool _configured = false;
  bool _disposed = false;
  bool busy = false;
  Future<void>? _initialization;
  Future<void>? _refresh;
  Timer? _expiryTimer;
  Timer? _refreshTimer;
  DateTime? _validUntil;
  Package? monthlyPackage;
  String? storeMessage;
  String? _managementURL;

  Future<bool> manageSubscription({
    Future<bool> Function(Uri)? openUrl,
  }) async {
    await refreshPremiumStatus();
    final fallback = switch (defaultTargetPlatform) {
      TargetPlatform.android =>
        Uri.parse('https://play.google.com/store/account/subscriptions'),
      TargetPlatform.iOS =>
        Uri.parse('https://apps.apple.com/account/subscriptions'),
      _ => null,
    };
    final management = Uri.tryParse(_managementURL ?? '');
    final urls = <Uri>{
      if (management != null &&
          management.scheme == 'https' &&
          management.host.isNotEmpty)
        management,
      if (fallback != null) fallback,
    };
    for (final url in urls) {
      try {
        final opened = await (openUrl != null
            ? openUrl(url)
            : launchUrl(url, mode: LaunchMode.externalApplication));
        if (opened) return true;
      } catch (_) {
        // Try the store fallback if the customer's link cannot be opened.
      }
    }
    return false;
  }

  bool get isPremium =>
      _isPremium &&
      (_validUntil == null || DateTime.now().isBefore(_validUntil!));
  int get premiumValidUntilMs =>
      isPremium ? _validUntil!.millisecondsSinceEpoch : 0;
  String? get monthlyPrice => monthlyPackage?.storeProduct.priceString;

  bool canUnlockForMinutes(int minutes) =>
      unlockMinuteOptions.contains(minutes) &&
      minutes <= (isPremium ? premiumUnlockMinutes : freeUnlockMinutes);

  int normalizeUnlockMinutes(int? minutes) {
    final limit = isPremium ? premiumUnlockMinutes : freeUnlockMinutes;
    final clamped =
        (minutes ?? defaultUnlockMinutes).clamp(defaultUnlockMinutes, limit);
    return unlockMinuteOptions.lastWhere((option) => option <= clamped);
  }

  Future<int> loadUnlockMinutes() async {
    final prefs = await _prefsFuture;
    final minutes =
        normalizeUnlockMinutes(prefs.getInt(unlockDurationPrefsKey));
    await prefs.setInt(unlockDurationPrefsKey, minutes);
    return minutes;
  }

  Future<void> saveUnlockMinutes(int minutes) async {
    final prefs = await _prefsFuture;
    if (!canUnlockForMinutes(minutes)) {
      throw ArgumentError.value(
          minutes, "minutes", "Unlock duration not allowed");
    }
    await prefs.setInt(unlockDurationPrefsKey, minutes);
  }

  static String formatUnlockMinutes(int minutes) {
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    if (hours == 0) return "$remainder min";
    return remainder == 0
        ? "$hours ${hours == 1 ? 'hr' : 'hrs'}"
        : "$hours hr $remainder min";
  }

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    final prefs = await _prefsFuture;
    await prefs.remove('premium.enabled');
    await prefs.remove('premium.developerOverride');
    try {
      await _client.configure();
      if (_disposed) return;
      _configured = true;
      _client.addListener(_applyCustomerInfo);
      _refreshTimer = Timer.periodic(const Duration(minutes: 5), (_) {
        unawaited(refreshPremiumStatus());
      });
    } catch (_) {
      storeMessage = 'Subscriptions are unavailable. Please try again.';
      _initialization = null;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> refreshPremiumStatus() =>
      _refresh ??= _refreshStatus().whenComplete(() => _refresh = null);

  Future<void> _refreshStatus() async {
    await initialize();
    if (!_configured || _disposed) return;
    try {
      // RevenueCat owns the persistent cache. Do not replace it with a saved bool
      // or invalidate it before fetching, so offline startup can use valid data.
      _applyCustomerInfo(await _client.customerInfo());
    } catch (_) {
      // Retain only previously verified, unexpired access on transport failures.
      if (!isPremium) _setPremium(false);
    }
  }

  void _applyCustomerInfo(CustomerInfo info) {
    if (_disposed) return;
    _managementURL = info.managementURL;
    final entitlement = info.entitlements.active[entitlementIdentifier];
    if (info.entitlements.verification == VerificationResult.failed ||
        entitlement?.verification == VerificationResult.failed) {
      // A failed signature never grants access, including through a listener.
      _setPremium(false);
      return;
    }
    if (entitlement == null ||
        !entitlement.isActive ||
        entitlement.store == Store.testStore) {
      _setPremium(false);
      return;
    }
    final requestDate = DateTime.tryParse(info.requestDate);
    final expiration = DateTime.tryParse(entitlement.expirationDate ?? '');
    // Bound fallback access to the SDK's offline grace window and the paid expiry.
    final cacheLimit =
        (requestDate ?? DateTime.now()).add(const Duration(days: 3));
    final previousValidUntil = _validUntil;
    _validUntil = expiration != null && expiration.isBefore(cacheLimit)
        ? expiration
        : cacheLimit;
    _expiryTimer?.cancel();
    if (!DateTime.now().isBefore(_validUntil!)) {
      _setPremium(false);
      return;
    }
    _expiryTimer = Timer(_validUntil!.difference(DateTime.now()), () {
      _setPremium(false);
      unawaited(refreshPremiumStatus());
    });
    // willRenew is deliberately ignored: cancellation retains paid access.
    _setPremium(true);
    if (previousValidUntil != _validUntil && !_disposed) notifyListeners();
  }

  void _setPremium(bool value) {
    final changed = _isPremium != value;
    _isPremium = value;
    if (!value) {
      _validUntil = null;
      _expiryTimer?.cancel();
    }
    if (changed && !_disposed) notifyListeners();
  }

  Future<void> loadOffering() async {
    await initialize();
    if (!_configured || _disposed) return;
    try {
      final offerings = await _client.offerings();
      final offering = offeringIdentifier.isEmpty
          ? offerings.current
          : offerings.all[offeringIdentifier];
      final package = offering?.monthly;
      monthlyPackage =
          package?.storeProduct.subscriptionPeriod == 'P1M' ? package : null;
      storeMessage = monthlyPackage == null
          ? 'Monthly subscription is unavailable. Please try again later.'
          : null;
    } catch (_) {
      monthlyPackage = null;
      storeMessage =
          'Could not load the subscription. Check your connection and retry.';
    }
    if (!_disposed) notifyListeners();
  }

  Future<String> subscribe() => _transact(restore: false);
  Future<String> restorePurchases() => _transact(restore: true);

  Future<String> _transact({required bool restore}) async {
    if (busy) return 'A purchase operation is already in progress.';
    busy = true;
    if (!_disposed) notifyListeners();
    try {
      await initialize();
      if (!_configured) return storeMessage ?? 'Subscriptions are unavailable.';
      if (!restore && monthlyPackage == null) await loadOffering();
      if (!restore && monthlyPackage == null) {
        return storeMessage ?? 'Monthly subscription is unavailable.';
      }
      final info = restore
          ? await _client.restore()
          : await _client.purchase(monthlyPackage!);
      _applyCustomerInfo(info);
      // Purchase/restore CustomerInfo is authoritative; the SDK also updates its cache.
      return isPremium
          ? (restore ? 'Premium purchases restored.' : 'Premium is now active.')
          : (restore
              ? 'No active Premium subscription was found.'
              : 'Purchase received. Premium will activate when the store confirms payment.');
    } on PlatformException catch (error) {
      final code = PurchasesErrorHelper.getErrorCode(error);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        return 'Purchase cancelled.';
      }
      if (code == PurchasesErrorCode.paymentPendingError) {
        return 'Payment is pending. Premium will activate after approval.';
      }
      return restore
          ? 'Could not restore purchases. Please try again.'
          : 'Purchase failed. Please try again.';
    } catch (_) {
      return 'The store is unavailable. Please try again.';
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _expiryTimer?.cancel();
    _refreshTimer?.cancel();
    if (_configured) _client.removeListener(_applyCustomerInfo);
    super.dispose();
  }
}
