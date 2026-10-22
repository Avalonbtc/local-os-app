import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../theme.dart';
import '../util/format.dart';
import 'notifier.dart';
import 'session.dart';

/// Android only: a foreground service that keeps checking `/api/v1/alerts` while the app is in
/// the background or swiped away, so offline alerts reach the notification shade. Without it,
/// Android freezes the app about a minute after it leaves the screen.
///
/// The polling runs in the service's own isolate (its own Flutter engine), reading the saved
/// credentials from the keystore; it survives the app's activity being destroyed.
abstract final class BackgroundMonitor {
  static const _enabledKey = 'monitor.enabled';
  static const _demoKey = 'monitor.demo';
  static const _seenKey = 'monitor.seen';
  static const interval = Duration(seconds: 30);

  static bool get supported => !kIsWeb && Platform.isAndroid;

  /// The service is up and polls the controller itself (the app then leaves background
  /// notifications to it; in demo mode the app keeps posting them, see Shell).
  static bool running = false;

  static void init() {
    if (!supported) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'rigdeck_monitor',
        channelName: '后台监控',
        channelDescription: '保持后台检查矿机离线通知（常驻）',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
        showWhen: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false, playSound: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(interval.inMilliseconds),
        // Resume monitoring after a reboot or an app update without opening the app.
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        // Timers must fire with the screen off; one small request every 30 s.
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  static Future<bool> get enabled async =>
      supported && (await FlutterForegroundTask.getData<bool>(key: _enabledKey) ?? true);

  static Future<void> setEnabled(bool value, {required bool demo}) async {
    if (!supported) return;
    await FlutterForegroundTask.saveData(key: _enabledKey, value: value);
    value ? await start(demo: demo) : await stop();
  }

  static Future<void> start({required bool demo}) async {
    if (!supported || !await enabled) return;
    await FlutterForegroundTask.saveData(key: _demoKey, value: demo);
    if (await FlutterForegroundTask.isRunningService) {
      // A new sign-in (or demo) restarts the task so it picks up the current credentials.
      await FlutterForegroundTask.restartService();
    } else {
      final result = await FlutterForegroundTask.startService(
        serviceId: 7307,
        serviceTypes: [ForegroundServiceTypes.specialUse],
        notificationTitle: 'RigDeck 后台监控中',
        notificationText: '每 30 秒检查一次离线通知',
        notificationIcon: const NotificationIcon(metaDataName: 'com.rigdeck.monitor_icon', backgroundColor: C.accent),
        callback: monitorEntryPoint,
      );
      if (result is ServiceRequestFailure) {
        debugPrint('background monitor not started: ${result.error}');
        return;
      }
    }
    running = true;
  }

  /// Newest alert the service has handled; the app starts announcing after it, so an alert the
  /// service held back (app was opening) still shows as a banner.
  static Future<int?> lastSeen() async =>
      supported && await FlutterForegroundTask.isRunningService ? FlutterForegroundTask.getData<int>(key: _seenKey) : null;

  static Future<void> stop() async {
    if (!supported) return;
    running = false;
    await FlutterForegroundTask.removeData(key: _seenKey);
    if (await FlutterForegroundTask.isRunningService) await FlutterForegroundTask.stopService();
  }
}

@pragma('vm:entry-point')
void monitorEntryPoint() {
  FlutterForegroundTask.setTaskHandler(AlertMonitorTask());
}

/// Runs in the service isolate. Announces alerts newer than the newest one it has seen, at most
/// three per check; ids double as notification ids, so an alert the app already showed is not
/// shown twice.
class AlertMonitorTask extends TaskHandler {
  HttpBackend? _backend;
  bool _demo = false;
  bool _busy = false;
  bool _expired = false;
  int _seen = -1;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    WidgetsFlutterBinding.ensureInitialized();
    await SystemNotifier.instance.init();
    _demo = await FlutterForegroundTask.getData<bool>(key: BackgroundMonitor._demoKey) ?? false;
    _seen = await FlutterForegroundTask.getData<int>(key: BackgroundMonitor._seenKey) ?? -1;
    if (_demo) {
      await _status('演示模式：由 App 生成通知');
      return;
    }
    await _poll();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    if (!_demo) _poll();
  }

  Future<void> _poll() async {
    if (_busy) return;
    _busy = true;
    try {
      final backend = _backend ??= _expired ? null : await _connect();
      if (backend == null) {
        await _status(_expired ? '登录已失效：打开 App 重新登录' : '未登录：打开 App 登录主控');
        return;
      }
      final list = await backend.getJson('/api/v1/alerts', query: const {'limit': '50'}) as List;
      final alerts = list.map((a) => StatusAlert.fromJson(asMap(a))).toList()..sort((a, b) => b.id.compareTo(a.id));
      final newest = alerts.isEmpty ? 0 : alerts.first.id;
      if (_seen >= 0) {
        // While the app is on screen it shows alerts itself.
        if (!await FlutterForegroundTask.isAppOnForeground) {
          for (final a in alerts.where((a) => a.id > _seen).take(3)) {
            await SystemNotifier.instance.show(a);
          }
        }
      }
      if (newest > _seen) {
        _seen = newest;
        await FlutterForegroundTask.saveData(key: BackgroundMonitor._seenKey, value: newest);
      }
      final offline = alerts.where((a) => a.offline).length;
      await _status('上次检查 ${clock(DateTime.now())} · 最近 $offline 条离线通知');
    } on ApiException catch (e) {
      if (e.status == 404) {
        await _status('主控没有离线检测（需要 offline-alerts 版本）');
      } else if (e.status != 401) {
        await _status('连接主控失败 ${clock(DateTime.now())}：${e.message}');
      }
    } catch (e, stack) {
      debugPrint('rigdeck monitor: check failed: $e');
      debugPrint('$stack');
      await _status('检查失败 ${clock(DateTime.now())}');
    } finally {
      _busy = false;
    }
  }

  Future<HttpBackend?> _connect() async {
    final creds = await SessionController.readStored();
    if (creds == null) return null;
    return HttpBackend(creds, onUnauthorized: () {
      // The 12 h session ran out: stop using it until the app signs in again (restart).
      _expired = true;
      _backend?.close();
      _backend = null;
    });
  }

  Future<void> _status(String text) =>
      FlutterForegroundTask.updateService(notificationTitle: 'RigDeck 后台监控中', notificationText: text);

  @override
  void onNotificationPressed() => FlutterForegroundTask.launchApp();

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _backend?.close();
  }
}
