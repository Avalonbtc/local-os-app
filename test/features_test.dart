import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rigdeck_app/data/session.dart';
import 'package:rigdeck_app/data/stores.dart';
import 'package:rigdeck_app/main.dart';
import 'package:rigdeck_app/ui/widgets.dart';

import 'support/fake_backend.dart';

/// The management features the web console has: adding machines, editing flight sheets,
/// overclocking, BIOS, terminal and commands — each walked against the in-memory controller.
Future<FakeBackend> _boot(WidgetTester tester, {Size size = const Size(390, 844), double text = 1}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = text;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final session = SessionController();
  await tester.runAsync(session.restore);
  await tester.pumpWidget(RigDeckApp(session: session));
  FleetStore.offThread = false;
  final backend = FakeBackend(latency: Duration.zero, background: false);
  session.useBackend(backend);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
  return backend;
}

/// Stop the stores' timers so nothing outlives the test.
Future<void> _logout(WidgetTester tester) async {
  final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
  nav.popUntil((r) => r.isFirst);
  await tester.pumpAndSettle();
  await tester.tap(find.text('更多').last);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.text('退出登录'), 200, scrollable: find.byType(Scrollable).last);
  await tester.tap(find.text('退出登录'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, '退出'));
  await tester.pumpAndSettle();
}

Future<void> _openRig(WidgetTester tester, String name) async {
  await tester.tap(find.text('矿机').last);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.text(name), 200, scrollable: find.byType(Scrollable).last);
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
}

/// The scroll view of the page on top (text fields have their own Scrollables inside).
Finder get _page => find.descendant(of: find.byType(Scaffold).last, matching: find.byType(Scrollable)).first;

Future<void> _enter(WidgetTester tester, String label, String text) async {
  final field = find.widgetWithText(TextField, label);
  await tester.scrollUntilVisible(field, 150, scrollable: _page);
  await tester.enterText(field, text);
  await tester.pump();
}

