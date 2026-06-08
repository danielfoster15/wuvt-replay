import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';
import 'models.dart';

/// Thin client for the wuvt-replay backend.
class Api {
  Api({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _base = (baseUrl ?? backendUrl).replaceAll(RegExp(r'/$'), '');

  final http.Client _client;
  final String _base;

  Future<dynamic> _getJson(String path) async {
    final resp =
        await _client.get(Uri.parse('$_base$path')).timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      throw ApiException('GET $path failed (${resp.statusCode})');
    }
    return jsonDecode(resp.body);
  }

  Future<List<Dj>> djs() async {
    final data = await _getJson('/djs') as Map<String, dynamic>;
    return ((data['djs'] ?? []) as List)
        .map((e) => Dj.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<DjDetail> djDetail(int djId) async {
    final data = await _getJson('/djs/$djId') as Map<String, dynamic>;
    return DjDetail.fromJson(data);
  }

  Future<SetDetail> setDetail(int setId) async {
    final data = await _getJson('/sets/$setId') as Map<String, dynamic>;
    return SetDetail.fromJson(data);
  }
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}
