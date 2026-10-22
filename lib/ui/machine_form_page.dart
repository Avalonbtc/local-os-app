import 'package:flutter/material.dart';

import '../api/client.dart';
import '../api/forms.dart';
import '../api/models.dart';
import '../theme.dart';
import 'more_page.dart';
import 'widgets.dart';

const _defaultPolicy = {
  'max_restarts': 5,
  'cooldown_seconds': 30,
  'failure_seconds': 120,
  'allow_host_reboot': false,
  'gpu_temp_limit_c': 85,
};

/// Ask the controller for the SSH host key at [host]:[port] and have the user confirm it.
/// Returns the fingerprint when trusted.
Future<String?> confirmHostKey(BuildContext context, String host, int port, {String? known}) async {
  final backend = AppScope.of(context).backend;
  final result = asMap(await backend.send('POST', '/api/v1/ssh/host-key', {'host': host, 'port': port}));
  final fingerprint = asStr(result['fingerprint']);
  if (!context.mounted || fingerprint.isEmpty) return null;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('确认服务器身份'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('主控已连接 $host:$port，获取到以下 ${asStr(result['algorithm'])} 主机指纹：', style: const TextStyle(height: 1.5)),
        const SizedBox(height: 8),
        SelectableText(fingerprint, style: mono.copyWith(fontSize: 12)),
        const SizedBox(height: 8),
        const Text('请确认这是要管理的服务器。保存后指纹变化会拒绝连接。', style: TextStyle(fontSize: 13, color: C.muted, height: 1.5)),
        if (known != null && known.isNotEmpty && known != fingerprint) ...[
          const SizedBox(height: 8),
          const Notice('与当前填写的指纹不同，请核实是否重装系统或更换了服务器。'),
        ],
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消', style: TextStyle(color: C.text2))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('信任此服务器')),
      ],
    ),
  );
  return ok == true ? fingerprint : null;
}

/// SSH login: password or private key (pasted; phones have no key files to pick).
class _Credential {
  String kind = 'password';
  final secret = TextEditingController();
  final passphrase = TextEditingController();

  Map<String, dynamic>? toJson() {
    final s = secret.text;
    if (s.isEmpty) return null;
    return kind == 'password'
        ? {'kind': 'password', 'password': s, 'sudo_password': null}
        : {
            'kind': 'private_key',
            'private_key': s.trim().endsWith('\n') ? s : '${s.trim()}\n',
            'passphrase': passphrase.text.isEmpty ? null : passphrase.text,
            'sudo_password': null,
          };
  }

  String? check() {
    if (kind == 'private_key' && secret.text.isNotEmpty &&
        !RegExp(r'^\s*-----BEGIN (?:OPENSSH |RSA |EC |DSA |ENCRYPTED )?PRIVATE KEY-----').hasMatch(secret.text)) {
      return '私钥应以 -----BEGIN … PRIVATE KEY----- 开头（OpenSSH / PEM 格式，不是 .pub 公钥）';
    }
    return null;
  }

  void dispose() {
    secret.dispose();
    passphrase.dispose();
  }

  List<Widget> fields(void Function(VoidCallback) setState, {required bool editing}) => [
        Choice<String>(
          value: kind,
          options: const {'password': '密码', 'private_key': '私钥'},
          onChanged: (v) => setState(() {
            kind = v;
            secret.clear();
            passphrase.clear();
          }),
        ),
        if (kind == 'password')
          FormText(secret, 'SSH 密码', obscure: true, help: editing ? '留空表示不修改' : null)
        else ...[
          FormText(secret, '私钥', monospace: true, lines: 4,
              hint: '-----BEGIN OPENSSH PRIVATE KEY-----', help: editing ? '留空表示不修改' : '粘贴私钥全文'),
          FormText(passphrase, '私钥密码（可选）', obscure: true),
        ],
      ];
}