Future<void> _tapVisible(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 150, scrollable: _page);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('add a machine: host key is confirmed, then it is in the list', (tester) async {
    await _boot(tester);
    await tester.tap(find.text('矿机').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('添加矿机'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加一台'));
    await tester.pumpAndSettle();

    await _enter(tester, '机器名称', 'rig-new');
    await _enter(tester, 'SSH 地址', '192.168.9.9');
    await _enter(tester, 'SSH 密码', 'test-only');
    await _tapVisible(tester, find.widgetWithText(FilledButton, '添加'));
    expect(find.text('确认服务器身份'), findsOneWidget);
    expect(find.textContaining('SHA256:'), findsOneWidget);
    await tester.tap(find.text('信任此服务器'));
    await tester.pumpAndSettle();

    expect(find.text('添加矿机'), findsNothing);
    await tester.scrollUntilVisible(find.text('rig-new'), 300, scrollable: find.byType(Scrollable).last);
    expect(find.text('rig-new'), findsOneWidget);
    await _logout(tester);
  });

  testWidgets('batch import: unreachable hosts are left out', (tester) async {
    await _boot(tester);
    await tester.tap(find.text('矿机').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('添加矿机'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('批量添加'));
    await tester.pumpAndSettle();

    await _enter(tester, '地址', '10.9.0.97-99');
    await _enter(tester, 'SSH 密码', 'test-only');
    await _tapVisible(tester, find.text('读取主机指纹'));
    await tester.scrollUntilVisible(find.text('连接被拒绝'), 150, scrollable: _page);
    expect(find.textContaining('rig-97 · 10.9.0.97'), findsOneWidget);
    expect(find.text('连接被拒绝'), findsOneWidget);
    await _tapVisible(tester, find.text('信任并添加 2 台'));
    await tester.tap(find.widgetWithText(FilledButton, '添加'));
    await tester.pumpAndSettle();
    expect(find.text('已添加'), findsNWidgets(2));
    await _logout(tester);
  });

  testWidgets('flight sheets: create one, edit another', (tester) async {
    await _boot(tester);
    await tester.tap(find.text('飞行表').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新建飞行表'));
    await tester.pumpAndSettle();
    expect(find.text('XMRig'), findsOneWidget);
    expect(find.text('6.22.2'), findsOneWidget);

    await _enter(tester, '飞行表名称', 'XMR · 测试池');
    // Pick a wallet (two exist, so none is preselected).
    await _tapVisible(tester, find.widgetWithText(DropdownButtonFormField<String>, '钱包'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('XMR · 主钱包').last);
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.widgetWithText(FilledButton, '保存'));
    expect(find.text('第 1 个挖矿软件：缺少矿池地址'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5)); // let the message clear off the button
    await tester.pumpAndSettle();
    await _enter(tester, '矿池地址', 'stratum+tcp://pool.test:3333');
    await _tapVisible(tester, find.widgetWithText(FilledButton, '保存'));
    expect(find.text('新建飞行表'), findsNothing);
    await tester.scrollUntilVisible(find.text('XMR · 测试池'), 300, scrollable: find.byType(Scrollable).last);
    expect(find.text('XMR · 测试池'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('XMR · 自建代理 A'), -300, scrollable: find.byType(Scrollable).last);
    final card = find.ancestor(of: find.text('XMR · 自建代理 A'), matching: find.byType(Panel));
    await tester.tap(find.descendant(of: card, matching: find.widgetWithText(OutlinedButton, '编辑')));
    await tester.pumpAndSettle();
    expect(find.text('编辑飞行表'), findsOneWidget);
    await _enter(tester, '飞行表名称', 'XMR · 自建代理 A2');
    await _tapVisible(tester, find.widgetWithText(FilledButton, '保存'));
    expect(find.text('XMR · 自建代理 A2'), findsOneWidget);
    expect(find.textContaining('v6'), findsOneWidget);
    await _logout(tester);
  });

  testWidgets('overclock: cards, last results, apply', (tester) async {
    await _boot(tester);
    await _openRig(tester, 'rig-03');
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('显卡超频'));
    await tester.pumpAndSettle();
    expect(find.text('NVIDIA 0'), findsOneWidget);
    expect(find.text('显存：nvidia-settings 无权限'), findsOneWidget);
    expect(find.textContaining('将应用：核心 1500'), findsNWidgets(2));

    await _enter(tester, '风扇（%）', '80 85');
    await tester.scrollUntilVisible(find.text('NVIDIA 1'), -300, scrollable: _page);
    expect(find.textContaining('风扇 85'), findsOneWidget);
    await _tapVisible(tester, find.text('应用超频'));
    await tester.tap(find.widgetWithText(FilledButton, '应用'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已提交'), findsOneWidget);
    await _logout(tester);
  });

  testWidgets('BIOS: edit a setting, write it, it shows as pending', (tester) async {
    await _boot(tester);
    await _openRig(tester, 'rig-01');
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('BIOS'));
    await tester.pumpAndSettle();
    expect(find.text('NUMA nodes per socket'), findsOneWidget);

    await tester.tap(find.text('NUMA nodes per socket'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('NPS4'));
    await tester.pumpAndSettle();
    expect(find.textContaining('→  NPS4'), findsOneWidget);
    await tester.tap(find.text('保存（1）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存，不重启'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // The job runs on the controller; editing is locked until it reports back.
    expect(find.text('进行中…'), findsOneWidget);
    expect(find.textContaining('SUM 操作进行中'), findsOneWidget);
    await _logout(tester);
  });

  testWidgets('terminal opens with the extra key row; commands run on many machines', (tester) async {
    await _boot(tester);
    await _openRig(tester, 'rig-01');
    await tester.tap(find.byTooltip('终端'));
    await tester.pumpAndSettle();
    expect(find.text('终端 · rig-01'), findsOneWidget);
    expect(find.text('Esc'), findsOneWidget);
    await tester.tap(find.text('Ctrl'));
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('执行命令'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 台：rig-01'), findsOneWidget);
    await tester.tap(find.text('运行时间'));
    await tester.pump();
    await _tapVisible(tester, find.widgetWithText(FilledButton, '执行'));
    await tester.tap(find.widgetWithText(FilledButton, '执行').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('结果 ·'), findsOneWidget);
    await _logout(tester);
  });

  testWidgets('new screens lay out on a 320 pt phone at 130 % text size', (tester) async {
    await _boot(tester, size: const Size(320, 640), text: 1.3);
    await _openRig(tester, 'rig-03');
    for (final (menu, title) in [('显卡超频', '超频'), ('BIOS', 'BIOS · rig-03'), ('编辑矿机', '编辑 rig-03')]) {
      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(menu));
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('飞行表').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新建飞行表'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('更多').last);
    await tester.pumpAndSettle();
    for (final page in ['超频模板', '批量执行命令', '批量添加矿机']) {
      await tester.tap(find.text(page));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
    await _logout(tester);
  });
}
