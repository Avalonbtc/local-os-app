import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:rigdeck_app/api/client.dart';

/// Test-only controller in memory: same paths and JSON shapes as RigDeck's REST API, so the
/// app's parsing and screens run unchanged in unit, widget and frame-timing tests. Large bodies
/// can be generated on a background isolate, like real network data arriving off the UI thread.
class FakeBackend extends Backend {
  FakeBackend({this.machines = 24, this.latency = const Duration(milliseconds: 120), this.background = true});

  final int machines;
  final Duration latency;

  /// Generate large bodies on a background isolate (off in widget tests, see FleetStore).
  final bool background;
  final _started = DateTime.now().millisecondsSinceEpoch;
  final _jobs = <Map<String, dynamic>>[];
  final _simulated = <Map<String, dynamic>>[];

  /// Raise a new alert, alternating rig-05 going offline and recovering.
  void simulateAlert() {
    final offline = _simulated.length.isEven;
    final rig = name(4);
    _simulated.add({
      'id': 100 + _simulated.length,
      'machine_id': id(4),
      'machine_name': rig,
      'kind': 'local',
      'event': offline ? 'offline' : 'recovered',
      'at': DateTime.now().toUtc().toIso8601String(),
      'message': offline ? '$rig 已离线：2 分钟没有收到遥测数据（主动上报和 SSH 读取都没有结果）' : '$rig 已恢复在线（离线约 1 分钟）',
    });
  }
  Map<String, dynamic> _settings = {
    'electricity_price': 0.56,
    'alerts': {
      'local_offline_minutes': 2,
      'pool_offline_minutes': 10,
      'pool_check': true,
      'popup': true,
      'proxies': [
        {'pool': 'mac.icuicu.de:6666', 'api_url': 'http://mac.icuicu.de:4048', 'has_token': true},
        {'pool': '149.104.4.41:8888', 'api_url': 'http://149.104.4.41:4048', 'has_token': true},
      ],
    },
  };

  @override
  int get serverOffsetMs => 0;

  static String id(int i) => '00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}';
  static String name(int i) => 'rig-${(i + 1).toString().padLeft(2, '0')}';

  @override
  Future<String> raw(String method, String path, {Map<String, String>? query, Object? body}) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    final q = query ?? const {};
    final now = DateTime.now().millisecondsSinceEpoch;
    final count = machines;
    final p = path.replaceFirst('/api/v1', '');
    final seg = p.split('/').where((s) => s.isNotEmpty).toList();

