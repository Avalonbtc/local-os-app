import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../theme.dart';
import 'batch_sheet.dart';
import 'more_page.dart';
import 'widgets.dart';

/// An SSH shell on the machine through the controller (`/machines/{id}/terminal`), or with
/// [instance] the miner's own console. Phones lack Esc / Ctrl / arrows, so a key row adds them.
class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key, required this.machine, this.instance});
  final Machine machine;
  final String? instance;
  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  final _terminal = Terminal(maxLines: 5000);
  final _controller = TerminalController();
  TerminalLink? _link;
  StreamSubscription<String>? _sub;
  bool _connecting = false;
  String? _closed;
  bool _ctrl = false;

  @override
  void initState() {
    super.initState();
    _terminal.onOutput = _send;
    _terminal.onResize = (cols, rows, _, _) => _link?.resize(cols, rows);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_link == null && !_connecting && _closed == null) _connect();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _link?.close();
    _controller.dispose();
    super.dispose();
  }

  void _send(String data) {
    // Sticky Ctrl from the key row applies to the next typed letter: Ctrl+C → 0x03.
    if (_ctrl && data.length == 1) {
      final c = data.toLowerCase().codeUnitAt(0);
      if (c >= 0x61 && c <= 0x7a) data = String.fromCharCode(c - 0x60);
      setState(() => _ctrl = false);
    }
    _link?.input(utf8.encode(data));
  }

  Future<void> _connect() async {
    final backend = AppScope.of(context).backend;
    setState(() {
      _connecting = true;
      _closed = null;
    });
    _terminal.write('\x1b[2m正在连接 ${widget.machine.name}…\x1b[0m\r\n');
    try {
      final link = await backend.openTerminal(widget.machine.id, instance: widget.instance);
      if (!mounted) {
        link.close();
        return;
      }
      _link = link;
      // Decode across frame boundaries: a multi-byte character may be split between frames.
      _sub = link.output.transform(const Utf8Decoder(allowMalformed: true)).listen(
        _terminal.write,
        onError: (Object e) => _end(errorText(e)),
        onDone: () => _end('连接已关闭'),
      );
      link.resize(_terminal.viewWidth, _terminal.viewHeight);
      setState(() => _connecting = false);
    } catch (e) {
      _end(errorText(e));
    }
  }

  void _end(String reason) {
    if (!mounted || _closed != null) return;
    _sub?.cancel();
    _sub = null;
    _link?.close();
    _link = null;
    _terminal.write('\r\n\x1b[33m$reason\x1b[0m\r\n');
    setState(() {
      _connecting = false;
      _closed = reason;
    });
  }

  Widget _key(String label, VoidCallback onTap, {bool on = false}) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Material(
          color: on ? C.accent : C.surface2,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minWidth: 44),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(label, style: mono.copyWith(fontSize: 13, color: on ? C.onAccent : C.text)),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final title = widget.instance == null ? '终端 · ${widget.machine.name}' : '${widget.instance} 控制台';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(title, overflow: TextOverflow.ellipsis),
        actions: [
          if (_closed != null)
            IconButton(tooltip: '重新连接', onPressed: _connect, icon: const Icon(Icons.refresh_rounded))
          else if (_connecting)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: TerminalView(
              _terminal,
              controller: _controller,
              autofocus: true,
              textStyle: const TerminalStyle(fontSize: 13),
              padding: const EdgeInsets.all(4),
            ),
          ),
          Container(
            color: C.bar,
            height: 44,
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
            child: ListView(scrollDirection: Axis.horizontal, children: [
              _key('Esc', () => _terminal.keyInput(TerminalKey.escape)),
              _key('Tab', () => _terminal.keyInput(TerminalKey.tab)),
              _key('Ctrl', () => setState(() => _ctrl = !_ctrl), on: _ctrl),
              _key('^C', () => _link?.input(const [3])),
              _key('←', () => _terminal.keyInput(TerminalKey.arrowLeft)),
              _key('↑', () => _terminal.keyInput(TerminalKey.arrowUp)),
              _key('↓', () => _terminal.keyInput(TerminalKey.arrowDown)),
              _key('→', () => _terminal.keyInput(TerminalKey.arrowRight)),
              for (final c in const ['|', '/', '-', '~', '\$'])
                _key(c, () => _send(c)),
            ]),
          ),
        ]),
      ),
    );
  }
}

