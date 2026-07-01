import 'package:shared_preferences/shared_preferences.dart';

/// Persists the last whole-set playback position (ms) per set, so reopening a
/// set resumes where you left off.
class ResumeStore {
  ResumeStore._();
  static final ResumeStore instance = ResumeStore._();

  SharedPreferences? _prefs;
  Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  String _key(int setId) => 'resume_ms_$setId';

  Future<void> save(int setId, int positionMs) async {
    final p = await _p;
    await p.setInt(_key(setId), positionMs);
  }

  Future<int?> load(int setId) async {
    final p = await _p;
    return p.getInt(_key(setId));
  }

  Future<void> clear(int setId) async {
    final p = await _p;
    await p.remove(_key(setId));
  }
}
