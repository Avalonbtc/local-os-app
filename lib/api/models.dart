import 'dart:convert';

/// Everything here is plain data built by pure functions, so it can be produced on a background
/// isolate (`Isolate.run`) and handed to the UI without work on the raster or UI thread.

double? asNum(dynamic v) => v is num && v.isFinite ? v.toDouble() : null;
String asStr(dynamic v, [String fallback = '']) => v is String ? v : fallback;
Map<String, dynamic> asMap(dynamic v) => v is Map ? v.cast<String, dynamic>() : const {};
List<dynamic> asList(dynamic v) => v is List ? v : const [];

class Machine {
  const Machine({
    required this.id,
    required this.name,
    required this.host,
    this.group = '',
    this.tags = const [],
    this.isController = false,
    this.hasBmc = false,
    this.bmcLabel,
    this.policy = const {},
  });
  final String id;
  final String name;
  final String host;
  final String group;
  final List<String> tags;
  final bool isController;
  final bool hasBmc;
  final String? bmcLabel;
  final Map<String, dynamic> policy;

  factory Machine.fromJson(Map<String, dynamic> j) {
    final bmc = j['bmc'];
    return Machine(
      id: asStr(j['id']),
      name: asStr(j['name']),
      host: asStr(j['host']),
      group: asStr(j['group']),
      tags: asList(j['tags']).whereType<String>().toList(growable: false),
      isController: j['is_controller'] == true,
      hasBmc: bmc is Map,
      bmcLabel: bmc is Map ? '${asStr(bmc['provider'], 'BMC')} · ${asStr(bmc['url'])}' : null,
      policy: asMap(j['policy']),
    );
  }
}

enum RigState { online, poolOffline, localOffline }

/// One miner instance as the rig reports it (runtime snapshot `mining.instances[]`).
class Instance {
  const Instance({
    required this.name,
    required this.coin,
    required this.miner,
    required this.desired,
    required this.alive,
    required this.statsFresh,
    this.phase,
    this.hashrateHs,
    this.accepted,
    this.rejected,
    this.connected,
    this.pool,
    this.sheetId,
    this.sheetName,
    this.sheetVersion,
    this.version,
    this.algorithm,
    this.uptime,
    this.error,
  });
  final String name;
  final String coin;
  final String miner;
  final String desired;
  final bool alive;
  final bool statsFresh;
  final String? phase;
  final double? hashrateHs;
  final int? accepted;
  final int? rejected;
  final bool? connected;
  final String? pool;
  final String? sheetId;
  final String? sheetName;
  final int? sheetVersion;
  final String? version;
  final String? algorithm;
  final double? uptime;
  final String? error;

  bool get running => desired == 'running';

  static Instance fromJson(Map<String, dynamic> j, double nowSec) {
    final stats = asMap(j['stats']);
    final statsAt = asNum(j['stats_observed_at']);
    final alive = j['process_alive'] == true;
    final desired = asStr(j['desired'], 'stopped');
    return Instance(
      name: asStr(j['instance']),
      coin: asStr(stats['coin'], asStr(j['configured_coin'], '?')).toUpperCase(),
      miner: asStr(j['miner_name'], asStr(j['miner'], asStr(j['instance']))),
      desired: desired,
      alive: alive,
      statsFresh: desired == 'running' && alive && statsAt != null && nowSec - statsAt < 60,
      phase: j['phase'] as String?,
      hashrateHs: asNum(stats['hashrate_hs']),
      accepted: asNum(stats['accepted'])?.toInt(),
      rejected: asNum(stats['rejected'])?.toInt(),
      connected: stats['connected'] is bool ? stats['connected'] as bool : null,
      pool: j['pool'] as String?,
      sheetId: j['sheet_id'] as String?,
      sheetName: j['sheet_name'] as String?,
      sheetVersion: asNum(j['sheet_version'])?.toInt(),
      version: (stats['version'] ?? j['package_version']) as String?,
      algorithm: (stats['algorithm'] ?? j['configured_algorithm']) as String?,
      uptime: asNum(stats['uptime']),
      error: j['error'] as String?,
    );
  }
}

class PoolCheck {
  const PoolCheck(this.instance, this.result, this.message, this.provider);
  final String instance;
  final String result;
  final String message;
  final String? provider;
}

