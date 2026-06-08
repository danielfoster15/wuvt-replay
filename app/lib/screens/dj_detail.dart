import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../util.dart';
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
    return Scaffold(
      appBar: AppBar(title: Text(widget.dj.airname)),
      body: FutureBuilder<DjDetail>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final detail = snap.data!;
          return ListView(
            children: [
              if (detail.topArtists.isNotEmpty) _TopArtists(detail.topArtists),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text('Sets', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              ...detail.sets.map((s) => _SetTile(dj: detail.dj, set: s)),
              if (detail.sets.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No sets found.'),
                ),
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Most played', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final a in artists)
                Chip(
                  label: Text('${a.name} · ${a.count}'),
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
    return ListTile(
      leading: const Icon(Icons.radio),
      title: Text(setDate(set.dtstart)),
      subtitle: Text(
        [setTime(set.dtstart), if (length.isNotEmpty) length].join('  ·  '),
      ),
      trailing: const Icon(Icons.play_circle_outline),
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
