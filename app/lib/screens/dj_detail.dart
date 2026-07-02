import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/artwork.dart';
import '../widgets/mini_player.dart';
import 'now_playing.dart';

class DjDetailScreen extends StatefulWidget {
  const DjDetailScreen({super.key, required this.dj});
  final Dj dj;

  @override
  State<DjDetailScreen> createState() => _DjDetailScreenState();
}

class _DjDetailScreenState extends State<DjDetailScreen> {
  final _api = Api();
  late Future<DjDetail> _future;

  @override
  void initState() {
    super.initState();
    _future = _api.djDetail(widget.dj.id);
  }

  @override
  Widget build(BuildContext context) {
    final accent = pastelFor(widget.dj.airname);
    return Scaffold(
      bottomNavigationBar: const MiniPlayer(),
      body: FutureBuilder<DjDetail>(
        future: _future,
        builder: (context, snap) {
          final waiting = snap.connectionState != ConnectionState.done;
          return CustomScrollView(
            slivers: [
              // Gradient hero: the DJ's pastel washing down into the dark bg.
              SliverAppBar(
                pinned: true,
                expandedHeight: 200,
                backgroundColor: Color.alphaBlend(
                    accent.withValues(alpha: 0.25), wuvtBg),
                flexibleSpace: FlexibleSpaceBar(
                  titlePadding:
                      const EdgeInsets.symmetric(horizontal: 52, vertical: 14),
                  centerTitle: false,
                  title: Text(
                    widget.dj.airname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: wuvtCream,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  background: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color.alphaBlend(
                              accent.withValues(alpha: 0.55), wuvtBg),
                          Color.alphaBlend(
                              accent.withValues(alpha: 0.12), wuvtBg),
                        ],
                      ),
                    ),
                    child: Align(
                      alignment: const Alignment(0, 0.1),
                      child: ArtTile(
                          seed: widget.dj.airname,
                          size: 96,
                          radius: 48,
                          shadow: true),
                    ),
                  ),
                ),
              ),
              if (waiting)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (snap.hasError)
                SliverFillRemaining(
                  child: Center(child: Text('${snap.error}')),
                )
              else ...[
                if (snap.data!.topArtists.isNotEmpty)
                  SliverToBoxAdapter(
                      child: _TopArtists(snap.data!.topArtists)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                    child: Text('Sets',
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                ),
                if (snap.data!.sets.isEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No sets found.'),
                    ),
                  )
                else
                  SliverList.builder(
                    itemCount: snap.data!.sets.length,
                    itemBuilder: (context, i) => _SetTile(
                        dj: snap.data!.dj, set: snap.data!.sets[i]),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _TopArtists extends StatelessWidget {
  const _TopArtists(this.artists);
  final List<TopArtist> artists;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('MOST PLAYED',
              style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final a in artists)
                Chip(
                  backgroundColor: Color.alphaBlend(
                      pastelFor(a.name).withValues(alpha: 0.16),
                      wuvtSurface),
                  label: Text(
                    '${a.name} · ${a.count}',
                    style: TextStyle(
                      color: Color.lerp(pastelFor(a.name), wuvtCream, 0.4),
                      fontSize: 12,
                    ),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SetTile extends StatelessWidget {
  const _SetTile({required this.dj, required this.set});
  final Dj dj;
  final SetSummary set;

  @override
  Widget build(BuildContext context) {
    final length = fmtSetLength(set.durationSec);
    final day = set.dtstart?.day.toString() ?? '?';
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: ArtTile(seed: 'set-${set.id}', size: 48, label: day),
      title: Text(
        setDate(set.dtstart),
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
      subtitle: Text(
        [setTime(set.dtstart), if (length.isNotEmpty) length].join('  ·  '),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: Icon(Icons.play_circle_outline,
          color: pastelFor(dj.airname), size: 28),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => NowPlayingScreen(
            setId: set.id,
            djName: dj.airname,
            start: set.dtstart,
          ),
        ),
      ),
    );
  }
}
