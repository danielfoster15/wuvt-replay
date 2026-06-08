/// Backend base URL. Override at build/run time without editing code:
///
///   flutter run --dart-define=BACKEND_URL=https://wuvt-replay.fly.dev
///
/// Defaults to localhost for desktop/web development. Note that on an Android
/// emulator the host machine is reachable at 10.0.2.2, and a physical Pixel must
/// use a LAN IP or the deployed Fly URL.
const String backendUrl = String.fromEnvironment(
  'BACKEND_URL',
  defaultValue: 'http://localhost:8077',
);
