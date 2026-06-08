import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../util.dart';
import 'dj_detail.dart';

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
  }

  void _reload() => setState(() => _future = _api.djs());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WUVT DJs')),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 12),
            Text('Could not reach the backend.\n$error',
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
