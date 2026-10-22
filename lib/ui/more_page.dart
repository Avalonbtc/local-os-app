import 'dart:async';

import 'package:flutter/material.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../theme.dart';
import '../util/format.dart';
import 'widgets.dart';

class MorePage extends StatelessWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final session = scope.session;
    Widget item(IconData icon, String label, VoidCallback onTap, {String? note, Color? color}) => ListTile(
          leading: DecoratedBox(
            decoration: BoxDecoration(color: const Color(0xFF262C33), borderRadius: BorderRadius.circular(8)),
            child: SizedBox.square(dimension: 32, child: Icon(icon, size: 18, color: color ?? C.rate)),
          ),
          title: Text(label, style: TextStyle(color: color)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (note != null) Text(note, style: const TextStyle(fontSize: 12, color: C.muted)),
            const Icon(Icons.chevron_right, color: C.faint),
          ]),
          onTap: onTap,
        );
    Widget group(List<Widget> children) => Panel(padding: EdgeInsets.zero, child: Column(children: children));
    return Scaffold(
      appBar: AppBar(title: const Text('更多')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Panel(
            child: Row(children: [
              CircleAvatar(
                backgroundColor: C.accent,
                foregroundColor: C.onAccent,
                child: Text(session.user.isEmpty ? '?' : session.user.characters.first, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(session.user, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(session.server, maxLines: 1, overflow: TextOverflow.ellipsis, style: mono.copyWith(fontSize: 12, color: C.muted)),
                ]),
              ),
            ]),
          ),
          const SectionLabel('矿场'),
          group([
            item(Icons.task_alt_rounded, '任务', () => push(context, const JobsPage())),
            item(Icons.account_balance_wallet_outlined, '钱包', () => push(context, const WalletsPage())),
          ]),
          const SectionLabel('设置'),
          group([
            item(Icons.tune_rounded, '矿场设定与离线通知', () => push(context, const FarmSettingsPage())),
            item(Icons.key_outlined, '令牌与审计记录', () => push(context, const TokensPage())),
          ]),
          const SectionLabel('账户'),
          group([
            item(Icons.logout_rounded, session.demo ? '退出演示' : '退出登录', () async {
              if (!session.demo && !await confirm(context, '退出登录？', '退出后需要重新输入主控地址和密码（或令牌）。', action: '退出')) return;
              await session.logout();
            }, color: C.badText),
          ]),
          const SizedBox(height: 16),
          const Text(
            '超频、BIOS、终端、添加矿机和编辑飞行表暂时在主控网页完成。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: C.muted, height: 1.5),
          ),
        ],
      ),
    );
  }
}

const _jobKinds = {
  'apply': '应用飞行表',
  'miner': '矿工操作',
  'power': '电源操作',
  'command': '执行命令',
  'bootstrap': '部署运行层',
  'bios_read': '读取 BIOS',
  'bios_write': '写入 BIOS',
  'gpu_oc': '应用超频',
  'gpu_oc_reset': '恢复默认频率',
  'adopt': '接管矿工',
};

(String, Color, Color) jobStatus(String s) => switch (s) {
      'succeeded' => ('成功', C.okText, C.okBg),
      'queued' => ('排队', C.text2, C.greyBg),
      'running' => ('执行中', C.rate, const Color(0xFF2A2416)),
      'cancelled' => ('已取消', C.text2, C.greyBg),
      'unknown' => ('结果不明', C.infoText, C.infoBg),
      'failed' => ('失败', C.badText, C.badBg),
      'reconciling' => ('对账中', C.infoText, C.infoBg),
      'blocked' => ('被阻止', C.badText, C.badBg),
      'skipped' => ('已跳过', C.text2, C.greyBg),
      _ => (s, C.text2, C.greyBg),
    };

class JobsPage extends StatefulWidget {
  const JobsPage({super.key});
  @override
  State<JobsPage> createState() => _JobsPageState();
}

