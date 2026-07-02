import 'package:flutter/material.dart';

import '../theme.dart';

/// Generated "album art": a vintage-pastel gradient tile with initials, stable
/// per [seed]. Stands in for artwork the archive doesn't have.
class ArtTile extends StatelessWidget {
  const ArtTile({
    super.key,
    required this.seed,
    this.size,
    this.radius = 10,
    this.label,
    this.shadow = false,
  });

  /// Drives the colors (and default initials): DJ airname, set id, ...
  final String seed;

  /// Square edge length; null fills the parent.
  final double? size;
  final double radius;

  /// Text on the tile; defaults to initials of [seed].
  final String? label;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final a = pastelFor(seed);
    final b = pastelPairFor(seed);
    final text = label ?? initialsFor(seed);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [a, b],
        ),
        boxShadow: shadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: Center(
        child: LayoutBuilder(
          builder: (context, constraints) => Text(
            text,
            style: TextStyle(
              color: wuvtInk.withValues(alpha: 0.7),
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              fontSize: constraints.maxHeight * (text.length > 2 ? 0.24 : 0.34),
            ),
          ),
        ),
      ),
    );
  }
}