/// Add one machine, or edit / delete an existing one.
class MachineFormPage extends StatefulWidget {
  const MachineFormPage({super.key, this.machine});
  final Machine? machine;
  @override
  State<MachineFormPage> createState() => _MachineFormPageState();
}

class _MachineFormPageState extends State<MachineFormPage> {
  late final Map<String, dynamic> _raw = widget.machine?.raw ?? const {};
  late final _name = TextEditingController(text: asStr(_raw['name']));
  late final _group = TextEditingController(text: asStr(_raw['group']));
  late final _tags = TextEditingController(text: asList(_raw['tags']).join(', '));
  late final _host = TextEditingController(text: asStr(_raw['host']));
  late final _port = TextEditingController(text: '${asNum(_raw['port'])?.toInt() ?? 22}');
  late final _user = TextEditingController(text: asStr(_raw['username'], 'root'));
  late final _hostKey = TextEditingController(text: asStr(_raw['host_key']));
  final _sudo = TextEditingController();
  final _cred = _Credential();
  late final Map<String, dynamic> _bmc = asMap(_raw['bmc']);
  late bool _bmcOn = _raw['bmc'] is Map;
  late String _bmcProvider = asStr(_bmc['provider'], 'redfish');
  late final _bmcUrl = TextEditingController(text: asStr(_bmc['url']));
  late final _bmcUser = TextEditingController(text: asStr(_bmc['username']));
  final _bmcPassword = TextEditingController();
  bool _bootstrap = true;
  bool _busy = false;
  bool _saving = false;
  late String _address = '${_host.text}:${_port.text}';

  bool get _editing => widget.machine != null;

  @override
  void dispose() {
    for (final c in [_name, _group, _tags, _host, _port, _user, _hostKey, _sudo, _bmcUrl, _bmcUser, _bmcPassword]) {
      c.dispose();
    }
    _cred.dispose();
    super.dispose();
  }

  /// A new address means a different server: its old fingerprint no longer applies.
  void _addressChanged(String _) {
    final now = '${_host.text.trim()}:${_port.text.trim()}';
    if (now != _address && _hostKey.text.isNotEmpty) setState(_hostKey.clear);
    _address = now;
  }

