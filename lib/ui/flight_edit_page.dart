import 'package:flutter/material.dart';

import '../api/client.dart';
import '../api/forms.dart';
import '../api/models.dart';
import '../theme.dart';
import 'more_page.dart';
import 'widgets.dart';

const _custom = 'custom';
const _newWallet = '__new__';

/// One miner of the sheet as the form holds it. Unknown miner/config keys are kept as stored.
class _Task {
  _Task(Map<String, dynamic> raw, List<MinerAdapter> adapters)
      : miner = Map.of(asMap(raw['miner'])),
        config = Map.of(asMap(raw['config'])),
        walletId = raw['wallet_id'] as String?,
        instance = TextEditingController(text: asStr(raw['instance'])) {
    final c = config;
    urls.text = asList(c['urls']).join('\n');
    algorithm.text = asStr(c['algorithm']);
    template.text = asStr(c['wallet_template'], '%WAL%.%WORKER_NAME%');
    password.text = asStr(c['password'], 'x');
    threads.text = c['threads'] == null ? '' : '${c['threads']}';
    cpus.text = asList(c['cpus']).join(',');
    extra.text = asList(c['extra_args']).join(' ');
    userConfig.text = asStr(c['user_config']);
    final adapter = asStr(miner['adapter']);
    if (adapter == customAdapter) {
      choice = _custom;
      customName.text = asStr(miner['custom_name'], asStr(miner['name']));
      customUrl.text = asStr(miner['url']);
      customVersion.text = asStr(miner['version']);
      customSha.text = asStr(miner['sha256']);
    } else if (adapter.isNotEmpty) {
      choice = adapter;
    }
  }

  final Map<String, dynamic> miner;
  final Map<String, dynamic> config;
  String? walletId;
  String? choice;
  final TextEditingController instance;
  final urls = TextEditingController();
  final algorithm = TextEditingController();
  final template = TextEditingController();
  final password = TextEditingController();
  final threads = TextEditingController();
  final cpus = TextEditingController();
  final extra = TextEditingController();
  final userConfig = TextEditingController();
  final customName = TextEditingController();
  final customUrl = TextEditingController();
  final customVersion = TextEditingController();
  final customSha = TextEditingController();

  List<TextEditingController> get _all => [
        instance, urls, algorithm, template, password, threads, cpus, extra, userConfig,
        customName, customUrl, customVersion, customSha,
      ];
  void dispose() {
    for (final c in _all) {
      c.dispose();
    }
  }

  void pickAdapter(MinerAdapter? a) {
    if (a == null) {
      choice = _custom;
      return;
    }
    choice = a.id;
    miner
      ..clear()
      ..addAll(minerSpec(a));
    if (algorithm.text.isEmpty) algorithm.text = defaultAlgorithm[a.id] ?? '';
  }

  void pickRelease(MinerAdapter a, MinerRelease r) => miner
    ..clear()
    ..addAll(minerSpec(a, r));

  List<String> _lines(String s) => s.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

  /// The stored task; throws [FormatException] with a message for the user.
  Map<String, dynamic> toJson(int n) {
    final name = instance.text.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(name)) throw FormatException('第 $n 个挖矿软件：实例名只能用字母、数字、- 和 _');
    if (walletId == null) throw FormatException('第 $n 个挖矿软件：请选择钱包');
    final custom = choice == _custom;
    final Map<String, dynamic> m;
    if (custom) {
      final url = customUrl.text.trim();
      final label = customName.text.trim().isEmpty ? inferMinerName(url) : customName.text.trim();
      if (url.isEmpty || label.isEmpty) throw FormatException('第 $n 个挖矿软件：请填写自定义包的下载地址和名称');
      m = {
        // Same package: keep what it declared (e.g. its own stats port for multi-instance).
        if (miner['capabilities'] != null && miner['url'] == url) 'capabilities': miner['capabilities'],
        'adapter': customAdapter,
        'name': label,
        'custom_name': label,
        'url': url,
        'version': customVersion.text.trim(),
        if (customSha.text.trim().isNotEmpty) 'sha256': customSha.text.trim(),
      };
    } else {
      if (choice == null || asStr(miner['url']).isEmpty) throw FormatException('第 $n 个挖矿软件：请选择挖矿软件和版本');
      m = miner;
    }
    final c = Map<String, dynamic>.of(config)
      ..['algorithm'] = algorithm.text.trim()
      ..['wallet_template'] = template.text.trim()
      ..['password'] = password.text
      ..['urls'] = _lines(urls.text);
    if (custom) {
      c['user_config'] = userConfig.text;
    } else {
      if (algorithm.text.trim().isEmpty) throw FormatException('第 $n 个挖矿软件：缺少算法');
      if ((c['urls'] as List).isEmpty) throw FormatException('第 $n 个挖矿软件：缺少矿池地址');
      final t = threads.text.trim();
      if (t.isEmpty) {
        c.remove('threads');
      } else {
        final v = int.tryParse(t);
        if (v == null || v < 1) throw FormatException('第 $n 个挖矿软件：线程数应为正整数');
        c['threads'] = v;
      }
      final cpuText = cpus.text.trim();
      c['cpus'] = cpuText.isEmpty
          ? <int>[]
          : [
              for (final s in cpuText.split(RegExp(r'[,，]')))
                int.tryParse(s.trim()) != null && int.parse(s.trim()) >= 0
                    ? int.parse(s.trim())
                    : throw FormatException('第 $n 个挖矿软件：CPU 编号应为非负整数，用逗号分隔'),
            ];
      c['extra_args'] = extra.text.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    }
    return {'instance': name, 'wallet_id': walletId, 'miner': m, 'config': c};
  }
}

