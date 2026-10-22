import 'dart:isolate';

import 'package:flutter/material.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../data/stores.dart';
import '../theme.dart';
import '../util/format.dart';
import 'batch_sheet.dart';
import 'more_page.dart';
import 'widgets.dart';

class MachineDetailPage extends StatelessWidget {
  const MachineDetailPage({super.key, required this.machineId});
  final String machineId;

  @override
  Widget build(BuildContext context) {
    final fleet = AppScope.of(context).fleet;
    return DefaultTabController(
      length: 5,
      child: ListenableBuilder(
        listenable: fleet,
        builder: (context, _) {
          final row = fleet.row(machineId);
          if (row == null) {
            return Scaffold(appBar: AppBar(), body: const EmptyHint('这台矿机已不存在'));
          }
          final look = rowLook(row);
          return Scaffold(
            appBar: AppBar(
              title: Row(children: [
                Flexible(child: Text(row.machine.name, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                Tag(look.label, fg: look.fg, bg: look.bg),
              ]),
              actions: [
                IconButton(
                  tooltip: '操作',
                  onPressed: () => showBatchSheet(context, [row]),
                  icon: const Icon(Icons.bolt_rounded),
                ),
              ],
              bottom: const TabBar(
                isScrollable: true,
                tabs: [Tab(text: '概述'), Tab(text: '矿工'), Tab(text: '统计'), Tab(text: '活动'), Tab(text: '电源')],
              ),
            ),
            body: TabBarView(children: [
              _Overview(row),
              _Miners(row),
              _Stats(machineId),
              _Activity(machineId),
              _Power(row),
            ]),
          );
        },
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview(this.r);
  final FleetRow r;

  @override
  Widget build(BuildContext context) {
    final i = r.instances.isEmpty ? null : r.instances.first;
    final shares = r.instances.fold<(int, int)>((0, 0), (a, x) => (a.$1 + (x.accepted ?? 0), a.$2 + (x.rejected ?? 0)));
    final rejectPct = shares.$1 + shares.$2 == 0 ? null : shares.$2 * 100 / (shares.$1 + shares.$2);
    final bad = r.poolChecks.where((c) => c.result == 'missing' || c.result == 'zero').toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (r.poolOffline) ...[
          Notice('矿池看不到这台矿机：${bad.isEmpty ? '矿池没有看到算力' : bad.map((c) => c.message).join('；')}。检查矿工的矿池地址和登录名，或代理是否重启过。'),
          const SizedBox(height: 12),
        ] else if (!r.fresh) ...[
          Notice(
            r.issues.isEmpty ? '没有收到这台矿机的数据' : r.issues.first,
            fg: C.badText,
            bg: C.badBg,
            border: const Color(0xFF5A2A2E),
            icon: Icons.cloud_off_outlined,
          ),
          const SizedBox(height: 12),
        ],
        Row(children: [
          Expanded(child: _Mini('本机算力', r.hashrateHs > 0 ? hashrate(r.hashrateHs) : '—', r.coin.isEmpty ? '' : r.coin, color: C.rate)),
          const SizedBox(width: 8),
          Expanded(child: _Mini('CPU 温度', celsius(r.cpuTemp), '功耗 ${watts(r.powerW)}')),
          const SizedBox(width: 8),
          Expanded(child: _Mini('份额', shares.$1 == 0 ? '—' : 'A ${shares.$1}', rejectPct == null ? '' : '拒绝 ${rejectPct.toStringAsFixed(1)}%')),
        ]),
        const SizedBox(height: 12),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Column(children: [
            KeyValue('状态', r.fresh ? '本地在线 · ${r.transport == 'push' ? '主动上报' : 'SSH 读取'}' : '离线 · 最后数据 ${r.lastSeen == null ? '—' : ago(r.lastSeen!)}'),
            if (i?.sheetName != null) KeyValue('飞行表', '${i!.sheetName}${i.sheetVersion == null ? '' : '（v${i.sheetVersion}）'}'),
            if (i != null) KeyValue('矿工', '${i.miner} ${i.version ?? ''} · 实例 ${r.instances.map((x) => x.name).join('、')}'),
            if (i?.pool != null) KeyValue('矿池', i!.pool!, valueStyle: mono.copyWith(fontSize: 13)),
            KeyValue('矿工运行', uptime(r.minerUptime)),
            KeyValue('CPU', '${r.logicalCpus ?? '—'} 线程 · 负载 ${r.load?.toStringAsFixed(1) ?? '—'}'),
            KeyValue('内存', r.memoryTotal == null ? '—' : '${gib(r.memoryUsed)} / ${gib(r.memoryTotal)} GiB'),
            if (r.gpuCount > 0) KeyValue('显卡', '${r.gpuCount} 块'),
            KeyValue('运行层', r.runtimeVersion ?? '—'),
          ]),
        ),
        const SizedBox(height: 12),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Column(children: [
            KeyValue('内网 IP', r.address ?? r.machine.host, valueStyle: mono.copyWith(fontSize: 13)),
            KeyValue('SSH', r.machine.host, valueStyle: mono.copyWith(fontSize: 13)),
            KeyValue('BMC', r.machine.bmcLabel ?? '未配置'),
            KeyValue('分组 / 标签', [r.machine.group, r.machine.tags.join(', ')].where((s) => s.isNotEmpty).join(' · ')),
          ]),
        ),
        if (r.issues.length > 1) ...[
          const SectionLabel('问题'),
          Panel(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final issue in r.issues)
                Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text('· $issue', style: const TextStyle(fontSize: 13, height: 1.4))),
            ]),
          ),
        ],
      ],
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini(this.label, this.value, this.sub, {this.color});
  final String label;
  final String value;
  final String sub;
  final Color? color;
  @override
  Widget build(BuildContext context) => Panel(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: C.muted)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: mono.copyWith(fontSize: 17, fontWeight: FontWeight.w600, color: color)),
          ),
          const SizedBox(height: 2),
          Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: C.muted)),
        ]),
      );
}

