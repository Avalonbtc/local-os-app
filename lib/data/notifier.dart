import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../api/models.dart';
import '../theme.dart';

/// Offline / recovery alerts in the phone's notification shade. Shown by the app itself while it
/// runs (foreground or recently backgrounded); notifications with the app closed need push from
/// the controller (APNs / FCM), which it does not have yet.
class SystemNotifier {
  SystemNotifier._();
  static final instance = SystemNotifier._();

  final _plugin = FlutterLocalNotificationsPlugin();

  /// Machine id from a tapped notification, consumed by the shell to open that machine.
  final tapped = ValueNotifier<String?>(null);
  bool _ready = false;

  static bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> init() async {
    if (!supported || _ready) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_rigdeck'),
          // Asked for explicitly (see requestPermission), not at launch.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (r) => tapped.value = r.payload,
      );
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) tapped.value = launch!.notificationResponse?.payload;
      _ready = true;
    } catch (e) {
      debugPrint('notifications unavailable: $e');
    }
  }

  /// Android 13+ and iOS ask the user once; later calls return the stored answer.
  Future<bool> requestPermission() async {
    if (!_ready) return false;
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
  }

  Future<void> show(StatusAlert a) async {
    if (!_ready) return;
    await _plugin.show(
      id: a.id,
      title: '${a.title} · ${a.machineName}',
      body: a.message,
      payload: a.machineId,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          // Offline and recovery go to separate channels so users can mute recoveries only.
          a.offline ? 'rig_offline' : 'rig_recovered',
          a.offline ? '矿机离线' : '矿机恢复',
          channelDescription: a.offline ? '矿机或矿池离线时提醒' : '离线的矿机恢复时提醒',
          importance: a.offline ? Importance.high : Importance.defaultImportance,
          priority: a.offline ? Priority.high : Priority.defaultPriority,
          color: a.offline ? C.bad : C.ok,
          category: AndroidNotificationCategory.status,
          styleInformation: BigTextStyleInformation(a.message),
          when: a.at.millisecondsSinceEpoch,
        ),
        iOS: DarwinNotificationDetails(
          threadIdentifier: a.machineId,
          interruptionLevel: a.offline ? InterruptionLevel.timeSensitive : InterruptionLevel.active,
        ),
      ),
    );
  }
}
