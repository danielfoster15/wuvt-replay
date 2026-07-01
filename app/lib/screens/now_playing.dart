import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../api.dart';
import '../audio_service.dart';
import '../focus_timer.dart';
import '../models.dart';
import '../resume_store.dart';
import '../util.dart';

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({
    super.key,
    required this.setId,
    required this.djName,
    this.start,
  });

  final int setId;
  final String djName;
  final DateTime? start;

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  final _api = Api();
  final _svc = PlayerService.instance;

  SetDetail? _set;
  Object? _error;
  double? _dragMs;
  bool _playbackError = false;
  int _retries = 0;
  StreamSubscription<PlaybackEvent>? _eventSub;
  Timer? _saveTimer;

  AudioPlayer get _player => _svc.player;

  @override
  void initState() {
    super.initState();
    // archive.org CDN nodes occasionally 500; without this the player would
    // just go silent. Auto-retry once, then offer a manual retry.
    _eventSub = _player.playbackEventStream.listen(
      (_) {},
      onError: (Object e, StackTrace st) => _onPlaybackError(),
    );
    // Persist the listening position so reopening the set resumes here.
    _saveTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _savePosition());
    _load();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _savePosition();
    _eventSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final set = await _api.setDetail(widget.setId);
      if (!mounted) return;
      setState(() => _set = set);
      if (set.available && !_svc.isLoaded(set.id)) {
        await _svc.loadSet(set);
        // Resume where we left off, unless that's right at the start or end.
        final saved = await ResumeStore.instance.load(set.id);
        final total = _svc.total.inMilliseconds;
        if (saved != null && saved > 3000 && saved < total - 5000) {
          await _svc.seekGlobal(Duration(milliseconds: saved));
        }
        // Don't await: play()'s future only completes when playback *ends*.
        unawaited(_player.play());
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Save the current whole-set position for this set, unless a break is
  /// running (its playback is muted and seeks around, so not a real position).
  void _savePosition() {
    if (!_svc.isLoaded(widget.setId)) return;
    final ft = FocusTimer.instance;
    if (ft.running && ft.mode == SessionMode.breakTime) return;
    final pos = _svc.globalPosition(_player.position).inMilliseconds;
    ResumeStore.instance.save(widget.setId, pos);
  }

  void _onPlaybackError() {
    // Only react to errors for the set this screen is showing.
    if (!mounted || !_svc.isLoaded(widget.setId)) return;
    if (_retries < 1) {
      _retries++;
      _retry();
    } else {
      setState(() => _playbackError = true);
    }
  }

  Future<void> _retry() async {
    final set = _set;
    if (set == null || !set.available) return;
    setState(() => _playbackError = false);
    try {
      await _svc.loadSet(set);
      unawaited(_player.play());
    } catch (_) {
      if (mounted) setState(() => _playbackError = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.djName, overflow: TextOverflow.ellipsis),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(child: Text('Error: $_error'));
    }
    final set = _set;
    if (set == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!set.available) {
      return const _Unavailable();
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(setTitle(set.dtstart),
              style: Theme.of(context).textTheme.titleMedium),
        ),
        if (_playbackError)
          MaterialBanner(
            content: const Text(
              'Playback hit a snag (archive.org can be flaky). Try again.',
            ),
            leading: const Icon(Icons.error_outline),
            actions: [
              TextButton(
                onPressed: () {
                  _retries = 0;
                  _retry();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        _Controls(svc: _svc),
        const _FocusTimerPanel(),
        _SeekBar(
          svc: _svc,
          dragMs: _dragMs,
          onChanged: (v) => setState(() => _dragMs = v),
          onChangeEnd: (v) async {
            await _svc.seekGlobal(Duration(milliseconds: v.round()));
            if (mounted) setState(() => _dragMs = null);
          },
        ),
        const Divider(height: 1),
        Expanded(child: _TrackList(svc: _svc, tracks: set.tracks)),
      ],
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.svc});
  final PlayerService svc;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlayerState>(
      stream: svc.player.playerStateStream,
      builder: (context, snap) {
        final state = snap.data;
        final playing = state?.playing ?? false;
        final processing = state?.processingState;
        final buffering = processing == ProcessingState.loading ||
            processing == ProcessingState.buffering;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              iconSize: 36,
              icon: const Icon(Icons.replay_10),
              onPressed: () async {
                final pos = svc.globalPosition(svc.player.position);
                await svc.seekGlobal(pos - const Duration(seconds: 10));
              },
            ),
            const SizedBox(width: 8),
            if (buffering)
              const SizedBox(
                width: 64,
                height: 64,
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(),
                ),
              )
            else
              IconButton(
                iconSize: 64,
                icon: Icon(playing
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_fill),
                onPressed: () =>
                    playing ? svc.player.pause() : svc.player.play(),
              ),
            const SizedBox(width: 8),
            IconButton(
              iconSize: 36,
              icon: const Icon(Icons.forward_30),
              onPressed: () async {
                final pos = svc.globalPosition(svc.player.position);
                await svc.seekGlobal(pos + const Duration(seconds: 30));
              },
            ),
          ],
        );
      },
    );
  }
}

/// Session timer with two modes (see [FocusTimer]):
/// - Focus: play the set, stop after N minutes of listening.
/// - Break: pause for N minutes, then start the set (a cue to get back to it).
class _FocusTimerPanel extends StatelessWidget {
  const _FocusTimerPanel();