class FleetRow {
  const FleetRow({
    required this.machine,
    required this.fresh,
    required this.state,
    required this.issues,
    required this.instances,
    required this.hashrateHs,
    required this.coin,
    this.cpuTemp,
    this.powerW,
    this.load,
    this.cpuPct,
    this.logicalCpus,
    this.memoryUsed,
    this.memoryTotal,
    this.address,
    this.transport,
    this.runtimeVersion,
    this.minerUptime,
    this.lastSeen,
    this.poolChecks = const [],
    this.poolState,
    this.gpuCount = 0,
  });
  final Machine machine;
  final bool fresh;
  final RigState state;
  final List<String> issues;
  final List<Instance> instances;
  final double hashrateHs;
  final String coin;
  final double? cpuTemp;
  final double? powerW;
  final double? load;
  final double? cpuPct;
  final int? logicalCpus;
  final double? memoryUsed;
  final double? memoryTotal;
  final String? address;
  final String? transport;
  final String? runtimeVersion;
  final double? minerUptime;
  final DateTime? lastSeen;
  final List<PoolCheck> poolChecks;
  final String? poolState;
  final int gpuCount;

  bool get poolOffline => state == RigState.poolOffline;
  bool get problem => issues.isNotEmpty;
}

class CoinRate {
  const CoinRate(this.coin, this.algorithm, this.hs, this.rigs);
  final String coin;
  final String algorithm;
  final double hs;
  final int rigs;
}

class FleetSnapshot {
  const FleetSnapshot({
    required this.rows,
    required this.rates,
    required this.powerW,
    required this.powerReadings,
    required this.statusAvailable,
    required this.online,
    required this.offline,
    required this.poolOffline,
    required this.problems,
    required this.poolChecked,
    required this.poolUnsupported,
  });
  final List<FleetRow> rows;
  final List<CoinRate> rates;
  final double powerW;
  final int powerReadings;
  final bool statusAvailable;
  final int online;
  final int offline;
  final int poolOffline;
  final int problems;
  final int poolChecked;
  final int poolUnsupported;

  static const empty = FleetSnapshot(
    rows: [],
    rates: [],
    powerW: 0,
    powerReadings: 0,
    statusAvailable: false,
    online: 0,
    offline: 0,
    poolOffline: 0,
    problems: 0,
    poolChecked: 0,
    poolUnsupported: 0,
  );
}

/// Natural order: rig-2 before rig-10.
int naturalCompare(String a, String b) {
  final re = RegExp(r'(\d+)|(\D+)');
  final x = re.allMatches(a.toLowerCase()).toList();
  final y = re.allMatches(b.toLowerCase()).toList();
  for (var i = 0; i < x.length && i < y.length; i++) {
    final p = x[i].group(0)!, q = y[i].group(0)!;
    final pn = int.tryParse(p), qn = int.tryParse(q);
    final c = (pn != null && qn != null) ? pn.compareTo(qn) : p.compareTo(q);
    if (c != 0) return c;
  }
  return x.length.compareTo(y.length);
}

class _Obs {
  _Obs(this.at, this.data, this.error);
  final DateTime? at;
  final Map<String, dynamic> data;
  final String? error;
  bool freshAt(int nowMs, int seconds) =>
      error == null && at != null && nowMs - at!.millisecondsSinceEpoch < seconds * 1000;
}

