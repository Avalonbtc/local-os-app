import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../api/client.dart';
import '../api/models.dart';

/// Polls the fleet every 10 s while the app is in the foreground. Decoding and the per-row
/// computation run on a background isolate; the UI only swaps in the finished snapshot.
class FleetStore extends ChangeNotifier {
  FleetStore(this.backend);
  final Backend backend;

  /// Widget tests run on a fake clock where isolate replies never arrive; they build inline.
  static bool offThread = true;

  FleetSnapshot snapshot = FleetSnapshot.empty;
  bool loaded = false;
  Object? error;

  /// Fleet hashrate of the main coin over this session (one sample per refresh, 30 min).
  final List<double> recent = [];

  /// Electricity price (yuan/kWh) for the daily cost estimate; read once, updated on save.
  double? price;

  Timer? _timer;
  bool _busy = false;

  void start() {
    if (_timer != null) return;
    refresh();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => refresh());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> refresh() async {
    if (_busy) return;
    _busy = true;
    try {
      final bodies = await Future.wait([
        backend.raw('GET', '/api/v1/machines'),
        backend.raw('GET', '/api/v1/telemetry', query: const {'summary': 'true'}),
        _optional(backend.raw('GET', '/api/v1/status')),
      ]);
      final snap = await _buildOffThread(bodies, backend.nowMs);
      if (price == null) {
        try {
          price = asNum(asMap(await backend.getJson('/api/v1/settings/farm'))['electricity_price']);
        } catch (_) {
          // The estimate just shows "—" until the next refresh.
        }
      }
      snapshot = snap;
      loaded = true;
      error = null;
      if (snap.rates.isNotEmpty) {
        recent.add(snap.rates.first.hs);
        if (recent.length > 180) recent.removeAt(0);
      }
    } catch (e) {
      error = e;
    } finally {
      _busy = false;
    }
    notifyListeners();
  }

  void setPrice(double value) {
    price = value;
    notifyListeners();
  }

  FleetRow? row(String id) {
    for (final r in snapshot.rows) {
      if (r.machine.id == id) return r;
    }
    return null;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}

/// Top level, so the closure sent to the isolate captures only the bodies (never the store).
Future<FleetSnapshot> _buildOffThread(List<String> bodies, int nowMs) => FleetStore.offThread
    ? Isolate.run(() => buildFleet(bodies[0], bodies[1], bodies[2], nowMs))
    : Future.value(buildFleet(bodies[0], bodies[1], bodies[2], nowMs));

/// A controller without offline detection (before `/status` existed) answers 404: treat it as
/// "no status" instead of failing the whole refresh.
Future<String> _optional(Future<String> request) async {
  try {
    return await request;
  } on ApiException catch (e) {
    if (e.status == 404) return '';
    rethrow;
  }
}

/// Offline / recovery alerts. New ones (after the newest seen when the app opened) are handed to
/// [onNew] so the shell can show them in-app; push notifications need controller support.
class AlertsStore extends ChangeNotifier {
  AlertsStore(this.backend);
  final Backend backend;

  List<StatusAlert> items = const [];
  bool supported = true;
  bool loaded = false;
  int unread = 0;
  int _seen = -1;
  void Function(List<StatusAlert>)? onNew;
  Timer? _timer;
  bool _busy = false;

  void start() {
    if (_timer != null) return;
    refresh();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => refresh());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void markRead() {
    if (unread == 0) return;
    unread = 0;
    notifyListeners();
  }

  Future<void> refresh() async {
    if (_busy || !supported) return;
    _busy = true;
    try {
      final list = await backend.getJson('/api/v1/alerts', query: const {'limit': '100'}) as List;
      final next = list.map((a) => StatusAlert.fromJson(asMap(a))).toList()..sort((a, b) => b.id.compareTo(a.id));
      final newest = next.isEmpty ? 0 : next.first.id;
      if (_seen >= 0) {
        final fresh = next.where((a) => a.id > _seen).toList();
        if (fresh.isNotEmpty) {
          unread += fresh.length;
          onNew?.call(fresh);
        }
      }
      if (newest > _seen) _seen = newest;
      items = next;
      loaded = true;
    } on ApiException catch (e) {
      if (e.status == 404) supported = false;
    } catch (_) {
      // Keep the last list; the fleet view already shows connection problems.
    } finally {
      _busy = false;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
