import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../api.dart';
import '../config.dart';
import '../models.dart';
import '../util.dart';
import 'dj_detail.dart';
import 'health.dart';

class DjListScreen extends StatefulWidget {
  const DjListScreen({super.key});

  @override
  State<DjListScreen> createState() => _DjListScreenState();
}

class _DjListScreenState extends State<DjListScreen> {
  final _api = Api();
  late Future<List<Dj>> _future;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = _api.djs();
    // Needed (Android 13+) for the media notification that keeps background
    // playback alive. Fire-and-forget; safe if already granted.
    Permission.notification.request();
  }

  void _reload() => setState(() => _future = _api.djs());

  /// Edit the backend URL in place (persisted; falls back to the built-in
  /// default when cleared) — no rebuild needed to move between LAN/tailnet.
  Future<void> _editBackendUrl() async {
    final cfg = BackendConfig.instance;
    final controller = TextEditingController(text: cfg.url);
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Backend URL'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                hintText: 'http://host:8080',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Default: $defaultBackendUrl',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'reset'),
            child: const Text('Use default'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (action == null) return;
    if (action == 'reset') {
      await cfg.setOverride(null);
    } else {
      final url = controller.text.trim();
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('URL must start with http:// or https://')));
        }
        return;
      }
      await cfg.setOverride(url);
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WUVT DJs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.monitor_heart_outlined),
            tooltip: 'Server health',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HealthScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Backend URL',
            onPressed: _editBackendUrl,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search DJs',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Dj>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return _ErrorView(error: snap.error, onRetry: _reload);
                }
                final djs = (snap.data ?? [])
                    .where((d) => d.airname.toLowerCase().contains(_query))
                    .toList();
                if (djs.isEmpty) {
                  return const Center(child: Text('No DJs found'));
                }
                return ListView.separated(
                  itemCount: djs.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final dj = djs[i];
                    return ListTile(
                      title: Text(dj.airname),
                      subtitle: dj.lastSet == null
                          ? null
                          : Text('Last on ${setDate(dj.lastSet)}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => DjDetailScreen(dj: dj),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final e = error;
    final message = e is ApiException ? e.message : 'Something went wrong.\n$e';
    final detail = e is ApiException ? e.detail : null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (detail != null) ...[
              const SizedBox(height: 8),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
