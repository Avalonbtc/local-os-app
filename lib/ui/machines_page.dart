import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme.dart';
import '../util/format.dart';
import 'batch_sheet.dart';
import 'machine_form_page.dart';
import 'shell.dart';
import 'widgets.dart';

enum _Filter { all, online, offline, pool, problem }

const _filterLabels = {
  _Filter.all: '全部',
  _Filter.online: '在线',
  _Filter.offline: '掉线',
  _Filter.pool: '矿池离线',
  _Filter.problem: '有问题',
};

/// Fixed row height: the list lays out 1 000 machines without measuring any of them.
const _rowExtent = 72.0;

class MachinesPage extends StatefulWidget {
  const MachinesPage({super.key});

  @override
  State<MachinesPage> createState() => _MachinesPageState();
}

class _MachinesPageState extends State<MachinesPage> {
  final _search = TextEditingController();
  _Filter _filter = _Filter.all;
  String _query = '';
  final Set<String> _selected = {};
  bool _selecting = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(FleetRow r) {
    switch (_filter) {
      case _Filter.online:
        if (!r.fresh) return false;
      case _Filter.offline:
        if (r.fresh) return false;
      case _Filter.pool:
        if (!r.poolOffline) return false;
      case _Filter.problem:
        if (!r.problem) return false;
      case _Filter.all:
        break;
    }
    if (_query.isEmpty) return true;
    final m = r.machine;
    return m.name.toLowerCase().contains(_query) ||
        m.host.contains(_query) ||
        (r.address?.contains(_query) ?? false) ||
        m.group.toLowerCase().contains(_query) ||
        m.tags.any((t) => t.toLowerCase().contains(_query));
  }

  int _count(FleetSnapshot s, _Filter f) => switch (f) {
        _Filter.all => s.rows.length,
        _Filter.online => s.online,
        _Filter.offline => s.offline,
        _Filter.pool => s.poolOffline,
        _Filter.problem => s.problems,
      };

  void _toggle(String id) => setState(() {
        if (!_selected.remove(id)) _selected.add(id);
        _selecting = _selected.isNotEmpty;
      });

  void _endSelection() => setState(() {
        _selected.clear();
        _selecting = false;
      });

