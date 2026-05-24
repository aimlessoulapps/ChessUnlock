import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum AppLockPermissionIssue {
  none,
  unsupported,
  usageAccessRequired,
  overlayPermissionRequired,
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

abstract class AppLockService {
  const AppLockService();

  bool get isSupported;

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
    return const UnsupportedAppLockService();
  }

  return const UnsupportedAppLockService(
    message: "App locking is only available on Android right now.",
  );
}