/// Create a flight sheet, or edit / delete one ([sheet]). Pops `true` when something changed.
class FlightEditPage extends StatefulWidget {
  const FlightEditPage({super.key, this.sheet});
  final FlightSheet? sheet;
  @override
  State<FlightEditPage> createState() => _FlightEditPageState();
}

class _FlightEditPageState extends State<FlightEditPage> {
  late final _name = TextEditingController(text: widget.sheet?.name ?? '');
  List<MinerAdapter>? _adapters;
  List<Wallet> _wallets = const [];
  List<_Task> _tasks = const [];
  Object? _error;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_adapters == null && _error == null) _load();
  }

  @override
  void dispose() {
    _name.dispose();
    for (final t in _tasks) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final b = AppScope.of(context).backend;
    try {
      final r = await Future.wait([b.getJson('/api/v1/adapters'), b.getJson('/api/v1/catalog/wallets')]);
      if (!mounted) return;
      final adapters = [
        for (final a in asList(r[0]).map((a) => MinerAdapter.fromJson(asMap(a))))
          if (a.id != customAdapter) a,
      ];
      final wallets = asList(r[1]).map((w) => Wallet.fromJson(asMap(w))).toList();
      final raw = widget.sheet?.rawTasks ?? const [];
      setState(() {
        _adapters = adapters;
        _wallets = wallets;
        _tasks = raw.isEmpty ? [_blank(1, adapters, wallets)] : [for (final t in raw) _Task(t, adapters)];
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  _Task _blank(int n, List<MinerAdapter> adapters, List<Wallet> wallets) {
    final t = _Task({'instance': 'cpu-$n', 'wallet_id': wallets.length == 1 ? wallets.first.id : null}, adapters);
    final xmrig = adapters.where((a) => a.id == 'xmrig').firstOrNull ?? adapters.firstOrNull;
    if (xmrig != null) t.pickAdapter(xmrig);
    return t;
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return toast(context, '请填写飞行表名称');
    final List<Map<String, dynamic>> tasks;
    try {
      tasks = [for (var i = 0; i < _tasks.length; i++) _tasks[i].toJson(i + 1)];
    } on FormatException catch (e) {
      return toast(context, e.message);
    }
    final names = tasks.map((t) => t['instance']).toSet();
    if (names.length != tasks.length) return toast(context, '实例名不能重复');
    final b = AppScope.of(context).backend;
    final sheet = widget.sheet;
    setState(() => _busy = true);
    try {
      final body = {'name': name, 'tasks': tasks, 'expected_version': sheet?.version};
      final saved = asMap(sheet == null
          ? await b.send('POST', '/api/v1/flight-sheets', body)
          : await b.send('PUT', '/api/v1/flight-sheets/${sheet.id}', body));
      if (!mounted) return;
      Navigator.pop(context, true);
      toast(context, saved['apply_job_id'] is String ? '已保存，正在更新使用这张飞行表的矿机' : '已保存',
          action: saved['apply_job_id'] is String ? '查看' : null, onAction: () => push(context, const JobsPage()));
    } catch (e) {
      if (!mounted) return;
      final conflict = e is ApiException && e.status == 409;
      toast(context, conflict ? '飞行表已被别人修改，请返回刷新后重新编辑' : '保存失败：${errorText(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final s = widget.sheet!;
    if (!await confirm(context, '删除「${s.name}」？', '正在使用它的矿机不会停止挖矿，但之后不能再按它更新。', action: '删除', danger: true)) return;
    if (!mounted) return;
    try {
      await AppScope.of(context).backend.send('DELETE', '/api/v1/flight-sheets/${s.id}');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) toast(context, '删除失败：${errorText(e)}');
    }
  }

  Future<void> _pickWallet(_Task t, String? id) async {
    if (id != _newWallet) return setState(() => t.walletId = id);
    final created = await editWallet(context);
    if (created == null || !mounted) return;
    setState(() {
      _wallets = [..._wallets, created];
      t.walletId = created.id;
    });
  }

  @override
  Widget build(BuildContext context) {
    final adapters = _adapters;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.sheet == null ? '新建飞行表' : '编辑飞行表'),
        actions: [
          if (widget.sheet != null)
            IconButton(tooltip: '删除飞行表', onPressed: _busy ? null : _delete, icon: const Icon(Icons.delete_outline, color: C.badText)),
        ],
      ),
      body: _error != null
          ? EmptyHint('读取挖矿软件或钱包失败：${errorText(_error!)}', icon: Icons.cloud_off_outlined)
          : adapters == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    FormText(_name, '飞行表名称', hint: 'XMR · 自建代理'),
                    for (var i = 0; i < _tasks.length; i++) ...[
                      _TaskCard(
                        index: i,
                        task: _tasks[i],
                        adapters: adapters,
                        wallets: _wallets,
                        onChanged: () => setState(() {}),
                        onWallet: (id) => _pickWallet(_tasks[i], id),
                        onRemove: _tasks.length == 1
                            ? null
                            : () => setState(() {
                                  _tasks.removeAt(i).dispose();
                                  _tasks = List.of(_tasks);
                                }),
                      ),
                      const SizedBox(height: 12),
                    ],
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _tasks = [..._tasks, _blank(_tasks.length + 1, adapters, _wallets)]),
                      icon: const Icon(Icons.add),
                      label: const Text('再加一个挖矿软件'),
                    ),
                    const SizedBox(height: 12),
                    if (widget.sheet != null) ...[
                      const Text('保存后，正在使用这张飞行表的矿机会自动更新并重启矿工。', style: TextStyle(fontSize: 12, color: C.muted, height: 1.5)),
                      const SizedBox(height: 8),
                    ],
                    FilledButton(
                      onPressed: _busy ? null : _save,
                      child: _busy
                          ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('保存'),
                    ),
                  ],
                ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.index,
    required this.task,
    required this.adapters,
    required this.wallets,
    required this.onChanged,
    required this.onWallet,
    required this.onRemove,
  });
  final int index;
  final _Task task;
  final List<MinerAdapter> adapters;
  final List<Wallet> wallets;
  final VoidCallback onChanged;
  final ValueChanged<String?> onWallet;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final t = task;
    final adapter = adapters.where((a) => a.id == t.choice).firstOrNull;
    final custom = t.choice == _custom;
    final version = asStr(t.miner['version']);
    final knownRelease = adapter?.releases.any((r) => r.version == version && r.url == t.miner['url']) ?? false;
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('挖矿软件 ${index + 1}', style: const TextStyle(fontWeight: FontWeight.w600))),
          if (onRemove != null)
            IconButton(tooltip: '移除', onPressed: onRemove, icon: const Icon(Icons.close, size: 20, color: C.muted)),
        ]),
        const SizedBox(height: 8),
        FormText(t.instance, '实例名', monospace: true, help: '同一台矿机上区分多个矿工，如 cpu-1'),
        _Dropdown<String>(
          label: '钱包',
          value: wallets.any((w) => w.id == t.walletId) ? t.walletId : null,
          items: {
            for (final w in wallets) w.id: '${w.coin} · ${w.name}',
            _newWallet: '＋ 新建钱包',
          },
          onChanged: onWallet,
        ),
        _Dropdown<String>(
          label: '挖矿软件',
          value: t.choice,
          items: {for (final a in adapters) a.id: a.name, _custom: '自定义（HiveOS 包地址）'},
          onChanged: (v) {
            t.pickAdapter(adapters.where((a) => a.id == v).firstOrNull);
            onChanged();
          },
        ),
        if (adapter != null && adapter.releases.isNotEmpty)
          _Dropdown<String>(
            label: '版本',
            value: knownRelease ? version : '__current__',
            items: {
              if (!knownRelease) '__current__': '当前 ${version.isEmpty ? '—' : version}（自定义下载地址）',
              for (final r in adapter.releases) r.version: r.version,
            },
            onChanged: (v) {
              final r = adapter.releases.where((r) => r.version == v).firstOrNull;
              if (r != null) t.pickRelease(adapter, r);
              onChanged();
            },
          ),
        if (custom) ...[
          FormText(t.customUrl, '安装包下载地址', monospace: true, keyboard: TextInputType.url,
              hint: 'https://…/miner-1.0.tar.gz', onChanged: (v) {
            if (t.customName.text.isEmpty) t.customName.text = inferMinerName(v.trim());
          }),
          FormText(t.customName, '挖矿软件名称'),
          FormText(t.customVersion, '版本（可选，仅显示用）'),
          FormText(t.customSha, 'SHA-256（可选）', monospace: true),
        ],
        FormText(
          t.algorithm,
          custom ? '加密算法（可选）' : '加密算法',
          monospace: true,
          suffix: PopupMenuButton<String>(
            tooltip: '常用算法',
            icon: const Icon(Icons.arrow_drop_down),
            onSelected: (v) {
              t.algorithm.text = v;
              onChanged();
            },
            itemBuilder: (_) => [for (final a in algorithms) PopupMenuItem(value: a, child: Text(a, style: mono))],
          ),
        ),
        FormText(t.urls, '矿池地址', monospace: true, lines: 2, keyboard: TextInputType.url,
            hint: 'stratum+tcp://pool:port', help: '每行一个，第一个优先，其余备用'),
        FormText(t.template, '钱包与矿机模板', monospace: true, help: '支持 %WAL%、%WORKER_NAME%、%COIN% 等变量'),
        FormText(t.password, '矿池密码', monospace: true),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: const Text('高级', style: TextStyle(fontSize: 14, color: C.text2)),
            children: custom
                ? [FormText(t.userConfig, '其他配置参数', monospace: true, lines: 3, help: '传给 HiveOS 自定义包的配置参数')]
                : [
                    FormText(t.threads, '线程数（可选）', keyboard: TextInputType.number, help: '留空由挖矿软件自动决定'),
                    FormText(t.cpus, 'CPU 编号（可选）', monospace: true, hint: '0,1,2,3', help: '绑定到这些逻辑 CPU，逗号分隔'),
                    FormText(t.extra, '额外参数（可选）', monospace: true, hint: '--huge-pages-jit'),
                  ],
          ),
        ),
      ]),
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({required this.label, required this.value, required this.items, required this.onChanged});
  final String label;
  final T? value;
  final Map<T, String> items;
  final ValueChanged<T?> onChanged;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<T>(
          initialValue: value,
          key: ValueKey(value),
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            for (final e in items.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: onChanged,
        ),
      );
}

