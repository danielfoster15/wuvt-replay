import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'screens/dj_list.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Background playback + lock-screen controls (not supported on web).
  if (!kIsWeb) {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'app.wuvt.wuvt_replay.audio',
      androidNotificationChannelName: 'WUVT Archive playback',
      androidNotificationOngoing: true,
    );
  }
  runApp(const WuvtReplayApp());
}

// Warm retro palette — vintage-radio feel: espresso-maroon surfaces with amber
// and clay-red accents on cream text.
const _amber = Color(0xFFE8A33D);
const _clay = Color(0xFFC75D4F);
const _bg = Color(0xFF1E1414);
const _surface = Color(0xFF2A1D1D);
const _surfaceHi = Color(0xFF3A2A2A);
const _cream = Color(0xFFF3E9DF);

class WuvtReplayApp extends StatelessWidget {
  const WuvtReplayApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _amber,
      brightness: Brightness.dark,
    ).copyWith(
      primary: _amber,
      onPrimary: const Color(0xFF2A1A00),
      secondary: _clay,
      onSecondary: const Color(0xFF2A0F0A),
      surface: _surface,
      onSurface: _cream,
      surfaceContainerHighest: _surfaceHi,
      primaryContainer: const Color(0xFF5A3A12),
      onPrimaryContainer: _cream,
    );

    return MaterialApp(
      title: 'WUVT Replay',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: _bg,
        appBarTheme: const AppBarTheme(
          backgroundColor: _surface,
          foregroundColor: _cream,
          centerTitle: false,
        ),
        sliderTheme: const SliderThemeData(
          activeTrackColor: _amber,
          thumbColor: _amber,
          inactiveTrackColor: _surfaceHi,
        ),
        chipTheme: ChipThemeData(
          backgroundColor: _surfaceHi,
          labelStyle: const TextStyle(color: _cream, fontSize: 12),
          side: const BorderSide(color: _clay),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        dividerColor: _surfaceHi,
      ),
      home: const DjListScreen(),
    );
  }
}