    if (method == 'GET') {
      switch (seg) {
        case ['me']:
          return jsonEncode({'actor': {'name': '测试'}, 'csrf': ''});
        case ['machines']:
          return background ? _bgMachines(count) : _machines(count);
        case ['telemetry']:
          final one = q['machine_id'];
          return background ? _bgTelemetry(count, now, one) : _telemetry(count, now, one);
        case ['status']:
          return background ? _bgStatus(count, now, _started) : _status(count, now, _started);
        case ['alerts']:
          return _alerts(now);
        case ['flight-sheets']:
          return _flights();
        case ['catalog', 'wallets']:
          return _wallets();
        case ['jobs']:
          return jsonEncode(_jobs.map((j) => _jobView(j, now)).toList().reversed.toList());
        case ['jobs', final jobId]:
          final job = _jobs.firstWhere((j) => j['id'] == jobId, orElse: () => const {});
          if (job.isEmpty) throw const ApiException(404, '记录不存在');
          return jsonEncode(_jobView(job, now));
        case ['settings', 'farm']:
          return jsonEncode(_settings);
        case ['tokens']:
          return jsonEncode([
            {'id': 't1', 'name': '本地 AI Agent', 'created_at': '2026-10-02T08:00:00Z', 'last_used_at': DateTime.now().toUtc().toIso8601String()},
            {'id': 't2', 'name': '监控脚本', 'created_at': '2026-09-25T08:00:00Z', 'last_used_at': null},
          ]);
        case ['audit']:
          return _audit(now);
        case ['machines', final m, 'messages']:
          return _messages(m, now);
        case ['machines', final m, 'history']:
          final kind = q['kind'] ?? 'system';
          final hours = int.tryParse(q['hours'] ?? '') ?? 24;
          final index = _index(m);
          return background ? _bgHistory(index, kind, hours, now) : _history(index, kind, hours, now);
        case ['machines', _, 'instances', final inst, 'log']:
          return jsonEncode({'instance': inst, 'text': _log(now), 'size': 4096});
        case ['machines', final m, 'bmc', 'power']:
          return jsonEncode({'state': _index(m) == 10 ? 'Off' : 'On', 'power_w': 380 + _index(m) * 3});
        case ['machines', _, 'bmc', 'sensors']:
          return jsonEncode({
            'items': [
              {'name': 'CPU Temp', 'unit': 'C', 'reading': 70, 'health': 'OK'},
              {'name': 'Inlet Temp', 'unit': 'C', 'reading': 31, 'health': 'OK'},
              {'name': 'VRM Temp', 'unit': 'C', 'reading': 84, 'health': 'Warning'},
              {'name': 'FAN1', 'unit': 'RPM', 'reading': 5600, 'health': 'OK'},
              {'name': 'PSU1 Input Power', 'unit': 'W', 'reading': 412, 'health': 'OK'},
            ],
          });
      }
    } else {
      switch (seg) {
        case ['logout']:
          return '';
        case ['jobs']:
          final input = (body as Map).cast<String, dynamic>();
          final jobId = 'job-${_jobs.length + 1}';
          _jobs.add({'id': jobId, 'input': input, 'created': now, 'cancelled': false});
          return jsonEncode({'job_id': jobId});
        case ['jobs', final jobId, 'cancel']:
          for (final j in _jobs) {
            if (j['id'] == jobId) j['cancelled'] = true;
          }
          return '';
        case ['settings', 'farm']:
          final next = (body as Map).cast<String, dynamic>();
          final alerts = Map<String, dynamic>.from(next['alerts'] as Map? ?? const {});
          alerts['proxies'] = [
            for (final p in (alerts['proxies'] as List? ?? const []))
              {...(p as Map).cast<String, dynamic>()..remove('token'), 'has_token': true},
          ];
          _settings = {...next, 'alerts': alerts};
          return jsonEncode(_settings);
      }
    }
    throw ApiException(404, '测试数据里没有 $method $path');
  }

  int _index(String machineId) => int.tryParse(machineId.split('-').last) ?? 0;

  Map<String, dynamic> _jobView(Map<String, dynamic> j, int now) {
    final input = (j['input'] as Map).cast<String, dynamic>();
    final elapsed = now - (j['created'] as int);
    final ids = (input['machine_ids'] as List).cast<String>();
    final cancelled = j['cancelled'] == true;
    final targets = <Map<String, dynamic>>[];
    for (var k = 0; k < ids.length; k++) {
      final step = elapsed - k * 700;
      final status = cancelled && step < 2500
          ? 'cancelled'
          : step < 0
              ? 'queued'
              : step < 2500
                  ? 'running'
                  : 'succeeded';
      targets.add({
        'id': '${j['id']}-$k',
        'machine_name': name(_index(ids[k])),
        'status': status,
        'output': status == 'succeeded' ? 'ok' : '',
        'error': null,
      });
    }
    final all = targets.map((t) => t['status']).toSet();
    final status = all.every((s) => s == 'succeeded')
        ? 'succeeded'
        : cancelled && !all.contains('running')
            ? 'cancelled'
            : all.contains('running') || all.contains('queued')
                ? 'running'
                : 'failed';
    return {
      'id': j['id'],
      'action': input['action'],
      'status': status,
      'created_at': DateTime.fromMillisecondsSinceEpoch(j['created'] as int).toUtc().toIso8601String(),
      'actor': '测试',
      'targets': targets,
    };
  }

  String _alerts(int now) {
    String at(int minutes) => DateTime.fromMillisecondsSinceEpoch(now - minutes * 60000).toUtc().toIso8601String();
    return jsonEncode([
      ..._simulated.reversed,
      {'id': 6, 'machine_id': id(11), 'machine_name': name(11), 'kind': 'local', 'event': 'offline', 'at': at(3), 'message': '${name(11)} 已离线：5 分钟没有收到遥测数据（主动上报和 SSH 读取都没有结果）'},
      {'id': 5, 'machine_id': id(6), 'machine_name': name(6), 'kind': 'pool', 'event': 'offline', 'at': at(12), 'message': '${name(6)} 矿池离线：本机在运行，但矿池已 10 分钟没有看到算力（xmr：xmrig-proxy 上看不到 worker「rig07」）'},
      {'id': 4, 'machine_id': id(3), 'machine_name': name(3), 'kind': 'local', 'event': 'recovered', 'at': at(170), 'message': '${name(3)} 已恢复在线（离线约 7 分钟）'},
      {'id': 3, 'machine_id': id(1), 'machine_name': name(1), 'kind': 'pool', 'event': 'recovered', 'at': at(60 * 16), 'message': '${name(1)} 矿池恢复：矿池已重新看到算力（离线约 14 分钟）'},
      {'id': 2, 'machine_id': id(1), 'machine_name': name(1), 'kind': 'pool', 'event': 'offline', 'at': at(60 * 16 + 14), 'message': '${name(1)} 矿池离线：本机在运行，但矿池已 10 分钟没有看到算力（xmr：supportxmr 上 worker「rig02」算力为 0）'},
      {'id': 1, 'machine_id': id(10), 'machine_name': name(10), 'kind': 'local', 'event': 'offline', 'at': at(60 * 29), 'message': '${name(10)} 已离线：2 分钟没有收到遥测数据'},
    ]);
  }

  String _flights() => jsonEncode([
        _sheet('s1', 'XMR · 自建代理 A', 5, 'stratum+tcp://mac.icuicu.de:6666'),
        _sheet('s2', 'XMR · 自建代理 B', 3, 'stratum+tcp://149.104.4.41:8888'),
        _sheet('s3', 'XMR · Kryptex 备用', 1, 'stratum+tcp://xmr.kryptex.network:7029'),
      ]);

  Map<String, dynamic> _sheet(String sid, String sheetName, int version, String url) => {
        'id': sid,
        'name': sheetName,
        'version': version,
        'tasks': [
          {
            'instance': 'xmr',
            'wallet_id': 'w1',
            'miner': {'adapter': 'xmrig', 'name': 'XMRig', 'version': '6.22.2'},
            'config': {'urls': [url], 'algorithm': 'rx/0', 'wallet_template': '%WAL%.%WORKER_NAME%'},
          },
        ],
      };

  String _wallets() => jsonEncode([
        {'id': 'w1', 'name': '主钱包', 'data': {'coin_symbol': 'XMR', 'address': '[你的 XMR 钱包地址]', 'note': '自建代理 A / B'}},
        {'id': 'w2', 'name': 'Kryptex 备用', 'data': {'coin_symbol': 'XMR', 'address': '[Kryptex 账户钱包]'}},
      ]);

  String _audit(int now) {
    String at(int minutes) => DateTime.fromMillisecondsSinceEpoch(now - minutes * 60000).toUtc().toIso8601String();
    return jsonEncode([
      {'id': 4, 'actor': '测试', 'action': 'job.create', 'target': '4 台矿机', 'detail': {}, 'created_at': at(6)},
      {'id': 3, 'actor': '测试', 'action': 'settings.farm', 'target': 'farm', 'detail': {}, 'created_at': at(37)},
      {'id': 2, 'actor': '测试', 'action': 'terminal.open', 'target': name(6), 'detail': {}, 'created_at': at(81)},
      {'id': 1, 'actor': '测试', 'action': 'login', 'target': 'app', 'detail': {}, 'created_at': at(300)},
    ]);
  }

  String _messages(String machineId, int now) {
    String at(int minutes) => DateTime.fromMillisecondsSinceEpoch(now - minutes * 60000).toUtc().toIso8601String();
    return jsonEncode([
      {'id': 'm5', 'at': at(11), 'level': 'warning', 'source': 'runtime', 'kind': 'pool_offline', 'instance': 'xmr', 'message': 'xmrig-proxy 上看不到 worker「rig07」，已持续 12 分钟'},
      {'id': 'm4', 'at': at(27), 'level': 'warning', 'source': 'runtime', 'kind': 'watchdog_restart', 'instance': 'xmr', 'message': '算力低于 1.0 kH/s 持续 2 分钟，看门狗已重启矿工'},
      {'id': 'm3', 'at': at(186), 'level': 'success', 'source': 'job', 'kind': 'apply', 'instance': null, 'message': '应用飞行表 XMR · 自建代理 B（v3）成功'},
      {'id': 'm2', 'at': at(190), 'level': 'info', 'source': 'audit', 'kind': 'policy', 'instance': null, 'message': '修改看门狗策略：最低算力 1.0 kH/s，最多重启 5 次 / 60 分钟'},
      {'id': 'm1', 'at': at(60 * 20), 'level': 'error', 'source': 'runtime', 'kind': 'exit', 'instance': 'xmr', 'message': '矿工进程意外退出（exit 137），看门狗已恢复'},
    ]);
  }

  static String _log(int now) {
    final t = DateTime.fromMillisecondsSinceEpoch(now);
    String c(int s) {
      final x = t.subtract(Duration(seconds: s));
      String d(int v) => v.toString().padLeft(2, '0');
      return '[${d(x.hour)}:${d(x.minute)}:${d(x.second)}]';
    }
    return [
      '${c(76)} accepted (2379/3) diff 120007 (41 ms)',
      '${c(60)} miner speed 10s/60s/15m 15412 15388 15401 H/s',
      '${c(45)} accepted (2380/3) diff 120007 (38 ms)',
      '${c(27)} net  149.104.4.41:8888 read error: "end of file"',
      '${c(27)} net  no active pools, stop mining',
      '${c(22)} net  use pool 149.104.4.41:8888  TLS off',
      '${c(22)} net  new job from 149.104.4.41:8888 diff 120007',
      '${c(6)} accepted (2381/3) diff 120007 (44 ms)',
      '${c(0)} miner speed 10s/60s/15m 15406 15391 15398 H/s',
    ].join('\n');
  }
}

