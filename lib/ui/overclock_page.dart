import 'package:flutter/material.dart';

import '../api/client.dart';
import '../api/forms.dart';
import '../api/models.dart';
import '../theme.dart';
import 'batch_sheet.dart';
import 'more_page.dart';
import 'widgets.dart';

const _kind = 'oc-profiles';

/// A saved overclock template (`catalog/oc-profiles`): its data is the GpuOcConfig itself.
class OcProfile {
  const OcProfile(this.id, this.name, this.config, this.revision);
  final String id;
  final String name;
  final Map<String, dynamic> config;
  final int? revision;
  factory OcProfile.fromJson(Map<String, dynamic> j) =>
      OcProfile(asStr(j['id']), asStr(j['name']), asMap(j['data']), asNum(j['revision'])?.toInt());
}

Future<List<OcProfile>> loadOcProfiles(Backend b) async =>
    asList(await b.getJson('/api/v1/catalog/$_kind')).map((p) => OcProfile.fromJson(asMap(p))).toList()
      ..sort((a, b) => naturalCompare(a.name, b.name));

/// Text controllers for every field, so typing never rebuilds more than the field itself.
class _OcForm {
  _OcForm() {
    for (final v in ocVendors) {
      for (final f in ocFields[v]!) {
        fields['$v.${f.key}'] = TextEditingController();
      }
    }
  }
  final fields = <String, TextEditingController>{};
  final runningDelay = TextEditingController();
  late final Listenable changes = Listenable.merge([...fields.values, runningDelay]);

  void load(Map<String, dynamic> config) {
    final t = OcText.fromConfig(config);
    for (final v in ocVendors) {
      for (final f in ocFields[v]!) {
        fields['$v.${f.key}']!.text = t.fields[v]![f.key] ?? '';
      }
    }
    runningDelay.text = t.runningDelay;
  }

  OcText get text {
    final t = OcText()..runningDelay = runningDelay.text;
    for (final v in ocVendors) {
      for (final f in ocFields[v]!) {
        final s = fields['$v.${f.key}']!.text;
        if (s.trim().isNotEmpty) t.fields[v]![f.key] = s;
      }
    }
    return t;
  }

  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    runningDelay.dispose();
  }
}

class _OcFields extends StatelessWidget {
  const _OcFields(this.form, this.vendors);
  final _OcForm form;
  final List<String> vendors;

  Widget _field(String v, OcField f) => FormText(
        form.fields['$v.${f.key}']!,
        f.unit.isEmpty ? f.label : '${f.label}（${f.unit}）',
        monospace: true,
        help: f.help,
        keyboard: const TextInputType.numberWithOptions(signed: true),
      );

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final v in vendors) ...[
          SectionLabel(ocVendorName[v]!),
          const SizedBox(height: 6),
          for (final f in ocFields[v]!.where((f) => !f.advanced)) _field(v, f),
          if (v == 'nvidia')
            FormText(form.runningDelay, '应用延迟（秒）', monospace: true, keyboard: TextInputType.number, help: '矿工启动后等这么久再应用（RUNNING_DELAY），留空立即应用'),
          if (ocFields[v]!.any((f) => f.advanced))
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('高级', style: TextStyle(fontSize: 14, color: C.text2)),
                children: [for (final f in ocFields[v]!.where((f) => f.advanced)) _field(v, f)],
              ),
            ),
        ],
        const Text('每张卡一个数，用空格分隔（HiveOS 写法）；只填一个数则所有卡相同；留空不修改。',
            style: TextStyle(fontSize: 12, color: C.muted, height: 1.5)),
      ]);
}

Future<String?> _askName(BuildContext context, String title, {String initial = ''}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: '模板名称')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消', style: TextStyle(color: C.text2))),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('保存')),
      ],
    ),
  ).whenComplete(c.dispose);
}

/// Per-machine overclock: the cards, what was applied last, and the form to apply or reset.
class OverclockPage extends StatefulWidget {
  const OverclockPage({super.key, required this.machineId});
  final String machineId;
  @override
  State<OverclockPage> createState() => _OverclockPageState();
}