  (String, int)? _target() {
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim());
    if (host.isEmpty) {
      toast(context, '请填写 SSH 地址');
      return null;
    }
    if (port == null || port < 1 || port > 65535) {
      toast(context, 'SSH 端口无效');
      return null;
    }
    return (host, port);
  }

  Future<String?> _probe() async {
    final t = _target();
    if (t == null) return null;
    setState(() => _busy = true);
    try {
      final key = await confirmHostKey(context, t.$1, t.$2, known: _hostKey.text.trim());
      if (key != null && mounted) setState(() => _hostKey.text = key);
      return key;
    } catch (e) {
      if (mounted) toast(context, '获取指纹失败：${errorText(e)}');
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final t = _target();
    if (t == null) return;
    if (_name.text.trim().isEmpty) return toast(context, '请填写机器名称');
    if (!_editing && _cred.secret.text.isEmpty) return toast(context, '请填写 SSH 密码或私钥');
    final credError = _cred.check();
    if (credError != null) return toast(context, credError);
    if (_bmcOn && (_bmcUrl.text.trim().isEmpty || _bmcUser.text.trim().isEmpty)) {
      return toast(context, '请填写 BMC 地址和用户名');
    }
    final hostKey = _hostKey.text.trim().isNotEmpty ? _hostKey.text.trim() : await _probe();
    if (hostKey == null || !mounted) return;
    final input = {
      'name': _name.text.trim(),
      'host': t.$1,
      'port': t.$2,
      'username': _user.text.trim().isEmpty ? 'root' : _user.text.trim(),
      'host_key': hostKey,
      'group': _group.text.trim(),
      'tags': _tags.text.split(RegExp(r'[,，]')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
      'is_controller': _raw['is_controller'] == true,
      'credential': _cred.toJson(),
      'sudo_password': _sudo.text.isEmpty ? null : _sudo.text,
      'bmc': _bmcOn
          ? {'url': _bmcUrl.text.trim(), 'username': _bmcUser.text.trim(), 'provider': _bmcProvider, 'ca_pem': _bmc['ca_pem']}
          : null,
      'bmc_credential': _bmcOn && _bmcPassword.text.isNotEmpty
          ? {'kind': 'password', 'password': _bmcPassword.text, 'sudo_password': null}
          : null,
      'policy': _editing ? widget.machine!.policy : _defaultPolicy,
    };
    final scope = AppScope.of(context);
    setState(() => _busy = _saving = true);
    try {
      String? warning;
      if (_editing) {
        await scope.backend.send('PUT', '/api/v1/machines/${widget.machine!.id}', input);
      } else {
        // The batch endpoint also queues the runtime deployment in the same call.
        final result = asMap(await scope.backend.send('POST', '/api/v1/machines/batch', {
          'machines': [input],
          'bootstrap': _bootstrap,
        }));
        final row = asMap(asList(result['results']).firstOrNull);
        if (row['error'] is String) throw ApiException(null, row['error'] as String);
        if (result['bootstrap_error'] is String) warning = '已添加，但部署运行层没有提交：${result['bootstrap_error']}';
      }
      await scope.fleet.refresh();
      if (!mounted) return;
      Navigator.pop(context, true);
      toast(context, warning ?? (_editing ? '已保存' : _bootstrap ? '已添加，正在部署运行层' : '已添加'),
          action: !_editing && _bootstrap && warning == null ? '查看' : null,
          onAction: () => push(context, const JobsPage()));
    } catch (e) {
      if (mounted) toast(context, '保存失败：${errorText(e)}');
    } finally {
      if (mounted) setState(() => _busy = _saving = false);
    }
  }

  Future<void> _delete() async {
    final m = widget.machine!;
    if (!await confirm(context, '删除 ${m.name}？', '从主控移除这台矿机及其凭据。矿机上的矿工不会被停止。', action: '删除', danger: true)) return;
    if (!mounted) return;
    final scope = AppScope.of(context);
    setState(() => _busy = true);
    try {
      await scope.backend.send('DELETE', '/api/v1/machines/${m.id}');
      await scope.fleet.refresh();
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) {
        toast(context, '删除失败：${errorText(e)}');
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? '编辑 ${widget.machine!.name}' : '添加矿机'),
        actions: [
          if (_editing)
            IconButton(tooltip: '删除矿机', onPressed: _busy ? null : _delete, icon: const Icon(Icons.delete_outline, color: C.badText)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FormText(_name, '机器名称', hint: 'rig-01'),
          FormText(_group, '分组（可选）'),
          FormText(_tags, '标签（可选）', hint: '逗号分隔'),
          const SectionLabel('SSH'),
          const SizedBox(height: 6),
          FormText(_host, 'SSH 地址', hint: '192.168.1.101', monospace: true, keyboard: TextInputType.url, onChanged: _addressChanged),
          Row(children: [
            Expanded(child: FormText(_port, '端口', keyboard: TextInputType.number, onChanged: _addressChanged)),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: FormText(_user, '用户')),
          ]),
          ..._cred.fields(setState, editing: _editing),
          FormText(_sudo, 'sudo 密码（可选）', obscure: true, help: '非 root 用户且 sudo 需要密码时填写'),
          FormText(_hostKey, 'SSH 主机指纹', monospace: true, hint: '留空保存时自动获取', help: '首次连接自动获取并让你确认；已知指纹也可直接填写'),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _probe,
              icon: const Icon(Icons.fingerprint, size: 18),
              label: const Text('获取并确认指纹'),
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('BMC（远程电源、BIOS）'),
            value: _bmcOn,
            onChanged: (v) => setState(() => _bmcOn = v),
          ),
          if (_bmcOn) ...[
            Choice<String>(
              value: _bmcProvider,
              options: const {'redfish': 'Redfish', 'ipmi': 'IPMI'},
              onChanged: (v) => setState(() => _bmcProvider = v),
            ),
            FormText(_bmcUrl, 'BMC 地址', hint: _bmcProvider == 'redfish' ? 'https://192.168.1.201' : '192.168.1.201', monospace: true, keyboard: TextInputType.url),
            FormText(_bmcUser, 'BMC 用户'),
            FormText(_bmcPassword, 'BMC 密码', obscure: true, help: _editing ? '留空表示不修改' : null),
          ],
          if (!_editing)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _bootstrap,
              onChanged: (v) => setState(() => _bootstrap = v ?? false),
              title: const Text('添加后部署运行层'),
              subtitle: const Text('安装 rig-agent 和矿工托管，之后才能应用飞行表', style: TextStyle(fontSize: 12, color: C.muted)),
            ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _saving
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_editing ? '保存' : '添加'),
          ),
        ],
      ),
    );
  }
}

