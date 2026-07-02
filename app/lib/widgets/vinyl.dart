import 'dart:async';

import 'package:flutter/material.dart';

import '../audio_service.dart';
import '../theme.dart';

/// A vinyl record that actually spins while the set plays (and freezes when
/// paused, like lifting the needle). Ink disc with grooves and a pastel label
/// carrying the seed's initials — the moving version of [ArtTile].
class SpinningVinyl extends StatefulWidget {
  const SpinningVinyl({super.key, required this.seed});
  final String seed;

  @override
  State<SpinningVinyl> createState() => _SpinningVinylState();
}

class _SpinningVinylState extends State<SpinningVinyl>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8), // slow, cinematic rev
  );
  StreamSubscription<bool>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = PlayerService.instance.player.playingStream.listen((playing) {
      if (playing) {
        _spin.repeat();
      } else {
        _spin.stop();
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = pastelFor(widget.seed);
    final labelPair = pastelPairFor(widget.seed);
    return AspectRatio(
      aspectRatio: 1,
      child: RotationTransition(
        turns: _spin,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Disc with rim light.
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: wuvtInk,
                border: Border.all(
                    color: wuvtCream.withValues(alpha: 0.25), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 30,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
            ),
            // Groove rings.
            for (final f in const [0.90, 0.80, 0.70, 0.60])
              Center(
                child: FractionallySizedBox(
                  widthFactor: f,
                  heightFactor: f,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: wuvtCream.withValues(alpha: 0.10),
                          width: 1.5),
                    ),
                  ),
                ),
              ),
            // Pastel label with initials.
            Center(
              child: FractionallySizedBox(
                widthFactor: 0.4,
                heightFactor: 0.4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [label, labelPair],
                    ),
                  ),
                  child: Center(
                    child: FractionallySizedBox(
                      widthFactor: 0.6,
                      child: FittedBox(
                        child: Text(
                          initialsFor(widget.seed),
                          style: TextStyle(
                            color: wuvtInk.withValues(alpha: 0.7),
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Spindle hole.
            Center(
              child: FractionallySizedBox(
                widthFactor: 0.045,
                heightFactor: 0.045,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: wuvtInk),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
