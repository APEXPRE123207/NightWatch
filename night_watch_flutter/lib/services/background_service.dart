import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Top-level callback for flutter_foreground_task background execution.
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(NightWatchTaskHandler());
}

class NightWatchTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Background task started
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Periodic heartbeat
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    // Clean up
  }
}

class BackgroundServiceManager {
  static Future<void> init() async {
    if (!Platform.isAndroid) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'night_watch_service',
        channelName: 'Night Watch Acoustic Monitoring',
        channelDescription: 'Maintains overnight sound monitoring while screen is locked.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  static Future<bool> startForegroundService() async {
    if (!Platform.isAndroid) return true;

    // Request notification permission if needed
    final notifPerm = await FlutterForegroundTask.checkNotificationPermission();
    if (notifPerm != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    if (await FlutterForegroundTask.isRunningService) {
      return true;
    }

    await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: '🌙 Night Watch Active',
      notificationText: 'Monitoring ambient acoustic environment...',
      callback: startCallback,
    );

    return true;
  }

  static Future<void> updateNotification({
    required String title,
    required String text,
  }) async {
    if (!Platform.isAndroid) return;
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: text,
      );
    }
  }

  static Future<bool> stopForegroundService() async {
    if (!Platform.isAndroid) return true;
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
      return true;
    }
    return true;
  }
}
