import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'focus_timer.dart';
import 'screens/dj_list.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final onAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  // Background playback + lock-screen controls (not supported on web).
  if (!kIsWeb) {
    // Standard init (no timeout): the AudioServiceActivity fix already prevents
    // the hang this previously guarded against, and a timeout here can abort the
    // native audio_service setup partway — which breaks the media notification /
    // lock-screen controls while leaving plain playback working.
    await JustAudioBackground.init(
      androidNotificationChannelId: 'app.wuvt.wuvt_replay.audio',
      androidNotificationChannelName: 'WUVT Archive playback',
      androidNotificationOngoing: true,
      // Dedicated white status-bar icon. The default (mipmap/ic_launcher) is now
      // an adaptive icon, which is invalid as a notification small icon.
      androidNotificationIcon: 'drawable/ic_stat_wuvt',
    );
  }
  if (onAndroid) {
    // Exact alarm that ends a break reliably even in Doze. The alarm fires in
    // its own isolate; this named port lets it signal the running app to resume.
    await AndroidAlarmManager.initialize();
    final port = ReceivePort();
    IsolateNameServer.removePortNameMapping(FocusTimer.alarmPortName);
    IsolateNameServer.registerPortWithName(port.sendPort, FocusTimer.alarmPortName);
    port.listen((_) => FocusTimer.instance.onAlarmFired());
  }
  runApp(const WuvtReplayApp());
}

// Retro radio palette — 70s warmth, 5 colors: espresso + cream base with a
// mustard / burnt-orange / teal accent trio.
const _mustard = Color(0xFFE8A33D); // primary
const _burnt = Color(0xFFD2683C); // secondary
const _teal = Color(0xFF3FA9A0); // tertiary — the pop
const _bg = Color(0xFF241A15); // espresso background
const _surface = Color(0xFF32241C); // warm brown surface
const _surfaceHi = Color(0xFF453228); // raised surface
const _cream = Color(0xFFF2E6D6); // text

class WuvtReplayApp extends StatelessWidget {
  const WuvtReplayApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _mustard,
      brightness: Brightness.dark,
    ).copyWith(
      primary: _mustard,
      onPrimary: const Color(0xFF2A1A00),
      secondary: _burnt,
      onSecondary: const Color(0xFF2A0F06),
      tertiary: _teal,
      onTertiary: const Color(0xFF052420),
      surface: _surface,
      onSurface: _cream,
      surfaceContainerHighest: _surfaceHi,
      primaryContainer: const Color(0xFF5A3A12),
      onPrimaryContainer: _cream,
      tertiaryContainer: const Color(0xFF1E4A45),
      onTertiaryContainer: _cream,
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
          foregroundColor: _mustard,
          centerTitle: false,
        ),
        sliderTheme: const SliderThemeData(
          activeTrackColor: _mustard,
          thumbColor: _mustard,
          inactiveTrackColor: _surfaceHi,
        ),
        chipTheme: ChipThemeData(
          backgroundColor: _surfaceHi,
          labelStyle: const TextStyle(color: _cream, fontSize: 12),
          side: const BorderSide(color: _burnt),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        // Mustard list icons (chevrons, radio, play) add warm pops throughout.
        listTileTheme: const ListTileThemeData(iconColor: _mustard),
        dividerColor: _surfaceHi,
      ),
      home: const DjListScreen(),
    );
  }
}