/// Build the fleet view from `/machines`, `/telemetry?summary=true` and `/status` (empty when
/// the controller predates offline detection). Runs on a background isolate.
FleetSnapshot buildFleet(String machinesJson, String telemetryJson, String statusJson, int nowMs) {
  final nowSec = nowMs / 1000;
  final machines = asList(jsonDecode(machinesJson))
      .map((m) => Machine.fromJson(asMap(m)))
      .toList()
    ..sort((a, b) => naturalCompare(a.name, b.name));
  final obs = <String, Map<String, _Obs>>{};
  for (final o in asList(jsonDecode(telemetryJson))) {
    final j = asMap(o);
    obs.putIfAbsent(asStr(j['machine_id']), () => {})[asStr(j['kind'])] = _Obs(
      DateTime.tryParse(asStr(j['observed_at'])),
      asMap(j['data']),
      j['error'] as String?,
    );
  }
  final statuses = <String, Map<String, dynamic>>{};
  var statusAvailable = false;
  if (statusJson.isNotEmpty) {
    statusAvailable = true;
    for (final s in asList(jsonDecode(statusJson))) {
      final j = asMap(s);
      statuses[asStr(j['machine_id'])] = j;
    }
  }

  final rows = <FleetRow>[];
  final rates = <String, (String, String, double, Set<String>)>{};
  var power = 0.0, readings = 0, online = 0, offline = 0, pool = 0, problems = 0;
  var poolChecked = 0, poolUnsupported = 0;
  for (final m in machines) {
    final o = obs[m.id] ?? const {};
    final system = o['system'], mining = o['mining'];
    final fresh = system?.freshAt(nowMs, 35) ?? false;
    final sys = fresh ? system!.data : const <String, dynamic>{};
    final instances = (mining != null && mining.freshAt(nowMs, 60))
        ? asList(mining.data['instances']).map((i) => Instance.fromJson(asMap(i), nowSec)).toList()
        : <Instance>[];
    final status = statuses[m.id];
    final checks = asList(status?['pool_checks'])
        .map((c) => asMap(c))
        .map((c) => PoolCheck(asStr(c['instance']), asStr(c['result']), asStr(c['message']), c['provider'] as String?))
        .toList(growable: false);
    final state = switch (status?['state']) {
      'local_offline' => RigState.localOffline,
      'pool_offline' => RigState.poolOffline,
      _ => fresh ? RigState.online : RigState.localOffline,
    };

    final issues = <String>[];
    if (system?.error != null) {
      issues.add('采集失败：${system!.error}');
    } else if (system != null && !fresh) {
      issues.add('超过 35 秒没有新数据');
    } else if (system == null) {
      issues.add('还没有收到数据');
    }
    if (state == RigState.poolOffline) {
      final why = checks.where((c) => c.result == 'missing' || c.result == 'zero').map((c) => c.message).join('；');
      issues.add('矿池离线：${why.isEmpty ? '矿池看不到算力' : why}');
    }
    for (final i in instances) {
      if (i.phase == 'faulted' || i.phase == 'failed') {
        issues.add('${i.name}：多次自动恢复失败，已停止重启');
      } else if (i.running && !i.alive) {
        issues.add('${i.name}：矿工进程未运行');
      } else if (i.error != null) {
        issues.add('${i.name}：${i.error}');
      } else if (i.connected == false) {
        issues.add('${i.name}：矿池未连接');
      }
    }

    var hs = 0.0;
    String coin = instances.isEmpty ? '' : instances.first.coin;
    double? uptime;
    for (final i in instances.where((i) => i.statsFresh)) {
      final r = i.hashrateHs;
      if (r != null) {
        hs += r;
        coin = i.coin;
        final key = '${i.coin}|${i.algorithm ?? ''}';
        final entry = rates[key] ?? (i.coin, i.algorithm ?? '', 0.0, <String>{});
        entry.$4.add(m.id);
        rates[key] = (entry.$1, entry.$2, entry.$3 + r, entry.$4);
      }
      final u = i.uptime;
      if (u != null && (uptime == null || u < uptime)) uptime = u;
    }

    final gpus = asList(sys['gpus']);
    double? watts;
    final cpuW = asNum(sys['cpu_power_w']);
    final gpuW = gpus.map((g) => asNum(asMap(g)['power_w'])).whereType<double>().toList();
    if (cpuW != null || gpuW.isNotEmpty) {
      watts = (cpuW ?? 0) + gpuW.fold(0.0, (a, b) => a + b);
      power += watts;
      readings++;
    }
    final addresses = asList(sys['addresses']);
    final load = asList(sys['load']);

    if (fresh) {
      online++;
    } else {
      offline++;
    }
    if (state == RigState.poolOffline) pool++;
    if (issues.isNotEmpty) problems++;
    final ps = status?['pool'] as String?;
    if (ps == 'online' || ps == 'offline') poolChecked++;
    if (ps == 'unsupported') poolUnsupported++;

    rows.add(FleetRow(
      machine: m,
      fresh: fresh,
      state: state,
      issues: issues,
      instances: instances,
      hashrateHs: hs,
      coin: coin,
      cpuTemp: asNum(sys['cpu_temperature']),
      powerW: watts,
      load: load.isEmpty ? null : asNum(load.first),
      cpuPct: asNum(sys['cpu_pct']),
      logicalCpus: asNum(sys['logical_cpus'])?.toInt(),
      memoryUsed: asNum(sys['memory_used']),
      memoryTotal: asNum(sys['memory_total']),
      address: addresses.isEmpty ? null : asStr(asMap(addresses.first)['address']),
      transport: sys['transport'] as String?,
      runtimeVersion: sys['runtime_version'] as String?,
      minerUptime: uptime,
      lastSeen: DateTime.tryParse(asStr(status?['last_seen_at'])) ?? system?.at,
      poolChecks: checks,
      poolState: ps,
      gpuCount: gpus.length,
    ));
  }
  final rateList = rates.values.map((r) => CoinRate(r.$1, r.$2, r.$3, r.$4.length)).toList()
    ..sort((a, b) => b.rigs != a.rigs ? b.rigs.compareTo(a.rigs) : b.hs.compareTo(a.hs));
  return FleetSnapshot(
    rows: rows,
    rates: rateList,
    powerW: power,
    powerReadings: readings,
    statusAvailable: statusAvailable,
    online: online,
    offline: offline,
    poolOffline: pool,
    problems: problems,
    poolChecked: poolChecked,
    poolUnsupported: poolUnsupported,
  );
}