/// Import many machines that share one login: probe every host key, let the user tick the
/// ones to trust, then add them in one call.
class BatchImportPage extends StatefulWidget {
  const BatchImportPage({super.key});
  @override
  State<BatchImportPage> createState() => _BatchImportPageState();
}

class _Probe {
  _Probe(this.target);
  final ImportTarget target;
  String? fingerprint;
  String? error;
  bool include = false;
  String? result;
  bool added = false;
}

class _BatchImportPageState extends State<BatchImportPage> {
  final _targets = TextEditingController();
  final _template = TextEditingController(text: 'rig-{last}');
  final _port = TextEditingController(text: '22');
  final _user = TextEditingController(text: 'root');
  final _group = TextEditingController();
  final _tags = TextEditingController();
  final _sudo = TextEditingController();
  final _cred = _Credential();
  bool _bootstrap = true;
  bool _busy = false;
  List<_Probe>? _rows;

  @override
  void dispose() {
    for (final c in [_targets, _template, _port, _user, _group, _tags, _sudo]) {
      c.dispose();
    }
    _cred.dispose();
    super.dispose();
  }

  Future<void> _probe() async {
    final List<ImportTarget> targets;
    try {
      targets = parseTargets(_targets.text, _template.text.trim().isEmpty ? 'rig-{last}' : _template.text.trim(),
          port: int.tryParse(_port.text.trim()) ?? 22, username: _user.text.trim().isEmpty ? 'root' : _user.text.trim());
    } on FormatException catch (e) {
      return toast(context, e.message);
    }
    if (targets.isEmpty) return toast(context, '请填写要导入的地址');
    final backend = AppScope.of(context).backend;
    setState(() => _busy = true);
    try {
      final result = await backend.send('POST', '/api/v1/ssh/host-keys', {
        'targets': [for (final t in targets) {'host': t.host, 'port': t.port}],
      });
      final rows = [for (final t in targets) _Probe(t)];
      // Results come back in request order.
      final list = asList(asMap(result)['results'] ?? result);
      for (var i = 0; i < rows.length && i < list.length; i++) {
        final r = asMap(list[i]);
        rows[i].fingerprint = r['fingerprint'] as String?;
        rows[i].error = r['error'] as String?;
        rows[i].include = rows[i].fingerprint != null && rows[i].error == null;
      }
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted) toast(context, '读取指纹失败：${errorText(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    final rows = _rows!.where((r) => r.include && !r.added).toList();
    if (rows.isEmpty) return;
    if (_cred.secret.text.isEmpty) return toast(context, '请填写 SSH 密码或私钥');
    final credError = _cred.check();
    if (credError != null) return toast(context, credError);
    if (!await confirm(context, '信任并添加 ${rows.length} 台？', '确认这些指纹属于你的服务器。之后指纹变化会拒绝连接。', action: '添加')) return;
    if (!mounted) return;
    final scope = AppScope.of(context);
    final tags = _tags.text.split(RegExp(r'[,，]')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    setState(() => _busy = true);
    try {
      final result = asMap(await scope.backend.send('POST', '/api/v1/machines/batch', {
        'machines': [
          for (final r in rows)
            {
              'name': r.target.name,
              'host': r.target.host,
              'port': r.target.port,
              'username': r.target.username,
              'host_key': r.fingerprint,
              'group': _group.text.trim(),
              'tags': tags,
              'is_controller': false,
              'credential': _cred.toJson(),
              'sudo_password': _sudo.text.isEmpty ? null : _sudo.text,
              'bmc': null,
              'bmc_credential': null,
              'policy': _defaultPolicy,
            },
        ],
        'bootstrap': _bootstrap,
      }));
      final results = asList(result['results']);
      setState(() {
        for (var i = 0; i < rows.length && i < results.length; i++) {
          final e = asMap(results[i])['error'];
          rows[i].added = e == null;
          rows[i].result = e is String ? e : '已添加';
        }
      });
      await scope.fleet.refresh();
      if (!mounted) return;
      final added = rows.where((r) => r.added).length;
      final bootError = result['bootstrap_error'];
      toast(
        context,
        bootError is String ? '已添加 $added 台，但部署运行层没有提交：$bootError' : '已添加 $added 台${_bootstrap && added > 0 ? '，正在部署运行层' : ''}',
        action: result['bootstrap_job_id'] is String ? '查看' : null,
        onAction: () => push(context, const JobsPage()),
      );
    } catch (e) {
      if (mounted) toast(context, '添加失败：${errorText(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final chosen = rows?.where((r) => r.include && !r.added).length ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('批量添加')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FormText(_targets, '地址', monospace: true, lines: 4,
              hint: '192.168.1.10-60\n192.168.1.0/24\nrig-07,192.168.1.17,22,root',
              help: '每行一个：地址段、CIDR，或「名称,地址[,端口[,用户]]」；一次最多 $maxImport 台'),
          FormText(_template, '命名模板', monospace: true, help: '{last} 末段 · {last2} 后两段 · {ip} 完整地址 · {n} / {n:3} 序号'),
          Row(children: [
            Expanded(child: FormText(_port, '端口', keyboard: TextInputType.number)),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: FormText(_user, '用户')),
          ]),
          FormText(_group, '分组（可选）'),
          FormText(_tags, '标签（可选）', hint: '逗号分隔'),
          const SectionLabel('统一的登录方式'),
          const SizedBox(height: 6),
          ..._cred.fields(setState, editing: false),
          FormText(_sudo, 'sudo 密码（可选）', obscure: true),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _bootstrap,
            onChanged: (v) => setState(() => _bootstrap = v ?? false),
            title: const Text('添加后部署运行层'),
          ),
          OutlinedButton(onPressed: _busy ? null : _probe, child: const Text('读取主机指纹')),
          if (rows != null) ...[
            const SizedBox(height: 16),
            SectionLabel('${rows.length} 台 · 勾选要信任的指纹'),
            Panel(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (final r in rows)
                  CheckboxListTile(
                    dense: true,
                    value: r.include,
                    onChanged: r.fingerprint == null || r.added ? null : (v) => setState(() => r.include = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text('${r.target.name} · ${r.target.host}${r.target.port == 22 ? '' : ':${r.target.port}'}'),
                    subtitle: Text(
                      r.result ?? r.error ?? r.fingerprint ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: mono.copyWith(
                        fontSize: 11,
                        color: r.added ? C.okText : (r.error != null || (r.result != null && !r.added)) ? C.badText : C.muted,
                      ),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy || chosen == 0 ? null : _create,
              child: Text(chosen == 0 ? '没有可添加的机器' : '信任并添加 $chosen 台'),
            ),
          ],
        ],
      ),
    );
  }
}
