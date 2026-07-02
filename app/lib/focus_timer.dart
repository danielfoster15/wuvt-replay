import 'dart:async';
import 'dart:ui' show IsolateNameServer;

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audio_service.dart';

/// Which kind of timed session is running.
enum SessionMode {
  /// Listen for N minutes, then stop the music. Counts only while the set is
  /// actually playing (real listening time).
  focus,

  /// Take a break for N minutes (wall-clock), then start the music — a cue
  /// that it's time to get back to work.
  breakTime,
}

/// Fires in a background isolate when a session's exact alarm goes off — even
/// in deep Doze, even if the app process is gone. If the app is alive, hand
/// off through the named port so it ends the session (resume/stop the music);
/// otherwise post a notification so the cue still arrives.
@pragma('vm:entry-point')
Future<void> sessionAlarmCallback(int id) async {
  final port = IsolateNameServer.lookupPortByName(FocusTimer.alarmPortName);
  if (port != null) {
    port.send(id);
    return;
  }
  // App process is dead: playback can't be controlled from here, but the cue
  // can still be delivered.
  final fln = FlutterLocalNotificationsPlugin();
  await fln.initialize(const InitializationSettings(
    android: AndroidInitializationSettings('ic_stat_wuvt'),
  ));
  final isBreak = id == FocusTimer.breakAlarmId;
  await fln.show(
    id,
    isBreak ? "Break's over" : 'Focus session finished',
    isBreak
        ? 'Open WUVT Replay to get back to the music.'
        : 'Nice work — the timer is done.',
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'app.wuvt.wuvt_replay.timer',
        'Focus & break timers',
        channelDescription: "Session-end cues when the app isn't running",
        importance: Importance.high,
        priority: Priority.high,
      ),
    ),
  );
}

/// Drives a [SessionMode] session.
///
/// Timing is deadline-based (a stored end [DateTime]), not tick-counting, so a
/// throttled timer can't drift the countdown — and each armed deadline is
/// mirrored by an exact OS alarm that fires even when Doze freezes Dart timers:
///
/// - Focus counts listening time: while the music plays there's an armed
///   deadline + alarm; pausing freezes the remaining time and cancels the
///   alarm; resuming re-arms both.
/// - Break is pure wall-clock: the deadline + alarm are set once at start.
///   The set plays muted+looping meanwhile (real audio keeps the app's
///   foreground service alive), then playback resumes audibly where it was.
///
/// A singleton like [PlayerService] so a session survives leaving the Now
/// Playing screen.
class FocusTimer extends ChangeNotifier {
  FocusTimer._();
  static final FocusTimer instance = FocusTimer._();

  static const minMinutes = 1;
  static const maxMinutes = 120;

  /// Named port the alarm isolate sends to (see [sessionAlarmCallback]).
  static const alarmPortName = 'wuvt_session_alarm';
  static const breakAlarmId = 424242;
  static const focusAlarmId = 424243;

  static const _prefModeKey = 'timer_mode';
  static const _prefMinutesKey = 'timer_minutes';

  SessionMode _mode = SessionMode.focus;
  int _minutes = 45; // chosen duration
  bool _running = false;
  DateTime? _endsAt; // deadline while actively counting down
  Duration? _pausedRemaining; // focus: frozen remaining while music is paused
  Timer? _ticker; // repaints the countdown; deadlines do the real timing
  int _breakResumeMs = 0; // set position to restore when a break ends
  StreamSubscription<bool>? _playingSub;

  SessionMode get mode => _mode;
  int get minutes => _minutes;
  bool get running => _running;

  Duration get remaining {
    if (!_running) return Duration(minutes: _minutes);
    final endsAt = _endsAt;
    if (endsAt != null) {
      final left = endsAt.difference(DateTime.now());
      return left.isNegative ? Duration.zero : left;
    }
    return _pausedRemaining ?? Duration(minutes: _minutes);
  }

  /// Restore the last-used mode and duration (called once at startup).
  Future<void> restore() async {
    final p = await SharedPreferences.getInstance();
    _minutes = (p.getInt(_prefMinutesKey) ?? _minutes)
        .clamp(minMinutes, maxMinutes);
    _mode = p.getString(_prefModeKey) == 'break'
        ? SessionMode.breakTime
        : SessionMode.focus;
    notifyListeners();
  }