class _Miners extends StatefulWidget {
  const _Miners(this.r);
  final FleetRow r;
  @override
  State<_Miners> createState() => _MinersState();
}

class _MinersState extends State<_Miners> with AutomaticKeepAliveClientMixin {
  String? _logInstance;
  String? _log;
  bool _loadingLog = false;

  @override
  bool get wantKeepAlive => true;

  Future<void> _op(String op, String label, Instance i) async {
    final scope = AppScope.of(context);
    try {
      await submitJob(scope.backend, [widget.r.machine.id], {'kind': 'miner', 'operation': op, 'instances': [i.name]});
      if (mounted) toast(context, '已提交：$label ${i.name}', action: '查看', onAction: () => push(context, const JobsPage()));
    } catch (e) {
      if (mounted) toast(context, '提交失败：${errorText(e)}');
    }
  }

  Future<void> _loadLog(String instance) async {
    setState(() {
      _logInstance = instance;
      _loadingLog = true;
    });
    try {
      final log = await AppScope.of(context)
          .backend
          .getJson('/api/v1/machines/${widget.r.machine.id}/instances/$instance/log', query: const {'lines': '200'});
      if (mounted) setState(() => _log = asStr(asMap(log)['text']));
    } catch (e) {
      if (mounted) setState(() => _log = '读取日志失败：${errorText(e)}');
    } finally {
      if (mounted) setState(() => _loadingLog = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final r = widget.r;
    if (r.instances.isEmpty) {
      return EmptyHint(r.fresh ? '这台矿机还没有托管矿工，请先应用飞行表' : '矿机离线，看不到矿工状态');
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final i in r.instances) ...[
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                DecoratedBox(
                  decoration: BoxDecoration(color: const Color(0xFF2A2416), borderRadius: BorderRadius.circular(10)),
                  child: SizedBox.square(
                    dimension: 36,
                    child: Center(child: Text(i.coin, style: mono.copyWith(color: C.rate, fontWeight: FontWeight.w700, fontSize: 11))),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${i.name} · ${i.miner} ${i.version ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(i.pool ?? i.sheetName ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: C.muted)),
                  ]),
                ),
                _stateTag(i),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _Field('算力', i.statsFresh ? hashrate(i.hashrateHs) : '—', color: C.rate)),
                Expanded(child: _Field('接受 / 拒绝', i.accepted == null ? '—' : '${i.accepted} / ${i.rejected ?? 0}')),
                Expanded(child: _Field('矿池连接', i.connected == null ? '—' : (i.connected! ? '已连接' : '断开'))),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _op(i.running ? 'stop' : 'start', i.running ? '停止' : '启动', i),
                    child: Text(i.running ? '停止' : '启动'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton(onPressed: () => _op('restart', '重启', i), child: const Text('重启'))),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton(onPressed: () => _loadLog(i.name), child: const Text('日志'))),
              ]),
            ]),
          ),
          const SizedBox(height: 12),
        ],
        if (_logInstance != null) ...[
          SectionLabel(
            '矿工日志 · $_logInstance',
            trailing: IconButton(
              tooltip: '刷新日志',
              onPressed: _loadingLog ? null : () => _loadLog(_logInstance!),
              icon: const Icon(Icons.refresh_rounded, size: 20),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF0B0D10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: C.divider),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _loadingLog && _log == null
                  ? const Center(child: CircularProgressIndicator())
                  : SelectableText(_log ?? '', style: mono.copyWith(fontSize: 11, height: 1.6, color: const Color(0xFFB9C3CC))),
            ),
          ),
        ],
      ],
    );
  }

  Widget _stateTag(Instance i) {
    if (!i.running) return const Tag('已停止', fg: C.text2, bg: C.greyBg);
    if (!i.alive) return const Tag('未运行', fg: C.badText, bg: C.badBg);
    if (i.phase == 'warmup' || i.phase == 'verifying') return const Tag('预热', fg: C.rate, bg: Color(0xFF2A2416));
    return const Tag('运行中', fg: C.okText, bg: C.okBg);
  }
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.value, {this.color});
  final String label;
  final String value;
  final Color? color;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 12, color: C.muted)),
        const SizedBox(height: 2),
        Text(value, style: mono.copyWith(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
      ]);
}