class _OverclockPageState extends State<OverclockPage> {
  final _form = _OcForm();
  List<OcProfile> _profiles = const [];
  String? _profile;
  bool _loaded = false;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final row = AppScope.of(context).fleet.row(widget.machineId);
    final saved = row?.gpuOc ?? const {};
    _form.load(asMap(saved['config']));
    _profile = saved['profile_name'] as String?;
    loadOcProfiles(AppScope.of(context).backend).then((p) {
      if (mounted) setState(() => _profiles = p);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _form.dispose();
    super.dispose();
  }

  Map<String, dynamic>? _config() {
    try {
      return _form.text.toConfig();
    } on FormatException catch (e) {
      toast(context, e.message);
      return null;
    }
  }

  Future<void> _run(Map<String, dynamic> action, String done) async {
    final b = AppScope.of(context).backend;
    setState(() => _busy = true);
    try {
      await submitJob(b, [widget.machineId], action, includeController: true);
      if (mounted) toast(context, done, action: '查看', onAction: () => push(context, const JobsPage()));
    } catch (e) {
      if (mounted) toast(context, '提交失败：${errorText(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply(FleetRow row) async {
    final config = _config();
    if (config == null) return;
    if (config.isEmpty) return toast(context, '没有填写任何参数');
    final ok = await confirm(context, '应用超频到 ${row.machine.name}？',
        '参数会立即写入显卡，并在矿机重启后自动重新应用。不合适的数值可能导致不稳定，可随时「恢复默认」。', action: '应用');
    if (ok) await _run({'kind': 'gpu_oc', 'profile_name': _profile, 'config': config}, '已提交，结果稍后显示在本页');
  }

  Future<void> _reset(FleetRow row) async {
    final ok = await confirm(context, '恢复 ${row.machine.name} 的显卡默认频率？', '清除超频设置，显卡回到驱动默认值。', action: '恢复默认', danger: true);
    if (ok) await _run({'kind': 'gpu_oc_reset'}, '已提交恢复默认');
  }

  Future<void> _saveAs() async {
    final config = _config();
    if (config == null) return;
    final name = await _askName(context, '另存为超频模板', initial: _profile ?? '');
    if (name == null || name.isEmpty || !mounted) return;
    try {
      await AppScope.of(context).backend.send('POST', '/api/v1/catalog/$_kind', {'name': name, 'data': config});
      if (!mounted) return;
      final p = await loadOcProfiles(AppScope.of(context).backend);
      if (mounted) {
        setState(() {
          _profiles = p;
          _profile = name;
        });
        toast(context, '模板已保存');
      }
    } catch (e) {
      if (mounted) toast(context, '保存失败：${errorText(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final fleet = AppScope.of(context).fleet;
    return Scaffold(
      appBar: AppBar(title: const Text('超频')),
      body: ListenableBuilder(
        listenable: fleet,
        builder: (context, _) {
          final row = fleet.row(widget.machineId);
          if (row == null) return const EmptyHint('这台矿机已不存在');
          final byVendor = {
            for (final v in ocVendors)
              v: row.gpus.where((g) => asStr(g['vendor']).toLowerCase() == v).toList()
                ..sort((a, b) => naturalCompare(asStr(a['id']), asStr(b['id']))),
          };
          final present = ocVendors.where((v) => byVendor[v]!.isNotEmpty).toList();
          final vendors = present.isEmpty ? ocVendors : present;
          final saved = row.gpuOc;
          final results = asList(saved['results']).map(asMap).toList();
          final appliedAt = asNum(saved['applied_at']);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Panel(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Column(children: [
                  KeyValue('矿机', row.machine.name),
                  KeyValue('当前超频', appliedAt == null ? '未应用（驱动默认）' : asStr(saved['profile_name'], '自定义')),
                  if (appliedAt != null)
                    KeyValue('应用时间', DateTime.fromMillisecondsSinceEpoch((appliedAt * 1000).toInt()).toString().substring(0, 19)),
                ]),
              ),
              const SizedBox(height: 12),
              if (present.isEmpty) ...[
                const Notice('未采集到 NVIDIA / AMD 显卡。可以先编辑并保存参数；应用前请确认显卡驱动已加载。',
                    fg: C.infoText, bg: C.infoBg, border: Color(0xFF24435A), icon: Icons.info_outline),
                const SizedBox(height: 12),
              ],
              // Only the cards follow the typing ("将应用" preview), not the whole form.
              ListenableBuilder(
                listenable: _form.changes,
                builder: (context, _) {
                  final text = _form.text;
                  return Column(children: [
                    for (final v in present)
                      for (var i = 0; i < byVendor[v]!.length; i++) ...[
                        _GpuCard(
                          title: '${ocVendorName[v]} $i',
                          gpu: byVendor[v]![i],
                          planned: text.plannedFor(v, i),
                          result: results.where((r) => r['bus_id'] == byVendor[v]![i]['id']).firstOrNull,
                        ),
                        const SizedBox(height: 8),
                      ],
                  ]);
                },
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: DropdownButtonFormField<String>(
                  key: ValueKey('${_profiles.length}|$_profile'),
                  initialValue: _profiles.any((p) => p.name == _profile) ? _profile : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '从模板载入'),
                  hint: Text(_profiles.isEmpty ? '还没有模板' : '选择模板'),
                  items: [for (final p in _profiles) DropdownMenuItem(value: p.name, child: Text(p.name))],
                  onChanged: (name) {
                    final p = _profiles.where((p) => p.name == name).firstOrNull;
                    if (p == null) return;
                    setState(() {
                      _profile = p.name;
                      _form.load(p.config);
                    });
                  },
                ),
              ),
              _OcFields(_form, vendors),
              const SizedBox(height: 16),
              FilledButton(onPressed: _busy ? null : () => _apply(row), child: const Text('应用超频')),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: _busy ? null : _saveAs, child: const Text('另存为模板'))),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => _reset(row),
                    child: const Text('恢复默认', style: TextStyle(color: C.badText)),
                  ),
                ),
              ]),
            ],
          );
        },
      ),
    );
  }
}

