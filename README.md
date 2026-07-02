# wuvt-replay

A personal Android app for replaying WUVT DJ sets from the archive.org airchecks —
**playing each set from its real start to its real end**, gapless across the hour-long
recordings, with no leftover minutes of the adjacent show.

WUVT records its broadcast as one-hour files on archive.org. A DJ set rarely lines up with
the clock hour, so this project stitches the overlapping hour files together and trims the
first and last so you hear exactly the set — nothing more.

```
┌─────────────┐   small JSON    ┌──────────────┐   audio bytes    ┌─────────────┐
│ Flutter app │ ───────────────▶│   backend    │                  │ archive.org │
│  (Pixel 6a) │◀─── play plan ──│  (FastAPI)   │─── resolves ────▶│  hour MP3s  │
└─────────────┘                 └──────────────┘                  └─────────────┘
        │                                                                ▲
        └──────────────── streams MP3 ranges directly ───────────────────┘
```

The backend turns a `set_id` into a ready-to-play **clip plan**; the app feeds that straight
into the audio player. Audio bytes stream from archive.org directly — they never pass through
the backend.

## Repo layout

- `backend/` — FastAPI service (DJ/set metadata + archive→MP3 clip planner). Deploys to Fly.io.
- `app/` — Flutter app (`just_audio` clip + concatenate, `just_audio_background` for
  lock-screen controls).

---

## Backend

### Run locally

```bash
cd backend
uv venv .venv && uv pip install -e ".[dev]"
.venv/bin/uvicorn app.main:app --reload --port 8077
.venv/bin/pytest          # unit tests for the clip math
```

### Endpoints

| Endpoint        | Returns                                                              |
|-----------------|---------------------------------------------------------------------|
| `GET /healthz`  | `{"ok": true}` (liveness only)                                      |
| `GET /health`   | rollup for the in-app health screen: backend, Nextcloud, storage    |
| `GET /djs`      | `{djs: [{id, airname, last_set}]}` (recently-on-air first)          |
| `GET /djs/{id}` | `{dj, sets: [{id, dtstart, dtend, duration_sec}], top_artists}`     |
| `GET /sets/{id}`| set detail + **clip plan** (see below) + tracklist                  |

`GET /sets/{id}` example:

```json
{
  "id": 60624, "dj": "210 Watts of DJ Taldin!",
  "dtstart": "2026-05-26T04:12:18+00:00", "dtend": "2026-05-26T06:02:07+00:00",
  "available": true,
  "segments": [
    {"url": "https://archive.org/download/WUVTFM_20260526_0400Z/...mp3", "clip_start_ms": 738000, "clip_end_ms": null},
    {"url": "https://archive.org/download/WUVTFM_20260526_0500Z/...mp3", "clip_start_ms": 0,      "clip_end_ms": null},
    {"url": "https://archive.org/download/WUVTFM_20260526_0600Z/...mp3", "clip_start_ms": 0,      "clip_end_ms": 127000}
  ],
  "tracks": [{"offset_ms": 1000, "artist": "White Zombie", "title": "Thunder Kiss '65", "...": "..."}]
}
```

`clip_end_ms: null` means "play to the natural end of that file." `available: false` means the
set has no archives yet (still on air or not uploaded) — the app disables Play.

### Deploy to Fly.io

```bash
cd backend
fly launch --no-deploy --copy-config   # first time; pick an app name if "wuvt-replay" is taken
fly deploy
```

Note the resulting URL (e.g. `https://wuvt-replay.fly.dev`) — the app points at it.

### Run on a Raspberry Pi (always-on)

The backend is tiny and idles at near-zero (audio streams from archive.org, not through it),
so a Pi running it 24/7 is a great fit. Copy `backend/` to the Pi, then:

```bash
cd backend
cp .env.example .env              # optional: fill in the /health check targets
docker compose up -d --build      # listens on :8080, restarts on boot/crash
```

(No Docker? Use a venv + a systemd service running `uvicorn app.main:app --host 0.0.0.0 --port 8080`.)

**Reaching it from your phone:**
- *At home, same wifi:* the app can use `http://<pi-lan-ip>:8080`.
- *Anywhere (cell data):* install [Tailscale](https://tailscale.com) on both the Pi and the
  phone (free for personal use). The phone then reaches the Pi at its `100.x.x.x` tailnet
  address from anywhere — no port forwarding, no exposing the Pi to the internet.

Then bake that address into the APK: `--dart-define=BACKEND_URL=http://<pi-address>:8080`.

---

## App

### Configure the backend URL

`app/lib/config.dart` holds the compile-time default. Override at build/run time
without editing code:

```bash
flutter run --dart-define=BACKEND_URL=http://homecloud.<tailnet>.ts.net:8080
```

The URL is also editable **in the app** (gear icon on the DJ list) and persists —
so you can move between LAN, tailnet, or a hosted backend without rebuilding.

### Build & run on your Pixel 6a

Requires the Flutter SDK and the Android toolchain (Android Studio / SDK / `adb`).

```bash
cd app
flutter pub get
flutter analyze
flutter run --dart-define=BACKEND_URL=https://wuvt-replay.fly.dev   # device plugged in via USB
# or build an installable APK:
flutter build apk --release --dart-define=BACKEND_URL=https://wuvt-replay.fly.dev
```

### Screens

1. **DJs** — searchable list of all DJs (recently-on-air first), plus server
   health and backend-URL settings in the app bar.
2. **DJ** — their recent sets (date + duration) and most-played bands.
3. **Now Playing** — play/pause, a seek bar spanning the whole set (across hour boundaries),
   the tracklist highlighting the song currently playing, and the **focus/break timer**.

### Focus & break timer

On Now Playing, pick a duration (1–120 min) and a mode:

- **Focus** — plays the set and stops it after N minutes of *listening*
  (pausing the music holds the countdown).
- **Break** — pauses for N minutes wall-clock, then starts the music again as
  the "back to work" cue. The set plays muted+looping meanwhile so Android
  keeps the app alive.

Session ends are enforced by **exact OS alarms** (`SCHEDULE_EXACT_ALARM`/
`USE_EXACT_ALARM`), so they fire on time even in deep Doze; if the app process
was killed mid-session, a notification delivers the cue instead. Each set also
**resumes where you left off** across app restarts.

## Status / roadmap

- ✅ Backend: metadata + clip planner, verified against live WUVT + archive.org.
- ✅ App: browse DJs/sets, gapless trimmed playback, background/lock-screen controls.
- ✅ Focus/break timer (Doze-proof via exact alarms) + per-set resume.
- ✅ Health screen: backend / Nextcloud / Expansion-drive status from the phone.
- ⏳ Deferred: genres and "most famous bands" (needs an enrichment source like Last.fm/Spotify).