// ---- Generators run on a background isolate (top level: nothing captured but their arguments).

Future<String> _bgMachines(int count) => Isolate.run(() => _machines(count));
Future<String> _bgTelemetry(int count, int now, String? only) => Isolate.run(() => _telemetry(count, now, only));
Future<String> _bgStatus(int count, int now, int started) => Isolate.run(() => _status(count, now, started));
Future<String> _bgHistory(int index, String kind, int hours, int now) =>
    Isolate.run(() => _history(index, kind, hours, now));

String _machines(int count) => jsonEncode([
      for (var i = 0; i < count; i++)
        {
          'id': FakeBackend.id(i),
          'name': FakeBackend.name(i),
          'host': '192.168.1.${21 + i % 220}',
          'port': 22,
          'username': 'root',
          'host_key': '',
          'group': i < count / 2 ? 'A 区' : 'B 区',
          'tags': ['cpu', 'epyc'],
          'is_controller': false,
          'bmc': i % 4 == 3 ? null : {'url': 'https://192.168.2.${21 + i % 220}', 'username': 'ADMIN', 'provider': 'redfish'},
          'policy': {'watchdog_enabled': true, 'min_hashrate_hs': 1000, 'max_restarts': 5},
          'created_at': '2026-09-01T00:00:00Z',
        },
    ]);