  @override
  Widget build(BuildContext context) {
    final fleet = AppScope.of(context).fleet;
    return ListenableBuilder(
      listenable: fleet,
      builder: (context, _) {
        final s = fleet.snapshot;
        final rows = s.rows.where(_matches).toList(growable: false);
        // Machines deleted meanwhile drop out of the selection.
        if (_selected.isNotEmpty) {
          final ids = {for (final r in s.rows) r.machine.id};
          _selected.removeWhere((id) => !ids.contains(id));
        }
        return PopScope(
          canPop: !_selecting,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _endSelection();
          },
          child: Scaffold(
            appBar: _selecting
                ? AppBar(
                    leading: IconButton(tooltip: '退出多选', onPressed: _endSelection, icon: const Icon(Icons.close)),
                    title: Text('已选 ${_selected.length} 台'),
                    actions: [
                      TextButton(
                        onPressed: () => setState(() => _selected.addAll(rows.map((r) => r.machine.id))),
                        child: const Text('全选'),
                      ),
                      IconButton(
                        tooltip: '批量操作',
                        onPressed: _selected.isEmpty
                            ? null
                            : () => showBatchSheet(
                                  context,
                                  s.rows.where((r) => _selected.contains(r.machine.id)).toList(),
                                  onDone: _endSelection,
                                ),
                        icon: const Icon(Icons.bolt_rounded, color: C.accent),
                      ),
                    ],
                  )
                : AppBar(
                    title: Text.rich(TextSpan(children: [
                      const TextSpan(text: '矿机 '),
                      TextSpan(text: '${s.rows.length}', style: mono.copyWith(fontSize: 14, color: C.muted, fontWeight: FontWeight.w400)),
                    ])),
                    actions: [
                      PopupMenuButton<bool>(
                        tooltip: '添加矿机',
                        icon: const Icon(Icons.add),
                        onSelected: (batch) => push(context, batch ? const BatchImportPage() : const MachineFormPage()),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: false, child: Text('添加一台')),
                          PopupMenuItem(value: true, child: Text('批量添加')),
                        ],
                      ),
                      IconButton(
                        tooltip: '多选',
                        onPressed: () => setState(() => _selecting = true),
                        icon: const Icon(Icons.checklist_rounded),
                      ),
                    ],
                  ),
            body: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                  decoration: InputDecoration(
                    hintText: '搜索名称、IP、分组、标签',
                    prefixIcon: const Icon(Icons.search, color: C.muted, size: 20),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清除',
                            onPressed: () => setState(() {
                              _search.clear();
                              _query = '';
                            }),
                            icon: const Icon(Icons.close, size: 18),
                          ),
                  ),
                ),
              ),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    for (final f in _Filter.values)
                      if (f != _Filter.pool || s.statusAvailable)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text('${_filterLabels[f]} ${_count(s, f)}'),
                            selected: _filter == f,
                            onSelected: (_) => setState(() => _filter = f),
                          ),
                        ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: !fleet.loaded
                    ? (fleet.error == null
                        ? const Center(child: CircularProgressIndicator())
                        : EmptyHint('连接主控失败：${errorText(fleet.error!)}', icon: Icons.cloud_off_outlined))
                    : rows.isEmpty
                        ? EmptyHint(s.rows.isEmpty ? '还没有矿机，请先在主控网页添加' : '没有符合条件的矿机')
                        : RefreshIndicator(
                            onRefresh: fleet.refresh,
                            child: ListView.builder(
                              itemExtent: _rowExtent,
                              itemCount: rows.length,
                              itemBuilder: (context, i) {
                                final r = rows[i];
                                return _MachineTile(
                                  key: ValueKey(r.machine.id),
                                  row: r,
                                  selecting: _selecting,
                                  selected: _selected.contains(r.machine.id),
                                  onTap: () => _selecting ? _toggle(r.machine.id) : openMachine(context, r.machine.id),
                                  onLongPress: () => _toggle(r.machine.id),
                                );
                              },
                            ),
                          ),
              ),
            ]),
          ),
        );
      },
    );
  }
}

class _MachineTile extends StatelessWidget {
  const _MachineTile({
    super.key,
    required this.row,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });
  final FleetRow row;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final r = row;
    final look = rowLook(r);
    final running = r.instances.where((i) => i.running).toList();
    final sub = !r.fresh
        ? (r.issues.isEmpty ? '离线' : r.issues.first)
        : running.isEmpty
            ? '未运行矿工'
            : '${r.coin} · ${r.minerUptime == null ? running.first.miner : '运行 ${uptime(r.minerUptime)}'}';
    final rateText = !r.fresh
        ? '—'
        : r.hashrateHs > 0
            ? hashrate(r.hashrateHs)
            : (running.isEmpty ? '—' : '等待统计');
    return Material(
      color: selected ? const Color(0xFF241F14) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: DecoratedBox(
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.divider))),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              if (selecting)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Icon(
                    selected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                    color: selected ? C.accent : C.faint,
                  ),
                )
              else
                Padding(padding: const EdgeInsets.only(right: 12), child: Dot(look.dot)),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(r.machine.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                      if (look.label != '在线') ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: FittedBox(fit: BoxFit.scaleDown, child: Tag(look.label, fg: look.fg, bg: look.bg)),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 3),
                    Text(
                      '${r.address ?? r.machine.host} · $sub',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: C.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Capped so the name keeps its room on narrow phones; figures scale down instead.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 116),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(rateText, style: mono.copyWith(fontSize: 14, fontWeight: FontWeight.w600, color: r.hashrateHs > 0 ? C.rate : C.faint)),
                      const SizedBox(height: 3),
                      Text(
                        r.fresh ? '${celsius(r.cpuTemp)} · ${watts(r.powerW)}' : '—',
                        style: mono.copyWith(fontSize: 12, color: C.muted),
                      ),
                    ],
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
