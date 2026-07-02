import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../api.dart';
import '../audio_service.dart';
import '../focus_timer.dart';
import '../models.dart';
import '../resume_store.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/vinyl.dart';

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
    final accent = pastelFor(widget.djName);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('PLAYING FROM WUVT ARCHIVE',
                style: Theme.of(context).textTheme.labelSmall),
            Text(
              widget.djName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
      body: DecoratedBox(
        // The DJ's pastel washing down into the dark background.
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0, 0.55],
            colors: [
              Color.alphaBlend(accent.withValues(alpha: 0.38), wuvtBg),
              wuvtBg,
            ],
          ),
        ),
        child: _buildBody(accent),
      ),
    );
  }

  Widget _buildBody(Color accent) {
    if (_error != null) {
      return Center(child: Text('$_error', textAlign: TextAlign.center));
    }
    final set = _set;
    if (set == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!set.available) {
      return const _Unavailable();
    }
    final topInset =
        MediaQuery.of(context).padding.top + kToolbarHeight + 12;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, topInset, 24, 0),
            child: Column(
              children: [
                if (_playbackError)
                  MaterialBanner(
                    backgroundColor: wuvtSurfaceHi,
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
                const SizedBox(height: 8),
                FractionallySizedBox(
                  widthFactor: 0.72,
                  child: SpinningVinyl(seed: widget.djName),
                ),
                const SizedBox(height: 28),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(setTitle(set.dtstart),
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                const SizedBox(height: 2),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    set.dj,
                    style: TextStyle(
                      fontSize: 15,
                      color: wuvtCream.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                _SeekBar(
                  svc: _svc,
                  dragMs: _dragMs,
                  onChanged: (v) => setState(() => _dragMs = v),
                  onChangeEnd: (v) async {
                    await _svc.seekGlobal(Duration(milliseconds: v.round()));
                    if (mounted) setState(() => _dragMs = null);
                  },
                ),
                _Controls(svc: _svc),
                const SizedBox(height: 16),
                _FocusTimerPanel(accent: accent),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('TRACKLIST',
                      style: Theme.of(context).textTheme.labelSmall),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ),
        _TrackList(svc: _svc, tracks: set.tracks, accent: accent),
        const SliverToBoxAdapter(child: SafeArea(child: SizedBox(height: 8))),
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
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              iconSize: 36,
              color: wuvtCream.withValues(alpha: 0.75),
              icon: const Icon(Icons.replay_10_rounded),
              onPressed: () async {
                final pos = svc.globalPosition(svc.player.position);
                await svc.seekGlobal(pos - const Duration(seconds: 10));
              },
            ),
            SizedBox(
              width: 76,
              height: 76,
              child: buffering
                  ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(strokeWidth: 3),
                    )
                  : IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: wuvtCream,
                        foregroundColor: wuvtInk,
                      ),
                      iconSize: 42,
                      icon: Icon(playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded),
                      onPressed: () =>
                          playing ? svc.player.pause() : svc.player.play(),
                    ),
            ),
            IconButton(
              iconSize: 36,
              color: wuvtCream.withValues(alpha: 0.75),
              icon: const Icon(Icons.forward_30_rounded),
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

/// Focus / break session control (see [FocusTimer]).
class _FocusTimerPanel extends StatelessWidget {
  const _FocusTimerPanel({required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final t = FocusTimer.instance;
    return ListenableBuilder(
      listenable: t,
      builder: (context, _) {
        final isBreak = t.mode == SessionMode.breakTime;
        return Container(
          decoration: BoxDecoration(
            color: wuvtSurfaceHi.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!t.running)
                Padding(
                  padding: const EdgeInsets.only(right: 6, bottom: 8),
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
                      color: accent, size: 22),
                  const SizedBox(width: 10),
                  Text(isBreak ? 'Break timer' : 'Focus timer',
                      style: TextStyle(
                          color: accent, fontWeight: FontWeight.w700)),
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
                    color: wuvtCream,
                    icon: Icon(t.running
                        ? Icons.stop_rounded
                        : Icons.play_arrow_rounded),
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
                  activeColor: accent,
                  onChanged: (v) => t.setMinutes(v.round()),
                ),
            ],
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
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
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
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(fmtDuration(Duration(milliseconds: value.round())),
                      style: Theme.of(context).textTheme.bodySmall),
                  Text(fmtDuration(svc.total),
                      style: Theme.of(context).textTheme.bodySmall),
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
  const _TrackList(
      {required this.svc, required this.tracks, required this.accent});
  final PlayerService svc;
  final List<TrackLog> tracks;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    // Only rebuild rows when the *current track* changes, not on every
    // position tick.
    return StreamBuilder<int>(
      stream: svc.player.positionStream
          .map((p) => currentTrackIndex(tracks, svc.globalPosition(p)))
          .distinct(),
      builder: (context, snap) {
        final current = snap.data ?? -1;
        return SliverList.builder(
          itemCount: tracks.length,
          itemBuilder: (context, i) {
            final t = tracks[i];
            final isCurrent = i == current;
            final dim = wuvtCream.withValues(alpha: 0.5);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
              decoration: isCurrent
                  ? BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    )
                  : null,
              child: ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                leading: SizedBox(
                  width: 40,
                  child: isCurrent
                      ? Icon(Icons.graphic_eq_rounded, color: accent)
                      : Text(
                          t.offsetMs == null
                              ? ''
                              : fmtDuration(
                                  Duration(milliseconds: t.offsetMs!)),
                          style: Theme.of(context).textTheme.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                ),
                title: Text(
                  '${t.artist} — ${t.title}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight:
                        isCurrent ? FontWeight.w700 : FontWeight.w400,
                    color: isCurrent
                        ? Color.lerp(accent, wuvtCream, 0.35)
                        : wuvtCream,
                  ),
                ),
                subtitle: t.album.isEmpty
                    ? null
                    : Text(t.album,
                        style: Theme.of(context).textTheme.bodySmall),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    if (t.isNew)
                      Icon(Icons.fiber_new, size: 18, color: dim),
                    if (t.isRequest) Icon(Icons.call, size: 15, color: dim),
                    if (t.isVinyl) Icon(Icons.album, size: 15, color: dim),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hourglass_empty,
                size: 48, color: wuvtCream.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            const Text(
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
