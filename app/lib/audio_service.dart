import 'dart:async';

import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'models.dart';
import 'util.dart';

/// Wraps a single [AudioPlayer] and knows how to load a DJ set as a chain of
/// trimmed hour-files, plus how to translate between per-segment and whole-set
/// positions.
class PlayerService {
  PlayerService._();
  static final PlayerService instance = PlayerService._();

  final AudioPlayer player = AudioPlayer();

  int? loadedSetId;
  SetDetail? loadedSet;
  List<int> _cumulativeMs = const [];
  int _totalMs = 0;

  Duration get total => Duration(milliseconds: _totalMs);

  /// Build the clip+concatenate source for [set] and load it (paused).
  Future<void> loadSet(SetDetail set) async {
    loadedSetId = set.id;
    loadedSet = set;

    _cumulativeMs = [];
    var acc = 0;
    for (final seg in set.segments) {
      _cumulativeMs.add(acc);
      acc += seg.durationMs;
    }
    _totalMs = acc;

    final mediaItem = MediaItem(
      id: 'set-${set.id}',
      album: 'WUVT Archive',
      title: setTitle(set.dtstart),
      artist: set.dj,
    );

    final sources = <AudioSource>[
      for (final seg in set.segments)
        ClippingAudioSource(
          child: AudioSource.uri(Uri.parse(seg.url)),
          start: Duration(milliseconds: seg.clipStartMs),
          end: seg.clipEndMs == null
              ? null
              : Duration(milliseconds: seg.clipEndMs!),
          tag: mediaItem,
        ),
    ];

    try {
      // Tear down any current playback before swapping in the new set, so the
      // previous audio can't keep playing underneath the new source.
      await player.stop();
      // Use setAudioSource + ConcatenatingAudioSource (deprecated but supported):
      // just_audio_background bridges playback events for this path, which is
      // what drives the media notification + lock-screen controls. The newer
      // setAudioSources() set the metadata but never broadcast the play state.
      // ignore: deprecated_member_use
      await player.setAudioSource(ConcatenatingAudioSource(children: sources));
    } on PlayerInterruptedException {
      // A newer loadSet() superseded this one (rapid set switching) — ignore.
    }
  }

  /// True if this set is the one currently loaded into the player.
  bool isLoaded(int setId) => loadedSetId == setId;

  /// Whole-set elapsed time from the current segment position + index.
  Duration globalPosition(Duration positionInSegment) {
    final idx = player.currentIndex ?? 0;
    final base =
        (idx >= 0 && idx < _cumulativeMs.length) ? _cumulativeMs[idx] : 0;
    return Duration(milliseconds: base + positionInSegment.inMilliseconds);
  }

  /// Seek to a position measured from the start of the whole set.
  Future<void> seekGlobal(Duration target) async {
    if (_cumulativeMs.isEmpty) return;
    final ms = target.inMilliseconds.clamp(0, _totalMs);
    var idx = 0;
    for (var i = 0; i < _cumulativeMs.length; i++) {
      if (ms >= _cumulativeMs[i]) {
        idx = i;
      } else {
        break;
      }
    }
    await player.seek(
      Duration(milliseconds: ms - _cumulativeMs[idx]),
      index: idx,
    );
  }

  /// Enter "break" playback: loop the set muted from the start, so real audio
  /// keeps the app (and its foreground service) alive with nothing audible.
  /// Looping means it never runs out no matter how long the break is.
  Future<void> startMutedBreak() async {
    await player.setLoopMode(LoopMode.all);
    await player.setVolume(0);
    await seekGlobal(Duration.zero);
    unawaited(player.play()); // play()'s future only completes when playback ends
  }

  /// End "break" playback: stop looping, restore volume, and jump back to the
  /// position the break started from. [play] resumes audible playback there.
  Future<void> endMutedBreak(int resumeMs, {required bool play}) async {
    await player.setLoopMode(LoopMode.off);
    await seekGlobal(Duration(milliseconds: resumeMs));
    await player.setVolume(1);
    if (play) {
      unawaited(player.play());
    } else {
      await player.pause();
    }
  }
}