class _JobsPageState extends State<JobsPage> {
  List<Job>? _jobs;
  Object? _error;
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_jobs == null && _error == null) _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await AppScope.of(context).backend.getJson('/api/v1/jobs') as List;
      if (!mounted) return;
      final jobs = list.map((j) => Job.fromJson(asMap(j))).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      setState(() {
        _jobs = jobs;
        _error = null;
      });
      // Follow running jobs closely; stop polling once everything has settled.
      _timer?.cancel();
      if (jobs.any((j) => j.active)) _timer = Timer(const Duration(seconds: 3), _load);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final jobs = _jobs;
    return Scaffold(
      appBar: AppBar(title: const Text('任务')),
      body: _error != null && jobs == null
          ? EmptyHint('读取任务失败：${errorText(_error!)}')
          : jobs == null
              ? const Center(child: CircularProgressIndicator())
              : jobs.isEmpty
                  ? const EmptyHint('还没有任务')
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: jobs.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) => _JobCard(jobs[i], onChanged: _load),
                      ),
                    ),
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard(this.job, {required this.onChanged});
  final Job job;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final (label, fg, bg) = jobStatus(job.status);
    final total = job.targets.length;
    final done = job.targets.where((t) => !['queued', 'running', 'reconciling'].contains(t.status)).length;
    return Panel(
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _JobTargets(job),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(_jobKinds[job.kind] ?? job.kind, style: const TextStyle(fontWeight: FontWeight.w600))),
          Tag(label, fg: fg, bg: bg),
        ]),
        const SizedBox(height: 4),
        Text('${job.actor} · ${ago(job.createdAt)} · $total 台', style: const TextStyle(fontSize: 12, color: C.muted)),
        if (job.active) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: total == 0 ? null : done / total, minHeight: 6, backgroundColor: C.divider),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () async {
                if (!await confirm(context, '取消任务？', '已经开始执行的机器会尽量停下，已完成的不会回滚。', action: '取消任务', danger: true)) return;
                if (!context.mounted) return;
                try {
                  await AppScope.of(context).backend.send('POST', '/api/v1/jobs/${job.id}/cancel');
                  onChanged();
                } catch (e) {
                  if (context.mounted) toast(context, '取消失败：${errorText(e)}');
                }
              },
              child: const Text('取消', style: TextStyle(color: C.badText)),
            ),
          ),
        ],
      ]),
    );
  }
}

class _JobTargets extends StatelessWidget {
  const _JobTargets(this.job);
  final Job job;
  @override
  Widget build(BuildContext context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Text(_jobKinds[job.kind] ?? job.kind, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              for (final t in job.targets)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(t.machineName, style: const TextStyle(fontWeight: FontWeight.w600))),
                      Builder(builder: (_) {
                        final (l, fg, bg) = jobStatus(t.status);
                        return Tag(l, fg: fg, bg: bg);
                      }),
                    ]),
                    if ((t.error ?? '').isNotEmpty || t.output.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        t.error ?? t.output,
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis,
                        style: mono.copyWith(fontSize: 11, color: t.error == null ? C.muted : C.badText, height: 1.5),
                      ),
                    ],
                  ]),
                ),
            ],
          ),
        ),
      );
}

class FarmSettingsPage extends StatefulWidget {
  const FarmSettingsPage({super.key});
  @override
  State<FarmSettingsPage> createState() => _FarmSettingsPageState();
}