bool _off(int i) => i == 10 || i == 11;

String _telemetry(int count, int now, String? only) {
  final out = <Map<String, dynamic>>[];
  final at = DateTime.fromMillisecondsSinceEpoch(now - 4000).toUtc().toIso8601String();
  final sec = now / 1000;
  for (var i = 0; i < count; i++) {
    final mid = FakeBackend.id(i);
    if (only != null && only != mid) continue;
    final r = Random(i * 7919 + now ~/ 10000);
    if (_off(i)) {
      out.add({'machine_id': mid, 'kind': 'system', 'observed_at': DateTime.fromMillisecondsSinceEpoch(now - 300000 - i * 1000).toUtc().toIso8601String(), 'data': null, 'error': 'SSH 连接超时'});
      continue;
    }
    final broken = i == 2;
    final rate = 15200 + r.nextDouble() * 800;
    out.add({
      'machine_id': mid,
      'kind': 'system',
      'observed_at': at,
      'error': null,
      'data': {
        'cpu_pct': 97 + r.nextDouble() * 2,
        'cpu_temperature': broken ? 48 : 67 + r.nextDouble() * 8,
        'cpu_power_w': broken ? 120 : 290 + r.nextDouble() * 40,
        'logical_cpus': 128,
        'load': [126.4, 126.1, 125.9],
        'memory_total': 270140000000,
        'memory_used': 41000000000,
        'gpus': [],
        'addresses': [{'address': '192.168.1.${21 + i % 220}'}],
        'runtime_version': '0.4.0',
        'transport': i % 5 == 0 ? 'ssh' : 'push',
      },
    });
    out.add({
      'machine_id': mid,
      'kind': 'mining',
      'observed_at': at,
      'error': null,
      'data': {
        'instances': [
          {
            'instance': 'xmr',
            'desired': 'running',
            'phase': broken ? 'recovering' : 'running',
            'process_alive': !broken,
            'observed_at': sec - 4,
            'stats_observed_at': broken ? null : sec - 4,
            'configured_coin': 'XMR',
            'configured_algorithm': 'rx/0',
            'miner': 'xmrig',
            'miner_name': 'XMRig',
            'package_version': '6.22.2',
            'pool': i % 2 == 0 ? 'mac.icuicu.de:6666' : '149.104.4.41:8888',
            'sheet_id': i % 2 == 0 ? 's1' : 's2',
            'sheet_name': i % 2 == 0 ? 'XMR · 自建代理 A' : 'XMR · 自建代理 B',
            'sheet_version': i % 2 == 0 ? 5 : 3,
            'error': broken ? '矿工进程未运行，看门狗重启中' : null,
            'stats': broken
                ? null
                : {
                    'hashrate_hs': rate,
                    'accepted': 2000 + i * 31 + now ~/ 30000 % 500,
                    'rejected': 3,
                    'connected': true,
                    'algorithm': 'rx/0',
                    'coin': 'XMR',
                    'version': '6.22.2',
                    'uptime': 3600 * (20 + i * 3),
                  },
          },
        ],
      },
    });
  }
  return jsonEncode(out);
}

