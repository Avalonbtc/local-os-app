import 'package:flutter_test/flutter_test.dart';
import 'package:rigdeck_app/api/models.dart';
import 'package:rigdeck_app/data/demo_backend.dart';
import 'package:rigdeck_app/data/stores.dart';

void main() {
  test('only alerts raised after the app opened are announced, once each', () async {
    final demo = DemoBackend(latency: Duration.zero, background: false);
    final store = AlertsStore(demo);
    final announced = <StatusAlert>[];
    store.onNew = announced.addAll;

    await store.refresh();
    expect(store.items, isNotEmpty);
    expect(announced, isEmpty, reason: 'history present at start is not re-announced');

    demo.simulateAlert();
    await store.refresh();
    expect(announced.single.offline, isTrue);
    expect(announced.single.machineName, 'rig-05');
    expect(store.unread, 1);

    await store.refresh();
    expect(announced, hasLength(1), reason: 'the same alert is not announced twice');

    demo.simulateAlert();
    await store.refresh();
    expect(announced.last.offline, isFalse);
    expect(announced.last.title, '矿机恢复在线');
    store.markRead();
    expect(store.unread, 0);
    store.dispose();
  });

  test('alerts after the background monitor mark are announced when the app opens', () async {
    final demo = DemoBackend(latency: Duration.zero, background: false);
    demo.simulateAlert(); // id 100, raised while the app was closed
    final store = AlertsStore(demo)..announceAfter(6);
    final announced = <StatusAlert>[];
    store.onNew = announced.addAll;
    await store.refresh();
    expect(announced.map((a) => a.id), [100]);
    store.dispose();
  });
}