class _FarmSettingsPageState extends State<FarmSettingsPage> {
  Map<String, dynamic>? _settings;
  Object? _error;
  bool _saving = false;
  final _price = TextEditingController();
  final _local = TextEditingController();
  final _pool = TextEditingController();
  bool _poolCheck = true;
  bool _popup = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_settings == null && _error == null) _load();
  }

  @override
  void dispose() {
    _price.dispose();
    _local.dispose();
    _pool.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = asMap(await AppScope.of(context).backend.getJson('/api/v1/settings/farm'));
      if (!mounted) return;
      final a = asMap(s['alerts']);
      setState(() {
        _settings = s;
        _price.text = (asNum(s['electricity_price']) ?? 0.56).toString();
        _local.text = '${asNum(a['local_offline_minutes'])?.toInt() ?? 2}';
        _pool.text = '${asNum(a['pool_offline_minutes'])?.toInt() ?? 10}';
        _poolCheck = a['pool_check'] != false;
        _popup = a['popup'] != false;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _save() async {
    final price = double.tryParse(_price.text.trim());
    final local = int.tryParse(_local.text.trim());
    final pool = int.tryParse(_pool.text.trim());
    if (price == null || local == null || pool == null) {
      toast(context, '请填写数字');
      return;
    }
    final scope = AppScope.of(context);
    final current = _settings ?? const {};
    final alerts = Map<String, dynamic>.from(asMap(current['alerts']));
    alerts
      ..['local_offline_minutes'] = local
      ..['pool_offline_minutes'] = pool
      ..['pool_check'] = _poolCheck
      ..['popup'] = _popup;
    setState(() => _saving = true);
    try {
      // Proxies go back as read (no token): the controller keeps their stored tokens.
      final saved = asMap(await scope.backend.send('PUT', '/api/v1/settings/farm', {...current, 'electricity_price': price, 'alerts': alerts}));
      scope.fleet.setPrice(asNum(saved['electricity_price']) ?? price);
      if (mounted) {
        setState(() => _settings = saved);
        toast(context, '已保存');
      }
    } catch (e) {
      if (mounted) toast(context, '保存失败：${errorText(e)}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _settings;
    final proxies = asList(asMap(s?['alerts'])['proxies']).map(asMap).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('矿场设定'),
        actions: [
          TextButton(onPressed: s == null || _saving ? null : _save, child: const Text('保存', style: TextStyle(fontWeight: FontWeight.w700))),
        ],
      ),
      body: _error != null
          ? EmptyHint('读取设定失败：${errorText(_error!)}')
          : s == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const SectionLabel('矿场（所有设备共用）'),
                    Panel(
                      child: _NumberField(controller: _price, label: '电价', suffix: '元/度', help: '预估电费 = 当前功耗 × 24 小时 × 电价', decimal: true),
                    ),
                    const SectionLabel('离线判定与通知'),
                    Panel(
                      child: Column(children: [
                        _NumberField(controller: _local, label: '本地离线判定', suffix: '分钟', help: '超过这么久没有任何遥测（主动上报和 SSH 都没有）才算离线，范围 1–1440'),
                        const SizedBox(height: 14),
                        _NumberField(controller: _pool, label: '矿池离线判定', suffix: '分钟', help: '矿池持续这么久看不到算力才算矿池离线，范围 5–1440'),
                        const SizedBox(height: 6),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('矿池检测'),
                          subtitle: const Text('supportxmr、Kryptex、HashVault、Nanopool 和自建 xmrig-proxy', style: TextStyle(fontSize: 12, color: C.muted)),
                          value: _poolCheck,
                          onChanged: (v) => setState(() => _poolCheck = v),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('网页弹窗'),
                          subtitle: const Text('主控网页右下角的离线与恢复弹窗', style: TextStyle(fontSize: 12, color: C.muted)),
                          value: _popup,
                          onChanged: (v) => setState(() => _popup = v),
                        ),
                      ]),
                    ),
                    if (proxies.isNotEmpty) ...[
                      const SectionLabel('自建 xmrig-proxy（在主控网页编辑）'),
                      Panel(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        child: Column(children: [
                          for (final p in proxies)
                            KeyValue(asStr(p['pool']), '${asStr(p['api_url'])}${p['has_token'] == true ? ' · 令牌已保存' : ''}', valueStyle: mono.copyWith(fontSize: 12, color: C.text2)),
                        ]),
                      ),
                    ],
                    const SizedBox(height: 16),
                    const Text(
                      'App 内会在打开时提示新的离线与恢复通知。锁屏推送需要主控增加推送服务，下一版接入。',
                      style: TextStyle(fontSize: 12, color: C.muted, height: 1.5),
                    ),
                  ],
                ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({required this.controller, required this.label, required this.suffix, required this.help, this.decimal = false});
  final TextEditingController controller;
  final String label;
  final String suffix;
  final String help;
  final bool decimal;
  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        style: mono,
        decoration: InputDecoration(labelText: label, suffixText: suffix, helperText: help, helperMaxLines: 2),
      );
}

class WalletsPage extends StatelessWidget {
  const WalletsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final b = AppScope.of(context).backend;
    return Scaffold(
      appBar: AppBar(title: const Text('钱包')),
      body: FutureBuilder<dynamic>(
        future: b.getJson('/api/v1/catalog/wallets'),
        builder: (context, snap) {
          if (snap.hasError) return EmptyHint('读取钱包失败：${errorText(snap.error!)}');
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final wallets = (snap.data as List).map((w) => Wallet.fromJson(asMap(w))).toList();
          if (wallets.isEmpty) return const EmptyHint('还没有钱包，请先在主控网页添加');
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: wallets.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final w = wallets[i];
              return Panel(
                child: Row(children: [
                  DecoratedBox(
                    decoration: BoxDecoration(color: const Color(0xFF2A2416), borderRadius: BorderRadius.circular(10)),
                    child: SizedBox.square(dimension: 38, child: Center(child: Text(w.coin, style: mono.copyWith(color: C.rate, fontWeight: FontWeight.w700, fontSize: 11)))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(w.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      SelectableText(w.address, maxLines: 1, style: mono.copyWith(fontSize: 12, color: C.muted)),
                      if (w.note.isNotEmpty) Text(w.note, style: const TextStyle(fontSize: 12, color: C.muted)),
                    ]),
                  ),
                ]),
              );
            },
          );
        },
      ),
    );
  }
}

