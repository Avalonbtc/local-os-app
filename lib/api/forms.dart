// Pure helpers behind the edit forms (batch import, overclock), kept free of Flutter so they
// can be unit-tested and match the web console's behaviour exactly.
import 'models.dart';

/// One machine to import: name, SSH address and login.
class ImportTarget {
  const ImportTarget(this.name, this.host, this.port, this.username);
  final String name;
  final String host;
  final int port;
  final String username;
}

const maxImport = 256;

/// Batch import lines, as in the web console:
///   `192.168.1.10-60`            range (names from [template])
///   `192.168.1.0/24`             CIDR (/22–/32)
///   `rig-07,192.168.1.17[,port[,user]]`  explicit name
/// Template variables: `{ip}` 192-168-1-17, `{last}` 17, `{last2}` 1-17, `{n}` / `{n:3}` index.
List<ImportTarget> parseTargets(String text, String template, {int port = 22, String username = 'root'}) {
  final rows = <ImportTarget>[];
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final line = raw.replaceAll(RegExp(r'#.*'), '').trim();
    if (line.isEmpty) continue;
    final fields = line.split(RegExp(r'[,\t;，]')).map((f) => f.trim()).toList();
    if (fields.length >= 2) {
      final p = fields.length > 2 && fields[2].isNotEmpty ? int.tryParse(fields[2]) : port;
      if (p == null || p < 1 || p > 65535) throw FormatException('${fields[0]}：端口无效');
      rows.add(ImportTarget(fields[0], expandHosts(fields[1]).first, p,
          fields.length > 3 && fields[3].isNotEmpty ? fields[3] : username));
      continue;
    }
    for (final host in expandHosts(fields[0])) {
      final parts = host.split('.');
      final index = rows.length + 1;
      final name = template
          .replaceAll('{ip}', host.replaceAll('.', '-'))
          .replaceAll('{last2}', parts.length < 2 ? host : parts.sublist(parts.length - 2).join('-'))
          .replaceAll('{last}', parts.last)
          .replaceAllMapped(
              RegExp(r'\{n(?::(\d+))?\}'), (m) => '$index'.padLeft(int.tryParse(m.group(1) ?? '') ?? 0, '0'));
      rows.add(ImportTarget(name, host, port, username));
    }
    if (rows.length > maxImport) throw const FormatException('一次最多 $maxImport 台');
  }
  return rows;
}

List<int>? _octets(String s) {
  final parts = s.trim().split('.');
  if (parts.length != 4) return null;
  final n = parts.map(int.tryParse).toList();
  return n.every((x) => x != null && x >= 0 && x <= 255) ? n.cast<int>() : null;
}

int _ipNumber(List<int> o) => ((o[0] << 24) | (o[1] << 16) | (o[2] << 8) | o[3]) & 0xFFFFFFFF;
String _ipText(int n) => [n >> 24 & 255, n >> 16 & 255, n >> 8 & 255, n & 255].join('.');

List<String> expandHosts(String token) {
  final text = token.trim();
  final cidr = RegExp(r'^(.+)/(\d{1,2})$').firstMatch(text);
  if (cidr != null) {
    final base = _octets(cidr.group(1)!);
    final bits = int.parse(cidr.group(2)!);
    if (base == null || bits < 22 || bits > 32) throw FormatException('$text：CIDR 只支持 /22 到 /32');
    final size = 1 << (32 - bits);
    final start = _ipNumber(base) & ~(size - 1) & 0xFFFFFFFF;
    return [
      for (var n = start; n < start + size; n++)
        if (size <= 2 || (n != start && n != start + size - 1)) _ipText(n),
    ];
  }
  final range = RegExp(r'^([\d.]+)\s*-\s*([\d.]+)$').firstMatch(text);
  if (range != null) {
    final first = _octets(range.group(1)!);
    if (first == null) throw FormatException('$text：起始地址无效');
    final endText = range.group(2)!;
    final last = endText.contains('.') ? _octets(endText) : [...first.take(3), int.tryParse(endText) ?? 999];
    if (last == null || last[3] > 255) throw FormatException('$text：结束地址无效');
    final a = _ipNumber(first), b = _ipNumber(last);
    if (b < a) throw FormatException('$text：结束地址小于起始地址');
    if (b - a >= maxImport) throw FormatException('$text：一次最多 $maxImport 台');
    return [for (var n = a; n <= b; n++) _ipText(n)];
  }
  if (!RegExp(r'^[A-Za-z0-9.:-]+$').hasMatch(text)) throw FormatException('$text：地址无效');
  return [text];
}

/// HiveOS overclock fields: one number per card separated by spaces; a single number applies
/// to every card. `key` is the controller's GpuOcConfig field.
class OcField {
  const OcField(this.key, this.label, this.help, {this.unit = '', this.advanced = false});
  final String key;
  final String label;
  final String help;
  final String unit;
  final bool advanced;
}

const ocVendors = ['nvidia', 'amd'];
const ocVendorName = {'nvidia': 'NVIDIA', 'amd': 'AMD'};

