import 'package:flutter/material.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../data/session.dart';
import '../data/stores.dart';
import '../theme.dart';
import 'alerts_page.dart';
import 'flights_page.dart';
import 'machine_detail_page.dart';
import 'machines_page.dart';
import 'more_page.dart';
import 'overview_page.dart';
import 'widgets.dart';

class Shell extends StatefulWidget {
  const Shell({super.key, required this.session, required this.backend});
  final SessionController session;
  final Backend backend;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  late final FleetStore _fleet = FleetStore(widget.backend);
  late final AlertsStore _alerts = AlertsStore(widget.backend);
  late final AppLifecycleListener _lifecycle;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _fleet.start();
    _alerts
      ..onNew = _announce
      ..start();
    // No polling (and no battery or radio use) while the app is in the background.
    _lifecycle = AppLifecycleListener(
      onResume: () {
        _fleet.start();
        _alerts.start();
      },
      onHide: () {
        _fleet.stop();
        _alerts.stop();
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _fleet.dispose();
    _alerts.dispose();
    super.dispose();
  }

  void _announce(List<StatusAlert> fresh) {
    if (!mounted) return;
    // The app-wide messenger: the notice shows over whichever page is open.
    final m = ScaffoldMessenger.of(context);
    final a = fresh.first;
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(
      backgroundColor: a.offline ? C.badBg : C.okBg,
      duration: Duration(seconds: a.offline ? 8 : 4),
      content: Text(
        fresh.length == 1 ? '${a.title} · ${a.machineName}\n${a.message}' : '${fresh.length} 条新通知：${a.title} · ${a.machineName} 等',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: a.offline ? C.badText : C.okText, height: 1.4),
      ),
      action: SnackBarAction(
        label: '查看',
        onPressed: () => setState(() => _tab = 3),
      ),
    ));
  }

  void _select(int index) {
    if (index == 3) _alerts.markRead();
    setState(() => _tab = index);
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      session: widget.session,
      backend: widget.backend,
      fleet: _fleet,
      alerts: _alerts,
      child: Scaffold(
          // Every tab stays mounted: switching tabs never rebuilds lists or loses scroll position.
          body: IndexedStack(
            index: _tab,
            children: [
              OverviewPage(onOpenTab: _select),
              const MachinesPage(),
              const FlightsPage(),
              const AlertsPage(),
              const MorePage(),
            ],
          ),
          bottomNavigationBar: ListenableBuilder(
            listenable: _alerts,
            builder: (context, _) => NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: _select,
              destinations: [
                const NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view_rounded), label: '总览'),
                const NavigationDestination(icon: Icon(Icons.dns_outlined), selectedIcon: Icon(Icons.dns), label: '矿机'),
                const NavigationDestination(icon: Icon(Icons.rocket_launch_outlined), selectedIcon: Icon(Icons.rocket_launch), label: '飞行表'),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: _alerts.unread > 0,
                    label: Text('${_alerts.unread}'),
                    child: const Icon(Icons.notifications_none_rounded),
                  ),
                  selectedIcon: const Icon(Icons.notifications_rounded),
                  label: '通知',
                ),
                const NavigationDestination(icon: Icon(Icons.more_horiz), label: '更多'),
              ],
            ),
          ),
      ),
    );
  }
}

void openMachine(BuildContext context, String machineId) => push(context, MachineDetailPage(machineId: machineId));