  Future<void> _persistPrefs() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_prefMinutesKey, _minutes);
    await p.setString(
        _prefModeKey, _mode == SessionMode.breakTime ? 'break' : 'focus');
  }

  /// Switch between focus and break. Ignored while running.
  void setMode(SessionMode m) {
    if (_running || m == _mode) return;
    _mode = m;
    unawaited(_persistPrefs());
    notifyListeners();
  }

  /// Change the chosen duration. Ignored while running.
  void setMinutes(int m) {
    if (_running) return;
    _minutes = m.clamp(minMinutes, maxMinutes);
    unawaited(_persistPrefs());
    notifyListeners();
  }

  /// Start a session against the currently loaded set.
  void start() {
    if (_running) return;
    final svc = PlayerService.instance;
    if (svc.loadedSetId == null) return; // nothing to time against
    _running = true;
    if (_mode == SessionMode.focus) {
      _pausedRemaining = Duration(minutes: _minutes);
      _ensurePlayingSub();
      unawaited(svc.player.play());
      // If already playing, the stream may not emit a change — arm directly.
      if (svc.player.playing) _armFocusDeadline();
    } else {
      // Remember where we are, then play the set muted+looping for the break.
      _breakResumeMs = svc.globalPosition(svc.player.position).inMilliseconds;
      unawaited(svc.startMutedBreak());
      _endsAt = DateTime.now().add(Duration(minutes: _minutes));
      _scheduleAlarm(breakAlarmId, _endsAt!);
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    notifyListeners();
  }

  /// Cancel the session. A canceled break restores audible playback at the
  /// starting position (paused); focus leaves playback as-is.
  void cancel() {
    if (!_running) return;
    final wasBreak = _mode == SessionMode.breakTime;
    _stopSession();
    if (wasBreak) {
      unawaited(
          PlayerService.instance.endMutedBreak(_breakResumeMs, play: false));
    }
    notifyListeners();
  }

  /// Called on the main isolate when a session's exact alarm fires.
  void onAlarmFired() {
    if (!_running) return;
    if (_mode == SessionMode.breakTime) {
      _finishBreak();
    } else if (_endsAt != null) {
      _finishFocus(); // armed focus deadline reached; ignore stale alarms
    }
  }

  /// Track play/pause so focus sessions only count listening time.
  void _ensurePlayingSub() {
    _playingSub ??= PlayerService.instance.player.playingStream
        .listen(_onPlayingChanged);
  }

  void _onPlayingChanged(bool playing) {
    if (!_running || _mode != SessionMode.focus) return;
    if (playing && _endsAt == null) {
      _armFocusDeadline();
      notifyListeners();
    } else if (!playing && _endsAt != null) {
      _pausedRemaining = remaining; // freeze the countdown
      _endsAt = null;
      unawaited(AndroidAlarmManager.cancel(focusAlarmId));
      notifyListeners();
    }
  }

  void _armFocusDeadline() {
    _endsAt = DateTime.now()
        .add(_pausedRemaining ?? Duration(minutes: _minutes));
    _pausedRemaining = null;
    _scheduleAlarm(focusAlarmId, _endsAt!);
  }

  void _scheduleAlarm(int id, DateTime at) {
    unawaited(AndroidAlarmManager.oneShotAt(
      at,
      id,
      sessionAlarmCallback,
      exact: true,
      wakeup: true,
      alarmClock: true,
      rescheduleOnReboot: false,
    ));
  }

  void _tick() {
    if (!_running) return;
    final endsAt = _endsAt;
    if (endsAt == null) return; // focus holding while paused — nothing to do
    if (DateTime.now().isBefore(endsAt)) {
      notifyListeners(); // repaint the countdown
      return;
    }
    _mode == SessionMode.focus ? _finishFocus() : _finishBreak();
  }

  void _finishFocus() {
    _stopSession();
    unawaited(PlayerService.instance.player.pause());
    HapticFeedback.heavyImpact(); // a felt cue that the music stopped
    notifyListeners();
  }

  void _finishBreak() {
    _stopSession();
    // Break's over: unmute and resume audible playback where we left off.
    unawaited(
        PlayerService.instance.endMutedBreak(_breakResumeMs, play: true));
    HapticFeedback.heavyImpact(); // a felt cue that the music is back
    notifyListeners();
  }

  void _stopSession() {
    _running = false;
    _ticker?.cancel();
    _ticker = null;
    _endsAt = null;
    _pausedRemaining = null;
    // Cancel both: only one can be pending, and cancel is a cheap no-op.
    unawaited(AndroidAlarmManager.cancel(breakAlarmId));
    unawaited(AndroidAlarmManager.cancel(focusAlarmId));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _playingSub?.cancel();
    super.dispose();
  }
}
