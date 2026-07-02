// Data models mirroring the backend's JSON contract (see backend/app/models.py).

DateTime? _parseDt(String? s) {
  if (s == null) return null;
  return DateTime.tryParse(s)?.toLocal();
}

class Dj {
  final int id;
  final String airname;
  final DateTime? lastSet;

  Dj({required this.id, required this.airname, this.lastSet});

  factory Dj.fromJson(Map<String, dynamic> j) => Dj(
        id: j['id'] as int,
        airname: (j['airname'] ?? '') as String,
        lastSet: _parseDt(j['last_set'] as String?),
      );
}

class SetSummary {
  final int id;
  final DateTime? dtstart;
  final DateTime? dtend;
  final int? durationSec;

  SetSummary({
    required this.id,
    this.dtstart,
    this.dtend,
    this.durationSec,
  });

  factory SetSummary.fromJson(Map<String, dynamic> j) => SetSummary(
        id: j['id'] as int,
        dtstart: _parseDt(j['dtstart'] as String?),
        dtend: _parseDt(j['dtend'] as String?),
        durationSec: j['duration_sec'] as int?,
      );
}

class TopArtist {
  final String name;
  final int count;

  TopArtist({required this.name, required this.count});

  factory TopArtist.fromJson(Map<String, dynamic> j) =>
      TopArtist(name: j['name'] as String, count: j['count'] as int);
}

class DjDetail {
  final Dj dj;
  final List<SetSummary> sets;
  final List<TopArtist> topArtists;

  DjDetail({required this.dj, required this.sets, required this.topArtists});

  factory DjDetail.fromJson(Map<String, dynamic> j) => DjDetail(
        dj: Dj.fromJson(j['dj'] as Map<String, dynamic>),
        sets: ((j['sets'] ?? []) as List)
            .map((e) => SetSummary.fromJson(e as Map<String, dynamic>))
            .toList(),
        topArtists: ((j['top_artists'] ?? []) as List)
            .map((e) => TopArtist.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class Segment {
  final String url;
  final int clipStartMs;
  final int? clipEndMs; // null => play to natural end of file
  final int durationMs;

  Segment({
    required this.url,
    required this.clipStartMs,
    this.clipEndMs,
    required this.durationMs,
  });

  factory Segment.fromJson(Map<String, dynamic> j) => Segment(
        url: j['url'] as String,
        clipStartMs: j['clip_start_ms'] as int,
        clipEndMs: j['clip_end_ms'] as int?,
        durationMs: j['duration_ms'] as int,
      );
}

class TrackLog {
  final int? offsetMs; // ms from set start
  final DateTime? played;
  final String artist;
  final String title;
  final String album;
  final bool isNew;
  final bool isRequest;
  final bool isVinyl;

  TrackLog({
    this.offsetMs,
    this.played,
    required this.artist,
    required this.title,
    required this.album,
    required this.isNew,
    required this.isRequest,
    required this.isVinyl,
  });

  factory TrackLog.fromJson(Map<String, dynamic> j) => TrackLog(
        offsetMs: j['offset_ms'] as int?,
        played: _parseDt(j['played'] as String?),
        artist: (j['artist'] ?? '') as String,
        title: (j['title'] ?? '') as String,
        album: (j['album'] ?? '') as String,
        isNew: (j['is_new'] ?? false) as bool,
        isRequest: (j['is_request'] ?? false) as bool,
        isVinyl: (j['is_vinyl'] ?? false) as bool,
      );
}

class BackendHealth {
  final bool ok;
  final String version;
  final int uptimeSec;

  BackendHealth({required this.ok, required this.version, required this.uptimeSec});

  factory BackendHealth.fromJson(Map<String, dynamic> j) => BackendHealth(
        ok: (j['ok'] ?? false) as bool,
        version: (j['version'] ?? '') as String,
        uptimeSec: (j['uptime_sec'] ?? 0) as int,
      );
}

class NextcloudHealth {
  final bool ok;
  final String? version;
  final bool? maintenance;
  final String? error;

  NextcloudHealth({required this.ok, this.version, this.maintenance, this.error});

  factory NextcloudHealth.fromJson(Map<String, dynamic> j) => NextcloudHealth(
        ok: (j['ok'] ?? false) as bool,
        version: j['version'] as String?,
        maintenance: j['maintenance'] as bool?,
        error: j['error'] as String?,
      );
}

class StorageHealth {
  final bool ok;
  final double? freeGb;
  final double? totalGb;
  final String? error;

  StorageHealth({required this.ok, this.freeGb, this.totalGb, this.error});

  factory StorageHealth.fromJson(Map<String, dynamic> j) => StorageHealth(
        ok: (j['ok'] ?? false) as bool,
        freeGb: (j['free_gb'] as num?)?.toDouble(),
        totalGb: (j['total_gb'] as num?)?.toDouble(),
        error: j['error'] as String?,
      );
}

class Health {
  final bool ok;
  final DateTime? checkedAt;
  final BackendHealth backend;
  final NextcloudHealth nextcloud;
  final StorageHealth storage;

  Health({
    required this.ok,
    this.checkedAt,
    required this.backend,
    required this.nextcloud,
    required this.storage,
  });

  factory Health.fromJson(Map<String, dynamic> j) => Health(
        ok: (j['ok'] ?? false) as bool,
        checkedAt: _parseDt(j['checked_at'] as String?),
        backend: BackendHealth.fromJson(j['backend'] as Map<String, dynamic>),
        nextcloud: NextcloudHealth.fromJson(j['nextcloud'] as Map<String, dynamic>),
        storage: StorageHealth.fromJson(j['storage'] as Map<String, dynamic>),
      );
}

class SetDetail {
  final int id;
  final String dj;
  final DateTime? dtstart;
  final DateTime? dtend;
  final bool available;
  final List<Segment> segments;
  final List<TrackLog> tracks;

  SetDetail({
    required this.id,
    required this.dj,
    this.dtstart,
    this.dtend,
    required this.available,
    required this.segments,
    required this.tracks,
  });

  factory SetDetail.fromJson(Map<String, dynamic> j) => SetDetail(
        id: j['id'] as int,
        dj: (j['dj'] ?? '') as String,
        dtstart: _parseDt(j['dtstart'] as String?),
        dtend: _parseDt(j['dtend'] as String?),
        available: (j['available'] ?? false) as bool,
        segments: ((j['segments'] ?? []) as List)
            .map((e) => Segment.fromJson(e as Map<String, dynamic>))
            .toList(),
        tracks: ((j['tracks'] ?? []) as List)
            .map((e) => TrackLog.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
