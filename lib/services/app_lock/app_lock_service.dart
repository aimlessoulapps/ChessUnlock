import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum AppLockPermissionIssue {
  none,
  unsupported,
  usageAccessRequired,
  overlayPermissionRequired,
  screenTimeAuthorizationRequired,
}

class AppLockPermissionStatus {
  const AppLockPermissionStatus(this.issue);

  final AppLockPermissionIssue issue;

  bool get isReady => issue == AppLockPermissionIssue.none;
}

class AppLockStateSnapshot {
  const AppLockStateSnapshot({
    required this.lockedAppIds,
    required this.lockEnabled,
    required this.indefiniteUnlock,
    required this.unlockUntilMs,
  });

  final Set<String> lockedAppIds;
  final bool lockEnabled;
  final bool indefiniteUnlock;
  final int unlockUntilMs;
}

class NativeAppSelectionResult {
  const NativeAppSelectionResult({
    required this.completed,
    required this.applicationCount,
    required this.categoryCount,
    required this.webDomainCount,
    required this.includeEntireCategory,
    this.errorMessage,
  });

  final bool completed;
  final int applicationCount;
  final int categoryCount;
  final int webDomainCount;
  final bool includeEntireCategory;
  final String? errorMessage;

  int get totalCount => applicationCount + categoryCount + webDomainCount;

  bool get hasSelection => totalCount > 0;

  List<String> get summaryLines {
    final lines = <String>[];
    if (applicationCount > 0) {
      lines.add(_selectedLabel(applicationCount, "app"));
    }
    if (categoryCount > 0) {
      lines.add(_selectedLabel(categoryCount, "category"));
    }
    if (webDomainCount > 0) {
      lines.add(_selectedLabel(webDomainCount, "web domain"));
    }
    return lines;
  }

  static String _selectedLabel(int count, String noun) {
    final plural = count == 1 ? noun : "${noun}s";
    return "$count $plural selected";
  }
}

abstract class AppLockService {
  const AppLockService();

  bool get isSupported;

  bool get usesNativeAppPicker => false;

  String get unsupportedMessage =>
      "App locking isn't available on this platform yet.";

  Future<bool> consumeOpenPuzzleRequest() async => false;

  Future<String?> getOwnAppId() async => null;

  Future<List<Map<String, dynamic>>> getLockableApps() async =>
      <Map<String, dynamic>>[];

  Future<List<Map<String, dynamic>>> getLockableAppIcons(
    Set<String> appIds,
  ) async =>
      <Map<String, dynamic>>[];

  Future<NativeAppSelectionResult?> openNativeAppPicker() async => null;

  Future<NativeAppSelectionResult?> getSelectionSummary() async => null;

  Future<bool> hasConfiguredLocks(Set<String> appIds) async {
    return (await sanitizeLockedAppIds(appIds)).isNotEmpty;
  }

  Future<Set<String>> sanitizeLockedAppIds(Set<String> appIds) async {
    final ownAppId = await getOwnAppId();
    return appIds
        .map((appId) => appId.trim())
        .where((appId) => appId.isNotEmpty && appId != ownAppId)
        .toSet();
  }

  Future<void> syncLockState(AppLockStateSnapshot snapshot) async {}

  Future<AppLockPermissionStatus> checkPermissions({
    required bool requiresOverlay,
  }) async =>
      const AppLockPermissionStatus(AppLockPermissionIssue.unsupported);

  Future<void> openUsageAccessSettings() async {}

  Future<void> openOverlaySettings() async {}

  Future<void> requestNotificationPermissionIfNeeded() async {}

  Future<void> startEnforcement() async {}

  Future<void> hideActiveBlocker() async {}

  Future<void> stopEnforcement() async {}

  Future<void> unlockFor(Duration? duration) async {}

  Future<void> relockNow() async {}
}

class AndroidAppLockService extends AppLockService {
  AndroidAppLockService({
    MethodChannel channel = const MethodChannel("chesslock/system"),
  }) : _channel = channel;

  final MethodChannel _channel;
  String? _ownAppId;

  @override
  bool get isSupported => true;

