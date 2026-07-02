import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../audio_service.dart';
import '../screens/now_playing.dart';
import '../theme.dart';
import '../util.dart';
import 'artwork.dart';

/// Spotify-style docked bar: shows the loaded set with play/pause and opens
/// Now Playing on tap. Collapses away when nothing is loaded. Put it in a
/// Scaffold's `bottomNavigationBar` slot.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final svc = PlayerService.instance;
    return StreamBuilder<PlayerState>(
      stream: svc.player.playerStateStream,
      builder: (context, snap) {
        final set = svc.loadedSet;
        if (set == null) return const SizedBox.shrink();
        final playing = snap.data?.playing ?? false;
        final accent = pastelFor(set.dj);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Material(
              color: Color.alphaBlend(
                  accent.withValues(alpha: 0.16), wuvtSurfaceHi),
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => NowPlayingScreen(
                      setId: set.id,
                      djName: set.dj,
                      start: set.dtstart,
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      ArtTile(seed: set.dj, size: 40, radius: 6),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              setTitle(set.dtstart),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                            Text(
                              set.dj,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded),
                        color: wuvtCream,
                        iconSize: 30,
                        onPressed: () =>
                            playing ? svc.player.pause() : svc.player.play(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
