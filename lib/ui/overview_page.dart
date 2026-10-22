import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme.dart';
import '../util/format.dart';
import 'more_page.dart';
import 'shell.dart';
import 'widgets.dart';

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key, required this.onOpenTab});
  final void Function(int tab) onOpenTab;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final fleet = scope.fleet;
    return Scaffold(
      appBar: AppBar(
        title: Text(scope.session.demo ? '矿场总览 · 演示' : '矿场总览'),
        actions: [
          IconButton(tooltip: '刷新', onPressed: fleet.refresh, icon: const Icon(Icons.refresh_rounded)),
          IconButton(
            tooltip: '矿场设定',
            onPressed: () => push(context, const FarmSettingsPage()),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: fleet,
        builder: (context, _) {
          final s = fleet.snapshot;
          if (!fleet.loaded) {
            return fleet.error == null
                ? const Center(child: CircularProgressIndicator())
                : EmptyHint('连接主控失败：${errorText(fleet.error!)}', icon: Icons.cloud_off_outlined);
          }
          final attention = [...s.rows.where((r) => r.problem)]
            ..sort((a, b) => _rank(a).compareTo(_rank(b)));
          final main = s.rates.isEmpty ? null : s.rates.first;
          return RefreshIndicator(
            onRefresh: fleet.refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                if (fleet.error != null) ...[
                  Notice('刷新失败，显示的是上一次的数据：${errorText(fleet.error!)}'),
                  const SizedBox(height: 10),
                ],
                Row(children: [
                  Expanded(
                    child: _Stat(
                      label: '矿机',
                      value: '${s.rows.length}',
                      unit: '台',
                      onTap: () => onOpenTab(1),
                      footer: Text.rich(TextSpan(children: [
                        TextSpan(text: '在线 ${s.online}  ', style: const TextStyle(color: C.okText)),
                        TextSpan(text: '离线 ${s.offline}  ', style: const TextStyle(color: C.badText)),
                        if (s.statusAvailable) TextSpan(text: '矿池 ${s.poolOffline}', style: const TextStyle(color: C.poolText)),
                      ]), style: const TextStyle(fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Stat(
                      label: main == null ? '算力' : '${main.coin} · ${main.algorithm}',
                      value: main == null ? '—' : hashrateParts(main.hs).$1,
                      unit: main == null ? '' : hashrateParts(main.hs).$2,
                      footer: Text(main == null ? '没有矿工在出算力' : '${main.rigs} 台出算力', style: const TextStyle(fontSize: 12, color: C.muted)),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: _Stat(
                      label: '软件功耗',
                      value: s.powerReadings == 0 ? '—' : (s.powerW / 1000).toStringAsFixed(2),
                      unit: 'kW',
                      footer: Text('${s.powerReadings}/${s.rows.length} 台有读数', style: const TextStyle(fontSize: 12, color: C.muted)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: _CostTile(powerW: s.powerReadings == 0 ? null : s.powerW, price: fleet.price)),
                ]),
                if (s.rates.length > 1) ...[
                  const SizedBox(height: 10),
                  Panel(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    child: Column(children: [
                      for (final r in s.rates.skip(1))
                        KeyValue('${r.coin} ${r.algorithm}', '${hashrate(r.hs)} · ${r.rigs} 台', valueStyle: mono.copyWith(fontSize: 13, color: C.rate)),
                    ]),
                  ),
                ],
                const SizedBox(height: 10),
                Panel(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Expanded(child: Text('实时算力', style: TextStyle(fontWeight: FontWeight.w600))),
                      Text('本次打开以来 · 每 10 秒', style: const TextStyle(fontSize: 12, color: C.muted)),
                    ]),
                    const SizedBox(height: 10),
                    fleet.recent.length < 2
                        ? const SizedBox(height: 64, child: Center(child: Text('收集中…', style: TextStyle(color: C.muted, fontSize: 12))))
                        : LineChart(ys: List.unmodifiable(fleet.recent), color: C.accent, height: 64),
                  ]),
                ),
                SectionLabel('需要处理', trailing: TextButton(onPressed: () => onOpenTab(3), child: const Text('全部通知'))),
                if (attention.isEmpty)
                  const Panel(child: Row(children: [
                    Icon(Icons.check_circle_outline, color: C.okText, size: 20),
                    SizedBox(width: 10),
                    Text('没有需要处理的矿机'),
                  ]))
                else
                  Panel(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(children: [
                      for (final r in attention.take(6)) _IssueTile(r),
                    ]),
                  ),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _Quick(icon: Icons.checklist_rounded, label: '批量操作', onTap: () => onOpenTab(1))),
                  const SizedBox(width: 8),
                  Expanded(child: _Quick(icon: Icons.rocket_launch_outlined, label: '应用飞行表', onTap: () => onOpenTab(2))),
                  const SizedBox(width: 8),
                  Expanded(child: _Quick(icon: Icons.task_alt_rounded, label: '任务进度', onTap: () => push(context, const JobsPage()))),
                ]),
              ],
            ),
          );
        },
      ),
    );
  }

  static int _rank(FleetRow r) => !r.fresh ? 0 : (r.poolOffline ? 1 : 2);
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.unit, required this.footer, this.onTap});
  final String label;
  final String value;
  final String unit;
  final Widget footer;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Panel(
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: C.muted)),
          const SizedBox(height: 6),
          // Scales down instead of overflowing on narrow phones or large system font sizes.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Text(value, style: mono.copyWith(fontSize: 26, fontWeight: FontWeight.w600)),
              const SizedBox(width: 5),
              Text(unit, style: const TextStyle(color: C.muted)),
            ]),
          ),
          const SizedBox(height: 6),
          footer,
        ]),
      );
}

class _CostTile extends StatelessWidget {
  const _CostTile({required this.powerW, required this.price});
  final double? powerW;
  final double? price;

  @override
  Widget build(BuildContext context) {
    final p = price, w = powerW;
    final daily = (p == null || w == null) ? null : w / 1000 * 24 * p;
    return _Stat(
      label: '预估电费',
      value: daily == null ? '—' : '¥${daily.toStringAsFixed(1)}',
      unit: '/日',
      onTap: () => push(context, const FarmSettingsPage()),
      footer: Text(p == null ? '电价未读取' : '${p.toStringAsFixed(2)} 元/度', style: const TextStyle(fontSize: 12, color: C.muted)),
    );
  }
}

class _IssueTile extends StatelessWidget {
  const _IssueTile(this.r);
  final FleetRow r;

  @override
  Widget build(BuildContext context) {
    final look = rowLook(r);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => openMachine(context, r.machine.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(children: [
          Tag(look.label, fg: look.fg, bg: look.bg),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.machine.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(r.issues.first, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: C.muted)),
            ]),
          ),
          const Icon(Icons.chevron_right, color: C.faint),
        ]),
      ),
    );
  }
}

class _Quick extends StatelessWidget {
  const _Quick({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Panel(
        color: C.surface2,
        padding: const EdgeInsets.symmetric(vertical: 12),
        onTap: onTap,
        child: Column(children: [
          Icon(icon, color: C.rate, size: 22),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ]),
      );
}
