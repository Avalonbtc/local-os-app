import 'package:flutter/material.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../theme.dart';
import 'more_page.dart';
import 'widgets.dart';

/// Actions on one or more machines. Everything becomes a controller job; the result shows up in
/// 任务 and in each machine's activity.
Future<void> showBatchSheet(BuildContext context, List<FleetRow> rows, {VoidCallback? onDone}) {
  final backend = AppScope.of(context).backend;
  Future<void> run(String label, List<String> ids, Map<String, dynamic> action) async {
    try {
      await submitJob(backend, ids, action);
      if (!context.mounted) return;
      onDone?.call();
      toast(context, '已提交：$label · ${ids.length} 台', action: '查看', onAction: () => push(context, const JobsPage()));
    } catch (e) {
      if (context.mounted) toast(context, '提交失败：${errorText(e)}');
    }
  }

  Future<void> miners(String op, String label) async {
    // One job per distinct instance set: the controller needs the instance names.
    final groups = <String, List<String>>{};
    for (final r in rows) {
      final names = r.instances.map((i) => i.name).toList()..sort();
      if (names.isEmpty) continue;
      groups.putIfAbsent(names.join(','), () => []).add(r.machine.id);
    }
    if (groups.isEmpty) {
      toast(context, '所选矿机没有托管矿工');
      return;
    }
    for (final e in groups.entries) {
      await run(label, e.value, {'kind': 'miner', 'operation': op, 'instances': e.key.split(',')});
    }
  }

  Future<void> power(String op, String label, {bool danger = false}) async {
    final ids = rows.where((r) => r.machine.hasBmc).map((r) => r.machine.id).toList();
    if (ids.isEmpty) {
      toast(context, '所选矿机都没有配置 BMC');
      return;
    }
    final skipped = rows.length - ids.length;
    final ok = await confirm(
      context,
      '$label ${ids.length} 台矿机？',
      '${skipped > 0 ? '$skipped 台没有 BMC，会跳过。' : ''}BMC 请求中断时不会推断是否执行，也不会自动重发。',
      action: label,
      danger: danger,
    );
    if (ok) await run(label, ids, {'kind': 'power', 'operation': op});
  }

  Future<void> apply() async {
    List<FlightSheet> sheets;
    try {
      sheets = (await backend.getJson('/api/v1/flight-sheets') as List).map((s) => FlightSheet.fromJson(asMap(s))).toList();
    } catch (e) {
      if (context.mounted) toast(context, '读取飞行表失败：${errorText(e)}');
      return;
    }
    if (!context.mounted) return;
    final sheet = await pickFlightSheet(context, sheets);
    if (sheet == null || !context.mounted) return;
    final ok = await confirm(context, '应用「${sheet.name}」？', '${rows.length} 台矿机会切换到这张飞行表（v${sheet.version}），矿工会重启。', action: '应用');
    if (ok) await run('应用飞行表', rows.map((r) => r.machine.id).toList(), {'kind': 'apply', 'sheet_id': sheet.id});
  }

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      Widget action(IconData icon, String label, Future<void> Function() onTap, {bool danger = false}) => _Action(
            icon: icon,
            label: label,
            danger: danger,
            onTap: () {
              Navigator.pop(sheetContext);
              onTap();
            },
          );
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(rows.length == 1 ? rows.first.machine.name : '对 ${rows.length} 台矿机', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              rows.take(4).map((r) => r.machine.name).join('、') + (rows.length > 4 ? ' 等' : ''),
              style: const TextStyle(fontSize: 12, color: C.muted),
            ),
            const SectionLabel('挖矿'),
            _Grid([
              action(Icons.rocket_launch_outlined, '应用飞行表', apply),
              action(Icons.play_arrow_rounded, '启动矿工', () => miners('start', '启动矿工')),
              action(Icons.stop_rounded, '停止矿工', () => miners('stop', '停止矿工')),
              action(Icons.restart_alt_rounded, '重启矿工', () => miners('restart', '重启矿工')),
            ]),
            const SectionLabel('电源（BMC）'),
            _Grid([
              action(Icons.power_settings_new_rounded, '开机', () => power('on', '开机')),
              action(Icons.power_off_outlined, '优雅关机', () => power('shutdown', '优雅关机')),
              action(Icons.flash_on_rounded, '强制重启', () => power('force_restart', '强制重启', danger: true), danger: true),
              action(Icons.block_rounded, '强制断电', () => power('force_off', '强制断电', danger: true), danger: true),
            ]),
          ]),
        ),
      );
    },
  );
}

Future<FlightSheet?> pickFlightSheet(BuildContext context, List<FlightSheet> sheets) => showModalBottomSheet<FlightSheet>(
      context: context,
      builder: (ctx) => SafeArea(
        child: sheets.isEmpty
            ? const EmptyHint('还没有飞行表，请先在主控网页创建')
            : ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 12),
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text('选择飞行表', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  for (final s in sheets)
                    ListTile(
                      title: Text(s.name),
                      subtitle: Text(
                        s.tasks.map((t) => '${t.minerName} ${t.minerVersion} · ${t.pools.isEmpty ? '—' : t.pools.first}').join('\n'),
                        style: const TextStyle(color: C.muted, fontSize: 12),
                      ),
                      trailing: Text('v${s.version}', style: const TextStyle(color: C.muted)),
                      onTap: () => Navigator.pop(ctx, s),
                    ),
                ],
              ),
      ),
    );

class _Grid extends StatelessWidget {
  const _Grid(this.children);
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: children[i]),
          ],
        ],
      );
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap, this.danger = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) => Panel(
        color: danger ? const Color(0xFF241719) : C.surface2,
        borderColor: danger ? const Color(0xFF5A2A2E) : const Color(0xFF2C333A),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        onTap: onTap,
        child: Column(children: [
          Icon(icon, color: danger ? C.badText : C.rate, size: 22),
          const SizedBox(height: 6),
          Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: danger ? C.badText : C.text)),
        ]),
      );
}