const _ranges = [(1, '1 小时'), (6, '6 小时'), (24, '24 小时'), (168, '7 天'), (720, '30 天')];

/// Top level: the isolate closure must not capture widget state.
Future<(Series, Series, Series)> _historyOffThread(String mining, String system) => FleetStore.offThread
    ? Isolate.run(() => buildHistory(mining, system))
    : Future.value(buildHistory(mining, system));

class _Stats extends StatefulWidget {
  const _Stats(this.machineId);
  final String machineId;
  @override
  State<_Stats> createState() => _StatsState();
}

class _StatsState extends State<_Stats> with AutomaticKeepAliveClientMixin {
  int _hours = 24;
  (Series, Series, Series)? _data;
  Object? _error;
  int _request = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_data == null && _error == null) _load();
  }

  Future<void> _load() async {
    final ticket = ++_request;
    // Also runs from didChangeDependencies, so no setState before the first await.
    _error = null;
    final backend = AppScope.of(context).backend;
    final q = {'hours': '$_hours', 'summary': 'true'};
    try {
      final bodies = await Future.wait([
        backend.raw('GET', '/api/v1/machines/${widget.machineId}/history', query: {...q, 'kind': 'mining'}),
        backend.raw('GET', '/api/v1/machines/${widget.machineId}/history', query: {...q, 'kind': 'system'}),
      ]);
      final data = await _historyOffThread(bodies[0], bodies[1]);
      if (mounted && ticket == _request) setState(() => _data = data);
    } catch (e) {
      if (mounted && ticket == _request) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final d = _data;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<int>(
          segments: [for (final r in _ranges) ButtonSegment(value: r.$1, label: Text(r.$2, style: const TextStyle(fontSize: 12)))],
          selected: {_hours},
          showSelectedIcon: false,
          onSelectionChanged: (v) {
            setState(() => _hours = v.first);
            _load();
          },
        ),
        const SizedBox(height: 12),
        if (_error != null)
          Notice('读取历史失败：${errorText(_error!)}')
        else if (d == null)
          const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
        else ...[
          _ChartCard('算力', d.$1, C.accent, hashrate),
          const SizedBox(height: 12),
          _ChartCard('CPU 温度', d.$2, C.chartTemp, celsius),
          const SizedBox(height: 12),
          _ChartCard('软件功耗', d.$3, C.info, watts),
        ],
      ],
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard(this.title, this.s, this.color, this.fmt);
  final String title;
  final Series s;
  final Color color;
  final String Function(double?) fmt;

  @override
  Widget build(BuildContext context) => Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))),
            Text(fmt(s.last), style: mono.copyWith(fontSize: 13, color: color)),
          ]),
          const SizedBox(height: 8),
          s.isEmpty
              ? const SizedBox(height: 104, child: Center(child: Text('这段时间没有数据', style: TextStyle(color: C.muted, fontSize: 12))))
              : LineChart(ys: s.ys, color: color),
          const SizedBox(height: 6),
          if (!s.isEmpty)
            Row(children: [
              Expanded(child: Text('最低 ${fmt(s.min)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: mono.copyWith(fontSize: 11, color: C.muted))),
              const SizedBox(width: 8),
              Expanded(
                child: Text('最高 ${fmt(s.max)}', maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right, style: mono.copyWith(fontSize: 11, color: C.muted)),
              ),
            ]),
        ]),
      );
}

class _Activity extends StatefulWidget {
  const _Activity(this.machineId);
  final String machineId;
  @override
  State<_Activity> createState() => _ActivityState();
}

