import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';

/// Health of the services on the Pi: this backend, Nextcloud, and the
/// Expansion drive they both depend on.
class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key});

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  final _api = Api();
  late Future<Health> _future;

  @override
  void initState() {
    super.initState();
    _future = _api.health();
  }

  void _reload() => setState(() => _future = _api.health());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Server health'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _reload),
        ],
      ),
      body: FutureBuilder<Health>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            // The health endpoint itself being unreachable is the most
            // important health signal of all.
            return _StatusList(rows: [
              _StatusRow(
                ok: false,
                title: 'Backend',
                detail: 'Unreachable: ${snap.error}',
              ),
            ], onRetry: _reload);
          }
          final h = snap.data!;
          return _StatusList(rows: [
            _StatusRow(
              ok: h.backend.ok,
              title: 'Backend',
              detail:
                  'v${h.backend.version} · up ${_fmtUptime(h.backend.uptimeSec)}',
            ),
            _StatusRow(
              ok: h.nextcloud.ok,
              title: 'Nextcloud',
              detail: h.nextcloud.ok
                  ? 'v${h.nextcloud.version}'
                      '${h.nextcloud.maintenance == true ? ' · maintenance' : ''}'
                  : h.nextcloud.error ?? 'unhealthy',
            ),
            _StatusRow(
              ok: h.storage.ok,
              title: 'Expansion drive',
              detail: h.storage.ok
                  ? '${_fmtGb(h.storage.freeGb)} free of ${_fmtGb(h.storage.totalGb)}'
                  : h.storage.error ?? 'unhealthy',
            ),
          ], onRetry: _reload, checkedAt: h.checkedAt);
        },
      ),
    );
  }
}

String _fmtUptime(int sec) {
  if (sec >= 86400) return '${(sec / 86400).toStringAsFixed(1)} days';
  if (sec >= 3600) return '${(sec / 3600).toStringAsFixed(1)} h';
  return '${(sec / 60).round()} min';
}

String _fmtGb(double? gb) {
  if (gb == null) return '?';
  if (gb >= 1024) return '${(gb / 1024).toStringAsFixed(1)} TB';
  return '${gb.round()} GB';
}

class _StatusRow {
  const _StatusRow({required this.ok, required this.title, required this.detail});
  final bool ok;
  final String title;
  final String detail;
}

class _StatusList extends StatelessWidget {
  const _StatusList({required this.rows, required this.onRetry, this.checkedAt});
  final List<_StatusRow> rows;
  final VoidCallback onRetry;
  final DateTime? checkedAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final r in rows)
          ListTile(
            leading: Icon(
              r.ok ? Icons.check_circle : Icons.error,
              color: r.ok ? Colors.green : theme.colorScheme.error,
              size: 32,
            ),
            title: Text(r.title),
            subtitle: Text(r.detail),
          ),
        if (checkedAt != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Checked ${TimeOfDay.fromDateTime(checkedAt!.toLocal()).format(context)}',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}