String _status(int count, int now, int started) {
  String iso(int ms) => DateTime.fromMillisecondsSinceEpoch(ms).toUtc().toIso8601String();
  return jsonEncode([
    for (var i = 0; i < count; i++)
      {
        'machine_id': FakeBackend.id(i),
        'state': _off(i) ? 'local_offline' : (i == 6 ? 'pool_offline' : 'online'),
        'local': _off(i) ? 'offline' : 'online',
        'last_seen_at': iso(_off(i) ? now - 300000 : now - 4000),
        'local_since': iso(started),
        'pool': i == 6 ? 'offline' : (i % 2 == 0 ? 'online' : 'online'),
        'pool_since': iso(started),
        'pool_bad_since': i == 6 ? iso(now - 720000) : null,
        'pool_checks': [
          {
            'instance': 'xmr',
            'pool_url': i % 2 == 0 ? 'mac.icuicu.de:6666' : '149.104.4.41:8888',
            'provider': 'xmrig-proxy',
            'worker': 'rig${(i + 1).toString().padLeft(2, '0')}',
            'result': i == 6 ? 'missing' : 'ok',
            'message': i == 6 ? 'xmrig-proxy 上看不到 worker「rig07」' : 'xmrig-proxy 已看到算力',
          },
        ],
        'checked_at': iso(now),
      },
  ]);
}

String _history(int index, String kind, int hours, int now) {
  final step = hours <= 24 ? 60000 : 600000;
  final n = hours * 3600000 ~/ step;
  final r = Random(index);
  final out = <Map<String, dynamic>>[];
  for (var k = 0; k < n; k++) {
    final t = now - (n - k) * step;
    final dip = (k > n * 0.62 && k < n * 0.66) ? 0.4 : 1.0;
    final at = DateTime.fromMillisecondsSinceEpoch(t).toUtc().toIso8601String();
    if (kind == 'mining') {
      out.add({
        'observed_at': at,
        'error': null,
        'data': {
          'instances': [
            {'stats': {'hashrate_hs': (15400 + sin(k / 9) * 300 + r.nextDouble() * 120) * dip}},
          ],
        },
      });
    } else {
      out.add({
        'observed_at': at,
        'error': null,
        'data': {
          'cpu_temperature': 62 + sin(k / 14) * 6 + r.nextDouble() * 2 - (dip < 1 ? 10 : 0),
          'cpu_power_w': (300 + sin(k / 11) * 18 + r.nextDouble() * 6) * (dip < 1 ? 0.6 : 1),
        },
      });
    }
  }
  return jsonEncode(out);
}