const _presets = {
  '运行时间': 'uptime',
  '内存': 'free -h',
  '磁盘': 'df -h /',
  '温度': 'sensors 2>/dev/null || cat /sys/class/thermal/thermal_zone*/temp',
  '显卡': 'nvidia-smi 2>/dev/null || echo "没有 nvidia-smi"',
  '矿工': '/usr/local/bin/rig-miner status 2>&1 | tail -n 40',
};

/// Run one shell command on many machines (a `command` job) and show each machine's output.
class CommandPage extends StatefulWidget {
  const CommandPage({super.key, this.machineIds = const []});
  final List<String> machineIds;
  @override
  State<CommandPage> createState() => _CommandPageState();
}

class _CommandPageState extends State<CommandPage> {
  late Set<String> _ids = {...widget.machineIds};
  final _script = TextEditingController();
  final _timeout = TextEditingController(text: '60');
  bool _busy = false;
  Job? _job;
  Timer? _poll;

  @override
  void dispose() {
    _poll?.cancel();
    _script.dispose();
    _timeout.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final rows = AppScope.of(context).fleet.snapshot.rows;
    final ids = await pickMachines(context, rows, title: '在这些矿机上执行', action: (n) => '选择 $n 台', initial: _ids);
    if (ids != null && mounted) setState(() => _ids = ids.toSet());
  }

  Future<void> _run() async {
    final script = _script.text.trim();
    final timeout = int.tryParse(_timeout.text.trim());
    if (_ids.isEmpty) return toast(context, '先选择矿机');
    if (script.isEmpty) return toast(context, '请输入命令');
    if (timeout == null || timeout < 1 || timeout > 3600) return toast(context, '超时应为 1–3600 秒');
    if (!await confirm(context, '在 ${_ids.length} 台矿机上执行？', script, action: '执行')) return;
    if (!mounted) return;
    final b = AppScope.of(context).backend;
    setState(() => _busy = true);
    try {
      final id = await submitJob(b, _ids.toList(), {'kind': 'command', 'script': script, 'timeout_seconds': timeout}, includeController: true);
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
        if (!job.active && job.status != 'reconciling') return;
      } catch (_) {
        if (!mounted) return;
      }
      _poll = Timer(const Duration(seconds: 2), tick);
    }

    tick();
  }

  @override
  Widget build(BuildContext context) {
    final fleet = AppScope.of(context).fleet;
    final names = [for (final id in _ids) fleet.row(id)?.machine.name ?? id]..sort(naturalCompare);
    final job = _job;
    return Scaffold(
      appBar: AppBar(title: const Text('执行命令')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Panel(
            onTap: _pick,
            child: Row(children: [
              const Icon(Icons.dns_outlined, color: C.rate, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _ids.isEmpty ? '选择矿机' : '${_ids.length} 台：${names.take(6).join('、')}${names.length > 6 ? ' 等' : ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.chevron_right, color: C.faint),
            ]),
          ),
          const SizedBox(height: 12),
          FormText(_script, '命令', monospace: true, lines: 3, hint: 'uptime', help: '以 SSH 用户身份在每台矿机上执行（sh）'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in _presets.entries)
              ActionChip(label: Text(e.key), onPressed: () => setState(() => _script.text = e.value)),
          ]),
          const SizedBox(height: 12),
          FormText(_timeout, '超时（秒）', keyboard: TextInputType.number),
          FilledButton(onPressed: _busy || (job?.active ?? false) ? null : _run, child: const Text('执行')),
          if (job != null) ...[
            const SizedBox(height: 16),
            SectionLabel('结果 · ${job.targets.where((t) => !{'queued', 'running', 'reconciling'}.contains(t.status)).length} / ${job.targets.length}'),
            for (final t in job.targets) ...[
              const SizedBox(height: 8),
              Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(t.machineName, style: const TextStyle(fontWeight: FontWeight.w600))),
                    Builder(builder: (_) {
                      final (l, fg, bg) = jobStatus(t.status);
                      return Tag(l, fg: fg, bg: bg);
                    }),
                  ]),
                  if ((t.error ?? '').isNotEmpty || t.output.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    SelectableText(
                      [t.output, ?t.error].where((s) => s.isNotEmpty).join('\n'),
                      style: mono.copyWith(fontSize: 11, height: 1.5, color: t.error == null ? C.text2 : C.badText),
                    ),
                  ],
                ]),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
