import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rigdeck_app/data/session.dart';
import 'package:rigdeck_app/main.dart';

import '../test/support/fake_backend.dart';

/// Frame timing on a real engine (profile mode):
/// `flutter drive --profile --driver=test_driver/perf_driver.dart --target=integration_test/perf_test.dart -d <device>`
/// Writes build/scroll_1000.timeline_summary.json (frame build/raster percentiles, missed frames).
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Render every vsync like a user's device does, so the timeline holds every frame.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('1 000 machines: scroll, switch tabs, open details', (tester) async {
    final session = SessionController();
    await tester.pumpWidget(RigDeckApp(session: session));
    await session.restore();
    session.useBackend(FakeBackend(machines: 1000));
    // Real clock: wait for the first refresh (data built on a background isolate).
    for (var i = 0; i < 50 && find.text('需要处理').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.tap(find.text('矿机').last);
    await tester.pumpAndSettle();
    expect(find.text('rig-01'), findsOneWidget);

    final list = find.byType(Scrollable).last;
    await binding.traceAction(() async {
      for (var i = 0; i < 6; i++) {
        await tester.fling(list, const Offset(0, -900), 6000);
        await tester.pumpAndSettle();
      }
      for (var i = 0; i < 6; i++) {
        await tester.fling(list, const Offset(0, 900), 6000);
        await tester.pumpAndSettle();
      }
      for (final tab in ['飞行表', '通知', '更多', '总览', '矿机']) {
        await tester.tap(find.text(tab).last);
        await tester.pumpAndSettle();
      }
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('rig-07'));
        await tester.pumpAndSettle();
        for (final tab in ['矿工', '统计', '活动', '概述']) {
          await tester.tap(find.widgetWithText(Tab, tab));
          await tester.pumpAndSettle();
        }
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
    }, reportKey: 'scroll_1000');
  });
}