class _GpuCard extends StatelessWidget {
  const _GpuCard({required this.title, required this.gpu, required this.planned, required this.result});
  final String title;
  final Map<String, dynamic> gpu;
  final String planned;
  final Map<String, dynamic>? result;

  String _n(String key, [String unit = '']) {
    final v = asNum(gpu[key]);
    return v == null ? '—' : '${v.round()}$unit';
  }

  @override
  Widget build(BuildContext context) {
    final r = result;
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(asStr(gpu['model'], asStr(gpu['name'])), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: C.muted)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          '${_n('temperature_c', '°C')} · 核心 ${_n('core_mhz')} / 显存 ${_n('mem_mhz', ' MHz')} · ${_n('power_w')} / ${_n('power_limit_w', ' W')} · 风扇 ${_n('fan_pct', '%')}',
          style: mono.copyWith(fontSize: 12, color: C.text2),
        ),
        const SizedBox(height: 4),
        Text('将应用：${planned.isEmpty ? '不修改' : planned}', style: const TextStyle(fontSize: 12, color: C.muted)),
        if (r != null) ...[
          const SizedBox(height: 6),
          Wrap(spacing: 4, runSpacing: 4, children: [
            for (final s in asList(r['applied'])) Tag('$s', fg: C.okText, bg: C.okBg),
            for (final s in asList(r['errors'])) Tag('$s', fg: C.badText, bg: C.badBg),
            for (final s in asList(r['skipped'])) Tag('$s', fg: C.poolText, bg: C.poolBg),
          ]),
        ],
      ]),
    );
  }
}

/// The template library: create, edit, delete, and apply a template to many machines at once.
class OcProfilesPage extends StatefulWidget {
  const OcProfilesPage({super.key});
  @override
  State<OcProfilesPage> createState() => _OcProfilesPageState();
}