  @override
  Widget build(BuildContext context) {
    final t = FocusTimer.instance;
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: t,
      builder: (context, _) {
        final isBreak = t.mode == SessionMode.breakTime;
        return Card(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          color: cs.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!t.running)
                  Padding(
                    padding: const EdgeInsets.only(right: 8, bottom: 6),
                    child: SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<SessionMode>(
                        segments: const [
                          ButtonSegment(
                            value: SessionMode.focus,
                            label: Text('Focus'),
                            icon: Icon(Icons.headphones),
                          ),
                          ButtonSegment(
                            value: SessionMode.breakTime,
                            label: Text('Break'),
                            icon: Icon(Icons.coffee),
                          ),
                        ],
                        selected: {t.mode},
                        onSelectionChanged: (s) => t.setMode(s.first),
                        showSelectedIcon: false,
                      ),
                    ),
                  ),
                Row(
                  children: [
                    Icon(isBreak ? Icons.coffee : Icons.timer_outlined,
                        color: cs.primary),
                    const SizedBox(width: 10),
                    Text(isBreak ? 'Break timer' : 'Focus timer',
                        style: TextStyle(
                            color: cs.primary, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text(
                      t.running ? fmtDuration(t.remaining) : '${t.minutes} min',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontFeatures: const [
                        FontFeature.tabularFigures(),
                      ]),
                    ),
                    IconButton(
                      tooltip: t.running ? 'Cancel timer' : 'Start timer',
                      icon: Icon(t.running ? Icons.stop : Icons.play_arrow),
                      onPressed: () => t.running ? t.cancel() : t.start(),
                    ),
                  ],
                ),
                if (t.running)
                  _TimerCaption(isBreak: isBreak)
                else
                  Slider(
                    value: t.minutes.toDouble(),
                    min: FocusTimer.minMinutes.toDouble(),
                    max: FocusTimer.maxMinutes.toDouble(),
                    divisions: FocusTimer.maxMinutes - FocusTimer.minMinutes,
                    label: '${t.minutes} min',
                    onChanged: (v) => t.setMinutes(v.round()),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One-line status under a running timer. Break: fixed cue. Focus: reflects
/// whether the countdown is currently advancing (i.e. the music is playing).
class _TimerCaption extends StatelessWidget {
  const _TimerCaption({required this.isBreak});
  final bool isBreak;

  @override
  Widget build(BuildContext context) {
    Widget caption(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 10, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child:
                Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
        );

    if (isBreak) return caption('Music starts when the timer ends');
    return StreamBuilder<bool>(
      stream: PlayerService.instance.player.playingStream,
      builder: (context, snap) {
        final playing = snap.data ?? false;
        return caption(playing
            ? 'Counts down while the music plays'
            : 'Paused — timer holds until you resume');
      },
    );
  }
}

class _SeekBar extends StatelessWidget {
  const _SeekBar({
    required this.svc,
    required this.dragMs,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final PlayerService svc;
  final double? dragMs;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final totalMs = svc.total.inMilliseconds.toDouble();
    return StreamBuilder<Duration>(
      stream: svc.player.positionStream,
      builder: (context, snap) {
        final elapsed = svc.globalPosition(snap.data ?? Duration.zero);
        final value = (dragMs ?? elapsed.inMilliseconds.toDouble())
            .clamp(0.0, totalMs == 0 ? 1.0 : totalMs);
        return Column(
          children: [
            Slider(
              value: value,
              max: totalMs == 0 ? 1.0 : totalMs,
              onChanged: totalMs == 0 ? null : onChanged,
              onChangeEnd: totalMs == 0 ? null : onChangeEnd,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(fmtDuration(Duration(milliseconds: value.round()))),
                  Text(fmtDuration(svc.total)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TrackList extends StatelessWidget {
  const _TrackList({required this.svc, required this.tracks});
  final PlayerService svc;
  final List<TrackLog> tracks;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: svc.player.positionStream,
      builder: (context, snap) {
        final elapsed = svc.globalPosition(snap.data ?? Duration.zero);
        final current = currentTrackIndex(tracks, elapsed);
        return ListView.builder(
          itemCount: tracks.length,
          itemBuilder: (context, i) {
            final t = tracks[i];
            final isCurrent = i == current;
            final cs = Theme.of(context).colorScheme;
            return Container(
              color: isCurrent ? cs.tertiaryContainer : null,
              child: ListTile(
                dense: true,
                leading: isCurrent
                    ? Icon(Icons.volume_up, color: cs.tertiary)
                    : Text(
                        t.offsetMs == null
                            ? ''
                            : fmtDuration(Duration(milliseconds: t.offsetMs!)),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                title: Text('${t.artist} — ${t.title}'),
                subtitle: t.album.isEmpty ? null : Text(t.album),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    if (t.isNew) const Icon(Icons.fiber_new, size: 18),
                    if (t.isRequest) const Icon(Icons.call, size: 16),
                    if (t.isVinyl) const Icon(Icons.album, size: 16),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hourglass_empty, size: 48),
            SizedBox(height: 12),
            Text(
              'The archive for this set isn\'t available yet.\n'
              'Airchecks usually appear after the set has ended.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
