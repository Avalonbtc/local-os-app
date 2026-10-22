import 'dart:async';

import 'package:flutter/material.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../theme.dart';
import 'widgets.dart';

class _Setting {
  _Setting(Map<String, dynamic> j)
      : id = asStr(j['id']),
        name = asStr(j['name'], asStr(j['id'])),
        group = asStr(j['group']),
        value = '${j['value'] ?? ''}',
        kind = asStr(j['kind']),
        options = asList(j['options']).map((o) => '$o').toList(),
        minimum = j['minimum'],
        maximum = j['maximum'],
        help = asStr(j['help']),
        condition = asStr(j['condition']),
        license = asStr(j['license']),
        search = '${asStr(j['name'])} ${asStr(j['group'])} ${asStr(j['help'])}'.toLowerCase();
  final String id;
  final String name;
  final String group;
  final String value;
  final String kind;
  final List<String> options;
  final Object? minimum;
  final Object? maximum;
  final String help;
  final String condition;
  final String license;
  final String search;
}

const _finished = {'succeeded', 'failed', 'cancelled', 'unknown', 'blocked', 'skipped'};

/// Read and change BIOS settings through the BMC (Supermicro SUM), like the web console:
/// writes only the changed settings, keeps a backup, never reboots by itself.
class BiosPage extends StatefulWidget {
  const BiosPage({super.key, required this.machine});
  final Machine machine;
  @override
  State<BiosPage> createState() => _BiosPageState();
}

