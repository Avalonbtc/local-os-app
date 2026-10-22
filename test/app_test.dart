import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rigdeck_app/data/demo_backend.dart';
import 'package:rigdeck_app/data/session.dart';
import 'package:rigdeck_app/data/stores.dart';
import 'package:rigdeck_app/main.dart';

/// Walks the demo farm the way a user would: overview → machines → filter → detail → back.
void main() {
  testWidgets('demo farm: overview, machine list, filters and machine detail', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final session = SessionController();
    await tester.runAsync(session.restore);
    await tester.pumpWidget(RigDeckApp(session: session));
    await tester.pump();
    expect(find.text('先看看演示数据'), findsOneWidget);

    // Same screens and parsing as the app's demo, generated inline: the fake test clock never
    // delivers background-isolate replies.
    FleetStore.offThread = false;
    session.startDemo(DemoBackend(latency: Duration.zero, background: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('矿场总览 · 演示'), findsOneWidget);
    expect(find.text('需要处理'), findsOneWidget);

    await tester.tap(find.text('矿机').last);
    await tester.pumpAndSettle();
    expect(find.text('rig-01'), findsOneWidget);
    expect(find.text('矿池离线 1'), findsOneWidget);

    await tester.tap(find.text('矿池离线 1'));
    await tester.pumpAndSettle();
    expect(find.text('rig-07'), findsOneWidget);
    expect(find.text('rig-01'), findsNothing);

    await tester.tap(find.text('rig-07'));
    await tester.pumpAndSettle();
    expect(find.textContaining('矿池看不到这台矿机'), findsOneWidget);
    expect(find.text('概述'), findsOneWidget);

    await tester.tap(find.widgetWithText(Tab, '矿工'));
    await tester.pumpAndSettle();
    expect(find.textContaining('XMRig'), findsWidgets);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('rig-07'), findsOneWidget);

    // Leave no timers running past the test.
    await tester.tap(find.text('更多').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('退出演示'));
    await tester.pumpAndSettle();
    expect(find.text('先看看演示数据'), findsOneWidget);
  });

  // Small phones and large system fonts must not overflow (Flutter reports overflow as an error).
  testWidgets('every main screen lays out on a 320 pt phone at 130 % text size', (tester) async {
    tester.view.physicalSize = const Size(320 * 2, 640 * 2);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final session = SessionController();
    await tester.runAsync(session.restore);
    await tester.pumpWidget(RigDeckApp(session: session));
    await tester.pump();
    FleetStore.offThread = false;
    session.startDemo(DemoBackend(latency: Duration.zero, background: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    for (final tab in ['矿机', '飞行表', '通知', '更多', '总览']) {
      await tester.tap(find.text(tab).last);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('矿机').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('rig-07'), 200, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('rig-07'));
    await tester.pumpAndSettle();
    for (final tab in ['矿工', '统计', '活动', '电源', '概述']) {
      await tester.tap(find.widgetWithText(Tab, tab));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
    }
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('更多').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('退出演示'));
    await tester.pumpAndSettle();
  });
}
