import 'package:flutter_test/flutter_test.dart';
import 'package:rigdeck_app/api/forms.dart';

void main() {
  group('batch import targets', () {
    test('range, CIDR and explicit lines, named from the template', () {
      final rows = parseTargets('192.168.1.10-12\n# comment\n10.0.0.0/30\nrig-07,192.168.1.17,2222,admin', 'rig-{last}');
      expect(rows.map((r) => r.name), ['rig-10', 'rig-11', 'rig-12', 'rig-1', 'rig-2', 'rig-07']);
      expect(rows.map((r) => r.host), ['192.168.1.10', '192.168.1.11', '192.168.1.12', '10.0.0.1', '10.0.0.2', '192.168.1.17']);
      expect(rows.last.port, 2222);
      expect(rows.last.username, 'admin');
      expect(rows.first.port, 22);
      expect(rows.first.username, 'root');
    });

    test('template variables', () {
      final rows = parseTargets('192.168.3.7-8', 'epyc-{n:3}-{last2}-{ip}');
      expect(rows.map((r) => r.name), ['epyc-001-3-7-192-168-3-7', 'epyc-002-3-8-192-168-3-8']);
    });

    test('full end address and full-width comma', () {
      expect(expandHosts('10.0.0.254-10.0.1.1'), ['10.0.0.254', '10.0.0.255', '10.0.1.0', '10.0.1.1']);
      expect(parseTargets('a，10.1.1.1', 'x').single.name, 'a');
    });

    test('rejects what the web console rejects', () {
      expect(() => expandHosts('10.0.0.0/16'), throwsFormatException);
      expect(() => expandHosts('10.0.0.9-3'), throwsFormatException);
      expect(() => expandHosts('10.0.0.0-10.0.2.0'), throwsFormatException);
      expect(() => expandHosts('bad host!'), throwsFormatException);
      expect(() => parseTargets('a,10.0.0.1,70000', 'x'), throwsFormatException);
    });
  });

  group('overclock form', () {
    test('text ↔ config round trip, HiveOS style', () {
      final t = OcText()
        ..fields['nvidia']!['clock'] = '1500 1450'
        ..fields['nvidia']!['mem'] = '2400'
        ..fields['amd']!['core_clock'] = '  '
        ..runningDelay = '30';
      final config = t.toConfig();
      expect(config, {
        'nvidia': {'clock': [1500, 1450], 'mem': [2400], 'running_delay': 30},
      });
      final back = OcText.fromConfig(config);
      expect(back.fields['nvidia']!['clock'], '1500 1450');
      expect(back.runningDelay, '30');
      expect(back.toConfig(), config);
    });

    test('names the field that is not a list of integers', () {
      final t = OcText()..fields['amd']!['pl'] = '120 abc';
      expect(() => t.toConfig(), throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('AMD 功耗墙'))));
    });

    test('per-card plan repeats the last value', () {
      final t = OcText()
        ..fields['nvidia']!['clock'] = '1500 1450'
        ..fields['nvidia']!['fan'] = '70';
      expect(t.plannedFor('nvidia', 0), '核心 1500 · 风扇 70');
      expect(t.plannedFor('nvidia', 3), '核心 1450 · 风扇 70');
      expect(t.plannedFor('amd', 0), '');
    });
  });

  group('miners', () {
    test('built-in adapter at its newest or a chosen release', () {
      final a = MinerAdapter.fromJson({
        'id': 'xmrig',
        'name': 'XMRig',
        'releases': [
          {'version': '6.22.2', 'url': 'u2', 'executable': 'x2', 'sha256': 'abc'},
          {'version': '6.21.0', 'url': 'u1', 'executable': 'x1', 'sha256': null},
        ],
      });
      expect(minerSpec(a), {'adapter': 'xmrig', 'name': 'XMRig', 'version': '6.22.2', 'url': 'u2', 'executable': 'x2', 'sha256': 'abc'});
      expect(minerSpec(a, a.releases.last), {'adapter': 'xmrig', 'name': 'XMRig', 'version': '6.21.0', 'url': 'u1', 'executable': 'x1'});
    });

    test('custom package name from its URL', () {
      expect(inferMinerName('https://example.com/dl/lolminer-1.88.tar.gz'), 'lolminer');
      expect(inferMinerName('https://example.com/dl/my_miner_v2.1-linux.zip'), 'my_miner');
      expect(inferMinerName('not a url'), 'not a url');
    });
  });
}
