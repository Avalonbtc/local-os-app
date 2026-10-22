import 'package:flutter/material.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../theme.dart';
import 'more_page.dart';
import 'widgets.dart';

class FlightsPage extends StatefulWidget {
  const FlightsPage({super.key});
  @override
  State<FlightsPage> createState() => _FlightsPageState();
}

class _FlightsPageState extends State<FlightsPage> {
  List<FlightSheet>? _sheets;
  Map<String, Wallet> _wallets = const {};
  Object? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sheets == null && _error == null) _load();
  }

  Future<void> _load() async {
    final b = AppScope.of(context).backend;
    try {
      final results = await Future.wait([b.getJson('/api/v1/flight-sheets'), b.getJson('/api/v1/catalog/wallets')]);
      if (!mounted) return;
      setState(() {
        _sheets = (results[0] as List).map((s) => FlightSheet.fromJson(asMap(s))).toList()
          ..sort((a, b) => naturalCompare(a.name, b.name));
        _wallets = {for (final w in (results[1] as List).map((w) => Wallet.fromJson(asMap(w)))) w.id: w};
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _apply(FlightSheet sheet) async {
    final scope = AppScope.of(context);
    final rows = scope.fleet.snapshot.rows;
    final picked = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MachinePicker(rows: rows, sheet: sheet),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    try {
      await submitJob(scope.backend, picked, {'kind': 'apply', 'sheet_id': sheet.id});
      if (mounted) toast(context, '已提交：应用「${sheet.name}」· ${picked.length} 台', action: '查看', onAction: () => push(context, const JobsPage()));
    } catch (e) {
      if (mounted) toast(context, '提交失败：${errorText(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final fleet = AppScope.of(context).fleet;
    final sheets = _sheets;
    return Scaffold(
      appBar: AppBar(
        title: const Text('飞行表'),
        actions: [
          IconButton(tooltip: '钱包', onPressed: () => push(context, const WalletsPage()), icon: const Icon(Icons.account_balance_wallet_outlined)),
        ],
      ),
      body: _error != null
          ? EmptyHint('读取飞行表失败：${errorText(_error!)}', icon: Icons.cloud_off_outlined)
          : sheets == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListenableBuilder(
                    listenable: fleet,
                    builder: (context, _) {
                      final inUse = <String, int>{};
                      for (final r in fleet.snapshot.rows) {
                        final ids = r.instances.map((i) => i.sheetId).whereType<String>().toSet();
                        for (final id in ids) {
                          inUse[id] = (inUse[id] ?? 0) + 1;
                        }
                      }
                      if (sheets.isEmpty) return const EmptyHint('还没有飞行表。新建和编辑先在主控网页完成。');
                      return ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: sheets.length + 1,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, i) {
                          if (i == sheets.length) {
                            return const Text('新建、编辑飞行表暂时在主控网页完成。', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: C.muted));
                          }
                          final s = sheets[i];
                          return _SheetCard(sheet: s, wallets: _wallets, inUse: inUse[s.id] ?? 0, onApply: () => _apply(s));
                        },
                      );
                    },
                  ),
                ),
    );
  }
}

class _SheetCard extends StatelessWidget {
  const _SheetCard({required this.sheet, required this.wallets, required this.inUse, required this.onApply});
  final FlightSheet sheet;
  final Map<String, Wallet> wallets;
  final int inUse;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final coin = sheet.tasks.isEmpty ? '?' : (wallets[sheet.tasks.first.walletId]?.coin ?? '?');
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          DecoratedBox(
            decoration: BoxDecoration(color: const Color(0xFF2A2416), borderRadius: BorderRadius.circular(10)),
            child: SizedBox.square(dimension: 38, child: Center(child: Text(coin, style: mono.copyWith(color: C.rate, fontWeight: FontWeight.w700, fontSize: 11)))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(sheet.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text('v${sheet.version} · ${inUse == 0 ? '未使用' : '$inUse 台在用'}', style: const TextStyle(fontSize: 12, color: C.muted)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        for (final t in sheet.tasks) ...[
          _Line('实例', t.instance),
          _Line('钱包', wallets[t.walletId]?.name ?? '—'),
          _Line('矿池', t.pools.isEmpty ? '—' : t.pools.join('\n'), monospace: true),
          _Line('软件', '${t.minerName} ${t.minerVersion}${t.algorithm.isEmpty ? '' : ' · ${t.algorithm}'}'),
        ],
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: onApply, child: const Text('应用到矿机'))),
      ]),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.k, this.v, {this.monospace = false});
  final String k;
  final String v;
  final bool monospace;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 48, child: Text(k, style: const TextStyle(fontSize: 12, color: C.muted, height: 1.6))),
          Expanded(child: Text(v, style: (monospace ? mono : const TextStyle()).copyWith(fontSize: 12, height: 1.6))),
        ]),
      );
}

class _MachinePicker extends StatefulWidget {
  const _MachinePicker({required this.rows, required this.sheet});
  final List<FleetRow> rows;
  final FlightSheet sheet;
  @override
  State<_MachinePicker> createState() => _MachinePickerState();
}

class _MachinePickerState extends State<_MachinePicker> {
  final Set<String> _picked = {};

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 4),
            child: Row(children: [
              Expanded(child: Text('应用「${widget.sheet.name}」到', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
              TextButton(
                onPressed: () => setState(() => _picked.length == rows.length ? _picked.clear() : _picked.addAll(rows.map((r) => r.machine.id))),
                child: Text(_picked.length == rows.length ? '全不选' : '全选'),
              ),
            ]),
          ),
          Expanded(
            child: ListView.builder(
              itemExtent: 56,
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final r = rows[i];
                final on = _picked.contains(r.machine.id);
                final current = r.instances.isEmpty ? '未应用' : (r.instances.first.sheetName ?? '—');
                return CheckboxListTile(
                  value: on,
                  onChanged: (_) => setState(() => on ? _picked.remove(r.machine.id) : _picked.add(r.machine.id)),
                  title: Text(r.machine.name),
                  subtitle: Text('当前：$current', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: C.muted)),
                  activeColor: C.accent,
                  checkColor: C.onAccent,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _picked.isEmpty ? null : () => Navigator.pop(context, _picked.toList()),
                child: Text(_picked.isEmpty ? '选择矿机' : '应用到 ${_picked.length} 台（矿工会重启）'),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
