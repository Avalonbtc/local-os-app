/// Hashrate with a unit that keeps 3–4 significant digits: `15.4 kH/s`.
String hashrate(double? hs) {
  if (hs == null) return '—';
  const units = ['H/s', 'kH/s', 'MH/s', 'GH/s', 'TH/s', 'PH/s'];
  var v = hs;
  var i = 0;
  while (v >= 1000 && i < units.length - 1) {
    v /= 1000;
    i++;
  }
  final digits = v >= 100 ? 0 : (v >= 10 ? 1 : 2);
  return '${v.toStringAsFixed(digits)} ${units[i]}';
}

(String, String) hashrateParts(double hs) {
  final text = hashrate(hs);
  final cut = text.indexOf(' ');
  return (text.substring(0, cut), text.substring(cut + 1));
}

String watts(double? w) {
  if (w == null) return '—';
  if (w >= 1000) return '${(w / 1000).toStringAsFixed(2)} kW';
  return '${w.round()} W';
}

String celsius(double? t) => t == null ? '—' : '${t.round()}°C';

/// `3d 4h`, `6h 12m`, `41m`.
String uptime(double? seconds) {
  if (seconds == null || seconds < 0) return '—';
  final s = seconds.floor();
  final d = s ~/ 86400, h = (s % 86400) ~/ 3600, m = (s % 3600) ~/ 60;
  if (d > 0) return '${d}d ${h}h';
  if (h > 0) return '${h}h ${m}m';
  return '${m}m';
}

String two(int v) => v.toString().padLeft(2, '0');

String clock(DateTime t) => '${two(t.hour)}:${two(t.minute)}';

/// `刚刚`, `3 分钟前`, `14:06`, `昨天 22:41`, `10-18 09:03`.
String ago(DateTime t, [DateTime? now]) {
  final n = now ?? DateTime.now();
  final local = t.toLocal();
  final diff = n.difference(local);
  if (diff.inSeconds < 60) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  final today = DateTime(n.year, n.month, n.day);
  if (!local.isBefore(today)) return clock(local);
  if (!local.isBefore(today.subtract(const Duration(days: 1)))) return '昨天 ${clock(local)}';
  return '${two(local.month)}-${two(local.day)} ${clock(local)}';
}

String dayLabel(DateTime t, [DateTime? now]) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final local = t.toLocal();
  if (!local.isBefore(today)) return '今天';
  if (!local.isBefore(today.subtract(const Duration(days: 1)))) return '昨天';
  return '${local.month} 月 ${local.day} 日';
}

String gib(double? bytes) => bytes == null ? '—' : (bytes / (1 << 30)).toStringAsFixed(1);