class _ActivityState extends State<_Activity> with AutomaticKeepAliveClientMixin {
  List<MachineMessage>? _items;
  Object? _error;
  String _filter = 'all';

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_items == null && _error == null) _load();
  }

  Future<void> _load() async {
    try {
      final list = await AppScope.of(context).backend.getJson('/api/v1/machines/${widget.machineId}/messages', query: const {'limit': '100'}) as List;
      if (mounted) setState(() => _items = list.map((m) => MachineMessage.fromJson(asMap(m))).toList());
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_error != null) return EmptyHint('读取消息失败：${errorText(_error!)}');
    final items = _items;
    if (items == null) return const Center(child: CircularProgressIndicator());
    final shown = items.where((m) => switch (_filter) {
          'warn' => m.level == 'warning' || m.level == 'error',
          'runtime' => m.source == 'runtime',
          'job' => m.source == 'job',
          'audit' => m.source == 'audit',
          _ => true,
        }).toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        itemCount: shown.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return SizedBox(
              height: 44,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final f in const [('all', '全部'), ('warn', '告警与错误'), ('runtime', '矿机事件'), ('job', '任务'), ('audit', '操作记录')])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(label: Text(f.$2), selected: _filter == f.$1, onSelected: (_) => setState(() => _filter = f.$1)),
                  ),
              ]),
            );
          }
          final m = shown[index - 1];
          final color = switch (m.level) {
            'error' => C.bad,
            'warning' => C.pool,
            'success' => C.ok,
            _ => C.info,
          };
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 5, right: 12), child: Dot(color, size: 10)),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m.message, style: const TextStyle(fontSize: 13, height: 1.45)),
                  const SizedBox(height: 3),
                  Text(
                    '${ago(m.at)} · ${const {'runtime': '运行层', 'job': '任务', 'audit': '操作记录'}[m.source] ?? m.source}${m.instance == null ? '' : ' · ${m.instance}'}',
                    style: const TextStyle(fontSize: 12, color: C.muted),
                  ),
                ]),
              ),
            ]),
          );
        },
      ),
    );
  }
}

class _Power extends StatefulWidget {
  const _Power(this.r);
  final FleetRow r;
  @override
  State<_Power> createState() => _PowerState();
}

class _PowerState extends State<_Power> with AutomaticKeepAliveClientMixin {
  Map<String, dynamic>? _power;
  List<dynamic>? _sensors;
  Object? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.r.machine.hasBmc && _power == null && _error == null) _load();
  }

  Future<void> _load() async {
    final b = AppScope.of(context).backend;
    final id = widget.r.machine.id;
    try {
      final results = await Future.wait([b.getJson('/api/v1/machines/$id/bmc/power'), b.getJson('/api/v1/machines/$id/bmc/sensors')]);
      if (mounted) {
        setState(() {
          _power = asMap(results[0]);
          _sensors = asList(asMap(results[1])['items']);
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final r = widget.r;
    if (!r.machine.hasBmc) {
      return const EmptyHint('这台矿机没有配置 BMC，不能远程开关机。\n在主控网页的矿机设置里添加 Redfish 或 IPMI。', icon: Icons.power_off_outlined);
    }
    final state = asStr(_power?['state'], '—');
    final on = state.toLowerCase() == 'on';
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null) ...[Notice('读取 BMC 失败：${errorText(_error!)}'), const SizedBox(height: 12)],
          Panel(
            child: Row(children: [
              Icon(Icons.power_settings_new_rounded, color: on ? C.okText : C.muted, size: 30),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_power == null ? '读取中…' : (on ? '已开机' : (state == 'Off' ? '已关机' : state)), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(r.machine.bmcLabel ?? 'BMC', style: const TextStyle(fontSize: 12, color: C.muted)),
                ]),
              ),
              Text(watts(asNum(_power?['power_w'])), style: mono.copyWith(fontSize: 18, fontWeight: FontWeight.w600)),
            ]),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => showBatchSheet(context, [r]),
            icon: const Icon(Icons.bolt_rounded, color: C.accent),
            label: const Text('开机 / 关机 / 强制重启…'),
          ),
          const SizedBox(height: 4),
          const Text('BMC 请求中断时不会按当前开关状态推断是否执行，也不会自动重发。', style: TextStyle(fontSize: 12, color: C.muted)),
          if (_sensors != null && _sensors!.isNotEmpty) ...[
            const SectionLabel('传感器'),
            Panel(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Column(children: [
                for (final s in _sensors!.map(asMap))
                  KeyValue(
                    asStr(s['name']),
                    '${asNum(s['reading'])?.toStringAsFixed(0) ?? '—'} ${asStr(s['unit'])}',
                    valueStyle: mono.copyWith(fontSize: 13, color: asStr(s['health'], 'OK') == 'OK' ? C.text : C.poolText),
                  ),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}
