import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import 'audio_service.dart';

/// Which kind of timed session is running.
enum SessionMode {
  /// Listen for N minutes, then stop the music. Counts down only while the set
  /// is actually playing (real listening time).
  focus,

  /// Take a break for N minutes, then start the music — a cue that it's time to
  /// get back to work.
  breakTime,
}

/// Drives a [SessionMode] session.
///
/// - Focus plays the set now and stops it after N minutes of *listening* (the
///   countdown holds while the music is paused).
/// - Break prepends N minutes of silence before the set (via
///   [PlayerService.loadSet]'s `leadInSilence`), so the audio engine starts the
///   music on its own when the break ends. That's reliable even locked/
///   backgrounded, since it's driven by active playback rather than a timer.
///
/// A singleton like [PlayerService] so the countdown survives leaving the Now
/// Playing screen.
class FocusTimer extends ChangeNotifier {
  FocusTimer._();
  static final FocusTimer instance = FocusTimer._();

  static const minMinutes = 1;
  static const maxMinutes = 120;

  SessionMode _mode = SessionMode.focus;
  int _minutes = 45; // chosen duration
  Duration _remaining = const Duration(minutes: 45);
  bool _running = false;
  Timer? _ticker;
  int _breakResumeMs = 0; // set position to restore when a break ends

  SessionMode get mode => _mode;
  int get minutes => _minutes;
  Duration get remaining => _remaining;
  bool get running => _running;

  /// Switch between focus and break. Ignored while running.
  void setMode(SessionMode m) {
    if (_running || m == _mode) return;
    _mode = m;
    notifyListeners();
  }

  /// Change the chosen duration. Ignored while running.
  void setMinutes(int m) {
    if (_running) return;
    _minutes = m.clamp(minMinutes, maxMinutes);
    _remaining = Duration(minutes: _minutes);
    notifyListeners();
  }

  /// Start counting down.
  void start() {
    if (_running) return;
    _running = true;
    _remaining = Duration(minutes: _minutes);
    final svc = PlayerService.instance;
    if (_mode == SessionMode.focus) {
      if (svc.loadedSetId != null) unawaited(svc.player.play());
    } else if (svc.loadedSetId != null) {
      // Remember where we are, then play the set muted+looping for the break.
      _breakResumeMs = svc.globalPosition(svc.player.position).inMilliseconds;
      unawaited(svc.startMutedBreak());
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    notifyListeners();
  }

  /// Cancel the timer. A canceled break restores audible playback at the
  /// starting position (paused); focus leaves playback as-is.
  void cancel() {
    if (!_running) return;
    final wasBreak = _mode == SessionMode.breakTime;
    _stopTicker();
    if (wasBreak) {
      unawaited(PlayerService.instance.endMutedBreak(_breakResumeMs, play: false));
    }
    notifyListeners();
  }

  void _tick() {
    // Both modes count playing time (the break plays silence to stay alive):
    // hold the countdown whenever playback is paused.
    if (!PlayerService.instance.player.playing) return;
    final next = _remaining - const Duration(seconds: 1);
    if (next > Duration.zero) {
      _remaining = next;
      notifyListeners();
      return;
    }
    // Reached zero.
    if (_mode == SessionMode.focus) {
      _finishFocus();
    } else {
      _finishBreak();
    }
  }

  void _finishFocus() {
    _stopTicker();
    unawaited(PlayerService.instance.player.pause());
    HapticFeedback.heavyImpact(); // a felt cue that the music stopped
    notifyListeners();
  }

  void _finishBreak() {
    _stopTicker();
    // Break's over: unmute and resume audible playback where we left off.
    unawaited(PlayerService.instance.endMutedBreak(_breakResumeMs, play: true));
    HapticFeedback.heavyImpact(); // a felt cue that the music is back
    notifyListeners();
  }

  void _stopTicker() {
    _running = false;
    _ticker?.cancel();
    _ticker = null;
    _remaining = Duration(minutes: _minutes);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