  @override
  Future<bool> consumeOpenPuzzleRequest() async {
    try {
      return await _channel.invokeMethod<bool>("consumeOpenPuzzleRequest") ??
          false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> getOwnAppId() async {
    final cached = _ownAppId;
    if (cached != null && cached.isNotEmpty) return cached;

    try {
      final appId =
          (await _channel.invokeMethod<String>("getOwnPackageName"))?.trim();
      if (appId == null || appId.isEmpty) return null;
      _ownAppId = appId;
      return appId;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getLockableApps() async {
    final ownAppId = await getOwnAppId();
    final raw = await _channel.invokeMethod<List<dynamic>>("getLaunchableApps");
    final list =
        (raw ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return list.where((m) {
      final appId = (m["packageName"] ?? "").toString();
      return appId.isNotEmpty && appId != ownAppId;
    }).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> getLockableAppIcons(
    Set<String> appIds,
  ) async {
    final sanitized = (await sanitizeLockedAppIds(appIds)).toList()..sort();
    if (sanitized.isEmpty) return <Map<String, dynamic>>[];

    final raw = await _channel.invokeMethod<List<dynamic>>(
      "getLaunchableAppIcons",
      {"packageNames": sanitized},
    );
    final list =
        (raw ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return list.where((m) {
      final appId = (m["packageName"] ?? "").toString();
      return appId.isNotEmpty && sanitized.contains(appId);
    }).toList();
  }

  @override
  Future<void> syncLockState(AppLockStateSnapshot snapshot) async {
    try {
      final lockedAppIds =
          (await sanitizeLockedAppIds(snapshot.lockedAppIds)).toList()..sort();
      await _channel.invokeMethod("syncWatcherState", {
        "lockedPackages": lockedAppIds,
        "lockEnabled": snapshot.lockEnabled,
        "indefiniteUnlock": snapshot.indefiniteUnlock,
        "unlockUntilMs": snapshot.unlockUntilMs,
      });
    } catch (_) {}
  }

  @override
  Future<AppLockPermissionStatus> checkPermissions({
    required bool requiresOverlay,
  }) async {
    final usageGranted = await _hasUsageAccess();
    if (!usageGranted) {
      return const AppLockPermissionStatus(
        AppLockPermissionIssue.usageAccessRequired,
      );
    }

    if (requiresOverlay) {
      final overlayGranted = await _hasOverlayPermission();
      if (!overlayGranted) {
        return const AppLockPermissionStatus(
          AppLockPermissionIssue.overlayPermissionRequired,
        );
      }
    }

    return const AppLockPermissionStatus(AppLockPermissionIssue.none);
  }

  Future<bool> _hasUsageAccess() async {
    try {
      final granted = await _channel.invokeMethod<bool>("hasUsageAccess");
      return granted == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _hasOverlayPermission() async {
    try {
      final ok = await _channel.invokeMethod<bool>("hasOverlayPermission");
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _hasNotificationPermission() async {
    try {
      final ok = await _channel.invokeMethod<bool>("hasNotificationPermission");
      return ok == true;
    } catch (_) {
      return true;
    }
  }

  @override
  Future<void> openUsageAccessSettings() async {
    try {
      await _channel.invokeMethod("openUsageAccessSettings");
    } catch (_) {}
  }

  @override
  Future<void> openOverlaySettings() async {
    try {
      await _channel.invokeMethod("openOverlaySettings");
    } catch (_) {}
  }

  @override
  Future<void> requestNotificationPermissionIfNeeded() async {
    try {
      final granted = await _hasNotificationPermission();
      if (!granted) {
        await _channel.invokeMethod("requestNotificationPermission");
      }
    } catch (_) {}
  }

  @override
  Future<void> startEnforcement() async {
    try {
      await _channel.invokeMethod("startWatcher");
    } catch (_) {}
  }

  @override
  Future<void> hideActiveBlocker() async {
    try {
      await _channel.invokeMethod("hideWatcherOverlay");
    } catch (_) {}
  }

  @override
  Future<void> stopEnforcement() async {
    try {
      await _channel.invokeMethod("stopWatcher");
    } catch (_) {}
  }
}

class IosScreenTimeAppLockService extends AppLockService {
  IosScreenTimeAppLockService({
    MethodChannel channel = const MethodChannel("chesslock/screen_time"),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  bool get isSupported => true;

  @override
  bool get usesNativeAppPicker => true;

  @override
  String get unsupportedMessage => "Screen Time setup isn't available.";

  @override
  Future<AppLockPermissionStatus> checkPermissions({
    required bool requiresOverlay,
  }) async {
    final available = await _isScreenTimeAvailable();
    if (!available) {
      return const AppLockPermissionStatus(AppLockPermissionIssue.unsupported);
    }

    final status = await _authorizationStatus();
    if (status == "approved") {
      return const AppLockPermissionStatus(AppLockPermissionIssue.none);
    }

    return const AppLockPermissionStatus(
      AppLockPermissionIssue.screenTimeAuthorizationRequired,
    );
  }

  @override
  Future<NativeAppSelectionResult?> openNativeAppPicker() async {
    final available = await _isScreenTimeAvailable();
    if (!available) {
      return _selectionFailure("Screen Time setup isn't available.");
    }

    final Map<String, dynamic> auth;
    try {
      auth = await _invokeMap("requestAuthorization");
    } on PlatformException catch (error) {
      return _selectionFailure(
        error.message ?? "Screen Time permission is required.",
      );
    }

    if ((auth["status"] ?? "").toString() != "approved") {
      return _selectionFailure("Screen Time permission is required.");
    }

    final Map<String, dynamic> raw;
    try {
      raw = await _invokeMap("presentFamilyActivityPicker");
    } on PlatformException catch (error) {
      return _selectionFailure(
        error.message ?? "Unable to open Screen Time app picker.",
      );
    }

    final result = _selectionResultFromMap(raw);
    _debugScreenTime(
      "picker result; completed=${result.completed} "
      "apps=${result.applicationCount} "
      "categories=${result.categoryCount} "
      "webDomains=${result.webDomainCount}",
    );
    return result;
  }

  @override
  Future<NativeAppSelectionResult?> getSelectionSummary() async {
    try {
      final raw = await _invokeMap("selectionMetadata");
      final summary = _selectionResultFromMap(raw);
      _debugScreenTime(
        "selection summary; apps=${summary.applicationCount} "
        "categories=${summary.categoryCount} "
        "webDomains=${summary.webDomainCount}",
      );
      return summary;
    } catch (error) {
      _debugScreenTime("selection summary failed; error=$error");
      return null;
    }
  }

  @override
  Future<bool> hasConfiguredLocks(Set<String> appIds) async {
    final summary = await getSelectionSummary();
    return summary?.hasSelection ?? false;
  }

  @override
  Future<void> syncLockState(AppLockStateSnapshot snapshot) async {
    try {
      await _invokeOperation("syncLockState", {
        "lockEnabled": snapshot.lockEnabled,
        "indefiniteUnlock": snapshot.indefiniteUnlock,
        "unlockUntilMs": snapshot.unlockUntilMs,
      });
    } on PlatformException catch (error) {
      if (error.code != "authorizationRequired") rethrow;
    }
  }

  @override
  Future<void> startEnforcement() async {
    await _invokeOperation("startEnforcement");
  }

  @override
  Future<void> hideActiveBlocker() async {
    await _invokeOperation("clearShields");
  }

  @override
  Future<void> stopEnforcement() async {
    await _invokeOperation("stopEnforcement");
  }

  @override
  Future<void> unlockFor(Duration? duration) async {
    final now = DateTime.now();
    await _invokeOperation("unlockFor", {
      "durationMs": duration?.inMilliseconds ?? 0,
      "indefinite": duration == null,
      "unlockUntilMs": duration == null
          ? 0
          : now.add(duration).millisecondsSinceEpoch,
    });
  }

  @override
  Future<void> relockNow() async {
    try {
      await _invokeOperation("relockNow");
    } on PlatformException catch (error) {
      if (error.code != "authorizationRequired") rethrow;
    }
  }

  Future<bool> _isScreenTimeAvailable() async {
    try {
      final raw = await _invokeMap("isAvailable");
      return raw["available"] == true;
    } catch (_) {
      return false;
    }
  }

  Future<String> _authorizationStatus() async {
    try {
      final raw = await _invokeMap("authorizationStatus");
      final status = (raw["status"] ?? "unknown").toString();
      _debugScreenTime("authorization status=$status");
      return status;
    } catch (_) {
      return "unknown";
    }
  }

  Future<Map<String, dynamic>> _invokeMap(String method) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(method);
    return Map<String, dynamic>.from(raw ?? const <String, dynamic>{});
  }

  Future<Map<String, dynamic>> _invokeOperation(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      method,
      arguments,
    );
    final payload = Map<String, dynamic>.from(raw ?? const <String, dynamic>{});
    _debugScreenTime(
      "operation $method result; success=${payload["success"]} "
      "shielded=${payload["shielded"]} "
      "apps=${payload["applicationCount"]} "
      "categories=${payload["categoryCount"]} "
      "webDomains=${payload["webDomainCount"]} "
      "code=${payload["code"]}",
    );
    if (payload["success"] == false) {
      throw PlatformException(
        code: payload["code"]?.toString() ?? method,
        message: payload["errorMessage"]?.toString() ??
            payload["message"]?.toString() ??
            "Screen Time operation failed.",
      );
    }
    return payload;
  }

  void _debugScreenTime(String message) {
    debugPrint("[screen-time][dart] $message");
  }

  NativeAppSelectionResult _selectionResultFromMap(Map<String, dynamic> raw) {
    return NativeAppSelectionResult(
      completed: raw["completed"] == true,
      applicationCount: (raw["applicationCount"] as num?)?.toInt() ?? 0,
      categoryCount: (raw["categoryCount"] as num?)?.toInt() ?? 0,
      webDomainCount: (raw["webDomainCount"] as num?)?.toInt() ?? 0,
      includeEntireCategory: raw["includeEntireCategory"] == true,
      errorMessage: raw["errorMessage"]?.toString(),
    );
  }

  NativeAppSelectionResult _selectionFailure(String message) {
    return NativeAppSelectionResult(
      completed: false,
      applicationCount: 0,
      categoryCount: 0,
      webDomainCount: 0,
      includeEntireCategory: false,
      errorMessage: message,
    );
  }
}

class UnsupportedAppLockService extends AppLockService {
  const UnsupportedAppLockService({
    this.message = "App locking isn't available on iOS yet.",
  });

  final String message;

  @override
  bool get isSupported => false;

  @override
  String get unsupportedMessage => message;
}

AppLockService createAppLockService() {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return AndroidAppLockService();
  }

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    return IosScreenTimeAppLockService();
  }

  return const UnsupportedAppLockService(
    message: "App locking is only available on Android right now.",
  );
}