class _OcProfilesPageState extends State<OcProfilesPage> {
  List<OcProfile>? _profiles;
  Object? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_profiles == null && _error == null) _load();
  }

  Future<void> _load() async {
    try {
      final p = await loadOcProfiles(AppScope.of(context).backend);
      if (mounted) {
        setState(() {
          _profiles = p;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _edit([OcProfile? p]) async {
    if (await push<bool>(context, OcProfileEditPage(profile: p)) == true) await _load();
  }

  Future<void> _applyMany(OcProfile p) async {
    final scope = AppScope.of(context);
    final rows = scope.fleet.snapshot.rows;
    final ids = await pickMachines(context, rows, title: '应用「${p.name}」到', action: (n) => '应用超频到 $n 台');
    if (ids == null || ids.isEmpty || !mounted) return;
    try {
      await submitJob(scope.backend, ids, {'kind': 'gpu_oc', 'profile_name': p.name, 'config': p.config}, includeController: true);
      if (mounted) toast(context, '已提交：应用「${p.name}」· ${ids.length} 台', action: '查看', onAction: () => push(context, const JobsPage()));
    } catch (e) {
      if (mounted) toast(context, '提交失败：${errorText(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final profiles = _profiles;
    return Scaffold(
      appBar: AppBar(
        title: const Text('超频模板'),
        actions: [IconButton(tooltip: '新建模板', onPressed: _edit, icon: const Icon(Icons.add))],
      ),
      body: _error != null && profiles == null
          ? EmptyHint('读取模板失败：${errorText(_error!)}')
          : profiles == null
              ? const Center(child: CircularProgressIndicator())
              : profiles.isEmpty
                  ? const EmptyHint('还没有超频模板。点右上角 ＋ 新建，或在矿机的「超频」里另存为模板。')
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: profiles.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final p = profiles[i];
                        final vendors = ocVendors.where((v) => p.config[v] is Map).map((v) => ocVendorName[v]).join(' + ');
                        final text = OcText.fromConfig(p.config);
                        return Panel(
                          onTap: () => _edit(p),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                              Text(vendors.isEmpty ? '空' : vendors, style: const TextStyle(fontSize: 12, color: C.muted)),
                            ]),
                            const SizedBox(height: 4),
                            Text(
                              [for (final v in ocVendors) if (text.plannedFor(v, 0).isNotEmpty) text.plannedFor(v, 0)].join('\n'),
                              style: mono.copyWith(fontSize: 12, color: C.text2),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(onPressed: () => _applyMany(p), child: const Text('应用到矿机')),
                            ),
                          ]),
                        );
                      },
                    ),
    );
  }
}

class OcProfileEditPage extends StatefulWidget {
  const OcProfileEditPage({super.key, this.profile});
  final OcProfile? profile;
  @override
  State<OcProfileEditPage> createState() => _OcProfileEditPageState();
}

class _OcProfileEditPageState extends State<OcProfileEditPage> {
  late final _name = TextEditingController(text: widget.profile?.name);
  final _form = _OcForm();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _form.load(widget.profile?.config ?? const {});
  }

  @override
  void dispose() {
    _name.dispose();
    _form.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return toast(context, '请填写模板名称');
    final Map<String, dynamic> config;
    try {
      config = _form.text.toConfig();
    } on FormatException catch (e) {
      return toast(context, e.message);
    }
    final p = widget.profile;
    final b = AppScope.of(context).backend;
    setState(() => _busy = true);
    try {
      final body = {'name': _name.text.trim(), 'data': config, 'expected_revision': p?.revision};
      if (p == null) {
        await b.send('POST', '/api/v1/catalog/$_kind', body);
      } else {
        await b.send('PUT', '/api/v1/catalog/$_kind/${p.id}', body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) toast(context, '保存失败：${errorText(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final p = widget.profile!;
    if (!await confirm(context, '删除模板「${p.name}」？', '已经应用到矿机上的参数不受影响。', action: '删除', danger: true)) return;
    if (!mounted) return;
    try {
      await AppScope.of(context).backend.send('DELETE', '/api/v1/catalog/$_kind/${p.id}');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) toast(context, '删除失败：${errorText(e)}');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.profile == null ? '新建超频模板' : '编辑超频模板'),
          actions: [
            if (widget.profile != null)
              IconButton(tooltip: '删除模板', onPressed: _busy ? null : _delete, icon: const Icon(Icons.delete_outline, color: C.badText)),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FormText(_name, '模板名称', hint: '3070 低功耗'),
            _OcFields(_form, ocVendors),
            const SizedBox(height: 16),
            FilledButton(onPressed: _busy ? null : _save, child: const Text('保存')),
          ],
        ),
      );
}
