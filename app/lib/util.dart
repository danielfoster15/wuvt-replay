import 'package:intl/intl.dart';

import 'models.dart';

final _dateFmt = DateFormat('EEE, MMM d, y');
final _timeFmt = DateFormat('h:mm a');

/// "Fri, May 26 · 4:12 AM" for a set's start time (local).
String setTitle(DateTime? start) {
  if (start == null) return 'Unknown date';
  return '${_dateFmt.format(start)} · ${_timeFmt.format(start)}';
}

String setDate(DateTime? start) =>
    start == null ? 'Unknown date' : _dateFmt.format(start);

String setTime(DateTime? start) =>
    start == null ? '' : _timeFmt.format(start);

/// "1:49:49" or "4:35" from a Duration.
String fmtDuration(Duration d) {
  final secs = d.inSeconds;
  final h = secs ~/ 3600;
  final m = (secs % 3600) ~/ 60;
  final s = secs % 60;
  final mm = m.toString().padLeft(h > 0 ? 2 : 1, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

/// Human duration for a set list row, e.g. "1h 50m".
String fmtSetLength(int? durationSec) {
  if (durationSec == null || durationSec <= 0) return '';
  final h = durationSec ~/ 3600;
  final m = (durationSec % 3600) ~/ 60;
  if (h > 0) return '${h}h ${m}m';
  return '${m}m';
}

/// Index of the track currently playing given elapsed time into the set,
/// or -1 if none yet. Tracks must be in chronological order.
int currentTrackIndex(List<TrackLog> tracks, Duration elapsed) {
  final ms = elapsed.inMilliseconds;
  int idx = -1;
  for (int i = 0; i < tracks.length; i++) {
    final off = tracks[i].offsetMs;
    if (off != null && off <= ms) {
      idx = i;
    } else if (off != null && off > ms) {
      break;
    }
  }
  return idx;
}
