import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/client.dart';
import 'monitor.dart';

/// Who is signed in, and to which controller. Credentials live in the platform keychain /
/// keystore, never in plain preferences.
class SessionController extends ChangeNotifier {
  SessionController({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'rigdeck.credentials';
  static const _lastServerKey = 'rigdeck.last_server';
  final FlutterSecureStorage _storage;

  Backend? backend;
  String user = '';
  String server = '';
  bool restoring = true;
  String lastServer = '';

  /// Saved credentials, also read by the background monitor's own isolate.
  static Future<Credentials?> readStored([FlutterSecureStorage storage = const FlutterSecureStorage()]) async {
    final raw = await storage.read(key: _key);
    return raw == null ? null : Credentials.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> restore() async {
    try {
      lastServer = await _storage.read(key: _lastServerKey) ?? '';
      final raw = await _storage.read(key: _key);
      final creds = raw == null ? null : Credentials.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      if (creds != null) _use(creds);
    } catch (_) {
      // A keystore reset after an OS upgrade: start at the login page.
    }
    restoring = false;
    notifyListeners();
  }

  Future<void> loginWithPassword(String serverInput, String name, String password) async {
    final s = normalizeServer(serverInput);
    await _save(await HttpBackend.login(s, name.trim(), password));
  }

  Future<void> loginWithToken(String serverInput, String token) async {
    final s = normalizeServer(serverInput);
    await _save(await HttpBackend.withToken(s, token.trim()));
  }

  /// Tests sign in to an in-memory backend.
  @visibleForTesting
  void useBackend(Backend b, {String user = '测试', String server = '测试'}) {
    backend?.close();
    backend = b;
    this.user = user;
    this.server = server;
    notifyListeners();
  }

  Future<void> logout() async {
    final b = backend;
    if (b is HttpBackend && b.credentials.cookie != null) {
      try {
        await b.send('POST', '/api/v1/logout');
      } catch (_) {
        // Signing out locally must work even when the controller is unreachable.
      }
    }
    b?.close();
    backend = null;
    notifyListeners();
    // Signed out: nothing left to monitor.
    await BackgroundMonitor.stop();
    try {
      await _storage.delete(key: _key);
    } catch (_) {
      // Nothing stored or the keystore is unavailable: already signed out in memory.
    }
  }

  Future<void> _save(Credentials c) async {
    await _storage.write(key: _key, value: jsonEncode(c.toJson()));
    await _storage.write(key: _lastServerKey, value: c.server);
    lastServer = c.server;
    _use(c);
    notifyListeners();
  }

  void _use(Credentials c) {
    backend?.close();
    backend = HttpBackend(c, onUnauthorized: _expired);
    user = c.user;
    server = c.server;
  }

  void _expired() {
    // Called from inside a request; leave the current frame before tearing the tree down.
    Future.microtask(logout);
  }
}