class StatusAlert {
  const StatusAlert({
    required this.id,
    required this.machineId,
    required this.machineName,
    required this.kind,
    required this.event,
    required this.at,
    required this.message,
  });
  final int id;
  final String machineId;
  final String machineName;
  final String kind;
  final String event;
  final DateTime at;
  final String message;

  bool get offline => event == 'offline';
  String get title => kind == 'local'
      ? (offline ? '矿机离线' : '矿机恢复在线')
      : (offline ? '矿池离线' : '矿池恢复');

  factory StatusAlert.fromJson(Map<String, dynamic> j) => StatusAlert(
        id: asNum(j['id'])?.toInt() ?? 0,
        machineId: asStr(j['machine_id']),
        machineName: asStr(j['machine_name']),
        kind: asStr(j['kind']),
        event: asStr(j['event']),
        at: DateTime.tryParse(asStr(j['at']))?.toLocal() ?? DateTime.now(),
        message: asStr(j['message']),
      );
}

class MachineMessage {
  const MachineMessage(this.id, this.at, this.level, this.source, this.kind, this.instance, this.message);
  final String id;
  final DateTime at;
  final String level;
  final String source;
  final String kind;
  final String? instance;
  final String message;
  factory MachineMessage.fromJson(Map<String, dynamic> j) => MachineMessage(
        asStr(j['id']),
        DateTime.tryParse(asStr(j['at']))?.toLocal() ?? DateTime.now(),
        asStr(j['level'], 'info'),
        asStr(j['source']),
        asStr(j['kind']),
        j['instance'] as String?,
        asStr(j['message']),
      );
}

class FlightSheet {
  const FlightSheet(this.id, this.name, this.version, this.tasks);
  final String id;
  final String name;
  final int version;
  final List<FlightTask> tasks;
  factory FlightSheet.fromJson(Map<String, dynamic> j) => FlightSheet(
        asStr(j['id']),
        asStr(j['name']),
        asNum(j['version'])?.toInt() ?? 1,
        asList(j['tasks']).map((t) => FlightTask.fromJson(asMap(t))).toList(growable: false),
      );
}

class FlightTask {
  const FlightTask(this.instance, this.walletId, this.minerName, this.minerVersion, this.pools, this.algorithm);
  final String instance;
  final String walletId;
  final String minerName;
  final String minerVersion;
  final List<String> pools;
  final String algorithm;
  factory FlightTask.fromJson(Map<String, dynamic> j) {
    final miner = asMap(j['miner']);
    final config = asMap(j['config']);
    final urls = asList(config['urls']).whereType<String>().toList(growable: false);
    return FlightTask(
      asStr(j['instance']),
      asStr(j['wallet_id']),
      asStr(miner['name'], asStr(miner['adapter'])),
      asStr(miner['version']),
      urls.isEmpty && config['url'] is String ? [config['url'] as String] : urls,
      asStr(config['algorithm']),
    );
  }
}

