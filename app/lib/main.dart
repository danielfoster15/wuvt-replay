import 'dart:async' show unawaited;
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'config.dart';
import 'focus_timer.dart';
import 'screens/dj_list.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final onAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  // Load persisted settings before the first screen fires its requests.
  await BackendConfig.instance.load();
  unawaited(FocusTimer.instance.restore());
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

class WuvtReplayApp extends StatelessWidget {
  const WuvtReplayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WUVT Replay',
      debugShowCheckedModeBanner: false,
      // Modern dark shell over a vintage-pastel accent family (theme.dart).
      theme: buildWuvtTheme(),
      home: const DjListScreen(),
    );
  }
}
