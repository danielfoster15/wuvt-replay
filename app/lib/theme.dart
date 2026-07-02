import 'package:flutter/material.dart';

/// Vintage pastel family — 12 muted retro tones spanning warm → cool → green.
/// Used for generated artwork tiles, chips, and screen accent gradients; each
/// DJ/set gets a stable color via [pastelFor].
const vintagePastels = <Color>[
  Color(0xFFF2D0A4), // butter sand
  Color(0xFFF5C09F), // peach
  Color(0xFFE8A98F), // terracotta
  Color(0xFFE8B4B8), // dusty rose
  Color(0xFFD8A5C0), // orchid
  Color(0xFFC9B8D8), // lavender
  Color(0xFFA9BFDE), // periwinkle
  Color(0xFF9FC9DC), // powder blue
  Color(0xFF96CFC4), // seafoam
  Color(0xFFABD8B4), // mint
  Color(0xFFB8C9A0), // sage
  Color(0xFFD9D3A8), // flax
];

// Dark, slightly warm neutrals under the pastels.
const wuvtBg = Color(0xFF14110D);
const wuvtSurface = Color(0xFF1D1915);
const wuvtSurfaceHi = Color(0xFF2A241D);
const wuvtCream = Color(0xFFF4EDE1);
const wuvtInk = Color(0xFF231E17); // dark text on pastel fills

/// Stable pastel for a seed string (DJ airname, set id, ...).
Color pastelFor(Object seed) =>
    vintagePastels[seed.hashCode.abs() % vintagePastels.length];

/// A second tone that pairs with [pastelFor] for gradients.
Color pastelPairFor(Object seed) {
  final i = seed.hashCode.abs() % vintagePastels.length;
  final next = vintagePastels[(i + 3) % vintagePastels.length];
  return Color.lerp(next, Colors.black, 0.18)!;
}

/// Initials for an artwork tile ("Kirsti Kaldro" -> "KK").
String initialsFor(String name) {
  final words =
      name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  final first = String.fromCharCode(words.first.runes.first).toUpperCase();
  if (words.length == 1) return first;
  final second = String.fromCharCode(words[1].runes.first).toUpperCase();
  return '$first$second';
}

ThemeData buildWuvtTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF96CFC4),
    brightness: Brightness.dark,
  ).copyWith(
    primary: const Color(0xFF96CFC4), // seafoam
    onPrimary: wuvtInk,
    secondary: const Color(0xFFE8B4B8), // dusty rose
    onSecondary: wuvtInk,
    tertiary: const Color(0xFF9FC9DC), // powder blue
    onTertiary: wuvtInk,
    surface: wuvtSurface,
    onSurface: wuvtCream,
    surfaceContainerHighest: wuvtSurfaceHi,
    outlineVariant: const Color(0xFF3A322A),
  );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final text = base.textTheme
      .apply(bodyColor: wuvtCream, displayColor: wuvtCream)
      .copyWith(
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800, letterSpacing: -0.5, color: wuvtCream),
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800, letterSpacing: -0.5, color: wuvtCream),
        titleLarge: base.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700, letterSpacing: -0.3, color: wuvtCream),
        titleMedium: base.textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w600, color: wuvtCream),
        bodySmall: base.textTheme.bodySmall
            ?.copyWith(color: wuvtCream.withValues(alpha: 0.55)),
        labelSmall: base.textTheme.labelSmall?.copyWith(
            letterSpacing: 1.2, color: wuvtCream.withValues(alpha: 0.6)),
      );

  return base.copyWith(
    scaffoldBackgroundColor: wuvtBg,
    textTheme: text,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: wuvtCream,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: wuvtCream,
        fontSize: 22,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
      ),
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 3,
      activeTrackColor: wuvtCream,
      inactiveTrackColor: wuvtCream.withValues(alpha: 0.18),
      thumbColor: wuvtCream,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: wuvtSurfaceHi,
      side: BorderSide.none,
      labelStyle: const TextStyle(color: wuvtCream, fontSize: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    listTileTheme:
        ListTileThemeData(iconColor: wuvtCream.withValues(alpha: 0.6)),
    dividerColor: const Color(0xFF2A241D),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        side: WidgetStatePropertyAll(
            BorderSide(color: wuvtCream.withValues(alpha: 0.15))),
        shape: const WidgetStatePropertyAll(StadiumBorder()),
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? scheme.primary.withValues(alpha: 0.22)
                : Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? scheme.primary
                : wuvtCream.withValues(alpha: 0.7)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: wuvtSurfaceHi,
      contentTextStyle: const TextStyle(color: wuvtCream),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