const ocFields = <String, List<OcField>>{
  'nvidia': [
    OcField('clock', '核心', '核心偏移；大于 500 为锁定核心频率（如 1500）', unit: 'MHz'),
    OcField('mem', '显存', '显存偏移，HiveOS/Linux 数值（Windows Afterburner 的 2 倍）', unit: 'MHz'),
    OcField('plimit', '功耗墙', '0 = 驱动默认', unit: 'W'),
    OcField('fan', '风扇', '0 = 自动', unit: '%'),
  ],
  'amd': [
    OcField('core_clock', '核心频率', '0 = 不修改', unit: 'MHz'),
    OcField('core_state', '核心状态', 'DPM 状态，0 = 自动'),
    OcField('core_vddc', '核心电压', '0 = 不修改；RDNA2/3 不支持绝对电压', unit: 'mV'),
    OcField('mem_clock', '显存频率', '0 = 不修改', unit: 'MHz'),
    OcField('mem_state', '显存状态', '0 = 自动'),
    OcField('fan', '风扇', '0 = 自动', unit: '%'),
    OcField('pl', '功耗墙', '0 = 驱动默认', unit: 'W'),
    OcField('ref', 'REF', '需要矿机上安装 amdmemtweak'),
    OcField('mvdd', 'MVDD', '需要改 PowerPlay 表，本版本仅保存不写入', unit: 'mV', advanced: true),
    OcField('vddci', 'VDDCI', '需要改 PowerPlay 表，本版本仅保存不写入', unit: 'mV', advanced: true),
    OcField('soc_clk', 'SOC 频率', '需要改 PowerPlay 表，本版本仅保存不写入', unit: 'MHz', advanced: true),
    OcField('soc_vdd_max', 'SOC 电压', '需要改 PowerPlay 表，本版本仅保存不写入', unit: 'mV', advanced: true),
  ],
};

List<int> parseOcList(String text) => [
      for (final p in text.trim().split(RegExp(r'[\s,]+')))
        if (p.isNotEmpty)
          RegExp(r'^-?\d+$').hasMatch(p) ? int.parse(p) : throw FormatException('“$p” 不是整数'),
    ];

/// The overclock form as typed: per vendor, per field, plus NVIDIA's running delay.
class OcText {
  OcText() : fields = {for (final v in ocVendors) v: <String, String>{}};
  final Map<String, Map<String, String>> fields;
  String runningDelay = '';

  factory OcText.fromConfig(Map<String, dynamic> config) {
    final text = OcText();
    for (final vendor in ocVendors) {
      final section = asMap(config[vendor]);
      for (final f in ocFields[vendor]!) {
        final values = asList(section[f.key]);
        if (values.isNotEmpty) text.fields[vendor]![f.key] = values.join(' ');
      }
    }
    final delay = asNum(asMap(config['nvidia'])['running_delay']);
    if (delay != null && delay > 0) text.runningDelay = '${delay.toInt()}';
    return text;
  }

  /// GpuOcConfig; throws [FormatException] naming the field that is not a list of integers.
  Map<String, dynamic> toConfig() {
    final config = <String, dynamic>{};
    for (final vendor in ocVendors) {
      final section = <String, dynamic>{};
      for (final f in ocFields[vendor]!) {
        try {
          final values = parseOcList(fields[vendor]![f.key] ?? '');
          if (values.isNotEmpty) section[f.key] = values;
        } on FormatException catch (e) {
          throw FormatException('${ocVendorName[vendor]} ${f.label}：${e.message}');
        }
      }
      if (vendor == 'nvidia' && runningDelay.trim().isNotEmpty) {
        final d = parseOcList(runningDelay);
        if (d.isNotEmpty) section['running_delay'] = d.first;
      }
      if (section.isNotEmpty) config[vendor] = section;
    }
    return config;
  }

  /// What a card at [index] of [vendor] will get, e.g. `核心 100 · 显存 1000`.
  String plannedFor(String vendor, int index) {
    final parts = <String>[];
    for (final f in ocFields[vendor]!) {
      final List<int> values;
      try {
        values = parseOcList(fields[vendor]![f.key] ?? '');
      } on FormatException {
        continue;
      }
      if (values.isEmpty) continue;
      final v = index < values.length ? values[index] : values.last;
      parts.add('${f.label} $v');
    }
    return parts.join(' · ');
  }
}

/// Miner adapters the flight sheet editor offers (`GET /api/v1/adapters`).
class MinerRelease {
  const MinerRelease(this.version, this.url, this.executable, this.sha256);
  final String version;
  final String url;
  final String executable;
  final String? sha256;
}

class MinerAdapter {
  const MinerAdapter(this.id, this.name, this.releases);
  final String id;
  final String name;
  final List<MinerRelease> releases;
  factory MinerAdapter.fromJson(Map<String, dynamic> j) => MinerAdapter(
        asStr(j['id']),
        asStr(j['name'], asStr(j['id'])),
        [
          for (final r in asList(j['releases']).map(asMap))
            MinerRelease(asStr(r['version']), asStr(r['url']), asStr(r['executable']), r['sha256'] as String?),
        ],
      );
}

const customAdapter = 'hive-custom';
const defaultAlgorithm = {'xmrig': 'rx/0', 'srbminer': 'randomx', 'cpuminer-opt': ''};
const algorithms = ['rx/0', 'randomx', 'rx/wow', 'cn/gpu', 'ghostrider', 'yespower', 'argon2d', 'sha256', 'scrypt'];

/// Miner spec for a built-in adapter at [release] (newest when null), as the web editor stores it.
Map<String, dynamic> minerSpec(MinerAdapter a, [MinerRelease? release]) {
  final r = release ?? (a.releases.isEmpty ? null : a.releases.first);
  return {
    'adapter': a.id,
    'name': a.name,
    'version': r?.version ?? '',
    'url': r?.url ?? '',
    'executable': r?.executable ?? '',
    'sha256': ?r?.sha256,
  };
}

/// Guess a custom package's miner name from its URL: `.../lolminer-1.2.tar.gz` → `lolminer`.
String inferMinerName(String url) {
  final file = Uri.tryParse(url)?.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => '') ?? '';
  return Uri.decodeComponent(file)
      .replaceAll(RegExp(r'\.(tar\.(gz|xz|bz2|zst)|tgz|txz|zip)$', caseSensitive: false), '')
      .replaceAll(RegExp(r'[-_]v?\d+(?:\.\d+)*(?:[-_.].*)?$', caseSensitive: false), '');
}
