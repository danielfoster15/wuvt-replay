import 'package:shared_preferences/shared_preferences.dart';

/// Compile-time default backend URL. Override at build/run time:
///
///   flutter run --dart-define=BACKEND_URL=http://homecloud.your-tailnet.ts.net:8080
///
/// Defaults to localhost for desktop/web development. Note that on an Android
/// emulator the host machine is reachable at 10.0.2.2, and a physical phone
/// must use a LAN IP or a tailnet address.
const String defaultBackendUrl = String.fromEnvironment(
  'BACKEND_URL',
  defaultValue: 'http://localhost:8077',
);

/// The backend URL actually in effect: a user-set override (persisted, editable
/// from the DJ list's settings action) or, absent that, [defaultBackendUrl].
/// Lets the app move between LAN / tailnet / future hosted URLs without a
/// rebuild.
class BackendConfig {
  BackendConfig._();
  static final BackendConfig instance = BackendConfig._();

  static const _prefKey = 'backend_url_override';

  String? _override;

  String get url => _override ?? defaultBackendUrl;
  bool get isOverridden => _override != null;

  /// Load the persisted override (called once at startup, before first use).
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _override = p.getString(_prefKey);
  }

  /// Set (or, with null/empty, clear) the override. Trailing slashes dropped.
  Future<void> setOverride(String? url) async {
    final p = await SharedPreferences.getInstance();
    final trimmed = url?.trim().replaceAll(RegExp(r'/+$'), '');
    if (trimmed == null || trimmed.isEmpty) {
      _override = null;
      await p.remove(_prefKey);
    } else {
      _override = trimmed;
      await p.setString(_prefKey, trimmed);
    }
  }
}
