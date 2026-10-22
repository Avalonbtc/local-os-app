import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme.dart';
import '../util/format.dart';
import 'more_page.dart';
import 'shell.dart';
import 'widgets.dart';

class AlertsPage extends StatefulWidget {
  const AlertsPage({super.key});
  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final alerts = AppScope.of(context).alerts;
    return Scaffold(
      appBar: AppBar(
        title: const Text('通知'),
        actions: [
          IconButton(
            tooltip: '通知设置',
            onPressed: () => push(context, const FarmSettingsPage()),
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: alerts,
        builder: (context, _) {
          if (!alerts.supported) {
            return const EmptyHint('这个主控还没有离线检测（需要包含 offline-alerts 的版本）', icon: Icons.notifications_off_outlined);
          }
          if (!alerts.loaded) return const Center(child: CircularProgressIndicator());
          final shown = alerts.items.where((a) => switch (_filter) {
                'offline' => a.offline,
                'pool' => a.kind == 'pool',
                'recovered' => !a.offline,
                _ => true,
              }).toList();
          // Flatten into day headers + items for one lazily built list.
          final entries = <Object>[];
          String? day;
          for (final a in shown) {
            final d = dayLabel(a.at);
            if (d != day) {
              entries.add(d);
              day = d;
            }
            entries.add(a);
          }
          return Column(children: [
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                children: [
                  for (final f in const [('all', '全部'), ('offline', '离线'), ('pool', '矿池'), ('recovered', '恢复')])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(label: Text(f.$2), selected: _filter == f.$1, onSelected: (_) => setState(() => _filter = f.$1)),
                    ),
                ],
              ),
            ),
            Expanded(
              child: entries.isEmpty
                  ? const EmptyHint('没有通知。矿机离线或恢复时会出现在这里。', icon: Icons.notifications_none_rounded)
                  : RefreshIndicator(
                      onRefresh: alerts.refresh,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: entries.length,
                        itemBuilder: (context, i) {
                          final e = entries[i];
                          if (e is String) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 14, bottom: 4),
                              child: Text(e, style: const TextStyle(fontSize: 12, color: C.muted)),
                            );
                          }
                          return _AlertTile(e as StatusAlert);
                        },
                      ),
                    ),
            ),
          ]);
        },
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile(this.a);
  final StatusAlert a;

  @override
  Widget build(BuildContext context) {
    final (fg, bg, icon) = !a.offline
        ? (C.okText, C.okBg, Icons.check_rounded)
        : a.kind == 'pool'
            ? (C.poolText, C.poolBg, Icons.warning_amber_rounded)
            : (C.badText, C.badBg, Icons.cloud_off_rounded);
    return InkWell(
      onTap: () => openMachine(context, a.machineId),
      child: DecoratedBox(
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.divider))),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            DecoratedBox(
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
              child: SizedBox.square(dimension: 36, child: Icon(icon, color: fg, size: 19)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('${a.title} · ${a.machineName}', style: const TextStyle(fontWeight: FontWeight.w600))),
                  Text(clock(a.at), style: mono.copyWith(fontSize: 12, color: C.muted)),
                ]),
                const SizedBox(height: 3),
                Text(a.message, style: const TextStyle(fontSize: 13, color: Color(0xFFB7C0C9), height: 1.45)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
