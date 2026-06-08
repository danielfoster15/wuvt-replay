package app.wuvt.wuvt_replay

import com.ryanheise.audioservice.AudioServiceActivity

// Must extend AudioServiceActivity (not FlutterActivity) so the UI and the
// just_audio_background audio service share one Flutter engine. With a plain
// FlutterActivity, JustAudioBackground.init() hangs and the app never starts.
class MainActivity : AudioServiceActivity()