/// Create (or edit, with [wallet]) a wallet in the controller's catalog.
Future<Wallet?> editWallet(BuildContext context, {Wallet? wallet}) {
  return showDialog<Wallet>(context: context, builder: (_) => _WalletDialog(wallet: wallet, backend: AppScope.of(context).backend));
}

class _WalletDialog extends StatefulWidget {
  const _WalletDialog({required this.wallet, required this.backend});
  final Wallet? wallet;
  final Backend backend;
  @override
  State<_WalletDialog> createState() => _WalletDialogState();
}

class _WalletDialogState extends State<_WalletDialog> {
  late final _name = TextEditingController(text: widget.wallet?.name);
  late final _coin = TextEditingController(text: widget.wallet?.coin ?? 'XMR');
  late final _address = TextEditingController(text: widget.wallet?.address);
  late final _notes = TextEditingController(text: widget.wallet?.note);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _coin, _address, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final coin = _coin.text.trim().toUpperCase();
    if (_name.text.trim().isEmpty || coin.isEmpty || _address.text.trim().isEmpty) {
      return setState(() => _error = '名称、币种和地址都要填写');
    }
    final w = widget.wallet;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final body = {
        'name': _name.text.trim(),
        'data': {'coin_symbol': coin, 'address': _address.text.trim(), 'source': '', 'notes': _notes.text.trim()},
        'expected_revision': w?.revision,
      };
      final saved = w == null
          ? await widget.backend.send('POST', '/api/v1/catalog/wallets', body)
          : await widget.backend.send('PUT', '/api/v1/catalog/wallets/${w.id}', body);
      if (mounted) Navigator.pop(context, Wallet.fromJson(asMap(saved)));
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.wallet == null ? '新建钱包' : '编辑钱包'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            FormText(_name, '名称', hint: '主钱包'),
            FormText(_coin, '币种', hint: 'XMR、ZEPH…', help: '任意币种符号'),
            FormText(_address, '钱包地址', monospace: true, lines: 2),
            FormText(_notes, '备注（可选）'),
            if (_error != null) Text(_error!, style: const TextStyle(color: C.badText, fontSize: 13)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消', style: TextStyle(color: C.text2))),
          FilledButton(onPressed: _busy ? null : _save, child: const Text('保存')),
        ],
      );
}
