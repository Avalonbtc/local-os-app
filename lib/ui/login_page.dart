import 'package:flutter/material.dart';

import '../data/session.dart';
import '../theme.dart';
import 'widgets.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.session});
  final SessionController session;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final _server = TextEditingController(text: widget.session.lastServer);
  final _user = TextEditingController(text: 'admin');
  final _password = TextEditingController();
  final _token = TextEditingController();
  bool _useToken = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _server.dispose();
    _user.dispose();
    _password.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_server.text.trim().isEmpty) {
      setState(() => _error = '请填写主控地址');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_useToken) {
        await widget.session.loginWithToken(_server.text, _token.text);
      } else {
        await widget.session.loginWithPassword(_server.text, _user.text, _password.text);
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
              children: [
                const _Logo(),
                const SizedBox(height: 14),
                const Text('RigDeck', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text('连接你的矿场主控，随时查看矿机状态与离线通知。', style: TextStyle(color: C.muted, fontSize: 15, height: 1.6)),
                const SizedBox(height: 28),
                TextField(
                  controller: _server,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  style: mono,
                  decoration: const InputDecoration(
                    labelText: '主控地址',
                    hintText: 'https://192.168.1.10 或 VPN 地址',
                    helperText: '局域网地址，或经 Tailscale / WireGuard 等 VPN 访问的地址',
                    helperMaxLines: 2,
                  ),
                ),
                const SizedBox(height: 16),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('账号密码')),
                    ButtonSegment(value: true, label: Text('API 令牌')),
                  ],
                  selected: {_useToken},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => setState(() => _useToken = v.first),
                ),
                const SizedBox(height: 16),
                if (_useToken)
                  TextField(
                    controller: _token,
                    obscureText: true,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'API 令牌',
                      helperText: '主控网页 设定 → AI / API 令牌 创建；不会过期，可随时撤销',
                      helperMaxLines: 2,
                    ),
                  )
                else ...[
                  TextField(
                    controller: _user,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: '用户名'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    onSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(labelText: '密码', helperText: '会话 12 小时后需要重新登录'),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Notice(_error!, fg: C.badText, bg: C.badBg, border: const Color(0xFF5A2A2E), icon: Icons.error_outline),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: C.onAccent))
                      : const Text('登录'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();
  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final h in const [18.0, 34.0, 26.0])
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: SizedBox(
                width: 9,
                height: h,
                child: const DecoratedBox(
                  decoration: BoxDecoration(color: C.accent, borderRadius: BorderRadius.all(Radius.circular(3))),
                ),
              ),
            ),
        ],
      );
}
