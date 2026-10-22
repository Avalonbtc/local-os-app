import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rigdeck_app/api/client.dart';
import 'package:rigdeck_app/api/models.dart';
import 'package:rigdeck_app/util/format.dart';

void main() {
  final now = DateTime.utc(2026, 10, 22, 6, 0, 0).millisecondsSinceEpoch;
  String iso(int msAgo) => DateTime.fromMillisecondsSinceEpoch(now - msAgo).toUtc().toIso8601String();
  Map<String, dynamic> machine(String id, String name, {bool bmc = false}) => {
        'id': id,
        'name': name,
        'host': '10.0.0.${id.hashCode % 200}',
        'group': 'A',
        'tags': ['cpu'],
        'is_controller': false,
        'bmc': bmc ? {'url': 'https://10.0.1.1', 'username': 'a', 'provider': 'redfish'} : null,
        'policy': {},
      };
  Map<String, dynamic> mining(String id, double rate, {bool alive = true, int ageMs = 4000}) => {
        'machine_id': id,
        'kind': 'mining',
        'observed_at': iso(ageMs),
        'error': null,
        'data': {
          'instances': [
            {
              'instance': 'xmr',
              'desired': 'running',
              'process_alive': alive,
              'stats_observed_at': (now - ageMs) / 1000,
              'configured_coin': 'xmr',
              'configured_algorithm': 'rx/0',
              'miner_name': 'XMRig',
              'stats': {'hashrate_hs': rate, 'accepted': 10, 'rejected': 1, 'connected': true, 'algorithm': 'rx/0', 'coin': 'XMR', 'uptime': 3600},
            },
          ],
        },
      };
  Map<String, dynamic> system(String id, {int ageMs = 4000, String? error}) => {
        'machine_id': id,
        'kind': 'system',
        'observed_at': iso(ageMs),
        'error': error,
        'data': error == null ? {'cpu_temperature': 70, 'cpu_power_w': 300, 'gpus': [{'power_w': 100}], 'load': [12.5]} : null,
      };

  test('fleet rows: freshness, controller status, issues, totals and natural order', () {
    final machines = jsonEncode([machine('a', 'rig-10'), machine('b', 'rig-2', bmc: true), machine('c', 'rig-3'), machine('d', 'rig-4')]);
    final telemetry = jsonEncode([
      system('a'), mining('a', 15000),
      system('b'), mining('b', 14000),
      system('c', ageMs: 120000), mining('c', 9000, ageMs: 120000),
      system('d'), mining('d', 0, alive: false),
    ]);
    final status = jsonEncode([
      {'machine_id': 'a', 'state': 'online', 'pool': 'online', 'pool_checks': []},
      {
        'machine_id': 'b',
        'state': 'pool_offline',
        'pool': 'offline',
        'pool_checks': [
          {'instance': 'xmr', 'result': 'missing', 'message': 'xmrig-proxy 上看不到 worker「rig2」', 'provider': 'xmrig-proxy'},
        ],
      },
      {'machine_id': 'c', 'state': 'local_offline', 'pool': 'online', 'pool_checks': [], 'last_seen_at': iso(120000)},
      {'machine_id': 'd', 'state': 'online', 'pool': 'unsupported', 'pool_checks': []},
    ]);
    final s = buildFleet(machines, telemetry, status, now);

    expect(s.rows.map((r) => r.machine.name), ['rig-2', 'rig-3', 'rig-4', 'rig-10']);
    final byName = {for (final r in s.rows) r.machine.name: r};
    expect(byName['rig-2']!.poolOffline, isTrue);
    expect(byName['rig-2']!.issues.single, contains('看不到 worker「rig2」'));
    expect(byName['rig-2']!.machine.hasBmc, isTrue);
    expect(byName['rig-3']!.fresh, isFalse);
    expect(byName['rig-3']!.state, RigState.localOffline);
    expect(byName['rig-3']!.hashrateHs, 0, reason: 'stale miner numbers are not summed');
    expect(byName['rig-4']!.issues, contains('xmr：矿工进程未运行'));
    expect(byName['rig-10']!.powerW, 400);
    expect(byName['rig-10']!.cpuTemp, 70);
    expect(s.online, 3);
    expect(s.offline, 1);
    expect(s.poolOffline, 1);
    expect(s.poolChecked, 3);
    expect(s.poolUnsupported, 1);
    expect(s.rates.single.coin, 'XMR');
    expect(s.rates.single.hs, 29000);
    expect(s.rates.single.rigs, 2);
    expect(s.powerW, 1200);
    expect(s.statusAvailable, isTrue);
  });

  test('without /status the fleet still works from telemetry freshness', () {
    final s = buildFleet(
      jsonEncode([machine('a', 'rig-1'), machine('b', 'rig-2')]),
      jsonEncode([system('a'), mining('a', 1000), system('b', error: 'SSH 连接超时')]),
      '',
      now,
    );
    expect(s.statusAvailable, isFalse);
    expect(s.rows.first.state, RigState.online);
    expect(s.rows.last.state, RigState.localOffline);
    expect(s.rows.last.issues.single, '采集失败：SSH 连接超时');
  });

  test('a thousand machines build quickly enough for a 10 s refresh', () {
    final ids = List.generate(1000, (i) => 'm$i');
    final machines = jsonEncode([for (final id in ids) machine(id, 'rig-$id')]);
    final telemetry = jsonEncode([for (final id in ids) ...[system(id), mining(id, 15000)]]);
    final watch = Stopwatch()..start();
    final s = buildFleet(machines, telemetry, '', now);
    watch.stop();
    expect(s.rows, hasLength(1000));
    expect(s.rates.single.rigs, 1000);
    // Runs on a background isolate in the app; this only guards against accidental O(n²).
    expect(watch.elapsedMilliseconds, lessThan(2000));
  });

  test('history is reduced to at most 240 points', () {
    final points = [for (var i = 0; i < 43200; i++) (i * 60000, i.toDouble())];
    final s = reduceSeries(points);
    expect(s.xs.length, lessThanOrEqualTo(240));
    expect(s.last, 43199);
    expect(s.min, lessThan(s.max));
    expect(reduceSeries([]).isEmpty, isTrue);
  });

  test('history parsing sums instance hashrates and CPU+GPU power', () {
    final mining = jsonEncode([
      {'observed_at': iso(60000), 'error': null, 'data': {'instances': [{'stats': {'hashrate_hs': 100}}, {'stats': {'hashrate_hs': 50}}]}},
      {'observed_at': iso(0), 'error': 'offline', 'data': null},
    ]);
    final sys = jsonEncode([
      {'observed_at': iso(60000), 'error': null, 'data': {'cpu_temperature': 60, 'cpu_power_w': 200, 'gpus': [{'power_w': 50}]}},
    ]);
    final (hash, temp, power) = buildHistory(mining, sys);
    expect(hash.ys, [150]);
    expect(temp.ys, [60]);
    expect(power.ys, [250]);
  });

  test('formatting', () {
    expect(hashrate(15412), '15.4 kH/s');
    expect(hashrate(152400), '152 kH/s');
    expect(hashrate(999), '999 H/s');
    expect(hashrate(null), '—');
    expect(watts(312.4), '312 W');
    expect(watts(3820), '3.82 kW');
    expect(uptime(3 * 86400 + 4 * 3600 + 5), '3d 4h');
    expect(uptime(41 * 60), '41m');
    final base = DateTime(2026, 10, 22, 14, 10);
    expect(ago(base.subtract(const Duration(seconds: 20)), base), '刚刚');
    expect(ago(base.subtract(const Duration(minutes: 3)), base), '3 分钟前');
    expect(ago(DateTime(2026, 10, 21, 22, 41), base), '昨天 22:41');
    expect(naturalCompare('rig-2', 'rig-10'), lessThan(0));
    expect(normalizeServer('192.168.1.10/'), 'https://192.168.1.10');
    expect(normalizeServer('http://h:8080'), 'http://h:8080');
    // Full-width input from a Chinese keyboard, as typed on a real phone.
    expect(normalizeServer('ＨＴＴＰ：／／127.0.0.1：8080'), 'http://127.0.0.1:8080');
    expect(normalizeServer('192。168。1。10：8080／'), 'https://192.168.1.10:8080');
    expect(() => normalizeServer('ftp://x'), throwsA(isA<ApiException>()));
    expect(() => normalizeServer('http://'), throwsA(isA<ApiException>()));
  });
}