class TokensPage extends StatefulWidget {
  const TokensPage({super.key});
  @override
  State<TokensPage> createState() => _TokensPageState();
}

class _TokensPageState extends State<TokensPage> {
  int _tab = 0;
  List<dynamic>? _tokens;
  List<dynamic>? _audit;
  Object? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_tokens == null && _error == null) _load();
  }

  Future<void> _load() async {
    final b = AppScope.of(context).backend;
    try {
      final r = await Future.wait([b.getJson('/api/v1/tokens'), b.getJson('/api/v1/audit')]);
      if (mounted) {
        setState(() {
          _tokens = r[0] as List;
          _audit = r[1] as List;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _revoke(Map<String, dynamic> t) async {
    if (!await confirm(context, '撤销「${asStr(t['name'])}」？', '用这个令牌的程序会立即失去访问权限。', action: '撤销', danger: true)) return;
    if (!mounted) return;
    try {
      await AppScope.of(context).backend.send('DELETE', '/api/v1/tokens/${asStr(t['id'])}');
      await _load();
    } catch (e) {
      if (mounted) toast(context, '撤销失败：${errorText(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = _tokens, audit = _audit;
    return Scaffold(
      appBar: AppBar(title: const Text('令牌与审计')),
      body: _error != null
          ? EmptyHint('读取失败：${errorText(_error!)}')
          : tokens == null || audit == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    SegmentedButton<int>(
                      segments: const [ButtonSegment(value: 0, label: Text('API 令牌')), ButtonSegment(value: 1, label: Text('审计记录'))],
                      selected: {_tab},
                      showSelectedIcon: false,
                      onSelectionChanged: (v) => setState(() => _tab = v.first),
                    ),
                    const SizedBox(height: 12),
                    if (_tab == 0) ...[
                      const Notice('令牌具有完整管理权限。新建令牌请在主控网页进行（明文只显示一次）。', fg: C.infoText, bg: C.infoBg, border: Color(0xFF3B4A5C), icon: Icons.info_outline),
                      const SizedBox(height: 12),
                      Panel(
                        padding: EdgeInsets.zero,
                        child: Column(children: [
                          if (tokens.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('没有令牌', style: TextStyle(color: C.muted))),
                          for (final t in tokens.map(asMap))
                            ListTile(
                              title: Text(asStr(t['name'])),
                              subtitle: Text(
                                '创建于 ${_date(t['created_at'])}${t['last_used_at'] == null ? '' : ' · 最近使用 ${_date(t['last_used_at'])}'}',
                                style: const TextStyle(fontSize: 12, color: C.muted),
                              ),
                              trailing: TextButton(onPressed: () => _revoke(t), child: const Text('撤销', style: TextStyle(color: C.badText))),
                            ),
                        ]),
                      ),
                    ] else
                      Panel(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        child: Column(children: [
                          if (audit.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('没有记录', style: TextStyle(color: C.muted))),
                          for (final a in audit.map(asMap).take(200))
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(asStr(a['action']), style: const TextStyle(fontSize: 13)),
                                    const SizedBox(height: 2),
                                    Text('${asStr(a['actor'])} · ${asStr(a['target'])}', style: const TextStyle(fontSize: 12, color: C.muted)),
                                  ]),
                                ),
                                Text(_date(a['created_at']), style: mono.copyWith(fontSize: 11, color: C.muted)),
                              ]),
                            ),
                        ]),
                      ),
                  ],
                ),
    );
  }

  static String _date(dynamic v) {
    final t = DateTime.tryParse(asStr(v));
    return t == null ? '—' : ago(t);
  }
}