class Wallet {
  const Wallet(this.id, this.name, this.coin, this.address, this.note);
  final String id;
  final String name;
  final String coin;
  final String address;
  final String note;
  factory Wallet.fromJson(Map<String, dynamic> j) {
    final d = asMap(j['data']);
    return Wallet(asStr(j['id']), asStr(j['name']), asStr(d['coin_symbol'], '?').toUpperCase(),
        asStr(d['address']), asStr(d['note'], asStr(d['source'])));
  }
}

class JobTarget {
  const JobTarget(this.id, this.machineName, this.status, this.output, this.error);
  final String id;
  final String machineName;
  final String status;
  final String output;
  final String? error;
}

class Job {
  const Job(this.id, this.kind, this.status, this.createdAt, this.actor, this.targets);
  final String id;
  final String kind;
  final String status;
  final DateTime createdAt;
  final String actor;
  final List<JobTarget> targets;

  bool get active => status == 'queued' || status == 'running';

  factory Job.fromJson(Map<String, dynamic> j) => Job(
        asStr(j['id']),
        asStr(asMap(j['action'])['kind'], '?'),
        asStr(j['status']),
        DateTime.tryParse(asStr(j['created_at']))?.toLocal() ?? DateTime.now(),
        asStr(j['actor']),
        asList(j['targets'])
            .map((t) => asMap(t))
            .map((t) => JobTarget(asStr(t['id']), asStr(t['machine_name']), asStr(t['status']),
                asStr(t['output']), t['error'] as String?))
            .toList(growable: false),
      );
}

/// A chart series reduced to at most [maxPoints] points (30 days of minute samples would
/// otherwise be 43 200 path segments per frame).
class Series {
  const Series(this.xs, this.ys, this.min, this.max, this.last);
  final List<double> xs;
  final List<double> ys;
  final double min;
  final double max;
  final double? last;
  bool get isEmpty => xs.isEmpty;
  static const empty = Series([], [], 0, 0, null);
}

Series reduceSeries(List<(int, double)> points, {int maxPoints = 240}) {
  if (points.isEmpty) return Series.empty;
  points.sort((a, b) => a.$1.compareTo(b.$1));
  final bucket = (points.length / maxPoints).ceil().clamp(1, points.length);
  final xs = <double>[], ys = <double>[];
  for (var i = 0; i < points.length; i += bucket) {
    final end = (i + bucket).clamp(0, points.length);
    var sum = 0.0;
    for (var k = i; k < end; k++) {
      sum += points[k].$2;
    }
    xs.add(points[i].$1.toDouble());
    ys.add(sum / (end - i));
  }
  var lo = ys.first, hi = ys.first;
  for (final y in ys) {
    if (y < lo) lo = y;
    if (y > hi) hi = y;
  }
  return Series(xs, ys, lo, hi, points.last.$2);
}

/// `/machines/{id}/history` → hashrate, CPU temperature and power series.
(Series, Series, Series) buildHistory(String miningJson, String systemJson) {
  final hash = <(int, double)>[], temp = <(int, double)>[], power = <(int, double)>[];
  for (final o in asList(jsonDecode(miningJson))) {
    final j = asMap(o);
    final at = DateTime.tryParse(asStr(j['observed_at']));
    if (at == null || j['error'] != null) continue;
    var sum = 0.0;
    var any = false;
    for (final i in asList(asMap(j['data'])['instances'])) {
      final r = asNum(asMap(asMap(i)['stats'])['hashrate_hs']);
      if (r != null) {
        sum += r;
        any = true;
      }
    }
    if (any) hash.add((at.millisecondsSinceEpoch, sum));
  }
  for (final o in asList(jsonDecode(systemJson))) {
    final j = asMap(o);
    final at = DateTime.tryParse(asStr(j['observed_at']));
    if (at == null || j['error'] != null) continue;
    final d = asMap(j['data']);
    final t = asNum(d['cpu_temperature']);
    if (t != null) temp.add((at.millisecondsSinceEpoch, t));
    final cpu = asNum(d['cpu_power_w']);
    final gpu = asList(d['gpus']).map((g) => asNum(asMap(g)['power_w'])).whereType<double>();
    if (cpu != null || gpu.isNotEmpty) {
      power.add((at.millisecondsSinceEpoch, (cpu ?? 0) + gpu.fold(0.0, (a, b) => a + b)));
    }
  }
  return (reduceSeries(hash), reduceSeries(temp), reduceSeries(power));
}