class _BiosPageState extends State<BiosPage> {
  List<_Setting>? _settings;
  Map<String, dynamic> _snapshot = const {};
  Object? _error;
  final _edits = <String, String>{};
  final _search = TextEditingController();
  String? _group;
  bool _busy = false;
  Job? _job;
  Timer? _poll;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_settings == null && _error == null) _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final snap = asMap(await AppScope.of(context).backend.getJson('/api/v1/machines/${widget.machine.id}/bios'));
      if (!mounted) return;
      setState(() {
        _snapshot = snap;
        _settings = asList(snap['settings']).map((s) => _Setting(asMap(s))).toList(growable: false);
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Map<String, dynamic> get _pending => asMap(_snapshot['pending']);
  bool get _running => _job != null && !_finished.contains(_job!.status);
  bool get _locked => _busy || _running || _pending.isNotEmpty;
  List<_Setting> get _changes => [
        for (final s in _settings ?? const <_Setting>[])
          if (_edits[s.id] != null && _edits[s.id] != s.value) s,
      ];

  Future<void> _submit(Map<String, dynamic> action) async {
    final b = AppScope.of(context).backend;
    setState(() => _busy = true);
    try {
      final id = await submitJob(b, [widget.machine.id], action, includeController: true);
      _follow(id);
    } catch (e) {
      if (mounted) toast(context, '提交失败：${errorText(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _follow(String jobId) {
    _poll?.cancel();
    Future<void> tick() async {
      try {
        final job = Job.fromJson(asMap(await AppScope.of(context).backend.getJson('/api/v1/jobs/$jobId')));
        if (!mounted) return;
        setState(() => _job = job);
        if (_finished.contains(job.status)) {
          if (job.status == 'succeeded') _edits.clear();
          await _load();
          return;
        }
      } catch (_) {
        if (!mounted) return;
      }
      _poll = Timer(const Duration(seconds: 2), tick);
    }

    tick();
  }

  Future<void> _write() async {
    final changes = _changes;
    final revision = _snapshot['revision'];
    if (changes.isEmpty || revision == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('确认修改 ${widget.machine.name} 的 BIOS'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('只提交以下修改，原配置会保留为备份。不会自动重启；NPS、功耗等设置需重启后生效。', style: TextStyle(height: 1.5, fontSize: 13)),
            for (final s in changes) ...[
              const SizedBox(height: 10),
              Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(s.group, style: const TextStyle(fontSize: 12, color: C.muted)),
              Text('${s.value} → ${_edits[s.id]}', style: mono.copyWith(fontSize: 12, color: C.rate)),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消', style: TextStyle(color: C.text2))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存，不重启')),
        ],
      ),
    );
    if (ok == true && mounted) {
      await _submit({'kind': 'bios_write', 'revision': revision, 'changes': {for (final s in changes) s.id: _edits[s.id]}});
    }
  }

  Future<void> _edit(_Setting s) async {
    if (_locked) return;
    final current = _edits[s.id] ?? s.value;
    String? next;
    if (s.options.isNotEmpty) {
      next = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
            child: ListView(shrinkWrap: true, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(s.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              for (final o in s.options)
                ListTile(
                  title: Text(o),
                  trailing: o == current ? const Icon(Icons.check, color: C.accent) : null,
                  subtitle: o == s.value ? const Text('当前回读值', style: TextStyle(fontSize: 12, color: C.muted)) : null,
                  onTap: () => Navigator.pop(ctx, o),
                ),
            ]),
          ),
        ),
      );
    } else {
      final c = TextEditingController(text: current);
      next = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(s.name),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: c,
              autofocus: true,
              style: mono,
              keyboardType: s.kind == 'Numeric' ? const TextInputType.numberWithOptions(signed: true) : null,
              decoration: InputDecoration(
                labelText: '修改值',
                helperText: s.kind == 'Numeric' ? 'BIOS 范围：${s.minimum ?? '—'}～${s.maximum ?? '—'}' : null,
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消', style: TextStyle(color: C.text2))),
            FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('确定')),
          ],
        ),
      );
      c.dispose();
    }
    if (next == null || !mounted) return;
    setState(() => next == s.value ? _edits.remove(s.id) : _edits[s.id] = next!);
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final changes = _changes;
    final pending = _pending;
    final query = _search.text.trim().toLowerCase();
    final shown = settings == null
        ? const <_Setting>[]
        : [
            for (final s in settings)
              if ((_group == null || s.group == _group) && (query.isEmpty || s.search.contains(query))) s,
          ];
    final groups = settings == null ? const <String>[] : ({for (final s in settings) s.group}.toList()..sort());
    final observed = DateTime.tryParse(asStr(_snapshot['observed_at']))?.toLocal();
    final job = _job;
    return Scaffold(
      appBar: AppBar(title: Text('BIOS · ${widget.machine.name}')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy || _running || changes.isNotEmpty ? null : () => _submit({'kind': 'bios_read', 'discard_pending': false}),
                child: Text(_running ? '进行中…' : '读取 BIOS'),
              ),
            ),
            if (changes.isNotEmpty) ...[
              const SizedBox(width: 8),
              OutlinedButton(onPressed: _locked ? null : () => setState(_edits.clear), child: const Text('放弃')),
            ],
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: changes.isEmpty || _locked ? null : _write,
                child: Text('保存（${changes.length}）'),
              ),
            ),
          ]),
        ),
      ),
      body: _error != null && settings == null
          ? ListView(children: [
              EmptyHint('读取 BIOS 失败：${errorText(_error!)}', icon: Icons.memory),
              Center(child: TextButton(onPressed: _load, child: const Text('重试'))),
            ])
          : settings == null
              ? const Center(child: CircularProgressIndicator())
              : CustomScrollView(slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    sliver: SliverList.list(children: [
                      Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        for (final l in asList(_snapshot['licenses'])) Tag('$l', fg: C.okText, bg: C.okBg),
                        Text(observed == null ? '尚未读取' : '读取于 ${observed.toString().substring(0, 19)}', style: const TextStyle(fontSize: 12, color: C.muted)),
                      ]),
                      const SizedBox(height: 10),
                      if (job != null) ...[
                        Notice(
                          [
                            _running ? 'SUM 操作进行中…' : job.status == 'succeeded' ? '任务完成' : '任务状态：${job.status}',
                            for (final t in job.targets)
                              if ((t.error ?? t.output).isNotEmpty) t.error ?? t.output,
                          ].join('\n'),
                          fg: job.status == 'failed' || job.status == 'unknown' ? C.badText : _running ? C.infoText : C.okText,
                          bg: job.status == 'failed' || job.status == 'unknown' ? C.badBg : _running ? C.infoBg : C.okBg,
                          border: C.border,
                          icon: _running ? Icons.hourglass_top_rounded : Icons.info_outline,
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (pending.isNotEmpty) ...[
                        Notice([
                          '有待生效或待核实的修改：',
                          for (final e in pending.entries)
                            '${settings.where((s) => s.id == e.key).firstOrNull?.name ?? e.key} → ${e.value}',
                          '安排重启后点「读取 BIOS」验证；回读未匹配前不会标记为已生效。如果已经重启、固件仍保持原值，可以清除标记后重新修改。',
                        ].join('\n')),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _busy || _running
                                ? null
                                : () async {
                                    if (await confirm(context, '清除待生效标记？', '会重新读取 BIOS，并把当前回读值当作最终结果。只在机器已重启后使用。', action: '读取并清除')) {
                                      await _submit({'kind': 'bios_read', 'discard_pending': true});
                                    }
                                  },
                            child: const Text('已重启，清除标记'),
                          ),
                        ),
                      ],
                      if (settings.isEmpty)
                        const EmptyHint('点下方「读取 BIOS」获取真实配置，通常需要十几秒', icon: Icons.memory)
                      else ...[
                        TextField(
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: '搜索 NPS、NUMA、cTDP、Power…'),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 36,
                          child: ListView(scrollDirection: Axis.horizontal, children: [
                            for (final g in [null, ...groups])
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                  label: Text(g ?? '全部 ${settings.length}'),
                                  selected: _group == g,
                                  onSelected: (_) => setState(() => _group = g),
                                ),
                              ),
                          ]),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ]),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    sliver: SliverList.separated(
                      itemCount: shown.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final s = shown[i];
                        final edited = _edits[s.id];
                        final p = pending[s.id];
                        return Panel(
                          onTap: _locked ? null : () => _edit(s),
                          borderColor: edited != null ? C.accent : null,
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text(s.group, style: const TextStyle(fontSize: 11, color: C.muted)),
                            const SizedBox(height: 6),
                            Row(children: [
                              Expanded(
                                child: Text.rich(TextSpan(children: [
                                  TextSpan(text: s.value, style: TextStyle(decoration: edited != null ? TextDecoration.lineThrough : null, color: edited != null ? C.muted : C.text)),
                                  if (edited != null) TextSpan(text: '  →  $edited', style: const TextStyle(color: C.rate, fontWeight: FontWeight.w600)),
                                ]), style: mono.copyWith(fontSize: 13)),
                              ),
                              if (p != null) Tag('待验证：$p', fg: C.poolText, bg: C.poolBg),
                            ]),
                            if (s.help.isNotEmpty || s.condition.isNotEmpty || s.license.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                [s.help, if (s.condition.isNotEmpty) '生效条件：${s.condition}', if (s.license.isNotEmpty) '授权：${s.license}'].where((t) => t.isNotEmpty).join('\n'),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, color: C.muted, height: 1.4),
                              ),
                            ],
                          ]),
                        );
                      },
                    ),
                  ),
                ]),
    );
  }
}
